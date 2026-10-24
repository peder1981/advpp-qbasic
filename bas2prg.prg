/*
{Protheus.doc} bas2prg.prg
    @type        source
    @author      AdvPP reconstruction
    @description Transpilador QBasic -> AdvPL sobre o runtime qbasic.prg.
                 Le um .bas e emite <nome>_qb.prg (#define QB_LIB +
                 #include "qbasic.prg"). Cada linha do .bas vira um comentario
                 "// <n>: <fonte>" seguido de "nQbLine := n", entao erros de
                 runtime e a depuracao apontam para a linha original.

                 Uso:  advplc run bas2prg.prg      (pergunta o .bas)
                       QB_FILE=nibbles.bas advplc run bas2prg.prg
                       advplc run qbasic.prg        (transpila E executa)

    Semantica preservada (o que exige mais que troca de palavras):
      - SUB/FUNCTION -> Static Function B_<nome>; variaveis nao-SHARED viram
        Private da rotina (locais no QBasic, visiveis a GOSUBs internos);
        DIM SHARED / variaveis do modulo -> Private do Main.
      - Parametros por referencia: o AdvPP nao tem '@' — a rotina devolve
        os parametros em __QBA e o chamador copia de volta (copy-back).
      - FUNCTION f: "f = expr" -> __RET; END/EXIT FUNCTION -> Return __RET.
      - Arrays com base 0 / "a TO b": indices deslocados para base 1.
      - AND/OR/XOR/NOT bit-a-bit sobre -1/0 (QAnd/QOr/...); condicoes via QbT.
      - DEFINT/sufixo %: atribuicao arredonda (QCint), como o QBasic.
      - GOSUB/ON ERROR -> Static Function LB_<label>; GOTO para tras ->
        laco Do While/Loop; DATA/RESTORE <label> -> offsets do pool.
*/
#ifndef QB_LIB
#define QB_LIB
#endif
#include "qbasic.prg"

// ===========================================================================
// Helpers de texto
// ===========================================================================

Static Function B2Trim( s ) ; Return AllTrim( s )
Static Function B2Up( s )   ; Return Upper( s )
Static Function B2I2S( n )  ; Return AllTrim( Str( Int( n ) ) )

Static Function B2IsIdCh( c )
Return c $ "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_.$%#&!"

Static Function B2IsIdStart( c )
Return Len( c ) == 1 .And. c $ "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"

/*/{Protheus.doc} B2In
    Pertinencia exata em lista "A,B,C" (o operador $ e substring e aceita "").
/*/
Static Function B2In( c, cList )
Return Len( c ) > 0 .And. AScan( StrTokArr2( cList, "," ), c ) > 0

Static Function B2IsDigit( c )
Return Len( c ) == 1 .And. c $ "0123456789"

/*/{Protheus.doc} B2SafePath
    Aceita so nomes de arquivo seguros para usar em linha de comando.
/*/
Static Function B2SafePath( c )
    Local i := Nil
    For i := 1 To Len( c )
        If !( SubStr( c, i, 1 ) $ "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-/" )
            Return .F.
        EndIf
    Next
Return Len( c ) > 0

/*/{Protheus.doc} B2Word
    Primeira palavra (identificador, com sufixo/pontos) apos espacos.
/*/
Static Function B2Word( s )
    Local i := 1, n := Len( s ), i0 := Nil
    Do While i <= n .And. SubStr( s, i, 1 ) $ " " + Chr( 9 )
        i += 1
    EndDo
    i0 := i
    Do While i <= n .And. B2IsIdCh( SubStr( s, i, 1 ) )
        i += 1
    EndDo
Return SubStr( s, i0, i - i0 )

/*/{Protheus.doc} B2After
    Texto apos a primeira palavra (trim).
/*/
Static Function B2After( s )
    Local cW := B2Word( s )
Return B2Trim( SubStr( B2Trim( s ), Len( cW ) + 1 ) )

/*/{Protheus.doc} B2StripSuf
    Remove sufixo de tipo ($ % # & !).
/*/
Static Function B2StripSuf( cId )
    If Len( cId ) > 1 .And. Right( cId, 1 ) $ "$%#&!"
        Return Left( cId, Len( cId ) - 1 )
    EndIf
Return cId

/*/{Protheus.doc} B2VarName
    Nome QBasic -> identificador AdvPL (maiusculo, sem sufixo, '.' -> '_').
    "a$" e "a" sao variaveis distintas no QBasic: strings ganham "_S".
/*/
Static Function B2VarName( cRaw )
    Local cU := B2Up( B2Trim( cRaw ) )
    If Len( cU ) > 1 .And. Right( cU, 1 ) == "$"
        Return StrTran( Left( cU, Len( cU ) - 1 ), ".", "_" ) + "_S"
    EndIf
Return StrTran( B2StripSuf( cU ), ".", "_" )

/*/{Protheus.doc} B2StripComment
    Remove comentario ' (fora de string) e REM.
/*/
Static Function B2StripComment( cLine )
    Local i := Nil, c := Nil, lStr := .F.
    For i := 1 To Len( cLine )
        c := SubStr( cLine, i, 1 )
        If c == '"'
            lStr := !lStr
        ElseIf c == "'" .And. !lStr
            Return B2Trim( Left( cLine, i - 1 ) )
        EndIf
    Next
    cLine := B2Trim( StrTran( cLine, Chr( 9 ), " " ) )
    If B2Up( B2Word( cLine ) ) == "REM"
        Return ""
    EndIf
Return cLine

/*/{Protheus.doc} B2SplitColons
    Divide em statements por ':' fora de string.
/*/
Static Function B2SplitColons( cLine )
    Local a := {}, i := Nil, c := Nil, lStr := .F., cCur := ""
    For i := 1 To Len( cLine )
        c := SubStr( cLine, i, 1 )
        If c == '"'
            lStr := !lStr
            cCur += c
        ElseIf c == ":" .And. !lStr
            AAdd( a, cCur )
            cCur := ""
        Else
            cCur += c
        EndIf
    Next
    If Len( B2Trim( cCur ) ) > 0
        AAdd( a, cCur )
    EndIf
Return a

/*/{Protheus.doc} B2SplitCommas
    Divide lista por ',' respeitando strings e parenteses.
/*/
Static Function B2SplitCommas( s )
    Local a := {}, i := Nil, c := Nil, nDepth := 0, cCur := "", lStr := .F.
    For i := 1 To Len( s )
        c := SubStr( s, i, 1 )
        If c == '"'
            lStr := !lStr
            cCur += c
        ElseIf !lStr .And. c == "("
            nDepth += 1
            cCur += c
        ElseIf !lStr .And. c == ")"
            nDepth -= 1
            cCur += c
        ElseIf !lStr .And. c == "," .And. nDepth == 0
            AAdd( a, cCur )
            cCur := ""
        Else
            cCur += c
        EndIf
    Next
    AAdd( a, cCur )
Return a

/*/{Protheus.doc} B2FindKw
    Posicao da palavra-chave cKw (limite de palavra, fora de string e de
    parenteses) a partir de nFrom; 0 se nao houver.
/*/
Static Function B2FindKw( cS, cKw, nFrom )
    Local i := Nil, c := Nil, lStr := .F., nDep := 0, cU := B2Up( cS ), nK := Len( cKw )
    nFrom := IIf( nFrom == Nil, 1, nFrom )
    For i := 1 To Len( cS )
        c := SubStr( cS, i, 1 )
        If c == '"'
            lStr := !lStr
        ElseIf !lStr .And. c == "("
            nDep += 1
        ElseIf !lStr .And. c == ")"
            nDep -= 1
        ElseIf !lStr .And. nDep == 0 .And. i >= nFrom .And. SubStr( cU, i, nK ) == cKw
            If ( i == 1 .Or. !B2IsIdCh( SubStr( cS, i - 1, 1 ) ) ) .And. ;
               ( i + nK > Len( cS ) .Or. !B2IsIdCh( SubStr( cS, i + nK, 1 ) ) )
                Return i
            EndIf
        EndIf
    Next
Return 0

/*/{Protheus.doc} B2FindTop
    Posicao do caractere c fora de string/parenteses; 0 se nao houver.
/*/
Static Function B2FindTop( cS, cCh )
    Local i := Nil, c := Nil, lStr := .F., nDep := 0
    For i := 1 To Len( cS )
        c := SubStr( cS, i, 1 )
        If c == '"'
            lStr := !lStr
        ElseIf !lStr .And. c == "("
            nDep += 1
        ElseIf !lStr .And. c == ")"
            nDep -= 1
        ElseIf !lStr .And. nDep == 0 .And. c == cCh
            Return i
        EndIf
    Next
Return 0

/*/{Protheus.doc} B2Words
    Palavras (maiusculas) fora de strings — para varrer GOSUB/GOTO.
/*/
Static Function B2Words( cS )
    Local a := {}, i := Nil, c := Nil, lStr := .F., cCur := ""
    For i := 1 To Len( cS ) + 1
        c := IIf( i <= Len( cS ), SubStr( cS, i, 1 ), " " )
        If c == '"'
            lStr := !lStr
            c := " "
        EndIf
        If !lStr .And. B2IsIdCh( c ) .And. c != "."
            cCur += B2Up( c )
        ElseIf Len( cCur ) > 0
            AAdd( a, cCur )
            cCur := ""
        EndIf
    Next
Return a

/*/{Protheus.doc} B2LabelName
    Alvo de GOTO/GOSUB/RESTORE -> nome de label (numero de linha -> L<n>).
/*/
Static Function B2LabelName( c )
    c := B2Up( B2Trim( c ) )
    If B2IsDigit( Left( c, 1 ) )
        Return "L" + c
    EndIf
Return c

/*/{Protheus.doc} B2LeadLabel
    Label no inicio da linha ("nome:" ou numero de linha) -> {label, resto}.
/*/
Static Function B2LeadLabel( cCode )
    Local i := 1, n := Len( cCode ), cName := Nil
    Local aKw := { "CLS", "BEEP", "END", "RETURN", "ELSE", "ELSEIF", "ENDIF", "LOOP", "WEND", "NEXT", "DO", ;
                   "RANDOMIZE", "STOP", "SYSTEM", "RESTORE", "PRINT", "LPRINT", "SLEEP", "CLEAR", ;
                   "RESUME", "EXIT", "CASE", "REM", "THEN", "CLOSE", "SCREEN", "LOCATE", "COLOR", ;
                   "GOTO", "GOSUB", "ON", "ERROR", "INPUT", "LINE", "FOR", "WHILE", "UNTIL", ;
                   "SELECT", "DIM", "REDIM", "TYPE", "SUB", "FUNCTION", "DECLARE", "CONST", ;
                   "SHARED", "STATIC", "DEF", "DEFINT", "DEFSNG", "DEFDBL", "DEFLNG", "DEFSTR", ;
                   "OPTION", "OPEN", "WRITE", "FIELD", "LSET", "RSET", "PUT", "GET", "SWAP", ;
                   "ERASE", "KILL", "NAME", "DATA", "READ", "POKE", "PSET", "PRESET", "CIRCLE", ;
                   "PAINT", "DRAW", "PLAY", "SOUND", "OUT", "WAIT", "VIEW", "WINDOW", "PALETTE", ;
                   "PCOPY", "CHAIN", "RUN", "SHELL", "CALL", "WIDTH", "TO", "STEP", "IS", "AS", ;
                   "BASE", "PRESERVE", "LET", "COMMON", "MKDIR", "RMDIR", "CHDIR", "FILES", ;
                   "ENVIRON", "SEEK", "LOCK", "UNLOCK", "TIMER", "KEY", "RANDOM", "BINARY", "ACCESS" }
    If n == 0
        Return { "", "" }
    EndIf
    If B2IsDigit( Left( cCode, 1 ) )
        Do While i <= n .And. B2IsDigit( SubStr( cCode, i, 1 ) )
            i += 1
        EndDo
        Return { "L" + Left( cCode, i - 1 ), B2Trim( SubStr( cCode, i ) ) }
    EndIf
    If !B2IsIdStart( Left( cCode, 1 ) )
        Return { "", cCode }
    EndIf
    cName := B2Word( cCode )
    If SubStr( cCode, Len( cName ) + 1, 1 ) != ":" .Or. Right( cName, 1 ) $ "$%#&!"
        Return { "", cCode }
    EndIf
    If AScan( aKw, B2Up( cName ) ) > 0 .Or. AScan( aSubs, B2VarName( cName ) ) > 0
        Return { "", cCode }
    EndIf
Return { B2Up( cName ), B2Trim( SubStr( cCode, Len( cName ) + 2 ) ) }

/*/{Protheus.doc} B2LeadLabels
    Labels encadeados no inicio da linha — numero de linha e/ou "nome:"
    (ex.: "100 loop: PRINT" gera {L100, LOOP}) -> { {labels}, resto }.
/*/
Static Function B2LeadLabels( cCode )
    Local aLs := {}, aOne := Nil
    Do While .T.
        aOne := B2LeadLabel( cCode )
        If Empty( aOne[1] )
            Exit
        EndIf
        AAdd( aLs, aOne[1] )
        cCode := aOne[2]
        If Empty( cCode )
            Exit
        EndIf
    EndDo
Return { aLs, cCode }

/*/{Protheus.doc} B2Clean
    Texto do fonte seguro para comentario (ASCII).
/*/
Static Function B2Clean( c )
    Local i := Nil, cOut := "", b := Nil
    For i := 1 To Len( c )
        b := Asc( SubStr( c, i, 1 ) )
        cOut += IIf( b < 32 .Or. b > 126, "?", SubStr( c, i, 1 ) )
    Next
Return cOut

/*/{Protheus.doc} B2Warn
    Registra aviso de construcao nao suportada (com linha do .bas).
/*/
Static Function B2Warn( cMsg )
    AAdd( aWarn, "linha " + B2I2S( nCurLine ) + ": " + cMsg )
Return

// ===========================================================================
// Passo A — varredura (declaracoes, labels, tipos)
// ===========================================================================

/*/{Protheus.doc} B2ParseParams
    "a, b() AS T, c$" -> { {nome, lArray, cTipo}, ... }
/*/
Static Function B2ParseParams( cIn )
    Local a := {}, aP := B2SplitCommas( cIn ), i := Nil, cP := Nil, cTy := Nil, nAs := Nil, lArr := Nil
    For i := 1 To Len( aP )
        cP := B2Trim( aP[i] )
        If Empty( cP )
            Loop
        EndIf
        cTy := ""
        nAs := B2FindKw( cP, "AS" )
        If nAs > 0
            cTy := B2Up( B2Trim( SubStr( cP, nAs + 2 ) ) )
            cP := B2Trim( Left( cP, nAs - 1 ) )
        EndIf
        lArr := Right( cP, 2 ) == "()"
        If lArr
            cP := B2Trim( Left( cP, Len( cP ) - 2 ) )
        EndIf
        AAdd( a, { cP, lArr, cTy } )
    Next
Return a

/*/{Protheus.doc} B2SigParse
    "SUB nome (params) [STATIC]" -> {NOME, aParams, lStr}
/*/
Static Function B2SigParse( cRest )
    Local cName := B2Word( cRest ), nP := Nil, nQ := Nil, cIn := ""
    nP := At( "(", cRest )
    If nP > 0
        nQ := Rat( ")", cRest )
        cIn := SubStr( cRest, nP + 1, nQ - nP - 1 )
    EndIf
Return { B2VarName( cName ), B2ParseParams( cIn ), Right( cName, 1 ) == "$" }

/*/{Protheus.doc} B2NoteType
    Registra o tipo declarado (AS ...) de uma variavel.
/*/
Static Function B2NoteType( cRaw, cTy )
    Local cN := B2VarName( cRaw )
    If Right( B2Trim( cRaw ), 1 ) == "$"
        B2AddU( aStrVars, cN )
    EndIf
    If Empty( cTy )
        Return
    EndIf
    cTy := B2Up( B2Trim( cTy ) )
    Do Case
    Case cTy == "INTEGER" .Or. cTy == "LONG"
        B2AddU( aIntVars, cN )
        If cTy == "LONG"
            B2AddU( aLngVars, cN )
        EndIf
    Case cTy == "SINGLE" .Or. cTy == "DOUBLE"
        B2AddU( aFltVars, cN )
    Case Left( cTy, 6 ) == "STRING"
        B2AddU( aStrVars, cN )
    Otherwise
        If AScan( aVarTN, cN ) == 0
            AAdd( aVarType, { cN, cTy } )
            AAdd( aVarTN, cN )
        EndIf
    EndCase
Return

Static Function B2AddU( a, c )
    If AScan( a, c ) == 0
        AAdd( a, c )
    EndIf
Return

/*/{Protheus.doc} B2ScanSubs
    Pre-passo: nomes de SUB/FUNCTION/DEF FN e assinaturas.
/*/
Static Function B2ScanSubs()
    Local i := Nil, cCode := Nil, cW := Nil, cRest := Nil, aSig := Nil, k := Nil
    For i := 1 To Len( aLines )
        cCode := B2StripComment( aLines[i] )
        cW := B2Up( B2Word( cCode ) )
        If cW == "DECLARE"
            cCode := B2After( cCode )
            cW := B2Up( B2Word( cCode ) )
        ElseIf cW == "STATIC" .And. B2In( B2Up( B2Word( B2After( cCode ) ) ), "SUB,FUNCTION" )
            cCode := B2After( cCode )
            cW := B2Up( B2Word( cCode ) )
        EndIf
        cRest := B2After( cCode )
        Do Case
        Case cW == "SUB"
            aSig := B2SigParse( cRest )
            B2AddU( aSubs, aSig[1] )
            B2AddSig( aSig )
        Case cW == "FUNCTION"
            aSig := B2SigParse( cRest )
            B2AddU( aFnN, aSig[1] )
            B2AddSig( aSig )
            If aSig[3]
                B2AddU( aStrVars, aSig[1] )
            EndIf
        Case cW == "DEF" .And. B2Up( Left( cRest, 2 ) ) == "FN"
            B2AddU( aFnN, B2VarName( B2Word( cRest ) ) )
        EndCase
    Next
    For k := 1 To Len( aSig2 )
        For i := 1 To Len( aSig2[k][2] )
            B2NoteType( aSig2[k][2][i][1], aSig2[k][2][i][3] )
            If aSig2[k][2][i][2]
                B2AddU( aArrN, B2VarName( aSig2[k][2][i][1] ) )
            EndIf
        Next
    Next
Return

Static Function B2AddSig( aSig )
    Local k := AScan( aSig2, {|x| x[1] == aSig[1] } )
    If k == 0
        AAdd( aSig2, aSig )
    ElseIf Len( aSig[2] ) > 0
        aSig2[k] := aSig
    EndIf
Return

Static Function B2GetSig( cName )
    Local k := AScan( aSig2, {|x| x[1] == cName } )
Return IIf( k > 0, aSig2[k], Nil )

