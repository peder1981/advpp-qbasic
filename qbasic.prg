/*
{Protheus.doc} qbasic.prg
    @type        source
    @author      AdvPP reconstruction
    @description Ambiente QBasic sobre o AdvPP. Dois papeis no mesmo arquivo:

                 1. RUNTIME (biblioteca) — emula a API do QBasic para os
                    programas gerados por bas2prg.prg. Os .prg gerados fazem
                        #define QB_LIB
                        #include "qbasic.prg"
                    e so recebem as funcoes Qb* / Q* (sem o Main do runner).

                 2. RUNNER (quando executado diretamente) — le um .bas,
                    transpila via bas2prg.prg e executa o resultado:
                        advplc run qbasic.prg            (pergunta o .bas)
                        QB_FILE=gorilla.bas advplc run qbasic.prg
                        QB_ACTION=gen  -> so gera <nome>_qb.prg (p/ depurar)
                    Sem tty (pipe): a 1a linha do stdin e o nome do .bas e o
                    restante vira o teclado do programa (smoke tests).

    @mapping     INKEY$   -> stty raw (VMIN=0) + FReadStr nao-bloqueante;
                             sem tty, teclas vem do stdin com cadencia de 250ms
                 SCREEN n -> resolucao virtual do modo (ex.: 9 = 640x350)
                             mapeada numa grade fisica 80x50 de meio-blocos
                 POINT    -> cor QBasic (0-15) da grade fisica (colisao)
                 COLOR    -> paleta CGA 0-15 convertida para ANSI
                 PLAY     -> MML -> ffplay(sine) em background
                 PEEK/POKE-> memoria virtual + DEF SEG; B800 = video texto
                 END      -> Throw("QBEND") capturado pelo Main gerado
*/
#ifndef QB_RT
#define QB_RT

#include "cp437.prg"

#define QB_PW    80      // grade fisica de pixels: 80 colunas
#define QB_PH    50      // x 50 linhas (2 pixels por celula, meio-bloco)
#define QB_MEMLO 1280    // memoria baixa virtual 0x0000-0x04FF
#define QB_VIDEO 753664  // 0xB8000 — video texto 80x25x2
#define QB_LOOPRATE 20000 // iteracoes/s de um FOR vazio num PC da epoca

/*/{Protheus.doc} QbRtVars
    Lista das variaveis globais do runtime. O Main do programa consumidor
    deve declara-las como Private (o transpilador emite esta lista).
/*/
Static Function QbRtVars()
Return "cEsc, lQbTTY, hQbIn, aQbPix, aQbScr, aQbMem, aQbCp, aQbAnsi, " + ;
       "nQbFg, nQbBg, nQbW, nQbH, nQbRow, nQbCol, nQbVW, nQbVH, nQbMode, " + ;
       "nQbSeg, nQbLX, nQbLY, cQbKBuf, cQbPipe, nQbPipePos, nQbLastKey, " + ;
       "lQbSound, lQbAlt, nQbLine, hQbTrace, aQbData, nQbDataPos, " + ;
       "cQbErrHdl, nQbErr, nQbResume, nQbResLbl, __QBRETRY, __QBSVERR, aQbFiles, cQbTmp, cQbBytes"

/*/{Protheus.doc} QbEnv
    GetEnv seguro: no AdvPP uma variavel inexistente volta como "Nil".
/*/
Static Function QbEnv( cVar )
    Local x := GetEnv( cVar )
    If ValType( x ) != "C" .Or. x == "Nil"
        Return ""
    EndIf
Return x

/*/{Protheus.doc} QbInit
    Inicializa o estado "DIM SHARED" do runtime. Chamar 1x no inicio do Main.
/*/
Static Function QbInit()
    Local i := Nil, cStty := Nil, cHas := ""
    cEsc     := Chr( 27 )
    lQbTTY   := UiTermWidth( 0 ) > 0
    hQbIn    := -1
    nQbFg    := 7
    nQbBg    := 0
    nQbW     := 80
    nQbH     := 25
    nQbRow   := 1
    nQbCol   := 1
    nQbVW    := 80
    nQbVH    := 25
    nQbMode  := 0
    nQbSeg   := 0
    nQbLX    := 0
    nQbLY    := 0
    nQbLine  := 0
    cQbKBuf  := ""
    cQbPipe  := ""
    nQbPipePos := 1
    nQbLastKey := Seconds()
    lQbAlt   := .F.
    aQbCp    := QCpTable()
    aQbAnsi  := { 0, 4, 2, 6, 1, 5, 3, 7, 8, 12, 10, 14, 9, 13, 11, 15 }
    If ValType( aQbData ) != "A"
        aQbData := {}
    EndIf
    If ValType( nQbDataPos ) != "N"
        nQbDataPos := 0
    EndIf
    // QB_TRACE=<arquivo>: registra cada linha do .bas executada (depuracao)
    hQbTrace := -1
    If !Empty( QbEnv( "QB_TRACE" ) )
        hQbTrace := FCreate( QbEnv( "QB_TRACE" ) )
    EndIf
    cQbErrHdl := ""
    nQbErr    := 0
    nQbResume := 0
    nQbResLbl := ""
    __QBRETRY := .F.
    __QBSVERR := Nil
    aQbFiles  := Array( 15 )
    aQbMem := Array( QB_MEMLO )
    AFill( aQbMem, 0 )
    // diretorio temporario privado (evita symlink previsivel em /tmp)
    cQbTmp := ""
    ProcRun( "mktemp", { "-d", "/tmp/qb_XXXXXX" }, {|c| cQbTmp := AllTrim( c ) } )
    If Empty( cQbTmp )
        cQbTmp := "/tmp/qb_" + QbPid()
    EndIf
    // tabela de 256 bytes crus: strings sao byte-arrays nesta VM mas Chr()
    // codifica UTF-8 (bytes >=128 viram 2+ bytes) — gera via printf octal
    cQbBytes := ""
    ProcRun( "bash", { "-c", 'for i in $(seq 0 255); do printf "\\$(printf %03o $i)"; done > "' + cQbTmp + '/b.tbl"' } )
    cStty := FOpen( cQbTmp + "/b.tbl", 0 )
    If cStty >= 0
        cQbBytes := FReadStr( cStty, 256 )
        FClose( cStty )
    EndIf
    If ValType( cQbBytes ) != "C" .Or. Len( cQbBytes ) < 256
        cQbBytes := ""
    EndIf
    QbAllocScr()

    If lQbTTY
        cStty := "stty -F /dev/tty -g 2>/dev/null > " + cQbTmp + "/tty.state; "
        cStty += "stty -F /dev/tty -icanon -echo min 0 time 0 2>/dev/null; true"
        ProcRun( "bash", { "-c", cStty } )
        hQbIn := FOpen( "/dev/stdin" )
        UiAltScreenEnter()
        lQbAlt := .T.
        ConOutRaw( cEsc + "[?25l" )
    Else
        cQbPipe := MemoRead( "/dev/stdin" )
        If ValType( cQbPipe ) != "C"
            cQbPipe := ""
        EndIf
    EndIf

    // som so em tty e com ffplay presente (QB_NOSOUND=1 desliga)
    lQbSound := .F.
    If lQbTTY .And. Empty( QbEnv( "QB_NOSOUND" ) )
        ProcRun( "bash", { "-c", "command -v ffplay >/dev/null 2>&1 && echo y" }, {|c| cHas := c } )
        lQbSound := ( AllTrim( cHas ) == "y" )
    EndIf
    QbCls()
Return

/*/{Protheus.doc} QbAllocScr
    (Re)aloca a grade fisica de pixels e a grade de texto (char,fg,bg).
/*/
Static Function QbAllocScr()
    Local i := Nil, j := Nil
    aQbPix := Array( QB_PH )
    For i := 1 To QB_PH
        aQbPix[i] := Array( QB_PW )
        AFill( aQbPix[i], 0 )
    Next
    aQbScr := Array( nQbH )
    For i := 1 To nQbH
        aQbScr[i] := Array( nQbW )
        For j := 1 To nQbW
            aQbScr[i][j] := { " ", 7, 0 }
        Next
    Next
Return

/*/{Protheus.doc} QbPid
    PID do processo (nomes temporarios exclusivos).
/*/
Static Function QbPid()
    Local cStat := MemoRead( "/proc/self/stat" ), nP := Nil
    If ValType( cStat ) != "C"
        Return "0"
    EndIf
    nP := At( " ", cStat )
Return IIf( nP > 0, AllTrim( Left( cStat, nP - 1 ) ), "0" )

/*/{Protheus.doc} QbTerm
    Restaura terminal (tty salvo, cursor, cores, tela principal).
/*/
Static Function QbTerm()
    Local cState := Nil
    If ValType( lQbTTY ) != "L"
        Return
    EndIf
    QbClose( 0 )
    ConOutRaw( cEsc + "[0m" + cEsc + "[?25h" )
    If hQbTrace >= 0
        FClose( hQbTrace )
        hQbTrace := -1
    EndIf
    If lQbTTY
        If hQbIn >= 0
            FClose( hQbIn )
            hQbIn := -1
        EndIf
        cState := cQbTmp + "/tty.state"
        ProcRun( "bash", { "-c", "stty -F /dev/tty $(cat " + cState + " 2>/dev/null) 2>/dev/null || stty -F /dev/tty sane 2>/dev/null; rm -f " + cState + "; rmdir " + cQbTmp + " 2>/dev/null; true" } )
        If lQbAlt
            UiAltScreenExit()
            lQbAlt := .F.
        EndIf
    Else
        ConOutRaw( Chr( 10 ) )
        ProcRun( "bash", { "-c", "rmdir " + cQbTmp + " 2>/dev/null; true" } )
    EndIf
Return

/*/{Protheus.doc} QbL
    Marca a linha corrente do .bas (emitido antes de cada linha traduzida).
/*/
Static Function QbL( n )
    nQbLine := n
    If hQbTrace >= 0
        FWrite( hQbTrace, AllTrim( Str( n ) ) + Chr( 10 ) )
    EndIf
Return

/*/{Protheus.doc} QbEnd
    END / SYSTEM / STOP — encerra o programa de qualquer profundidade.
/*/
Static Function QbEnd()
    Throw( "QBEND" )
