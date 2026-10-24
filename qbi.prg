// qbi.prg - Interpretador QBasic em AdvPL (Fases 1 e 1b: nucleo da linguagem)
//
// Uso:  QB_FILE=prog.bas advplc run qbi.prg
//       (sem QB_FILE: o nome do .bas e lido da 1a linha do stdin)
//
// Escopo (ver _reversa_sdd/qbasic-interp/fase0-escopo.md):
//   Fase 1:  PRINT (; , e zonas de 14), INPUT, LINE INPUT, LET/implicito,
//            IF (linha unica e bloco com ELSEIF/ELSE), FOR/NEXT STEP,
//            WHILE/WEND, DO/LOOP (WHILE/UNTIL pre e pos-teste), EXIT,
//            GOTO, GOSUB/RETURN, END, STOP, DIM (1D/2D, limites "lo TO hi"),
//            DATA/READ/RESTORE, CLS, LOCATE, RANDOMIZE, REM, '.
//   Fase 1b: SUB, FUNCTION (com STATIC), CALL, DECLARE, CONST, TYPE
//            (campos com ponto e arrays de registros), SELECT CASE
//            (valores, listas, faixas TO e IS), DIM SHARED, parametros
//            de array ("a() AS T"), sufixos de tipo % ! # &.
//   Funcoes: LEN MID$ LEFT$ RIGHT$ STR$ VAL INT FIX ABS SGN CHR$ ASC
//            UCASE$ LCASE$ SPACE$ STRING$ LTRIM$ RTRIM$ SQR RND TIMER INKEY$.
//
// Limitacoes conhecidas:
//   - DEFINT/DEFSNG/... sao ignorados: variaveis continuam em ponto flutuante.
//   - AND/OR/NOT operam em verdadeiro/falso (-1/0), nao bit a bit.
//   - Elemento de array passado como argumento (a(i)) e passado por valor.
//   - Notacao cientifica (1E5) nao e lida pelo lexer.
//   - Fora do escopo ainda: graficos, COLOR, SOUND/PLAY, PEEK/POKE, teclado.
//
// Estado compartilhado entre funcoes via Private declaradas em Main().
// Nota AdvPP: NAO use o identificador "aS" (ver fase0-escopo.md).

User Function Main()
    Local cFile := ""
    Local cSrc := ""
    Local nI := 0

    Private aTok := {}
    Private nTP := 1
    Private aStmt := {}
    Private aStmtLn := {}
    Private aStmtSrc := {}
    Private nPC := 1
    Private lJmp := .F.
    Private lStop := .F.
    Private lRet := .F.
    Private cErr := ""
    Private nErrLn := 0
    Private aVN := {}
    Private aVV := {}
    Private aVM := {}
    Private aFrm := {}
    Private aGos := {}
    Private aData := {}
    Private nDP := 1
    Private nCol := 0
    Private hIn := -1
    Private nSeed := 12345
    Private aDefName := {}
    Private aDefKind := {}
    Private aDefStart := {}
    Private aDefParams := {}
    Private aDefStat := {}
    Private aTypeName := {}
    Private aTypeFld := {}
    Private aTypeDef := {}
    Private aShr := {}
    Private aCall := {}
    Private nFrameSeq := 0
    Private aSel := {}
    Private aLblName := {}
    Private aLblIdx := {}
    Private nSeg := 0
    Private aMem := {}
    Private lTTY := .F.
    Private aScr := {}
    Private aAtt := {}
    Private nRow := 0
    Private nAttr := 7
    Private nFg := 7
    Private nBg := 0
    Private nEmitAtt := -1
    Private cSttySave := ""
    Private nMode := 0
    Private nGW := 0
    Private nGH := 0
    Private aPix := {}
    Private aPal := {}
    Private lDirty := .F.
    Private aLast := {}
    Private nGx := 0
    Private nGy := 0
    Private nEmitF := -1
    Private nEmitB := -1
    Private aFnName := {}
    Private aFnParams := {}
    Private aFnBody := {}
    Private nInkCount := 0
    Private aClip := {}
    Private aBrk := {}
    Private lBrkHit := .F.
    Private nBrkSkip := 0
    Private nTabW := 8
    Private lSel := .F.
    Private nSelR := 0
    Private nSelC := 0
    Private lClipLine := .F.
    Private aRet := {}
    Private aFileN := {}
    Private aFileH := {}
    Private aFileM := {}
    Private aFileT := {}
    Private aFileP := {}
    Private nPrFile := 0
    Private aTypeLen := {}
    Private aDefT := {}
    Private aCp := {}
    Private nRndX := 327680
    Private nTy := "S"
    Private cPend := ""
    Private aEd := {}
    Private nEdRow := 1
    Private nEdCol := 1
    Private nTopLine := 1
    Private cFileName := "UNTITLED.BAS"
    Private lEdDirty := .F.
    Private lMenuOpen := .F.
    Private lHelpOpen := .F.
    Private lHlpLoaded := .F.
    Private aHlp := {}
    Private aHlpView := {}
    Private cHlpTitle := ""
    Private nHlpTop := 1
    Private nMenu := 1
    Private nMenuItem := 1
    Private lImmFocus := .F.
    Private cImm := ""
    Private aImmOut := {}
    Private lIdeQuit := .F.
    Private lStepOn := .F.
    Private nDbgLine := 0
    Private cFind := ""
    Private lCapt := .F.
    Private cCapt := ""
    Private nErrLbl := 0
    Private nErrResume := 0
    Private nErrNum := 0

    QiScrInit()
    lTTY := QiIsTTY()
    If lTTY
        QiTermInit()
    EndIf

    For nI := 1 To 26
        AAdd( aDefT, "S" )
    Next
    aCp := QiCpTable()
    cFile := QiEnv( "QB_FILE" )
    If Empty( cFile ) .Or. QiEnv( "QB_IDE" ) == "1"
        // IDE: sem arquivo abre a tela vazia; QB_FILE abre o arquivo para editar
        QiIdeInit()
        If !Empty( cFile )
            IdeLoadFile( cFile )
        EndIf
        QiIdeLoop()
        QiTermRestore()
        QiDump()
        Return .T.
    EndIf
    cSrc := MemoRead( cFile )
    If Empty( cSrc )
        QiOut( "Arquivo nao encontrado: " + cFile + Chr(10) )
    Else
        If QiLoad( cSrc )
            QiRun()
        EndIf
        If !Empty( cErr )
            QiErrorBox( cErr )
        EndIf
    EndIf

    QiGfxFlush()
    If nMode != 0 .And. !Empty( QiEnv( "QB_PNG" ) )
        QiPngDump( QiEnv( "QB_PNG" ) )
    EndIf
    QiTermRestore()
    QiDump()
Return Empty( cErr )

// ---------------------------------------------------------------------------
// Ambiente e entrada
// ---------------------------------------------------------------------------

Static Function QiEnv( cVar )
    Local cV := GetEnv( cVar )
    If ValType( cV ) != "C" .Or. cV == "Nil"
        Return ""
    EndIf
Return cV

// Le uma linha da entrada. lEcho: ecoa na tela (terminal).
Static Function QiReadLine( lEcho )
    Local cLine := ""
    Local cCh := ""
    Local cK := ""
    If lCapt
        // dentro da IDE (passo/Immediate): a resposta vem do teclado
        While .T.
            cK := QiInkey()
            If cK == ""
                If !lTTY
                    Exit
                EndIf
                Loop
            EndIf
            If cK == Chr(13)
                Exit
            ElseIf cK == Chr(8) .Or. cK == Chr(127)
                If Len( cLine ) > 0
                    cLine := Left( cLine, Len( cLine ) - 1 )
                EndIf
            ElseIf Len( cK ) == 1 .And. Asc( cK ) >= 32
                cLine += cK
            EndIf
        EndDo
        Return cLine
    EndIf
    If hIn < 0
        hIn := FOpen( "/dev/stdin" )
    EndIf
    If hIn < 0
        Return ""
    EndIf
    QiTermMode( .T. )
    cCh := FReadStr( hIn, 1 )
    While !cCh == "" .And. cCh != Chr(10) .And. cCh != Chr(13)
        If cCh == Chr(127) .Or. cCh == Chr(8)
            If Len( cLine ) > 0
                cLine := Left( cLine, Len( cLine ) - 1 )
                If lEcho .And. lTTY .And. nCol > 0
                    nCol := nCol - 1
                    aScr[nRow*80+nCol+1] := " "
                    ConOutRaw( Chr(8) + " " + Chr(8) )
                EndIf
            EndIf
        Else
            cLine += cCh
            If lEcho
                QiPutStr( cCh )
            EndIf
        EndIf
        cCh := FReadStr( hIn, 1 )
    EndDo
    QiTermMode( .F. )
    QiNewLine()
Return cLine

Static Function QiErr( cMsg )
    If Empty( cErr )
        cErr := cMsg
    EndIf
Return .F.

// Saida de texto: passa pelo buffer de tela (cursor e atributos)
Static Function QiOut( cS )
    QiPutStr( cS )
Return

// ---------------------------------------------------------------------------
// Lexer: linha -> tokens {tipo, valor [, bruto]}
//   N numero, S string, W palavra (valor em maiusculas), O operador
// ---------------------------------------------------------------------------

Static Function QiLex( cL )
    Local aT := {}
    Local nI := 1
    Local nN := Len( cL )
    Local cC := ""
    Local cNx := ""
    Local cBuf := ""
    Local cRaw := ""
    Local lDone := .F.

    While nI <= nN .And. !lDone
        cC := SubStr( cL, nI, 1 )
        If cC == " " .Or. cC == Chr(9)
            nI := nI + 1
        ElseIf cC == "'"
            lDone := .T.
        ElseIf cC == Chr(34)
            cBuf := ""
            nI := nI + 1
            While nI <= nN .And. SubStr( cL, nI, 1 ) != Chr(34)
                cBuf += SubStr( cL, nI, 1 )
                nI := nI + 1
            EndDo
            nI := nI + 1
            AAdd( aT, { "S", cBuf } )
        ElseIf cC == "&" .And. nI < nN .And. At( Upper( SubStr( cL, nI + 1, 1 ) ), "HO" ) > 0
            // literal &H (hexadecimal) ou &O (octal)
            cNx := Upper( SubStr( cL, nI + 1, 1 ) )
            nI := nI + 2
            cBuf := ""
            If cNx == "H"
                While nI <= nN .And. At( Upper( SubStr( cL, nI, 1 ) ), "0123456789ABCDEF" ) > 0
                    cBuf += Upper( SubStr( cL, nI, 1 ) )
                    nI := nI + 1
                EndDo
                AAdd( aT, { "N", QiBaseVal( cBuf, 16 ) } )
            Else
                While nI <= nN .And. At( SubStr( cL, nI, 1 ), "01234567" ) > 0
                    cBuf += SubStr( cL, nI, 1 )
                    nI := nI + 1
                EndDo
                AAdd( aT, { "N", QiBaseVal( cBuf, 8 ) } )
            EndIf
        ElseIf At( cC, "0123456789" ) > 0 .Or. ( cC == "." .And. nI < nN .And. At( SubStr( cL, nI + 1, 1 ), "0123456789" ) > 0 )
            cBuf := ""
            While nI <= nN .And. At( SubStr( cL, nI, 1 ), "0123456789." ) > 0
                cBuf += SubStr( cL, nI, 1 )
                nI := nI + 1
            EndDo
            // expoente: 1E5, 2.5e-3, 1D2
            If nI < nN .And. At( Upper( SubStr( cL, nI, 1 ) ), "ED" ) > 0
                cNx := SubStr( cL, nI + 1, 1 )
                If At( cNx, "0123456789+-" ) > 0
                    cBuf += "E"
                    nI := nI + 1
                    If cNx == "+" .Or. cNx == "-"
                        cBuf += cNx
                        nI := nI + 1
                    EndIf
                    While nI <= nN .And. At( SubStr( cL, nI, 1 ), "0123456789" ) > 0
                        cBuf += SubStr( cL, nI, 1 )
                        nI := nI + 1
                    EndDo
                EndIf
            EndIf
            // sufixo de tipo (! # % &) nao altera o valor
            If nI <= nN .And. At( SubStr( cL, nI, 1 ), "!#%&" ) > 0
                nI := nI + 1
            EndIf
            // tipo do literal: expoente ou ponto (> 7 digitos = dupla); inteiros I/L
            cNx := ""
            If nI <= nN
                cNx := SubStr( cL, nI, 1 )
            EndIf
            AAdd( aT, { "N", Val( cBuf ), QiLitType( cBuf, cNx ) } )
            If cNx == "!" .Or. cNx == "#" .Or. cNx == "%" .Or. cNx == "&"
                nI := nI + 1
            EndIf
        ElseIf At( Upper( cC ), "ABCDEFGHIJKLMNOPQRSTUVWXYZ_" ) > 0
            cBuf := ""
            cRaw := ""
            While nI <= nN .And. At( Upper( SubStr( cL, nI, 1 ) ), "ABCDEFGHIJKLMNOPQRSTUVWXYZ_0123456789" ) > 0
                cBuf += Upper( SubStr( cL, nI, 1 ) )
                cRaw += SubStr( cL, nI, 1 )
                nI := nI + 1
            EndDo
            If nI <= nN
                If At( SubStr( cL, nI, 1 ), "$%!#&" ) > 0
                    cBuf += SubStr( cL, nI, 1 )
                    cRaw += SubStr( cL, nI, 1 )
                    nI := nI + 1
                EndIf
            EndIf
            If cBuf == "REM"
                lDone := .T.
            Else
                AAdd( aT, { "W", cBuf, cRaw } )
            EndIf
        ElseIf cC == "?"
            AAdd( aT, { "W", "PRINT", "PRINT" } )
            nI := nI + 1
        Else
            cNx := ""
            If nI < nN
                cNx := SubStr( cL, nI + 1, 1 )
            EndIf
            If ( cC == "<" .And. cNx == ">" ) .Or. ( cC == "<" .And. cNx == "=" ) .Or. ( cC == ">" .And. cNx == "=" )
                AAdd( aT, { "O", cC + cNx } )
                nI := nI + 2
            ElseIf At( cC, "=+-*/\^(),;:<>.#" ) > 0
                AAdd( aT, { "O", cC } )
                nI := nI + 1
            Else
                QiErr( "Caractere invalido: " + cC )
                lDone := .T.
            EndIf
        EndIf
    EndDo
Return aT

// Converte digitos de uma base (2..16) em numero
Static Function QiBaseVal( cD, nBase )
    Local nR := 0
    Local k := 0
    Local nV := 0
    For k := 1 To Len( cD )
        nV := At( SubStr( cD, k, 1 ), "0123456789ABCDEF" ) - 1
        nR := nR * nBase + nV
    Next
Return nR

Static Function QiSplit( cS, cSep )
    Local aR := {}
    Local cR := cS
    Local nP := At( cSep, cR )
    While nP > 0
        AAdd( aR, SubStr( cR, 1, nP - 1 ) )
        cR := SubStr( cR, nP + 1 )
        nP := At( cSep, cR )
    EndDo
    AAdd( aR, cR )
Return aR

// Tipo de um literal: I (inteiro), L (longo), S (simples) ou D (dupla)
Static Function QiLitType( cBuf, cSuf )
    Local cT := ""
    Local nDig := 0
    Local v := Val( cBuf )
    Local k := 0
    Local cC := ""
    If cSuf == "!"
        Return "S"
    ElseIf cSuf == "#"
        Return "D"
    ElseIf cSuf == "%"
        Return "I"
    ElseIf cSuf == "&"
        Return "L"
    EndIf
    If At( "E", cBuf ) > 0
        Return "S"
    EndIf
    If At( ".", cBuf ) > 0
        For k := 1 To Len( cBuf )
            cC := SubStr( cBuf, k, 1 )
            If cC != "." .And. ( nDig > 0 .Or. cC != "0" )
                nDig := nDig + 1
            EndIf
        Next
        If nDig > 7
            Return "D"
        EndIf
        Return "S"
    EndIf
    If v <= 32767
        Return "I"
    EndIf
    If v <= 2147483647
        Return "L"
    EndIf
Return "D"

// Tabela CP437 (codigo DOS -> ponto Unicode), gerada de cp437.prg
Static Function QiCpTable()
    Return { ;
    32, 9786, 9787, 9829, 9830, 9827, 9824, 8226, 9688, 9675, 9689, 9794, 9792, 9834, 9835, 9788, ;
    9658, 9668, 8597, 8252, 182, 167, 9644, 8616, 8593, 8595, 8594, 8592, 8735, 8596, 9650, 9660, ;
    32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, ;
    48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, ;
    64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, ;
    80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95, ;
    96, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, ;
    112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122, 123, 124, 125, 126, 8962, ;
    199, 252, 233, 226, 228, 224, 229, 231, 234, 235, 232, 239, 238, 236, 196, 197, ;
    201, 230, 198, 244, 246, 242, 251, 249, 255, 214, 220, 162, 163, 165, 8359, 402, ;
    225, 237, 243, 250, 241, 209, 170, 186, 191, 8976, 172, 189, 188, 161, 171, 187, ;
    9617, 9618, 9619, 9474, 9508, 9569, 9570, 9558, 9557, 9571, 9553, 9559, 9565, 9564, 9563, 9488, ;
    9492, 9524, 9516, 9500, 9472, 9532, 9566, 9567, 9562, 9556, 9577, 9574, 9568, 9552, 9580, 9575, ;
    9576, 9572, 9573, 9561, 9560, 9554, 9555, 9579, 9578, 9496, 9484, 9608, 9604, 9612, 9616, 9600, ;
    945, 223, 915, 960, 931, 963, 181, 964, 934, 920, 937, 948, 8734, 966, 949, 8745, ;
    8801, 177, 8805, 8804, 8992, 8993, 247, 8776, 176, 8729, 183, 8730, 8319, 178, 9632, 160 }

// Caractere (UTF-8) do codigo CP437 n (0..255)
Static Function QiChrG( n )
    Local k := Int( n )
    If k < 0 .Or. k > 255
        k := Mod( k, 256 )
    EndIf
    If k < 32
        Return Chr( k )
    EndIf
Return Chr( aCp[k+1] )

// Codigo CP437 do caractere s (primeiro caractere UTF-8)
Static Function QiAscG( s )
    Local cp := QiCodePoint( s )
    Local nP := AScan( aCp, cp )
    If nP == 0
        Return Asc( s )
    EndIf
Return nP - 1

// Ponto Unicode do primeiro caractere UTF-8 de s
Static Function QiCodePoint( s )
    Local b1 := Asc( SubStr( s, 1, 1 ) )
    Local b2 := 0
    Local b3 := 0
    Local b4 := 0
    If b1 < 128
        Return b1
    EndIf
    b2 := Asc( SubStr( s, 2, 1 ) ) - 128
    If b1 < 224
        Return ( b1 - 192 ) * 64 + b2
    EndIf
    b3 := Asc( SubStr( s, 3, 1 ) ) - 128
    If b1 < 240
        Return ( b1 - 224 ) * 4096 + b2 * 64 + b3
    EndIf
    b4 := Asc( SubStr( s, 4, 1 ) ) - 128
Return ( b1 - 240 ) * 262144 + b2 * 4096 + b3 * 64 + b4

// Quebra uma string UTF-8 em caracteres (um elemento por caractere)
Static Function QiSplitU( s )
    Local aR := {}
    Local k := 1
    Local b := 0
    Local nL := 1
    While k <= Len( s )
        b := Asc( SubStr( s, k, 1 ) )
        nL := 1
        If b >= 240
            nL := 4
        ElseIf b >= 224
            nL := 3
        ElseIf b >= 192
            nL := 2
        EndIf
        AAdd( aR, SubStr( s, k, nL ) )
        k := k + nL
    EndDo
Return aR

// Caracteres de nIni a nFim (1-based) de uma string UTF-8
Static Function QiSubU( s, nIni, nCnt )
    Local aC := QiSplitU( s )
    Local cR := ""
    Local k := 0
    For k := Max( 1, nIni ) To Min( Len( aC ), nIni + nCnt - 1 )
        cR += aC[k]
    Next
Return cR

// Numero de caracteres de uma string UTF-8 (bytes de continuacao nao contam)
Static Function QiLenU( s )
    Local k := 0
    Local n := 0
    Local b := 0
    For k := 1 To Len( s )
        b := Asc( SubStr( s, k, 1 ) )
        If b < 128 .Or. b >= 192
            n := n + 1
        EndIf
    Next
Return n

// Divide tokens em comandos separados por ':'
Static Function QiSplitStmts( aT )
    Local aR := {}
    Local aCur := {}
    Local nK := 0
    For nK := 1 To Len( aT )
        If aT[nK][1] == "O" .And. aT[nK][2] == ":"
            If Len( aCur ) > 0
                AAdd( aR, aCur )
            EndIf
            aCur := {}
        Else
            AAdd( aCur, aT[nK] )
        EndIf
    Next
    If Len( aCur ) > 0
        AAdd( aR, aCur )
    EndIf
Return aR

Static Function QiWord( aSt, nK )
    Local cR := ""
    If nK <= Len( aSt )
        If aSt[nK][1] == "W"
            cR := aSt[nK][2]
        EndIf
    EndIf
Return cR

// Verdadeiro se o token na posicao nK e o operador cOp
Static Function QiOpAt( aSt, nK, cOp )
    Local lR := .F.
    If nK <= Len( aSt )
        If aSt[nK][1] == "O"
            lR := aSt[nK][2] == cOp
        EndIf
    EndIf
Return lR

Static Function QiIsBlockIf( aSt )
    Local lR := .F.
    Local nL := Len( aSt )
    If nL > 0
        If aSt[nL][1] == "W" .And. aSt[nL][2] == "THEN"
            lR := .T.
        EndIf
    EndIf
Return lR

// ---------------------------------------------------------------------------
// Carga: linhas -> comandos, depois registro de SUB/FUNCTION/TYPE/SHARED
// ---------------------------------------------------------------------------

Static Function QiLoad( cSrc )
    Local aLines := QiSplit( StrTran( cSrc, Chr(13), "" ), Chr(10) )
    Local nI := 0
    Local nK := 0
    Local aT := {}
    Local aPart := {}
    Local nLbl := 0

    For nI := 1 To Len( aLines )
        aT := QiLex( aLines[nI] )
        If !Empty( cErr )
            nErrLn := nI
            Return .F.
        EndIf
        nLbl := 0
        If Len( aT ) > 0
            If aT[1][1] == "N"
                nLbl := aT[1][2]
                aT := QiTail( aT, 2 )
            EndIf
        EndIf
        If Len( aT ) == 0
            Loop
        EndIf
        If QiWord( aT, 1 ) == "IF"
            aPart := { aT }
        Else
            aPart := QiSplitStmts( aT )
        EndIf
        For nK := 1 To Len( aPart )
            QiAddStmt( aPart[nK], nLbl, nI )
            nLbl := 0
        Next
    Next
    If Empty( cErr )
        QiRegister()
    EndIf
Return Empty( cErr )

Static Function QiTail( aT, nFrom )
    Local aR := {}
    Local nK := 0
    For nK := nFrom To Len( aT )
        AAdd( aR, aT[nK] )
    Next
Return aR

Static Function QiAddStmt( aSt, nLbl, nSrc )
    AAdd( aStmt, aSt )
    AAdd( aStmtLn, nLbl )
    AAdd( aStmtSrc, nSrc )
    If QiWord( aSt, 1 ) == "DATA"
        QiCollectData( aSt )
    EndIf
Return

Static Function QiCollectData( aSt )
    Local nK := 2
    Local lNeg := .F.
    While nK <= Len( aSt )
        If aSt[nK][1] == "O" .And. aSt[nK][2] == "-"
            lNeg := .T.
        ElseIf aSt[nK][1] == "N"
            If lNeg
                AAdd( aData, -aSt[nK][2] )
            Else
                AAdd( aData, aSt[nK][2] )
            EndIf
            lNeg := .F.
        ElseIf aSt[nK][1] == "S"
            AAdd( aData, aSt[nK][2] )
        ElseIf aSt[nK][1] == "W"
            AAdd( aData, aSt[nK][3] )
        EndIf
        nK := nK + 1
    EndDo
Return

// Registra definicoes de SUB/FUNCTION, TYPE, nomes compartilhados e CONST
Static Function QiRegister()
    Local j := 0
    Local nJ := 0
    Local cF := ""
    Local aSt := {}
    Local aFlds := {}
    Local aDfl := {}
    Local cFT := ""
    Local aLen := {}
    Local nLn := 0

    For j := 1 To Len( aStmt )
        aSt := aStmt[j]
        cF := QiWord( aSt, 1 )
        If cF == "SUB" .Or. cF == "FUNCTION"
            AAdd( aDefName, QiWord( aSt, 2 ) )
            If cF == "SUB"
                AAdd( aDefKind, "S" )
            Else
                AAdd( aDefKind, "F" )
            EndIf
            AAdd( aDefStart, j )
            AAdd( aDefParams, QiParseParams( aSt ) )
            AAdd( aDefStat, QiHasWord( aSt, "STATIC" ) )
        ElseIf cF == "TYPE"
            aFlds := {}
            aDfl := {}
            aLen := {}
            nJ := j + 1
            While nJ <= Len( aStmt ) .And. !( QiWord( aStmt[nJ], 1 ) == "END" .And. QiWord( aStmt[nJ], 2 ) == "TYPE" )
                cFT := QiWord( aStmt[nJ], 3 )
                AAdd( aFlds, QiWord( aStmt[nJ], 1 ) )
                If QiReserved( QiWord( aStmt[nJ], 1 ) )
                    nErrLn := aStmtSrc[nJ]
                    QiErr( "Syntax error" )
                EndIf
                If cFT == "STRING"
                    // STRING * n: tamanho fixo (preenchido com espacos)
                    nLn := 0
                    If QiOpAt( aStmt[nJ], 4, "*" ) .And. ValType( aStmt[nJ][5][2] ) == "N"
                        nLn := aStmt[nJ][5][2]
                    Else
                        nErrLn := aStmtSrc[nJ]
                        QiErr( "Expected: *" )
                    EndIf
                    AAdd( aLen, nLn )
                    If nLn > 0
                        AAdd( aDfl, Space( nLn ) )
                    Else
                        AAdd( aDfl, "" )
                    EndIf
                Else
                    AAdd( aLen, 0 )
                    AAdd( aDfl, 0 )
                EndIf
                nJ := nJ + 1
            EndDo
            AAdd( aTypeName, QiWord( aSt, 2 ) )
            AAdd( aTypeFld, aFlds )
            AAdd( aTypeDef, aDfl )
            AAdd( aTypeLen, aLen )
        ElseIf cF == "DEF" .And. Left( QiWord( aSt, 2 ), 2 ) == "FN"
            QiRegDefFn( aSt )
        ElseIf Left( cF, 3 ) == "DEF" .And. Len( cF ) == 6 .And. cF != "DEFFN"
            QiRegDefType( aSt, cF )
        ElseIf Len( aSt ) == 1 .And. aSt[1][1] == "W" .And. AScan( aDefName, aSt[1][2] ) == 0
            // rotulo textual "NOME:" (linha propria; SUB sem argumentos fica de fora)
            AAdd( aLblName, aSt[1][2] )
            AAdd( aLblIdx, j )
        ElseIf cF == "DIM" .And. QiWord( aSt, 2 ) == "SHARED"
            QiAddShared( aSt, 3 )
        ElseIf cF == "SHARED"
            QiAddShared( aSt, 2 )
        ElseIf cF == "CONST"
            QiAddShared( aSt, 2 )
        EndIf
    Next
Return