/*/{Protheus.doc} B2Scan
    Passo A: CONST, TYPE, DIM (tipos e limites), DATA, DEFINT/DEFSTR,
    OPTION BASE, labels e alvos de GOSUB/GOTO/ON ERROR.
/*/
Static Function B2Scan()
    Local i := Nil, k := Nil, cCode := Nil, aLead := Nil, aSt := Nil, cS := Nil, cW := Nil, cRest := Nil, aW := Nil, j := Nil, lInType := .F., cTyName := ""
    Local aFlds := {}, aFTys := {}, nAs := Nil, aGoto := {}, nLbl := Nil
    aDepth := B2Depths()
    For i := 1 To Len( aLines )
        nCurLine := i
        cCode := B2StripComment( aLines[i] )
        aLead := B2LeadLabels( cCode )
        For k := 1 To Len( aLead[1] )
            AAdd( aLblPos, { aLead[1][k], i } )
            AAdd( aDataLbl, { aLead[1][k], Len( aData ) } )
        Next
        cCode := aLead[2]
        If Empty( cCode ) .Or. B2Up( B2Word( cCode ) ) == "REM"
            Loop
        EndIf
        // alvos de desvio (inclusive dentro de IF de uma linha)
        aW := B2Words( cCode )
        For j := 1 To Len( aW ) - 1
            Do Case
            Case aW[j] == "GOSUB"
                B2AddU( aFnLbl, B2LabelName( aW[j+1] ) )
            Case aW[j] == "GOTO" .And. j > 1 .And. aW[j-1] == "ERROR"
                If aW[j+1] != "0"
                    B2AddU( aFnLbl, B2LabelName( aW[j+1] ) )
                    B2AddU( aErrLbl, B2LabelName( aW[j+1] ) )
                EndIf
            Case aW[j] == "GOTO" .Or. ( ( aW[j] == "THEN" .Or. aW[j] == "ELSE" ) .And. B2IsDigit( Left( aW[j+1], 1 ) ) )
                AAdd( aGoto, { B2LabelName( aW[j+1] ), i } )
            Case aW[j] == "RESUME" .And. aW[j+1] != "NEXT" .And. !B2IsDigit( Left( aW[j+1], 1 ) )
                B2AddU( aResLbl, B2LabelName( aW[j+1] ) )
            EndCase
        Next

        aSt := B2SplitColons( cCode )
        For k := 1 To Len( aSt )
            cS := B2Trim( aSt[k] )
            cW := B2Up( B2Word( cS ) )
            cRest := B2After( cS )
            If lInType
                If cW == "END" .And. B2Up( B2Word( cRest ) ) == "TYPE"
                    AAdd( aType, { cTyName, aFlds, aFTys } )
                    lInType := .F.
                ElseIf !Empty( cW )
                    nAs := B2FindKw( cS, "AS" )
                    AAdd( aFlds, B2VarName( cW ) )
                    AAdd( aFTys, IIf( nAs > 0, B2Up( B2Trim( SubStr( cS, nAs + 2 ) ) ), "SINGLE" ) )
                EndIf
                Loop
            EndIf
            Do Case
            Case cW == "TYPE"
                cTyName := B2Up( B2Word( cRest ) )
                aFlds := {}
                aFTys := {}
                lInType := .T.
            Case cW == "CONST"
                B2AddConst( cRest )
            Case cW == "DIM" .Or. cW == "REDIM" .Or. cW == "COMMON" .Or. cW == "STATIC"
                B2ScanDim( cRest )
            Case cW == "SHARED"
                B2ScanShared( cRest )
            Case cW == "DATA"
                B2ScanData( cRest )
            Case cW == "DEFINT" .Or. cW == "DEFLNG"
                cDefInt += B2Letters( cRest )
            Case cW == "DEFSTR"
                cDefStr += B2Letters( cRest )
            Case cW == "OPTION" .And. B2Up( B2Word( cRest ) ) == "BASE"
                cBase := B2Trim( B2After( cRest ) )
            EndCase
        Next
    Next
    // GOTO para tras na mesma rotina -> laco estruturado
    For k := 1 To Len( aGoto )
        nLbl := AScan( aLblPos, {|x| x[1] == aGoto[k][1] } )
        If nLbl > 0 .And. aLblPos[nLbl][2] < aGoto[k][2] .And. AScan( aFnLbl, aGoto[k][1] ) == 0
            j := AScan( aGotoLoop, {|x| x[1] == aGoto[k][1] } )
            If j == 0
                AAdd( aGotoLoop, { aGoto[k][1], aGoto[k][2] } )
            Else
                aGotoLoop[j][2] := Max( aGotoLoop[j][2], aGoto[k][2] )
            EndIf
        EndIf
    Next
    // GOTO para frente na mesma profundidade de bloco -> guarda __QBG_<lbl>
    For k := 1 To Len( aGoto )
        nLbl := AScan( aLblPos, {|x| x[1] == aGoto[k][1] } )
        If nLbl > 0 .And. aLblPos[nLbl][2] > aGoto[k][2] .And. AScan( aFnLbl, aGoto[k][1] ) == 0 .And. ;
           aDepth[ aGoto[k][2] ] == aDepth[ aLblPos[nLbl][2] ]
            AAdd( aGotoFwd, { aGoto[k][1], aGoto[k][2] } )
        EndIf
    Next
    B2PlanDispatch( aGoto )
Return

/*/{Protheus.doc} B2PlanDispatch
    Decide quais regioes (rid) precisam do dispatcher de PC:
    0 = fluxo do modulo; cada SUB/FUNCTION/DEF FN e cada label-alvo de
    GOSUB/ON ERROR abre um novo rid. Um rid vira dispatch quando tem:
    (a) GOTO intra-rotina que cruza fronteira de bloco (profundidade dif.),
    (b) label alvo de RESUME <lbl>,
    (c) statement ON ERROR (o Catch do dispatcher chama o tratador),
    (d) ser alvo de GOTO cross-routine.
    Nesta VM o EndTry interno limpa o handler do frame, entao rotinas com
    dispatch nao podem ter Try aninhado: o Catch do dispatcher faz tudo.
/*/
Static Function B2PlanDispatch( aGoto )
    Local i := Nil, k := Nil, j := Nil, nLbl := Nil, nRid := 0
    Local cCode := Nil, aLead := Nil, cW := Nil, cRest := Nil, aW := Nil
    // rid por linha
    aRid := {}
    For i := 1 To Len( aLines )
        cCode := B2StripComment( aLines[i] )
        aLead := B2LeadLabels( cCode )
        For k := 1 To Len( aLead[1] )
            If AScan( aFnLbl, aLead[1][k] ) > 0
                nRid += 1
                Exit
            EndIf
        Next
        cW := B2Up( B2Word( aLead[2] ) )
        cRest := B2After( aLead[2] )
        If cW == "STATIC" .And. B2In( B2Up( B2Word( cRest ) ), "SUB,FUNCTION" )
            cW := B2Up( B2Word( cRest ) )
            cRest := B2After( cRest )
        EndIf
        If cW == "SUB" .Or. cW == "FUNCTION" .Or. ;
           ( cW == "DEF" .And. B2Up( Left( cRest, 2 ) ) == "FN" .And. B2FindTop( cRest, "=" ) == 0 )
            nRid += 1
        EndIf
        AAdd( aRid, nRid )
        If cW == "END" .And. B2In( B2Up( B2Word( cRest ) ), "SUB,FUNCTION,DEF" )
            nRid := 0
        EndIf
    Next
    // criterios (a) e (d)
    For k := 1 To Len( aGoto )
        nLbl := AScan( aLblPos, {|x| x[1] == aGoto[k][1] } )
        If nLbl == 0
            Loop
        EndIf
        If aRid[ aGoto[k][2] ] == aRid[ aLblPos[nLbl][2] ]
            If aDepth[ aGoto[k][2] ] != aDepth[ aLblPos[nLbl][2] ]
                B2AddU( aDispRid, aRid[ aGoto[k][2] ] )
            EndIf
        ElseIf AScan( aFnLbl, aGoto[k][1] ) == 0
            B2AddU( aDispRid, aRid[ aLblPos[nLbl][2] ] )
            B2Warn( "GOTO " + aGoto[k][1] + " cruza rotinas — alcança so se a rotina alvo estiver na pilha" )
        EndIf
    Next
    // criterio (b): RESUME <lbl>
    For k := 1 To Len( aResLbl )
        nLbl := AScan( aLblPos, {|x| x[1] == aResLbl[k] } )
        If nLbl > 0
            B2AddU( aDispRid, aRid[ aLblPos[nLbl][2] ] )
        Else
            B2Warn( "RESUME para label desconhecido " + aResLbl[k] )
        EndIf
    Next
    // criterio (c): ON ERROR GOTO dentro do rid
    If Len( aErrLbl ) > 0
        For i := 1 To Len( aLines )
            cCode := B2LeadLabels( B2StripComment( aLines[i] ) )[2]
            aW := B2Words( cCode )
            For j := 1 To Len( aW ) - 2
                If aW[j] == "ON" .And. aW[j+1] == "ERROR" .And. aW[j+2] == "GOTO"
                    B2AddU( aDispRid, aRid[i] )
                EndIf
            Next
        Next
    EndIf
    // labels alvos dentro de rids com dispatch (mapa do dispatcher)
    For k := 1 To Len( aLblPos )
        If AScan( aDispRid, aRid[ aLblPos[k][2] ] ) > 0
            AAdd( aDispLbls, { aLblPos[k][1], aRid[ aLblPos[k][2] ] } )
        EndIf
    Next
    // em rids com dispatch nenhum GOTO usa laco/guarda: remove os cadastros
    j := 1
    Do While j <= Len( aGotoLoop )
        nLbl := AScan( aLblPos, {|x| x[1] == aGotoLoop[j][1] } )
        If nLbl > 0 .And. AScan( aDispRid, aRid[ aLblPos[nLbl][2] ] ) > 0
            ADel( aGotoLoop, j )      // ADel ja trunca nesta VM
        Else
            j += 1
        EndIf
    EndDo
    j := 1
    Do While j <= Len( aGotoFwd )
        nLbl := AScan( aLblPos, {|x| x[1] == aGotoFwd[j][1] } )
        If ( nLbl > 0 .And. AScan( aDispRid, aRid[ aLblPos[nLbl][2] ] ) > 0 ) .Or. ;
           AScan( aDispRid, aRid[ aGotoFwd[j][2] ] ) > 0
            ADel( aGotoFwd, j )
        Else
            j += 1
        EndIf
    EndDo
Return

/*/{Protheus.doc} B2Depths
    Profundidade de bloco (IF/FOR/DO/WHILE/SELECT/rotina) no inicio de cada
    linha — usada para decidir se um GOTO para frente e "local" (mesma
    profundidade no salto e no alvo).
/*/
Static Function B2Depths()
    Local aD := {}, i := Nil, k := Nil, cCode := Nil, aSt := Nil, cS := Nil, cW := Nil, cRest := Nil, nDep := 0, nTh := 0
    For i := 1 To Len( aLines )
        AAdd( aD, nDep )
        cCode := B2LeadLabels( B2StripComment( aLines[i] ) )[2]
        If B2Up( B2Word( cCode ) ) == "REM"
            Loop
        EndIf
        aSt := B2Statements( cCode )
        For k := 1 To Len( aSt )
            cS := B2Trim( aSt[k] )
            cW := B2Up( B2Word( cS ) )
            cRest := B2After( cS )
            Do Case
            Case cW == "IF"
                nTh := B2FindKw( cRest, "THEN" )
                If nTh == 0 .Or. Empty( B2Trim( SubStr( cRest, nTh + 4 ) ) )
                    nDep += 1
                EndIf
            Case cW == "FOR" .Or. cW == "WHILE" .Or. cW == "SELECT" .Or. cW == "DO"
                nDep += 1
            Case cW == "SUB" .Or. cW == "FUNCTION"
                nDep := 0
            Case cW == "NEXT"
                nDep -= IIf( Empty( cRest ), 1, Len( B2SplitCommas( cRest ) ) )
            Case cW == "WEND" .Or. cW == "LOOP"
                nDep -= 1
            Case cW == "END" .And. B2In( B2Up( B2Word( cRest ) ), "IF,SELECT,SUB,FUNCTION,DEF,TYPE" )
                nDep -= 1
            EndCase
            If nDep < 0
                nDep := 0
            EndIf
        Next
    Next
Return aD

/*/{Protheus.doc} B2Letters
    "A-Z" / "A-C, X" -> "ABC...".
/*/
Static Function B2Letters( cRest )
    Local a := B2SplitCommas( cRest ), i := Nil, c := Nil, cOut := "", n1 := Nil, n2 := Nil, n := Nil
    For i := 1 To Len( a )
        c := B2Up( StrTran( a[i], " ", "" ) )
        If Len( c ) == 0
            Loop
        EndIf
        n1 := Asc( Left( c, 1 ) )
        n2 := IIf( "-" $ c, Asc( Right( c, 1 ) ), n1 )
        For n := n1 To n2
            cOut += Chr( n )
        Next
    Next
Return cOut

/*/{Protheus.doc} B2AddConst
    CONST a = 1, b = a * 2 — valor ja traduzido para AdvPL.
/*/
Static Function B2AddConst( cRest )
    Local a := B2SplitCommas( cRest ), i := Nil, cI := Nil, nEq := Nil, cN := Nil, cV := Nil
    For i := 1 To Len( a )
        cI := a[i]
        nEq := At( "=", cI )
        If nEq == 0
            Loop
        EndIf
        cN := B2VarName( Left( cI, nEq - 1 ) )
        cV := B2Expr( SubStr( cI, nEq + 1 ), .F. )
        If !( B2IsNumLit( cV ) .Or. Left( cV, 1 ) == '"' )
            cV := "(" + cV + ")"
        EndIf
        AAdd( aConst, { cN, cV } )
        AAdd( aConstN, cN )
    Next
Return

/*/{Protheus.doc} B2ScanDim
    DIM [SHARED] a(1 TO n, m) AS T, ... — registra arrays, limites e tipos.
/*/
Static Function B2ScanDim( cRest )
    Local lShared := .F., a := Nil, i := Nil, cI := Nil, cName := Nil, nP := Nil, nQ := Nil, cDims := Nil, aD := Nil, aLB := Nil, k := Nil, nTo := Nil, nAs := Nil, cTy := Nil
    If B2Up( B2Word( cRest ) ) == "SHARED"
        lShared := .T.
        cRest := B2After( cRest )
    EndIf
    If B2Up( B2Word( cRest ) ) == "PRESERVE"
        cRest := B2After( cRest )
    EndIf
    a := B2SplitCommas( cRest )
    For i := 1 To Len( a )
        cI := B2Trim( a[i] )
        If Empty( cI )
            Loop
        EndIf
        cName := B2Word( cI )
        nAs := B2FindKw( cI, "AS" )
        cTy := IIf( nAs > 0, SubStr( cI, nAs + 2 ), "" )
        B2NoteType( cName, cTy )
        If lShared
            B2AddU( aShared, B2VarName( cName ) )
        EndIf
        nP := At( "(", cI )
        If nP > 0 .And. ( nAs == 0 .Or. nP < nAs )
            B2AddU( aArrN, B2VarName( cName ) )
            nQ := Rat( ")", IIf( nAs > 0, Left( cI, nAs - 1 ), cI ) )
            cDims := SubStr( cI, nP + 1, nQ - nP - 1 )
            If !Empty( cDims ) .And. AScan( aArrLB, {|x| x[1] == B2VarName( cName ) } ) == 0
                aD := B2SplitCommas( cDims )
                aLB := {}
                For k := 1 To Len( aD )
                    nTo := B2FindKw( aD[k], "TO" )
                    AAdd( aLB, IIf( nTo > 0, B2Trim( Left( aD[k], nTo - 1 ) ), cBase ) )
                Next
                AAdd( aArrLB, { B2VarName( cName ), aLB } )
            EndIf
        EndIf
    Next
Return

Static Function B2ScanShared( cRest )
    Local a := B2SplitCommas( cRest ), i := Nil, cI := Nil, nAs := Nil
    For i := 1 To Len( a )
        cI := B2Trim( a[i] )
        If Empty( cI )
            Loop
        EndIf
        nAs := B2FindKw( cI, "AS" )
        B2NoteType( B2Word( cI ), IIf( nAs > 0, SubStr( cI, nAs + 2 ), "" ) )
        B2AddU( aShared, B2VarName( B2Word( cI ) ) )
    Next
Return

/*/{Protheus.doc} B2ScanData
    DATA 1, -2, "txt", txt — itens viram literais AdvPL do pool aQbData.
/*/
Static Function B2ScanData( cRest )
    Local a := B2SplitCommas( cRest ), i := Nil, cI := Nil
    For i := 1 To Len( a )
        cI := B2Trim( a[i] )
        If Left( cI, 1 ) == '"'
            AAdd( aData, B2SanitizeStr( cI ) )
        ElseIf B2IsNumLit( StrTran( StrTran( cI, "-", "" ), "+", "" ) )
            AAdd( aData, B2NumLit( cI ) )
        ElseIf Left( B2Up( cI ), 2 ) == "&H"
            AAdd( aData, B2I2S( B2HexVal( SubStr( cI, 3 ) ) ) )
        Else
            AAdd( aData, '"' + StrTran( cI, '"', "'" ) + '"' )
        EndIf
    Next
Return

/*/{Protheus.doc} B2MapParams
    Limites de arrays recebidos por parametro: segue as chamadas
    "Sub arr(), ..." e herda os limites do array real.
/*/
Static Function B2MapParams()
    Local i := Nil, k := Nil, j := Nil, cCode := Nil, aSt := Nil, cS := Nil, cW := Nil, cArgs := Nil, aSig := Nil, aA := Nil, cA := Nil, nArr := Nil
    For i := 1 To Len( aLines )
        cCode := B2LeadLabels( B2StripComment( aLines[i] ) )[2]
        aSt := B2Flatten( cCode )
        For k := 1 To Len( aSt )
            cS := B2Trim( aSt[k] )
            cW := B2Up( B2Word( cS ) )
            cArgs := B2After( cS )
            If cW == "CALL"
                cW := B2Up( B2Word( cArgs ) )
                cArgs := B2After( cArgs )
                If Left( cArgs, 1 ) == "("
                    cArgs := SubStr( cArgs, 2, Rat( ")", cArgs ) - 2 )
                EndIf
            EndIf
            aSig := B2GetSig( B2VarName( cW ) )
            If aSig == Nil .Or. AScan( aSubs, B2VarName( cW ) ) == 0
                Loop
            EndIf
            aA := B2SplitCommas( cArgs )
            For j := 1 To Min( Len( aA ), Len( aSig[2] ) )
                cA := B2Trim( aA[j] )
                If aSig[2][j][2] .And. Right( cA, 2 ) == "()"
                    nArr := AScan( aArrLB, {|x| x[1] == B2VarName( Left( cA, Len( cA ) - 2 ) ) } )
                    If nArr > 0
                        AAdd( aParamLB, { aSig[1] + "." + B2VarName( aSig[2][j][1] ), aArrLB[nArr][2] } )
                    EndIf
                EndIf
            Next
        Next
    Next
Return