Return

/*/{Protheus.doc} QbCatch
    Tratador do Main gerado: QBEND e saida normal; o resto e erro de runtime
    reportado com a linha do .bas (nQbLine) para depuracao.
/*/
Static Function QbCatch( oErr )
    Local cMsg := Nil
    cMsg := IIf( ValType( oErr ) == "O", oErr:Description, cValToChar( oErr ) )
    If "QBEND" $ cMsg
        Return
    EndIf
    QbTerm()
    ConOut( "Erro de runtime QBasic na linha " + AllTrim( Str( nQbLine ) ) + " do .bas: " + cMsg )
Return

/*/{Protheus.doc} QbErrText / QbIsCtl / QbResTarget / QbErrNo
    Excecao -> texto; excecoes de controle (QBEND/QBGOTO); alvo de um
    QBGOTO; e codigo de erro estilo QBasic para ERR.
/*/
Static Function QbErrText( oErr )
    If ValType( oErr ) == "O"
        Return cValToChar( oErr:Description )
    EndIf
Return cValToChar( oErr )

Static Function QbIsCtl( oErr )
    Local c := QbErrText( oErr )
Return "QBEND" $ c .Or. "QBGOTO:" $ c

Static Function QbResTarget( oErr )
    Local c := QbErrText( oErr ), n := At( "QBGOTO:", c )
Return IIf( n > 0, SubStr( c, n + 7 ), "" )

Static Function QbErrNo( oErr )
    Local c := Upper( QbErrText( oErr ) ), n := At( "QBERR:", c )
    If n > 0
        n := Val( SubStr( c, n + 6 ) )
        If n > 0
            Return n
        EndIf
    EndIf
    Do Case
    Case "FILE NOT FOUND" $ c                          ; Return 53
    Case "BAD FILE" $ c                                ; Return 52
    Case "TOO MANY FILES" $ c                          ; Return 67
    Case "EOF" $ c .Or. "PAST END" $ c                 ; Return 62
    Case "DIVISION" $ c .Or. "DIVIDE" $ c              ; Return 11
    Case "RANGE" $ c .Or. "SUBSCRIPT" $ c              ; Return 9
    Case "TYPE MISMATCH" $ c                           ; Return 13
    Case "OVERFLOW" $ c                                ; Return 6
    Case "ILLEGAL" $ c .Or. "INVALID" $ c              ; Return 5
    EndCase
Return 5

/*/{Protheus.doc} QbGoto / QbRaise
    Salto arbitrario por excecao (PC-dispatch) e ERROR n do QBasic.
/*/
Static Function QbGoto( cLbl )
    Throw( "QBGOTO:" + Upper( AllTrim( cLbl ) ) )
Return

Static Function QbRaise( n )
    Throw( "QBERR:" + AllTrim( Str( Int( n ) ) ) )
Return

// ---------------------------------------------------------------------------
// Texto: COLOR / LOCATE / CLS / PRINT
// ---------------------------------------------------------------------------

/*/{Protheus.doc} QbI2S
/*/
Static Function QbI2S( n )
Return AllTrim( Str( Int( n ) ) )

/*/{Protheus.doc} QbAnsi
    Cor QBasic 0-15 (CGA) -> indice ANSI-256 (0-15 na ordem ANSI).
/*/
Static Function QbAnsi( c )
    If ValType( c ) != "N"
        c := 0
    EndIf
Return aQbAnsi[ Mod( Int( Abs( c ) ), 16 ) + 1 ]

Static Function QbAt( x, y )
    ConOutRaw( cEsc + "[" + QbI2S( y ) + ";" + QbI2S( x ) + "H" )
Return

Static Function QbCol( fg, bg )
    ConOutRaw( cEsc + "[38;5;" + QbI2S( QbAnsi( fg ) ) + ";48;5;" + QbI2S( QbAnsi( bg ) ) + "m" )
Return

/*/{Protheus.doc} QbColor
    COLOR [fg][,bg] — argumentos omitidos mantem o valor atual.
/*/
Static Function QbColor( fg, bg )
    If ValType( fg ) == "N"
        nQbFg := Int( fg )
    EndIf
    If ValType( bg ) == "N"
        nQbBg := Int( bg )
    EndIf
    QbCol( nQbFg, nQbBg )
Return

/*/{Protheus.doc} QbLocate
    LOCATE [row][,col] — omitidos mantem a posicao atual.
/*/
Static Function QbLocate( r, c )
    If ValType( r ) == "N"
        nQbRow := Max( 1, Min( nQbH, QCint( r ) ) )
    EndIf
    If ValType( c ) == "N"
        nQbCol := Max( 1, Min( nQbW, QCint( c ) ) )
    EndIf
    QbAt( nQbCol, nQbRow )
Return

/*/{Protheus.doc} QbCls
    CLS — limpa tela, grade de texto e framebuffer de pixels.
/*/
Static Function QbCls()
    Local i := Nil, j := Nil
    For i := 1 To QB_PH
        AFill( aQbPix[i], nQbBg )
    Next
    For i := 1 To nQbH
        For j := 1 To nQbW
            aQbScr[i][j] := { " ", nQbFg, nQbBg }
        Next
    Next
    nQbRow := 1
    nQbCol := 1
    QbCol( nQbFg, nQbBg )
    ConOutRaw( cEsc + "[2J" + cEsc + "[H" )
Return

/*/{Protheus.doc} QbWidth
    WIDTH cols[,rows] — ajusta a grade de texto (80/40 x 25/43/50).
/*/
Static Function QbWidth( nC, nR )
    If ValType( nC ) == "N" .And. nC > 0
        nQbW := Int( nC )
    EndIf
    If ValType( nR ) == "N" .And. nR > 0
        nQbH := Int( nR )
    EndIf
    QbAllocScr()
    QbCls()
Return

/*/{Protheus.doc} QbGlyphs
    Quantidade de glifos de uma string UTF-8 (para avancar a coluna).
/*/
Static Function QbGlyphs( c )
    Local i := Nil, n := 0, b := Nil
    For i := 1 To Len( c )
        b := Asc( SubStr( c, i, 1 ) )
        If b < 128 .Or. b >= 192
            n += 1
        EndIf
    Next
Return n

/*/{Protheus.doc} QbOut
    Emite texto na posicao corrente com a cor corrente e avanca a coluna.
/*/
Static Function QbOut( cTxt )
    Local i := Nil, nLast := 0
    If Empty( cTxt ) .And. Len( cTxt ) == 0
        Return
    EndIf
    QbCol( nQbFg, nQbBg )
    ConOutRaw( cTxt )
    For i := 1 To Len( cTxt )
        If SubStr( cTxt, i, 1 ) == Chr( 10 )
            nQbRow += 1
            nLast := i
        EndIf
    Next
    If nLast > 0
        nQbCol := QbGlyphs( SubStr( cTxt, nLast + 1 ) ) + 1
    Else
        nQbCol += QbGlyphs( cTxt )
    EndIf
Return

/*/{Protheus.doc} QbPr
    PRINT de um item: numeros com espaco de sinal e espaco final (QBasic).
/*/
Static Function QbPr( x )
    Do Case
    Case ValType( x ) == "N"
        QbOut( QStr( x ) + " " )
    Case ValType( x ) == "L"
        QbOut( QStr( IIf( x, -1, 0 ) ) + " " )
    Case ValType( x ) == "C"
        QbOut( x )
    EndCase
Return

/*/{Protheus.doc} QbPrZone
    Separador ',' do PRINT: proxima zona de 14 colunas.
/*/
Static Function QbPrZone()
    Local nNext := Int( ( nQbCol - 1 ) / 14 ) * 14 + 15
    QbOut( Space( Max( 1, nNext - nQbCol ) ) )
Return

/*/{Protheus.doc} QbPrTab
    TAB(n) dentro do PRINT: avanca ate a coluna n (quebra linha se ja passou).
/*/
Static Function QbPrTab( n )
    n := Int( n )
    If n < nQbCol
        QbPrNL()
    EndIf
    If n > nQbCol
        QbOut( Space( n - nQbCol ) )
    EndIf
Return

/*/{Protheus.doc} QbPrNL
    Fim de PRINT sem ';' — nova linha (rola na ultima linha).
/*/
Static Function QbPrNL()
    nQbCol := 1
    If nQbRow < nQbH
        nQbRow += 1
        QbAt( 1, nQbRow )
    Else
        ConOutRaw( Chr( 13 ) + Chr( 10 ) )
    EndIf
Return

/*/{Protheus.doc} QbUSING
    PRINT USING simplificado: largura = quantidade de '#'.
/*/
Static Function QbUSING( cFmt, x )
    Local nW := 0, nDec := 0, k := Nil, nP := Nil
    If ValType( x ) != "N"
        Return cValToChar( x )
    EndIf
    For k := 1 To Len( cFmt )
        If SubStr( cFmt, k, 1 ) == "#"
            nW += 1
        EndIf
    Next
    nP := At( ".", cFmt )
    If nP > 0
        For k := nP + 1 To Len( cFmt )
            If SubStr( cFmt, k, 1 ) == "#"
                nDec += 1
            EndIf
        Next
    EndIf
Return PadL( AllTrim( Str( x, 20, nDec ) ), Max( 1, nW + IIf( nDec > 0, 1, 0 ) ) )

// ---------------------------------------------------------------------------
// Funcoes BASIC (strings / numeros / logica)
// ---------------------------------------------------------------------------

/*/{Protheus.doc} QNumStr
    Numero -> texto no estilo QBasic (precisao simples, sem zeros a direita).
/*/
Static Function QNumStr( n )
    Local c := Nil, nInt := Nil, nDec := Nil
    If n == Int( n ) .And. Abs( n ) < 1e15
        Return AllTrim( Str( n, 20, 0 ) )
    EndIf
    nInt := Len( AllTrim( Str( Int( Abs( n ) ), 20, 0 ) ) )
    nDec := Max( 1, 7 - IIf( Int( Abs( n ) ) == 0, 0, nInt ) )
    c := AllTrim( Str( n, 30, nDec ) )
    Do While "." $ c .And. Right( c, 1 ) == "0"
        c := Left( c, Len( c ) - 1 )
    EndDo
    If Right( c, 1 ) == "."
        c := Left( c, Len( c ) - 1 )
    EndIf
    c := StrTran( c, "-0.", "-." )
    If Left( c, 2 ) == "0."
        c := SubStr( c, 2 )
    EndIf