// Nomes logo apos SHARED / CONST: W no inicio ou apos ','
Static Function QiAddShared( aSt, nFrom )
    Local k := 0
    Local lOk := .F.
    For k := nFrom To Len( aSt )
        If aSt[k][1] == "W"
            lOk := .F.
            If k == nFrom
                lOk := .T.
            ElseIf QiOpAt( aSt, k - 1, "," )
                lOk := .T.
            EndIf
            If lOk
                If AScan( aShr, aSt[k][2] ) == 0
                    AAdd( aShr, aSt[k][2] )
                EndIf
            EndIf
        EndIf
    Next
Return

// DEFINT/DEFLNG/DEFSNG/DEFDBL/DEFSTR letra[-letra][, ...]: tipo por inicial
Static Function QiRegDefType( aSt, cF )
    Local cT := ""
    Local k := 1
    Local nA := 0
    Local nB := 0
    If cF == "DEFINT"
        cT := "I"
    ElseIf cF == "DEFLNG"
        cT := "L"
    ElseIf cF == "DEFSNG"
        cT := "S"
    ElseIf cF == "DEFDBL"
        cT := "D"
    Else
        Return
    EndIf
    While k <= Len( aSt )
        If aSt[k][1] == "W" .And. Len( aSt[k][2] ) == 1
            nA := Asc( aSt[k][2] ) - 64
            nB := nA
            If QiOpAt( aSt, k + 1, "-" ) .And. k + 2 <= Len( aSt )
                If aSt[k+2][1] == "W" .And. Len( aSt[k+2][2] ) == 1
                    nB := Asc( aSt[k+2][2] ) - 64
                    k := k + 2
                EndIf
            EndIf
            For nA := nA To nB
                If nA >= 1 .And. nA <= 26
                    aDefT[nA] := cT
                EndIf
            Next
            nA := 0
        EndIf
        k := k + 1
    EndDo
Return

// Tipo de uma variavel pelo sufixo do nome, ou pela inicial (DEFxxx)
Static Function QiTypeOf( cNm )
    Local cL := Right( cNm, 1 )
    Local nI := 0
    If cL == "$"
        Return "$"
    ElseIf cL == "%"
        Return "I"
    ElseIf cL == "&"
        Return "L"
    ElseIf cL == "!"
        Return "S"
    ElseIf cL == "#"
        Return "D"
    EndIf
    nI := Asc( Left( cNm, 1 ) ) - 64
    If nI >= 1 .And. nI <= 26 .And. Len( aDefT ) == 26
        Return aDefT[nI]
    EndIf
Return "S"

// Rank de tipo numerico: I=1, L=2, S=3, D=4
Static Function QiRank( cT )
    If cT == "I"
        Return 1
    ElseIf cT == "L"
        Return 2
    ElseIf cT == "S"
        Return 3
    EndIf
Return 4

// Tipo do resultado de uma operacao binaria
Static Function QiCmbT( tA, tB, cOp )
    Local r := Max( QiRank( tA ), QiRank( tB ) )
    If cOp == "/" .Or. cOp == "^"
        r := Max( r, 3 )
    ElseIf cOp == "\" .Or. cOp == "MOD"
        If r >= 2
            Return "L"
        EndIf
        Return "I"
    EndIf
    If r == 1
        Return "I"
    ElseIf r == 2
        Return "L"
    ElseIf r == 3
        Return "S"
    EndIf
Return "D"

// Arredonda para precisao simples (mantissa de 24 bits, meio-para-par), como o SINGLE do QBASIC
Static Function QiF32( v )
    Local a := Abs( v )
    Local e := 0
    Local sc := 0
    Local m := 0
    If a == 0 .Or. ValType( v ) != "N"
        Return v
    EndIf
    e := Int( Log( a ) / Log( 2 ) )
    If a < QiP2( e )
        e := e - 1
    EndIf
    If a >= QiP2( e + 1 )
        e := e + 1
    EndIf
    sc := QiP2( 23 - e )
    m := QiRoundEven( a * sc )
    If v < 0
        Return -( m / sc )
    EndIf
Return m / sc

// Potencia de 2 com expoente inteiro (exata)
Static Function QiP2( k )
    Local r := 1
    Local i := 0
    If k >= 0
        For i := 1 To k
            r := r * 2
        Next
    Else
        For i := 1 To -k
            r := r / 2
        Next
    EndIf
Return r

// Precisao do valor conforme o tipo: S arredonda para 7 digitos, D para 16
Static Function QiFin( v, cT )
    If ValType( v ) != "N"
        Return v
    EndIf
    If cT == "I" .And. ( v < -32768 .Or. v > 32767 )
        QiErr( "Overflow" )
    ElseIf cT == "L" .And. ( v < -2147483648 .Or. v > 2147483647 )
        QiErr( "Overflow" )
    EndIf
    If cT == "S"
        Return QiF32( v )
    EndIf
Return v

// Conversao na atribuicao para o tipo da variavel
Static Function QiConvT( cT, v )
    Local r := 0
    If ValType( v ) != "N" .Or. cT == "$"
        Return v
    EndIf
    If cT == "I"
        r := QiRoundEven( v )
        If r < -32768 .Or. r > 32767
            QiErr( "Overflow" )
        EndIf
        Return r
    ElseIf cT == "L"
        r := QiRoundEven( v )
        If r < -2147483648 .Or. r > 2147483647
            QiErr( "Overflow" )
        EndIf
        Return r
    ElseIf cT == "S"
        Return QiF32( v )
    EndIf
Return v

// Potencia de 10 com expoente inteiro
Static Function QiP10( k )
    Local r := 1
    Local i := 0
    If k >= 0
        For i := 1 To k
            r := r * 10
        Next
    Else
        For i := 1 To -k
            r := r / 10
        Next
    EndIf
Return r

// Arredonda para nSig algarismos significativos
Static Function QiSig( v, nSig )
    Local a := Abs( v )
    Local e := 0
    Local sc := 0
    Local m := 0
    If a == 0
        Return 0
    EndIf
    e := Int( Log( a ) / Log( 10 ) )
    If a < QiP10( e )
        e := e - 1
    EndIf
    If a >= QiP10( e + 1 )
        e := e + 1
    EndIf
    sc := QiP10( nSig - 1 - e )
    m := Int( a * sc + 0.5 )
    If v < 0
        Return -( m / sc )
    EndIf
Return m / sc

// Texto de um numero no formato do PRINT/STR$ do QBASIC
Static Function QiFmtNum( v, cT )
    Local nSig := 7
    Local a := Abs( v )
    Local e := 0
    Local sc := 0
    Local m := 0
    Local cD := ""
    Local nd := 0
    Local nFix := 0
    Local ip := ""
    Local fp := ""
    Local txt := ""
    Local cE := ""
    If cT == "I" .Or. cT == "L"
        Return AllTrim( Str( v ) )
    EndIf
    If cT == "D"
        nSig := 16
    EndIf
    If a == 0
        Return "0"
    EndIf
    e := Int( Log( a ) / Log( 10 ) )
    If a < QiP10( e )
        e := e - 1
    EndIf
    If a >= QiP10( e + 1 )
        e := e + 1
    EndIf
    sc := QiP10( nSig - 1 - e )
    m := Int( a * sc + 0.5 )
    If m >= QiP10( nSig )
        m := Int( m / 10 )
        e := e + 1
    EndIf
    cD := AllTrim( Str( m ) )
    While Len( cD ) > 1 .And. Right( cD, 1 ) == "0"
        cD := Left( cD, Len( cD ) - 1 )
    EndDo
    nd := Len( cD )
    If e >= 0
        nFix := Max( e + 1, nd )
    Else
        nFix := ( -e - 1 ) + nd
    EndIf
    If nFix <= nSig
        If e >= 0
            If nd >= e + 1
                ip := Left( cD, e + 1 )
                fp := SubStr( cD, e + 2 )
            Else
                ip := cD + Replicate( "0", e + 1 - nd )
                fp := ""
            EndIf
            txt := ip
            If Len( fp ) > 0
                txt += "." + fp
            EndIf
        Else
            txt := "." + Replicate( "0", -e - 1 ) + cD
        EndIf
    Else
        cE := AllTrim( Str( Abs( e ) ) )
        If Len( cE ) < 2
            cE := "0" + cE
        EndIf
        txt := Left( cD, 1 )
        If nd > 1
            txt += "." + SubStr( cD, 2 )
        EndIf
        txt += "E" + If( e < 0, "-", "+" ) + cE
    EndIf
    If v < 0
        txt := "-" + txt
    EndIf
Return txt

// DEFSNG etc. de letras isoladas: tabela de tipos e gravacao na atribuicao
// (QiConvT e QiFmtNum acima)

// DEF FNnome(params) = expressao
Static Function QiRegDefFn( aSt )
    Local k := 0
    Local aPar := {}
    Local aBody := {}
    Local nEq := 0
    For k := 3 To Len( aSt )
        If QiOpAt( aSt, k, "=" )
            nEq := k
            Exit
        EndIf
    Next
    If nEq == 0
        Return
    EndIf
    For k := 4 To nEq - 1
        If aSt[k][1] == "W" .And. ( QiOpAt( aSt, k - 1, "(" ) .Or. QiOpAt( aSt, k - 1, "," ) )
            AAdd( aPar, aSt[k][2] )
        EndIf
    Next
    For k := nEq + 1 To Len( aSt )
        AAdd( aBody, aSt[k] )
    Next
    AAdd( aFnName, QiWord( aSt, 2 ) )
    AAdd( aFnParams, aPar )
    AAdd( aFnBody, aBody )
Return

// Chamada de DEF FN: quadro local com os parametros; avalia a expressao
Static Function QiCallDefFn( cNm, aA )
    Local nF := AScan( aFnName, cNm )
    Local aPar := {}
    Local aSvT := aTok
    Local nSvP := nTP
    Local id := ""
    Local k := 0
    Local vRet := 0
    If nF == 0
        QiErr( "Undefined user function" )
        Return 0
    EndIf
    aPar := aFnParams[nF]
    nFrameSeq := nFrameSeq + 1
    id := "D" + LTrim( Str( nFrameSeq ) )
    For k := 1 To Len( aPar )
        If k <= Len( aA )
            QiAddVar( QiKeyId( id, aPar[k] ), aA[k], { "", 0, 0 } )
        Else
            QiAddVar( QiKeyId( id, aPar[k] ), QiDefault( aPar[k] ), { "", 0, 0 } )
        EndIf
    Next
    AAdd( aCall, { id, cNm, .T. } )
    aTok := aFnBody[nF]
    nTP := 1
    vRet := QiExpr()
    QiPopCall()
    aTok := aSvT
    nTP := nSvP
Return vRet

Static Function QiHasWord( aSt, cW )
    Local lR := .F.
    Local k := 0
    For k := 1 To Len( aSt )
        If QiWord( aSt, k ) == cW
            lR := .T.
        EndIf
    Next
Return lR

// Parametros de SUB/FUNCTION: {nome, eh_array}
// Palavras reservadas do BASIC: nao podem ser nomes de campo ou variavel
Static Function QiReserved( cNm )
    Local aR := { "PRINT", "INPUT", "LET", "IF", "THEN", "ELSE", "ELSEIF", "END", "FOR", "TO", "STEP", ;
                  "NEXT", "WHILE", "WEND", "DO", "LOOP", "UNTIL", "GOTO", "GOSUB", "RETURN", "REM", ;
                  "DIM", "CLS", "DATA", "READ", "RESTORE", "STOP", "AND", "OR", "NOT", "MOD", ;
                  "SELECT", "CASE", "SUB", "FUNCTION", "CALL", "CONST", "DECLARE", "SHARED", "TYPE", ;
                  "DEF", "SEG", "LOCATE", "COLOR", "SCREEN", "PSET", "LINE", "CIRCLE", "PAINT", ;
                  "GET", "PUT", "PLAY", "SOUND", "BEEP", "TIMER", "SLEEP", "RANDOMIZE", "SWAP", ;
                  "ON", "ERROR", "RESUME", "OPEN", "CLOSE", "USING", "WIDTH", "VIEW", "WINDOW", ;
                  "PALETTE", "POKE", "PEEK", "OUT", "INP", "KILL", "NAME", "FIELD", "EXIT", "AS" }
Return AScan( aR, Upper( cNm ) ) > 0

Static Function QiParseParams( aSt )
    Local aR := {}
    Local k := 0
    Local nL := Len( aSt )
    Local lIn := .F.
    Local cNm := ""
    Local lArr := .F.
    For k := 3 To nL
        If !lIn
            If QiOpAt( aSt, k, "(" )
                lIn := .T.
            EndIf
        Else
            If QiOpAt( aSt, k, ")" ) .And. !QiOpAt( aSt, k - 1, "(" )
                Exit
            ElseIf aSt[k][1] == "W" .And. aSt[k][2] != "AS"
                If QiOpAt( aSt, k - 1, "(" ) .Or. QiOpAt( aSt, k - 1, "," )
                    cNm := aSt[k][2]
                    lArr := QiOpAt( aSt, k + 1, "(" )
                    AAdd( aR, { cNm, lArr } )
                EndIf
            EndIf
        EndIf
    Next
Return aR

// ---------------------------------------------------------------------------
// Execucao
// ---------------------------------------------------------------------------

Static Function QiRun()
    Local nCur := 0
    lStop := .F.
    nPC := 1
    While nPC <= Len( aStmt ) .And. !lStop .And. Empty( cErr )
        nCur := nPC
        nPC := nPC + 1
        lJmp := .F.
        QiExec( aStmt[nCur], nCur )
        If !Empty( cErr )
            If !QiTrap( nCur ) .And. nErrLn == 0
                nErrLn := aStmtSrc[nCur]
            EndIf
        EndIf
    EndDo
Return Empty( cErr )

// ON ERROR: desvia para o rotulo registrado. Retorna .T. se tratou o erro.
Static Function QiTrap( nCur )
    Local lR := .F.
    If nErrLbl > 0 .And. !Empty( cErr )
        nErrNum := QiErrCode( cErr )
        nErrResume := nCur
        cErr := ""
        nPC := nErrLbl
        lJmp := .T.
        lR := .T.
    EndIf
Return lR

// Codigo numerico do erro, como em ERR do QBasic
Static Function QiErrCode( cMsg )
    Local nC := 2
    If cMsg == "Illegal function call"
        nC := 5
    ElseIf cMsg == "Subscript out of range"
        nC := 9
    ElseIf cMsg == "Type mismatch"
        nC := 13
    ElseIf cMsg == "Division by zero"
        nC := 11
    ElseIf cMsg == "Undefined line number" .Or. cMsg == "Label not defined"
        nC := 8
    ElseIf cMsg == "NEXT sem FOR"
        nC := 1
    ElseIf cMsg == "Overflow"
        nC := 6
    EndIf
Return nC

Static Function QiExec( aSt, nCur )
    Local cW := QiWord( aSt, 1 )
    Local cW2 := QiWord( aSt, 2 )

    If Len( aSt ) == 0
        Return
    EndIf

    If cW == "PRINT"
        QiPrint( aSt )
    ElseIf cW == "INPUT"
        QiInput( aSt )
    ElseIf cW == "LINE" .And. cW2 == "INPUT"
        QiLineInput( aSt )
    ElseIf cW == "LET"
        QiAssign( aSt, 2 )
    ElseIf cW == "IF"
        QiIf( aSt, nCur )
    ElseIf cW == "ELSE" .Or. cW == "ELSEIF"
        QiJumpEndIf( nCur )
    ElseIf cW == "END"
        If cW2 == "SUB" .And. Len( aRet ) > 0
            QiFlatRet()
        ElseIf cW2 == "SUB" .Or. cW2 == "FUNCTION"
            lRet := .T.
        ElseIf cW2 == "SELECT"
            QiPopSel()
        ElseIf cW2 == "IF" .Or. cW2 == "TYPE"
            // fim de bloco: nada a fazer no fluxo normal
        Else
            lStop := .T.
        EndIf
    ElseIf cW == "STOP"
        lStop := .T.
    ElseIf cW == "SUB" .Or. cW == "FUNCTION" .Or. cW == "TYPE"
        QiSkipTo( nCur, cW )
    ElseIf cW == "DECLARE" .Or. cW == "DEFINT" .Or. cW == "DEFSNG" .Or. cW == "DEFDBL" .Or. cW == "DEFSTR" .Or. cW == "OPTION" .Or. cW == "DATA" .Or. cW == "COMMON"
        // sem efeito em tempo de execucao
    ElseIf cW == "CONST"
        QiConst( aSt )
    ElseIf cW == "CALL"
        QiCallStmt( aSt, 2 )
    ElseIf cW == "SELECT"
        QiSelect( aSt, nCur )
    ElseIf cW == "CASE"
        QiCaseJump( nCur )
    ElseIf cW == "FOR"
        QiFor( aSt, nCur )
    ElseIf cW == "NEXT"
        QiNext()
    ElseIf cW == "WHILE"
        QiWhile( aSt, nCur )
    ElseIf cW == "WEND"
        QiWend()
    ElseIf cW == "DO"
        QiDo( aSt, nCur )
    ElseIf cW == "LOOP"
        QiLoop( aSt )
    ElseIf cW == "EXIT"
        QiExit( aSt )
    ElseIf cW == "GOTO"
        QiGotoStmt( aSt )
    ElseIf cW == "GOSUB"
        AAdd( aGos, nPC )
        QiGotoStmt( aSt )
    ElseIf cW == "RETURN"
        QiReturn()
    ElseIf cW == "DIM" .Or. cW == "REDIM"
        QiDim( aSt )
    ElseIf cW == "READ"
        QiRead( aSt )
    ElseIf cW == "RESTORE"
        nDP := 1
    ElseIf cW == "CLS"
        QiCls()
    ElseIf cW == "LOCATE"
        QiLocate( aSt )
    ElseIf cW == "COLOR"
        QiColor( aSt )
    ElseIf cW == "SCREEN"
        QiScreen( aSt )
    ElseIf cW == "WIDTH"
        // largura fixa de 80 colunas nesta fase
    ElseIf cW == "SWAP"
        QiSwap( aSt )
    ElseIf cW == "MID$" .And. QiOpAt( aSt, 2, "(" )
        QiMidAssign( aSt )
    ElseIf cW == "OPEN"
        QiOpenFile( aSt )
    ElseIf cW == "CLOSE"
        QiCloseFile( aSt )
    ElseIf cW == "ON" .And. cW2 == "ERROR"
        QiOnError( aSt )
    ElseIf cW == "RESUME"
        QiResume( aSt )
    ElseIf cW == "DEF" .And. cW2 == "SEG"
        QiDefSeg( aSt )
    ElseIf cW == "DEF"
        // DEF FN: registrado na carga; nada a fazer no fluxo
    ElseIf cW == "POKE"
        QiPoke( aSt )
    ElseIf cW == "LINE"
        QiLineStmt( aSt )
    ElseIf cW == "PSET"
        QiPsetStmt( aSt, .F. )
    ElseIf cW == "PRESET"
        QiPsetStmt( aSt, .T. )
    ElseIf cW == "CIRCLE"
        QiCircleStmt( aSt )
    ElseIf cW == "PAINT"
        QiPaintStmt( aSt )
    ElseIf cW == "GET"
        QiGetStmt( aSt )
    ElseIf cW == "PUT"
        QiPutStmt( aSt )
    ElseIf cW == "PALETTE"
        QiPaletteStmt( aSt )
    ElseIf cW == "VIEW" .Or. cW == "WAIT"
        // janela de visao e porta de hardware: sem efeito nesta fase
    ElseIf cW == "SLEEP"
        QiSleepStmt( aSt )
    ElseIf cW == "BEEP"
        // BEEP medido no QBASIC original: ~904 Hz por ~320 ms
        QiPlaySeg( { { 904, 2560 } } )
    ElseIf cW == "SOUND"
        QiSoundStmt( aSt )
    ElseIf cW == "PLAY"
        QiPlayStmt( aSt )
    ElseIf cW == "RANDOMIZE"
        // semente fixa nesta fase
    ElseIf Len( aSt ) == 1 .And. AScan( aLblName, cW ) > 0 .And. AScan( aDefName, cW ) == 0
        // rotulo textual: nao faz nada ao ser alcancado
    ElseIf AScan( aDefName, cW ) > 0 .And. !QiOpAt( aSt, 2, "=" )
        QiCallStmt( aSt, 1 )
    ElseIf QiOpAt( aSt, 2, "=" ) .Or. QiOpAt( aSt, 2, "(" )
        QiAssign( aSt, 1 )
    Else
        QiErr( "Statement not implemented: " + cW )
    EndIf
Return

// Memoria virtual de 64 KB (PEEK/POKE). Leituras nao escritas valem 0.
Static Function QiMemInit()
    Local k := 0
    If Len( aMem ) == 0
        aMem := Array( 65536 )
        For k := 1 To 65536
            aMem[k] := 0
        Next
    EndIf
Return

// DEF SEG [= expr]
Static Function QiDefSeg( aSt )
    aTok := aSt
    nTP := 3
    If QiTokIs( "O", "=" )
        nTP := nTP + 1
        nSeg := QiIdx( QiExpr() )
    Else
        nSeg := 0
    EndIf
Return

Static Function QiPoke( aSt )
    Local vA := 0
    Local vV := 0
    aTok := aSt
    nTP := 2
    vA := QiExpr()
    If !QiTokIs( "O", "," )
        QiErr( "Syntax error" )
        Return
    EndIf
    nTP := nTP + 1
    vV := QiExpr()
    If !Empty( cErr )
        Return
    EndIf
    QiMemWrite( QiLin( vA ), Mod( Int( vV ), 256 ) )
Return

// Endereco linear = segmento * 16 + deslocamento
Static Function QiLin( vA )
Return nSeg * 16 + QiIdx( vA )

// ON ERROR GOTO rotulo | ON ERROR GOTO 0
Static Function QiOnError( aSt )
    Local nL := 0
    If !QiWordAtIs( aSt, 3, "GOTO" )
        QiErr( "Syntax error" )
        Return
    EndIf
    If Len( aSt ) < 4
        QiErr( "Syntax error" )
        Return
    EndIf
    If aSt[4][1] == "N"
        nErrLbl := 0
    ElseIf aSt[4][1] == "W"
        nL := AScan( aLblName, aSt[4][2] )
        If nL == 0
            QiErr( "Label not defined" )
            Return
        EndIf
        nErrLbl := aLblIdx[nL]
    Else
        QiErr( "Syntax error" )
    EndIf
Return

Static Function QiWordAtIs( aSt, nK, cW )
Return QiWord( aSt, nK ) == cW

// RESUME [NEXT | rotulo]: retoma apos o comando que falhou
Static Function QiResume( aSt )
    Local nL := 0
    nErrNum := 0
    If Len( aSt ) == 1
        nPC := nErrResume
    ElseIf QiWord( aSt, 2 ) == "NEXT"
        nPC := nErrResume + 1
    ElseIf aSt[2][1] == "W"
        nL := AScan( aLblName, aSt[2][2] )
        If nL == 0
            QiErr( "Label not defined" )
            Return
        EndIf
        nPC := aLblIdx[nL]
    Else
        QiErr( "Syntax error" )
        Return
    EndIf
    lJmp := .T.
Return

// Pula o bloco SUB/FUNCTION/TYPE ate o END correspondente
Static Function QiSkipTo( nCur, cKind )
    Local j := nCur + 1
    While j <= Len( aStmt )
        If QiWord( aStmt[j], 1 ) == "END" .And. QiWord( aStmt[j], 2 ) == cKind
            nPC := j + 1
            lJmp := .T.
            Return
        EndIf
        j := j + 1
    EndDo
    QiErr( "Falta END " + cKind )
Return

// ---------------------------------------------------------------------------
// E/S
// ---------------------------------------------------------------------------

// OPEN "arquivo" FOR OUTPUT|INPUT AS #n
Static Function QiOpenFile( aSt )
    Local cNm := ""
    Local cMd := ""
    Local nN := 0
    Local h := 0
    aTok := aSt
    nTP := 2
    If QiTT() != "S"
        QiErr( "Syntax error" )
        Return
    EndIf
    cNm := QiTV()
    nTP := nTP + 1
    If !QiTokIs( "W", "FOR" )
        QiErr( "Syntax error" )
        Return
    EndIf
    nTP := nTP + 1
    cMd := QiTV()
    nTP := nTP + 1
    If !QiTokIs( "W", "AS" )
        QiErr( "Syntax error" )
        Return
    EndIf
    nTP := nTP + 1
    If !QiTokIs( "O", "#" )
        QiErr( "Syntax error" )
        Return
    EndIf
    nTP := nTP + 1
    nN := QiExpr()
    If !Empty( cErr )
        Return
    EndIf
    If AScan( aFileN, nN ) > 0
        QiErr( "File already open" )
        Return
    EndIf
    If cMd == "OUTPUT"
        h := FCreate( cNm )
        If h < 0
            QiErr( "File not found" )
            Return
        EndIf
        AAdd( aFileN, nN )
        AAdd( aFileH, h )
        AAdd( aFileM, "O" )
        AAdd( aFileT, "" )
        AAdd( aFileP, 1 )
    ElseIf cMd == "INPUT"
        If !File( cNm )
            QiErr( "File not found" )
            Return
        EndIf
        AAdd( aFileN, nN )
        AAdd( aFileH, 0 )
        AAdd( aFileM, "I" )
        AAdd( aFileT, MemoRead( cNm ) )
        AAdd( aFileP, 1 )
    Else
        QiErr( "Statement not implemented: OPEN " + cMd )
    EndIf
Return

// Indice interno do arquivo aberto com numero nN (0 se nao existe)
Static Function QiFileIdx( nN )
Return AScan( aFileN, nN )

Static Function QiCloseFile( aSt )
    Local k := 0
    Local nN := -1
    aTok := aSt
    nTP := 2
    If QiTokIs( "O", "#" )
        nTP := nTP + 1
        nN := QiExpr()
    EndIf
    For k := Len( aFileN ) To 1 Step -1
        If nN < 0 .Or. aFileN[k] == nN
            If aFileM[k] == "O"
                FClose( aFileH[k] )
            EndIf
            QiFileRemove( k )
        EndIf
    Next
Return

Static Function QiFileRemove( k )
    Local aN := {}
    Local aH := {}
    Local aM := {}
    Local aT := {}
    Local aP := {}
    Local j := 0
    For j := 1 To Len( aFileN )
        If j != k
            AAdd( aN, aFileN[j] )
            AAdd( aH, aFileH[j] )
            AAdd( aM, aFileM[j] )
            AAdd( aT, aFileT[j] )
            AAdd( aP, aFileP[j] )
        EndIf
    Next
    aFileN := aN
    aFileH := aH
    aFileM := aM
    aFileT := aT
    aFileP := aP
Return

// Escreve texto no arquivo n (LF vira CRLF, como no DOS)
Static Function QiFileWrite( nN, cT )
    Local k := QiFileIdx( nN )
    If k == 0 .Or. aFileM[k] != "O"
        QiErr( "Bad file mode" )
        Return
    EndIf
    FWrite( aFileH[k], StrTran( cT, Chr(10), Chr(13) + Chr(10) ) )
Return

// Le uma linha do arquivo de entrada n ("" no fim)
Static Function QiFileLine( nN )
    Local k := QiFileIdx( nN )
    Local cT := ""
    Local nP := 0
    Local cR := ""
    If k == 0 .Or. aFileM[k] != "I"
        QiErr( "Bad file mode" )
        Return ""
    EndIf
    cT := aFileT[k]
    If aFileP[k] > Len( cT )
        Return ""
    EndIf
    cR := SubStr( cT, aFileP[k] )
    nP := At( Chr(10), cR )
    If nP == 0
        aFileP[k] := Len( cT ) + 1
    Else
        aFileP[k] := aFileP[k] + nP
        cR := Left( cR, nP - 1 )
    EndIf