/*/{Protheus.doc} B2Flatten
    Statements de uma linha, abrindo os ramos de IF ... THEN a ELSE b.
/*/
Static Function B2Flatten( cCode )
    Local aR := {}, aSt := B2Statements( cCode ), k := 0, cS := "", nTh := 0, nEl := 0, cTail := ""
    For k := 1 To Len( aSt )
        cS := B2Trim( aSt[k] )
        nTh := IIf( B2Up( B2Word( cS ) ) == "IF", B2FindKw( cS, "THEN" ), 0 )
        If nTh > 0 .And. !Empty( B2Trim( SubStr( cS, nTh + 4 ) ) )
            cTail := B2Trim( SubStr( cS, nTh + 4 ) )
            nEl := B2FindKw( cTail, "ELSE" )
            If nEl > 0
                B2AddLines( aR, B2Flatten( SubStr( cTail, nEl + 4 ) ) )
                cTail := Left( cTail, nEl - 1 )
            EndIf
            B2AddLines( aR, B2Flatten( cTail ) )
        Else
            AAdd( aR, cS )
        EndIf
    Next
Return aR

// ===========================================================================
// Tipos (TYPE ... END TYPE)
// ===========================================================================

Static Function B2TypeOf( cVar )
    Local k := AScan( aVarType, {|x| x[1] == cVar } )
Return IIf( k > 0, aVarType[k][2], "" )

Static Function B2TypeRec( cTy )
    Local k := AScan( aType, {|x| x[1] == B2Up( cTy ) } )
Return IIf( k > 0, aType[k], Nil )

/*/{Protheus.doc} B2TypeTpl
    Literal modelo de um TYPE: {0, "", {..}} (campos aninhados inclusos).
/*/
Static Function B2TypeTpl( cTy )
    Local aT := B2TypeRec( cTy ), c := "{", i := Nil, cFt := Nil
    If aT == Nil
        Return "0"
    EndIf
    For i := 1 To Len( aT[2] )
        cFt := aT[3][i]
        c += IIf( i > 1, ", ", "" )
        Do Case
        Case Left( cFt, 6 ) == "STRING"
            c += '""'
        Case B2TypeRec( cFt ) != Nil
            c += B2TypeTpl( cFt )
        Otherwise
            c += "0"
        EndCase
    Next
Return c + "}"

/*/{Protheus.doc} B2FieldPath
    ".a.b" sobre o TYPE cTy -> "[ia][ib]". aRet[2] = tipo do ultimo campo.
/*/
Static Function B2FieldPath( cTy, cPath )
    Local aF := StrTokArr2( cPath, "." ), i := Nil, aT := Nil, k := Nil, cOut := "", cFt := ""
    For i := 1 To Len( aF )
        aT := B2TypeRec( cTy )
        k := 0
        If aT != Nil
            k := AScan( aT[2], B2VarName( aF[i] ) )
        EndIf
        If k == 0
            B2Warn( "campo desconhecido ." + aF[i] )
            Return { cOut + "[1]", "" }
        EndIf
        cOut += "[" + B2I2S( k ) + "]"
        cFt := aT[3][k]
        cTy := cFt
    Next
Return { cOut, cFt }

// ===========================================================================
// Classificacao de variaveis
// ===========================================================================

Static Function B2IsStrVar( cN, cRaw )
    If cRaw != Nil .And. Right( B2Trim( cRaw ), 1 ) == "$"
        Return .T.
    EndIf
    If AScan( aStrVars, cN ) > 0
        Return .T.
    EndIf
    If AScan( aIntVars, cN ) > 0 .Or. AScan( aFltVars, cN ) > 0 .Or. AScan( aVarTN, cN ) > 0
        Return .F.
    EndIf
    If cRaw != Nil .And. Len( B2Trim( cRaw ) ) > 0 .And. Right( B2Trim( cRaw ), 1 ) $ "%&!#"
        Return .F.
    EndIf
Return Len( cN ) > 0 .And. Left( cN, 1 ) $ cDefStr

Static Function B2IsIntVar( cN, cRaw )
    If cRaw != Nil .And. Len( B2Trim( cRaw ) ) > 0 .And. Right( B2Trim( cRaw ), 1 ) $ "%&"
        Return .T.
    EndIf
    If cRaw != Nil .And. Len( B2Trim( cRaw ) ) > 0 .And. Right( B2Trim( cRaw ), 1 ) $ "$!#"
        Return .F.
    EndIf
    If AScan( aIntVars, cN ) > 0
        Return .T.
    EndIf
    If AScan( aFltVars, cN ) > 0 .Or. AScan( aStrVars, cN ) > 0 .Or. AScan( aVarTN, cN ) > 0
        Return .F.
    EndIf
Return Len( cN ) > 0 .And. Left( cN, 1 ) $ cDefInt

/*/{Protheus.doc} B2Rec
    Registra variavel usada/atribuida na rotina dona corrente.
/*/
Static Function B2Rec( cN )
    If nOwner == 0 .Or. AScan( aCurParams, cN ) > 0
        Return
    EndIf
    B2AddU( aOwners[nOwner][2], cN )
Return

// ===========================================================================
// Expressoes
// ===========================================================================

Static Function B2IsNumLit( c )
    Local i := Nil, ch := Nil, lDig := .F.
    c := B2Trim( c )
    If Len( c ) == 0
        Return .F.
    EndIf
    For i := 1 To Len( c )
        ch := SubStr( c, i, 1 )
        If B2IsDigit( ch )
            lDig := .T.
        ElseIf !( ch $ ".-+eEdD" )
            Return .F.
        EndIf
    Next
Return lDig .And. B2IsDigit( Left( StrTran( StrTran( c, "-", "" ), ".", "" ), 1 ) )

/*/{Protheus.doc} B2NumLit
    Literal numerico QBasic -> AdvPL (.5 -> 0.5, 1D3 -> 1E3, sem sufixo).
/*/
Static Function B2NumLit( c )
    c := B2Trim( c )
    If Right( c, 1 ) $ "#%!&"
        c := Left( c, Len( c ) - 1 )
    EndIf
    c := StrTran( StrTran( c, "D", "E" ), "d", "E" )
    If Left( c, 1 ) == "."
        c := "0" + c
    ElseIf Left( c, 2 ) == "-."
        c := "-0" + SubStr( c, 2 )
    EndIf
    If Right( c, 1 ) == "."
        c := Left( c, Len( c ) - 1 )
    EndIf
Return c

Static Function B2HexVal( s )
    Local n := 0, i := Nil, k := Nil
    For i := 1 To Len( s )
        k := At( B2Up( SubStr( s, i, 1 ) ), "0123456789ABCDEF" )
        If k == 0
            Exit
        EndIf
        n := n * 16 + k - 1
    Next
Return n

Static Function B2OctVal( s )
    Local n := 0, i := Nil
    For i := 1 To Len( s )
        If !( SubStr( s, i, 1 ) $ "01234567" )
            Exit
        EndIf
        n := n * 8 + Val( SubStr( s, i, 1 ) )
    Next
Return n

/*/{Protheus.doc} B2SanitizeStr
    Literal "..." com bytes CP437 (>127 ou controle) -> glifos Unicode.
/*/
Static Function B2SanitizeStr( cTok )
    Local cInner := SubStr( cTok, 2, Len( cTok ) - 2 ), i := Nil, nB := Nil, cOut := ""
    For i := 1 To Len( cInner )
        nB := Asc( SubStr( cInner, i, 1 ) )
        If nB > 127 .Or. ( nB < 32 .And. nB != 9 )
            cOut += aB2Cp[ nB + 1 ]
        Else
            cOut += SubStr( cInner, i, 1 )
        EndIf
    Next
Return '"' + cOut + '"'

/*/{Protheus.doc} B2Tok
    Tokeniza: S string, N numero, I ident, F ident(...), P (...), O operador.
/*/
Static Function B2Tok( cE )
    Local a := {}, i := 1, n := Len( cE ), c := Nil, c2 := Nil, cTok := Nil, nDep := Nil, cB := Nil, cCh := Nil
    Local aKw := { "AND", "OR", "XOR", "NOT", "MOD", "EQV", "IMP", "TO", "STEP", "THEN", "ELSE", "IS" }
    Do While i <= n
        c := SubStr( cE, i, 1 )
        If c == " " .Or. c == Chr( 9 )
            i += 1
            Loop
        EndIf
        If c == "&" .And. i + 1 <= n .And. B2Up( SubStr( cE, i + 1, 1 ) ) $ "HO"
            cB := B2Up( SubStr( cE, i + 1, 1 ) )
            cTok := ""
            i += 2
            Do While i <= n .And. SubStr( cE, i, 1 ) $ "0123456789ABCDEFabcdef"
                cTok += SubStr( cE, i, 1 )
                i += 1
            EndDo
            If i <= n .And. SubStr( cE, i, 1 ) $ "&%"
                i += 1
            EndIf
            AAdd( a, { "N", B2I2S( IIf( cB == "H", B2HexVal( cTok ), B2OctVal( cTok ) ) ) } )
            Loop
        EndIf
        If c == '"'
            cTok := c
            i += 1
            Do While i <= n .And. SubStr( cE, i, 1 ) != '"'
                cTok += SubStr( cE, i, 1 )
                i += 1
            EndDo
            AAdd( a, { "S", cTok + '"' } )
            i += 1
            Loop
        EndIf
        If B2IsDigit( c ) .Or. ( c == "." .And. B2IsDigit( SubStr( cE, i + 1, 1 ) ) )
            cTok := c
            i += 1
            Do While i <= n
                cCh := SubStr( cE, i, 1 )
                If B2IsDigit( cCh ) .Or. cCh == "."
                    cTok += cCh
                ElseIf B2Up( cCh ) $ "ED" .And. ( B2IsDigit( SubStr( cE, i + 1, 1 ) ) .Or. ;
                        ( SubStr( cE, i + 1, 1 ) $ "+-" .And. B2IsDigit( SubStr( cE, i + 2, 1 ) ) ) )
                    cTok += cCh + SubStr( cE, i + 1, 1 )
                    i += 1
                ElseIf cCh $ "#%!&"
                    i += 1
                    Exit
                Else
                    Exit
                EndIf
                i += 1
            EndDo
            AAdd( a, { "N", B2NumLit( cTok ) } )
            Loop
        EndIf
        If B2IsIdStart( c )
            cTok := c
            i += 1
            Do While i <= n .And. B2IsIdCh( SubStr( cE, i, 1 ) )
                cTok += SubStr( cE, i, 1 )
                i += 1
            EndDo
            Do While i <= n .And. SubStr( cE, i, 1 ) == " "
                i += 1
            EndDo
            If i <= n .And. SubStr( cE, i, 1 ) == "(" .And. AScan( aKw, B2Up( cTok ) ) == 0
                nDep := 0
                Do While i <= n
                    cCh := SubStr( cE, i, 1 )
                    cTok += cCh
                    If cCh == '"'
                        i += 1
                        Do While i <= n .And. SubStr( cE, i, 1 ) != '"'
                            cTok += SubStr( cE, i, 1 )
                            i += 1
                        EndDo
                        cTok += '"'
                    ElseIf cCh == "("
                        nDep += 1
                    ElseIf cCh == ")"
                        nDep -= 1
                        If nDep == 0
                            i += 1
                            Exit
                        EndIf
                    EndIf
                    i += 1
                EndDo
                AAdd( a, { "F", cTok } )
            Else
                AAdd( a, { "I", cTok } )
            EndIf
            Loop
        EndIf
        If c == "("
            nDep := 0
            cTok := ""
            Do While i <= n
                cCh := SubStr( cE, i, 1 )
                cTok += cCh
                If cCh == '"'
                    i += 1
                    Do While i <= n .And. SubStr( cE, i, 1 ) != '"'
                        cTok += SubStr( cE, i, 1 )
                        i += 1
                    EndDo
                    cTok += '"'
                ElseIf cCh == "("
                    nDep += 1
                ElseIf cCh == ")"
                    nDep -= 1
                    If nDep == 0
                        i += 1
                        Exit
                    EndIf
                EndIf
                i += 1
            EndDo
            AAdd( a, { "P", cTok } )
            Loop
        EndIf
        c2 := SubStr( cE, i, 2 )
        If AScan( { ">=", "<=", "<>", "=<", "=>", "><" }, c2 ) > 0
            AAdd( a, { "O", c2 } )
            i += 2
        Else
            AAdd( a, { "O", c } )
            i += 1
        EndIf
    EndDo
Return a

/*/{Protheus.doc} B2Expr
    Traduz expressao QBasic -> AdvPL. lCond = contexto de condicao
    (comparacoes ficam logicas; fora dele viram -1/0 via QbN).
/*/
Static Function B2Expr( cE, lCond )
    Local a := B2Tok( cE ), aOut := {}, i := Nil, cT := Nil, cX := Nil, cU := Nil, nWrap := 0, lField := .F., aFP := Nil
    Local aLog := { "AND", "OR", "XOR", "NOT", "EQV", "IMP" }, cBaseArr := ""
    For i := 1 To Len( a )
        cT := a[i][1]
        cX := a[i][2]
        cU := B2Up( cX )
        If cT == "I" .And. ( AScan( aLog, cU ) > 0 .Or. cU == "MOD" )
            cT := "O"
        EndIf
        If cT == "I" .And. lField
            lField := .F.
            aFP := B2FieldPath( B2TypeOf( cBaseArr ), cU )
            If Len( aOut ) > 0
                aOut[ Len( aOut ) ] += aFP[1]
            EndIf
            Loop
        EndIf
        Do Case
        Case cT == "S"
            AAdd( aOut, B2SanitizeStr( cX ) )
        Case cT == "N"
            AAdd( aOut, cX )
        Case cT == "I"
            AAdd( aOut, B2Ident( cX ) )
        Case cT == "F"
            cBaseArr := B2VarName( Left( cX, At( "(", cX ) - 1 ) )
            AAdd( aOut, B2Call( cX ) )
        Case cT == "P"
            AAdd( aOut, "(" + B2Expr( SubStr( cX, 2, Len( cX ) - 2 ), lCond ) + ")" )
        Case cT == "O"
            Do Case
            Case cU == "MOD" .Or. cU == "\"
                If Len( aOut ) > 0
                    B2Absorb( aOut )
                    aOut[ Len( aOut ) ] := IIf( cU == "MOD", "QMod(", "IntDiv(" ) + aOut[ Len( aOut ) ] + ", "
                    nWrap := 1
                EndIf
                Loop
            Case AScan( aLog, cU ) > 0
                AAdd( aOut, "@" + cU + "@" )
            Case cU == "="
                AAdd( aOut, "==" )
            Case cU == "<>" .Or. cU == "><"
                AAdd( aOut, "!=" )
            Case cU == "=<"
                AAdd( aOut, "<=" )
            Case cU == "=>"
                AAdd( aOut, ">=" )
            Case cU == "."
                lField := .T.
            Case cU == "#" .Or. cU == "&"
                // numero de arquivo / literal solto: ignorado
            Otherwise
                If nWrap == 1 .And. ( cU == "-" .Or. cU == "+" ) .And. Right( aOut[ Len( aOut ) ], 2 ) == ", "
                    aOut[ Len( aOut ) ] += cU
                    Loop
                EndIf
                AAdd( aOut, cU )
            EndCase
        EndCase
        If nWrap == 1 .And. cT $ "SNIFP"
            nWrap := 0
            aOut[ Len( aOut ) - 1 ] += aOut[ Len( aOut ) ] + ")"
            ASize( aOut, Len( aOut ) - 1 )
        EndIf
    Next
Return B2Join( aOut, lCond )

/*/{Protheus.doc} B2Absorb
    Junta a cadeia "a * b / c" no fim de aOut num unico item (operando
    esquerdo de MOD e '\', que tem precedencia menor que * e /).
/*/
Static Function B2Absorb( aOut )
    Local j := Len( aOut ), c := Nil, i := Nil
    Do While j >= 3 .And. ( aOut[ j - 1 ] == "*" .Or. aOut[ j - 1 ] == "/" )
        j -= 2
    EndDo
    If j < Len( aOut )
        c := ""
        For i := j To Len( aOut )
            c += aOut[i]
        Next
        ASize( aOut, j )
        aOut[j] := c
    EndIf
Return

/*/{Protheus.doc} B2Join
    Monta a expressao respeitando a precedencia dos operadores logicos
    (IMP < EQV < XOR < OR < AND < NOT < relacionais).
/*/
Static Function B2Join( aOut, lCond )
    Local aOps := { "@IMP@", "@EQV@", "@XOR@", "@OR@", "@AND@" }
    Local aFn  := { "QImp", "QEqv", "QXor", "QOr", "QAnd" }
    Local k := Nil, i := Nil, nAt := Nil, aL := Nil, aR := Nil, c := "", lRel := .F.
    For k := 1 To Len( aOps )
        nAt := 0
        For i := Len( aOut ) To 1 Step -1
            If aOut[i] == aOps[k]
                nAt := i
                Exit
            EndIf
        Next
        If nAt > 0
            aL := {}
            aR := {}
            For i := 1 To nAt - 1
                AAdd( aL, aOut[i] )
            Next
            For i := nAt + 1 To Len( aOut )
                AAdd( aR, aOut[i] )
            Next
            Return aFn[k] + "( " + B2Join( aL, lCond ) + ", " + B2Join( aR, lCond ) + " )"
        EndIf
    Next
    If Len( aOut ) > 0 .And. aOut[1] == "@NOT@"
        aR := {}
        For i := 2 To Len( aOut )
            AAdd( aR, aOut[i] )
        Next
        Return "QNot( " + B2Join( aR, lCond ) + " )"
    EndIf
    For i := 1 To Len( aOut )
        If AScan( { "==", "!=", "<", ">", "<=", ">=" }, aOut[i] ) > 0
            lRel := .T.
            c += " " + aOut[i] + " "
        Else
            c += aOut[i]
        EndIf
    Next
    If lRel .And. !lCond
        Return "QbN( " + c + " )"
    EndIf
Return c

Static Function B2Cond( cE )
Return "QbT( " + B2Expr( cE, .T. ) + " )"

/*/{Protheus.doc} B2Ident
    Identificador sem parenteses: funcao embutida sem argumentos, campo de
    TYPE (x.campo), CONST, retorno de FUNCTION, FUNCTION sem args ou variavel.
/*/
Static Function B2Ident( cX )
    Local cU := B2Up( cX ), cN := Nil, nDot := Nil, cBase := Nil, k := Nil, aFP := Nil
    Local aBare := { "INKEY$", "QInkey()", "TIMER", "QTimer()", "RND", "QRndF()", ;
                     "CSRLIN", "QCsrLin()", "DATE$", "QDate()", "TIME$", "Time()", ;
                     "FREEFILE", "QbFreeFile()", "ERR", "nQbErr", "ERL", "nQbLine", "COMMAND$", '""' }
    k := AScan( aBare, cU )
    If k > 0 .And. Mod( k, 2 ) == 1
        Return aBare[ k + 1 ]
    EndIf
    nDot := At( ".", cU )
    If nDot > 1
        cBase := B2VarName( Left( cU, nDot - 1 ) )
        If B2TypeOf( cBase ) != ""
            B2Rec( cBase )
            aFP := B2FieldPath( B2TypeOf( cBase ), SubStr( cU, nDot + 1 ) )
            Return cBase + aFP[1]
        EndIf
    EndIf
    cN := B2VarName( cU )
    If Right( cU, 1 ) == "$"
        B2AddU( aStrVars, cN )
    EndIf
    k := AScan( aConstN, cN )
    If k > 0
        Return aConst[k][2]
    EndIf
    If cN == cFnName
        Return "__RET"
    EndIf
    If AScan( aFnN, cN ) > 0
        Return "B_" + cN + "()"
    EndIf
    B2Rec( cN )