Return c

/*/{Protheus.doc} QStr
    STR$ — espaco de sinal para positivos.
/*/
Static Function QStr( n )
    If ValType( n ) == "L"
        n := IIf( n, -1, 0 )
    EndIf
Return IIf( n >= 0, " ", "" ) + QNumStr( n )

/*/{Protheus.doc} QChr / QAsc
    CHR$/ASC sobre a code page 437 (blocos, setas, molduras do DOS).
/*/
Static Function QChr( n )
    n := Int( n )
    If n == 0 .Or. n == 7 .Or. n == 8 .Or. n == 9 .Or. n == 10 .Or. n == 13 .Or. ( n >= 32 .And. n <= 126 )
        Return Chr( n )
    EndIf
    If n < 0 .Or. n > 255
        Return ""
    EndIf
Return aQbCp[ n + 1 ]

Static Function QAsc( c )
    Local b := Nil, nL := Nil, k := Nil
    If Len( c ) == 0
        Return 0
    EndIf
    b := Asc( Left( c, 1 ) )
    If b < 128
        Return b
    EndIf
    nL := IIf( b >= 240, 4, IIf( b >= 224, 3, 2 ) )
    k := AScan( aQbCp, Left( c, nL ) )
Return IIf( k > 0, k - 1, b )

/*/{Protheus.doc} QInstr
    INSTR([start,] s$, t$) — ordem de argumentos do QBasic.
/*/
Static Function QInstr( a, b, c )
    Local n := Nil
    If ValType( a ) == "N"
        n := At( c, SubStr( b, a ) )
        Return IIf( n > 0, n + a - 1, 0 )
    EndIf
Return At( b, a )

/*/{Protheus.doc} QString
    STRING$(n, c$|codigo)
/*/
Static Function QString( n, c )
    If ValType( c ) == "N"
        c := QChr( c )
    Else
        c := Left( c, 1 )
    EndIf
Return Replicate( c, Max( 0, Int( n ) ) )

/*/{Protheus.doc} QCint / QInt / QMod / IntDiv
    CINT (arredondamento bancario), INT (piso), MOD e '\' com operandos
    arredondados para inteiro como no QBasic.
/*/
Static Function QCint( x )
    Local f := Nil, d := Nil
    If ValType( x ) == "L"
        Return IIf( x, -1, 0 )
    EndIf
    f := QInt( x )
    d := x - f
    If d > 0.5
        Return f + 1
    ElseIf d < 0.5
        Return f
    EndIf
Return IIf( Mod( f, 2 ) == 0, f, f + 1 )

Static Function QInt( x )
    Local n := Int( x )
Return IIf( x < 0 .And. n != x, n - 1, n )

Static Function QMod( a, b )
    a := QCint( a )
    b := QCint( b )
    If b == 0
        Return 0
    EndIf
Return a - Int( a / b ) * b

Static Function IntDiv( a, b )
    a := QCint( a )
    b := QCint( b )
    If b == 0
        Return 0
    EndIf
Return Int( a / b )

Static Function QSign( x ) ; Return IIf( x > 0, 1, IIf( x < 0, -1, 0 ) )
// Randomize() do AdvPP limita o intervalo a 32767: duas amostras = ~30 bits
Static Function QRndF( x ) ; Return ( Randomize( 0, 32767 ) * 32767 + Randomize( 0, 32767 ) ) / ( 32767 * 32767 )
/*/{Protheus.doc} QTimer
    TIMER — segundos desde a meia-noite. Cada leitura custa 1 ms, como a
    chamada era cara num PC da epoca: lacos que calibram velocidade
    contando iteracoes ate o TIMER avancar (ex.: CalcDelay do GORILLAS)
    passam a medir ~1000 iteracoes/s em vez da velocidade da VM.
/*/
Static Function QTimer()
    Sleep( 1 )
Return Mod( Seconds(), 86400 )
/*/{Protheus.doc} QTab
    TAB(n) avaliado como expressao (fora do PRINT): devolve os espacos ate
    a coluna n a partir da coluna corrente. No PRINT o transpilador emite
    QbPrTab(), que faz o posicionamento exato inclusive com quebra de linha.
/*/
Static Function QTab( n )
    n := Int( n )
    If n < nQbCol
        Return Chr( 13 ) + Chr( 10 ) + Space( Max( 0, n - 1 ) )
    EndIf
Return Space( n - nQbCol )
Static Function QPos( n )  ; Return nQbCol
Static Function QCsrLin()  ; Return nQbRow
Static Function QInp( n )  ; Return 0
Static Function QStrig( n ); Return 0
Static Function QDate()
    Local d := Date()
Return StrZero( Month( d ), 2 ) + "-" + StrZero( Day( d ), 2 ) + "-" + StrZero( Year( d ), 4 )

Static Function QHex( n )
    Local c := "", nN := Int( n )
    If nN < 0
        nN += 65536
    EndIf
    Do While nN > 0
        c := SubStr( "0123456789ABCDEF", Mod( nN, 16 ) + 1, 1 ) + c
        nN := Int( nN / 16 )
    EndDo
Return IIf( c == "", "0", c )

Static Function QOct( n )
    Local c := "", nN := Int( n )
    Do While nN > 0
        c := Chr( 48 + Mod( nN, 8 ) ) + c
        nN := Int( nN / 8 )
    EndDo
Return IIf( c == "", "0", c )

/*/{Protheus.doc} QDelayLoop
    "FOR i = a TO b: NEXT" vazio = espera calibrada pela CPU no QBasic.
    Emula uma maquina da epoca (QB_LOOPRATE iteracoes/s) para que a
    calibracao do programa (TIMER antes/depois) continue coerente.
    Retorna o valor final da variavel de controle (b + passo).
/*/
Static Function QDelayLoop( nFrom, nTo, nStep )
    Local nIt := 0, nEnd := 0
    nStep := IIf( ValType( nStep ) == "N" .And. nStep != 0, nStep, 1 )
    nIt := Max( 0, Int( ( nTo - nFrom ) / nStep ) + 1 )
    nEnd := Seconds() + nIt / QB_LOOPRATE
    Do While Seconds() < nEnd
        If nEnd - Seconds() > 0.003
            Sleep( 1 )
        EndIf
    EndDo
Return nFrom + nIt * nStep

/*/{Protheus.doc} QbT / QbN
    Verdade do QBasic: numero != 0 e verdadeiro; comparacoes valem -1/0.
/*/
Static Function QbT( x )
    Do Case
    Case ValType( x ) == "L" ; Return x
    Case ValType( x ) == "N" ; Return x != 0
    Case ValType( x ) == "C" ; Return Len( x ) > 0
    EndCase
Return .F.

Static Function QbN( x )
Return IIf( ValType( x ) == "L", IIf( x, -1, 0 ), x )

/*/{Protheus.doc} QAnd / QOr / QXor / QNot / QEqv / QImp
    Operadores logicos do QBasic: bit-a-bit sobre inteiros; logicos se
    ambos os operandos ja forem logicos (resultado de comparacoes).
/*/
Static Function QAnd( a, b )
    If ValType( a ) == "L" .And. ValType( b ) == "L"
        Return a .And. b
    EndIf
Return NAnd( QCint( QbN( a ) ), QCint( QbN( b ) ) )

Static Function QOr( a, b )
    If ValType( a ) == "L" .And. ValType( b ) == "L"
        Return a .Or. b
    EndIf
Return NOr( QCint( QbN( a ) ), QCint( QbN( b ) ) )

Static Function QXor( a, b )
    If ValType( a ) == "L" .And. ValType( b ) == "L"
        Return a != b
    EndIf
Return NXor( QCint( QbN( a ) ), QCint( QbN( b ) ) )

Static Function QNot( a )
    If ValType( a ) == "L"
        Return !a
    EndIf
Return -QCint( a ) - 1

Static Function QEqv( a, b ) ; Return QNot( QXor( a, b ) )
Static Function QImp( a, b ) ; Return QOr( QNot( a ), b )

/*/{Protheus.doc} QDimArr
    DIM a(d1, d2, ...) — aDims = tamanhos; xInit = valor (0, "") ou array
    modelo de um TYPE (clonado por elemento). Dims vazios -> so o elemento.
/*/
Static Function QDimArr( aDims, xInit, nLev )
    Local a := Nil, i := Nil, n := Nil
    If nLev == Nil
        nLev := 1
    EndIf
    If nLev > Len( aDims )
        Return IIf( ValType( xInit ) == "A", AClone( xInit ), xInit )
    EndIf
    n := Max( 0, Int( aDims[ nLev ] ) )
    a := Array( n )
    For i := 1 To n
        a[i] := QDimArr( aDims, xInit, nLev + 1 )
    Next
Return a

/*/{Protheus.doc} QbRead
    READ — proximo item do pool DATA (RESTORE ajusta nQbDataPos).
/*/
Static Function QbRead()
    nQbDataPos += 1
    If nQbDataPos > Len( aQbData )
        Return 0
    EndIf
Return aQbData[ nQbDataPos ]

// ---------------------------------------------------------------------------
// Teclado: INKEY$ / INPUT / SLEEP
// ---------------------------------------------------------------------------