Return StrTran( cR, Chr(13), "" )

// EOF(n): -1 quando a leitura do arquivo n chegou ao fim
Static Function QiEofFile( nN )
    Local k := QiFileIdx( nN )
    Local lE := .T.
    If k > 0 .And. aFileM[k] == "I"
        lE := aFileP[k] > Len( aFileT[k] )
    EndIf
Return QiBool( lE )

// PRINT: itens separados por ';' (sem espaco) ou ',' (zona de 14 colunas)
Static Function QiPrint( aSt )
    Local cOut := ""
    Local lNL := .T.
    Local vV := 0
    Local aNum := {}
    Local tV := "S"
    Local cFmt := ""
    Local lUsing := .F.
    aTok := aSt
    nTP := 2
    nPrFile := 0
    If QiTokIs( "O", "#" )
        nTP := nTP + 1
        nPrFile := QiExpr()
        QiComma()
    EndIf
    If QiTokIs( "W", "USING" )
        nTP := nTP + 1
        cFmt := QiExpr()
        If !QiTokIs( "O", ";" ) .And. !QiTokIs( "O", "," )
            QiErr( "Syntax error" )
            Return
        EndIf
        nTP := nTP + 1
        lUsing := .T.
    EndIf
    While nTP <= Len( aTok ) .And. Empty( cErr )
        If lUsing
            vV := QiExpr()
            If !Empty( cErr )
                Return
            EndIf
            cOut += QiUsing( cFmt, vV )
            lNL := .T.
            If QiTokIs( "O", ";" ) .Or. QiTokIs( "O", "," )
                nTP := nTP + 1
                lNL := .F.
            EndIf
            If nTP > Len( aTok )
                Exit
            EndIf
            Loop
        EndIf
        If QiTokIs( "O", ";" )
            nTP := nTP + 1
            lNL := .F.
        ElseIf QiTokIs( "O", "," )
            nTP := nTP + 1
            cOut += Space( 14 - Mod( nCol + Len( cOut ), 14 ) )
            lNL := .F.
        ElseIf ( QiTokIs( "W", "TAB" ) .Or. QiTokIs( "W", "SPC" ) ) .And. QiOpAt( aTok, nTP + 1, "(" )
            // TAB(n): ate a coluna n-1; SPC(n): n espacos
            lNL := .T.
            If QiTokIs( "W", "SPC" )
                nTP := nTP + 1
                aNum := QiArgs()
                If Len( aNum ) == 1 .And. ValType( aNum[1] ) == "N"
                    cOut += Space( Max( 0, Int( aNum[1] ) ) )
                EndIf
            Else
                nTP := nTP + 1
                aNum := QiArgs()
                If Len( aNum ) == 1 .And. ValType( aNum[1] ) == "N"
                    If Int( aNum[1] ) - 1 > nCol + Len( cOut )
                        cOut += Space( Int( aNum[1] ) - 1 - nCol - Len( cOut ) )
                    EndIf
                EndIf
            EndIf
        Else
            vV := QiExpr()
            tV := nTy
            If !Empty( cErr )
                Return
            EndIf
            If ValType( vV ) == "N"
                If vV >= 0
                    cOut += " " + QiFmtNum( vV, tV ) + " "
                Else
                    cOut += QiFmtNum( vV, tV ) + " "
                EndIf
            Else
                cOut += vV
            EndIf
            lNL := .T.
        EndIf
    EndDo
    If lNL
        cOut += Chr(10)
    EndIf
    If nPrFile > 0
        QiFileWrite( nPrFile, cOut )
    Else
        QiOut( cOut )
    EndIf
Return

// PRINT USING: formata um numero conforme o campo numerico do modelo
Static Function QiUsing( cF, v )
    Local nP := 0
    Local k := 1
    Local j := 1
    Local cC := ""
    Local cLead := ""
    Local cPre := ""
    Local cPost := ""
    Local nInt := 0
    Local nDec := 0
    Local lComma := .F.
    Local lExp := .F.
    Local lPlus := .F.
    Local lMinus := .F.
    Local lDot := .F.
    Local lStar := .F.
    Local lNeg := .F.
    Local a := 0
    Local m := 0
    Local e := 0
    Local ip := ""
    Local fp := ""
    Local cNum := ""
    Local cBody := ""
    Local nW := 0
    Local cPad := " "
    Local nEnd := 0
    For k := 1 To Len( cF )
        cC := SubStr( cF, k, 1 )
        If cC == "#" .Or. cC == "." .Or. cC == "+" .Or. ( cC == "$" .And. SubStr( cF, k + 1, 1 ) == "$" ) .Or. ( cC == "*" .And. SubStr( cF, k + 1, 1 ) == "*" )
            nP := k
            Exit
        EndIf
    Next
    If nP == 0
        Return cF
    EndIf
    cPre := Left( cF, nP - 1 )
    j := nP
    If SubStr( cF, j, 1 ) == "+"
        lPlus := .T.
        cLead := "+"
        j := j + 1
    ElseIf SubStr( cF, j, 2 ) == "$$"
        cLead := "$$"
        j := j + 2
    ElseIf SubStr( cF, j, 2 ) == "**"
        cLead := "**"
        lStar := .T.
        cPad := "*"
        j := j + 2
    EndIf
    While j <= Len( cF )
        cC := SubStr( cF, j, 1 )
        If cC == "#"
            If lDot
                nDec := nDec + 1
            Else
                nInt := nInt + 1
            EndIf
        ElseIf cC == ","
            lComma := .T.
        ElseIf cC == "."
            lDot := .T.
        Else
            Exit
        EndIf
        j := j + 1
    EndDo
    If SubStr( cF, j, 4 ) == "^^^^"
        lExp := .T.
        j := j + 4
    EndIf
    If SubStr( cF, j, 1 ) == "+"
        lPlus := .T.
        j := j + 1
    ElseIf SubStr( cF, j, 1 ) == "-"
        lMinus := .T.
        j := j + 1
    EndIf
    nEnd := j
    cPost := SubStr( cF, j )
    nW := nEnd - nP
    lNeg := v < 0
    a := Abs( v )
    If lExp
        e := 0
        If a > 0
            e := Int( Log( a ) / Log( 10 ) ) + 1
            If a < QiP10( e - 1 )
                e := e - 1
            EndIf
        EndIf
        m := Int( ( a / QiP10( e ) ) * QiP10( nDec ) + 0.5 )
        fp := AllTrim( Str( m ) )
        If nDec > 0
            fp := Replicate( "0", nDec - Len( fp ) ) + fp
        EndIf
        cBody := If( lNeg, "-", "" ) + "0" + If( nDec > 0, "." + fp, "" ) + "E" + If( e < 0, "-", "+" )
        cBody += If( Abs( e ) < 10, "0", "" ) + AllTrim( Str( Abs( e ) ) )
    Else
        m := Int( a * QiP10( nDec ) + 0.5 )
        ip := AllTrim( Str( Int( m / QiP10( nDec ) ) ) )
        If nDec > 0
            fp := AllTrim( Str( Mod( m, QiP10( nDec ) ) ) )
            fp := Replicate( "0", nDec - Len( fp ) ) + fp
        EndIf
        If lComma
            cNum := ""
            k := Len( ip )
            While k > 3
                cNum := "," + SubStr( ip, k - 2, 3 ) + cNum
                k := k - 3
            EndDo
            ip := SubStr( ip, 1, k ) + cNum
        EndIf
        If Len( StrTran( ip, ",", "" ) ) > nInt .And. nInt > 0
            cBody := "%"
        Else
            cBody := ""
        EndIf
        cNum := ip + If( lDot, "." + fp, "" )
        If lPlus
            cBody += If( lNeg, "-", "+" )
        ElseIf lNeg
            cBody += "-"
        EndIf
        If cLead == "$$"
            cBody += "$"
        EndIf
        cBody += cNum
        If lMinus
            cBody += If( lNeg, "-", " " )
        EndIf
    EndIf
    If Len( cBody ) < nW
        cBody := Replicate( cPad, nW - Len( cBody ) ) + cBody
    EndIf
Return cPre + cBody + cPost

// Caixa de mensagem de erro, como a do QBASIC: texto centralizado e "< OK >".
// Em terminal espera Enter/Esc; fora dele apenas desenha a caixa.
Static Function QiErrorBox( cMsg )
    Local nW := Max( Len( cMsg ) + 6, 14 )
    Local nL := Int( ( 80 - nW ) / 2 )
    Local r0 := 9
    Local k := 0
    Local nAt := 112
    Local cK := ""
    For k := 0 To 4
        QiPutBox( r0 + k, nL, nW, k, nAt )
    Next
    QiPutAt( r0 + 1, nL + Int( ( nW - Len( cMsg ) ) / 2 ), cMsg, nAt )
    QiPutAt( r0 + 3, nL + Int( ( nW - 6 ) / 2 ), "< OK >", nAt )
    lDirty := .T.
    QiGfxFlush()
    If lTTY
        While .T.
            cK := QiInkey()
            If cK == Chr(13) .Or. cK == Chr(27)
                Exit
            EndIf
        EndDo
    EndIf
Return

// Linha k da caixa (0 = topo, 4 = base)
Static Function QiPutBox( nR, nC, nW, k, nAt )
    Local cLeft := ""
    Local cMid := ""
    Local cRight := ""
    Local j := 0
    If k == 0
        cLeft := QiChrG( 218 )
        cMid := QiChrG( 196 )
        cRight := QiChrG( 191 )
    ElseIf k == 4
        cLeft := QiChrG( 192 )
        cMid := QiChrG( 196 )
        cRight := QiChrG( 217 )
    Else
        cLeft := QiChrG( 179 )
        cMid := " "
        cRight := QiChrG( 179 )
    EndIf
    QiPutAt( nR, nC, cLeft, nAt )
    For j := 1 To nW - 2
        QiPutAt( nR, nC + j, cMid, nAt )
    Next
    QiPutAt( nR, nC + nW - 1, cRight, nAt )
Return

// Escreve texto na tela em uma posicao, sem mover o cursor da saida
Static Function QiPutAt( nR, nC, cT, nAt )
    Local aCh := QiSplitU( cT )
    Local k := 0
    Local nI := 0
    For k := 1 To Len( aCh )
        nI := nC + k - 1
        If nI >= 0 .And. nI < 80 .And. nR >= 0 .And. nR < 25
            aScr[nR*80 + nI + 1] := aCh[k]
            aAtt[nR*80 + nI + 1] := nAt
        EndIf
    Next
Return

// Texto de um numero, sem espacos de sinal
Static Function QiNumTxt( v )
    Local cS := ""
    If v == Int( v )
        cS := AllTrim( Str( v ) )
    Else
        cS := AllTrim( Str( v, 20, 6 ) )
        While Right( cS, 1 ) == "0"
            cS := Left( cS, Len( cS ) - 1 )
        EndDo
        If Right( cS, 1 ) == "."
            cS := Left( cS, Len( cS ) - 1 )
        EndIf
    EndIf
Return cS

Static Function QiInput( aSt )
    Local cPrm := ""
    Local cPr := ""
    Local lQ := .T.
    Local cLine := ""
    Local aParts := {}
    Local nK := 1
    Local t := {}
    Local cRaw := ""
    Local vV := ""

    aTok := aSt
    nTP := 2
    nPrFile := 0
    If QiTokIs( "O", "#" )
        nTP := nTP + 1
        nPrFile := QiExpr()
        QiComma()
        lQ := .F.
    EndIf
    If QiTT() == "S"
        cPrm := QiTV()
        nTP := nTP + 1
        If QiTokIs( "O", ";" )
            nTP := nTP + 1
        ElseIf QiTokIs( "O", "," )
            lQ := .F.
            nTP := nTP + 1
        EndIf
    EndIf
    cPr := cPrm
    If lQ
        cPr := cPr + "? "
    EndIf
    If nPrFile == 0
        QiOut( cPr )
        cLine := QiReadLine( .T. )
    Else
        cLine := QiFileLine( nPrFile )
    EndIf
    aParts := QiSplit( cLine, "," )

    While Empty( cErr ) .And. QiTT() == "W"
        t := QiTarget()
        cRaw := ""
        If nK <= Len( aParts )
            cRaw := AllTrim( aParts[nK] )
        EndIf
        nK := nK + 1
        If Right( t[1], 1 ) == "$"
            vV := cRaw
        Else
            vV := QiVal( cRaw )
        EndIf
        QiStoreT( t, vV )
        If QiTokIs( "O", "," )
            nTP := nTP + 1
        Else
            Exit
        EndIf
    EndDo
Return

// LINE INPUT [prompt;] var$
Static Function QiLineInput( aSt )
    Local cPrm := ""
    Local t := {}
    aTok := aSt
    nTP := 3
    nPrFile := 0
    If QiTokIs( "O", "#" )
        nTP := nTP + 1
        nPrFile := QiExpr()
        QiComma()
    EndIf
    If QiTT() == "S"
        cPrm := QiTV()
        nTP := nTP + 1
        If QiTokIs( "O", ";" ) .Or. QiTokIs( "O", "," )
            nTP := nTP + 1
        EndIf
    EndIf
    If nPrFile == 0
        QiOut( cPrm )
    EndIf
    t := QiTarget()
    If nPrFile == 0
        QiStoreT( t, QiReadLine( .T. ) )
    Else
        QiStoreT( t, QiFileLine( nPrFile ) )
    EndIf
Return

// ---------------------------------------------------------------------------
// Atribuicao e alvos
// ---------------------------------------------------------------------------

// MID$(s, inicio, comp) = expressao: troca os caracteres (sem mudar o tamanho)
Static Function QiMidAssign( aSt )
    Local cNm := ""
    Local nI := 0
    Local nC := 0
    Local hasLen := .F.
    Local vV := ""
    Local cS := ""
    Local nCount := 0
    aTok := aSt
    nTP := 3
    If QiTT() != "W"
        QiErr( "Syntax error" )
        Return
    EndIf
    cNm := QiTV()
    nTP := nTP + 1
    If !QiTokIs( "O", "," )
        QiErr( "Syntax error" )
        Return
    EndIf
    nTP := nTP + 1
    nI := QiRoundEven( QiExpr() )
    If QiTokIs( "O", "," )
        nTP := nTP + 1
        nC := QiRoundEven( QiExpr() )
        hasLen := .T.
    EndIf
    If !QiTokIs( "O", ")" )
        QiErr( "Syntax error" )
        Return
    EndIf
    nTP := nTP + 1
    If !QiTokIs( "O", "=" )
        QiErr( "Syntax error" )
        Return
    EndIf
    nTP := nTP + 1
    vV := QiExpr()
    If !Empty( cErr )
        Return
    EndIf
    cS := QiVarGet( cNm )
    If ValType( cS ) != "C" .Or. nI < 1 .Or. nI > QiLenU( cS )
        Return
    EndIf
    nCount := QiLenU( vV )
    If hasLen
        nCount := Min( nCount, nC )
    EndIf
    nCount := Min( nCount, QiLenU( cS ) - nI + 1 )
    If nCount < 1
        Return
    EndIf
    QiVarSet( cNm, QiSubU( cS, 1, nI - 1 ) + QiSubU( vV, 1, nCount ) + QiSubU( cS, nI + nCount, QiLenU( cS ) ) )
Return

// SWAP a, b: troca os valores de dois alvos
Static Function QiSwap( aSt )
    Local t1 := {}
    Local t2 := {}
    Local v1 := 0
    Local v2 := 0
    aTok := aSt
    nTP := 2
    t1 := QiTarget()
    If !QiComma()
        QiErr( "Syntax error" )
        Return
    EndIf
    t2 := QiTarget()
    If !Empty( cErr )
        Return
    EndIf
    v1 := QiVarOrElem( t1[1], t1[2] )
    v2 := QiVarOrElem( t2[1], t2[2] )
    QiStoreT( t1, v2 )
    QiStoreT( t2, v1 )
Return

// LET / atribuicao implicita. nFrom aponta para o alvo.
Static Function QiAssign( aSt, nFrom )
    Local t := {}
    Local vV := 0
    aTok := aSt
    nTP := nFrom
    t := QiTarget()
    If !Empty( cErr )
        Return
    EndIf
    If !QiTokIs( "O", "=" )
        QiErr( "Syntax error" )
        Return
    EndIf
    nTP := nTP + 1
    vV := QiExpr()
    If !Empty( cErr )
        Return
    EndIf
    QiStoreT( t, vV )
Return

// Alvo: {nome, indices, campo}
Static Function QiTarget()
    Local t := { "", {}, "" }
    If QiTT() != "W"
        QiErr( "Syntax error" )
        Return t
    EndIf
    t[1] := QiTV()
    nTP := nTP + 1
    If QiTokIs( "O", "(" )
        t[2] := QiArgs()
    EndIf
    If QiTokIs( "O", "." )
        nTP := nTP + 1
        t[3] := QiTV()
        nTP := nTP + 1
    EndIf
Return t

Static Function QiStoreT( t, vV )
    Local rec := 0
    Local fi := 0
    If !Empty( t[3] )
        rec := QiVarOrElem( t[1], t[2] )
        If !Empty( cErr )
            Return
        EndIf
        fi := QiFieldIdx( QiTypeOfName( t[1] ), t[3] )
        If fi == 0
            QiErr( "Element is not a member" )
            Return
        EndIf
        If ValType( vV ) == "C" .And. QiFieldLen( QiTypeOfName( t[1] ), fi ) > 0
            vV := Left( vV + Space( QiFieldLen( QiTypeOfName( t[1] ), fi ) ), QiFieldLen( QiTypeOfName( t[1] ), fi ) )
        EndIf
        rec[fi] := vV
    ElseIf Len( t[2] ) > 0
        QiElemOf( t[1], t[2], .T., vV )
    Else
        QiVarSet( t[1], vV )
    EndIf
Return

Static Function QiVarOrElem( cNm, aIdx )
    Local vR := 0
    If Len( aIdx ) > 0
        vR := QiElemOf( cNm, aIdx, .F., 0 )
    Else
        vR := QiVarGet( cNm )
    EndIf
Return vR

Static Function QiTypeOfName( cNm )
    Local pos := AScan( aVN, QiKey( cNm ) )
    Local cT := ""
    If pos > 0
        cT := aVM[pos][1]
    EndIf
Return cT

// Tamanho fixo de um campo STRING * n (0 se nao for)
Static Function QiFieldLen( cType, fi )
    Local k := AScan( aTypeName, cType )
    Local nR := 0
    If k > 0 .And. fi > 0
        nR := aTypeLen[k][fi]
    EndIf
Return nR

Static Function QiFieldIdx( cType, cFld )
    Local k := 0
    Local fi := 0
    If Empty( cType )
        Return 0
    EndIf
    k := AScan( aTypeName, cType )
    If k == 0
        Return 0
    EndIf
    fi := AScan( aTypeFld[k], cFld )
Return fi

// ---------------------------------------------------------------------------
// IF / SELECT CASE / laços
// ---------------------------------------------------------------------------

Static Function QiIf( aSt, nCur )
    Local vC := 0
    Local aBody := {}
    Local aElse := {}
    Local lElse := .F.
    Local nK := 0

    aTok := aSt
    nTP := 2
    vC := QiExpr()
    If !Empty( cErr )
        Return
    EndIf
    If QiTokIs( "W", "THEN" )
        nTP := nTP + 1
    ElseIf QiTokIs( "W", "GOTO" )
        // IF cond GOTO n: o corpo comeca no GOTO
    Else
        QiErr( "Syntax error" )
        Return
    EndIf

    If nTP > Len( aTok )
        If QiTruth( vC )
            Return
        EndIf
        QiSkipClause( nCur )
        Return
    EndIf

    For nK := nTP To Len( aTok )
        If !lElse .And. aTok[nK][1] == "W" .And. aTok[nK][2] == "ELSE"
            lElse := .T.
        ElseIf lElse
            AAdd( aElse, aTok[nK] )
        Else
            AAdd( aBody, aTok[nK] )
        EndIf
    Next

    If QiTruth( vC )
        QiExecBody( aBody, nCur )
    Else
        QiExecBody( aElse, nCur )
    EndIf
Return

Static Function QiExecBody( aB, nCur )
    Local aCmds := {}
    Local nK := 0
    If Len( aB ) == 0
        Return
    EndIf
    If aB[1][1] == "N"
        QiExec( { { "W", "GOTO", "GOTO" }, aB[1] }, nCur )
        Return
    EndIf
    aCmds := QiSplitStmts( aB )
    For nK := 1 To Len( aCmds )
        QiExec( aCmds[nK], nCur )
        If lJmp .Or. lStop .Or. lRet .Or. !Empty( cErr )
            Exit
        EndIf
    Next
Return

// Bloco IF com condicao falsa: vai para o proximo ELSEIF/ELSE/END IF do mesmo nivel
Static Function QiSkipClause( nCur )
    Local nD := 0
    Local j := nCur + 1
    Local cF := ""
    Local cS := ""
    Local vC := 0
    While j <= Len( aStmt )
        cF := QiWord( aStmt[j], 1 )
        cS := QiWord( aStmt[j], 2 )
        If cF == "IF" .And. QiIsBlockIf( aStmt[j] )
            nD := nD + 1
        ElseIf cF == "END" .And. cS == "IF"
            If nD == 0
                nPC := j + 1
                lJmp := .T.
                Return
            EndIf
            nD := nD - 1
        ElseIf nD == 0 .And. cF == "ELSE"
            nPC := j + 1
            lJmp := .T.
            Return
        ElseIf nD == 0 .And. cF == "ELSEIF"
            aTok := aStmt[j]
            nTP := 2
            vC := QiExpr()
            If !Empty( cErr )
                Return
            EndIf
            If QiTruth( vC )
                nPC := j + 1
                lJmp := .T.
                Return
            EndIf
        EndIf
        j := j + 1
    EndDo
    QiErr( "IF sem END IF" )
Return

// ELSE/ELSEIF alcancado pelo fluxo normal: o ramo verdadeiro terminou
Static Function QiJumpEndIf( nCur )
    Local nD := 0
    Local j := nCur + 1
    Local cF := ""
    Local cS := ""
    While j <= Len( aStmt )
        cF := QiWord( aStmt[j], 1 )
        cS := QiWord( aStmt[j], 2 )
        If cF == "IF" .And. QiIsBlockIf( aStmt[j] )
            nD := nD + 1
        ElseIf cF == "END" .And. cS == "IF"
            If nD == 0
                nPC := j + 1
                lJmp := .T.
                Return
            EndIf
            nD := nD - 1
        EndIf
        j := j + 1
    EndDo
    QiErr( "IF sem END IF" )
Return

// Indice do fechamento correspondente (mesmo nivel), ou 0
Static Function QiFindClose( nFrom, cOpen, cClose )
    Local nD := 0
    Local j := nFrom + 1
    Local cF := ""
    While j <= Len( aStmt )
        cF := QiWord( aStmt[j], 1 )
        If cF == cOpen
            nD := nD + 1
        ElseIf cF == cClose
            If nD == 0
                Return j
            EndIf
            nD := nD - 1
        EndIf
        j := j + 1
    EndDo
Return 0

// SELECT CASE expr: empilha o valor e localiza o primeiro CASE que casa
Static Function QiSelect( aSt, nCur )
    Local vV := 0
    aTok := aSt
    nTP := 3
    vV := QiExpr()
    If !Empty( cErr )
        Return
    EndIf
    AAdd( aSel, vV )
    QiSelectScan( nCur )
Return

Static Function QiSelectScan( nCur )
    Local vV := aSel[Len( aSel )]
    Local nD := 0
    Local j := nCur + 1
    Local nElse := 0
    Local cF := ""
    Local cS := ""
    While j <= Len( aStmt )
        cF := QiWord( aStmt[j], 1 )
        cS := QiWord( aStmt[j], 2 )
        If cF == "SELECT" .And. cS == "CASE"
            nD := nD + 1
        ElseIf cF == "END" .And. cS == "SELECT"
            If nD == 0
                If nElse > 0
                    nPC := nElse + 1
                Else
                    nPC := j
                EndIf
                lJmp := .T.
                Return
            EndIf
            nD := nD - 1
        ElseIf nD == 0 .And. cF == "CASE"
            If cS == "ELSE"
                nElse := j
            ElseIf QiCaseMatch( aStmt[j], vV )
                nPC := j + 1
                lJmp := .T.
                Return
            EndIf
        EndIf
        j := j + 1
    EndDo
    QiErr( "SELECT CASE sem END SELECT" )
Return

// Testa os itens de um CASE contra o valor do SELECT
Static Function QiCaseMatch( aC, vV )
    Local lOk := .F.
    Local e1 := 0
    Local e2 := 0
    Local cOp := ""
    aTok := aC
    nTP := 2
    While nTP <= Len( aTok ) .And. Empty( cErr ) .And. !lOk
        If QiTokIs( "W", "IS" )
            nTP := nTP + 1
            cOp := QiTV()
            nTP := nTP + 1
            e1 := QiExpr()
            If ValType( vV ) == ValType( e1 )
                lOk := QiCmp( vV, e1, cOp ) != 0
            EndIf
        Else
            e1 := QiExpr()
            If QiTokIs( "W", "TO" )
                nTP := nTP + 1
                e2 := QiExpr()
                If ValType( vV ) == ValType( e1 ) .And. ValType( vV ) == ValType( e2 )
                    lOk := ( vV >= e1 ) .And. ( vV <= e2 )
                EndIf
            Else
                If ValType( vV ) == ValType( e1 )
                    lOk := vV == e1
                EndIf
            EndIf
        EndIf
        If QiTokIs( "O", "," )
            nTP := nTP + 1
        Else
            Exit
        EndIf
    EndDo
Return lOk

// CASE alcancado pelo fluxo normal: o ramo anterior terminou -> END SELECT
Static Function QiCaseJump( nCur )
    Local nD := 0
    Local j := nCur + 1
    Local cF := ""
    Local cS := ""
    While j <= Len( aStmt )
        cF := QiWord( aStmt[j], 1 )
        cS := QiWord( aStmt[j], 2 )
        If cF == "SELECT" .And. cS == "CASE"
            nD := nD + 1
        ElseIf cF == "END" .And. cS == "SELECT"
            If nD == 0
                nPC := j
                lJmp := .T.
                Return
            EndIf
            nD := nD - 1
        EndIf
        j := j + 1
    EndDo
    QiErr( "SELECT CASE sem END SELECT" )
Return

Static Function QiPopSel()
    Local aN := {}
    Local k := 0
    For k := 1 To Len( aSel ) - 1
        AAdd( aN, aSel[k] )
    Next
    aSel := aN
Return

// Pilha de laços: {tipo, indice do comando de abertura, var, fim, passo}
// tipos: "F" FOR, "W" WHILE, "D" DO

Static Function QiPopFrm()
    Local aN := {}
    Local k := 0
    For k := 1 To Len( aFrm ) - 1
        AAdd( aN, aFrm[k] )
    Next
    aFrm := aN
Return

Static Function QiPopIf( cTipo, nCur )
    Local nTop := Len( aFrm )
    If nTop > 0
        If aFrm[nTop][1] == cTipo .And. aFrm[nTop][2] == nCur
            QiPopFrm()
        EndIf
    EndIf
Return