Return cN

/*/{Protheus.doc} B2Call
    ident(args): funcao embutida, UBOUND/LBOUND, array, FUNCTION do usuario.
/*/
Static Function B2Call( cX )
    Local nP := At( "(", cX ), cRaw := Nil, cU := Nil, cN := Nil, cIn := Nil, k := Nil, aA := Nil, cLB := Nil
    Local aMap := { "LEFT$", "Left", "RIGHT$", "Right", "MID$", "SubStr", "STR$", "QStr", ;
                    "VAL", "Val", "CHR$", "QChr", "ASC", "QAsc", "LEN", "Len", ;
                    "UCASE$", "Upper", "LCASE$", "Lower", "SPACE$", "Space", "STRING$", "QString", ;
                    "INSTR", "QInstr", "INT", "QInt", "FIX", "Int", "CINT", "QCint", "CLNG", "QCint", ;
                    "CSNG", "", "CDBL", "", "ABS", "Abs", "SIN", "Sin", "COS", "Cos", "ATN", "Atan", ;
                    "TAN", "Tan", "SQR", "Sqrt", "EXP", "Exp", "LOG", "Log", "SGN", "QSign", ;
                    "RND", "QRndF", "TIMER", "QTimer", "POINT", "QPoint", "PEEK", "QPeek", ;
                    "SPC", "Space", "TAB", "QTab", "LTRIM$", "LTrim", "RTRIM$", "RTrim", ;
                    "INP", "QInp", "HEX$", "QHex", "OCT$", "QOct", "ENVIRON$", "QbEnv", ;
                    "STRIG", "QStrig", "POS", "QPos", "INKEY$", "QInkey", "FRE", "QInp", "EOF", "QbFEof", ;
                    "LOF", "QbFLof", "LOC", "QbFLoc", "SEEK", "QbFPos", ;
                    "MKI$", "QbMki", "CVI", "QbCvi", "MKL$", "QbMkl", "CVL", "QbCvl", ;
                    "MKS$", "QbMks", "CVS", "QbCvs", "MKD$", "QbMkd", "CVD", "QbCvd" }
    cRaw := B2Trim( Left( cX, nP - 1 ) )
    cU := B2Up( cRaw )
    cN := B2VarName( cRaw )
    cIn := SubStr( cX, nP + 1, Rat( ")", cX ) - nP - 1 )
    If Empty( B2Trim( cIn ) )
        B2Rec( cN )
        Return cN
    EndIf
    k := AScan( aMap, cU )
    If k > 0 .And. Mod( k, 2 ) == 1
        Return aMap[ k + 1 ] + "(" + B2ExprList( cIn ) + ")"
    EndIf
    If cU == "UBOUND" .Or. cU == "LBOUND"
        aA := B2SplitCommas( cIn )
        cN := B2VarName( StrTran( B2Trim( aA[1] ), "()", "" ) )
        k := IIf( Len( aA ) > 1, Max( 1, Val( aA[2] ) ), 1 )
        cLB := B2LBExpr( cN, k )
        If cU == "LBOUND"
            Return cLB
        EndIf
        Return "(Len(" + cN + Replicate( "[1]", k - 1 ) + ")+" + cLB + "-1)"
    EndIf
    If AScan( aArrN, cN ) > 0
        B2Rec( cN )
        Return cN + B2IdxList( cN, cIn )
    EndIf
    If AScan( aFnN, cN ) > 0
        Return "B_" + cN + "(" + B2ExprList( cIn ) + ")"
    EndIf
    B2Warn( cRaw + "(...) nao declarado: tratado como array implicito" )
    B2AddU( aArrN, cN )
    B2Rec( cN )
Return cN + B2IdxList( cN, cIn )

Static Function B2ExprList( cIn )
    Local a := B2SplitCommas( cIn ), cR := "", i := Nil
    For i := 1 To Len( a )
        cR += IIf( i > 1, ", ", "" ) + IIf( Empty( B2Trim( a[i] ) ), "Nil", B2Expr( a[i], .F. ) )
    Next
Return cR

/*/{Protheus.doc} B2LBExpr
    Limite inferior (AdvPL) da dimensao k do array cN.
/*/
Static Function B2LBExpr( cN, k )
    Local n := Nil, aLB := Nil
    If !Empty( cCurSub )
        n := AScan( aParamLB, {|x| x[1] == cCurSub + "." + cN } )
        If n > 0
            aLB := aParamLB[n][2]
        EndIf
    EndIf
    If aLB == Nil
        n := AScan( aArrLB, {|x| x[1] == cN } )
        If n > 0
            aLB := aArrLB[n][2]
        EndIf
    EndIf
    If aLB == Nil .Or. k > Len( aLB )
        Return B2Expr( cBase, .F. )
    EndIf
Return B2Expr( aLB[k], .F. )

/*/{Protheus.doc} B2IdxList
    Indices QBasic -> [..][..] deslocados para base 1.
/*/
Static Function B2IdxList( cN, cIn )
    Local a := B2SplitCommas( cIn ), cR := "", i := Nil, cE := Nil, cLB := Nil
    For i := 1 To Len( a )
        cE := B2Expr( a[i], .F. )
        cLB := B2LBExpr( cN, i )
        Do Case
        Case cLB == "1"
            cR += "[" + cE + "]"
        Case cLB == "0" .And. B2IsNumLit( cE )
            cR += "[" + B2I2S( Val( cE ) + 1 ) + "]"
        Case cLB == "0"
            cR += "[" + cE + "+1]"
        Otherwise
            cR += "[(" + cE + ")-(" + cLB + ")+1]"
        EndCase
    Next
Return cR

// ===========================================================================
// Lvalues e atribuicao
// ===========================================================================

/*/{Protheus.doc} B2IsLvalSyntax
    "x", "x$", "a(i)", "a(i).campo", "x.campo"
/*/
Static Function B2IsLvalSyntax( c )
    Local cW := Nil
    c := B2Trim( c )
    If !B2IsIdStart( Left( c, 1 ) )
        Return .F.
    EndIf
    cW := B2Word( c )
    c := B2Trim( SubStr( c, Len( cW ) + 1 ) )
    If Left( c, 1 ) == "("
        c := B2Trim( SubStr( c, B2MatchParen( c ) + 1 ) )
        If Left( c, 1 ) == "."
            c := B2Trim( SubStr( c, Len( B2Word( SubStr( c, 2 ) ) ) + 2 ) )
        EndIf
    EndIf
Return Empty( c )

/*/{Protheus.doc} B2MatchParen
    Posicao do ')' que fecha o '(' em c[1].
/*/
Static Function B2MatchParen( c )
    Local i := Nil, nDep := 0, lStr := .F., ch := Nil
    For i := 1 To Len( c )
        ch := SubStr( c, i, 1 )
        If ch == '"'
            lStr := !lStr
        ElseIf !lStr .And. ch == "("
            nDep += 1
        ElseIf !lStr .And. ch == ")"
            nDep -= 1
            If nDep == 0
                Return i
            EndIf
        EndIf
    Next
Return Len( c )

/*/{Protheus.doc} B2LValue
    Lado esquerdo -> {cTraduzido, cBase, lEscalar, cRaw, cTipoCampo}
/*/
Static Function B2LValue( cLhs )
    Local cRaw := B2Word( cLhs ), cRest := Nil, cBase := Nil, nDot := Nil, cTr := Nil, nQ := Nil, cIn := Nil, aFP := Nil, cFt := "", lScalar := .T.
    cRest := B2Trim( SubStr( B2Trim( cLhs ), Len( cRaw ) + 1 ) )
    nDot := At( ".", cRaw )
    If nDot > 1 .And. B2TypeOf( B2VarName( Left( cRaw, nDot - 1 ) ) ) != ""
        cBase := B2VarName( Left( cRaw, nDot - 1 ) )
        aFP := B2FieldPath( B2TypeOf( cBase ), SubStr( cRaw, nDot + 1 ) )
        Return { cBase + aFP[1], cBase, .F., cRaw, aFP[2] }
    EndIf
    cBase := B2VarName( cRaw )
    If Right( cRaw, 1 ) == "$"
        B2AddU( aStrVars, cBase )
    EndIf
    cTr := cBase
    If Left( cRest, 1 ) == "("
        lScalar := .F.
        nQ := B2MatchParen( cRest )
        cIn := SubStr( cRest, 2, nQ - 2 )
        B2AddU( aArrN, cBase )
        cTr += B2IdxList( cBase, cIn )
        cRest := B2Trim( SubStr( cRest, nQ + 1 ) )
        If Left( cRest, 1 ) == "."
            aFP := B2FieldPath( B2TypeOf( cBase ), SubStr( cRest, 2 ) )
            cTr += aFP[1]
            cFt := aFP[2]
        EndIf
    EndIf
Return { cTr, cBase, lScalar, cRaw, cFt }

/*/{Protheus.doc} B2AssignTo
    Atribuicao QBasic com retorno de FUNCTION e arredondamento de inteiros.
/*/
Static Function B2AssignTo( cLhs, cRhs )
    Local aLV := B2LValue( cLhs ), lInt := Nil
    If aLV[3] .And. aLV[2] == cFnName
        If lFnInt
            cRhs := "QCint( " + cRhs + " )"
        EndIf
        Return "__RET := " + cRhs
    EndIf
    If aLV[3]
        B2Rec( aLV[2] )
    EndIf
    If Empty( aLV[5] )
        lInt := AScan( aVarTN, aLV[2] ) == 0 .And. B2IsIntVar( aLV[2], aLV[4] )
    Else
        lInt := aLV[5] == "INTEGER" .Or. aLV[5] == "LONG"
    EndIf
    If lInt
        cRhs := "QCint( " + cRhs + " )"
    EndIf
Return aLV[1] + " := " + cRhs

// ===========================================================================
// Statements
// ===========================================================================

/*/{Protheus.doc} B2Statements
    Divide por ':' mantendo o IF de uma linha inteiro (THEN a: b ELSE c).
/*/
Static Function B2Statements( cCode )
    Local aSeg := B2SplitColons( cCode ), aR := {}, k := Nil, j := Nil, cS := Nil, nTh := Nil
    For k := 1 To Len( aSeg )
        cS := B2Trim( aSeg[k] )
        If Empty( cS )
            Loop
        EndIf
        If B2Up( B2Word( cS ) ) == "IF"
            nTh := B2FindKw( cS, "THEN" )
            If nTh > 0 .And. !Empty( B2Trim( SubStr( cS, nTh + 4 ) ) )
                For j := k + 1 To Len( aSeg )
                    cS += ":" + aSeg[j]
                Next
                AAdd( aR, cS )
                Exit
            EndIf
        EndIf
        AAdd( aR, cS )
    Next
Return aR

/*/{Protheus.doc} B2EmitList
    Traduz uma lista de statements, concatenando as linhas.
/*/
Static Function B2EmitList( cCode, cInd )
    Local aR := {}, aSt := B2Statements( cCode ), k := Nil, j := Nil, aE := Nil
    For k := 1 To Len( aSt )
        If k < Len( aSt ) .And. B2Up( B2Word( aSt[k] ) ) == "FOR" .And. B2Up( B2Word( aSt[k+1] ) ) == "NEXT"
            AAdd( aR, cInd + B2DelayLoop( aSt[k] ) )
            k += 1
            Loop
        EndIf
        aE := B2Emit( aSt[k] )
        For j := 1 To Len( aE )
            AAdd( aR, cInd + aE[j] )
        Next
    Next
Return aR

/*/{Protheus.doc} B2DelayLoop
    "FOR v = a TO b [STEP s]: NEXT" (laco vazio de espera) -> QDelayLoop.
/*/
Static Function B2DelayLoop( cFor )
    Local cRest := B2After( cFor ), nP := At( "=", cRest ), nQ := B2FindKw( cRest, "TO" ), aLV := Nil, cTo := "", cStep := "Nil", nS := 0
    aLV := B2LValue( Left( cRest, nP - 1 ) )
    B2Rec( aLV[2] )
    cTo := SubStr( cRest, nQ + 2 )
    nS := B2FindKw( cTo, "STEP" )
    If nS > 0
        cStep := B2Expr( SubStr( cTo, nS + 4 ), .F. )
        cTo := Left( cTo, nS - 1 )
    EndIf
Return aLV[1] + " := QDelayLoop( " + B2Expr( SubStr( cRest, nP + 1, nQ - nP - 1 ), .F. ) + ", " + B2Expr( cTo, .F. ) + ", " + cStep + " )    // laco vazio de espera"

/*/{Protheus.doc} B2Footer
    Linhas de saida de SUB/FUNCTION (copy-back dos parametros + Return).
/*/
Static Function B2Footer()
    Local aR := {}
    If cBlkKind == "SUB" .Or. cBlkKind == "FUNC"
        If !Empty( cCurParamList )
            AAdd( aR, "__QBA := { " + cCurParamList + " }" )
        EndIf
        AAdd( aR, IIf( cBlkKind == "FUNC", "Return __RET", "Return" ) )
    ElseIf cBlkKind == "DEFFN"
        AAdd( aR, "Return __RET" )
    Else
        AAdd( aR, "Return" )
    EndIf
Return aR