/*/{Protheus.doc} QbKFill
    Alimenta cQbKBuf. Em tty: leitura nao-bloqueante (VMIN=0). Sem tty: o
    stdin inteiro foi lido no QbInit e as teclas sao liberadas a cada 250ms
    (lNow = imediato, usado pelo INPUT). Teclado esgotado -> encerra (END).
/*/
Static Function QbKFill( lNow )
    Local cB := Nil, nL := Nil
    If lQbTTY
        If hQbIn >= 0
            cB := FReadStr( hQbIn, 64 )
            If ValType( cB ) == "C" .And. Len( cB ) > 0
                cQbKBuf += cB
            EndIf
        EndIf
        Return
    EndIf
    If Len( cQbKBuf ) > 0
        Return
    EndIf
    If nQbPipePos > Len( cQbPipe )
        If Seconds() - nQbLastKey > 2.0
            QbEnd()
        EndIf
        Return
    EndIf
    If lNow == .T. .Or. Seconds() - nQbLastKey >= 0.25
        nL := 1
        If SubStr( cQbPipe, nQbPipePos, 2 ) == cEsc + "["
            nL := 2
            Do While nQbPipePos + nL <= Len( cQbPipe ) .And. SubStr( cQbPipe, nQbPipePos + nL, 1 ) $ "0123456789;?"
                nL += 1
            EndDo
            nL += 1
        EndIf
        cQbKBuf += SubStr( cQbPipe, nQbPipePos, nL )
        nQbPipePos += nL
        nQbLastKey := Seconds()
    EndIf
Return

/*/{Protheus.doc} QInkey
    INKEY$ — "" se nada; setas como CHR$(0)+"H"/"P"/"K"/"M" (como no DOS);
    Enter = CHR$(13); Backspace = CHR$(8).
/*/
Static Function QInkey()
    Local c := Nil, b := Nil, nL := Nil, i := 0, cFin := ""
    QbKFill()
    If Len( cQbKBuf ) == 0
        Return ""
    EndIf
    c := Left( cQbKBuf, 1 )
    // sequencias CSI/SS3 (ESC [ ... final, ESC O x): setas viram CHR$(0)+codigo;
    // respostas do terminal (ex.: ESC[25;1R) e outras teclas sao descartadas
    If c == cEsc .And. Len( cQbKBuf ) >= 2 .And. SubStr( cQbKBuf, 2, 1 ) $ "[O"
        i := 3
        Do While i <= Len( cQbKBuf ) .And. SubStr( cQbKBuf, i, 1 ) $ "0123456789;?"
            i += 1
        EndDo
        If i > Len( cQbKBuf )
            If lQbTTY
                Return ""                      // sequencia ainda incompleta
            EndIf
            cQbKBuf := ""
            Return ""
        EndIf
        cFin := SubStr( cQbKBuf, i, 1 )
        cQbKBuf := SubStr( cQbKBuf, i + 1 )
        Do Case
        Case cFin == "A" ; Return Chr( 0 ) + "H"
        Case cFin == "B" ; Return Chr( 0 ) + "P"
        Case cFin == "C" ; Return Chr( 0 ) + "M"
        Case cFin == "D" ; Return Chr( 0 ) + "K"
        Case cFin == "H" ; Return Chr( 0 ) + "G"
        Case cFin == "F" ; Return Chr( 0 ) + "O"
        EndCase
        Return ""
    EndIf
    b := Asc( c )
    nL := IIf( b >= 240, 4, IIf( b >= 224, 3, IIf( b >= 192, 2, 1 ) ) )
    c := Left( cQbKBuf, nL )
    cQbKBuf := SubStr( cQbKBuf, nL + 1 )
    Do Case
    Case c == Chr( 10 ) ; Return Chr( 13 )
    Case c == Chr( 127 ) ; Return Chr( 8 )
    EndCase
Return c

/*/{Protheus.doc} QInkeyWait
    Espera uma tecla (bloqueante).
/*/
Static Function QInkeyWait( lNow )
    Local k := ""
    Do While .T.
        QbKFill( lNow )
        k := QInkey()
        If Len( k ) > 0
            Exit
        EndIf
        Sleep( 15 )
    EndDo
Return k

/*/{Protheus.doc} QFlushKeys / QWaitKey / QSleep
/*/
Static Function QFlushKeys()
    Do While Len( QInkey() ) > 0
    EndDo
Return

Static Function QWaitKey()
    QInkeyWait()
Return

Static Function QSleep( s )
    Local nEnd := Seconds() + s
    Do While Seconds() < nEnd
        QbKFill()
        If Len( cQbKBuf ) > 0
            Exit
        EndIf
        Sleep( 20 )
    EndDo
Return

/*/{Protheus.doc} QInput
    INPUT / LINE INPUT — editor de linha proprio sobre QInkey (mesmo canal
    de teclado do INKEY$, com eco e backspace).
/*/
Static Function QInput( cPrompt )
    Local cLine := "", k := Nil
    If !Empty( cPrompt )
        QbOut( cPrompt )
    EndIf
    ConOutRaw( cEsc + "[?25h" )
    Do While .T.
        k := QInkeyWait( .T. )
        Do Case
        Case k == Chr( 13 )
            Exit
        Case k == Chr( 8 )
            If Len( cLine ) > 0
                cLine := Left( cLine, Len( cLine ) - 1 )
                Do While Len( cLine ) > 0 .And. Asc( Right( cLine, 1 ) ) >= 128 .And. Asc( Right( cLine, 1 ) ) < 192
                    cLine := Left( cLine, Len( cLine ) - 1 )
                EndDo
                ConOutRaw( Chr( 8 ) + " " + Chr( 8 ) )
                nQbCol := Max( 1, nQbCol - 1 )
            EndIf
        Case Left( k, 1 ) == Chr( 0 ) .Or. Asc( k ) < 32
            // teclas especiais ignoradas
        Otherwise
            cLine += k
            QbOut( k )
        EndCase
    EndDo
    ConOutRaw( cEsc + "[?25l" )
    QbPrNL()
Return cLine

/*/{Protheus.doc} QInputList
    INPUT com varias variaveis: linha separada por virgulas.
/*/
Static Function QInputList( cPrompt, nVars )
    Local cLine := QInput( cPrompt ), a := Nil, i := Nil
    a := StrTokArr2( cLine, "," )
    For i := 1 To Len( a )
        a[i] := AllTrim( a[i] )
    Next
    Do While Len( a ) < nVars
        AAdd( a, "" )
    EndDo
Return a

// ---------------------------------------------------------------------------
// Graficos: SCREEN / PSET / POINT / LINE / CIRCLE / PAINT / GET / PUT
// ---------------------------------------------------------------------------

/*/{Protheus.doc} QbScreen
    SCREEN n — define a resolucao virtual do modo grafico.
/*/
Static Function QbScreen( n )
    n := IIf( ValType( n ) == "N", Int( n ), 0 )
    nQbMode := n
    Do Case
    Case n == 1 .Or. n == 7 .Or. n == 13
        nQbVW := 320 ; nQbVH := 200
    Case n == 2 .Or. n == 8
        nQbVW := 640 ; nQbVH := 200
    Case n == 9 .Or. n == 10
        nQbVW := 640 ; nQbVH := 350
    Case n == 11 .Or. n == 12
        nQbVW := 640 ; nQbVH := 480
    Otherwise
        nQbVW := 80 ; nQbVH := 25
    EndCase
    QbCls()
Return

/*/{Protheus.doc} QbPX / QbPY
    Coordenada virtual -> pixel fisico (1-based).
/*/
Static Function QbPX( x )
Return Int( x * QB_PW / nQbVW ) + 1
Static Function QbPY( y )
Return Int( y * QB_PH / nQbVH ) + 1

/*/{Protheus.doc} QbPSetP
    Liga pixel fisico e reemite a celula (so se a cor mudou).
/*/
Static Function QbPSetP( px, py, c )
    Local row := Nil, nTop := Nil, nBot := Nil
    If px < 1 .Or. px > QB_PW .Or. py < 1 .Or. py > QB_PH
        Return
    EndIf
    c := Int( c )
    If aQbPix[py][px] == c
        Return
    EndIf
    aQbPix[py][px] := c
    row := Int( ( py + 1 ) / 2 )
    nTop := aQbPix[ row * 2 - 1 ][px]
    nBot := aQbPix[ row * 2 ][px]
    QbAt( px, row )
    If nTop == nBot
        ConOutRaw( cEsc + "[38;5;" + QbI2S( QbAnsi( nTop ) ) + ";48;5;" + QbI2S( QbAnsi( nTop ) ) + "m█" )
    Else
        ConOutRaw( cEsc + "[38;5;" + QbI2S( QbAnsi( nTop ) ) + ";48;5;" + QbI2S( QbAnsi( nBot ) ) + "m▀" )
    EndIf
Return

/*/{Protheus.doc} QPset / QPreset / QPoint
    PSET/PRESET (x,y)[,c] e POINT(x,y) em coordenadas virtuais.
/*/
Static Function QPset( x, y, c )
    nQbLX := x
    nQbLY := y
    QbPSetP( QbPX( x ), QbPY( y ), IIf( ValType( c ) == "N", c, nQbFg ) )
Return

Static Function QPreset( x, y, c )
    QPset( x, y, IIf( ValType( c ) == "N", c, nQbBg ) )
Return

Static Function QPoint( x, y )
    Local px := QbPX( x ), py := QbPY( y )
    If px < 1 .Or. px > QB_PW .Or. py < 1 .Or. py > QB_PH
        Return -1
    EndIf
Return aQbPix[py][px]

/*/{Protheus.doc} QLine
    LINE [(x1,y1)]-(x2,y2)[,c[,B|BF]] — Bresenham na grade fisica.
/*/
Static Function QLine( x1, y1, x2, y2, c, cMode )
    Local px1 := Nil, py1 := Nil, px2 := Nil, py2 := Nil, x := Nil, y := Nil, dx := Nil, dy := Nil, sx := Nil, sy := Nil, err := Nil, e2 := Nil
    If ValType( x1 ) != "N"
        x1 := nQbLX
        y1 := nQbLY
    EndIf
    c := IIf( ValType( c ) == "N", c, nQbFg )
    cMode := Upper( AllTrim( IIf( ValType( cMode ) == "C", cMode, "" ) ) )
    nQbLX := x2
    nQbLY := y2
    px1 := QbPX( x1 ) ; py1 := QbPY( y1 )
    px2 := QbPX( x2 ) ; py2 := QbPY( y2 )
    If cMode == "BF"
        For y := Min( py1, py2 ) To Max( py1, py2 )
            For x := Min( px1, px2 ) To Max( px1, px2 )
                QbPSetP( x, y, c )
            Next
        Next
        Return
    EndIf
    If cMode == "B"
        For x := Min( px1, px2 ) To Max( px1, px2 )
            QbPSetP( x, py1, c ) ; QbPSetP( x, py2, c )
        Next
        For y := Min( py1, py2 ) To Max( py1, py2 )
            QbPSetP( px1, y, c ) ; QbPSetP( px2, y, c )
        Next
        Return
    EndIf
    dx := Abs( px2 - px1 ) ; sx := IIf( px1 < px2, 1, -1 )
    dy := Abs( py2 - py1 ) ; sy := IIf( py1 < py2, 1, -1 )
    err := dx - dy
    x := px1 ; y := py1
    Do While .T.
        QbPSetP( x, y, c )
        If x == px2 .And. y == py2
            Exit
        EndIf
        e2 := 2 * err
        If e2 > -dy ; err -= dy ; x += sx ; EndIf
        If e2 <  dx ; err += dx ; y += sy ; EndIf
    EndDo