Static Function QiFor( aSt, nCur )
    Local cNm := ""
    Local vS := 0
    Local vE := 0
    Local vP := 1
    Local j := 0

    aTok := aSt
    nTP := 2
    If QiTT() != "W"
        QiErr( "Syntax error" )
        Return
    EndIf
    cNm := QiTV()
    nTP := nTP + 1
    If !QiTokIs( "O", "=" )
        QiErr( "Syntax error" )
        Return
    EndIf
    nTP := nTP + 1
    vS := QiExpr()
    If !QiTokIs( "W", "TO" )
        QiErr( "Syntax error" )
        Return
    EndIf
    nTP := nTP + 1
    vE := QiExpr()
    If QiTokIs( "W", "STEP" )
        nTP := nTP + 1
        vP := QiExpr()
    EndIf
    If !Empty( cErr )
        Return
    EndIf
    If vP == 0
        QiErr( "Illegal function call" )
        Return
    EndIf
    QiVarSet( cNm, vS )
    If ( vP > 0 .And. vS > vE ) .Or. ( vP < 0 .And. vS < vE )
        j := QiFindClose( nCur, "FOR", "NEXT" )
        If j == 0
            QiErr( "FOR sem NEXT" )
            Return
        EndIf
        nPC := j + 1
        lJmp := .T.
    Else
        AAdd( aFrm, { "F", nCur, cNm, vE, vP } )
    EndIf
Return

Static Function QiNext()
    Local nTop := Len( aFrm )
    Local fr := {}
    Local vN := 0
    If nTop == 0
        QiErr( "NEXT sem FOR" )
        Return
    EndIf
    fr := aFrm[nTop]
    If fr[1] != "F"
        QiErr( "NEXT sem FOR" )
        Return
    EndIf
    vN := QiVarGet( fr[3] ) + fr[5]
    QiVarSet( fr[3], vN )
    If ( fr[5] > 0 .And. vN > fr[4] ) .Or. ( fr[5] < 0 .And. vN < fr[4] )
        QiPopFrm()
    Else
        nPC := fr[2] + 1
        lJmp := .T.
    EndIf
Return

Static Function QiWhile( aSt, nCur )
    Local vC := 0
    Local j := 0
    QiPopIf( "W", nCur )
    aTok := aSt
    nTP := 2
    vC := QiExpr()
    If !Empty( cErr )
        Return
    EndIf
    If QiTruth( vC )
        AAdd( aFrm, { "W", nCur, "", 0, 0 } )
    Else
        j := QiFindClose( nCur, "WHILE", "WEND" )
        If j == 0
            QiErr( "WHILE sem WEND" )
            Return
        EndIf
        nPC := j + 1
        lJmp := .T.
    EndIf
Return

Static Function QiWend()
    Local nTop := Len( aFrm )
    If nTop == 0
        QiErr( "WEND sem WHILE" )
        Return
    EndIf
    If aFrm[nTop][1] != "W"
        QiErr( "WEND sem WHILE" )
        Return
    EndIf
    nPC := aFrm[nTop][2]
    lJmp := .T.
Return

Static Function QiDo( aSt, nCur )
    Local vC := 0
    Local lWhile := .F.
    Local lCont := .T.
    Local j := 0
    Local cK := QiWord( aSt, 2 )

    QiPopIf( "D", nCur )
    If cK == "WHILE" .Or. cK == "UNTIL"
        lWhile := cK == "WHILE"
        aTok := aSt
        nTP := 3
        vC := QiExpr()
        If !Empty( cErr )
            Return
        EndIf
        lCont := QiTruth( vC )
        If !lWhile
            lCont := !lCont
        EndIf
        If !lCont
            j := QiFindClose( nCur, "DO", "LOOP" )
            If j == 0
                QiErr( "DO sem LOOP" )
                Return
            EndIf
            nPC := j + 1
            lJmp := .T.
            Return
        EndIf
    EndIf
    AAdd( aFrm, { "D", nCur, "", 0, 0 } )
Return

Static Function QiLoop( aSt )
    Local nTop := Len( aFrm )
    Local vC := 0
    Local lWhile := .F.
    Local lCont := .T.
    Local cK := QiWord( aSt, 2 )

    If nTop == 0
        QiErr( "LOOP sem DO" )
        Return
    EndIf
    If aFrm[nTop][1] != "D"
        QiErr( "LOOP sem DO" )
        Return
    EndIf
    If cK == "WHILE" .Or. cK == "UNTIL"
        lWhile := cK == "WHILE"
        aTok := aSt
        nTP := 3
        vC := QiExpr()
        If !Empty( cErr )
            Return
        EndIf
        lCont := QiTruth( vC )
        If !lWhile
            lCont := !lCont
        EndIf
    EndIf
    If lCont
        nPC := aFrm[nTop][2]
        lJmp := .T.
    Else
        QiPopFrm()
    EndIf
Return

Static Function QiExit( aSt )
    Local cK := QiWord( aSt, 2 )
    Local nTop := Len( aFrm )
    Local j := 0
    Local cOpen := ""
    Local cClose := ""
    Local cTipo := ""

    If cK == "SUB" .And. Len( aRet ) > 0
        QiFlatRet()
        Return
    EndIf
    If cK == "SUB" .Or. cK == "FUNCTION"
        lRet := .T.
        Return
    EndIf
    If nTop == 0
        QiErr( "EXIT fora de laco" )
        Return
    EndIf
    If cK == "FOR"
        cOpen := "FOR"
        cClose := "NEXT"
        cTipo := "F"
    ElseIf cK == "DO"
        cOpen := "DO"
        cClose := "LOOP"
        cTipo := "D"
    ElseIf cK == "WHILE"
        cOpen := "WHILE"
        cClose := "WEND"
        cTipo := "W"
    Else
        QiErr( "EXIT invalido" )
        Return
    EndIf
    If aFrm[nTop][1] != cTipo
        QiErr( "EXIT " + cK + " fora do laco correspondente" )
        Return
    EndIf
    j := QiFindClose( aFrm[nTop][2], cOpen, cClose )
    If j == 0
        QiErr( "Laco sem fechamento" )
        Return
    EndIf
    QiPopFrm()
    nPC := j + 1
    lJmp := .T.
Return

Static Function QiGotoStmt( aSt )
    Local nP := 0
    Local nL := 0
    If Len( aSt ) < 2
        QiErr( "Syntax error" )
        Return
    EndIf
    If aSt[2][1] == "W"
        nL := AScan( aLblName, aSt[2][2] )
        If nL == 0
            QiErr( "Label not defined" )
            Return
        EndIf
        nPC := aLblIdx[nL]
        lJmp := .T.
        Return
    EndIf
    If aSt[2][1] != "N"
        QiErr( "Syntax error" )
        Return
    EndIf
    nP := AScan( aStmtLn, aSt[2][2] )
    If nP == 0
        QiErr( "Undefined line number" )
        Return
    EndIf
    nPC := nP
    lJmp := .T.
Return

Static Function QiReturn()
    Local nTop := Len( aGos )
    Local aN := {}
    Local k := 0
    If nTop == 0
        QiErr( "RETURN sem GOSUB" )
        Return
    EndIf
    nPC := aGos[nTop]
    For k := 1 To nTop - 1
        AAdd( aN, aGos[k] )
    Next
    aGos := aN
    lJmp := .T.
Return

Static Function QiConst( aSt )
    Local cNm := ""
    Local vV := 0
    aTok := aSt
    nTP := 2
    While Empty( cErr ) .And. QiTT() == "W"
        cNm := QiTV()
        nTP := nTP + 1
        If !QiTokIs( "O", "=" )
            QiErr( "Syntax error" )
            Return
        EndIf
        nTP := nTP + 1
        vV := QiExpr()
        QiVarSet( cNm, vV )
        If QiTokIs( "O", "," )
            nTP := nTP + 1
        Else
            Exit
        EndIf
    EndDo
Return

// ---------------------------------------------------------------------------
// Tela 80x25 em modo texto (Fase 2)
// Buffer aScr/aAtt: 2000 celulas (linha*80 + coluna + 1). Atributo CGA:
// baixo nibble = cor do texto, bits 4-6 = cor de fundo.
// Em terminal (lTTY) a saida usa ANSI; em pipe sai texto puro.
// ---------------------------------------------------------------------------

Static Function QiScrInit()
    Local k := 0
    aScr := Array( 2000 )
    aAtt := Array( 2000 )
    For k := 1 To 2000
        aScr[k] := " "
        aAtt[k] := 7
    Next
Return

// Sequencia SGR para o atributo CGA (paleta de 256 cores do terminal)
Static Function QiSgr( nAt )
    Local aMap := { 0, 4, 2, 6, 1, 5, 3, 7, 8, 12, 10, 14, 9, 13, 11, 15 }
    Local nF := Mod( nAt, 16 )
    Local nB := Mod( Int( nAt / 16 ), 8 )
Return Chr(27) + "[0;38;5;" + LTrim( Str( aMap[nF+1] ) ) + ";48;5;" + LTrim( Str( aMap[nB+1] ) ) + "m"

// Escreve texto na tela na posicao do cursor (LF = nova linha)
Static Function QiPutStr( cS )
    Local k := 1
    Local cCh := ""
    Local b := 0
    Local nL := 1
    If lCapt
        cCapt += cS
        Return
    EndIf
    While k <= Len( cS )
        b := Asc( SubStr( cS, k, 1 ) )
        nL := 1
        If b >= 240
            nL := 4
        ElseIf b >= 224
            nL := 3
        ElseIf b >= 192
            nL := 2
        EndIf
        cCh := SubStr( cS, k, nL )
        k := k + nL
        If cCh == Chr(10)
            QiNewLine()
        ElseIf cCh == Chr(13)
            // CR: nada (o QBASIC so move o cursor com LF)
        Else
            // caracteres de controle ocupam a celula com o proprio codigo (como na memoria de video)
            QiPutCell( cCh )
        EndIf
    EndDo
Return

Static Function QiPutCell( cCh )
    Local nIdx := 0
    If nCol >= 80
        QiNewLine()
    EndIf
    nIdx := nRow * 80 + nCol + 1
    aScr[nIdx] := cCh
    aAtt[nIdx] := nAttr
    If lTTY .And. nAttr != nEmitAtt
        ConOutRaw( QiSgr( nAttr ) )
        nEmitAtt := nAttr
    EndIf
    If Len( cCh ) == 1 .And. Asc( cCh ) < 32
        ConOutRaw( " " )
    Else
        ConOutRaw( cCh )
    EndIf
    lDirty := .T.
    nCol := nCol + 1
Return

Static Function QiNewLine()
    If lTTY
        ConOutRaw( Chr(13) + Chr(10) )
    Else
        ConOutRaw( Chr(10) )
    EndIf
    nCol := 0
    nRow := nRow + 1
    If nRow > 23
        QiScrollUp()
        nRow := 23
    EndIf
Return

Static Function QiScrollUp()
    Local r := 0
    Local c := 0
    For r := 0 To 22
        For c := 1 To 80
            aScr[r*80+c] := aScr[(r+1)*80+c]
            aAtt[r*80+c] := aAtt[(r+1)*80+c]
        Next
    Next
    For c := 1 To 80
        aScr[1840+c] := " "
        aAtt[1840+c] := nAttr
    Next
Return

Static Function QiCls()
    Local k := 0
    Local nPx := 0
    If nMode != 0
        For nPx := 1 To Len( aPix )
            aPix[nPx] := 0
        Next
        lDirty := .T.
    EndIf
    For k := 1 To 2000
        aScr[k] := " "
        aAtt[k] := nAttr
    Next
    nRow := 0
    nCol := 0
    If lTTY
        ConOutRaw( QiSgr( nAttr ) + Chr(27) + "[2J" + Chr(27) + "[H" )
        nEmitAtt := nAttr
    EndIf
Return

// LOCATE linha, coluna [, cursor]
Static Function QiLocate( aSt )
    Local vR := 0
    Local vC := 0
    Local vCur := -1
    Local lHasC := .F.
    aTok := aSt
    nTP := 2
    If nTP > Len( aTok )
        Return
    EndIf
    vR := QiExpr()
    If QiTokIs( "O", "," )
        nTP := nTP + 1
        If !QiTokIs( "O", "," )
            vC := QiExpr()
            lHasC := .T.
        EndIf
        If QiTokIs( "O", "," )
            nTP := nTP + 1
            vCur := QiExpr()
        EndIf
    EndIf
    If !Empty( cErr )
        Return
    EndIf
    If !lHasC
        vC := nCol + 1
    EndIf
    If vR < 1 .Or. vR > 25 .Or. vC < 1 .Or. vC > 80
        QiErr( "Illegal function call" )
        Return
    EndIf
    nRow := Int( vR ) - 1
    nCol := Int( vC ) - 1
    If lTTY
        ConOutRaw( Chr(27) + "[" + LTrim( Str( nRow + 1 ) ) + ";" + LTrim( Str( nCol + 1 ) ) + "H" )
        If vCur == 0
            ConOutRaw( Chr(27) + "[?25l" )
        ElseIf vCur == 1
            ConOutRaw( Chr(27) + "[?25h" )
        EndIf
    EndIf
Return

// COLOR fg [, bg]: fg 0-15, bg 0-7
Static Function QiColor( aSt )
    Local vF := -1
    Local vB := -1
    aTok := aSt
    nTP := 2
    If nTP <= Len( aTok ) .And. !QiTokIs( "O", "," )
        vF := QiExpr()
    EndIf
    If QiTokIs( "O", "," )
        nTP := nTP + 1
        If nTP <= Len( aTok )
            vB := QiExpr()
        EndIf
    EndIf
    If !Empty( cErr )
        Return
    EndIf
    If vF >= 0
        If vF > 15
            QiErr( "Illegal function call" )
            Return
        EndIf
        nFg := Int( vF )
    EndIf
    If vB >= 0
        If vB > 7
            QiErr( "Illegal function call" )
            Return
        EndIf
        nBg := Int( vB )
    EndIf
    nAttr := nBg * 16 + nFg
Return

// ---------------------------------------------------------------------------
// Graficos (Fase 4). Pixels em aPix (indice de paleta, linha-major).
// Modos: 0 texto; 1 320x200 (4 cores); 2 640x200 (2); 9 640x350 (16); 12 640x480 (16).
// No terminal, a grade fisica 80x25 usa meio-bloco (U+2580): cor de cima = pixel
// superior, cor de baixo = pixel inferior. Texto (Fase 2) aparece por cima.
// ---------------------------------------------------------------------------

Static Function QiScreen( aSt )
    Local vM := 0
    aTok := aSt
    nTP := 2
    If nTP > Len( aTok )
        Return
    EndIf
    vM := QiExpr()
    If !Empty( cErr )
        Return
    EndIf
    QiSetMode( Int( vM ) )
Return

Static Function QiSetMode( nM )
    Local nW := 0
    Local nH := 0
    Local nC := 0
    Local k := 0
    If nM == 0
        nMode := 0
        aPix := {}
        aPal := {}
    Else
        If nM == 1
            nW := 320
            nH := 200
            nC := 4
        ElseIf nM == 2
            nW := 640
            nH := 200
            nC := 2
        ElseIf nM == 9
            nW := 640
            nH := 350
            nC := 16
        ElseIf nM == 12
            nW := 640
            nH := 480
            nC := 16
        Else
            QiErr( "Illegal function call" )
            Return
        EndIf
        nMode := nM
        nGW := nW
        nGH := nH
        aPix := Array( nW * nH )
        For k := 1 To nW * nH
            aPix[k] := 0
        Next
        aPal := Array( 16 )
        For k := 1 To 16
            aPal[k] := k - 1
        Next
        nFg := nC - 1
        nBg := 0
        nAttr := 7
        nGx := 0
        nGy := 0
    EndIf
    aLast := {}
    QiCls()
    lDirty := .T.
Return

// Cor de tela para um indice de paleta
Static Function QiPalOf( v )
    Local nI := 0
    If v < 0
        Return 0
    EndIf
    nI := Mod( Int( v ), 16 )
    If Len( aPal ) == 16
        Return aPal[nI+1]
    EndIf
Return nI

// SGR com cores 0-15 (fundo e texto)
Static Function QiSgrRaw( nF, nB )
    Local aMap := { 0, 4, 2, 6, 1, 5, 3, 7, 8, 12, 10, 14, 9, 13, 11, 15 }
Return Chr(27) + "[0;38;5;" + LTrim( Str( aMap[Mod( nF, 16 ) + 1] ) ) + ";48;5;" + LTrim( Str( aMap[Mod( nB, 16 ) + 1] ) ) + "m"

// Redesenha no terminal apenas as celulas alteradas (texto por cima do grafico)
Static Function QiGfxFlush()
    Local r := 0
    Local c := 0
    Local cell := 0
    Local cOut := ""
    Local cKey := ""
    Local cCh := ""
    Local nF := 0
    Local nB := 0
    Local nPx := 0
    Local nPy := 0
    Local nT := 0
    Local nBt := 0
    If !lDirty
        Return
    EndIf
    lDirty := .F.
    If !lTTY
        Return
    EndIf
    If Len( aLast ) == 0
        aLast := Array( 2000 )
        For cell := 1 To 2000
            aLast[cell] := ""
        Next
    EndIf
    For r := 0 To 24
        For c := 0 To 79
            cell := r * 80 + c + 1
            If nMode != 0 .And. aScr[cell] == " "
                nPx := Int( c * nGW / 80 )
                nPy := Int( ( 2 * r ) * nGH / 50 )
                nT := QiPalOf( QiPixGet( nPx, nPy ) )
                nPy := Int( ( 2 * r + 1 ) * nGH / 50 )
                nBt := QiPalOf( QiPixGet( nPx, nPy ) )
                cCh := Chr(226) + Chr(150) + Chr(128)
                nF := nT
                nB := nBt
                cKey := "G" + LTrim( Str( nT ) ) + "," + LTrim( Str( nBt ) )
            Else
                cCh := aScr[cell]
                nF := Mod( aAtt[cell], 16 )
                nB := Mod( Int( aAtt[cell] / 16 ), 8 )
                cKey := "T" + cCh + LTrim( Str( nF ) ) + "," + LTrim( Str( nB ) )
            EndIf
            If aLast[cell] != cKey
                aLast[cell] := cKey
                cOut += Chr(27) + "[" + LTrim( Str( r + 1 ) ) + ";" + LTrim( Str( c + 1 ) ) + "H"
                If nF != nEmitF .Or. nB != nEmitB
                    cOut += QiSgrRaw( nF, nB )
                    nEmitF := nF
                    nEmitB := nB
                EndIf
                cOut += cCh
            EndIf
        Next
    Next
    If Len( cOut ) > 0
        ConOutRaw( cOut + Chr(27) + "[" + LTrim( Str( nRow + 1 ) ) + ";" + LTrim( Str( nCol + 1 ) ) + "H" )
        nEmitAtt := -1
    EndIf
Return

// Depuracao: grava o quadro grafico como PPM ASCII (P3), convertido depois para PNG
Static Function QiPngDump( cPath )
    Local aRgb := { { 0,0,0 }, { 0,0,170 }, { 0,170,0 }, { 0,170,170 }, { 170,0,0 }, { 170,0,170 }, { 170,85,0 }, { 170,170,170 }, { 85,85,85 }, { 85,85,255 }, { 85,255,85 }, { 85,255,255 }, { 255,85,85 }, { 255,85,255 }, { 255,255,85 }, { 255,255,255 } }
    Local h := FCreate( cPath )
    Local y := 0
    Local x := 0
    Local c := 0
    Local cLn := ""
    If h < 0
        Return
    EndIf
    FWrite( h, "P3" + Chr(10) + LTrim( Str( nGW ) ) + " " + LTrim( Str( nGH ) ) + Chr(10) + "255" + Chr(10) )
    For y := 0 To nGH - 1
        cLn := ""
        For x := 0 To nGW - 1
            c := QiPalOf( aPix[y*nGW + x + 1] )
            cLn += LTrim( Str( aRgb[c+1][1] ) ) + " " + LTrim( Str( aRgb[c+1][2] ) ) + " " + LTrim( Str( aRgb[c+1][3] ) ) + " "
        Next
        FWrite( h, cLn + Chr(10) )
    Next
    FClose( h )
Return

// Arredonda para inteiro (QBasic arredonda coordenadas)
Static Function QiRnd( v )
    Local r := 0
    If ValType( v ) != "N"
        QiErr( "Type mismatch" )
        Return 0
    EndIf
    If v >= 0
        r := Int( v + 0.5 )
    Else
        r := -Int( -v + 0.5 )
    EndIf
Return r

Static Function QiPix( x, y, c )
    If nMode == 0 .Or. x < 0 .Or. y < 0 .Or. x >= nGW .Or. y >= nGH
        Return
    EndIf
    aPix[y*nGW + x + 1] := c
    lDirty := .T.
Return

// Cor do pixel, ou -1 fora da tela
Static Function QiPixGet( x, y )
    If nMode == 0 .Or. x < 0 .Or. y < 0 .Or. x >= nGW .Or. y >= nGH
        Return -1
    EndIf
Return aPix[y*nGW + x + 1]

// Coordenada (x, y) com STEP opcional (relativa ao ultimo ponto)
Static Function QiPoint()
    Local lRel := .F.
    Local x := 0
    Local y := 0
    If QiTokIs( "W", "STEP" )
        nTP := nTP + 1
        lRel := .T.
    EndIf
    If !QiTokIs( "O", "(" )
        QiErr( "Syntax error" )
        Return { 0, 0 }
    EndIf
    nTP := nTP + 1
    x := QiExpr()
    If !QiTokIs( "O", "," )
        QiErr( "Syntax error" )
        Return { 0, 0 }
    EndIf
    nTP := nTP + 1
    y := QiExpr()
    If !QiTokIs( "O", ")" )
        QiErr( "Syntax error" )
        Return { 0, 0 }
    EndIf
    nTP := nTP + 1
    If lRel
        x := x + nGx
        y := y + nGy
    EndIf
Return { QiRnd( x ), QiRnd( y ) }

// Consome uma virgula opcional; .T. se havia
Static Function QiComma()
    Local lR := .F.
    If QiTokIs( "O", "," )
        nTP := nTP + 1
        lR := .T.
    EndIf
Return lR

Static Function QiPsetStmt( aSt, lReset )
    Local aP := {}
    Local c := 0
    aTok := aSt
    nTP := 2
    aP := QiPoint()
    If !Empty( cErr )
        Return
    EndIf
    c := nFg
    If lReset
        c := nBg
    EndIf
    If QiComma()
        c := QiExpr()
    EndIf
    If !Empty( cErr )
        Return
    EndIf
    QiPix( aP[1], aP[2], Int( c ) )
    nGx := aP[1]
    nGy := aP[2]
Return

// Segmento de reta (Bresenham)
Static Function QiLineDraw( x1, y1, x2, y2, c )
    Local dx := Abs( x2 - x1 )
    Local dy := -Abs( y2 - y1 )
    Local sx := 1
    Local sy := 1
    Local e := 0
    Local e2 := 0
    Local x := x1
    Local y := y1
    If x1 > x2
        sx := -1
    EndIf
    If y1 > y2
        sy := -1
    EndIf
    e := dx + dy
    While .T.
        QiPix( x, y, c )
        If x == x2 .And. y == y2
            Exit
        EndIf
        e2 := 2 * e
        If e2 >= dy
            e := e + dy
            x := x + sx
        EndIf
        If e2 <= dx
            e := e + dx
            y := y + sy
        EndIf
    EndDo
Return

// Retangulo: lFill .T. preenche (BF), .F. so contorno (B)
Static Function QiBox( x1, y1, x2, y2, c, lFill )
    Local xa := x1
    Local xb := x2
    Local ya := y1
    Local yb := y2
    Local x := 0
    Local y := 0
    If xa > xb
        xa := x2
        xb := x1
    EndIf
    If ya > yb
        ya := y2
        yb := y1
    EndIf
    If lFill
        For y := ya To yb
            For x := xa To xb
                QiPix( x, y, c )
            Next
        Next
    Else
        QiLineDraw( xa, ya, xb, ya, c )
        QiLineDraw( xa, yb, xb, yb, c )
        QiLineDraw( xa, ya, xa, yb, c )
        QiLineDraw( xb, ya, xb, yb, c )
    EndIf
Return

// LINE [(x1,y1)|STEP] -(x2,y2) [, cor [, B|BF]]
Static Function QiLineStmt( aSt )
    Local aA := { 0, 0 }
    Local aB := { 0, 0 }
    Local lHas := .F.
    Local c := 0
    Local cBox := ""
    aTok := aSt
    nTP := 2
    If QiTokIs( "W", "STEP" ) .Or. QiTokIs( "O", "(" )
        aA := QiPoint()
        lHas := .T.
    EndIf
    If !QiTokIs( "O", "-" )
        QiErr( "Syntax error" )
        Return
    EndIf
    nTP := nTP + 1
    aB := QiPoint()
    If !Empty( cErr )
        Return
    EndIf
    c := nFg
    If QiComma()
        If !QiTokIs( "O", "," )
            c := QiExpr()
        EndIf
        If QiComma()
            If QiTT() == "W"
                cBox := QiTV()
                nTP := nTP + 1
            EndIf
        EndIf
    EndIf
    If !lHas
        aA := { nGx, nGy }
    EndIf
    If !Empty( cErr )
        Return
    EndIf
    If cBox == "BF"
        QiBox( aA[1], aA[2], aB[1], aB[2], Int( c ), .T. )
    ElseIf cBox == "B"
        QiBox( aA[1], aA[2], aB[1], aB[2], Int( c ), .F. )
    Else
        QiLineDraw( aA[1], aA[2], aB[1], aB[2], Int( c ) )
    EndIf
    nGx := aB[1]
    nGy := aB[2]
Return

// CIRCLE [STEP] (x,y), raio [, cor [, inicio [, fim [, aspecto]]]]
// Angulos em radianos, anti-horario a partir de 3 horas. Aspecto default 4/3 * H/W.
Static Function QiCircleStmt( aSt )
    Local aC := { 0, 0 }
    Local vR := 0
    Local c := 0
    Local vS := 0
    Local vE := 6.28318530718
    Local vAsp := 0
    Local ry := 0
    Local nN := 0
    Local i := 0
    Local t := 0
    Local x := 0
    Local y := 0
    aTok := aSt
    nTP := 2
    aC := QiPoint()
    If !QiComma()
        QiErr( "Syntax error" )
        Return
    EndIf
    vR := QiExpr()
    If !Empty( cErr )
        Return
    EndIf
    If nMode == 0 .Or. vR < 0
        QiErr( "Illegal function call" )
        Return
    EndIf
    c := nFg
    vAsp := ( 4 / 3 ) * nGH / nGW
    If QiComma()
        If !QiTokIs( "O", "," )
            c := QiExpr()
        EndIf
        If QiComma()
            If !QiTokIs( "O", "," )
                vS := QiExpr()
            EndIf
            If QiComma()
                If !QiTokIs( "O", "," )
                    vE := QiExpr()
                EndIf
                If QiComma()
                    vAsp := QiExpr()
                EndIf
            EndIf
        EndIf
    EndIf
    If !Empty( cErr )
        Return
    EndIf
    ry := vR * vAsp
    nN := Int( 2 * 3.14159265 * vR * 2 ) + 8
    For i := 0 To nN
        t := vS + ( vE - vS ) * i / nN
        x := aC[1] + vR * Cos( t )
        y := aC[2] - ry * Sin( t )
        QiPix( QiRnd( x ), QiRnd( y ), Int( c ) )
    Next
    nGx := aC[1]
    nGy := aC[2]
Return