/*/{Protheus.doc} B2Emit
    Traduz UM statement QBasic -> array de linhas AdvPL.
/*/
Static Function B2Emit( cS )
    Local aR := {}, cW := B2Up( B2Word( cS ) ), cRest := B2After( cS ), cU := Nil
    Local nP := Nil, nQ := Nil, cV := Nil, cE := Nil, aA := Nil, i := Nil, cSel := Nil, cCond := Nil, cTail := Nil, nEl := Nil, aLV := Nil, aPts := Nil, aOp := Nil, cTo := Nil, cStep := Nil, nAs := Nil

    If Left( B2Trim( cS ), 1 ) == "?"
        cW := "PRINT"
        cRest := B2Trim( SubStr( B2Trim( cS ), 2 ) )
    EndIf
    cU := B2Up( cRest )
    Do Case
    // ------------------------------------------------------------ estrutura
    Case cW == "IF"
        nP := B2FindKw( cRest, "THEN" )
        If nP == 0
            nP := B2FindKw( cRest, "GOTO" )
            If nP > 0
                cRest := Left( cRest, nP - 1 ) + "THEN " + SubStr( cRest, nP )
                nP := B2FindKw( cRest, "THEN" )
            EndIf
        EndIf
        If nP == 0
            B2Warn( "IF sem THEN" )
            Return { "// TODO: " + B2Clean( cS ) }
        EndIf
        cCond := B2Cond( Left( cRest, nP - 1 ) )
        cTail := B2Trim( SubStr( cRest, nP + 4 ) )
        AAdd( aR, "If " + cCond )
        If !Empty( cTail )
            nEl := B2FindKw( cTail, "ELSE" )
            cE := ""
            If nEl > 0
                cE := B2Trim( SubStr( cTail, nEl + 4 ) )
                cTail := B2Trim( Left( cTail, nEl - 1 ) )
            EndIf
            B2AddLines( aR, B2EmitList( IIf( B2IsDigit( Left( cTail, 1 ) ), "GOTO " + cTail, cTail ), "    " ) )
            If nEl > 0
                AAdd( aR, "Else" )
                B2AddLines( aR, B2EmitList( IIf( B2IsDigit( Left( cE, 1 ) ), "GOTO " + cE, cE ), "    " ) )
            EndIf
            AAdd( aR, "EndIf" )
        EndIf
    Case cW == "ELSEIF"
        nP := B2FindKw( cRest, "THEN" )
        AAdd( aR, "ElseIf " + B2Cond( IIf( nP > 0, Left( cRest, nP - 1 ), cRest ) ) )
    Case cW == "ELSE"
        AAdd( aR, "Else" )
        If !Empty( cRest )
            B2AddLines( aR, B2EmitList( cRest, "" ) )
        EndIf
    Case cW == "ENDIF"
        AAdd( aR, "EndIf" )
    Case cW == "END"
        cV := B2Up( B2Word( cRest ) )
        Do Case
        Case cV == "IF"     ; AAdd( aR, "EndIf" )
        Case cV == "SELECT"
            AAdd( aR, "EndCase" )
            If Len( aSelStk ) > 0
                ASize( aSelStk, Len( aSelStk ) - 1 )
            EndIf
        Case cV == "TYPE" .Or. cV == "SUB" .Or. cV == "FUNCTION" .Or. cV == "DEF"
            // fronteiras tratadas em B2Gen
        Otherwise
            AAdd( aR, "QbEnd()" )
        EndCase
    Case cW == "FOR"
        nP := At( "=", cRest )
        nQ := B2FindKw( cRest, "TO" )
        If nP == 0 .Or. nQ == 0
            B2Warn( "FOR malformado" )
            Return { "// TODO: " + B2Clean( cS ) }
        EndIf
        aLV := B2LValue( Left( cRest, nP - 1 ) )
        B2Rec( aLV[2] )
        cE := B2Expr( SubStr( cRest, nP + 1, nQ - nP - 1 ), .F. )
        cTo := SubStr( cRest, nQ + 2 )
        nP := B2FindKw( cTo, "STEP" )
        cStep := ""
        If nP > 0
            cStep := " Step " + B2Expr( SubStr( cTo, nP + 4 ), .F. )
            cTo := Left( cTo, nP - 1 )
        EndIf
        AAdd( aR, "For " + aLV[1] + " := " + cE + " To " + B2Expr( cTo, .F. ) + cStep )
    Case cW == "NEXT"
        nP := IIf( Empty( cRest ), 1, Len( B2SplitCommas( cRest ) ) )
        For i := 1 To nP
            AAdd( aR, "Next" )
        Next
    Case cW == "DO"
        Do Case
        Case B2Up( B2Word( cRest ) ) == "WHILE"
            AAdd( aR, "Do While " + B2Cond( B2After( cRest ) ) )
        Case B2Up( B2Word( cRest ) ) == "UNTIL"
            AAdd( aR, "Do While !" + B2Cond( B2After( cRest ) ) )
        Otherwise
            AAdd( aR, "Do While .T." )
        EndCase
    Case cW == "LOOP"
        Do Case
        Case B2Up( B2Word( cRest ) ) == "UNTIL"
            AAdd( aR, "If " + B2Cond( B2After( cRest ) ) )
            AAdd( aR, "    Exit" )
            AAdd( aR, "EndIf" )
        Case B2Up( B2Word( cRest ) ) == "WHILE"
            AAdd( aR, "If !" + B2Cond( B2After( cRest ) ) )
            AAdd( aR, "    Exit" )
            AAdd( aR, "EndIf" )
        EndCase
        AAdd( aR, "EndDo" )
    Case cW == "WHILE"
        AAdd( aR, "Do While " + B2Cond( cRest ) )
    Case cW == "WEND"
        AAdd( aR, "EndDo" )
    Case cW == "SELECT"
        nSel += 1
        cSel := "__SEL" + B2I2S( nSel )
        AAdd( aSelStk, cSel )
        B2Rec( cSel )
        If B2Up( B2Word( cRest ) ) == "CASE"
            cRest := B2After( cRest )
        EndIf
        AAdd( aR, cSel + " := " + B2Expr( cRest, .F. ) )
        AAdd( aR, "Do Case" )
    Case cW == "CASE"
        cSel := IIf( Len( aSelStk ) > 0, ATail( aSelStk ), "__SEL0" )
        If cU == "ELSE"
            AAdd( aR, "Otherwise" )
        Else
            aA := B2SplitCommas( cRest )
            cCond := ""
            For i := 1 To Len( aA )
                cE := B2Trim( aA[i] )
                cCond += IIf( i > 1, " .Or. ", "" )
                nP := B2FindKw( cE, "TO" )
                Do Case
                Case B2Up( B2Word( cE ) ) == "IS"
                    cE := B2After( cE )
                    nQ := IIf( Len( cE ) > 1 .And. SubStr( cE, 2, 1 ) $ "=>", 2, 1 )
                    cV := Left( cE, nQ )
                    cV := IIf( cV == "=", "==", IIf( cV == "<>", "!=", cV ) )
                    cCond += cSel + " " + cV + " " + B2Expr( SubStr( cE, nQ + 1 ), .F. )
                Case nP > 0
                    cCond += "( " + cSel + " >= " + B2Expr( Left( cE, nP - 1 ), .F. ) + " .And. " + cSel + " <= " + B2Expr( SubStr( cE, nP + 2 ), .F. ) + " )"
                Otherwise
                    cCond += cSel + " == " + B2Expr( cE, .F. )
                EndCase
            Next
            AAdd( aR, "Case " + cCond )
        EndIf
    Case cW == "EXIT"
        cV := B2Up( B2Word( cRest ) )
        If cV == "SUB" .Or. cV == "FUNCTION" .Or. cV == "DEF"
            B2AddLines( aR, B2Footer() )
        Else
            AAdd( aR, "Exit" )
        EndIf
    Case cW == "GOSUB"
        AAdd( aR, "LB_" + B2LabelName( cRest ) + "()" )
    Case cW == "GOTO"
        cV := B2LabelName( cRest )
        nP := AScan( aGotoOpen, {|x| x[1] == cV } )
        If lDispBlk .Or. AScan( aDispLbls, {|x| x[1] == cV } ) > 0
            AAdd( aR, 'QbGoto( "' + cV + '" )' )
        ElseIf nP > 0 .And. aGotoOpen[nP][3] == nLoopDepth
            AAdd( aR, "Loop    // GOTO " + cV )
        ElseIf AScan( aGotoFwd, {|x| x[1] == cV } ) > 0
            B2Rec( "__QBG_" + cV )
            AAdd( aR, "__QBG_" + cV + " := .T." )
            AAdd( aFwdPending, cV )
        Else
            B2Warn( "GOTO " + cV + " (salto nao estruturado) nao suportado" )
            AAdd( aR, "// TODO: GOTO " + cV )
        EndIf
    Case cW == "RETURN"
        AAdd( aR, "Return" )
    Case cW == "ON"
        If B2Up( B2Word( cRest ) ) == "ERROR"
            cV := B2LabelName( B2After( B2After( cRest ) ) )   // "ERROR GOTO lbl"
            If cV == "L0"
                AAdd( aR, 'cQbErrHdl := ""' )
                lQbTrap := .F.
            Else
                AAdd( aR, 'cQbErrHdl := "' + cV + '"' )
                lQbTrap := .T.
            EndIf
        Else
            B2Warn( "ON ... GOSUB/GOTO/eventos nao suportado" )
            AAdd( aR, "// TODO: " + B2Clean( cS ) )
        EndIf
    Case cW == "RESUME"
        Do Case
        Case B2Up( B2Word( cRest ) ) == "NEXT"
            AAdd( aR, "nQbResume := 2" )
        Case Empty( cRest ) .Or. cRest == "0"
            AAdd( aR, "nQbResume := 1" )
        Otherwise
            AAdd( aR, "nQbResume := 3" )
            AAdd( aR, 'nQbResLbl := "' + B2LabelName( cRest ) + '"' )
        EndCase
        AAdd( aR, "Return" )
    Case cW == "CALL"
        If B2In( B2Up( B2Word( cRest ) ), "ABSOLUTE,INTERRUPT,INTERRUPTX" )
            B2Warn( "CALL ABSOLUTE/INTERRUPT nao suportado" )
            AAdd( aR, "// TODO: " + B2Clean( cS ) )
        Else
            cV := B2Word( cRest )
            cE := B2Trim( SubStr( cRest, Len( cV ) + 1 ) )
            If Left( cE, 1 ) == "("
                cE := SubStr( cE, 2, B2MatchParen( cE ) - 2 )
            EndIf
            B2AddLines( aR, B2CallStmt( cV, cE ) )
        EndIf
    Case cW == "SUB" .Or. cW == "FUNCTION" .Or. cW == "DECLARE" .Or. cW == "TYPE" .Or. cW == "CONST" .Or. ;
         cW == "DEFINT" .Or. cW == "DEFSNG" .Or. cW == "DEFDBL" .Or. cW == "DEFLNG" .Or. cW == "DEFSTR" .Or. ;
         cW == "OPTION" .Or. cW == "DATA" .Or. cW == "REM" .Or. cW == "SHARED" .Or. cW == "STATIC" .Or. ;
         cW == "RANDOMIZE" .Or. cW == "CLEAR" .Or. cW == "KEY" .Or. cW == "TIMER" .Or. ;
         cW == "PALETTE" .Or. cW == "VIEW" .Or. cW == "WINDOW" .Or. cW == "PCOPY" .Or. cW == "OUT" .Or. ;
         cW == "WAIT" .Or. cW == "ERASE" .Or. cW == "COMMON" .And. B2Up( B2Word( cRest ) ) != "SHARED"
        // declaracoes / efeitos sem equivalente: nada a emitir

    // -------------------------------------------------------- declaracoes
    Case cW == "DIM" .Or. cW == "REDIM" .Or. cW == "COMMON"
        If B2Up( B2Word( cRest ) ) == "SHARED"
            cRest := B2After( cRest )
        EndIf
        If B2Up( B2Word( cRest ) ) == "PRESERVE"
            cRest := B2After( cRest )
        EndIf
        If cW != "COMMON"
            aA := B2SplitCommas( cRest )
            For i := 1 To Len( aA )
                If !Empty( B2Trim( aA[i] ) )
                    AAdd( aR, B2DimStmt( B2Trim( aA[i] ) ) )
                EndIf
            Next
        EndIf
    Case cW == "DEF"
        If B2Up( B2Word( cRest ) ) == "SEG"
            nP := At( "=", cRest )
            AAdd( aR, "QDefSeg( " + IIf( nP > 0, B2Expr( SubStr( cRest, nP + 1 ), .F. ), "0" ) + " )" )
        EndIf
    Case cW == "READ"
        aA := B2SplitCommas( cRest )
        For i := 1 To Len( aA )
            AAdd( aR, B2AssignTo( aA[i], "QbRead()" ) )
        Next
    Case cW == "RESTORE"
        nP := 0
        If !Empty( cRest )
            nQ := AScan( aDataLbl, {|x| x[1] == B2LabelName( cRest ) } )
            If nQ > 0
                nP := aDataLbl[nQ][2]
            Else
                B2Warn( "RESTORE para label desconhecido " + cRest )
            EndIf
        EndIf
        AAdd( aR, "nQbDataPos := " + B2I2S( nP ) )
    Case cW == "SWAP"
        aA := B2SplitCommas( cRest )
        If Len( aA ) == 2
            cV := B2LValue( aA[1] )[1]
            cE := B2LValue( aA[2] )[1]
            B2Rec( "__SWAP" )
            AAdd( aR, "__SWAP := " + cV )
            AAdd( aR, cV + " := " + cE )
            AAdd( aR, cE + " := __SWAP" )
        EndIf
    Case cW == "LET"
        B2AddLines( aR, B2Emit( cRest ) )

    // ---------------------------------------------------------------- tela
    Case cW == "CLS"
        AAdd( aR, "QbCls()" )
    Case cW == "SCREEN"
        aA := B2SplitCommas( cRest )
        AAdd( aR, "QbScreen( " + IIf( Empty( B2Trim( aA[1] ) ), "Nil", B2Expr( aA[1], .F. ) ) + " )" )
    Case cW == "WIDTH"
        If Left( cRest, 1 ) == "#" .Or. B2Up( B2Word( cRest ) ) == "LPRINT"
            Return {}
        EndIf
        AAdd( aR, "QbWidth( " + B2ExprList( cRest ) + " )" )
    Case cW == "LOCATE"
        aA := B2SplitCommas( cRest )
        AAdd( aR, "QbLocate( " + IIf( Len( aA ) >= 1 .And. !Empty( B2Trim( aA[1] ) ), B2Expr( aA[1], .F. ), "Nil" ) + ", " + ;
                                 IIf( Len( aA ) >= 2 .And. !Empty( B2Trim( aA[2] ) ), B2Expr( aA[2], .F. ), "Nil" ) + " )" )
    Case cW == "COLOR"
        aA := B2SplitCommas( cRest )
        AAdd( aR, "QbColor( " + IIf( Len( aA ) >= 1 .And. !Empty( B2Trim( aA[1] ) ), B2Expr( aA[1], .F. ), "Nil" ) + ", " + ;
                                IIf( Len( aA ) >= 2 .And. !Empty( B2Trim( aA[2] ) ), B2Expr( aA[2], .F. ), "Nil" ) + " )" )
    Case cW == "PRINT" .Or. cW == "?" .Or. cW == "LPRINT"
        B2AddLines( aR, B2Print( cRest ) )
    Case cW == "INPUT"
        B2AddLines( aR, B2Input( cRest, .F. ) )
    Case cW == "LINE"
        If B2Up( B2Word( cRest ) ) == "INPUT"
            B2AddLines( aR, B2Input( B2After( cRest ), .T. ) )
        Else
            AAdd( aR, B2LineStmt( cRest ) )
        EndIf
    Case cW == "PSET" .Or. cW == "PRESET"
        aPts := B2ParenPts( cRest )
        If Len( aPts ) >= 1
            aOp := B2SplitCommas( SubStr( cRest, aPts[1][2] ) )
            AAdd( aR, IIf( cW == "PSET", "QPset( ", "QPreset( " ) + B2Expr( aPts[1][1][1], .F. ) + ", " + B2Expr( aPts[1][1][2], .F. ) + ", " + ;
                      IIf( Len( aOp ) >= 2 .And. !Empty( B2Trim( aOp[2] ) ), B2Expr( aOp[2], .F. ), "Nil" ) + " )" )
        EndIf
    Case cW == "CIRCLE"
        aPts := B2ParenPts( cRest )
        If Len( aPts ) >= 1
            aOp := B2SplitCommas( SubStr( cRest, aPts[1][2] ) )
            cE := "QCircle( " + B2Expr( aPts[1][1][1], .F. ) + ", " + B2Expr( aPts[1][1][2], .F. )
            For i := 2 To 7
                cE += ", " + IIf( Len( aOp ) >= i .And. !Empty( B2Trim( aOp[i] ) ), B2Expr( aOp[i], .F. ), "Nil" )
            Next
            AAdd( aR, cE + " )" )
        EndIf
    Case cW == "PAINT"
        aPts := B2ParenPts( cRest )
        If Len( aPts ) >= 1
            aOp := B2SplitCommas( SubStr( cRest, aPts[1][2] ) )
            AAdd( aR, "QPaint( " + B2Expr( aPts[1][1][1], .F. ) + ", " + B2Expr( aPts[1][1][2], .F. ) + ", " + ;
                      IIf( Len( aOp ) >= 2 .And. !Empty( B2Trim( aOp[2] ) ), B2Expr( aOp[2], .F. ), "Nil" ) + ", " + ;
                      IIf( Len( aOp ) >= 3 .And. !Empty( B2Trim( aOp[3] ) ), B2Expr( aOp[3], .F. ), "Nil" ) + " )" )
        EndIf
    Case ( cW == "GET" .Or. cW == "PUT" ) .And. Left( cRest, 1 ) == "#"
        B2AddLines( aR, B2GetPutF( cW, cRest ) )
    Case cW == "GET"
        aPts := B2ParenPts( cRest )
        If Len( aPts ) >= 2
            aOp := B2SplitCommas( SubStr( cRest, aPts[2][2] ) )
            cV := B2VarName( B2Word( IIf( Len( aOp ) >= 2, aOp[2], "" ) ) )
            B2Rec( cV )
            AAdd( aR, cV + " := QbGet( " + B2Expr( aPts[1][1][1], .F. ) + ", " + B2Expr( aPts[1][1][2], .F. ) + ", " + ;
                      B2Expr( aPts[2][1][1], .F. ) + ", " + B2Expr( aPts[2][1][2], .F. ) + " )" )
        EndIf
    Case cW == "PUT"
        aPts := B2ParenPts( cRest )
        If Len( aPts ) >= 1
            aOp := B2SplitCommas( SubStr( cRest, aPts[1][2] ) )
            cV := B2VarName( B2Word( IIf( Len( aOp ) >= 2, aOp[2], "" ) ) )
            B2Rec( cV )
            AAdd( aR, "QbPut( " + B2Expr( aPts[1][1][1], .F. ) + ", " + B2Expr( aPts[1][1][2], .F. ) + ", " + cV + ", " + ;
                      '"' + IIf( Len( aOp ) >= 3, B2Up( B2Trim( aOp[3] ) ), "XOR" ) + '" )' )
        EndIf
    Case cW == "DRAW"
        B2Warn( "DRAW nao suportado" )
        AAdd( aR, "// TODO: " + B2Clean( cS ) )

    // ---------------------------------------------------------------- som
    Case cW == "PLAY"
        If !B2In( cU, "ON,OFF,STOP" )
            AAdd( aR, "QPlay( " + B2Expr( cRest, .F. ) + " )" )
        EndIf
    Case cW == "SOUND"
        aA := B2SplitCommas( cRest )
        If Len( aA ) == 2
            AAdd( aR, "QTone( " + B2Expr( aA[1], .F. ) + ", " + B2Expr( aA[2], .F. ) + " )" )
        EndIf
    Case cW == "BEEP"
        AAdd( aR, "Tone()" )
    Case cW == "SLEEP"
        AAdd( aR, IIf( Empty( cRest ), "QWaitKey()", "QSleep( " + B2Expr( cRest, .F. ) + " )" ) )

    // ---------------------------------------------------------- memoria/fim
    Case cW == "POKE"
        aA := B2SplitCommas( cRest )
        If Len( aA ) == 2
            AAdd( aR, "QPoke( " + B2Expr( aA[1], .F. ) + ", " + B2Expr( aA[2], .F. ) + " )" )
        EndIf
    Case cW == "STOP" .Or. cW == "SYSTEM"
        AAdd( aR, "QbEnd()" )
    Case cW == "ERROR"
        AAdd( aR, "QbRaise( " + B2Expr( cRest, .F. ) + " )" )
    Case cW == "OPEN"
        nP := B2FindKw( cRest, "AS" )
        nQ := B2FindKw( cRest, "FOR" )
        aA := B2SplitCommas( cRest )
        If nQ > 0 .And. nP > nQ
            cV := B2Trim( Left( cRest, nQ - 1 ) )
            cE := B2Trim( SubStr( cRest, nQ + 3, nP - nQ - 3 ) )
            // "RANDOM LEN = n" / "BINARY" — modo = 1a palavra, LEN opcional
            nP := B2FindKw( cE, "LEN" )
            cStep := "Nil"
            If nP > 0
                cStep := B2Trim( SubStr( cE, nP + 3 ) )
                If Left( cStep, 1 ) == "="
                    cStep := B2Trim( SubStr( cStep, 2 ) )
                EndIf
                cStep := B2Expr( cStep, .F. )
                cE := B2Trim( Left( cE, nP - 1 ) )
            EndIf
            cE := B2Up( B2Word( cE ) )
            nP := B2FindKw( cRest, "AS" )
            AAdd( aR, "QbOpen( " + B2Expr( cV, .F. ) + ", '" + cE + "', " + B2Expr( SubStr( cRest, nP + 2 ), .F. ) + ", " + cStep + " )" )
        ElseIf Len( aA ) >= 3 .And. B2In( StrTran( B2Trim( aA[1] ), '"', "" ), "I,O,A,R,B" )
            cE := StrTran( B2Trim( aA[1] ), '"', "" )
            cE := IIf( cE == "I", "INPUT", IIf( cE == "O", "OUTPUT", IIf( cE == "A", "APPEND", IIf( cE == "B", "BINARY", "RANDOM" ) ) ) )
            cStep := IIf( Len( aA ) >= 4 .And. !Empty( B2Trim( aA[4] ) ), B2Expr( aA[4], .F. ), "Nil" )
            AAdd( aR, "QbOpen( " + B2Expr( aA[3], .F. ) + ", '" + cE + "', " + B2Expr( aA[2], .F. ) + ", " + cStep + " )" )
        Else
            B2Warn( "OPEN malformado" )
            AAdd( aR, "// TODO: " + B2Clean( cS ) )
        EndIf
    Case cW == "CLOSE"
        cE := B2Trim( cRest )
        If Left( cE, 1 ) == "#"
            cE := B2Trim( SubStr( cE, 2 ) )
        EndIf
        AAdd( aR, "QbClose( " + IIf( Empty( cE ), "0", B2Expr( cE, .F. ) ) + " )" )
    Case cW == "FIELD"
        B2AddLines( aR, B2FieldStmt( cRest ) )
    Case cW == "LSET" .Or. cW == "RSET"
        nP := B2FindTop( cRest, "=" )
        If nP > 0
            cV := B2LValue( Left( cRest, nP - 1 ) )[1]
            AAdd( aR, cV + " := " + IIf( cW == "LSET", "Pad( ", "PadL( " ) + B2Expr( SubStr( cRest, nP + 1 ), .F. ) + ", Len( " + cV + " ) )" )
        EndIf
    Case cW == "KILL"
        AAdd( aR, "QbKill( " + B2Expr( cRest, .F. ) + " )" )
    Case cW == "NAME"
        nP := B2FindKw( cRest, "AS" )
        If nP > 0
            AAdd( aR, "QbName( " + B2Expr( Left( cRest, nP - 1 ), .F. ) + ", " + B2Expr( SubStr( cRest, nP + 2 ), .F. ) + " )" )
        EndIf
    Case cW == "SEEK"
        aA := B2SplitCommas( cRest )
        If Len( aA ) >= 2 .And. Left( B2Trim( aA[1] ), 1 ) == "#"
            AAdd( aR, "QbFSeek( " + B2Expr( SubStr( B2Trim( aA[1] ), 2 ), .F. ) + ", " + B2Expr( aA[2], .F. ) + " )" )
        EndIf
    Case cW == "WRITE"
        B2AddLines( aR, B2WriteStmt( cRest ) )
    Case B2In( cW, "SHELL,CHAIN,RUN,MKDIR,RMDIR,CHDIR,FILES,ENVIRON,LOCK,UNLOCK" )
        B2Warn( cW + " (arquivos/sistema) nao suportado" )
        AAdd( aR, "// TODO: " + B2Clean( cS ) )
    Case Left( cW, 4 ) == "MID$" .And. B2FindTop( cS, "=" ) > 0
        B2Warn( "MID$(...) = ... nao suportado" )
        AAdd( aR, "// TODO: " + B2Clean( cS ) )

    // ------------------------------------------------ atribuicao / chamada
    Otherwise
        nP := B2FindTop( cS, "=" )
        If nP > 0 .And. B2IsLvalSyntax( Left( cS, nP - 1 ) )
            AAdd( aR, B2AssignTo( Left( cS, nP - 1 ), B2Expr( SubStr( cS, nP + 1 ), .F. ) ) )
        ElseIf AScan( aSubs, B2VarName( cW ) ) > 0 .Or. AScan( aFnN, B2VarName( cW ) ) > 0
            B2AddLines( aR, B2CallStmt( B2Word( cS ), cRest ) )
        Else
            B2Warn( "statement nao reconhecido: " + B2Clean( cS ) )
            AAdd( aR, "// TODO: " + B2Clean( cS ) )
        EndIf
    EndCase
    If lQbTrap .And. !lDispBlk .And. Len( aR ) > 0 .And. !B2IsStruct( LTrim( aR[1] ) )
        aR := B2TrapWrap( aR )
    EndIf