Return

/*/{Protheus.doc} QCircle
    CIRCLE (x,y), r[, c[, inicio, fim[, aspecto]]] — arcos e elipses por
    amostragem angular em coordenadas virtuais.
/*/
Static Function QCircle( cx, cy, r, c, nA1, nA2, nAsp )
    Local rx := Nil, ry := Nil, nSteps := Nil, i := Nil, t := Nil, nPi2 := 6.283185307179586
    c := IIf( ValType( c ) == "N", c, nQbFg )
    If ValType( nAsp ) != "N" .Or. nAsp <= 0
        nAsp := ( 4 / 3 ) * nQbVH / nQbVW
    EndIf
    If nAsp < 1
        rx := r ; ry := r * nAsp
    Else
        ry := r ; rx := r / nAsp
    EndIf
    nA1 := IIf( ValType( nA1 ) == "N", Abs( nA1 ), 0 )
    nA2 := IIf( ValType( nA2 ) == "N", Abs( nA2 ), nPi2 )
    If nA2 < nA1
        nA2 += nPi2
    EndIf
    nSteps := Max( 12, Int( ( nA2 - nA1 ) * Max( rx * QB_PW / nQbVW, ry * QB_PH / nQbVH ) * 2 ) )
    For i := 0 To nSteps
        t := nA1 + ( nA2 - nA1 ) * i / nSteps
        QbPSetP( QbPX( cx + rx * Cos( t ) ), QbPY( cy - ry * Sin( t ) ), c )
    Next
    nQbLX := cx
    nQbLY := cy
Return

/*/{Protheus.doc} QPaint
    PAINT (x,y)[,cor[,borda]] — flood fill 4-conexo ate a cor de borda
    (pilha indexada: O(1) por pixel).
/*/
Static Function QPaint( x, y, c, nBord )
    Local aStk := {}, nTop := 0, px := Nil, py := Nil, k := Nil
    Local aDX := { 1, -1, 0, 0 }, aDY := { 0, 0, 1, -1 }
    c := IIf( ValType( c ) == "N", c, nQbFg )
    nBord := IIf( ValType( nBord ) == "N", nBord, c )
    AAdd( aStk, { QbPX( x ), QbPY( y ) } )
    nTop := 1
    Do While nTop > 0
        px := aStk[ nTop ][1]
        py := aStk[ nTop ][2]
        nTop -= 1
        If px >= 1 .And. px <= QB_PW .And. py >= 1 .And. py <= QB_PH .And. ;
           aQbPix[py][px] != nBord .And. aQbPix[py][px] != c
            QbPSetP( px, py, c )
            For k := 1 To 4
                nTop += 1
                If nTop > Len( aStk )
                    AAdd( aStk, { px + aDX[k], py + aDY[k] } )
                Else
                    aStk[ nTop ] := { px + aDX[k], py + aDY[k] }
                EndIf
            Next
        EndIf
    EndDo
Return

/*/{Protheus.doc} QbGet
    GET (x1,y1)-(x2,y2), arr — captura a regiao fisica: {"PHY", w, h, linhas}.
/*/
Static Function QbGet( x1, y1, x2, y2 )
    Local px1 := QbPX( Min( x1, x2 ) ), py1 := QbPY( Min( y1, y2 ) )
    Local px2 := QbPX( Max( x1, x2 ) ), py2 := QbPY( Max( y1, y2 ) )
    Local aR := { "PHY", px2 - px1 + 1, py2 - py1 + 1, {} }, x := Nil, y := Nil, aRow := Nil
    For y := py1 To py2
        aRow := {}
        For x := px1 To px2
            AAdd( aRow, IIf( x >= 1 .And. x <= QB_PW .And. y >= 1 .And. y <= QB_PH, aQbPix[y][x], 0 ) )
        Next
        AAdd( aR[4], aRow )
    Next
Return aR

/*/{Protheus.doc} QbPutOp
    Combina cor existente com a do sprite segundo o modo do PUT.
/*/
Static Function QbPutOp( nOld, nNew, cMode )
    Do Case
    Case cMode == "PSET"   ; Return nNew
    Case cMode == "PRESET" ; Return NXor( nNew, 15 )
    Case cMode == "AND"    ; Return NAnd( nOld, nNew )
    Case cMode == "OR"     ; Return NOr( nOld, nNew )
    EndCase
Return NXor( nOld, nNew )

/*/{Protheus.doc} QbDecode
    Array numerico de GET do DOS (ex.: DATA de sprites) -> {w, h, pixels}.
    Suporta EGA/VGA 4 planos (SCREEN 7-12), CGA 2bpp (1) e 8bpp (13).
/*/
Static Function QbDecode( aSrc )
    Local aB := {}, i := Nil, v := Nil, nW := Nil, nH := Nil, aPix := Nil, y := Nil, x := Nil, p := Nil, nBpr := Nil, nOff := Nil, nCol := Nil, nBit := Nil, nByte := Nil
    For i := 1 To Len( aSrc )
        v := IIf( ValType( aSrc[i] ) == "N", Int( aSrc[i] ), 0 )
        If v < 0
            v += 4294967296
        EndIf
        AAdd( aB, Mod( v, 256 ) )
        AAdd( aB, Mod( Int( v / 256 ), 256 ) )
        AAdd( aB, Mod( Int( v / 65536 ), 256 ) )
        AAdd( aB, Mod( Int( v / 16777216 ), 256 ) )
    Next
    If Len( aB ) < 4
        Return { 0, 0, {} }
    EndIf
    nW := aB[1] + aB[2] * 256
    nH := aB[3] + aB[4] * 256
    If nQbMode == 1
        nW := Int( nW / 2 )
    ElseIf nQbMode == 13
        nW := Int( nW / 8 )
    EndIf
    aPix := Array( nH )
    nOff := 5
    For y := 1 To nH
        aPix[y] := Array( nW )
        AFill( aPix[y], 0 )
        Do Case
        Case nQbMode == 13
            For x := 1 To nW
                aPix[y][x] := IIf( nOff <= Len( aB ), aB[ nOff ], 0 )
                nOff += 1
            Next
        Case nQbMode == 1
            nBpr := Int( ( nW * 2 + 7 ) / 8 )
            For x := 1 To nW
                nByte := IIf( nOff + Int( ( x - 1 ) / 4 ) <= Len( aB ), aB[ nOff + Int( ( x - 1 ) / 4 ) ], 0 )
                aPix[y][x] := Mod( Int( nByte / ( 4 ^ ( 3 - Mod( x - 1, 4 ) ) ) ), 4 )
            Next
            nOff += nBpr
        Otherwise
            nBpr := Int( ( nW + 7 ) / 8 )
            For p := 0 To 3
                For x := 1 To nW
                    nByte := IIf( nOff + Int( ( x - 1 ) / 8 ) <= Len( aB ), aB[ nOff + Int( ( x - 1 ) / 8 ) ], 0 )
                    nBit := Mod( Int( nByte / ( 2 ^ ( 7 - Mod( x - 1, 8 ) ) ) ), 2 )
                    aPix[y][x] += nBit * ( 2 ^ p )
                Next
                nOff += nBpr
            Next
        EndCase
    Next
Return { nW, nH, aPix }

/*/{Protheus.doc} QbPut
    PUT (x,y), arr[, PSET|PRESET|AND|OR|XOR] — XOR e o padrao do QBasic.
    Cada celula fisica coberta recebe UMA vez a amostra central do sprite,
    para que XOR duplo restaure o fundo mesmo com escala.
/*/
Static Function QbPut( x, y, aSpr, cMode )
    Local px0 := Nil, py0 := Nil, px1 := Nil, py1 := Nil, px := Nil, py := Nil, vx := Nil, vy := Nil, aD := Nil, nC := Nil
    If ValType( aSpr ) != "A" .Or. Len( aSpr ) == 0
        Return
    EndIf
    cMode := Upper( AllTrim( IIf( ValType( cMode ) == "C", cMode, "XOR" ) ) )
    If Empty( cMode )
        cMode := "XOR"
    EndIf
    px0 := QbPX( x )
    py0 := QbPY( y )
    If ValType( aSpr[1] ) == "C" .And. aSpr[1] == "PHY"
        For py := 1 To aSpr[3]
            For px := 1 To aSpr[2]
                If px0 + px - 1 >= 1 .And. px0 + px - 1 <= QB_PW .And. py0 + py - 1 >= 1 .And. py0 + py - 1 <= QB_PH
                    QbPSetP( px0 + px - 1, py0 + py - 1, QbPutOp( aQbPix[py0+py-1][px0+px-1], aSpr[4][py][px], cMode ) )
                EndIf
            Next
        Next
        Return
    EndIf
    aD := QbDecode( aSpr )
    If aD[1] <= 0 .Or. aD[2] <= 0
        Return
    EndIf
    px1 := QbPX( x + aD[1] - 1 )
    py1 := QbPY( y + aD[2] - 1 )
    For py := py0 To py1
        For px := px0 To px1
            vx := Int( ( px - 1 + 0.5 ) * nQbVW / QB_PW - x ) + 1
            vy := Int( ( py - 1 + 0.5 ) * nQbVH / QB_PH - y ) + 1
            vx := Max( 1, Min( aD[1], vx ) )
            vy := Max( 1, Min( aD[2], vy ) )
            If px >= 1 .And. px <= QB_PW .And. py >= 1 .And. py <= QB_PH
                nC := aD[3][vy][vx]
                QbPSetP( px, py, QbPutOp( aQbPix[py][px], nC, cMode ) )
            EndIf
        Next
    Next