// Preenchimento de regiao limitada pela cor de contorno (pilha, sem recursao)
Static Function QiFlood( x0, y0, cFill, cBorder )
    Local t := QiPixGet( x0, y0 )
    Local nTot := 0
    Local aVis := {}
    Local aStk := {}
    Local nSp := 0
    Local idx := 0
    Local px := 0
    Local py := 0
    Local k := 0
    If t < 0 .Or. t == cBorder .Or. t == cFill
        Return
    EndIf
    nTot := nGW * nGH
    aVis := Array( nTot )
    aStk := Array( nTot )
    For k := 1 To nTot
        aVis[k] := .F.
    Next
    idx := y0 * nGW + x0 + 1
    aVis[idx] := .T.
    nSp := 1
    aStk[1] := idx
    While nSp > 0
        idx := aStk[nSp]
        nSp := nSp - 1
        aPix[idx] := cFill
        px := Mod( idx - 1, nGW )
        py := Int( ( idx - 1 ) / nGW )
        If px > 0
            nSp := QiFlPush( idx - 1, aVis, aStk, nSp, cBorder )
        EndIf
        If px < nGW - 1
            nSp := QiFlPush( idx + 1, aVis, aStk, nSp, cBorder )
        EndIf
        If py > 0
            nSp := QiFlPush( idx - nGW, aVis, aStk, nSp, cBorder )
        EndIf
        If py < nGH - 1
            nSp := QiFlPush( idx + nGW, aVis, aStk, nSp, cBorder )
        EndIf
    EndDo
    lDirty := .T.
Return

Static Function QiFlPush( n, aVis, aStk, nSp, cBorder )
    If !aVis[n] .And. aPix[n] != cBorder
        aVis[n] := .T.
        nSp := nSp + 1
        aStk[nSp] := n
    EndIf
Return nSp

// PAINT [STEP] (x,y) [, cor [, contorno]]
Static Function QiPaintStmt( aSt )
    Local aP := { 0, 0 }
    Local c := 0
    Local cb := 0
    aTok := aSt
    nTP := 2
    aP := QiPoint()
    If !Empty( cErr )
        Return
    EndIf
    c := nFg
    cb := nFg
    If QiComma()
        If !QiTokIs( "O", "," )
            c := QiExpr()
        EndIf
        cb := c
        If QiComma()
            cb := QiExpr()
        EndIf
    EndIf
    If !Empty( cErr ) .Or. nMode == 0
        Return
    EndIf
    QiFlood( aP[1], aP[2], Int( c ), Int( cb ) )
Return

// Operacao bit a bit sobre cores de 8 bits: X xor, A and, O or
Static Function QiBitOp( a, b, cOp )
    Local r := 0
    Local k := 0
    Local pw := 1
    Local ba := 0
    Local bb := 0
    Local bit := 0
    Local x := Int( a )
    Local y := Int( b )
    For k := 1 To 8
        ba := Mod( x, 2 )
        bb := Mod( y, 2 )
        If cOp == "X"
            bit := Mod( ba + bb, 2 )
        ElseIf cOp == "A"
            bit := ba * bb
        Else
            bit := 0
            If ba + bb > 0
                bit := 1
            EndIf
        EndIf
        r := r + bit * pw
        x := Int( x / 2 )
        y := Int( y / 2 )
        pw := pw * 2
    Next
Return r

// GET (x1,y1)-(x2,y2), nome : guarda {largura, altura, pixels}
Static Function QiGetStmt( aSt )
    Local aA := { 0, 0 }
    Local aB := { 0, 0 }
    Local t := {}
    Local x0 := 0
    Local x1 := 0
    Local y0 := 0
    Local y1 := 0
    Local w := 0
    Local h := 0
    Local i := 0
    Local j := 0
    Local aPx := {}
    Local v := 0
    aTok := aSt
    nTP := 2
    aA := QiPoint()
    If !QiTokIs( "O", "-" )
        QiErr( "Syntax error" )
        Return
    EndIf
    nTP := nTP + 1
    aB := QiPoint()
    If !QiComma()
        QiErr( "Syntax error" )
        Return
    EndIf
    t := QiTarget()
    If !Empty( cErr )
        Return
    EndIf
    x0 := aA[1]
    x1 := aB[1]
    If x0 > x1
        x0 := aB[1]
        x1 := aA[1]
    EndIf
    y0 := aA[2]
    y1 := aB[2]
    If y0 > y1
        y0 := aB[2]
        y1 := aA[2]
    EndIf
    w := x1 - x0 + 1
    h := y1 - y0 + 1
    aPx := Array( w * h )
    For j := 0 To h - 1
        For i := 0 To w - 1
            v := QiPixGet( x0 + i, y0 + j )
            If v < 0
                v := 0
            EndIf
            aPx[j*w + i + 1] := v
        Next
    Next
    If Len( t[2] ) > 0
        QiElemOf( t[1], t[2], .T., { w, h, aPx } )
    Else
        QiVarSet( t[1], { w, h, aPx } )
    EndIf
Return

// PUT (x,y), nome [, PSET|PRESET|XOR|AND|OR]  (padrao XOR)
Static Function QiPutStmt( aSt )
    Local aA := { 0, 0 }
    Local t := {}
    Local aBlk := {}
    Local cAct := "X"
    Local cWord := ""
    Local w := 0
    Local h := 0
    Local i := 0
    Local j := 0
    Local src := 0
    Local dst := 0
    Local res := 0
    Local x := 0
    Local y := 0
    aTok := aSt
    nTP := 2
    aA := QiPoint()
    If !QiComma()
        QiErr( "Syntax error" )
        Return
    EndIf
    t := QiTarget()
    If QiComma()
        If QiTT() == "W"
            cWord := QiTV()
            nTP := nTP + 1
            If cWord == "PSET"
                cAct := "P"
            ElseIf cWord == "PRESET"
                cAct := "N"
            ElseIf cWord == "AND"
                cAct := "A"
            ElseIf cWord == "OR"
                cAct := "O"
            EndIf
        EndIf
    EndIf
    aBlk := QiVarOrElem( t[1], t[2] )
    If !Empty( cErr )
        Return
    EndIf
    If ValType( aBlk ) != "A" .Or. Len( aBlk ) != 3
        QiErr( "Type mismatch" )
        Return
    EndIf
    w := aBlk[1]
    h := aBlk[2]
    For j := 0 To h - 1
        For i := 0 To w - 1
            x := aA[1] + i
            y := aA[2] + j
            dst := QiPixGet( x, y )
            If dst >= 0
                src := aBlk[3][j*w + i + 1]
                If cAct == "P"
                    res := src
                ElseIf cAct == "N"
                    res := 15 - src
                Else
                    res := QiBitOp( dst, src, cAct )
                EndIf
                QiPix( x, y, res )
            EndIf
        Next
    Next
Return

// PALETTE attr, cor  (sem argumentos: restaura paleta padrao)
Static Function QiPaletteStmt( aSt )
    Local vA := -1
    Local vC := -1
    Local k := 0
    aTok := aSt
    nTP := 2
    If Len( aPal ) != 16
        Return
    EndIf
    If nTP > Len( aTok )
        For k := 1 To 16
            aPal[k] := k - 1
        Next
        Return
    EndIf
    vA := QiExpr()
    If QiComma()
        vC := QiExpr()
    EndIf
    If !Empty( cErr )
        Return
    EndIf
    If vA >= 0 .And. vA < 16 .And. vC >= 0 .And. vC < 16
        aPal[Int( vA ) + 1] := Int( vC )
    EndIf
Return

// SLEEP [segundos]: sem argumento espera uma tecla (so no terminal)
Static Function QiSleepStmt( aSt )
    Local vS := 0
    Local cK := ""
    aTok := aSt
    nTP := 2
    QiGfxFlush()
    If nTP > Len( aTok )
        If lTTY
            cK := ""
            While cK == ""
                cK := QiInkey()
            EndDo
        EndIf
        Return
    EndIf
    vS := QiExpr()
    If Empty( cErr ) .And. vS > 0
        ProcRun( "bash", { "-c", "sleep " + LTrim( Str( vS ) ) } )
    EndIf
Return

// SOUND freq, duracao (ticks de 1/18.2 s)
Static Function QiSoundStmt( aSt )
    Local vF := 0
    Local vD := 0
    aTok := aSt
    nTP := 2
    vF := QiExpr()
    If !QiComma()
        QiErr( "Syntax error" )
        Return
    EndIf
    vD := QiExpr()
    If !Empty( cErr )
        Return
    EndIf
    If vF >= 32767
        vF := 0
    EndIf
    QiPlaySeg( { { Int( vF ), Int( vD / 18.2 * 8000 ) } } )
Return

// PLAY "notacao": converte para segmentos {frequencia, amostras}
Static Function QiPlayStmt( aSt )
    aTok := aSt
    nTP := 2
    If QiTT() != "S"
        QiErr( "Syntax error" )
        Return
    EndIf
    QiPlaySeg( QiMml( Upper( QiTV() ) ) )
Return

// Le numero inteiro em cM a partir de i: {valor, proxima_posicao}
Static Function QiMmlNum( cM, i )
    Local nV := 0
    Local lHas := .F.
    Local cC := ""
    While i <= Len( cM )
        cC := SubStr( cM, i, 1 )
        If At( cC, "0123456789" ) == 0
            Exit
        EndIf
        nV := nV * 10 + ( Asc( cC ) - 48 )
        i := i + 1
        lHas := .T.
    EndDo
    If !lHas
        nV := 0
    EndIf
Return { nV, i }

// Interpreta a string de PLAY (MML do QBasic)
Static Function QiMml( cM )
    Local aSeg := {}
    Local nOct := 4
    Local nLen := 4
    Local nTempo := 120
    Local nLeg := 0.875
    Local i := 1
    Local n := Len( cM )
    Local cC := ""
    Local nSemi := 0
    Local nIdx := 0
    Local aNum := {}
    Local nNL := 0
    Local nTot := 0
    Local nAdd := 0
    Local nS := 0
    Local nF := 0
    Local aSemi := { 0, 2, 4, 5, 7, 9, 11 }
    Local lPause := .F.
    Local nSnd := 0
    Local nRst := 0
    While i <= n
        cC := SubStr( cM, i, 1 )
        i := i + 1
        nIdx := At( cC, "CDEFGAB" )
        lPause := .F.
        If nIdx > 0 .Or. cC == "P" .Or. cC == "N"
            If nIdx > 0
                nSemi := aSemi[nIdx]
                If i <= n
                    If SubStr( cM, i, 1 ) == "#" .Or. SubStr( cM, i, 1 ) == "+"
                        nSemi := nSemi + 1
                        i := i + 1
                    ElseIf SubStr( cM, i, 1 ) == "-"
                        nSemi := nSemi - 1
                        i := i + 1
                    EndIf
                EndIf
                // O do QBASIC: "O2" e o C4 (261 Hz) padrao, por isso a oitava padrao e somada a 2
                nF := 440 * Exp( Log( 2 ) * ( ( nOct + 2 ) * 12 + nSemi - 57 ) / 12 )
            ElseIf cC == "P"
                lPause := .T.
            Else
                aNum := QiMmlNum( cM, i )
                i := aNum[2]
                nF := 0
                If aNum[1] > 0
                    nF := 440 * Exp( Log( 2 ) * ( aNum[1] - 1 - 57 ) / 12 )
                Else
                    lPause := .T.
                EndIf
            EndIf
            aNum := QiMmlNum( cM, i )
            i := aNum[2]
            nNL := nLen
            If aNum[1] > 0
                nNL := aNum[1]
            EndIf
            nTot := ( 240 / nTempo ) / nNL
            nAdd := nTot / 2
            While i <= n .And. SubStr( cM, i, 1 ) == "."
                nTot := nTot + nAdd
                nAdd := nAdd / 2
                i := i + 1
            EndDo
            If lPause
                AAdd( aSeg, { 0, Int( nTot * 8000 ) } )
            Else
                nS := Int( nTot * nLeg * 8000 )
                nRst := Int( nTot * 8000 ) - nS
                AAdd( aSeg, { Int( nF ), nS } )
                If nRst > 0
                    AAdd( aSeg, { 0, nRst } )
                EndIf
            EndIf
        ElseIf cC == "O"
            aNum := QiMmlNum( cM, i )
            i := aNum[2]
            nOct := aNum[1]
        ElseIf cC == ">"
            nOct := nOct + 1
        ElseIf cC == "<"
            nOct := nOct - 1
        ElseIf cC == "L"
            aNum := QiMmlNum( cM, i )
            i := aNum[2]
            If aNum[1] > 0
                nLen := aNum[1]
            EndIf
        ElseIf cC == "T"
            aNum := QiMmlNum( cM, i )
            i := aNum[2]
            If aNum[1] > 0
                nTempo := aNum[1]
            EndIf
        ElseIf cC == "M"
            If i <= n
                cC := SubStr( cM, i, 1 )
                i := i + 1
                If cC == "N"
                    nLeg := 0.875
                ElseIf cC == "L"
                    nLeg := 1
                ElseIf cC == "S"
                    nLeg := 0.75
                EndIf
            EndIf
        EndIf
    EndDo
Return aSeg

// Toca os segmentos: sem QB_SOUNDLOG, gera PCM 8 kHz e chama aplay (se existir)
Static Function QiPlaySeg( aSeg )
    Local k := 0
    Local cBase := ""
    Local h := -1
    If Len( aSeg ) == 0
        Return
    EndIf
    If QiEnv( "QB_SOUNDLOG" ) == "1"
        For k := 1 To Len( aSeg )
            ConOutRaw( "SOUND " + LTrim( Str( aSeg[k][1] ) ) + " " + LTrim( Str( aSeg[k][2] ) ) + Chr(10) )
        Next
        Return
    EndIf
    cBase := "/tmp/qbi_snd_" + LTrim( Str( Int( Seconds() * 1000 ) ) )
    h := FCreate( cBase + ".hex" )
    If h < 0
        Return
    EndIf
    For k := 1 To Len( aSeg )
        QiWriteTone( h, aSeg[k][1], aSeg[k][2] )
    Next
    FClose( h )
    ProcRun( "bash", { "-c", "command -v aplay >/dev/null 2>&1 && xxd -r -p " + cBase + ".hex > " + cBase + ".raw && aplay -q -t raw -f U8 -r 8000 -c 1 " + cBase + ".raw; rm -f " + cBase + ".hex " + cBase + ".raw" } )
Return

// Amostras U8 (8 kHz) de uma onda quadrada suave (senoide), em hexadecimal
Static Function QiWriteTone( h, nFreq, nN )
    Local cHx := "0123456789abcdef"
    Local cBuf := ""
    Local i := 0
    Local v := 128
    For i := 1 To nN
        v := 128
        If nFreq > 0
            v := 128 + Int( 100 * Sin( 6.28318530718 * nFreq * i / 8000 ) )
        EndIf
        cBuf += SubStr( cHx, Int( v / 16 ) + 1, 1 ) + SubStr( cHx, Mod( v, 16 ) + 1, 1 )
        If Len( cBuf ) >= 2048
            FWrite( h, cBuf )
            cBuf := ""
        EndIf
    Next
    If Len( cBuf ) > 0
        FWrite( h, cBuf )
    EndIf
Return

// Terminal: detecta tty; em tty o teclado fica em modo raw (leitura sem bloqueio)
Static Function QiIsTTY()
    Local nRc := ProcRun( "bash", { "-c", "stty -g </dev/tty >/dev/null 2>&1" } )
Return nRc == 0

Static Function QiTermInit()
    ProcRun( "bash", { "-c", "stty -g </dev/tty" }, {|c| cSttySave := AllTrim( c ) } )
    ProcRun( "bash", { "-c", "stty raw -echo min 0 time 0 </dev/tty" } )
    ConOutRaw( Chr(27) + "[0m" + Chr(27) + "[2J" + Chr(27) + "[H" )
    nEmitAtt := -1
Return

Static Function QiTermRestore()
    If lTTY
        ConOutRaw( Chr(27) + "[0m" + Chr(27) + "[?25h" )
        If !Empty( cSttySave )
            ProcRun( "bash", { "-c", 'stty "' + cSttySave + '" </dev/tty' } )
        EndIf
    EndIf
Return

// Leitura de linha bloqueante (min 1) ou nao bloqueante (min 0)
Static Function QiTermMode( lBlock )
    If lTTY
        If lBlock
            ProcRun( "bash", { "-c", "stty min 1 time 0 </dev/tty" } )
        Else
            ProcRun( "bash", { "-c", "stty min 0 time 0 </dev/tty" } )
        EndIf
    EndIf
Return

// INKEY$: tecla pendente ou "". Setas viram CHR$(0)+H/P/K/M (como no QBasic).
// Byte seguinte a um ESC. FReadStr bloqueia sem dado, entao em tty o byte e
// lido com timeout (50 ms) pelo bash: ESC isolado vira Chr(27) sem esperar tecla.
Static Function QiPeekByte()
    Local aGot := {}
    Local cCmd := ""
    If !lTTY
        Return FReadStr( hIn, 1 )
    EndIf
    cCmd := "IFS= read -rsn1 -t 0.05 k </dev/tty && printf 'K%s\n' " + Chr(34) + "$k" + Chr(34)
    ProcRun( "bash", { "-c", cCmd }, {|c| AAdd( aGot, c ) } )
    If Len( aGot ) > 0 .And. Left( aGot[1], 1 ) == "K"
        Return SubStr( aGot[1], 2, 1 )
    EndIf
Return ""

Static Function QiInkey()
    Local cCh := ""
    Local cNx := ""
    Local cPar := ""
    QiGfxFlush()
    nInkCount := nInkCount + 1
    If nMode != 0 .And. !Empty( QiEnv( "QB_PNG" ) ) .And. nInkCount == Val( QiEnv( "QB_PNG_AT" ) )
        QiPngDump( QiEnv( "QB_PNG" ) )
    EndIf
    If hIn < 0
        hIn := FOpen( "/dev/stdin" )
    EndIf
    If hIn < 0
        Return ""
    EndIf
    If cPend != ""
        cCh := cPend
        cPend := ""
    Else
        cCh := FReadStr( hIn, 1 )
    EndIf
    If cCh == ""
        Return ""
    EndIf
    If cCh == Chr(27)
        cNx := QiPeekByte()
        If cNx == ""
            Return Chr(27)
        EndIf
        If cNx != "[" .And. cNx != "O"
            // ESC isolado seguido de outra tecla: devolve a outra tecla a fila
            cPend := cNx
            Return Chr(27)
        EndIf
        If cNx == "O"
            cNx := FReadStr( hIn, 1 )
            If cNx == "P"
                Return Chr(0) + ";"
            ElseIf cNx == "Q"
                Return Chr(0) + "<"
            ElseIf cNx == "R"
                Return Chr(0) + "="
            ElseIf cNx == "S"
                Return Chr(0) + ">"
            EndIf
            Return ""
        EndIf
        If cNx == "["
            cNx := FReadStr( hIn, 1 )
            While !cNx == "" .And. At( cNx, "0123456789;" ) > 0
                cPar += cNx
                cNx := FReadStr( hIn, 1 )
            EndDo
            If cPar == "1;2"
                // Shift+seta: selecao no editor
                If cNx == "A"
                    Return Chr(1) + "H"
                ElseIf cNx == "B"
                    Return Chr(1) + "P"
                ElseIf cNx == "C"
                    Return Chr(1) + "M"
                ElseIf cNx == "D"
                    Return Chr(1) + "K"
                EndIf
                Return ""
            EndIf
            If cNx == "A"
                Return Chr(0) + "H"
            ElseIf cNx == "B"
                Return Chr(0) + "P"
            ElseIf cNx == "C"
                Return Chr(0) + "M"
            ElseIf cNx == "D"
                Return Chr(0) + "K"
            ElseIf cNx == "H"
                Return Chr(0) + "G"
            ElseIf cNx == "F"
                Return Chr(0) + "O"
            ElseIf cNx == "~"
                If cPar == "1" .Or. cPar == "7"
                    Return Chr(0) + "G"
                ElseIf cPar == "4" .Or. cPar == "8"
                    Return Chr(0) + "O"
                ElseIf cPar == "3"
                    Return Chr(0) + "S"
                ElseIf cPar == "5"
                    Return Chr(0) + "I"
                ElseIf cPar == "6"
                    Return Chr(0) + "Q"
                ElseIf cPar == "11"
                    Return Chr(0) + ";"
                ElseIf cPar == "12"
                    Return Chr(0) + "<"
                ElseIf cPar == "13"
                    Return Chr(0) + "="
                ElseIf cPar == "14"
                    Return Chr(0) + ">"
                ElseIf cPar == "15"
                    Return Chr(0) + "?"
                ElseIf cPar == "17"
                    Return Chr(0) + "@"
                ElseIf cPar == "18"
                    Return Chr(0) + "A"
                ElseIf cPar == "19"
                    Return Chr(0) + "B"
                ElseIf cPar == "20"
                    Return Chr(0) + "C"
                ElseIf cPar == "21"
                    Return Chr(0) + "D"
                EndIf
            EndIf
            Return ""
        EndIf
        Return ""
    EndIf
    If cCh == Chr(127)
        Return Chr(8)
    EndIf
Return cCh

// Reproduz o buffer de tela (linhas sem espacos a direita) quando QB_DUMP=1
Static Function QiDump()
    Local r := 0
    Local c := 0
    Local cLn := ""
    If QiEnv( "QB_DUMP" ) == "1"
        For r := 0 To 24
            cLn := ""
            For c := 1 To 80
                cLn += aScr[r*80+c]
            Next
            ConOutRaw( RTrim( cLn ) + Chr(10) )
        Next
    ElseIf QiEnv( "QB_DUMP" ) == "2"
        // atributos no mesmo formato do oraculo: STR$(atributo) + "," por celula
        For r := 0 To 24
            cLn := ""
            For c := 1 To 80
                cLn += " " + LTrim( Str( aAtt[r*80+c] ) ) + ","
            Next
            ConOutRaw( cLn + Chr(10) )
        Next
    EndIf
Return

// ---------------------------------------------------------------------------
// Memoria: enderecos linear em B800 mapeiam para o buffer de tela
// ---------------------------------------------------------------------------

Static Function QiVidIdx( nLin )
    Local nV := nLin - 753664
    If nV < 0 .Or. nV > 3999
        nV := -1
    EndIf
Return nV

Static Function QiMemRead( nLin )
    Local nV := QiVidIdx( nLin )
    Local nCell := 0
    If nV >= 0
        nCell := Int( nV / 2 ) + 1
        If Mod( nV, 2 ) == 0
            Return Asc( aScr[nCell] )
        EndIf
        Return aAtt[nCell]
    EndIf
    QiMemInit()
Return aMem[Mod( nLin, 65536 ) + 1]

Static Function QiMemWrite( nLin, nVal )
    Local nV := QiVidIdx( nLin )
    Local nCell := 0
    If nV >= 0
        nCell := Int( nV / 2 ) + 1
        If Mod( nV, 2 ) == 0
            aScr[nCell] := Chr( nVal )
        Else
            aAtt[nCell] := nVal
        EndIf
        QiVidDraw( nCell )
        Return
    EndIf
    QiMemInit()
    aMem[Mod( nLin, 65536 ) + 1] := nVal
Return

// Desenha a celula alterada por POKE no terminal e volta o cursor
Static Function QiVidDraw( nCell )
    Local r := Int( ( nCell - 1 ) / 80 )
    Local c := Mod( nCell - 1, 80 )
    If lTTY
        ConOutRaw( Chr(27) + "[" + LTrim( Str( r + 1 ) ) + ";" + LTrim( Str( c + 1 ) ) + "H" + QiSgr( aAtt[nCell] ) + aScr[nCell] )
        ConOutRaw( Chr(27) + "[" + LTrim( Str( nRow + 1 ) ) + ";" + LTrim( Str( nCol + 1 ) ) + "H" )
        nEmitAtt := -1
    EndIf
Return

// ---------------------------------------------------------------------------
// DATA, DIM
// ---------------------------------------------------------------------------

Static Function QiRead( aSt )
    Local t := {}
    Local vV := 0
    aTok := aSt
    nTP := 2
    While Empty( cErr ) .And. QiTT() == "W"
        t := QiTarget()
        If nDP > Len( aData )
            QiErr( "Sem mais DATA" )
            Return
        EndIf
        vV := aData[nDP]
        nDP := nDP + 1
        If Right( t[1], 1 ) == "$"
            If ValType( vV ) == "N"
                vV := QiNumTxt( vV )
            EndIf
        Else
            If ValType( vV ) == "C"
                vV := QiVal( vV )
            EndIf
        EndIf
        QiStoreT( t, vV )
        If QiTokIs( "O", "," )
            nTP := nTP + 1
        Else
            Exit
        EndIf
    EndDo
Return

// DIM [SHARED] nome(lo TO hi, ...) [AS tipo], ...
Static Function QiDim( aSt )
    Local lRedim := QiWord( aSt, 1 ) == "REDIM"
    Local cNm := ""
    Local cType := ""
    Local cRec := ""
    Local aSz := {}
    Local aLo := {}
    Local v1 := 0
    Local lo := 0
    Local hi := 0
    Local key := ""
    aTok := aSt
    nTP := 2
    If QiTokIs( "W", "SHARED" ) .Or. QiTokIs( "W", "PRESERVE" )
        nTP := nTP + 1
    EndIf
    While Empty( cErr ) .And. QiTT() == "W"
        cNm := QiTV()
        nTP := nTP + 1
        aSz := {}
        aLo := {}
        If QiTokIs( "O", "(" )
            nTP := nTP + 1
            While Empty( cErr )
                v1 := QiExpr()
                lo := 0
                If QiTokIs( "W", "TO" )
                    nTP := nTP + 1
                    lo := Int( v1 )
                    hi := Int( QiExpr() )
                Else
                    hi := Int( v1 )
                EndIf
                AAdd( aSz, hi - lo + 1 )
                AAdd( aLo, lo )
                If QiTokIs( "O", "," )
                    nTP := nTP + 1
                Else
                    Exit
                EndIf
            EndDo
            If !QiTokIs( "O", ")" )
                QiErr( "Syntax error" )
                Return
            EndIf
            nTP := nTP + 1
        EndIf
        cRec := ""
        If QiTokIs( "W", "AS" )
            nTP := nTP + 1
            cType := QiTV()
            nTP := nTP + 1
            If AScan( aTypeName, cType ) > 0
                cRec := cType
            EndIf
        EndIf
        key := QiKey( cNm )
        If AScan( aVN, key ) > 0 .And. !lRedim
            QiErr( "Array already dimensioned" )
            Return
        EndIf
        If Len( aSz ) > 0
            If Len( aLo ) == 1
                QiDimStore( key, QiNewArr( cNm, aSz, cRec ), { cRec, aLo[1], 0 } )
            Else
                QiDimStore( key, QiNewArr( cNm, aSz, cRec ), { cRec, aLo[1], aLo[2] } )
            EndIf
        ElseIf !Empty( cRec )
            QiDimStore( key, QiNewRec( cRec ), { cRec, 0, 0 } )
        Else
            QiDimStore( key, QiDefault( cNm ), { "", 0, 0 } )
        EndIf
        If QiTokIs( "O", "," )
            nTP := nTP + 1
        Else
            Exit
        EndIf
    EndDo
Return

// Cria ou (REDIM) substitui a variavel/array
Static Function QiDimStore( cKey, vV, aMeta )
    Local pos := AScan( aVN, cKey )
    If pos > 0
        aVV[pos] := vV
        aVM[pos] := aMeta
    Else
        QiAddVar( cKey, vV, aMeta )
    EndIf
Return

// ---------------------------------------------------------------------------
// Variaveis, escopo e arrays
// ---------------------------------------------------------------------------

// Chave de escopo: globais usam o proprio nome; variaveis locais de SUB/FUNCTION
// usam "<quadro>|<nome>"; nomes compartilhados (SHARED/CONST) sao sempre globais.
Static Function QiKey( cNm )
    Local nTop := Len( aCall )
    If nTop == 0
        Return cNm
    EndIf
    If AScan( aShr, cNm ) > 0
        Return cNm
    EndIf
Return aCall[nTop][1] + "|" + cNm

Static Function QiKeyId( cId, cNm )
Return cId + "|" + cNm

Static Function QiAddVar( cKey, vV, aMeta )
    AAdd( aVN, cKey )
    AAdd( aVV, vV )
    AAdd( aVM, aMeta )