Return aR

/*/{Protheus.doc} B2TrapWrap
    Envolve o statement em Try/Catch que despacha para cQbErrHdl
    (ON ERROR GOTO). nQbResume: 1=retentar, 2=continuar, 3=ir ao label,
    4=relancar. Nesta VM Throw dentro de Catch e fatal, entao a
    propagacao e adiada para depois do EndDo.
/*/
Static Function B2TrapWrap( aR )
    Local aW := { "Do While .T.", "    Try" }, i := Nil
    For i := 1 To Len( aR )
        AAdd( aW, "        " + aR[i] )
    Next
    AAdd( aW, "        Exit" )
    AAdd( aW, "    Catch __oErr" )
    AAdd( aW, "        __QBSVERR := __oErr" )
    AAdd( aW, "        nQbErr := QbErrNo( __oErr )" )
    AAdd( aW, "        nQbResume := 0" )
    AAdd( aW, '        nQbResLbl := ""' )
    AAdd( aW, "        __QBRETRY := .F." )
    AAdd( aW, "        If QbIsCtl( __oErr )" )
    AAdd( aW, '            If "QBGOTO:" $ QbErrText( __oErr )' )
    AAdd( aW, "                nQbResume := 3" )
    AAdd( aW, "                nQbResLbl := QbResTarget( __oErr )" )
    AAdd( aW, "            Else" )
    AAdd( aW, "                nQbResume := 4" )
    AAdd( aW, "            EndIf" )
    AAdd( aW, "        ElseIf Empty( cQbErrHdl )" )
    AAdd( aW, "            nQbResume := 4" )
    AAdd( aW, "        Else" )
    AAdd( aW, "            B_QbErrCall( cQbErrHdl )" )
    AAdd( aW, "            __QBRETRY := ( nQbResume == 1 )" )
    AAdd( aW, "        EndIf" )
    AAdd( aW, "    EndTry" )
    AAdd( aW, "    If !__QBRETRY" )
    AAdd( aW, "        Exit" )
    AAdd( aW, "    EndIf" )
    AAdd( aW, "EndDo" )
    AAdd( aW, "Do Case" )
    AAdd( aW, "Case nQbResume == 3 ; QbGoto( nQbResLbl )" )
    If Empty( cBlkKind )
        AAdd( aW, "Case nQbResume == 4 ; QbCatch( __QBSVERR )" )
    Else
        AAdd( aW, "Case nQbResume == 4 ; Throw( __QBSVERR )" )
    EndIf
    AAdd( aW, "EndCase" )
Return aW

/*/{Protheus.doc} B2IsStruct
    A linha ja e estrutura/controle/rotulo — nao envolver em Try.
/*/
Static Function B2IsStruct( c )
    Local cW := B2Up( B2Word( c ) )
Return Left( c, 2 ) == "//" .Or. Left( c, 2 ) == "/*" .Or. ;
       B2In( cW, "IF,ELSE,ELSEIF,ENDIF,FOR,NEXT,DO,LOOP,WHILE,WEND,SELECT,CASE,OTHERWISE,ENDCASE,END,TRY,CATCH,ENDTRY,EXIT,RETURN,QUIT,STATIC" ) .Or. ;
       Left( c, 5 ) == "Exit" .Or. Left( c, 4 ) == "Loop" .Or. Left( c, 6 ) == "QbGoto"

/*/{Protheus.doc} B2StrLen / B2TypeSpec / B2VarSpec
    "STRING * 25" -> 25; spec binario de um TYPE ou de uma variavel
    ("I"/"L"/"S"/"D", {"S",n}, {"T",{...}}) para GET/PUT.
/*/
Static Function B2StrLen( cFt )
    Local n := At( "*", cFt )
Return IIf( n > 0, Val( SubStr( cFt, n + 1 ) ), 1 )

Static Function B2TypeSpec( cTy )
    Local aT := B2TypeRec( cTy ), c := "{", i := Nil, cFt := Nil
    If aT == Nil
        Return '"S"'
    EndIf
    For i := 1 To Len( aT[2] )
        cFt := aT[3][i]
        c += IIf( i > 1, ", ", "" )
        Do Case
        Case cFt == "INTEGER"           ; c += '"I"'
        Case cFt == "LONG"              ; c += '"L"'
        Case cFt == "DOUBLE"            ; c += '"D"'
        Case Left( cFt, 6 ) == "STRING" ; c += '{ "S", ' + B2I2S( B2StrLen( cFt ) ) + ' }'
        Case B2TypeRec( cFt ) != Nil    ; c += '{ "T", ' + B2TypeSpec( cFt ) + ' }'
        Otherwise                       ; c += '"S"'
        EndCase
    Next
Return c + "}"

Static Function B2VarSpec( cVar )
    Local cRaw := B2Word( B2Trim( cVar ) ), cN := B2VarName( cRaw ), cTy := B2TypeOf( cN ), cSuf := Right( B2Trim( cRaw ), 1 )
    If cTy != ""
        Return B2TypeSpec( cTy )
    EndIf
    Do Case
    Case cSuf == "%" .Or. cSuf == "&"   ; Return IIf( cSuf == "&", '"L"', '"I"' )
    Case cSuf == "#"                    ; Return '"D"'
    Case cSuf == "$"                    ; Return '{ "S", Len( ' + cN + ' ) }'
    Case AScan( aLngVars, cN ) > 0      ; Return '"L"'
    Case AScan( aIntVars, cN ) > 0      ; Return '"I"'
    Case AScan( aStrVars, cN ) > 0      ; Return '{ "S", Len( ' + cN + ' ) }'
    Otherwise                           ; Return '"S"'
    EndCase
Return '"S"'

/*/{Protheus.doc} B2FieldStmt
    FIELD #n, w AS v, ... — campos viram variaveis string de largura fixa;
    o layout fica em aFldMap (por expressao de canal) para GET/PUT.
/*/
Static Function B2FieldStmt( cRest )
    Local aR := {}, nP := B2FindTop( cRest, "," ), aA := Nil, i := Nil, cV := Nil, cChan := "", aFlds := {}, nAs := Nil
    If nP == 0
        B2Warn( "FIELD malformado" )
        Return { "// TODO: FIELD " + B2Clean( cRest ) }
    EndIf
    cChan := B2Expr( SubStr( cRest, 2, nP - 2 ), .F. )
    aA := B2SplitCommas( SubStr( cRest, nP + 1 ) )
    For i := 1 To Len( aA )
        cV := B2Trim( aA[i] )
        nAs := B2FindKw( cV, "AS" )
        If nAs > 0
            AAdd( aFlds, { B2Trim( Left( cV, nAs - 1 ) ), B2Trim( SubStr( cV, nAs + 2 ) ) } )
            AAdd( aR, B2AssignTo( B2Trim( SubStr( cV, nAs + 2 ) ), "Space( " + B2Expr( Left( cV, nAs - 1 ), .F. ) + " )" ) )
        EndIf
    Next
    nP := AScan( aFldMap, {|x| x[1] == cChan } )
    If nP > 0
        aFldMap[nP][2] := aFlds
    Else
        AAdd( aFldMap, { cChan, aFlds } )
    EndIf
Return aR

/*/{Protheus.doc} B2GetPutF
    GET #n[, rec][, var] / PUT #n[, rec][, var] — com FIELD reconstrui os
    campos; var de TYPE usa QbPack/QbUnpk; escalares usam MK$/CV$.
/*/
Static Function B2GetPutF( cW, cRest )
    Local aR := {}, aA := B2SplitCommas( cRest ), cChan := "", cRec := "Nil", cVar := "", cVar2 := "", nF := 0, j := 0
    Local cOff := "", cSpec := "", cSz := "", aLV := Nil, lStr := .F., cTy := ""
    If Len( aA ) < 1 .Or. Left( B2Trim( aA[1] ), 1 ) != "#"
        B2Warn( cW + " # malformado" )
        Return { "// TODO: " + B2Clean( cW + " " + cRest ) }
    EndIf
    cChan := B2Expr( SubStr( B2Trim( aA[1] ), 2 ), .F. )
    If Len( aA ) >= 2 .And. !Empty( B2Trim( aA[2] ) )
        cRec := B2Expr( aA[2], .F. )
    EndIf
    If Len( aA ) >= 3
        cVar := B2Trim( aA[3] )
    EndIf
    nF := AScan( aFldMap, {|x| x[1] == cChan } )
    If cW == "GET"
        If nF > 0
            B2Rec( "__FR" )
            AAdd( aR, "__FR := QbFReadRec( " + cChan + ", " + cRec + " )" )
            cOff := "1"
            For j := 1 To Len( aFldMap[nF][2] )
                cSpec := B2Expr( aFldMap[nF][2][j][1], .F. )
                AAdd( aR, B2AssignTo( aFldMap[nF][2][j][2], "SubStr( __FR, " + cOff + ", " + cSpec + " )" ) )
                cOff += " + " + cSpec
            Next
        ElseIf Empty( cVar )
            AAdd( aR, "QbFReadRec( " + cChan + ", " + cRec + " )" )
        Else
            cVar2 := B2VarName( B2Word( cVar ) )
            cTy := B2TypeOf( cVar2 )
            lStr := B2IsStrVar( cVar2, B2Word( cVar ) )
            cSpec := B2VarSpec( cVar )
            aLV := B2LValue( cVar )
            If lStr
                AAdd( aR, B2AssignTo( cVar, "QbFReadN( " + cChan + ", Len( " + aLV[1] + " ), " + cRec + " )" ) )
            ElseIf cTy != ""
                AAdd( aR, B2AssignTo( cVar, "QbUnpk( QbFReadN( " + cChan + ", QbSpecLen( " + cSpec + " ), " + cRec + " ), " + cSpec + " )" ) )
            Else
                cSz := IIf( cSpec == '"I"', "2", IIf( cSpec == '"D"', "8", "4" ) )
                AAdd( aR, B2AssignTo( cVar, "QbUnpk1( QbFReadN( " + cChan + ", " + cSz + ", " + cRec + " ), " + cSpec + " )[1]" ) )
            EndIf
        EndIf
    Else
        If nF > 0
            cOff := ""
            For j := 1 To Len( aFldMap[nF][2] )
                aLV := B2LValue( aFldMap[nF][2][j][2] )
                cOff += " + Pad( " + aLV[1] + ", " + B2Expr( aFldMap[nF][2][j][1], .F. ) + " )"
            Next
            AAdd( aR, "QbFWriteRec( " + cChan + ", " + cRec + ", " + SubStr( cOff, 4 ) + " )" )
        ElseIf Empty( cVar )
            AAdd( aR, "QbFWriteRec( " + cChan + ", " + cRec + ", QbFBuff( " + cChan + " ) )" )
        ElseIf ( cTy := B2TypeOf( B2VarName( B2Word( cVar ) ) ) ) != ""
            AAdd( aR, "QbFWriteRec( " + cChan + ", " + cRec + ", QbPack( " + B2LValue( cVar )[1] + ", " + B2TypeSpec( cTy ) + " ) )" )
        ElseIf B2IsStrVar( B2VarName( B2Word( cVar ) ), B2Word( cVar ) )
            AAdd( aR, "QbFWriteRec( " + cChan + ", " + cRec + ", " + B2LValue( cVar )[1] + " )" )
        Else
            AAdd( aR, "QbFWriteRec( " + cChan + ", " + cRec + ", QbPack1( " + B2LValue( cVar )[1] + ", " + B2VarSpec( cVar ) + " ) )" )
        EndIf
    EndIf
Return aR

/*/{Protheus.doc} B2WriteStmt
    WRITE [#n,] itens — separados por virgula, strings entre aspas.
/*/
Static Function B2WriteStmt( cRest )
    Local aR := {}, cChan := "", nP := Nil, aA := Nil, i := Nil
    cRest := B2Trim( cRest )
    If Left( cRest, 1 ) == "#"
        nP := B2FindTop( cRest, "," )
        If nP == 0
            B2Warn( "WRITE # malformado" )
            Return { "// TODO: WRITE " + B2Clean( cRest ) }
        EndIf
        cChan := B2Expr( SubStr( cRest, 2, nP - 2 ), .F. )
        cRest := SubStr( cRest, nP + 1 )
    EndIf
    B2Rec( "__PRLN" )
    AAdd( aR, '__PRLN := ""' )
    aA := B2SplitCommas( cRest )
    For i := 1 To Len( aA )
        If !Empty( B2Trim( aA[i] ) )
            AAdd( aR, "__PRLN += " + IIf( i > 1, '", " + ', "" ) + "QbWrItem( " + B2Expr( aA[i], .F. ) + " )" )
        EndIf
    Next
    If Empty( cChan )
        AAdd( aR, "QbOut( __PRLN )" )
        AAdd( aR, "QbPrNL()" )
    Else
        AAdd( aR, "QbFWr( " + cChan + ", __PRLN, .T. )" )
    EndIf
Return aR

/*/{Protheus.doc} B2DispHead / B2DispTail / B2GrdDelta
    Dispatcher de PC para rids com saltos nao estruturados: cada unidade de
    nivel 0 vira "If __PC <= n ... __PC := n+1 ... EndIf" dentro de
    Do While/Try; o Catch mapeia QBGOTO para o PC do label e trata ON ERROR
    (nQbResume: 1=refaz, 2=proximo, 3=label) sem Try aninhado.
/*/
Static Function B2DispHead()
    Local cIni := "0"
    nPc := 0
    lGrd := .F.
    nGrDep := 0
    If cBlkKind == "LBL"      // rotinas de label aceitam ponto de entrada via nPc0
        cIni := 'IIf( ValType( nPc0 ) == "N", Int( nPc0 ), 0 )'
    EndIf
    B2Put( { 'Private __PC := ' + cIni + ', __QBDL := "", __QBDERR := Nil, __QBPCF := 0', "Do While .T.", "    Try" } )
Return

Static Function B2DispTail()
    Local aW := {}, k := Nil, nP := Nil
    If lGrd
        B2Put( { "__PC := " + B2I2S( nPc + 1 ), "EndIf" } )
        lGrd := .F.
    EndIf
    AAdd( aW, "        Exit" )
    AAdd( aW, "    Catch __oD" )
    AAdd( aW, "        __QBDERR := __oD" )
    AAdd( aW, "        __QBDL := QbResTarget( __oD )" )
    If Len( aErrLbl ) > 0
        AAdd( aW, "        If Empty( __QBDL ) .And. !QbIsCtl( __oD ) .And. !Empty( cQbErrHdl )" )
        AAdd( aW, "            nQbErr := QbErrNo( __oD )" )
        AAdd( aW, "            nQbResume := 0" )
        AAdd( aW, '            nQbResLbl := ""' )
        AAdd( aW, "            __QBPCF := __PC" )
        AAdd( aW, "            B_QbErrCall( cQbErrHdl )" )
        AAdd( aW, "            Do Case" )
        AAdd( aW, "            Case nQbResume == 1 ; __PC := __QBPCF" )
        AAdd( aW, "            Case nQbResume == 3 ; __QBDL := nQbResLbl" )
        AAdd( aW, "            Otherwise ; __PC := __QBPCF + 1" )
        AAdd( aW, "            EndCase" )
        AAdd( aW, "            If Empty( __QBDL ) ; Loop ; EndIf" )
        AAdd( aW, "        EndIf" )
    EndIf
    AAdd( aW, "        Do Case" )
    AAdd( aW, "        @@DISP" + B2I2S( nCurRid ) + "@@" )
    AAdd( aW, "        Otherwise ; Exit" )
    AAdd( aW, "        EndCase" )
    AAdd( aW, "    EndTry" )
    AAdd( aW, "EndDo" )
    If Empty( cBlkKind )
        AAdd( aW, "If __QBDERR != Nil ; QbCatch( __QBDERR ) ; EndIf" )
    Else
        AAdd( aW, "If __QBDERR != Nil ; Throw( __QBDERR ) ; EndIf" )
    EndIf
    B2Put( aW )
Return

/*/{Protheus.doc} B2DispCases
    Gera os Cases do mapa de labels do rid nRid — chamada no fim, quando
    aDispMap esta completo (labels de outros rids viram chamada LB_ via PC).
/*/
Static Function B2DispCases( nRid )
    Local c := "", k := Nil, nP := Nil
    For k := 1 To Len( aDispMap )
        If aDispMap[k][1] == nRid
            c += 'Case __QBDL == "' + aDispMap[k][2] + '" ; __PC := ' + B2I2S( aDispMap[k][3] ) + ' ; Loop' + Chr( 10 ) + "        "
        EndIf
    Next
    For k := 1 To Len( aDispMap )
        If aDispMap[k][1] != nRid
            nP := AScan( aRidFn, {|x| x[1] == aDispMap[k][1] } )
            If nP > 0
                c += 'Case __QBDL == "' + aDispMap[k][2] + '"' + Chr( 10 ) + "            " + ;
                     '__QBDERR := Nil' + Chr( 10 ) + "            " + ;
                     'Try' + Chr( 10 ) + "                " + aRidFn[nP][2] + "( " + B2I2S( aDispMap[k][3] ) + " )" + Chr( 10 ) + "            " + ;
                     'Catch __oX' + Chr( 10 ) + "                __QBDERR := __oX" + Chr( 10 ) + "            " + ;
                     'EndTry' + Chr( 10 ) + "            " + ;
                     'Exit' + Chr( 10 ) + "        "
            EndIf
        EndIf
    Next
Return c

Static Function B2GrdDelta( aL )
    Local i := Nil, c := Nil, n := 0
    For i := 1 To Len( aL )
        c := LTrim( aL[i] )
        Do Case
        Case Left( c, 3 ) == "If " .Or. Left( c, 4 ) == "For " .Or. Left( c, 9 ) == "Do While " .Or. Left( c, 7 ) == "Do Case" .Or. c == "Try"
            n += 1
        Case c == "EndIf" .Or. c == "Next" .Or. Left( c, 5 ) == "EndDo" .Or. c == "EndCase" .Or. c == "EndTry"
            n -= 1
        EndCase
    Next
Return n

Static Function B2AddLines( aDst, aSrc )
    Local i := Nil
    For i := 1 To Len( aSrc )
        AAdd( aDst, aSrc[i] )
    Next
Return