Return

// ---------------------------------------------------------------------------
// Som: PLAY / SOUND / BEEP
// ---------------------------------------------------------------------------

/*/{Protheus.doc} QNoteHz
    Nota MML -> Hz. No QBasic a oitava 3 comeca no do central (O3 A = 440).
/*/
Static Function QNoteHz( cL, cAcc, nOct )
    Local aSemi := { 9, 11, 0, 2, 4, 5, 7 }   // A B C D E F G
    Local nSemi := aSemi[ At( cL, "ABCDEFG" ) ]
    If cAcc == "+" .Or. cAcc == "#"
        nSemi += 1
    ElseIf cAcc == "-"
        nSemi -= 1
    EndIf
Return 440 * ( 2 ^ ( ( nOct * 12 + nSemi - 45 ) / 12 ) )

/*/{Protheus.doc} QbNote
    Comando ffplay para uma nota (ou sleep para pausa).
/*/
Static Function QbNote( nHz, nDur )
    If nHz <= 0
        Return "sleep " + AllTrim( Str( nDur, 8, 3 ) ) + "; "
    EndIf
Return 'ffplay -nodisp -autoexit -f lavfi -i "sine=f=' + QbI2S( nHz ) + ':d=' + AllTrim( Str( nDur, 8, 3 ) ) + '" >/dev/null 2>&1; '

/*/{Protheus.doc} QPlay
    PLAY "mml" — T O L N P R < > notas A-G (+ - #), pontuado (.), prefixos
    MB/MF/MN/ML/MS. Toca tudo num unico processo de fundo.
/*/
Static Function QPlay( cMml )
    Local i := 1, cL := Nil, cAcc := Nil, cNum := Nil, nOct := 4, nLen := 4, nTempo := 120
    Local cCmd := "", nDur := Nil, nN := Nil
    If !lQbSound .Or. ValType( cMml ) != "C"
        Return
    EndIf
    cMml := Upper( StrTran( cMml, " ", "" ) )
    Do While i <= Len( cMml )
        cL := SubStr( cMml, i, 1 )
        i += 1
        If cL == "M"
            i += 1
            Loop
        EndIf
        cAcc := ""
        If cL $ "ABCDEFG" .And. i <= Len( cMml ) .And. SubStr( cMml, i, 1 ) $ "+-#"
            cAcc := SubStr( cMml, i, 1 )
            i += 1
        EndIf
        cNum := ""
        Do While i <= Len( cMml ) .And. SubStr( cMml, i, 1 ) $ "0123456789"
            cNum += SubStr( cMml, i, 1 )
            i += 1
        EndDo
        nN := Val( cNum )
        nDur := 0
        Do Case
        Case cL == "T" ; nTempo := Max( 32, nN )
        Case cL == "O" ; nOct := Max( 0, Min( 6, nN ) )
        Case cL == "L" ; nLen := Max( 1, nN )
        Case cL == "<" ; nOct := Max( 0, nOct - 1 )
        Case cL == ">" ; nOct := Min( 6, nOct + 1 )
        Case cL == "N"
            nDur := 240 / nTempo / nLen
            cCmd += QbNote( IIf( nN > 0, 440 * ( 2 ^ ( ( nN - 46 ) / 12 ) ), 0 ), nDur )
        Case cL == "P" .Or. cL == "R"
            nDur := 240 / nTempo / IIf( nN > 0, nN, nLen )
            cCmd += QbNote( 0, nDur )
        Case cL $ "ABCDEFG"
            nDur := 240 / nTempo / IIf( nN > 0, nN, nLen )
            If i <= Len( cMml ) .And. SubStr( cMml, i, 1 ) == "."
                nDur *= 1.5
                i += 1
            EndIf
            cCmd += QbNote( QNoteHz( cL, cAcc, nOct ), nDur )
        EndCase
    EndDo
    If Len( cCmd ) > 0
        ProcRun( "bash", { "-c", "nohup bash -c " + Chr( 39 ) + cCmd + Chr( 39 ) + " >/dev/null 2>&1 &" } )
    EndIf
Return

/*/{Protheus.doc} QTone
    SOUND freq, duracao — duracao em ticks do relogio (18.2 por segundo).
/*/
Static Function QTone( nHz, nTicks )
    Local nDur := nTicks / 18.2
    If !lQbSound .Or. nHz < 37 .Or. nDur < 0.03
        Return
    EndIf
    ProcRun( "bash", { "-c", "nohup " + QbNote( nHz, nDur ) + " &" } )
Return

// ---------------------------------------------------------------------------
// Arquivos: OPEN / CLOSE / PRINT # / INPUT # / EOF / FREEFILE / FIELD / GET / PUT
// aQbFiles[n] = {handle, modo, buffer, pos, recLen, ultimoRegistro} por canal
// ---------------------------------------------------------------------------

/*/{Protheus.doc} QbOpen
    OPEN "f" FOR INPUT|OUTPUT|APPEND|RANDOM|BINARY AS #n [LEN = r]
/*/
Static Function QbOpen( cName, cMode, nChan, nLen )
    Local h := -1
    nChan := IIf( ValType( nChan ) == "N", Int( nChan ), 0 )
    If nChan < 1 .Or. nChan > Len( aQbFiles )
        Throw( "QBERR: Bad file number" )
    EndIf
    cMode := Upper( AllTrim( IIf( ValType( cMode ) == "C", cMode, "INPUT" ) ) )
    Do Case
    Case cMode == "OUTPUT"
        h := FCreate( cName )
    Case cMode == "APPEND"
        h := FOpen( cName, 2 )
        If h < 0
            h := FCreate( cName )
        Else
            FSeek( h, 0, 2 )
        EndIf
    Case cMode == "INPUT"
        h := FOpen( cName, 0 )
    Otherwise
        h := FOpen( cName, 2 )
        If h < 0
            h := FCreate( cName )
        EndIf
    EndCase
    If h < 0
        Throw( "QBERR: File not found: " + cName )
    EndIf
    nLen := IIf( ValType( nLen ) == "N" .And. nLen > 0, Int( nLen ), 128 )
    aQbFiles[ nChan ] := { h, cMode, "", 0, nLen, "" }
Return .T.

/*/{Protheus.doc} QbFGet
    Valida o canal e devolve o slot aQbFiles[n] (erro "Bad file number").
/*/
Static Function QbFGet( nChan )
    nChan := Int( nChan )
    If nChan < 1 .Or. nChan > Len( aQbFiles ) .Or. ValType( aQbFiles[ nChan ] ) != "A"
        Throw( "QBERR: Bad file number" )
    EndIf
Return aQbFiles[ nChan ]

/*/{Protheus.doc} QbClose
    CLOSE [#n] — sem argumento fecha todos.
/*/
Static Function QbClose( nChan )
    Local i := Nil
    If ValType( nChan ) == "N" .And. nChan > 0
        If nChan <= Len( aQbFiles ) .And. ValType( aQbFiles[ nChan ] ) == "A"
            FClose( aQbFiles[ nChan ][1] )
            aQbFiles[ nChan ] := Nil
        EndIf
        Return
    EndIf
    For i := 1 To Len( aQbFiles )
        If ValType( aQbFiles[ i ] ) == "A"
            FClose( aQbFiles[ i ][1] )
            aQbFiles[ i ] := Nil
        EndIf
    Next
Return

Static Function QbFreeFile()
    Local i := Nil
    For i := 1 To Len( aQbFiles )
        If aQbFiles[ i ] == Nil
            Return i
        EndIf
    Next
Return 0

/*/{Protheus.doc} QbFWr
    PRINT #n, ... — escreve a linha montada (+ CRLF salvo lNl == .F.).
/*/
Static Function QbFWr( nChan, cTxt, lNl )
    Local aF := QbFGet( nChan )
    FWrite( aF[1], cTxt + IIf( lNl == .F., "", Chr( 13 ) + Chr( 10 ) ) )
    aF[4] := FSeek( aF[1], 0, 1 )
Return

/*/{Protheus.doc} QbPrStr / QbFZon / QbFTab
    Versao "string" de QbPr / QbPrZone / QbPrTab para PRINT #.
/*/
Static Function QbPrStr( x )
    Do Case
    Case ValType( x ) == "N" ; Return QStr( x ) + " "
    Case ValType( x ) == "L" ; Return QStr( IIf( x, -1, 0 ) ) + " "
    Case ValType( x ) == "C" ; Return x
    EndCase
Return ""

Static Function QbFZon( cLine )
    Local nNext := Int( Len( cLine ) / 14 ) * 14 + 15
Return Space( Max( 1, nNext - Len( cLine ) - 1 ) )

Static Function QbFTab( cLine, n )
    n := Int( n )
    If n < Len( cLine ) + 1
        Return Chr( 13 ) + Chr( 10 ) + Space( Max( 0, n - 1 ) )
    EndIf
Return Space( n - Len( cLine ) - 1 )

/*/{Protheus.doc} QbFReadLn
    Le uma linha do canal (mantem buffer por arquivo em aQbFiles[n][3]).
/*/
Static Function QbFReadLn( nChan )
    Local aF := Nil, cB := "", nP := 0
    nChan := Int( nChan )
    If nChan < 1 .Or. nChan > Len( aQbFiles ) .Or. ValType( aQbFiles[ nChan ] ) != "A"
        Return ""
    EndIf
    aF := aQbFiles[ nChan ]
    Do While .T.
        nP := At( Chr( 10 ), aF[3] )
        If nP > 0
            cB := Left( aF[3], nP - 1 )
            aF[3] := SubStr( aF[3], nP + 1 )
            Return StrTran( cB, Chr( 13 ), "" )
        EndIf
        cB := FReadStr( aF[1], 256 )
        If ValType( cB ) != "C" .Or. Len( cB ) == 0
            cB := aF[3]
            aF[3] := ""
            Return StrTran( IIf( ValType( cB ) == "C", cB, "" ), Chr( 13 ), "" )
        EndIf
        aF[3] += cB
        aF[4] := FSeek( aF[1], 0, 1 )
    EndDo