Return

Static Function QiDefault( cNm )
    Local vR := 0
    If Right( cNm, 1 ) == "$"
        vR := ""
    EndIf
Return vR

Static Function QiGetRaw( cKey, vDef )
    Local pos := AScan( aVN, cKey )
    Local vR := vDef
    If pos > 0
        vR := aVV[pos]
    EndIf
Return vR

Static Function QiVarGet( cNm )
    Local pos := AScan( aVN, QiKey( cNm ) )
    If pos > 0
        Return aVV[pos]
    EndIf
Return QiDefault( cNm )

Static Function QiVarSet( cNm, vV )
    Local key := QiKey( cNm )
    Local pos := AScan( aVN, key )
    If ( Right( cNm, 1 ) == "$" ) != ( ValType( vV ) == "C" )
        QiErr( "Type mismatch" )
        Return .F.
    EndIf
    vV := QiConvT( QiTypeOf( cNm ), vV )
    If pos > 0
        aVV[pos] := vV
    Else
        QiAddVar( key, vV, { "", 0, 0 } )
    EndIf
Return .T.

// Garante o array (auto-DIM 0..10) e devolve a posicao em aVN
Static Function QiEnsureArr( cNm, nDims )
    Local key := QiKey( cNm )
    Local nP := AScan( aVN, key )
    Local aSz := {}
    Local k := 0
    If nP == 0
        For k := 1 To nDims
            AAdd( aSz, 11 )
        Next
        QiAddVar( key, QiNewArr( cNm, aSz, "" ), { "", 0, 0 } )
        nP := Len( aVN )
    EndIf
Return nP

// aSz: quantidade de elementos por dimensao
Static Function QiNewArr( cNm, aSz, cRec )
    Local aA := Array( aSz[1] )
    Local i := 0
    Local j := 0
    If Len( aSz ) == 1
        For i := 1 To Len( aA )
            aA[i] := QiElemDefault( cNm, cRec )
        Next
    Else
        For i := 1 To Len( aA )
            aA[i] := Array( aSz[2] )
            For j := 1 To Len( aA[i] )
                aA[i][j] := QiElemDefault( cNm, cRec )
            Next
        Next
    EndIf
Return aA

Static Function QiElemDefault( cNm, cRec )
    Local vR := 0
    If Empty( cRec )
        vR := QiDefault( cNm )
    Else
        vR := QiNewRec( cRec )
    EndIf
Return vR

// Registro de TYPE: array com um valor por campo, na ordem da definicao
Static Function QiNewRec( cRec )
    Local k := AScan( aTypeName, cRec )
    Local n := 0
    Local arr := {}
    Local j := 0
    If k == 0
        QiErr( "Type not defined: " + cRec )
        Return 0
    EndIf
    n := Len( aTypeFld[k] )
    arr := Array( n )
    For j := 1 To n
        arr[j] := aTypeDef[k][j]
    Next
Return arr

Static Function QiIdx( v )
    If ValType( v ) != "N"
        QiErr( "Type mismatch" )
        Return 0
    EndIf
Return Int( v )

// Leitura (lSet .F.) ou escrita (lSet .T.) de elemento 1D ou 2D, com limites
Static Function QiElemOf( cNm, aIdx, lSet, vVal )
    Local pos := AScan( aVN, QiKey( cNm ) )
    Local arr := 0
    Local meta := {}
    Local i := 0
    Local j := 0
    Local aRow := {}

    If pos == 0
        pos := QiEnsureArr( cNm, Len( aIdx ) )
    EndIf
    arr := aVV[pos]
    meta := aVM[pos]
    If ValType( arr ) != "A"
        QiErr( "Syntax error" )
        Return QiDefault( cNm )
    EndIf
    If Len( aIdx ) == 1
        i := QiIdx( aIdx[1] ) - meta[2]
        If !Empty( cErr )
            Return QiDefault( cNm )
        EndIf
        If i < 0 .Or. i + 1 > Len( arr )
            QiErr( "Subscript out of range" )
            Return QiDefault( cNm )
        EndIf
        If lSet
            If ( Right( cNm, 1 ) == "$" ) != ( ValType( vVal ) == "C" )
                QiErr( "Type mismatch" )
                Return QiDefault( cNm )
            EndIf
            vVal := QiConvT( QiTypeOf( cNm ), vVal )
            arr[i+1] := vVal
            Return vVal
        EndIf
        Return arr[i+1]
    EndIf
    If Len( aIdx ) == 2
        i := QiIdx( aIdx[1] ) - meta[2]
        If !Empty( cErr )
            Return QiDefault( cNm )
        EndIf
        If i < 0 .Or. i + 1 > Len( arr )
            QiErr( "Subscript out of range" )
            Return QiDefault( cNm )
        EndIf
        aRow := arr[i+1]
        j := QiIdx( aIdx[2] ) - meta[3]
        If !Empty( cErr )
            Return QiDefault( cNm )
        EndIf
        If j < 0 .Or. j + 1 > Len( aRow )
            QiErr( "Subscript out of range" )
            Return QiDefault( cNm )
        EndIf
        If lSet
            If ( Right( cNm, 1 ) == "$" ) != ( ValType( vVal ) == "C" )
                QiErr( "Type mismatch" )
                Return QiDefault( cNm )
            EndIf
            vVal := QiConvT( QiTypeOf( cNm ), vVal )
            aRow[j+1] := vVal
            Return vVal
        EndIf
        Return aRow[j+1]
    EndIf
    QiErr( "Syntax error" )
Return QiDefault( cNm )

// ---------------------------------------------------------------------------
// SUB / FUNCTION: chamada, parametros por referencia (copia de volta)
// ---------------------------------------------------------------------------

// CALL nome args  (nName = posicao do nome no comando)
Static Function QiCallStmt( aSt, nName )
    Local cNm := QiWord( aSt, nName )
    Local aA := {}
    Local nD := AScan( aDefName, cNm )
    aTok := aSt
    nTP := nName + 1
    If nD == 0
        QiErr( "Sub not defined: " + cNm )
        Return
    EndIf
    If QiTokIs( "O", "(" )
        aA := QiCallArgs( .T. )
    ElseIf nTP <= Len( aTok )
        aA := QiCallArgs( .F. )
    EndIf
    If Empty( cErr )
        QiCallFlat( cNm, aA )
    EndIf
Return

// CALL de SUB sem recursao: empilha o retorno e salta para o corpo.
// O retorno (END SUB / EXIT SUB) desfaz a copia de parametros. Assim o
// passo a passo e os breakpoints entram dentro da SUB.
Static Function QiCallFlat( cNm, aA )
    Local nD := AScan( aDefName, cNm )
    Local aPar := {}
    Local id := ""
    Local k := 0
    Local aCopy := {}
    Local pos := 0
    If nD == 0
        QiErr( "Sub not defined: " + cNm )
        Return
    EndIf
    aPar := aDefParams[nD]
    If Len( aA ) > Len( aPar )
        QiErr( "Argument-count mismatch" )
        Return
    EndIf
    If aDefStat[nD]
        id := "S:" + cNm
    Else
        nFrameSeq := nFrameSeq + 1
        id := "F" + LTrim( Str( nFrameSeq ) )
    EndIf
    For k := 1 To Len( aPar )
        If k <= Len( aA )
            If aA[k][1] == "A"
                pos := QiEnsureArr( aA[k][3], 1 )
                QiAddVar( QiKeyId( id, aPar[k][1] ), aVV[pos], aVM[pos] )
            Else
                QiAddVar( QiKeyId( id, aPar[k][1] ), aA[k][2], { "", 0, 0 } )
                If aA[k][1] == "R"
                    AAdd( aCopy, { QiKeyId( id, aPar[k][1] ), aA[k][3], 0 } )
                EndIf
            EndIf
        Else
            QiAddVar( QiKeyId( id, aPar[k][1] ), QiDefault( aPar[k][1] ), { "", 0, 0 } )
        EndIf
    Next
    AAdd( aCall, { id, cNm, .F. } )
    AAdd( aRet, { nPC, aCopy } )
    nPC := aDefStart[nD] + 1
    lJmp := .F.
Return

// Retorno de SUB sem recursao (END SUB / EXIT SUB)
Static Function QiFlatRet()
    Local nTop := Len( aRet )
    Local ent := aRet[nTop]
    Local aN := {}
    Local k := 0
    For k := 1 To Len( ent[2] )
        ent[2][k][3] := QiGetRaw( ent[2][k][1], 0 )
    Next
    QiPopCall()
    For k := 1 To nTop - 1
        AAdd( aN, aRet[k] )
    Next
    aRet := aN
    nPC := ent[1]
    lJmp := .T.
    For k := 1 To Len( ent[2] )
        If Empty( cErr )
            QiVarSet( ent[2][k][2], ent[2][k][3] )
        EndIf
    Next
Return

// Lista de argumentos: {tipo, valor, nome}. Tipo: V valor, R variavel (copia de volta), A array inteiro
Static Function QiCallArgs( lParen )
    Local aR := {}
    Local nStart := 0
    Local cK := "V"
    Local v := 0
    Local cNm := ""

    If lParen
        nTP := nTP + 1
        If QiTokIs( "O", ")" )
            nTP := nTP + 1
            Return aR
        EndIf
    EndIf
    While Empty( cErr )
        If QiTT() == "W" .And. QiOpAt( aTok, nTP + 1, "(" ) .And. QiOpAt( aTok, nTP + 2, ")" )
            AAdd( aR, { "A", 0, QiTV() } )
            nTP := nTP + 3
        Else
            nStart := nTP
            v := QiExpr()
            cK := "V"
            cNm := ""
            If nTP == nStart + 1 .And. aTok[nStart][1] == "W"
                cK := "R"
                cNm := aTok[nStart][2]
            EndIf
            AAdd( aR, { cK, v, cNm } )
        EndIf
        If QiTokIs( "O", "," )
            nTP := nTP + 1
        ElseIf lParen .And. QiTokIs( "O", ")" )
            nTP := nTP + 1
            Exit
        ElseIf !lParen
            Exit
        Else
            QiErr( "Syntax error" )
            Exit
        EndIf
    EndDo
Return aR

// Executa SUB/FUNCTION. Retorna o valor (FUNCTION) ou 0.
Static Function QiCallUser( cNm, aA, lFunc )
    Local nD := AScan( aDefName, cNm )
    Local aPar := {}
    Local aSvT := aTok
    Local nSvP := nTP
    Local nSvPc := nPC
    Local lSvJ := lJmp
    Local id := ""
    Local k := 0
    Local nCur := 0
    Local aCopy := {}
    Local vRet := 0
    Local pos := 0

    If nD == 0
        QiErr( "Sub or function not defined: " + cNm )
        Return 0
    EndIf
    aPar := aDefParams[nD]
    If Len( aA ) > Len( aPar )
        QiErr( "Argument-count mismatch" )
        Return 0
    EndIf

    // Argumentos sao resolvidos no escopo do chamador (antes de empilhar o quadro)
    If aDefStat[nD]
        id := "S:" + cNm
    Else
        nFrameSeq := nFrameSeq + 1
        id := "F" + LTrim( Str( nFrameSeq ) )
    EndIf
    For k := 1 To Len( aPar )
        If k <= Len( aA )
            If aA[k][1] == "A"
                pos := QiEnsureArr( aA[k][3], 1 )
                QiAddVar( QiKeyId( id, aPar[k][1] ), aVV[pos], aVM[pos] )
            Else
                QiAddVar( QiKeyId( id, aPar[k][1] ), aA[k][2], { "", 0, 0 } )
                If aA[k][1] == "R"
                    AAdd( aCopy, { QiKeyId( id, aPar[k][1] ), aA[k][3], 0 } )
                EndIf
            EndIf
        Else
            QiAddVar( QiKeyId( id, aPar[k][1] ), QiDefault( aPar[k][1] ), { "", 0, 0 } )
        EndIf
    Next
    If Empty( cErr )
        AAdd( aCall, { id, cNm, lFunc } )
        nPC := aDefStart[nD] + 1
        lJmp := .F.
        lRet := .F.
        While nPC <= Len( aStmt ) .And. !lRet .And. !lStop .And. Empty( cErr )
            nCur := nPC
            nPC := nPC + 1
            lJmp := .F.
                QiExec( aStmt[nCur], nCur )
            If !Empty( cErr )
                If !QiTrap( nCur ) .And. nErrLn == 0
                    nErrLn := aStmtSrc[nCur]
                EndIf
            EndIf
        EndDo
        lRet := .F.
        If lFunc
            vRet := QiGetRaw( QiKeyId( id, cNm ), QiDefault( cNm ) )
        EndIf
        For k := 1 To Len( aCopy )
            aCopy[k][3] := QiGetRaw( aCopy[k][1], 0 )
        Next
        QiPopCall()
    EndIf

    aTok := aSvT
    nTP := nSvP
    nPC := nSvPc
    lJmp := lSvJ
    For k := 1 To Len( aCopy )
        If Empty( cErr )
            QiVarSet( aCopy[k][2], aCopy[k][3] )
        EndIf
    Next
Return vRet

Static Function QiPopCall()
    Local aN := {}
    Local k := 0
    For k := 1 To Len( aCall ) - 1
        AAdd( aN, aCall[k] )
    Next
    aCall := aN
Return

// ---------------------------------------------------------------------------
// Expressoes (precedencia: OR < AND < NOT < relacionais < + - < MOD < \ < * /
//                           < unario - < ^ < primario)
// ---------------------------------------------------------------------------

Static Function QiTT()
    Local cR := ""
    If nTP <= Len( aTok )
        cR := aTok[nTP][1]
    EndIf
Return cR

Static Function QiTV()
    Local xR := ""
    If nTP <= Len( aTok )
        xR := aTok[nTP][2]
    EndIf
Return xR

Static Function QiTokIs( cT, cV )
    Local lR := .F.
    If QiTT() == cT
        If ValType( QiTV() ) == "C"
            lR := QiTV() == cV
        EndIf
    EndIf
Return lR

Static Function QiBool( lB )
    Local vR := 0
    If lB
        vR := -1
    EndIf
Return vR

Static Function QiTruth( v )
    Local lR := .F.
    If ValType( v ) == "C"
        QiErr( "Type mismatch" )
    Else
        lR := v != 0
    EndIf
Return lR

Static Function QiExpr()
    Local vL := QiAnd()
    Local vR := 0
    Local cOp := ""
    While Empty( cErr ) .And. ( QiTokIs( "W", "OR" ) .Or. QiTokIs( "W", "XOR" ) )
        cOp := QiTV()
        nTP := nTP + 1
        vR := QiAnd()
        If cOp == "OR"
            vL := QiBit2( vL, vR, "O" )
        Else
            vL := QiBit2( vL, vR, "X" )
        EndIf
    EndDo
Return vL

Static Function QiAnd()
    Local vL := QiNot()
    Local vR := 0
    While Empty( cErr ) .And. QiTokIs( "W", "AND" )
        nTP := nTP + 1
        vR := QiNot()
        vL := QiBit2( vL, vR, "A" )
    EndDo
Return vL

Static Function QiNot()
    Local vR := 0
    If QiTokIs( "W", "NOT" )
        nTP := nTP + 1
        vR := QiNot()
        If ValType( vR ) != "N"
            QiErr( "Type mismatch" )
            Return 0
        EndIf
        vR := -QiRoundEven( vR ) - 1
        nTy := "L"
        If vR >= -32768 .And. vR <= 32767
            nTy := "I"
        EndIf
        Return vR
    EndIf
Return QiRel()

// Operacao bit a bit entre inteiros: 16 bits se ambos cabem em inteiro, senao 32 bits
Static Function QiBit2( a, b, cOp )
    Local x := QiRoundEven( a )
    Local y := QiRoundEven( b )
    Local nBits := 16
    Local nMod := 65536
    Local u := 0
    Local v := 0
    Local r := 0
    Local pw := 1
    Local k := 0
    Local ba := 0
    Local bb := 0
    Local bt := 0
    If x < -32768 .Or. x > 32767 .Or. y < -32768 .Or. y > 32767
        nBits := 32
        nMod := 4294967296
    EndIf
    If x < 0
        u := x + nMod
    Else
        u := x
    EndIf
    If y < 0
        v := y + nMod
    Else
        v := y
    EndIf
    nTy := "L"
    If nBits == 16
        nTy := "I"
    EndIf
    For k := 1 To nBits
        ba := Mod( u, 2 )
        bb := Mod( v, 2 )
        If cOp == "A"
            bt := ba * bb
        ElseIf cOp == "O"
            bt := 0
            If ba + bb > 0
                bt := 1
            EndIf
        Else
            bt := Mod( ba + bb, 2 )
        EndIf
        r := r + bt * pw
        u := Int( u / 2 )
        v := Int( v / 2 )
        pw := pw * 2
    Next
    If r >= nMod / 2
        r := r - nMod
    EndIf
Return r

Static Function QiRel()
    Local vL := QiAdd()
    Local vR := 0
    Local cOp := ""
    If QiTT() == "O"
        cOp := QiTV()
        If cOp == "=" .Or. cOp == "<>" .Or. cOp == "<" .Or. cOp == ">" .Or. cOp == "<=" .Or. cOp == ">="
            nTP := nTP + 1
            vR := QiAdd()
            vL := QiCmpChk( vL, vR, cOp )
            nTy := "I"
        EndIf
    EndIf
Return vL

Static Function QiCmpChk( a, b, cOp )
    If ValType( a ) != ValType( b )
        QiErr( "Type mismatch" )
        Return 0
    EndIf
Return QiCmp( a, b, cOp )

Static Function QiCmp( a, b, cOp )
    Local lRes := .F.
    If cOp == "="
        lRes := a == b
    ElseIf cOp == "<>"
        lRes := a != b
    ElseIf cOp == "<"
        lRes := a < b
    ElseIf cOp == ">"
        lRes := a > b
    ElseIf cOp == "<="
        lRes := a <= b
    Else
        lRes := a >= b
    EndIf
Return QiBool( lRes )

Static Function QiAdd()
    Local vL := QiMod()
    Local tL := nTy
    Local vR := 0
    Local tR := "S"
    Local cOp := ""
    Local cT := ""
    While Empty( cErr ) .And. QiTT() == "O" .And. ( QiTV() == "+" .Or. QiTV() == "-" )
        cOp := QiTV()
        nTP := nTP + 1
        vR := QiMod()
        tR := nTy
        If cOp == "+"
            If ValType( vL ) == "C" .And. ValType( vR ) == "C"
                vL := vL + vR
                tL := "$"
            ElseIf ValType( vL ) == "N" .And. ValType( vR ) == "N"
                cT := QiCmbT( tL, tR, "+" )
                vL := QiFin( vL + vR, cT )
                tL := cT
            Else
                QiErr( "Type mismatch" )
                Return 0
            EndIf
        Else
            If ValType( vL ) != "N" .Or. ValType( vR ) != "N"
                QiErr( "Type mismatch" )
                Return 0
            EndIf
            cT := QiCmbT( tL, tR, "-" )
            vL := QiFin( vL - vR, cT )
            tL := cT
        EndIf
    EndDo
    nTy := tL
Return vL

Static Function QiMod()
    Local vL := QiIDiv()
    Local tL := nTy
    Local vR := 0
    Local tR := "S"
    Local q := 0
    Local cT := ""
    While Empty( cErr ) .And. QiTokIs( "W", "MOD" )
        nTP := nTP + 1
        vR := QiIDiv()
        tR := nTy
        If ValType( vL ) != "N" .Or. ValType( vR ) != "N"
            QiErr( "Type mismatch" )
            Return 0
        EndIf
        If QiRoundEven( vR ) == 0
            QiErr( "Division by zero" )
            Return 0
        EndIf
        q := TruncInt( QiRoundEven( vL ) / QiRoundEven( vR ) )
        vL := QiRoundEven( vL ) - QiRoundEven( vR ) * q
        cT := QiCmbT( tL, tR, "MOD" )
        tL := cT
    EndDo
    nTy := tL
Return vL