/*/{Protheus.doc} B2CallStmt
    Chamada de SUB com copy-back dos argumentos que sao variaveis
    (emula passagem por referencia do QBasic).
/*/
Static Function B2CallStmt( cName, cArgs )
    Local cN := B2VarName( cName ), aA := {}, aSig := B2GetSig( cN ), cOut := Nil, i := Nil, cA := Nil, aBack := {}, aR := Nil
    If !Empty( B2Trim( cArgs ) )
        aA := B2SplitCommas( cArgs )
    EndIf
    cOut := "B_" + cN + "("
    For i := 1 To Len( aA )
        cA := B2Trim( aA[i] )
        cOut += IIf( i > 1, ", ", " " )
        If Right( cA, 2 ) == "()"
            cOut += B2VarName( Left( cA, Len( cA ) - 2 ) )
        ElseIf Empty( cA )
            cOut += "Nil"
        Else
            cOut += B2Expr( cA, .F. )
            If aSig != Nil .And. i <= Len( aSig[2] ) .And. !aSig[2][i][2] .And. B2IsLvalSyntax( cA ) .And. ;
               AScan( aConstN, B2VarName( B2Word( cA ) ) ) == 0 .And. AScan( aFnN, B2VarName( B2Word( cA ) ) ) == 0 .And. ;
               !( "(" $ cA .And. AScan( aArrN, B2VarName( B2Word( cA ) ) ) == 0 )
                AAdd( aBack, B2LValue( cA )[1] + " := __QBA[" + B2I2S( i ) + "]" )
            EndIf
        EndIf
    Next
    cOut += IIf( Len( aA ) > 0, " )", ")" )
    aR := { cOut }
    B2AddLines( aR, aBack )
Return aR

/*/{Protheus.doc} B2Print
    PRINT a; b, c[;] -> QbPr/QbPrZone/QbPrTab/QbPrNL.
/*/
Static Function B2Print( cRest )
    Local aR := {}, aI := {}, aSep := {}, cCur := "", lStr := .F., nDep := 0, i := Nil, c := Nil, cI := Nil, cFmt := "", nP := Nil, lUsing := .F.
    Local cChan := "", cE := Nil
    cRest := B2Trim( cRest )
    If Left( cRest, 1 ) == "#"
        nP := B2FindTop( cRest, "," )
        If nP == 0
            B2Warn( "PRINT # malformado" )
            Return { "// TODO: PRINT " + B2Clean( cRest ) }
        EndIf
        cChan := B2Expr( SubStr( cRest, 2, nP - 2 ), .F. )
        cRest := SubStr( cRest, nP + 1 )
        B2Rec( "__PRLN" )
        AAdd( aR, '__PRLN := ""' )
    EndIf
    If B2Up( B2Word( cRest ) ) == "USING"
        cRest := B2After( cRest )
        nP := B2FindTop( cRest, ";" )
        cFmt := B2Expr( Left( cRest, nP - 1 ), .F. )
        cRest := SubStr( cRest, nP + 1 )
        lUsing := .T.
    EndIf
    For i := 1 To Len( cRest )
        c := SubStr( cRest, i, 1 )
        If c == '"'
            lStr := !lStr
            cCur += c
        ElseIf !lStr .And. c == "("
            nDep += 1
            cCur += c
        ElseIf !lStr .And. c == ")"
            nDep -= 1
            cCur += c
        ElseIf !lStr .And. nDep == 0 .And. c $ ";,"
            AAdd( aI, cCur )
            AAdd( aSep, c )
            cCur := ""
        Else
            cCur += c
        EndIf
    Next
    AAdd( aI, cCur )
    AAdd( aSep, "" )
    For i := 1 To Len( aI )
        cI := B2Trim( aI[i] )
        Do Case
        Case Empty( cI )
        Case B2Up( Left( cI, 4 ) ) == "TAB("
            cE := B2Expr( SubStr( cI, 5, B2MatchParen( SubStr( cI, 4 ) ) - 2 ), .F. )
            AAdd( aR, IIf( Empty( cChan ), "QbPrTab( " + cE + " )", "__PRLN += QbFTab( __PRLN, " + cE + " )" ) )
        Case B2Up( Left( cI, 4 ) ) == "SPC("
            cE := B2Expr( SubStr( cI, 5, B2MatchParen( SubStr( cI, 4 ) ) - 2 ), .F. )
            AAdd( aR, IIf( Empty( cChan ), "QbPr( Space( " + cE + " ) )", "__PRLN += Space( " + cE + " )" ) )
        Case lUsing
            AAdd( aR, IIf( Empty( cChan ), "QbPr( QbUSING( " + cFmt + ", " + B2Expr( cI, .F. ) + " ) )", "__PRLN += QbUSING( " + cFmt + ", " + B2Expr( cI, .F. ) + " )" ) )
        Otherwise
            AAdd( aR, IIf( Empty( cChan ), "QbPr( " + B2Expr( cI, .F. ) + " )", "__PRLN += QbPrStr( " + B2Expr( cI, .F. ) + " )" ) )
        EndCase
        If aSep[i] == ","
            AAdd( aR, IIf( Empty( cChan ), "QbPrZone()", "__PRLN += QbFZon( __PRLN )" ) )
        EndIf
    Next
    // sem ';' ou ',' no final -> nova linha
    If Empty( cChan )
        If Len( aI ) == 1 .Or. !Empty( B2Trim( ATail( aI ) ) )
            AAdd( aR, "QbPrNL()" )
        EndIf
    Else
        AAdd( aR, "QbFWr( " + cChan + ", __PRLN, " + IIf( Len( aI ) == 1 .Or. !Empty( B2Trim( ATail( aI ) ) ), ".T.", ".F." ) + " )" )
    EndIf
Return aR

/*/{Protheus.doc} B2Input
    INPUT [;]["prompt"{;|,}] v1[, v2] / LINE INPUT ["prompt";] v$
/*/
Static Function B2Input( cRest, lLine )
    Local aR := {}, cPr := "", nP := Nil, aV := Nil, i := Nil, cV := Nil, lStrV := Nil, cE := Nil
    cRest := B2Trim( cRest )
    If Left( cRest, 1 ) == "#"
        nP := B2FindTop( cRest, "," )
        If nP == 0
            B2Warn( "INPUT # malformado" )
            Return { "// TODO: INPUT " + B2Clean( cRest ) }
        EndIf
        cE := B2Expr( SubStr( cRest, 2, nP - 2 ), .F. )
        cRest := SubStr( cRest, nP + 1 )
        If lLine
            Return { B2AssignTo( B2Trim( cRest ), "QbFReadLn( " + cE + " )" ) }
        EndIf
        aV := B2SplitCommas( cRest )
        B2Rec( "__INP" )
        AAdd( aR, "__INP := QbInputF( " + cE + ", " + B2I2S( Len( aV ) ) + " )" )
        For i := 1 To Len( aV )
            cV := B2Trim( aV[i] )
            lStrV := B2IsStrVar( B2VarName( B2Word( cV ) ), B2Word( cV ) )
            AAdd( aR, B2AssignTo( cV, IIf( lStrV, "__INP[" + B2I2S( i ) + "]", "Val( __INP[" + B2I2S( i ) + "] )" ) ) )
        Next
        Return aR
    EndIf
    If Left( cRest, 1 ) == ";"
        cRest := B2Trim( SubStr( cRest, 2 ) )
    EndIf
    If Left( cRest, 1 ) == '"'
        nP := At( '"', SubStr( cRest, 2 ) ) + 1
        cPr := SubStr( cRest, 1, nP )
        cRest := B2Trim( SubStr( cRest, nP + 1 ) )
        If Left( cRest, 1 ) == ";" .And. !lLine
            cPr := Left( cPr, Len( cPr ) - 1 ) + '? "'
        EndIf
        If Len( cRest ) > 0 .And. Left( cRest, 1 ) $ ",;"
            cRest := B2Trim( SubStr( cRest, 2 ) )
        EndIf
        cPr := B2SanitizeStr( cPr )
    Else
        cPr := IIf( lLine, '""', '"? "' )
    EndIf
    If lLine
        Return { B2AssignTo( cRest, "QInput( " + cPr + " )" ) }
    EndIf
    aV := B2SplitCommas( cRest )
    B2Rec( "__INP" )
    AAdd( aR, "__INP := QInputList( " + cPr + ", " + B2I2S( Len( aV ) ) + " )" )
    For i := 1 To Len( aV )
        cV := B2Trim( aV[i] )
        lStrV := B2IsStrVar( B2VarName( B2Word( cV ) ), B2Word( cV ) )
        AAdd( aR, B2AssignTo( cV, IIf( lStrV, "__INP[" + B2I2S( i ) + "]", "Val( __INP[" + B2I2S( i ) + "] )" ) ) )
    Next
Return aR

/*/{Protheus.doc} B2ParenPts
    "(x1,y1)-(x2,y2),..." -> { { {x,y}, posApos }, ... } (prefixo STEP ignorado)
/*/
Static Function B2ParenPts( cS )
    Local aR := {}, i := 1, n := Len( cS ), c := Nil, nDep := Nil, cCur := Nil, lStr := Nil
    Do While i <= n .And. Len( aR ) < 2
        c := SubStr( cS, i, 1 )
        If c == ","
            Exit
        EndIf
        If c == "("
            nDep := 1
            cCur := ""
            lStr := .F.
            i += 1
            Do While i <= n .And. nDep > 0
                c := SubStr( cS, i, 1 )
                If c == '"'
                    lStr := !lStr
                ElseIf !lStr .And. c == "("
                    nDep += 1
                ElseIf !lStr .And. c == ")"
                    nDep -= 1
                EndIf
                If nDep > 0
                    cCur += c
                EndIf
                i += 1
            EndDo
            AAdd( aR, { B2SplitCommas( cCur ), i } )
        Else
            i += 1
        EndIf
    EndDo
Return aR

/*/{Protheus.doc} B2LineStmt
    LINE [[STEP](x1,y1)]-[STEP](x2,y2)[,[c][,B|BF]]
/*/
Static Function B2LineStmt( cRest )
    Local aPts := B2ParenPts( cRest ), aOp := Nil, cP1X := "Nil", cP1Y := "Nil", aP2 := Nil, nTail := Nil
    Local cCol := "Nil", cMode := '""'
    If Len( aPts ) == 0
        B2Warn( "LINE malformado" )
        Return "// TODO: LINE " + B2Clean( cRest )
    EndIf
    If Left( B2Trim( cRest ), 1 ) == "-" .Or. Len( aPts ) == 1
        aP2 := aPts[1]
    Else
        cP1X := B2Expr( aPts[1][1][1], .F. )
        cP1Y := B2Expr( aPts[1][1][2], .F. )
        aP2 := aPts[2]
    EndIf
    nTail := aP2[2]
    aOp := B2SplitCommas( SubStr( cRest, nTail ) )
    If Len( aOp ) >= 2 .And. !Empty( B2Trim( aOp[2] ) )
        cCol := B2Expr( aOp[2], .F. )
    EndIf
    If Len( aOp ) >= 3 .And. !Empty( B2Trim( aOp[3] ) )
        cMode := '"' + B2Up( B2Trim( aOp[3] ) ) + '"'
    EndIf
Return "QLine( " + cP1X + ", " + cP1Y + ", " + B2Expr( aP2[1][1], .F. ) + ", " + B2Expr( aP2[1][2], .F. ) + ", " + cCol + ", " + cMode + " )"

/*/{Protheus.doc} B2DimSize
    "a TO b" -> b-a+1 ; "n" -> n-base+1 (dobrado quando literal).
/*/
Static Function B2DimSize( cD )
    Local nTo := B2FindKw( cD, "TO" ), cLo := Nil, cHi := Nil
    If nTo > 0
        cLo := B2Expr( Left( cD, nTo - 1 ), .F. )
        cHi := B2Expr( SubStr( cD, nTo + 2 ), .F. )
    Else
        cLo := B2Expr( cBase, .F. )
        cHi := B2Expr( cD, .F. )
    EndIf
    If B2IsNumLit( cLo ) .And. B2IsNumLit( cHi )
        Return B2I2S( Val( cHi ) - Val( cLo ) + 1 )
    EndIf
Return "(" + cHi + ")-(" + cLo + ")+1"

/*/{Protheus.doc} B2DimStmt
    DIM a(dims) [AS tipo] -> a := QDimArr( {tamanhos}, modelo )
/*/
Static Function B2DimStmt( cI )
    Local cRaw := B2Word( cI ), cN := B2VarName( cRaw ), nAs := B2FindKw( cI, "AS" ), cTy := "", cTpl := Nil
    Local nP := At( "(", cI ), nQ := Nil, aD := Nil, i := Nil, cSizes := ""
    If nAs > 0
        cTy := B2Up( B2Trim( SubStr( cI, nAs + 2 ) ) )
    EndIf
    Do Case
    Case B2TypeRec( cTy ) != Nil
        cTpl := B2TypeTpl( cTy )
    Case Left( cTy, 6 ) == "STRING" .Or. ( Empty( cTy ) .And. B2IsStrVar( cN, cRaw ) )
        cTpl := '""'
    Otherwise
        cTpl := "0"
    EndCase
    B2Rec( cN )
    If nP > 0 .And. ( nAs == 0 .Or. nP < nAs )
        nQ := B2MatchParen( SubStr( cI, nP ) ) + nP - 1
        aD := B2SplitCommas( SubStr( cI, nP + 1, nQ - nP - 1 ) )
        If Empty( B2Trim( aD[1] ) )
            Return ""
        EndIf
        For i := 1 To Len( aD )
            cSizes += IIf( i > 1, ", ", "" ) + B2DimSize( aD[i] )
        Next
        Return cN + " := QDimArr( { " + cSizes + " }, " + cTpl + " )"
    EndIf
Return cN + " := " + cTpl

// ===========================================================================
// Passo B — geracao
// ===========================================================================

/*/{Protheus.doc} B2Track
    Atualiza profundidade de blocos/lacos a partir das linhas emitidas.
/*/
Static Function B2Track( aL )
    Local i := Nil, c := Nil
    For i := 1 To Len( aL )
        c := LTrim( aL[i] )
        Do Case
        Case Left( c, 4 ) == "For " .Or. Left( c, 9 ) == "Do While "
            nLoopDepth += 1
            nBlkDepth += 1
        Case Left( c, 3 ) == "If " .Or. Left( c, 7 ) == "Do Case"
            nBlkDepth += 1
        Case c == "Next" .Or. Left( c, 5 ) == "EndDo"
            nLoopDepth -= 1
            nBlkDepth -= 1
        Case c == "EndIf" .Or. c == "EndCase"
            nBlkDepth -= 1
        EndCase
    Next
Return

/*/{Protheus.doc} B2Put
    Acrescenta linhas ao bloco corrente (ou ao Main).
/*/
Static Function B2Put( aL )
    Local i := Nil
    For i := 1 To Len( aL )
        If Empty( cBlkKind )
            AAdd( aMainL, aL[i] )
        Else
            AAdd( aBlkL, aL[i] )
        EndIf
    Next
    B2Track( aL )
Return

/*/{Protheus.doc} B2CloseGotos
    Fecha lacos de GOTO cuja ultima referencia ja passou (lForce = todos).
/*/
Static Function B2CloseGotos( nLine, lForce )
    Local aG := Nil
    Do While Len( aGotoOpen ) > 0
        aG := ATail( aGotoOpen )
        If aG[5] != nBlkId
            Exit
        EndIf
        If lForce .Or. ( nLine >= aG[2] .And. nBlkDepth == aG[4] )
            B2Put( { "Exit", "EndDo    // fim do laco do label " + aG[1] } )
            ASize( aGotoOpen, Len( aGotoOpen ) - 1 )
        Else
            Exit
        EndIf
    EndDo
Return

/*/{Protheus.doc} B2Fmt
    Indenta um corpo de rotina.
/*/
Static Function B2Fmt( aL, nBase )
    Local cOut := "", i := Nil, c := Nil, nLev := nBase, nPre := Nil, nPost := Nil
    For i := 1 To Len( aL )
        c := LTrim( aL[i] )
        nPre := 0
        nPost := 0
        Do Case
        Case Left( c, 3 ) == "If " .Or. Left( c, 4 ) == "For " .Or. Left( c, 9 ) == "Do While " .Or. c == "Try"
            nPost := 1
        Case Left( c, 7 ) == "Do Case"
            nPost := 2
        Case c == "Else" .Or. Left( c, 7 ) == "ElseIf " .Or. Left( c, 5 ) == "Case " .Or. c == "Otherwise" .Or. Left( c, 5 ) == "Catch"
            nPre := -1
            nPost := 1
        Case c == "EndIf" .Or. c == "Next" .Or. Left( c, 5 ) == "EndDo" .Or. c == "EndTry"
            nPre := -1
        Case c == "EndCase"
            nPre := -2
        EndCase
        nLev := Max( nBase, nLev + nPre )
        cOut += Space( nLev * 4 ) + c + Chr( 10 )
        nLev += nPost
    Next
Return cOut

/*/{Protheus.doc} B2Open / B2Close
    Abre/fecha uma rotina gerada (SUB, FUNCTION, DEF FN ou label GOSUB).
/*/
Static Function B2Open( cKind, cHdr )
    If Empty( cBlkKind )
        aMainDepth := { nLoopDepth, nBlkDepth }
    EndIf
    nBlkId += 1
    cBlkKind := cKind
    cBlkHdr := cHdr
    aBlkL := {}
    nLoopDepth := 0
    nBlkDepth := 0
    lQbTrap := .F.
    aFwdPending := {}
    aFwdOpen := {}
Return

Static Function B2Close()
    Local cTxt := Nil, aAll := Nil, i := Nil
    If lDispBlk
        B2DispTail()              // cauda do dispatcher (aMainL ou aBlkL)
        lDispBlk := .F.
    EndIf
    If Empty( cBlkKind )
        Return
    EndIf
    For i := 1 To Len( aFwdOpen )
        B2Put( { "EndIf    // label " + aFwdOpen[i] + " nao atingido na rotina" } )
    Next
    aFwdOpen := {}
    aFwdPending := {}
    B2CloseGotos( 0, .T. )
    cTxt := cBlkHdr + Chr( 10 )
    If cBlkKind == "SUB" .Or. cBlkKind == "FUNC"
        cTxt += "    @@PRIV" + B2I2S( nOwner ) + "@@" + Chr( 10 )
    EndIf
    If cBlkKind == "FUNC" .Or. cBlkKind == "DEFFN"
        cTxt += "    Local __RET := " + IIf( lFnStr, '""', "0" ) + Chr( 10 )
    EndIf
    aAll := AClone( aBlkL )
    B2AddLines( aAll, B2Footer() )
    cTxt += B2Fmt( B2NestReturns( aAll ), 1 ) + Chr( 10 )
    AAdd( aOutBlk, cTxt )
    cBlkKind := ""
    aBlkL := {}
    nBlkId := 0
    nLoopDepth := aMainDepth[1]
    nBlkDepth := aMainDepth[2]
Return