Return ""

/*/{Protheus.doc} QbFEof
    EOF(n) — preenche o buffer uma vez antes de testar.
/*/
Static Function QbFEof( nChan )
    Local aF := Nil, cB := ""
    nChan := Int( nChan )
    If nChan < 1 .Or. nChan > Len( aQbFiles ) .Or. ValType( aQbFiles[ nChan ] ) != "A"
        Return -1
    EndIf
    aF := aQbFiles[ nChan ]
    If Len( aF[3] ) == 0
        cB := FReadStr( aF[1], 256 )
        If ValType( cB ) == "C" .And. Len( cB ) > 0
            aF[3] += cB
        EndIf
    EndIf
Return IIf( Len( aF[3] ) == 0, -1, 0 )

/*/{Protheus.doc} QbInputF
    INPUT #n, v... — linha do arquivo separada por virgulas, respeitando
    strings entre aspas (virgula interna nao separa; "" = aspa literal).
/*/
Static Function QbInputF( nChan, nVars )
    Local cLine := QbFReadLn( nChan ), a := {}, i := 1, n := Len( cLine )
    Local c := Nil, cCur := "", lQ := .F.
    Do While i <= n .And. Len( a ) < nVars
        c := SubStr( cLine, i, 1 )
        Do Case
        Case lQ .And. c == '"'
            If i + 1 <= n .And. SubStr( cLine, i + 1, 1 ) == '"'
                cCur += '"' ; i += 1
            Else
                lQ := .F.
            EndIf
        Case lQ             ; cCur += c
        Case c == '"'       ; lQ := .T.
        Case c == ","       ; AAdd( a, cCur ) ; cCur := ""
        Otherwise           ; cCur += c
        EndCase
        i += 1
    EndDo
    AAdd( a, cCur )
    For i := 1 To Len( a )
        a[i] := AllTrim( a[i] )
    Next
    Do While Len( a ) < nVars
        AAdd( a, "" )
    EndDo
Return a

// ---------------------------------------------------------------------------
// Arquivos binarios: FIELD / GET / PUT / SEEK / LOF / LOC + MK$/CV$
// ---------------------------------------------------------------------------

/*/{Protheus.doc} QbFReadRec / QbFReadN
    Le um registro (recLen bytes) ou n bytes. Em RANDOM, rec = numero do
    registro (1-based); nos demais modos, rec = offset de byte (1-based).
/*/
Static Function QbFReadRec( nChan, nRec )
    Local aF := QbFGet( nChan ), cB := ""
    If ValType( nRec ) == "N" .And. nRec > 0
        If aF[2] == "RANDOM"
            FSeek( aF[1], ( Int( nRec ) - 1 ) * aF[5] )
        Else
            FSeek( aF[1], Int( nRec ) - 1 )
        EndIf
    EndIf
    cB := FReadStr( aF[1], aF[5] )
    cB := IIf( ValType( cB ) == "C", cB, "" )
    aF[4] := FSeek( aF[1], 0, 1 )
    aF[6] := cB
Return cB

Static Function QbFReadN( nChan, nLen, nRec )
    Local aF := QbFGet( nChan ), cB := ""
    If ValType( nRec ) == "N" .And. nRec > 0
        If aF[2] == "RANDOM"
            FSeek( aF[1], ( Int( nRec ) - 1 ) * aF[5] )
        Else
            FSeek( aF[1], Int( nRec ) - 1 )
        EndIf
    EndIf
    cB := FReadStr( aF[1], IIf( ValType( nLen ) == "N" .And. nLen > 0, Int( nLen ), aF[5] ) )
    cB := IIf( ValType( cB ) == "C", cB, "" )
    aF[4] := FSeek( aF[1], 0, 1 )
    aF[6] := cB
Return cB

/*/{Protheus.doc} QbFWriteRec / QbFBuff / QbFSeek
    PUT #n[, rec][, dado]; buffer do ultimo GET; SEEK #n, pos.
/*/
Static Function QbFWriteRec( nChan, nRec, cData )
    Local aF := QbFGet( nChan )
    If ValType( nRec ) == "N" .And. nRec > 0
        If aF[2] == "RANDOM"
            FSeek( aF[1], ( Int( nRec ) - 1 ) * aF[5] )
        Else
            FSeek( aF[1], Int( nRec ) - 1 )
        EndIf
    EndIf
    cData := IIf( ValType( cData ) == "C", cData, "" )
    If aF[2] == "RANDOM"
        cData := Pad( cData, aF[5] )
    EndIf
    FWrite( aF[1], cData )
    aF[4] := FSeek( aF[1], 0, 1 )
    aF[6] := cData
Return

Static Function QbFBuff( nChan )
Return QbFGet( nChan )[6]

Static Function QbFSeek( nChan, nPos )
    Local aF := QbFGet( nChan )
    nPos := Int( nPos )
    If aF[2] == "RANDOM"
        FSeek( aF[1], Max( 0, nPos - 1 ) * aF[5] )
    Else
        FSeek( aF[1], Max( 0, nPos - 1 ) )
    EndIf
    aF[4] := FSeek( aF[1], 0, 1 )
Return

/*/{Protheus.doc} QbFLof / QbFLoc / QbFPos
    LOF(n) = tamanho em bytes; LOC(n)/SEEK(n) = posicao (registro ou byte).
/*/
Static Function QbFLof( nChan )
    Local aF := QbFGet( nChan ), nPos := FSeek( aF[1], 0, 1 ), nEnd := 0
    nEnd := FSeek( aF[1], 0, 2 )
    FSeek( aF[1], nPos )
Return nEnd

Static Function QbFLoc( nChan )
    Local aF := QbFGet( nChan )
    If aF[2] == "RANDOM"
        Return Int( Max( 0, aF[4] - 1 ) / aF[5] ) + 1
    EndIf
Return aF[4] + 1

Static Function QbFPos( nChan )
Return QbFLoc( nChan )

/*/{Protheus.doc} QbKill / QbName / QbWrItem
    KILL, NAME ... AS ..., e item de WRITE (string com aspas, numero sem).
/*/
Static Function QbKill( cName )
    If FErase( cName ) != 0      // FErase: 0 = apagou, -1 = falhou
        Throw( "QBERR: File not found: " + cName )
    EndIf
Return

Static Function QbName( cOld, cNew )
    If FRename( cOld, cNew ) != 0   // FRename: 0 = renomeou, -1 = falhou
        Throw( "QBERR: File not found: " + cOld )
    EndIf
Return

Static Function QbWrItem( x )
    If ValType( x ) == "C"
        Return '"' + x + '"'
    EndIf
Return QNumStr( QbN( x ) )

/*/{Protheus.doc} MK$/CV$ — representacao binaria little-endian do QBasic.
    INTEGER=2, LONG=4, SINGLE=IEEE754-32, DOUBLE=IEEE754-64 (aproximado).
/*/
/*/{Protheus.doc} QbByte
    Byte cru n (0-255) como string de 1 byte — usa a tabela gerada em
    QbInit (Chr() codificaria UTF-8 acima de 127).
/*/
Static Function QbByte( n )
    If Len( cQbBytes ) >= 256
        Return SubStr( cQbBytes, Mod( Int( n ), 256 ) + 1, 1 )
    EndIf
Return Chr( Mod( Int( n ), 128 ) )   // fallback degradado (sem bytes crus)

Static Function QbMki( n )
    n := QCint( n )
    If n < 0 ; n += 65536 ; EndIf
Return QbByte( Mod( n, 256 ) ) + QbByte( Mod( Int( n / 256 ), 256 ) )

Static Function QbCvi( c )
    Local n := Asc( SubStr( c, 1, 1 ) ) + Asc( SubStr( c, 2, 1 ) ) * 256
Return IIf( n >= 32768, n - 65536, n )

Static Function QbCvlU( c )
Return Asc( SubStr( c, 1, 1 ) ) + Asc( SubStr( c, 2, 1 ) ) * 256 + ;
       Asc( SubStr( c, 3, 1 ) ) * 65536 + Asc( SubStr( c, 4, 1 ) ) * 16777216

Static Function QbCvl( c )
    Local n := QbCvlU( c )
Return IIf( n >= 2147483648, n - 4294967296, n )

Static Function QbMkl( n )
    n := Int( n )
    If n < 0 ; n += 4294967296 ; EndIf
Return QbByte( Mod( n, 256 ) ) + QbByte( Mod( Int( n / 256 ), 256 ) ) + ;
       QbByte( Mod( Int( n / 65536 ), 256 ) ) + QbByte( Mod( Int( n / 16777216 ), 256 ) )

Static Function QbMks( x )
    Local nS := 0, nE := 0, nM := 0, nA := 0, n := 0
    If x == 0
        Return Replicate( Chr( 0 ), 4 )
    EndIf
    nA := Abs( x )
    nS := IIf( x < 0, 1, 0 )
    nE := Int( Log( nA ) / Log( 2 ) )
    Do While nA / ( 2 ^ nE ) >= 2 ; nE += 1 ; EndDo
    Do While nA / ( 2 ^ nE ) < 1  ; nE -= 1 ; EndDo
    nM := Int( ( nA / ( 2 ^ nE ) - 1 ) * 8388608 + 0.5 )
    If nM >= 8388608 ; nM := 0 ; nE += 1 ; EndIf
    n := nS * 2147483648 + ( nE + 127 ) * 8388608 + nM
Return QbByte( Mod( n, 256 ) ) + QbByte( Mod( Int( n / 256 ), 256 ) ) + ;
       QbByte( Mod( Int( n / 65536 ), 256 ) ) + QbByte( Mod( Int( n / 16777216 ), 256 ) )

Static Function QbCvs( c )
    Local n := QbCvlU( c ), nS := Int( n / 2147483648 ), nE := Mod( Int( n / 8388608 ), 256 ), nM := Mod( n, 8388608 )
    If nE == 0 .And. nM == 0
        Return 0
    EndIf
    If nE == 255
        Return IIf( nS == 1, -1, 1 ) * 1e38
    EndIf
Return IIf( nS == 1, -1, 1 ) * ( 1 + nM / 8388608 ) * ( 2 ^ ( nE - 127 ) )