Static Function QiIDiv()
    Local vL := QiMul()
    Local tL := nTy
    Local vR := 0
    Local tR := "S"
    Local cT := ""
    While Empty( cErr ) .And. QiTokIs( "O", "\" )
        nTP := nTP + 1
        vR := QiMul()
        tR := nTy
        If ValType( vL ) != "N" .Or. ValType( vR ) != "N"
            QiErr( "Type mismatch" )
            Return 0
        EndIf
        If QiRoundEven( vR ) == 0
            QiErr( "Division by zero" )
            Return 0
        EndIf
        vL := TruncInt( QiRoundEven( vL ) / QiRoundEven( vR ) )
        cT := QiCmbT( tL, tR, "\" )
        tL := cT
    EndDo
    nTy := tL
Return vL

Static Function QiMul()
    Local vL := QiUnary()
    Local tL := nTy
    Local vR := 0
    Local tR := "S"
    Local cOp := ""
    Local cT := ""
    While Empty( cErr ) .And. QiTT() == "O" .And. ( QiTV() == "*" .Or. QiTV() == "/" )
        cOp := QiTV()
        nTP := nTP + 1
        vR := QiUnary()
        tR := nTy
        If ValType( vL ) != "N" .Or. ValType( vR ) != "N"
            QiErr( "Type mismatch" )
            Return 0
        EndIf
        cT := QiCmbT( tL, tR, cOp )
        If cOp == "*"
            vL := QiFin( vL * vR, cT )
        Else
            If vR == 0
                QiErr( "Division by zero" )
                Return 0
            EndIf
            vL := QiFin( vL / vR, cT )
        EndIf
        tL := cT
    EndDo
    nTy := tL
Return vL

Static Function QiUnary()
    Local vR := 0
    If QiTokIs( "O", "-" )
        nTP := nTP + 1
        vR := QiUnary()
        If ValType( vR ) != "N"
            QiErr( "Type mismatch" )
            Return 0
        EndIf
        Return -vR
    EndIf
    If QiTokIs( "O", "+" )
        nTP := nTP + 1
        Return QiUnary()
    EndIf
Return QiPow()

Static Function QiPow()
    Local vL := QiPrim()
    Local tL := nTy
    Local vR := 0
    Local tR := "S"
    Local cT := ""
    While Empty( cErr ) .And. QiTokIs( "O", "^" )
        nTP := nTP + 1
        vR := QiPrim()
        tR := nTy
        cT := QiCmbT( tL, tR, "^" )
        vL := QiFin( QiPowN( vL, vR ), cT )
        tL := cT
    EndDo
    nTy := tL
Return vL

Static Function QiPowN( a, b )
    Local vR := 1
    Local k := 0
    If ValType( a ) != "N" .Or. ValType( b ) != "N"
        QiErr( "Type mismatch" )
        Return 0
    EndIf
    If b == Int( b ) .And. b >= 0
        For k := 1 To b
            vR := vR * a
        Next
        Return vR
    EndIf
    If a < 0
        QiErr( "Illegal function call" )
        Return 0
    EndIf
    If a == 0
        Return 0
    EndIf
Return Exp( b * Log( a ) )

// Primario: numero, string, (expr), funcao/SUB, variavel, elemento e campo
Static Function QiPrim()
    Local vR := 0
    Local cNm := ""
    Local aA := {}
    Local nD := 0
    Local fi := 0
    Local cFld := ""

    If QiTT() == "N"
        vR := QiTV()
        nTy := aTok[nTP][3]
        nTP := nTP + 1
    ElseIf QiTT() == "S"
        vR := QiTV()
        nTy := "$"
        nTP := nTP + 1
    ElseIf QiTokIs( "O", "(" )
        nTP := nTP + 1
        vR := QiExpr()
        If !QiTokIs( "O", ")" )
            QiErr( "Syntax error" )
            Return 0
        EndIf
        nTP := nTP + 1
    ElseIf QiTT() == "W"
        cNm := QiTV()
        nTP := nTP + 1
        If AScan( aFnName, cNm ) > 0
            If QiTokIs( "O", "(" )
                aA := QiArgs()
            EndIf
            Return QiCallDefFn( cNm, aA )
        EndIf
        If cNm == "LBOUND" .Or. cNm == "UBOUND"
            Return QiBoundOf( cNm == "LBOUND" )
        EndIf
        nD := AScan( aDefName, cNm )
        If nD > 0 .And. aDefKind[nD] == "F"
            If QiTokIs( "O", "(" )
                aA := QiCallArgs( .T. )
            EndIf
            Return QiCallUser( cNm, aA, .T. )
        EndIf
        If QiIsFunc( cNm )
            If QiTokIs( "O", "(" )
                aA := QiArgs()
            EndIf
            Return QiCallFn( cNm, aA )
        EndIf
        If QiTokIs( "O", "(" )
            aA := QiArgs()
            vR := QiElemOf( cNm, aA, .F., 0 )
        Else
            vR := QiVarGet( cNm )
        EndIf
        nTy := QiTypeOf( cNm )
        If QiTokIs( "O", "." )
            nTP := nTP + 1
            cFld := QiTV()
            nTP := nTP + 1
            fi := QiFieldIdx( QiTypeOfName( cNm ), cFld )
            If fi == 0
                QiErr( "Element is not a member" )
                Return 0
            EndIf
            vR := vR[fi]
        EndIf
    Else
        QiErr( "Syntax error" )
    EndIf
Return vR

// LBOUND(nome [, dim]) / UBOUND(nome [, dim]); o token atual segue o nome da funcao
Static Function QiBoundOf( lLow )
    Local cNm := ""
    Local nDim := 1
    Local pos := 0
    Local lo := 0
    Local nSz := 0
    If !QiTokIs( "O", "(" )
        QiErr( "Syntax error" )
        Return 0
    EndIf
    nTP := nTP + 1
    If QiTT() != "W"
        QiErr( "Syntax error" )
        Return 0
    EndIf
    cNm := QiTV()
    nTP := nTP + 1
    If QiTokIs( "O", "," )
        nTP := nTP + 1
        nDim := QiRoundEven( QiExpr() )
    EndIf
    If !QiTokIs( "O", ")" )
        QiErr( "Syntax error" )
        Return 0
    EndIf
    nTP := nTP + 1
    pos := AScan( aVN, QiKey( cNm ) )
    If pos == 0 .Or. ValType( aVV[pos] ) != "A"
        QiErr( "Array not defined" )
        Return 0
    EndIf
    If nDim == 1
        lo := aVM[pos][2]
        nSz := Len( aVV[pos] )
    Else
        lo := aVM[pos][3]
        If Len( aVV[pos] ) == 0
            nSz := 0
        Else
            nSz := Len( aVV[pos][1] )
        EndIf
    EndIf
    If lLow
        Return lo
    EndIf
Return lo + nSz - 1

// Lista de argumentos (somente valores); o token atual deve ser '('
Static Function QiArgs()
    Local aA := {}
    nTP := nTP + 1
    If QiTokIs( "O", ")" )
        nTP := nTP + 1
        Return aA
    EndIf
    While Empty( cErr )
        AAdd( aA, QiExpr() )
        If QiTokIs( "O", "," )
            nTP := nTP + 1
        ElseIf QiTokIs( "O", ")" )
            nTP := nTP + 1
            Exit
        Else
            QiErr( "Syntax error" )
            Exit
        EndIf
    EndDo
Return aA

// ---------------------------------------------------------------------------
// Funcoes embutidas
// ---------------------------------------------------------------------------

Static Function QiIsFunc( cNm )
    Local aFns := { "LEN", "MID$", "LEFT$", "RIGHT$", "STR$", "VAL", "INT", "FIX", ;
                    "ABS", "SGN", "CHR$", "ASC", "UCASE$", "LCASE$", "SPACE$", ;
                    "STRING$", "LTRIM$", "RTRIM$", "SQR", "RND", "TIMER", "INKEY$", "PEEK", "POINT", "ATN", "ERR", "CINT", "CLNG", "CSNG", "CDBL", "EOF", "HEX$", "OCT$", "INSTR" }
Return AScan( aFns, cNm ) > 0

Static Function QiArgAt( aA, n )
    Local vR := 0
    If n > Len( aA )
        QiErr( "Illegal function call" )
    Else
        vR := aA[n]
    EndIf
Return vR

Static Function QiCallFn( cNm, aA )
    Local a1 := 0
    Local a2 := 0
    Local nB := 0
    Local tArg := nTy
    nTy := "S"

    If cNm == "ATN"
        Return ATan( QiArgAt( aA, 1 ) )
    EndIf
    If cNm == "ERR"
        Return nErrNum
    EndIf
    If cNm == "HEX$" .Or. cNm == "OCT$"
        Return QiBaseTxt( QiArgAt( aA, 1 ), If( cNm == "HEX$", 16, 8 ) )
    EndIf
    If cNm == "INSTR"
        nTy := "I"
        Return QiInstr( aA )
    EndIf
    If cNm == "LEFT$" .Or. cNm == "RIGHT$" .Or. cNm == "MID$"
        a1 := QiArgAt( aA, 1 )
        If ValType( a1 ) != "C"
            QiErr( "Type mismatch" )
            Return ""
        EndIf
        If cNm == "LEFT$"
            Return QiSubU( a1, 1, Int( QiArgAt( aA, 2 ) ) )
        EndIf
        If cNm == "RIGHT$"
            nB := QiLenU( a1 )
            Return QiSubU( a1, nB - Int( QiArgAt( aA, 2 ) ) + 1, Int( QiArgAt( aA, 2 ) ) )
        EndIf
        If Int( QiArgAt( aA, 2 ) ) < 1
            QiErr( "Illegal function call" )
            Return ""
        EndIf
        If Len( aA ) >= 3
            nB := Int( aA[3] )
        Else
            nB := QiLenU( a1 )
        EndIf
        Return QiSubU( a1, Int( aA[2] ), nB )
    EndIf

    If cNm == "CINT" .Or. cNm == "CLNG"
        nTy := "I"
        If cNm == "CLNG"
            nTy := "L"
        EndIf
        Return QiRoundEven( QiArgAt( aA, 1 ) )
    EndIf
    If cNm == "CSNG" .Or. cNm == "CDBL"
        Return QiArgAt( aA, 1 )
    EndIf
    If cNm == "POINT"
        Return QiPixGet( QiRnd( QiArgAt( aA, 1 ) ), QiRnd( QiArgAt( aA, 2 ) ) )
    EndIf
    If cNm == "TIMER"
        QiGfxFlush()
        Return Seconds()
    ElseIf cNm == "INKEY$"
        Return QiInkey()
    ElseIf cNm == "EOF"
        Return QiEofFile( QiArgAt( aA, 1 ) )
    ElseIf cNm == "PEEK"
        Return QiMemRead( QiLin( QiArgAt( aA, 1 ) ) )
    ElseIf cNm == "RND"
        nTy := "S"
        nRndX := QiRndNext()
        Return nRndX / 16777216
    EndIf

    a1 := QiArgAt( aA, 1 )
    If !Empty( cErr )
        Return ""
    EndIf

    If cNm == "LEN"
        If ValType( a1 ) != "C"
            QiErr( "Type mismatch" )
            Return 0
        EndIf
        nTy := "I"
        Return QiLenU( a1 )
    ElseIf cNm == "STR$"
        If ValType( a1 ) != "N"
            QiErr( "Type mismatch" )
            Return ""
        EndIf
        If a1 >= 0
            Return " " + QiFmtNum( a1, tArg )
        EndIf
        Return QiFmtNum( a1, tArg )
    ElseIf cNm == "VAL"
        If ValType( a1 ) != "C"
            QiErr( "Type mismatch" )
            Return 0
        EndIf
        Return QiVal( a1 )
    ElseIf cNm == "INT"
        If ValType( a1 ) != "N"
            QiErr( "Type mismatch" )
            Return 0
        EndIf
        Return FloorInt( a1 )
    ElseIf cNm == "FIX"
        If ValType( a1 ) != "N"
            QiErr( "Type mismatch" )
            Return 0
        EndIf
        Return TruncInt( a1 )
    ElseIf cNm == "ABS"
        If ValType( a1 ) != "N"
            QiErr( "Type mismatch" )
            Return 0
        EndIf
        Return Abs( a1 )
    ElseIf cNm == "SGN"
        If ValType( a1 ) != "N"
            QiErr( "Type mismatch" )
            Return 0
        EndIf
        If a1 > 0
            Return 1
        EndIf
        If a1 < 0
            Return -1
        EndIf
        Return 0
    ElseIf cNm == "CHR$"
        If ValType( a1 ) != "N"
            QiErr( "Type mismatch" )
            Return ""
        EndIf
        Return QiChrG( Int( a1 ) )
    ElseIf cNm == "ASC"
        If ValType( a1 ) != "C" .Or. Len( a1 ) == 0
            QiErr( "Illegal function call" )
            Return 0
        EndIf
        Return QiAscG( a1 )
    ElseIf cNm == "UCASE$"
        Return Upper( a1 )
    ElseIf cNm == "LCASE$"
        Return Lower( a1 )
    ElseIf cNm == "SPACE$"
        Return Space( Int( a1 ) )
    ElseIf cNm == "STRING$"
        a2 := QiArgAt( aA, 2 )
        If ValType( a2 ) == "C"
            Return Replicate( Left( a2, 1 ), Int( a1 ) )
        EndIf
        Return Replicate( QiChrG( Int( a2 ) ), Int( a1 ) )
    ElseIf cNm == "LTRIM$"
        Return LTrim( a1 )
    ElseIf cNm == "RTRIM$"
        Return RTrim( a1 )
    ElseIf cNm == "SQR"
        If ValType( a1 ) != "N" .Or. a1 < 0
            QiErr( "Illegal function call" )
            Return 0
        EndIf
        If a1 == 0
            Return 0
        EndIf
        Return Exp( 0.5 * Log( a1 ) )
    EndIf
    QiErr( "Statement not implemented: " + cNm )
Return 0

// VAL do QBASIC: ignora espacos iniciais, le o maior prefixo numerico e para
// no primeiro caractere que nao pertence ao numero (o Val do AdvPP nao faz isso)
Static Function QiVal( cT )
    Local cS := LTrim( cT )
    Local cN := ""
    Local k := 1
    Local cC := ""
    Local lDig := .F.
    If SubStr( cS, 1, 1 ) == "+" .Or. SubStr( cS, 1, 1 ) == "-"
        cN := SubStr( cS, 1, 1 )
        k := 2
    EndIf
    While k <= Len( cS )
        cC := SubStr( cS, k, 1 )
        If At( cC, "0123456789" ) > 0
            cN += cC
            lDig := .T.
        ElseIf cC == "." .And. At( ".", cN ) == 0
            cN += cC
        Else
            Exit
        EndIf
        k := k + 1
    EndDo
    If !lDig
        Return 0
    EndIf
Return Val( cN )

// HEX$ / OCT$ de inteiro (negativos em complemento de dois de 16 bits)
Static Function QiBaseTxt( v, nB )
    Local n := QiRoundEven( v )
    Local cR := ""
    Local cD := "0123456789ABCDEF"
    Local k := 0
    If n < 0
        n := n + 65536
    EndIf
    If n == 0
        Return "0"
    EndIf
    While n > 0
        cR := SubStr( cD, Mod( n, nB ) + 1, 1 ) + cR
        n := Int( n / nB )
    EndDo
Return cR

// INSTR([inicio,] texto, procurado)
Static Function QiInstr( aA )
    Local nI := 1
    Local cT := ""
    Local cF := ""
    Local nP := 0
    If Len( aA ) >= 3
        nI := QiRoundEven( aA[1] )
        cT := aA[2]
        cF := aA[3]
    Else
        cT := aA[1]
        cF := aA[2]
    EndIf
    If nI < 1
        QiErr( "Illegal function call" )
        Return 0
    EndIf
    If Len( cF ) == 0
        Return nI
    EndIf
    If nI > Len( cT )
        Return 0
    EndIf
    nP := At( cF, SubStr( cT, nI ) )
    If nP == 0
        Return 0
    EndIf
    // posicao em bytes -> posicao em caracteres
Return QiLenU( Left( SubStr( cT, nI ), nP - 1 ) ) + nI

// Proximo estado do gerador de RND do QBASIC (24 bits), exato em aritmetica de double
Static Function QiRndNext()
    Local aH := Int( 1140671485 / 4096 )
    Local aL := Mod( 1140671485, 4096 )
    Local lo := nRndX * aL
    Local hi := Mod( nRndX * aH, 4096 )
Return Mod( lo + hi * 4096 + 12820163, 16777216 )

// Arredondamento para o inteiro mais proximo; empate vai para o par (como o QBasic)
Static Function QiRoundEven( x )
    Local a := 0
    Local f := 0
    Local r := 0
    If ValType( x ) != "N"
        QiErr( "Type mismatch" )
        Return 0
    EndIf
    a := Abs( x )
    f := Int( a )
    r := f
    If a - f > 0.5
        r := f + 1
    ElseIf a - f == 0.5
        If Mod( f, 2 ) == 1
            r := f + 1
        EndIf
    EndIf
    If x < 0
        r := -r
    EndIf
Return r

Static Function TruncInt( x )
    Local r := 0
    If x >= 0
        r := Int( x )
    Else
        r := -Int( -x )
    EndIf
Return r

Static Function FloorInt( x )
    Local r := Int( x )
    If r > x
        r := r - 1
    EndIf
Return r

// ===========================================================================
// IDE (Fase 3): editor, menus, janela Immediate, F5 executa, F8 passo a passo.
// Layout 80x25 (como o QBASIC): 0 menu; 1 titulo; 2-15 editor; 16 titulo
// Immediate; 17-23 Immediate (saida + entrada); 24 barra de status.
// Teclas: F1 ajuda, F2 SUBs, F5 executar, F6 alterna editor/Immediate,
// F8 passo, F10 ou ESC abre menus, setas/Home/End/PgUp/PgDn/Del no editor.
// ===========================================================================

Static Function QiIdeInit()
    aEd := { "" }
    nEdRow := 1
    nEdCol := 1
    nTopLine := 1
    cFileName := "UNTITLED.BAS"
    lEdDirty := .F.
    lMenuOpen := .F.
    nMenu := 1
    nMenuItem := 1
    lImmFocus := .F.
    cImm := ""
    aImmOut := {}
    lIdeQuit := .F.
    lStepOn := .F.
    nDbgLine := 0
    cFind := ""
    nMode := 0
    aLast := {}
    QiCls()
Return

// Carrega arquivo para o editor (linhas separadas por LF; CR ignorado)
Static Function IdeLoadFile( cPath )
    Local cS := MemoRead( cPath )
    If Empty( cS )
        IdeMsg( "Arquivo vazio ou nao encontrado: " + cPath )
        aEd := { "" }
    Else
        aEd := QiSplit( StrTran( cS, Chr(13), "" ), Chr(10) )
        If Len( aEd ) == 0
            aEd := { "" }
        EndIf
    EndIf
    cFileName := cPath
    nEdRow := 1
    nEdCol := 1
    nTopLine := 1
    lEdDirty := .F.
Return

// Mensagem na janela Immediate
Static Function IdeMsg( cM )
    AAdd( aImmOut, cM )
Return

// Junta as linhas do editor num unico texto
Static Function IdeJoin()
    Local cR := ""
    Local k := 0
    For k := 1 To Len( aEd )
        cR += aEd[k]
        If k < Len( aEd )
            cR += Chr(10)
        EndIf
    Next
Return cR

// ---------------------------------------------------------------------------
// Edicao
// ---------------------------------------------------------------------------

Static Function IdeDelLine( nIdx )
    Local aN := {}
    Local k := 0
    For k := 1 To Len( aEd )
        If k != nIdx
            AAdd( aN, aEd[k] )
        EndIf
    Next
    If Len( aN ) == 0
        aN := { "" }
    EndIf
    aEd := aN
Return

// Limites da selecao normalizados: {linha1, col1, linha2, col2} (col2 = posicao do cursor, exclusiva)
Static Function IdeSelBounds()
    Local r1 := nSelR
    Local c1 := nSelC
    Local r2 := nEdRow
    Local c2 := nEdCol
    If r2 < r1 .Or. ( r2 == r1 .And. c2 < c1 )
        r1 := nEdRow
        c1 := nEdCol
        r2 := nSelR
        c2 := nSelC
    EndIf
Return { r1, c1, r2, c2 }

// Texto da selecao como linhas
Static Function IdeSelText()
    Local b := IdeSelBounds()
    Local aR := {}
    Local k := 0
    If b[1] == b[3]
        AAdd( aR, SubStr( aEd[b[1]], b[2], b[4] - b[2] ) )
    Else
        AAdd( aR, SubStr( aEd[b[1]], b[2] ) )
        For k := b[1] + 1 To b[3] - 1
            AAdd( aR, aEd[k] )
        Next
        AAdd( aR, Left( aEd[b[3]], b[4] - 1 ) )
    EndIf
Return aR

// Remove o texto selecionado e posiciona o cursor no inicio dele
Static Function IdeDelSel()
    Local b := IdeSelBounds()
    Local aN := {}
    Local k := 0
    If !lSel
        Return
    EndIf
    aEd[b[1]] := Left( aEd[b[1]], b[2] - 1 ) + SubStr( aEd[b[3]], b[4] )
    For k := 1 To Len( aEd )
        If k < b[1] .Or. k > b[3]
            AAdd( aN, aEd[k] )
        ElseIf k == b[1]
            AAdd( aN, aEd[k] )
        EndIf
    Next
    If Len( aN ) == 0
        aN := { "" }
    EndIf
    aEd := aN
    nEdRow := b[1]
    nEdCol := b[2]
    lSel := .F.
    lEdDirty := .T.
Return

// Cola texto (varias linhas) na posicao do cursor
Static Function IdeInsertText( aL )
    Local rest := ""
    Local aN := {}
    Local n := Len( aL )
    Local k := 0
    Local j := 0
    If n == 0
        Return
    EndIf
    If n == 1
        IdeInsChar( aL[1] )
        Return
    EndIf
    rest := SubStr( aEd[nEdRow], nEdCol )
    aEd[nEdRow] := Left( aEd[nEdRow], nEdCol - 1 ) + aL[1]
    For k := 1 To Len( aEd )
        AAdd( aN, aEd[k] )
        If k == nEdRow
            For j := 2 To n - 1
                AAdd( aN, aL[j] )
            Next
            AAdd( aN, aL[n] + rest )
        EndIf
    Next
    aEd := aN
    nEdCol := Len( aL[n] ) + 1
    nEdRow := nEdRow + n - 1
    lEdDirty := .T.
Return

// Insere linhas (copia) antes da linha nPos
Static Function IdeInsertLines( nPos, aNew )
    Local aN := {}
    Local k := 0
    Local j := 0
    If Len( aNew ) == 0
        Return
    EndIf
    For k := 1 To Len( aEd )
        If k == nPos
            For j := 1 To Len( aNew )
                AAdd( aN, aNew[j] )
            Next
        EndIf
        AAdd( aN, aEd[k] )
    Next
    aEd := aN
    lEdDirty := .T.
Return

// Ajuda contextual (F1): palavra sob o cursor
Static Function IdeContextHelp()
    Local cL := aEd[nEdRow]
    Local nI := nEdCol
    Local nB := 0
    Local nE := 0
    Local cW := ""
    Local k := 0
    Local aH := IdeHelpTable()
    While nI > 1 .And. At( SubStr( cL, nI - 1, 1 ), "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789$%!#&_" ) > 0
        nI := nI - 1
    EndDo
    nB := nI
    nE := nEdCol
    While nE <= Len( cL ) .And. At( SubStr( cL, nE, 1 ), "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789$%!#&_" ) > 0
        nE := nE + 1
    EndDo
    cW := Upper( SubStr( cL, nB, nE - nB ) )
    If Empty( cW )
        IdeMsg( "Posicione o cursor sobre uma palavra-chave." )
        Return
    EndIf
    If IdeHlpLoad()
        k := IdeHlpFind( cW )
        If k > 0
            cHlpTitle := aHlp[k][1]
            aHlpView := aHlp[k][2]
            nHlpTop := 1
            lHelpOpen := .T.
        Else
            IdeMsg( "Sem topico de ajuda para: " + cW )
        EndIf
        Return
    EndIf
    IdeMsg( "Defina QB_HLP com o caminho de QBASIC.HLP para a ajuda completa." )
    For k := 1 To Len( aH )
        If aH[k][1] == cW
            IdeMsg( cW + ": " + aH[k][2] )
            Return
        EndIf
    Next
    IdeMsg( "Sem ajuda para: " + cW )
Return

// Carrega os topicos do QBASIC.HLP (uma vez) chamando o extrator Python por ProcRun.
// QB_HLP = caminho do QBASIC.HLP; QB_HLP_TOOL = extrator (default tests/qbi/tools/hlp_extract.py)
Static Function IdeHlpLoad()
    Local cHlp := QiEnv( "QB_HLP" )
    Local cTool := QiEnv( "QB_HLP_TOOL" )
    Local cCmd := ""
    Local aRaw := {}
    Local cL := ""
    Local cRest := ""
    Local nSp := 0
    Local k := 0
    If lHlpLoaded
        Return Len( aHlp ) > 0
    EndIf
    lHlpLoaded := .T.
    If Empty( cHlp )
        Return .F.
    EndIf
    If Empty( cTool )
        cTool := "tests/qbi/tools/hlp_extract.py"
    EndIf
    cCmd := "python3 -I '" + cTool + "' '" + cHlp + "' 2>/dev/null"
    ProcRun( "bash", { "-c", cCmd }, {|c| AAdd( aRaw, c ) } )
    For k := 1 To Len( aRaw )
        cL := aRaw[k]
        If Left( cL, 4 ) == "### "
            cRest := SubStr( cL, 5 )
            nSp := At( " ", cRest )
            AAdd( aHlp, { If( nSp > 0, SubStr( cRest, nSp + 1 ), "" ), {} } )
        ElseIf Len( aHlp ) > 0
            AAdd( aHlp[Len( aHlp )][2], cL )
        EndIf
    Next
Return Len( aHlp ) > 0

// Indice do topico cujo titulo casa com a palavra (1o: item do titulo; 2o: primeira palavra)
Static Function IdeHlpFind( cW )
    Local k := 0
    Local j := 0
    Local nPass := 0
    Local aSeg := {}
    For nPass := 1 To 2
        For k := 1 To Len( aHlp )
            If nPass == 1
                aSeg := IdeHlpSplit( aHlp[k][1] )
                For j := 1 To Len( aSeg )
                    If IdeHlpNorm( aSeg[j] ) == cW
                        Return k
                    EndIf
                Next
            ElseIf IdeHlpFirst( IdeHlpNorm( aHlp[k][1] ) ) == cW
                Return k
            EndIf
        Next
    Next
Return 0

Static Function IdeHlpSplit( cT )
    Local aR := {}
    Local cS := cT
    Local nP := At( ",", cS )
    While nP > 0
        AAdd( aR, Left( cS, nP - 1 ) )
        cS := SubStr( cS, nP + 1 )
        nP := At( ",", cS )
    EndDo
    AAdd( aR, cS )
Return aR

// Nome do item sem o sufixo de tipo: "PLAY Statement (Music)" -> "PLAY"
Static Function IdeHlpNorm( cT )
    Local cS := Upper( AllTrim( cT ) )
    Local aSuf := { " STATEMENTS", " STATEMENT", " FUNCTION", " COMMAND", " (" }
    Local k := 0
    For k := 1 To Len( aSuf )
        If At( aSuf[k], cS ) > 0
            cS := Left( cS, At( aSuf[k], cS ) - 1 )
        EndIf
    Next
Return AllTrim( cS )

Static Function IdeHlpFirst( cS )
    Local nP := At( " ", cS )
Return If( nP > 0, Left( cS, nP - 1 ), cS )

// Visualizador modal da ajuda: ocupa a tela, rola com setas/PgUp/PgDn/Home/End, ESC fecha
Static Function IdeHlpKey( cK )
    Local nMax := Max( 1, Len( aHlpView ) - 20 )
    If cK == Chr(27)
        lHelpOpen := .F.
    ElseIf cK == Chr(0) + "H"
        nHlpTop := Max( 1, nHlpTop - 1 )
    ElseIf cK == Chr(0) + "P"
        nHlpTop := Min( nMax, nHlpTop + 1 )
    ElseIf cK == Chr(0) + "I"
        nHlpTop := Max( 1, nHlpTop - 20 )
    ElseIf cK == Chr(0) + "Q"
        nHlpTop := Min( nMax, nHlpTop + 20 )
    ElseIf cK == Chr(0) + "G"
        nHlpTop := 1
    ElseIf cK == Chr(0) + "O"
        nHlpTop := nMax
    EndIf
Return

Static Function IdeHlpDraw()
    Local k := 0
    Local nAt := 31
    Local nAtT := 112
    Local nLast := Min( Len( aHlpView ), nHlpTop + 20 )
    For k := 0 To 23
        IdePut( k, 0, Space( 80 ), nAt )
    Next
    IdePut( 0, 0, Space( 80 ), nAtT )
    QiPutAt( 0, 1, "Ajuda: " + cHlpTitle, nAtT )
    For k := nHlpTop To nLast
        QiPutAt( 2 + k - nHlpTop, 1, QiSubU( aHlpView[k], 1, 78 ), nAt )
    Next
    IdePut( 23, 0, Space( 80 ), nAtT )
    IdePut( 23, 1, "Setas/PgUp/PgDn/Home/End rolam   ESC fecha", nAtT )
Return

// Tabela de ajuda contextual (resumo dos comandos implementados)
Static Function IdeHelpTable()
Return { ;
    { "PRINT", "mostra valores na tela; ';' cola, ',' avanca a zona de 14 colunas" }, ;
    { "INPUT", "le valores do teclado; mostra '?' como prompt" }, ;
    { "LET", "atribui um valor a uma variavel ou elemento" }, ;
    { "IF", "executa comandos se a condicao for verdadeira; THEN, ELSE, END IF" }, ;
    { "FOR", "laco com contador; NEXT fecha; STEP define o passo" }, ;
    { "NEXT", "fecha um laco FOR" }, ;
    { "WHILE", "laco enquanto a condicao for verdadeira; WEND fecha" }, ;
    { "DO", "laco DO ... LOOP com WHILE ou UNTIL" }, ;
    { "LOOP", "fecha um laco DO" }, ;
    { "GOTO", "desvia para um numero de linha ou rotulo" }, ;
    { "GOSUB", "chama uma sub-rotina interna; RETURN volta" }, ;
    { "SUB", "define um procedimento; END SUB fecha" }, ;
    { "FUNCTION", "define uma funcao que retorna valor; END FUNCTION fecha" }, ;
    { "CALL", "chama um SUB" }, ;
    { "DIM", "declara arrays e registros; SHARED torna global" }, ;
    { "REDIM", "redimensiona um array" }, ;
    { "TYPE", "define um tipo de registro; END TYPE fecha" }, ;
    { "CONST", "define constantes" }, ;
    { "SELECT", "SELECT CASE escolhe entre valores; END SELECT fecha" }, ;
    { "CASE", "ramo de SELECT CASE (valor, lista, TO, IS, ELSE)" }, ;
    { "DATA", "valores lidos por READ" }, ;
    { "READ", "le valores de DATA" }, ;
    { "CLS", "limpa a tela" }, ;
    { "LOCATE", "posiciona o cursor: linha, coluna" }, ;
    { "COLOR", "cor do texto e do fundo" }, ;
    { "SCREEN", "modo de video (0 texto; 1, 2, 9, 12 graficos)" }, ;
    { "PSET", "acende um pixel" }, ;
    { "LINE", "desenha reta; B retangulo; BF retangulo preenchido" }, ;
    { "CIRCLE", "desenha circulo ou arco: centro, raio, cor, inicio, fim" }, ;
    { "PAINT", "preenche uma regiao delimitada pela cor de contorno" }, ;
    { "GET", "guarda uma area da tela num array" }, ;
    { "PUT", "desenha uma area guardada por GET" }, ;
    { "PALETTE", "troca a cor de um atributo da paleta" }, ;
    { "PLAY", "toca musica em notacao MML" }, ;
    { "SOUND", "toca uma frequencia por uma duracao em ticks" }, ;
    { "BEEP", "toca um bip" }, ;
    { "DEF", "DEF SEG define o segmento de memoria; DEF FN define funcao de uma linha" }, ;
    { "PEEK", "le um byte da memoria" }, ;
    { "POKE", "grava um byte na memoria" }, ;
    { "ON", "ON ERROR GOTO rotulo trata erros" }, ;
    { "RESUME", "retoma a execucao apos um erro tratado" }, ;
    { "END", "encerra o programa" }, ;
    { "EXIT", "sai de SUB, FUNCTION, FOR, DO ou WHILE" }, ;
    { "TIMER", "segundos desde a meia-noite" }, ;
    { "INKEY$", "tecla pressionada, ou texto vazio" }, ;
    { "RND", "numero aleatorio entre 0 e 1" }, ;
    { "INT", "maior inteiro menor ou igual ao valor" }, ;
    { "LEN", "tamanho de uma string" }, ;
    { "MID$", "parte de uma string: texto, inicio, tamanho" }, ;
    { "LEFT$", "primeiros caracteres de uma string" }, ;
    { "RIGHT$", "ultimos caracteres de uma string" }, ;
    { "VAL", "converte texto em numero" }, ;
    { "STR$", "converte numero em texto" }, ;
    { "CHR$", "caractere de um codigo ASCII" }, ;
    { "ASC", "codigo ASCII do primeiro caractere" } }

Static Function IdeInsChar( cC )
    Local cL := aEd[nEdRow]
    aEd[nEdRow] := Left( cL, nEdCol - 1 ) + cC + SubStr( cL, nEdCol )
    nEdCol := nEdCol + 1
    lEdDirty := .T.
Return

Static Function IdeEnter()
    Local cL := aEd[nEdRow]
    Local cRest := SubStr( cL, nEdCol )
    Local aN := {}
    Local k := 0
    aEd[nEdRow] := Left( cL, nEdCol - 1 )
    For k := 1 To Len( aEd )
        AAdd( aN, aEd[k] )
        If k == nEdRow
            AAdd( aN, cRest )
        EndIf
    Next
    aEd := aN
    nEdRow := nEdRow + 1
    nEdCol := 1
    lEdDirty := .T.
Return

Static Function IdeBackspace()
    Local cL := ""
    Local nPrev := 0
    If nEdCol > 1
        cL := aEd[nEdRow]
        aEd[nEdRow] := Left( cL, nEdCol - 2 ) + SubStr( cL, nEdCol )
        nEdCol := nEdCol - 1
        lEdDirty := .T.
    ElseIf nEdRow > 1
        nPrev := Len( aEd[nEdRow - 1] )
        aEd[nEdRow - 1] := aEd[nEdRow - 1] + aEd[nEdRow]
        IdeDelLine( nEdRow )
        nEdRow := nEdRow - 1
        nEdCol := nPrev + 1
        lEdDirty := .T.
    EndIf
Return

Static Function IdeDelete()
    Local cL := aEd[nEdRow]
    If nEdCol <= Len( cL )
        aEd[nEdRow] := Left( cL, nEdCol - 1 ) + SubStr( cL, nEdCol + 1 )
        lEdDirty := .T.
    ElseIf nEdRow < Len( aEd )
        aEd[nEdRow] := cL + aEd[nEdRow + 1]
        IdeDelLine( nEdRow + 1 )
        lEdDirty := .T.
    EndIf
Return

// Movimento do cursor; cKey: H cima, P baixo, K esquerda, M direita, G Home, O End, I PgUp, Q PgDn
Static Function IdeMove( cKey )
    Local nL := 0
    If cKey == "H"
        nEdRow := Max( 1, nEdRow - 1 )
    ElseIf cKey == "P"
        nEdRow := Min( Len( aEd ), nEdRow + 1 )
    ElseIf cKey == "K"
        If nEdCol > 1
            nEdCol := nEdCol - 1
        ElseIf nEdRow > 1
            nEdRow := nEdRow - 1
            nEdCol := Len( aEd[nEdRow] ) + 1
        EndIf
    ElseIf cKey == "M"
        If nEdCol <= Len( aEd[nEdRow] )
            nEdCol := nEdCol + 1
        ElseIf nEdRow < Len( aEd )
            nEdRow := nEdRow + 1
            nEdCol := 1
        EndIf
    ElseIf cKey == "G"
        nEdCol := 1
    ElseIf cKey == "O"
        nEdCol := Len( aEd[nEdRow] ) + 1
    ElseIf cKey == "I"
        nEdRow := Max( 1, nEdRow - 14 )
    ElseIf cKey == "Q"
        nEdRow := Min( Len( aEd ), nEdRow + 14 )
    EndIf
    nL := Len( aEd[nEdRow] ) + 1
    If nEdCol > nL
        nEdCol := nL
    EndIf
    If nEdCol < 1
        nEdCol := 1
    EndIf
Return

// Mantem a linha do cursor visivel (14 linhas de editor)
Static Function IdeClampView()
    If nEdRow < nTopLine
        nTopLine := nEdRow
    EndIf
    If nEdRow > nTopLine + 13
        nTopLine := nEdRow - 13
    EndIf
Return

// ---------------------------------------------------------------------------
// Busca
// ---------------------------------------------------------------------------

Static Function IdeFind( lNext )
    Local k := 0
    Local nL := 0
    Local nP := 0
    Local cU := Upper( cFind )
    Local nStartCol := nEdCol
    If Empty( cFind )
        Return
    EndIf
    For k := 0 To Len( aEd )
        nL := nEdRow + k
        If nL > Len( aEd )
            nL := nL - Len( aEd )
        EndIf
        If k == 0 .And. lNext
            nP := At( cU, Upper( SubStr( aEd[nL], nStartCol + 1 ) ) )
            If nP > 0
                nEdCol := nStartCol + nP
                nEdRow := nL
                IdeClampView()
                Return
            EndIf
        ElseIf k == 0
            nP := At( cU, Upper( aEd[nL] ) )
            If nP > 0
                nEdCol := nP
                IdeClampView()
                Return
            EndIf
        Else
            nP := At( cU, Upper( aEd[nL] ) )
            If nP > 0
                nEdRow := nL
                nEdCol := nP
                IdeClampView()
                Return
            EndIf
        EndIf
    Next
    IdeMsg( "Nao encontrado: " + cFind )
Return

// Proximo SUB ou FUNCTION (F2)
Static Function IdeNextDef()
    Local k := 0
    Local nL := 0
    Local cT := ""
    For k := 1 To Len( aEd )
        nL := nEdRow + k
        If nL > Len( aEd )
            nL := nL - Len( aEd )
        EndIf
        cT := Upper( LTrim( aEd[nL] ) )
        If Left( cT, 4 ) == "SUB " .Or. Left( cT, 9 ) == "FUNCTION "
            nEdRow := nL
            nEdCol := 1
            IdeClampView()
            Return
        EndIf
    Next
    IdeMsg( "Nenhum SUB ou FUNCTION no programa" )
Return

// ---------------------------------------------------------------------------
// Arquivos (salvamento em hexadecimal + xxd, para preservar bytes)
// ---------------------------------------------------------------------------

Static Function IdeSave( cName )
    Local cTxt := ""
    Local cHex := ""
    Local k := 0
    Local nB := 0
    Local cTmp := "/tmp/qbi_save_" + LTrim( Str( Int( Seconds() * 1000 ) ) ) + ".hex"
    Local h := 0
    Local cHx := "0123456789abcdef"
    Local cOut := ""
    For k := 1 To Len( aEd )
        cTxt += aEd[k] + Chr(13) + Chr(10)
    Next
    h := FCreate( cTmp )
    If h < 0
        IdeMsg( "Nao foi possivel gravar: " + cName )
        Return
    EndIf
    For k := 1 To Len( cTxt )
        nB := Asc( SubStr( cTxt, k, 1 ) )
        If nB > 255
            nB := 63
        EndIf
        cOut += SubStr( cHx, Int( nB / 16 ) + 1, 1 ) + SubStr( cHx, Mod( nB, 16 ) + 1, 1 )
        If Len( cOut ) >= 2048
            FWrite( h, cOut )
            cOut := ""
        EndIf
    Next
    If Len( cOut ) > 0
        FWrite( h, cOut )
    EndIf
    FClose( h )
    ProcRun( "bash", { "-c", "xxd -r -p '" + cTmp + "' > '" + cName + "'; rm -f '" + cTmp + "'" } )
    lEdDirty := .F.
    IdeMsg( "Gravado: " + cName )
Return

// ---------------------------------------------------------------------------
// Prompt na barra de status (linha 24)
// ---------------------------------------------------------------------------

Static Function IdePrompt( cLbl )
    Local cBuf := ""
    Local cK := ""
    Local nA := 48
    While .T.
        IdePut( 24, 0, Space( 80 ), nA )
        IdePut( 24, 0, cLbl + cBuf, nA )
        lDirty := .T.
        QiGfxFlush()
        cK := QiInkey()
        If cK == ""
            If !lTTY
                Return ""
            EndIf
            Loop
        EndIf
        If cK == Chr(13)
            Return cBuf
        ElseIf cK == Chr(27)
            Return ""
        ElseIf cK == Chr(8) .Or. cK == Chr(127)
            If Len( cBuf ) > 0
                cBuf := Left( cBuf, Len( cBuf ) - 1 )
            EndIf
        ElseIf Asc( cK ) >= 32 .And. Len( cK ) == 1
            cBuf += cK
        EndIf
    EndDo
Return ""

// Escreve texto na grade de tela (linha, coluna 0-based)
Static Function IdePut( nR, nC, cT, nAt )
    Local k := 0
    Local nI := 0
    For k := 1 To Len( cT )
        nI := nC + k - 1
        If nI >= 0 .And. nI < 80 .And. nR >= 0 .And. nR < 25
            aScr[nR*80 + nI + 1] := SubStr( cT, k, 1 )
            aAtt[nR*80 + nI + 1] := nAt
        EndIf
    Next
Return

// ---------------------------------------------------------------------------
// Menus
// ---------------------------------------------------------------------------

Static Function IdeMenus()
Return { ;
    { "File", { { "New", "NEW" }, { "Open...", "OPEN" }, { "Save", "SAVE" }, { "Save As...", "SAVEAS" }, { "Exit", "EXIT" } } }, ;
    { "Edit", { { "Cut", "CUT" }, { "Copy", "COPY" }, { "Paste", "PASTE" }, { "Clear", "CLEAR" } } }, ;
    { "View", { { "SUBs...", "SUBS" }, { "Output Screen", "OUTSCR" }, { "Immediate", "IMM" } } }, ;
    { "Search", { { "Find...", "FIND" }, { "Find Next", "FINDNEXT" } } }, ;
    { "Run", { { "Start", "RUN" }, { "Continue", "CONT" } } }, ;
    { "Debug", { { "Step", "STEP" } } }, ;
    { "Options", { { "Tab width (4/8)", "TABW" } } }, ;
    { "Help", { { "Index", "HELP" } } } }

// Coluna inicial do menu n na barra
Static Function IdeMenuCol( nN )
    Local aM := IdeMenus()
    Local nC := 2
    Local k := 0
    For k := 1 To nN - 1
        nC := nC + Len( aM[k][1] ) + 2
    Next
Return nC

Static Function IdeMenuKey( cK )
    Local aM := IdeMenus()
    Local cAct := ""
    Local nK := 0
    If cK == Chr(27)
        lMenuOpen := .F.
    ElseIf cK == Chr(0) + "K"
        nMenu := nMenu - 1
        If nMenu < 1
            nMenu := Len( aM )
        EndIf
        nMenuItem := 1
    ElseIf cK == Chr(0) + "M"
        nMenu := nMenu + 1
        If nMenu > Len( aM )
            nMenu := 1
        EndIf
        nMenuItem := 1
    ElseIf cK == Chr(0) + "H"
        nMenuItem := Max( 1, nMenuItem - 1 )
    ElseIf cK == Chr(0) + "P"
        nMenuItem := Min( Len( aM[nMenu][2] ), nMenuItem + 1 )
    ElseIf cK == Chr(13)
        cAct := aM[nMenu][2][nMenuItem][2]
        lMenuOpen := .F.
        IdeAction( cAct )
    ElseIf Len( cK ) == 1 .And. Asc( cK ) >= 32
        For nK := 1 To Len( aM )
            If Upper( Left( aM[nK][1], 1 ) ) == Upper( cK )
                nMenu := nK
                nMenuItem := 1
                Exit
            EndIf
        Next
    EndIf
Return

Static Function IdeToggleBrk()
    Local nP := AScan( aBrk, nEdRow )
    If nP > 0
        ADel( aBrk, nP )
        ASize( aBrk, Len( aBrk ) - 1 )
        IdeMsg( "Breakpoint removido: linha " + LTrim( Str( nEdRow ) ) )
    Else
        AAdd( aBrk, nEdRow )
        IdeMsg( "Breakpoint: linha " + LTrim( Str( nEdRow ) ) )
    EndIf
Return

// ---------------------------------------------------------------------------
// Acoes
// ---------------------------------------------------------------------------

Static Function IdeAction( cAct )
    Local cP := ""
    If cAct == "NEW"
        aEd := { "" }
        cFileName := "UNTITLED.BAS"
        nEdRow := 1
        nEdCol := 1
        nTopLine := 1
    ElseIf cAct == "OPEN"
        cP := IdePrompt( "File name: " )
        If !Empty( cP )
            IdeLoadFile( cP )
        EndIf
    ElseIf cAct == "SAVE"
        If cFileName == "UNTITLED.BAS"
            IdeAction( "SAVEAS" )
        Else
            IdeSave( cFileName )
        EndIf
    ElseIf cAct == "SAVEAS"
        cP := IdePrompt( "Save as: " )
        If !Empty( cP )
            cFileName := cP
            IdeSave( cFileName )
        EndIf
    ElseIf cAct == "EXIT"
        lIdeQuit := .T.
    ElseIf cAct == "SUBS"
        IdeNextDef()
    ElseIf cAct == "IMM"
        lImmFocus := !lImmFocus
    ElseIf cAct == "FIND"
        cP := IdePrompt( "Find: " )
        If !Empty( cP )
            cFind := cP
            IdeFind( .F. )
        EndIf
    ElseIf cAct == "FINDNEXT"
        IdeFind( .T. )
    ElseIf cAct == "RUN"
        IdeRunProgram()
    ElseIf cAct == "CONT"
        IdeRunProgram()
    ElseIf cAct == "STEP"
        IdeStep()
    ElseIf cAct == "HELP"
        IdeHelp()
    ElseIf cAct == "CUT"
        If lSel
            aClip := IdeSelText()
            lClipLine := .F.
            IdeDelSel()
        Else
            aClip := { aEd[nEdRow] }
            lClipLine := .T.
            IdeDelLine( nEdRow )
            nEdRow := Min( nEdRow, Len( aEd ) )
            nEdCol := 1
            lEdDirty := .T.
        EndIf
    ElseIf cAct == "COPY"
        If lSel
            aClip := IdeSelText()
            lClipLine := .F.
        Else
            aClip := { aEd[nEdRow] }
            lClipLine := .T.
        EndIf
    ElseIf cAct == "PASTE"
        If lClipLine
            IdeInsertLines( nEdRow, aClip )
        Else
            IdeDelSel()
            IdeInsertText( aClip )
        EndIf
    ElseIf cAct == "CLEAR"
        IdeDelLine( nEdRow )
        nEdRow := Min( nEdRow, Len( aEd ) )
        nEdCol := 1
        lEdDirty := .T.
    ElseIf cAct == "TABW"
        If nTabW == 8
            nTabW := 4
        Else
            nTabW := 8
        EndIf
        IdeMsg( "Largura de tabulacao: " + LTrim( Str( nTabW ) ) )
    ElseIf cAct == "NOP"
        IdeMsg( "Opcao nao implementada nesta versao." )
    EndIf
Return

Static Function IdeHelp()
    IdeMsg( "F1 ajuda  F2 SUBs  F5 executar  F6 Immediate  F8 passo" )
    IdeMsg( "ESC ou F10 abre os menus; no Immediate digite um comando e Enter." )
    IdeMsg( "Ctrl de arquivo: File > Open/Save. Busca: Search > Find." )
Return

// ---------------------------------------------------------------------------
// Execucao: F5 usa a tela do usuario; F8 executa um comando por vez
// ---------------------------------------------------------------------------

// Reinicia o estado do programa (mantem a IDE)
Static Function QiReset()
    aStmt := {}
    aStmtLn := {}
    aStmtSrc := {}
    nPC := 1
    lJmp := .F.
    lStop := .F.
    lRet := .F.
    cErr := ""
    nErrLn := 0
    aVN := {}
    aVV := {}
    aVM := {}
    aFrm := {}
    aGos := {}
    aData := {}
    nDP := 1
    aDefName := {}
    aDefKind := {}
    aDefStart := {}
    aDefParams := {}
    aDefStat := {}
    aTypeName := {}
    aTypeFld := {}
    aTypeDef := {}
    aShr := {}
    aCall := {}
    nFrameSeq := 0
    aSel := {}
    aLblName := {}
    aLblIdx := {}
    aFnName := {}
    aFnParams := {}
    aFnBody := {}
    nErrLbl := 0
    nErrResume := 0
    nErrNum := 0
    aTok := {}
    nTP := 1
Return

Static Function IdeRunProgram()
    Local aSvScr := {}
    Local aSvAtt := {}
    Local k := 0
    Local cK := ""
    If lStepOn
        IdeContinue()
        Return
    EndIf
    If Len( aBrk ) > 0
        // com breakpoints: executa passo a passo, saida na janela Immediate
        QiReset()
        If !QiLoad( IdeJoin() )
            IdeMsg( "? " + cErr )
            cErr := ""
            Return
        EndIf
        nPC := 1
        lStop := .F.
        lStepOn := .T.
        nDbgLine := 0
        cCapt := ""
        lCapt := .T.
        IdeContinue()
        Return
    EndIf
    For k := 1 To 2000
        AAdd( aSvScr, aScr[k] )
        AAdd( aSvAtt, aAtt[k] )
    Next
    QiReset()
    QiCls()
    If QiLoad( IdeJoin() )
        QiRun()
    EndIf
    If !Empty( cErr )
        IdeMsg( "? " + cErr + " na linha " + AllTrim( Str( nErrLn ) ) )
        cErr := ""
    EndIf
    QiOut( Chr(10) + "Pressione uma tecla para voltar ao editor." )
    lDirty := .T.
    QiGfxFlush()
    While .T.
        cK := QiInkey()
        If cK != ""
            Exit
        EndIf
        If !lTTY
            Exit
        EndIf
    EndDo
    For k := 1 To 2000
        aScr[k] := aSvScr[k]
        aAtt[k] := aSvAtt[k]
    Next
    QiIdeTerm()
    nMode := 0
    aLast := {}
    nEmitAtt := -1
    lDirty := .T.
Return

// F8: carrega o programa na primeira vez e executa a proxima instrucao
Static Function IdeStep()
    If !lStepOn
        QiReset()
        If !QiLoad( IdeJoin() )
            IdeMsg( "? " + cErr )
            cErr := ""
            Return
        EndIf
        nPC := 1
        lStop := .F.
        lStepOn := .T.
        nDbgLine := 0
        cCapt := ""
        lCapt := .T.
    EndIf
    IdeStepOne()
Return

Static Function IdeStepOne()
    Local nCur := 0
    If nPC > Len( aStmt ) .Or. lStop .Or. !Empty( cErr )
        IdeEndStep()
        Return
    EndIf
    nCur := nPC
    nPC := nPC + 1
    lJmp := .F.
    QiExec( aStmt[nCur], nCur )
    nDbgLine := aStmtSrc[nCur]
    nEdRow := Min( nDbgLine, Len( aEd ) )
    nEdCol := 1
    IdeClampView()
    IdeFlushCapt()
    If !Empty( cErr )
        IdeMsg( "? " + cErr + " na linha " + AllTrim( Str( nDbgLine ) ) )
        cErr := ""
        IdeEndStep()
    EndIf
Return

Static Function IdeContinue()
    lBrkHit := .F.
    nBrkSkip := nPC
    While lStepOn .And. nPC <= Len( aStmt ) .And. !lStop .And. Empty( cErr )
        If AScan( aBrk, aStmtSrc[nPC] ) > 0 .And. nPC != nBrkSkip
            // para antes da linha marcada
            lBrkHit := .T.
            nDbgLine := aStmtSrc[nPC]
            nEdRow := Min( nDbgLine, Len( aEd ) )
            nEdCol := 1
            IdeClampView()
            IdeFlushCapt()
            IdeMsg( "Interrompido no breakpoint, linha " + LTrim( Str( nDbgLine ) ) )
            Return
        EndIf
        nBrkSkip := 0
        IdeStepOne()
    EndDo
    If lStepOn .And. !lBrkHit
        IdeEndStep()
    EndIf
Return

Static Function IdeEndStep()
    lStepOn := .F.
    lCapt := .F.
    IdeFlushCapt()
    IdeMsg( "Fim do programa (passo)." )
    nDbgLine := 0
Return

// Passa a saida capturada para a janela Immediate
Static Function IdeFlushCapt()
    Local aL := QiSplit( cCapt, Chr(10) )
    Local k := 0
    If Len( aL ) > 0
        For k := 1 To Len( aL )
            If !( k == Len( aL ) .And. Empty( aL[k] ) )
                IdeMsg( aL[k] )
            EndIf
        Next
    EndIf
    cCapt := ""
Return

// Executa uma linha digitada no Immediate, no contexto do programa atual
Static Function IdeImmExec()
    Local cLine := cImm
    Local aSvSt := aStmt
    Local aSvLn := aStmtLn
    Local aSvSrc := aStmtSrc
    Local nSvPC := nPC
    Local lSvStop := lStop
    Local aT := {}
    Local aPart := {}
    Local k := 0
    cImm := ""
    If Empty( Trim( cLine ) )
        Return
    EndIf
    IdeMsg( "> " + cLine )
    aStmt := {}
    aStmtLn := {}
    aStmtSrc := {}
    cErr := ""
    lCapt := .T.
    cCapt := ""
    aT := QiLex( cLine )
    If Empty( cErr )
        aPart := QiSplitStmts( aT )
        For k := 1 To Len( aPart )
            QiAddStmt( aPart[k], 0, 0 )
        Next
        nPC := 1
        lStop := .F.
        QiRun()
    EndIf
    lCapt := .F.
    IdeFlushCapt()
    If !Empty( cErr )
        IdeMsg( "? " + cErr )
        cErr := ""
    EndIf
    aStmt := aSvSt
    aStmtLn := aSvLn
    aStmtSrc := aSvSrc
    nPC := nSvPC
    lStop := lSvStop
Return

// ---------------------------------------------------------------------------
// Teclado e desenho
// ---------------------------------------------------------------------------

Static Function IdeKey( cK )
    If lHelpOpen
        IdeHlpKey( cK )
        Return
    EndIf
    If lMenuOpen
        IdeMenuKey( cK )
        Return
    EndIf
    If cK == Chr(27) .Or. cK == Chr(0) + "D"
        lMenuOpen := .T.
        nMenu := 1
        nMenuItem := 1
        Return
    EndIf
    If cK == Chr(0) + ";"
        IdeContextHelp()
        Return
    EndIf
    If cK == Chr(0) + "C"
        IdeToggleBrk()
        Return
    EndIf
    If cK == Chr(0) + "<"
        IdeAction( "SUBS" )
        Return
    EndIf
    If cK == Chr(0) + "?"
        IdeAction( "RUN" )
        Return
    EndIf
    If cK == Chr(0) + "@"
        IdeAction( "IMM" )
        Return
    EndIf
    If cK == Chr(0) + "B"
        IdeAction( "STEP" )
        Return
    EndIf
    If lImmFocus
        IdeImmKey( cK )
        Return
    EndIf
    If Left( cK, 1 ) == Chr(1)
        // Shift+seta: estende a selecao
        If !lSel
            lSel := .T.
            nSelR := nEdRow
            nSelC := nEdCol
        EndIf
        IdeMove( Right( cK, 1 ) )
        IdeClampView()
        Return
    EndIf
    If Left( cK, 1 ) == Chr(0)
        If lSel .And. cK == Chr(0) + "S"
            IdeDelSel()
            IdeClampView()
            Return
        EndIf
        lSel := .F.
    ElseIf lSel .And. ( cK == Chr(13) .Or. cK == Chr(8) .Or. cK == Chr(127) .Or. cK == Chr(9) .Or. Asc( cK ) >= 32 )
        IdeDelSel()
        If cK == Chr(8) .Or. cK == Chr(127)
            IdeClampView()
            Return
        EndIf
    EndIf
    If cK == Chr(0) + "H" .Or. cK == Chr(0) + "P" .Or. cK == Chr(0) + "K" .Or. cK == Chr(0) + "M" ;
        .Or. cK == Chr(0) + "G" .Or. cK == Chr(0) + "O" .Or. cK == Chr(0) + "I" .Or. cK == Chr(0) + "Q"
        IdeMove( Right( cK, 1 ) )
    ElseIf cK == Chr(0) + "S"
        IdeDelete()
    ElseIf cK == Chr(13)
        IdeEnter()
    ElseIf cK == Chr(8) .Or. cK == Chr(127)
        IdeBackspace()
    ElseIf cK == Chr(9)
        IdeInsChar( Space( nTabW - Mod( nEdCol - 1, nTabW ) ) )
    ElseIf Len( cK ) == 1 .And. Asc( cK ) >= 32
        IdeInsChar( cK )
    EndIf
    IdeClampView()
Return

Static Function IdeImmKey( cK )
    If cK == Chr(13)
        IdeImmExec()
    ElseIf cK == Chr(8) .Or. cK == Chr(127)
        If Len( cImm ) > 0
            cImm := Left( cImm, Len( cImm ) - 1 )
        EndIf
    ElseIf Len( cK ) == 1 .And. Asc( cK ) >= 32
        cImm += cK
    EndIf
Return

// Monta a tela inteira da IDE na grade e envia so o que mudou
Static Function IdeRender()
    Local k := 0
    Local r := 0
    Local aM := IdeMenus()
    Local nC := 0
    Local cLn := ""
    Local nAtE := 31
    Local nAtM := 112
    Local nAtS := 48
    Local nAtH := 112
    Local nTot := 0
    Local aOut := {}
    Local nFirst := 0
    Local nL := 0
    Local cTxt := ""
    For k := 1 To 2000
        aScr[k] := " "
        aAtt[k] := nAtE
    Next
    // barra de menus
    IdePut( 0, 0, Space( 80 ), nAtM )
    For k := 1 To Len( aM )
        nC := IdeMenuCol( k )
        IdePut( 0, nC, aM[k][1], If( lMenuOpen .And. k == nMenu, 15, nAtM ) )
    Next
    // titulo da janela do programa
    IdePut( 1, 0, Space( 80 ), nAtM )
    cTxt := " " + cFileName + " "
    IdePut( 1, Int( ( 80 - Len( cTxt ) ) / 2 ), cTxt, nAtM )
    // editor
    For r := 0 To 13
        nL := nTopLine + r
        If nL <= Len( aEd )
            cLn := Left( aEd[nL], 80 )
            IdePut( 2 + r, 0, cLn, If( nL == nDbgLine, nAtH, If( AScan( aBrk, nL ) > 0, 79, nAtE ) ) )
            If nL == nDbgLine
                IdePut( 2 + r, Len( cLn ), Space( 80 - Len( cLn ) ), nAtH )
            EndIf
        EndIf
    Next
    // selecao em video reverso
    If lSel
        Local bs := IdeSelBounds()
        Local rr := 0
        Local c0 := 0
        Local c9 := 0
        For rr := bs[1] To bs[3]
            If rr >= nTopLine .And. rr <= nTopLine + 13
                c0 := 1
                c9 := Len( aEd[rr] )
                If rr == bs[1]
                    c0 := bs[2]
                EndIf
                If rr == bs[3]
                    c9 := bs[4] - 1
                EndIf
                For k := c0 To c9
                    aAtt[( 2 + rr - nTopLine )*80 + k] := 112
                Next
            EndIf
        Next
    EndIf
    // janela Immediate
    IdePut( 16, 0, Space( 80 ), nAtM )
    IdePut( 16, 2, "Immediate", nAtM )
    For k := 0 To 5
        nFirst := Len( aImmOut ) - 5 + k
        If nFirst >= 1
            IdePut( 17 + k, 0, Left( aImmOut[nFirst], 80 ), nAtE )
        EndIf
    Next
    IdePut( 23, 0, Space( 80 ), nAtE )
    IdePut( 23, 0, "? " + cImm, nAtE )
    // barra de status
    IdePut( 24, 0, Space( 80 ), nAtS )
    IdePut( 24, 0, "<Shift+F1=Help> <F6=Window> <F2=Subs> <F5=Run> <F8=Step>", nAtS )
    IdePut( 24, 60, StrZero( nEdRow, 5 ) + ":" + StrZero( nEdCol, 3 ), nAtS )
    // menu suspenso
    If lMenuOpen
        IdeDrawDrop( aM )
    EndIf
    If lHelpOpen
        IdeHlpDraw()
    EndIf
    // cursor
    If lImmFocus
        nRow := 23
        nCol := Min( 79, 2 + Len( cImm ) )
    Else
        nRow := Max( 2, Min( 15, 2 + nEdRow - nTopLine - 1 + 1 ) ) - 1 + 1
        nRow := 2 + ( nEdRow - nTopLine )
        nCol := Min( 79, nEdCol - 1 )
    EndIf
    lDirty := .T.
    QiGfxFlush()
Return

Static Function IdeDrawDrop( aM )
    Local nC := IdeMenuCol( nMenu )
    Local k := 0
    Local nW := 0
    Local aIt := aM[nMenu][2]
    For k := 1 To Len( aIt )
        nW := Max( nW, Len( aIt[k][1] ) )
    Next
    nW := nW + 4
    IdePut( 1, nC - 1, Space( nW ), 112 )
    For k := 1 To Len( aIt )
        IdePut( 1 + k, nC - 1, Space( nW ), If( k == nMenuItem, 15, 112 ) )
        IdePut( 1 + k, nC, aIt[k][1], If( k == nMenuItem, 15, 112 ) )
    Next
Return

// ---------------------------------------------------------------------------
// Laço principal da IDE
// ---------------------------------------------------------------------------

// Modo de terminal da IDE: leitura com espera de 0,1 s (sem processo por ciclo)
Static Function QiIdeTerm()
    If lTTY
        ProcRun( "bash", { "-c", "stty min 0 time 1 </dev/tty" } )
    EndIf
Return

Static Function QiIdeLoop()
    Local cK := ""
    QiIdeTerm()
    IdeRender()
    While !lIdeQuit
        cK := QiInkey()
        If cK == ""
            If !lTTY
                Exit
            EndIf
            Loop
        EndIf
        IdeKey( cK )
        IdeRender()
    EndDo
Return