/*/{Protheus.doc} B2NestReturns
    O parser do AdvPP encerra a funcao no primeiro Return de nivel 0: o
    codigo seguinte vira script de topo (executado antes do Main!). Todo
    Return de nivel 0 que nao seja a ultima linha vai para "If .T.".
/*/
Static Function B2NestReturns( aL )
    Local aR := {}, i := 0, c := "", nDep := 0
    For i := 1 To Len( aL )
        c := LTrim( aL[i] )
        If nDep == 0 .And. i < Len( aL ) .And. ( c == "Return" .Or. Left( c, 7 ) == "Return " )
            AAdd( aR, "If .T." )
            AAdd( aR, c )
            AAdd( aR, "EndIf" )
            Loop
        EndIf
        AAdd( aR, aL[i] )
        Do Case
        Case Left( c, 3 ) == "If " .Or. Left( c, 4 ) == "For " .Or. Left( c, 9 ) == "Do While " .Or. Left( c, 7 ) == "Do Case" .Or. c == "Try"
            nDep += 1
        Case c == "EndIf" .Or. c == "Next" .Or. Left( c, 5 ) == "EndDo" .Or. c == "EndCase" .Or. c == "EndTry"
            nDep -= 1
        EndCase
    Next
Return aR

/*/{Protheus.doc} B2NewOwner
    Nova rotina dona de variaveis (Main ou SUB/FUNCTION).
/*/
Static Function B2NewOwner( aParams )
    AAdd( aOwners, { "", {}, aParams } )
    nOwner := Len( aOwners )
Return

/*/{Protheus.doc} B2PrivDecl
    Declaracao Private das variaveis da rotina dona n.
/*/
Static Function B2PrivDecl( n, lMain )
    Local aV := AClone( aOwners[n][2] ), aRt := StrTokArr2( StrTran( QbRtVars(), " ", "" ), "," ), i := Nil, cOut := "", nCnt := 0, cN := Nil
    If lMain
        For i := 1 To Len( aShared )
            B2AddU( aV, aShared[i] )
        Next
    EndIf
    For i := 1 To Len( aV )
        cN := aV[i]
        If AScan( aRt, {|x| Upper( x ) == cN } ) > 0 .Or. AScan( aOwners[n][3], cN ) > 0 .Or. ;
           AScan( aConstN, cN ) > 0 .Or. cN == "__RET" .Or. cN == "__QBA" .Or. ;
           ( !lMain .And. AScan( aShared, cN ) > 0 )
            Loop
        EndIf
        cOut += IIf( nCnt == 0, "Private ", IIf( Mod( nCnt, 6 ) == 0, Chr( 10 ) + "    Private ", ", " ) )
        cOut += cN + " := " + IIf( Left( cN, 6 ) == "__QBG_", ".F.", IIf( B2IsStrVar( cN ), '""', "0" ) )
        nCnt += 1
    Next
Return IIf( nCnt == 0, "// (sem variaveis locais)", cOut )

/*/{Protheus.doc} B2Gen
    Passo B: gera o texto do .prg.
/*/
Static Function B2Gen()
    Local i := Nil, k := Nil, cCode := Nil, aLead := Nil, cW := Nil, cRest := Nil, aSig := Nil, aL := Nil, aE := Nil, cHdr := Nil, cOut := Nil, nIns := Nil, cFirst := Nil, nEq := Nil, cBody := Nil, aP := Nil, cArgs := Nil
    Local lInType := .F., cMain := Nil, cData := ""

    B2NewOwner( {} )          // owner 1 = Main
    nCurRid := 0
    lDispBlk := AScan( aDispRid, 0 ) > 0
    If lDispBlk
        B2DispHead()
    EndIf
    For i := 1 To Len( aLines )
        nCurLine := i
        cCode := B2StripComment( aLines[i] )
        aLead := B2LeadLabels( cCode )
        cCode := aLead[2]
        cW := B2Up( B2Word( cCode ) )
        cRest := B2After( cCode )

        If lInType
            If cW == "END" .And. B2Up( B2Word( cRest ) ) == "TYPE"
                lInType := .F.
            EndIf
            Loop
        EndIf
        If cW == "TYPE"
            lInType := .T.
            Loop
        EndIf

        For k := 1 To Len( aLead[1] )
            B2OnLabel( aLead[1][k], i )
        Next
        If Empty( cCode )
            B2CloseGotos( i, .F. )
            Loop
        EndIf

        If cW == "STATIC" .And. B2In( B2Up( B2Word( cRest ) ), "SUB,FUNCTION" )
            cCode := cRest
            cW := B2Up( B2Word( cCode ) )
            cRest := B2After( cCode )
        EndIf

        // ---- fronteiras de rotina
        If cW == "SUB" .Or. cW == "FUNCTION"
            B2Close()
            aSig := B2SigParse( cRest )
            aP := {}
            cArgs := ""
            For k := 1 To Len( aSig[2] )
                AAdd( aP, B2VarName( aSig[2][k][1] ) )
                cArgs += IIf( k > 1, ", ", "" ) + ATail( aP )
            Next
            aCurParams := aP
            cCurParamList := cArgs
            cCurSub := aSig[1]
            cFnName := IIf( cW == "FUNCTION", aSig[1], "" )
            lFnStr := cW == "FUNCTION" .And. B2IsStrVar( aSig[1], B2Word( cRest ) )
            lFnInt := cW == "FUNCTION" .And. B2IsIntVar( aSig[1], B2Word( cRest ) )
            B2NewOwner( aP )
            nCurRid := aRid[ i ]
            AAdd( aRidFn, { nCurRid, "B_" + aSig[1] } )
            B2Open( IIf( cW == "SUB", "SUB", "FUNC" ), "/* " + cW + " " + aSig[1] + " — .bas linha " + B2I2S( i ) + " */" + Chr( 10 ) + ;
                    "Static Function B_" + aSig[1] + "(" + IIf( Empty( cArgs ), "", " " + cArgs + " " ) + ")" )
            lDispBlk := AScan( aDispRid, nCurRid ) > 0
            If lDispBlk
                B2DispHead()
            EndIf
            Loop
        EndIf
        If cW == "DEF" .And. B2Up( Left( cRest, 2 ) ) == "FN"
            nEq := B2FindTop( cRest, "=" )
            aSig := B2SigParse( IIf( nEq > 0, Left( cRest, nEq - 1 ), cRest ) )
            aP := {}
            cArgs := ""
            For k := 1 To Len( aSig[2] )
                AAdd( aP, B2VarName( aSig[2][k][1] ) )
                cArgs += IIf( k > 1, ", ", "" ) + ATail( aP )
            Next
            cHdr := "/* DEF " + aSig[1] + " — .bas linha " + B2I2S( i ) + " */" + Chr( 10 ) + ;
                    "Static Function B_" + aSig[1] + "(" + IIf( Empty( cArgs ), "", " " + cArgs + " " ) + ")"
            If nEq > 0
                aCurParams := aP
                cBody := B2Expr( SubStr( cRest, nEq + 1 ), .F. )
                aCurParams := {}
                AAdd( aOutBlk, cHdr + Chr( 10 ) + "Return " + cBody + Chr( 10 ) + Chr( 10 ) )
            Else
                B2Close()
                aCurParams := aP
                cCurParamList := ""
                cFnName := aSig[1]
                lFnStr := aSig[3]
                lFnInt := .F.
                nOwner := 1
                nCurRid := aRid[ i ]
                B2Open( "DEFFN", cHdr )
                lDispBlk := AScan( aDispRid, nCurRid ) > 0
                If lDispBlk
                    B2DispHead()
                EndIf
            EndIf
            Loop
        EndIf
        If cW == "END" .And. B2In( B2Up( B2Word( cRest ) ), "SUB,FUNCTION,DEF" )
            B2Close()
            nOwner := 1
            aCurParams := {}
            cCurParamList := ""
            cFnName := ""
            cCurSub := ""
            Loop
        EndIf

        // ---- statements da linha
        aL := {}
        aE := B2EmitList( cCode, "" )
        For k := 1 To Len( aE )
            AAdd( aL, aE[k] )
        Next
        If Len( aL ) > 0
            cFirst := LTrim( aL[1] )
            nIns := IIf( Left( cFirst, 5 ) == "Case " .Or. cFirst == "Otherwise" .Or. cFirst == "Else" .Or. Left( cFirst, 7 ) == "ElseIf ", 1, 0 )
            aE := { "// " + B2I2S( i ) + ": " + B2Clean( Left( cCode, 110 ) ) }
            If nIns == 1
                AAdd( aE, aL[1] )
            EndIf
            AAdd( aE, "QbL( " + B2I2S( i ) + " )" )
            For k := nIns + 1 To Len( aL )
                AAdd( aE, aL[k] )
            Next
            If lDispBlk
                If !lGrd
                    nPc += 1
                    B2Put( { "If __PC <= " + B2I2S( nPc ) + "    // pc " + B2I2S( nPc ) } )
                    lGrd := .T.
                    nGrDep := 0
                EndIf
                B2Put( aE )
                nGrDep += B2GrdDelta( aE )
                If nGrDep <= 0
                    B2Put( { "__PC := " + B2I2S( nPc + 1 ), "EndIf" } )
                    lGrd := .F.
                EndIf
            Else
                B2Put( aE )
            EndIf
        EndIf
        // GOTO para frente emitido nesta linha -> guarda o que vem ate o label
        For k := 1 To Len( aFwdPending )
            B2Put( { "If !__QBG_" + aFwdPending[k] + "    // salto sobre " + aFwdPending[k] } )
            AAdd( aFwdOpen, aFwdPending[k] )
        Next
        aFwdPending := {}
        B2CloseGotos( i, .F. )
    Next
    B2Close()
    nOwner := 1
    B2CloseGotos( 0, .T. )

    // ---- despachante de ON ERROR GOTO
    If Len( aErrLbl ) > 0
        cBody := "/* despachante de ON ERROR GOTO — o tratador e uma rotina GOSUB que termina em RESUME */" + Chr( 10 ) + ;
                 "Static Function B_QbErrCall( cLbl )" + Chr( 10 ) + "    Do Case" + Chr( 10 )
        For k := 1 To Len( aErrLbl )
            cBody += "    Case cLbl == """ + aErrLbl[k] + """ ; LB_" + aErrLbl[k] + "()" + Chr( 10 )
        Next
        cBody += "    EndCase" + Chr( 10 ) + "Return" + Chr( 10 ) + Chr( 10 )
        AAdd( aOutBlk, cBody )
    EndIf

    // ---- Main
    For k := 1 To Len( aData )
        cData += IIf( k > 1, ", ", "" ) + aData[k]
        If Mod( k, 12 ) == 0 .And. k < Len( aData )
            cData += " ;" + Chr( 10 ) + "        "
        EndIf
    Next
    cMain := "/* Main — modulo principal de " + cSrcName + " */" + Chr( 10 )
    cMain += "User Function Main()" + Chr( 10 )
    cMain += "    Local oErr" + Chr( 10 )
    cMain += "    Private " + QbRtVars() + Chr( 10 )
    cMain += "    @@PRIV1@@" + Chr( 10 )
    cMain += "    aQbData := { " + cData + " }" + Chr( 10 )
    cMain += "    nQbDataPos := 0" + Chr( 10 )
    cMain += "    QbInit()" + Chr( 10 )
    cMain += "    Try" + Chr( 10 )
    cMain += B2Fmt( aMainL, 2 )
    cMain += "    Catch oErr" + Chr( 10 )
    cMain += "        QbCatch( oErr )" + Chr( 10 )
    cMain += "    EndTry" + Chr( 10 )
    cMain += "    QbTerm()" + Chr( 10 )
    cMain += "Return .T." + Chr( 10 )

    cOut := "/*" + Chr( 10 )
    cOut += "  Gerado por bas2prg.prg a partir de " + cSrcName + " — nao editar." + Chr( 10 )
    cOut += "  Cada '// n:' indica a linha n do .bas; QbL(n) marca a linha (QB_TRACE=arquivo grava o rastro)." + Chr( 10 )
    If Len( aWarn ) > 0
        cOut += "  Construcoes nao suportadas (" + B2I2S( Len( aWarn ) ) + "):" + Chr( 10 )
        For k := 1 To Len( aWarn )
            cOut += "    - " + B2Clean( aWarn[k] ) + Chr( 10 )
        Next
    EndIf
    cOut += "*/" + Chr( 10 )
    cOut += "#define QB_" + "LIB" + Chr( 10 )   // concatenado: o pre-processador expande macros ate em literais
    cOut += '#include "qbasic.prg"' + Chr( 10 ) + Chr( 10 )
    For k := 1 To Len( aOutBlk )
        cOut += aOutBlk[k]
    Next
    cOut += cMain
    For k := 1 To Len( aOwners )
        cOut := StrTran( cOut, "@@PRIV" + B2I2S( k ) + "@@", B2PrivDecl( k, k == 1 ) )
    Next
    For k := 1 To Len( aDispRid )
        cOut := StrTran( cOut, "@@DISP" + B2I2S( aDispRid[k] ) + "@@", B2DispCases( aDispRid[k] ) )
    Next
Return cOut

/*/{Protheus.doc} B2OnLabel
    Label encontrado na geracao: rotina GOSUB, inicio de laco de GOTO ou
    apenas marcador (labels de DATA).
/*/
Static Function B2OnLabel( cLbl, nLine )
    Local k := Nil, j := Nil, nC := 0
    // fecha guardas de GOTO-para-frente que apontam para este label
    For j := 1 To Len( aFwdOpen )
        If aFwdOpen[j] == cLbl
            nC += 1
        EndIf
    Next
    For j := 1 To nC
        B2Put( { "EndIf    // fim do salto para " + cLbl } )
    Next
    If nC > 0
        B2Put( { "__QBG_" + cLbl + " := .F." } )
        j := 1
        Do While j <= Len( aFwdOpen )
            If aFwdOpen[j] == cLbl
                ADel( aFwdOpen, j )          // ADel ja trunca nesta VM
            Else
                j += 1
            EndIf
        EndDo
    EndIf
    If AScan( aFnLbl, cLbl ) > 0
        // o fluxo "cai" dentro da rotina do label (fallthrough do QBasic)
        If lDispBlk
            If lGrd
                B2Put( { "LB_" + cLbl + "()    // continua no label " + cLbl } )
            Else
                nPc += 1
                B2Put( { "If __PC <= " + B2I2S( nPc ), "    LB_" + cLbl + "()    // continua no label " + cLbl, ;
                         "__PC := " + B2I2S( nPc + 1 ), "EndIf" } )
            EndIf
        Else
            B2Put( { "LB_" + cLbl + "()    // continua no label " + cLbl } )
        EndIf
        B2Close()
        aCurParams := {}
        nCurRid := aRid[ nLine ]
        AAdd( aRidFn, { nCurRid, "LB_" + cLbl } )
        B2Open( "LBL", "/* label " + cLbl + " — .bas linha " + B2I2S( nLine ) + " (GOSUB) */" + Chr( 10 ) + ;
                "Static Function LB_" + cLbl + "( nPc0 )" )
        lDispBlk := AScan( aDispRid, nCurRid ) > 0
        If lDispBlk
            B2DispHead()
        EndIf
        Return
    EndIf
    If lDispBlk
        AAdd( aDispMap, { nCurRid, cLbl, IIf( lGrd, nPc, nPc + 1 ) } )
        B2Put( { "// label " + cLbl } )
        Return
    EndIf
    k := AScan( aGotoLoop, {|x| x[1] == cLbl } )
    If k > 0
        B2Put( { "Do While .T.    // label " + cLbl + " (alvo de GOTO)" } )
        AAdd( aGotoOpen, { cLbl, aGotoLoop[k][2], nLoopDepth, nBlkDepth, nBlkId } )
        Return
    EndIf
    B2Put( { "// label " + cLbl } )
Return

/*/{Protheus.doc} B2Transpile
    Transpila cFile -> <base>_qb.prg. Retorna o nome gerado ou "".
/*/
Static Function B2Transpile( cFile )
    Local cSrc := Nil, cOut := Nil, nP := Nil, cOutBase := Nil, cDst := Nil, k := Nil
    Private aLines := {}, aConst := {}, aConstN := {}, aType := {}, aVarType := {}, aVarTN := {}
    Private aArrN := {}, aArrLB := {}, aParamLB := {}, aShared := {}, aSubs := {}, aFnN := {}, aSig2 := {}
    Private aStrVars := {}, aIntVars := {}, aFltVars := {}, cDefInt := "", cDefStr := "", cBase := "0"
    Private aLblPos := {}, aDataLbl := {}, aFnLbl := {}, aGotoLoop := {}, aGotoOpen := {}, aData := {}
    Private aWarn := {}, aOwners := {}, nOwner := 0, aCurParams := {}, cCurParamList := "", cCurSub := ""
    Private cFnName := "", lFnStr := .F., lFnInt := .F., nSel := 0, aSelStk := {}
    Private cBlkKind := "", cBlkHdr := "", aBlkL := {}, aMainL := {}, aOutBlk := {}
    Private nLoopDepth := 0, nBlkDepth := 0, aMainDepth := { 0, 0 }, nBlkId := 0, nCurLine := 0, cSrcName := cFile, aB2Cp := QCpTable()
    Private aGotoFwd := {}, aFwdPending := {}, aFwdOpen := {}, aErrLbl := {}, lQbTrap := .F., aDepth := {}
    Private aRid := {}, aDispRid := {}, aDispLbls := {}, aResLbl := {}, aFldMap := {}, aDispMap := {}, aRidFn := {}
    Private lDispBlk := .F., lGrd := .F., nGrDep := 0, nPc := 0, lTrapSav := .F., nCurRid := 0, aLngVars := {}

    cSrc := MemoRead( cFile )
    If ValType( cSrc ) != "C" .Or. Empty( cSrc )
        ConOut( "ERRO: nao consegui ler " + cFile )
        Return ""
    EndIf
    cSrc := StrTran( StrTran( cSrc, Chr( 13 ), "" ), Chr( 26 ), "" )
    aLines := StrTokArr2( cSrc, Chr( 10 ), .T. )

    B2ScanSubs()
    B2Scan()
    B2MapParams()
    nCurLine := 0
    cOut := B2Gen()

    nP := Rat( "/", cFile )
    cOutBase := IIf( nP > 0, SubStr( cFile, nP + 1 ), cFile )
    nP := Rat( ".", cOutBase )
    If nP > 0
        cOutBase := Left( cOutBase, nP - 1 )
    EndIf
    cDst := IIf( Rat( "/", cFile ) > 0, Left( cFile, Rat( "/", cFile ) ), "" ) + cOutBase + "_qb.prg"
    MemoWrite( cDst, cOut )
    ConOut( "bas2prg: " + cFile + " (" + B2I2S( Len( aLines ) ) + " linhas) -> " + cDst + " (" + B2I2S( Len( cOut ) ) + " bytes)" )
    If Len( aWarn ) > 0
        ConOut( "bas2prg: " + B2I2S( Len( aWarn ) ) + " construcao(oes) nao suportada(s):" )
        For k := 1 To Len( aWarn )
            ConOut( "  - " + aWarn[k] )
        Next
    EndIf
Return cDst

// ===========================================================================
// Main — transpilador standalone
// ===========================================================================
#ifndef B2_LIB
User Function Main()
    Local cFile := QbEnv( "QB_FILE" )
    If Empty( cFile )
        cFile := ConIn( "Arquivo .bas: " )
        cFile := IIf( ValType( cFile ) == "C", AllTrim( cFile ), "" )
    EndIf
    If Empty( cFile )
        ConOut( "uso: QB_FILE=programa.bas advplc run bas2prg.prg" )
        Return .F.
    EndIf
Return !Empty( B2Transpile( cFile ) )
#endif