Static Function QbMkd( x )
    Local nS := 0, nE := 0, nA := 0, nM := 0, nHi := 0, nLo := 0
    If x == 0
        Return Replicate( Chr( 0 ), 8 )
    EndIf
    nA := Abs( x )
    nS := IIf( x < 0, 1, 0 )
    nE := Int( Log( nA ) / Log( 2 ) )
    Do While nA / ( 2 ^ nE ) >= 2 ; nE += 1 ; EndDo
    Do While nA / ( 2 ^ nE ) < 1  ; nE -= 1 ; EndDo
    nM := ( nA / ( 2 ^ nE ) - 1 ) * 4503599627370496
    nHi := nS * 2147483648 + ( nE + 1023 ) * 1048576 + Int( nM / 4294967296 )
    nLo := Mod( nM, 4294967296 )
Return QbMkl( nLo ) + QbMkl( nHi )

Static Function QbCvd( c )
    Local nLo := QbCvlU( Left( c, 4 ) ), nHi := QbCvlU( SubStr( c, 5, 4 ) )
    Local nS := Int( nHi / 2147483648 ), nE := Mod( Int( nHi / 1048576 ), 2048 )
    Local nM := Mod( nHi, 1048576 ) * 4294967296 + nLo
    If nE == 0 .And. nM == 0
        Return 0
    EndIf
Return IIf( nS == 1, -1, 1 ) * ( 1 + nM / 4503599627370496 ) * ( 2 ^ ( nE - 1023 ) )

/*/{Protheus.doc} QbPack / QbUnpk / QbSpecLen
    Serializacao de uma var de TYPE (array de campos) segundo a spec:
    "I","L","S","D" = numeros; {"S",n} = STRING*n; {"T",{...}} = TYPE aninhado.
/*/
Static Function QbSpecLen( aSpec )
    Local n := 0, i := Nil
    For i := 1 To Len( aSpec )
        If ValType( aSpec[i] ) == "C"
            n += IIf( aSpec[i] == "I", 2, IIf( aSpec[i] == "D", 8, 4 ) )
        ElseIf aSpec[i][1] == "S"
            n += aSpec[i][2]
        Else
            n += QbSpecLen( aSpec[i][2] )
        EndIf
    Next
Return n

Static Function QbPack1( x, sp )
    Do Case
    Case ValType( sp ) == "C" .And. sp == "I" ; Return QbMki( x )
    Case ValType( sp ) == "C" .And. sp == "L" ; Return QbMkl( x )
    Case ValType( sp ) == "C" .And. sp == "S" ; Return QbMks( x )
    Case ValType( sp ) == "C" .And. sp == "D" ; Return QbMkd( x )
    Case ValType( sp ) == "A" .And. sp[1] == "S" ; Return Pad( cValToChar( x ), sp[2] )
    Case ValType( sp ) == "A" .And. sp[1] == "T" ; Return QbPack( x, sp[2] )
    EndCase
Return ""

Static Function QbPack( xVal, aSpec )
    Local c := "", i := Nil
    If ValType( xVal ) != "A"
        Return Replicate( Chr( 0 ), QbSpecLen( aSpec ) )
    EndIf
    For i := 1 To Len( aSpec )
        c += QbPack1( IIf( i <= Len( xVal ), xVal[i], 0 ), aSpec[i] )
    Next
Return c

Static Function QbUnpk1( c, nP, sp )
    Do Case
    Case ValType( sp ) == "C" .And. sp == "I" ; Return { QbCvi( SubStr( c, nP, 2 ) ), 2 }
    Case ValType( sp ) == "C" .And. sp == "L" ; Return { QbCvl( SubStr( c, nP, 4 ) ), 4 }
    Case ValType( sp ) == "C" .And. sp == "S" ; Return { QbCvs( SubStr( c, nP, 4 ) ), 4 }
    Case ValType( sp ) == "C" .And. sp == "D" ; Return { QbCvd( SubStr( c, nP, 8 ) ), 8 }
    Case ValType( sp ) == "A" .And. sp[1] == "S" ; Return { SubStr( c, nP, sp[2] ), sp[2] }
    Case ValType( sp ) == "A" .And. sp[1] == "T" ; Return { QbUnpk( SubStr( c, nP ), sp[2] ), QbSpecLen( sp[2] ) }
    EndCase
Return { 0, 0 }

Static Function QbUnpk( cData, aSpec )
    Local a := {}, i := Nil, nP := 1, aU := Nil
    For i := 1 To Len( aSpec )
        aU := QbUnpk1( cData, nP, aSpec[i] )
        AAdd( a, aU[1] )
        nP += aU[2]
    Next
Return a

// ---------------------------------------------------------------------------
// Memoria: DEF SEG / PEEK / POKE
// ---------------------------------------------------------------------------

/*/{Protheus.doc} QDefSeg
    DEF SEG [= seg]
/*/
Static Function QDefSeg( nSeg )
    nQbSeg := IIf( ValType( nSeg ) == "N", Int( nSeg ), 0 )
Return

/*/{Protheus.doc} QPeek
    PEEK(off) — endereco = seg*16 + off. Memoria baixa (flags) ou video B800.
/*/
Static Function QPeek( nOff )
    Local nAddr := nQbSeg * 16 + Int( nOff ), nCell := Nil, row := Nil, col := Nil
    If nAddr >= 0 .And. nAddr < QB_MEMLO
        Return aQbMem[ nAddr + 1 ]
    EndIf
    If nAddr >= QB_VIDEO .And. nAddr < QB_VIDEO + 4000
        nCell := Int( ( nAddr - QB_VIDEO ) / 2 )
        row := Int( nCell / 80 ) + 1
        col := Mod( nCell, 80 ) + 1
        If row <= nQbH .And. col <= nQbW
            If Mod( nAddr - QB_VIDEO, 2 ) == 0
                Return QAsc( aQbScr[row][col][1] )
            EndIf
            Return aQbScr[row][col][2] + aQbScr[row][col][3] * 16
        EndIf
    EndIf
Return 0

/*/{Protheus.doc} QPoke
    POKE off, v — no video B800 reemite a celula alterada.
/*/
Static Function QPoke( nOff, nVal )
    Local nAddr := nQbSeg * 16 + Int( nOff ), nCell := Nil, row := Nil, col := Nil
    nVal := Int( nVal )
    If nAddr >= 0 .And. nAddr < QB_MEMLO
        aQbMem[ nAddr + 1 ] := nVal
        Return
    EndIf
    If nAddr >= QB_VIDEO .And. nAddr < QB_VIDEO + 4000
        nCell := Int( ( nAddr - QB_VIDEO ) / 2 )
        row := Int( nCell / 80 ) + 1
        col := Mod( nCell, 80 ) + 1
        If row <= nQbH .And. col <= nQbW
            If Mod( nAddr - QB_VIDEO, 2 ) == 0
                aQbScr[row][col][1] := QChr( nVal )
            Else
                aQbScr[row][col][2] := Mod( nVal, 16 )
                aQbScr[row][col][3] := Int( nVal / 16 )
            EndIf
            QbAt( col, row )
            QbCol( aQbScr[row][col][2], aQbScr[row][col][3] )
            ConOutRaw( aQbScr[row][col][1] )
            QbAt( nQbCol, nQbRow )
        EndIf
    EndIf
Return

// ---------------------------------------------------------------------------
// RUNNER — executado so quando qbasic.prg e o programa principal
// ---------------------------------------------------------------------------
#ifndef QB_LIB
#define QB_LIB
#define B2_LIB
#include "bas2prg.prg"

/*/{Protheus.doc} Main
    Runner: transpila o .bas (bas2prg) e executa o .prg gerado.
    QB_FILE=<arq.bas>  QB_ACTION=run|gen
/*/
User Function Main()
    Local cFile := QbEnv( "QB_FILE" ), cIn := "", cDst := Nil, nP := Nil, cTmp := "", nRc := Nil
    Local lTTY := UiTermWidth( 0 ) > 0
    Local cAction := Lower( AllTrim( QbEnv( "QB_ACTION" ) ) )

    If !lTTY
        cIn := MemoRead( "/dev/stdin" )
        cIn := IIf( ValType( cIn ) == "C", StrTran( cIn, Chr( 13 ), "" ), "" )
    EndIf
    If Empty( cFile )
        If lTTY
            cFile := ConIn( "Programa QBasic (.bas): " )
            cFile := IIf( ValType( cFile ) == "C", cFile, "" )
        Else
            nP := At( Chr( 10 ), cIn )
            cFile := IIf( nP > 0, Left( cIn, nP - 1 ), cIn )
            cIn := IIf( nP > 0, SubStr( cIn, nP + 1 ), "" )
        EndIf
    EndIf
    cFile := AllTrim( cFile )
    If Empty( cFile )
        ConOut( "uso: QB_FILE=programa.bas advplc run qbasic.prg  (QB_ACTION=gen so gera o .prg)" )
        Return .F.
    EndIf
    If !B2SafePath( cFile )
        ConOut( "ERRO: nome de arquivo invalido (use letras, digitos, . _ - /): " + cFile )
        Return .F.
    EndIf

    cDst := B2Transpile( cFile )
    If Empty( cDst )
        Return .F.
    EndIf
    If cAction == "gen"
        ConOut( "gerado " + cDst + " — depure com: advplc run " + cDst )
        Return .T.
    EndIf

    If lTTY
        nRc := ProcRun( "bash", { "-c", 'S=$(stty -g </dev/tty); trap : INT; advplc run "' + cDst + '" </dev/tty >/dev/tty 2>&1; stty "$S" </dev/tty' } )
    Else
        ProcRun( "mktemp", { "/tmp/qbin.XXXXXX" }, {|c| cTmp := AllTrim( c ) } )
        If Empty( cTmp )
            ConOut( "ERRO: mktemp falhou" )
            Return .F.
        EndIf
        MemoWrite( cTmp, cIn )
        nRc := ProcRun( "bash", { "-c", 'advplc run "' + cDst + '" < "' + cTmp + '" 2>&1' }, {|c| ConOut( c ) } )
        FErase( cTmp )
    EndIf
Return nRc == 0
#endif

#endif
