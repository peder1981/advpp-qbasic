/*
{Protheus.doc} nibbles.prg
    @type        source
    @author      AdvPP reconstruction
    @description Reconstrucao integral do QBasic NIBBLES.BAS (Copyright
                 Microsoft 1990) em AdvPL puro, compilado pelo AdvPP (advplc).

                 Um ou dois jogadores guiam cobras pelo campo comendo numeros.
                 Cada numero comido aumenta o placar e o comprimento da cobra;
                 bater em muro, na outra cobra ou em si mesmo custa uma vida.

    @rendering   O original simulava graficos 80x50 "pixels" em texto 80x25 com
                 chr(219)/chr(220)/chr(223). Aqui: cada "ponto" da arena vira
                 metade de uma celula — U+2580 (▀) com fg=cor do ponto de cima
                 e bg=cor do ponto de baixo (ANSI-256), equivalente ao truque
                 COLOR de fg/bg do original.
    @input       O AdvPP nao tem INKEY$ (polling de tecla nao-bloqueante).
                 Solucao: processo reader em background faz `stty -icanon -echo`
                 e `read -rsn1` no /dev/tty, despejando cada byte em
                 /tmp/nib_<pid>_key.bin; o loop do jogo consome o arquivo a
                 cada tick via FOpen/FSeek/FReadStr com offset. Setas chegam
                 como sequencia ESC [ A-D. Sem tty (pipe), o jogo roda sem
                 input e as pausas caem em ConIn (Enter). O reader se
                 auto-encerra quando some /tmp/nib_<pid>.run, quando recebe
                 TERM (via pidfile) ou quando o pid do VM morre.
    @sound       PLAY -> Tone() (bell do terminal).
*/

#define MAXSNAKE  1000   // MAXSNAKELENGTH
#define STARTOVER 1
#define SAMELEVEL 2
#define NEXTLEVEL 3

#define DIR_UP    1
#define DIR_DN    2
#define DIR_LF    3
#define DIR_RT    4

#define ARENA_R   50
#define ARENA_C   80

// arquivos de cooperacao com o reader de teclado: diretorio privado via
// mktemp -d (sem alvo previsivel para symlink em /tmp)
#define NKF      ( NTmpF( "key.bin" ) )
#define NKRUN    ( NTmpF( "nib.run" ) )
#define NKSH     ( NTmpF( "read.sh" ) )
#define NKPID    ( NTmpF( "nib.pid" ) )

/*/{Protheus.doc} NTmpF
    Caminho dentro do dir temporario privado (criado sob demanda).
/*/
Static Function NTmpF( cName )
    Local cD := ""
    If ValType( cNTmpDir ) != "C" .Or. Empty( cNTmpDir )
        cNTmpDir := ""
        ProcRun( "mktemp", { "-d", "/tmp/nib_XXXXXX" }, {|c| cD := AllTrim( c ) } )
        cNTmpDir := IIf( Empty( cD ), "/tmp/nib_" + NMYPID(), cD )
    EndIf
Return cNTmpDir + "/" + cName

/*/{Protheus.doc} Main
    Bloco principal do .bas: RANDOMIZE, Intro, GetInputs, SetColors,
    DrawScreen, loop PlayNibbles ate StillWantsToPlay = .F.
/*/
User Function Main()
    // "DIM SHARED" do original — Private = escopo dinamico descendente
    Private nW       := 80
    Private nH       := 25
    Private cEsc     := Chr( 27 )
    Private aArena   := {}     // aArena[r][c] = cor ANSI-256 do ponto
    Private aColor   := {}     // colorTable(1..6)
    Private nLevel   := 1      // curLevel
    Private nPlayers := 1
    Private nDelay   := 50     // curSpeed em ms por tick
    Private cDiff    := "N"    // diff$ (aumenta velocidade durante o jogo)
    Private cMonitor := "C"
    Private lTTY     := .F.    // terminal real? (reader de teclas possivel)
    Private nKeyOff  := 0      // offset de leitura do key-stream
    Private lQuit    := .F.    // 'Q' ou EOF -> sai com limpeza
    Private lHasKey  := .F.    // key-stream ativo
    Private cNTmpDir := ""     // dir temporario privado (mktemp -d)

    lTTY := UiTermWidth( 0 ) > 0
    If lTTY
        nW := UiTermWidth( 80 )
    EndIf

    If nW < ARENA_C
        ConOut( "Nibbles precisa de pelo menos 80 colunas de terminal." )
        Return .F.
    EndIf

    UiAltScreenEnter()
    ConOutRaw( cEsc + "[?25l" + cEsc + "[2J" )

    NIntro()
    If !lQuit
        NInputs()
    EndIf
    If !lQuit
        NSetColors()
        NDrawScreen()
        NStartKeys()

        Do While !lQuit
            NPlay()
            If lQuit
                Exit
            EndIf
            If !NStillWants()
                Exit
            EndIf
        EndDo

        NStopKeys()
    EndIf

    ConOutRaw( cEsc + "[?25h" + cEsc + "[0m" )
    UiAltScreenExit()
Return .T.

// ---------------------------------------------------------------------------
// Primitivas de tela
// ---------------------------------------------------------------------------

/*/{Protheus.doc} NI2S
    Int -> string trimada.
/*/
Static Function NI2S( n )
Return AllTrim( Str( Int( n ) ) )

/*/{Protheus.doc} NAt
    Move cursor para (x,y) — LOCATE.
/*/
Static Function NAt( x, y )
    ConOutRaw( cEsc + "[" + NI2S(y) + ";" + NI2S(x) + "H" )
Return

/*/{Protheus.doc} NPraw
    Emite celula com fg+bg sem tocar estado (transiente).
/*/
Static Function NPraw( x, y, cCh, fg, bg )
    If x < 1 .Or. y < 1 .Or. x > nW .Or. y < 1 .Or. y > nH
        Return
    EndIf
    NAt( x, y )
    ConOutRaw( cEsc + "[38;5;" + NI2S(fg) + ";48;5;" + NI2S(bg) + "m" + cCh )
Return

/*/{Protheus.doc} NTxt
    Texto puro (nao muda arena) — PRINT do original.
/*/
Static Function NTxt( x, y, cTxt, fg, bg )
    If y < 1 .Or. y > nH
        Return
    EndIf
    NAt( Max( 1, x ), y )
    ConOutRaw( cEsc + "[38;5;" + NI2S(fg) + ";48;5;" + NI2S(bg) + "m" + cTxt )
Return

/*/{Protheus.doc} NCenter
    SUB Center — centraliza na linha (base 80 do original).
/*/
Static Function NCenter( nRow, cTxt, fg, bg )
    NTxt( Int( 41 - Len( cTxt ) / 2 ), nRow, cTxt, fg, bg )
Return

/*/{Protheus.doc} NCls
    Limpa a tela (CLS).
/*/
Static Function NCls()
    ConOutRaw( cEsc + "[2J" + cEsc + "[H" )
Return

/*/{Protheus.doc} NRealR / NSister
    Mapeamentos da arenaType: realRow = INT((row+1)/2);
    sister = (row MOD 2) * 2 - 1  (linha impar -> irma abaixo/+1 = ponto de cima)
/*/
Static Function NRealR( r )
Return Int( ( r + 1 ) / 2 )
Static Function NSister( r )
Return Mod( r, 2 ) * 2 - 1

// ---------------------------------------------------------------------------
// Set / PointIsThere — coracao da renderizacao 80x50
// ---------------------------------------------------------------------------

/*/{Protheus.doc} NSet
    SUB Set — liga um "ponto" da arena e reemite a celula real correspondente
    (o par ponto+irma define o char: ▀ sempre, fg=ponto de cima, bg=de baixo).
/*/
Static Function NSet( r, c, nCol )
    Local rr, sr, nTop, nBot

    If r == 0
        Return
    EndIf
    If r < 1 .Or. r > ARENA_R .Or. c < 1 .Or. c > ARENA_C
        Return
    EndIf

    aArena[r][c] := nCol
    rr := NRealR( r )
    sr := r + NSister( r )          // irma: impar+1 (par seguinte), par-1
    nTop := aArena[ IIf( Mod( r, 2 ) == 1, r, sr ) ][c]
    nBot := aArena[ IIf( Mod( r, 2 ) == 1, sr, r ) ][c]

    If nTop == nBot
        NPraw( c, rr, "█", nTop, nTop )
    Else
        NPraw( c, rr, "▀", nTop, nBot )
    EndIf
Return

/*/{Protheus.doc} NPoint
    FUNCTION PointIsThere — .T. se o ponto nao tem a cor de fundo.
/*/
Static Function NPoint( r, c, nBg )
    If r == 0
        Return .F.
    EndIf
    If r < 1 .Or. r > ARENA_R .Or. c < 1 .Or. c > ARENA_C
        Return .T.                       // fora = parede
    EndIf
Return aArena[r][c] != nBg

// ---------------------------------------------------------------------------
// Key-stream (substituto de INKEY$)
// ---------------------------------------------------------------------------

/*/{Protheus.doc} NMYPID
    PID do processo via /proc/self/stat (para o reader se vigiar).
/*/
Static Function NMYPID()
    Local cStat := MemoRead( "/proc/self/stat" )
    Local nP    := At( " ", cStat )
    If nP > 0
        Return AllTrim( Left( cStat, nP - 1 ) )
    EndIf
Return ""

/*/{Protheus.doc} NStartKeys
    Sobe o reader de teclas em background (tty cru -> stream de bytes).
/*/
Static Function NStartKeys()
    Local cSh, h

    If !lTTY
        Return                       // sem tty: jogo roda sem input (teste/pipe)
    EndIf

    cSh := "#!/bin/bash"                                      + Chr(10) + ;
           "KFILE=" + NKF + " RFLAG=" + NKRUN + " PIDF=" + NKPID + " TTY=/dev/tty" + Chr(10) + ;
           "STATE=$(stty -F $TTY -g 2>/dev/null)"              + Chr(10) + ;
           '[ -z "$STATE" ] && exit 1'                         + Chr(10) + ;
           "stty -F $TTY -icanon -echo min 1 time 0"           + Chr(10) + ;
           ': > "$KFILE"'                                      + Chr(10) + ;
           'echo $$ > "$PIDF"'                                 + Chr(10) + ;
           "WATCH=$1"                                          + Chr(10) + ;
           'cleanup(){ stty -F $TTY "$STATE" 2>/dev/null; rm -f "$KFILE" "$RFLAG" "$PIDF"; rmdir "$(dirname "$KFILE")" 2>/dev/null; exit 0; }' + Chr(10) + ;
           "trap cleanup TERM INT"                             + Chr(10) + ;
           'while [ -f "$RFLAG" ]; do'                         + Chr(10) + ;
           '  [ -n "$WATCH" ] && ! kill -0 "$WATCH" 2>/dev/null && cleanup' + Chr(10) + ;
           "  if IFS= read -rsn1 -d '' -t 0.2 k < $TTY 2>/dev/null; then" + Chr(10) + ;
           "    printf '%s' " + Chr(34) + "$k" + Chr(34) + " >> " + Chr(34) + "$KFILE" + Chr(34) + Chr(10) + ;
           "  fi"                                              + Chr(10) + ;
           "done"                                              + Chr(10) + ;
           "cleanup"                                           + Chr(10)

    MemoWrite( NKSH, cSh )
    MemoWrite( NKRUN, "1" )
    ProcRun( "bash", { "-c", "nohup bash " + NKSH + " " + NMYPID() + " </dev/null >/dev/null 2>&1 &" } )
    Sleep( 150 )
    nKeyOff := 0
    // reader subiu de fato? (KFILE so e criado se o stty funcionou)
    h := FOpen( NKF )
    If h >= 0
        FClose( h )
        lHasKey := .T.
    Else
        lHasKey := .F.
        FErase( NKSH )
        FErase( NKRUN )
    EndIf
Return

/*/{Protheus.doc} NStopKeys
    Remove a flag e manda TERM para o pid do reader (pidfile); o proprio
    reader restaura o tty via trap. stty sane fica como fallback.
/*/
Static Function NStopKeys()
    Local cPid := "", i := 0, lDig := .F.
    FErase( NKRUN )
    If lHasKey
        cPid := MemoRead( NKPID )
        cPid := IIf( ValType( cPid ) == "C", AllTrim( cPid ), "" )
        lDig := !Empty( cPid ) .And. Len( cPid ) <= 8
        For i := 1 To Len( cPid )
            If !( SubStr( cPid, i, 1 ) $ "0123456789" )
                lDig := .F.
            EndIf
        Next
        If lDig
            ProcRun( "bash", { "-c", "kill " + cPid + " 2>/dev/null; true" } )
        EndIf
        Sleep( 300 )
        ProcRun( "bash", { "-c", "stty -F /dev/tty sane 2>/dev/null; rm -f " + NKPID + "; true" } )
        lHasKey := .F.
    EndIf
Return

/*/{Protheus.doc} NKeys
    Le os bytes novos do stream e traduz em tokens:
    setas (ESC [ A-D) -> "UP"/"DN"/"LF"/"RT"; resto -> o proprio char.
/*/
Static Function NKeys()
    Local h, cBuf, i, cB, cB2, cB3
    Local aTok := {}

    If !lHasKey
        Return aTok
    EndIf
    h := FOpen( NKF )
    If h < 0
        Return aTok
    EndIf
    FSeek( h, nKeyOff )
    cBuf := FReadStr( h, 512 )
    FClose( h )
    nKeyOff += Len( cBuf )

    // nao consumir sequencia de escape cortada no fim do buffer
    If Len( cBuf ) >= 1 .And. Right( cBuf, 1 ) == cEsc
        cBuf := Left( cBuf, Len( cBuf ) - 1 )
        nKeyOff -= 1
    EndIf
    If Len( cBuf ) >= 2 .And. SubStr( cBuf, Len( cBuf ) - 1, 2 ) == cEsc + "["
        cBuf := Left( cBuf, Len( cBuf ) - 2 )
        nKeyOff -= 2
    EndIf

    i := 1
    Do While i <= Len( cBuf )
        cB := SubStr( cBuf, i, 1 )
        If cB == cEsc .And. i + 2 <= Len( cBuf )
            cB2 := SubStr( cBuf, i + 1, 1 )
            cB3 := SubStr( cBuf, i + 2, 1 )
            If cB2 == "["
                Do Case
                Case cB3 == "A" ; AAdd( aTok, "UP" )
                Case cB3 == "B" ; AAdd( aTok, "DN" )
                Case cB3 == "C" ; AAdd( aTok, "RT" )
                Case cB3 == "D" ; AAdd( aTok, "LF" )
                EndCase
                i += 3
                Loop
            EndIf
        EndIf
        AAdd( aTok, cB )
        i += 1
    EndDo
Return aTok

/*/{Protheus.doc} NKFlush
    Descarta input pendente (WHILE INKEY$ <> "": WEND do original).
/*/
Static Function NKFlush()
    Local a := NKeys()
Return

/*/{Protheus.doc} NKWait
    Espera um token da lista aKeys pelo stream (ou ConIn fora de tty).
    Retorna o token recebido; "" em EOF/quit.
/*/
Static Function NKWait( aKeys )
    Local aTok, k, cIn

    If !lHasKey
        cIn := ConIn( "" )
        If IsNil( cIn )
            lQuit := .T.
            Return ""
        EndIf
        cIn := Upper( Left( AllTrim( cIn ), 1 ) )
        If Empty( cIn )
            cIn := " "
        EndIf
        Return cIn
    EndIf

    Do While .T.
        aTok := NKeys()
        For k := 1 To Len( aTok )
            If Upper( aTok[k] ) == "Q"
                lQuit := .T.
                Return "Q"
            EndIf
            If aTok[k] == Chr(13) .Or. aTok[k] == Chr(10)
                Return " "
            EndIf
            If aKeys == Nil .Or. AScan( aKeys, Upper( aTok[k] ) ) > 0
                Return Upper( aTok[k] )
            EndIf
        Next
        Sleep( 30 )
    EndDo
Return ""

// ---------------------------------------------------------------------------
// Telas
// ---------------------------------------------------------------------------

/*/{Protheus.doc} NSparkle
    SparklePause — borda animada por ciclos fixos + Enter (ou stream).
/*/
Static Function NSparkle()
    Local a, b, i
    Local cPat := "*    *    *    *    *    *    *    *    *    *    *    *    *    *    *    *    *    "

    For i := 1 To 3
        For a := 1 To 5
            NTxt( 1, 1,  SubStr( cPat, a,     Min( Len( cPat ) - a + 1, ARENA_C ) ), 196, 0 )
            NTxt( 1, 22, SubStr( cPat, 6 - a, Min( Len( cPat ) - 5 + a, ARENA_C ) ), 196, 0 )
            For b := 2 To 21
                If Mod( a + b, 5 ) == 1
                    NTxt( 80, b, "*", 196, 0 )
                    NTxt( 1, 23 - b, "*", 196, 0 )
                Else
                    NTxt( 80, b, " ", 196, 0 )
                    NTxt( 1, 23 - b, " ", 196, 0 )
                EndIf
            Next
            Sleep( 60 )
        Next
    Next
    NKWait( Nil )                    // qualquer tecla continua
Return

/*/{Protheus.doc} NIntro
    SUB Intro — tela de abertura com tabela de controles.
/*/
Static Function NIntro()
    NCls()
    NCenter( 4,  "Q B a s i c   N i b b l e s", 231, 0 )
    NCenter( 6,  "Copyright (C) Microsoft Corporation 1990", 250, 0 )
    NCenter( 8,  "Nibbles is a game for one or two players.  Navigate your snakes", 250, 0 )
    NCenter( 9,  "around the game board trying to eat up numbers while avoiding", 250, 0 )
    NCenter( 10, "running into walls or other snakes.  The more numbers you eat up,", 250, 0 )
    NCenter( 11, "the more points you gain and the longer your snake becomes.", 250, 0 )
    NCenter( 13, " Game Controls ", 220, 0 )
    NCenter( 15, "  General             Player 1               Player 2    ", 250, 0 )
    NCenter( 16, "                        (Up)                   (Up)      ", 250, 0 )
    NCenter( 17, "P - Pause Q - Quit    " + Chr(24) + "                      W       ", 250, 0 )
    NCenter( 18, "                     (Left) " + Chr(27) + "   " + Chr(26) + " (Right)   (Left) A   D (Right)  ", 250, 0 )
    NCenter( 19, "                         " + Chr(25) + "                      S       ", 250, 0 )
    NCenter( 20, "                       (Down)                 (Down)     ", 250, 0 )
    NCenter( 24, "Pressione Enter para continuar", 231, 0 )
    NSparkle()
Return

/*/{Protheus.doc} NInputs
    SUB GetInputs — jogadores, skill, aceleracao, monitor + speed convertida
    para ms por tick (o benchmark FOR/NEXT do original vira Sleep).
/*/
Static Function NInputs()
    Local cIn, nVal, nSkill

    NCls()
    Do While .T.
        ConOutRaw( cEsc + "[?25h" )
        NAt( 20, 5 )
        cIn := ConIn( "Quantos jogadores (1 ou 2)? " )
        If IsNil( cIn ) ; lQuit := .T. ; Return ; EndIf
        nVal := Int( Val( AllTrim( cIn ) ) )
        If nVal == 1 .Or. nVal == 2
            nPlayers := nVal
            Exit
        EndIf
    EndDo

    NTxt( 21, 8,  "Nivel de habilidade (1 a 100)", 250, 0 )
    NTxt( 22, 9,  "1   = Novice", 250, 0 )
    NTxt( 22, 10, "90  = Expert", 250, 0 )
    NTxt( 22, 11, "100 = Twiddle Fingers", 250, 0 )
    NTxt( 15, 12, "(a velocidade do computador pode afetar seu nivel)", 250, 0 )
    Do While .T.
        NTxt( 43, 8, Space( 36 ), 250, 0 )
        NAt( 43, 8 )
        cIn := ConIn( "" )
        If IsNil( cIn ) ; lQuit := .T. ; Return ; EndIf
        nSkill := Int( Val( AllTrim( cIn ) ) )
        If nSkill >= 1 .And. nSkill <= 100
            Exit
        EndIf
    EndDo

    // speed = (100 - speed) * 2 + 1 do original; cada unidade ~0.5 ms
    nDelay := Max( 1, Int( ( ( 100 - nSkill ) * 2 + 1 ) / 2 ) )

    Do While .T.
        NAt( 15, 15 )
        cIn := ConIn( "Aumentar velocidade durante o jogo (Y ou N)? " )
        If IsNil( cIn ) ; lQuit := .T. ; Return ; EndIf
        cDiff := Upper( Left( AllTrim( cIn ), 1 ) )
        If cDiff $ "YN"
            Exit
        EndIf
    EndDo

    Do While .T.
        NAt( 17, 17 )
        cIn := ConIn( "Monitor monocromatico ou colorido (M ou C)? " )
        If IsNil( cIn ) ; lQuit := .T. ; Return ; EndIf
        cMonitor := Upper( Left( AllTrim( cIn ), 1 ) )
        If cMonitor $ "MC"
            Exit
        EndIf
    EndDo
    ConOutRaw( cEsc + "[?25l" )
Return

/*/{Protheus.doc} NSetColors
    GOSUB SetColors — colorTable: snake1, snake2, walls, bg, dlgFg, dlgBg.
/*/
Static Function NSetColors()
    If cMonitor == "M"
        aColor := { 231, 250, 250, 16, 255, 16 }
    Else
        aColor := { 226, 213, 196, 17, 231, 52 }
    EndIf
Return

/*/{Protheus.doc} NDrawScreen
    SUB DrawScreen — moldura + aloca a arena.
/*/
Static Function NDrawScreen()
    Local r, c
    NCls()
    NCenter( 1,  "Nibbles!", 226, 0 )
    NCenter( 11, "Initializing Playing Field...", 250, 0 )
    aArena := Array( ARENA_R )
    For r := 1 To ARENA_R
        aArena[r] := Array( ARENA_C )
        For c := 1 To ARENA_C
            aArena[r][c] := aColor[4]
        Next
    Next
Return

/*/{Protheus.doc} NInitColors
    SUB InitColors — fundo + borda do campo (Set em toda a moldura).
/*/
Static Function NInitColors()
    Local r, c

    For r := 1 To ARENA_R
        For c := 1 To ARENA_C
            aArena[r][c] := aColor[4]
        Next
    Next
    NCls()

    For c := 1 To ARENA_C
        NSet( 3,  c, aColor[3] )
        NSet( 50, c, aColor[3] )
    Next
    For r := 4 To 49
        NSet( r, 1,  aColor[3] )
        NSet( r, 80, aColor[3] )
    Next
Return

/*/{Protheus.doc} NEraseSnake
    SUB EraseSnake — apaga a cobra "de um jeito muito legal":
    10 segmentos por vez, de tras para frente.
    aBody[b][p] = {row,col} (buffer circular), aSam[i] = snaketype-array.
/*/
Static Function NEraseSnake( aSam, aBody, nSnake )
    Local b, c, nTail
    For c := 0 To 9
        For b := aSam[nSnake][2] - c To 0 Step -10
            nTail := Mod( aSam[nSnake][1] + MAXSNAKE - b, MAXSNAKE ) + 1
            NSet( aBody[nTail][nSnake][1], aBody[nTail][nSnake][2], aColor[4] )
        Next
    Next
Return

/*/{Protheus.doc} NScore
    SUB PrintScore — linha 1: JAKE a esquerda (se 2 jog), SAMMY a direita.
/*/
Static Function NScore( aSam )
    If nPlayers == 2
        NTxt( 1, 1, Pad( NI2S( aSam[2][6] ), 9 ) + "  Lives: " + NI2S( aSam[2][5] ) + "  <--JAKE", 231, aColor[4] )
    EndIf
    NTxt( 49, 1, "SAMMY-->  Lives: " + NI2S( aSam[1][5] ) + "     " + PadL( NI2S( aSam[1][6] ), 9 ), 231, aColor[4] )
Return

/*/{Protheus.doc} NBox
    Caixa de dialogo do SpacePause/Game Over (moldura de '█' como o original).
/*/
Static Function NBox( aLines )
    Local i
    Local nW0 := 33
    Local x0  := Int( ( ARENA_C - nW0 ) / 2 )
    Local y0  := 10

    For i := 0 To Len( aLines ) + 1
        If i == 0 .Or. i == Len( aLines ) + 1
            NTxt( x0, y0 + i, Replicate( "█", nW0 ), aColor[5], aColor[6] )
        Else
            NTxt( x0, y0 + i, "█" + Pad( aLines[i], nW0 - 2 ) + "█", aColor[5], aColor[6] )
        EndIf
    Next
Return

/*/{Protheus.doc} NUnBox
    Restaura a regiao da caixa repintando os pontos da arena.
/*/
Static Function NUnBox()
    Local i, j
    For i := 20 To 28
        For j := 22 To 58
            NSet( i, j, aArena[i][j] )
        Next
    Next
Return

/*/{Protheus.doc} NSpacePause
    SUB SpacePause — caixa + espera de espaco/Enter no stream (Enter fora tty).
/*/
Static Function NSpacePause( cTxt )
    NKFlush()
    NBox( { " " + Pad( cTxt, 29 ) } )
    NKWait( { " " } )
    NUnBox()
Return

/*/{Protheus.doc} NStillWants
    FUNCTION StillWantsToPlay — GAME OVER + Play Again (Y/N -> Y/S sim).
/*/
Static Function NStillWants()
    Local k
    NKFlush()
    NBox( { "      G A M E   O V E R      ", ;
            "                             ", ;
            "      Play Again?   (Y/N)    " } )
    k := NKWait( { "Y", "S", "N", "Q" } )
    NUnBox()
Return k == "Y" .Or. k == "S"

// ---------------------------------------------------------------------------
// Niveis
// ---------------------------------------------------------------------------

/*/{Protheus.doc} NLevel
    SUB Level — STARTOVER/NEXTLEVEL/SAMELEVEL + os 10 layouts de muro,
    todos portados literalmente (incluindo posicoes e direcoes iniciais).
/*/
Static Function NLevel( nWhat, aSam )
    Local i

    Do Case
    Case nWhat == STARTOVER
        nLevel := 1
    Case nWhat == NEXTLEVEL
        nLevel += 1
    EndCase

    // initialize snakes
    aSam[1][1] := 1
    aSam[1][2] := 2
    aSam[1][8] := .T.
    aSam[2][1] := 1
    aSam[2][2] := 2
    aSam[2][8] := .T.

    NInitColors()

    Do Case
    Case nLevel == 1
        aSam[1][3] := 25 ; aSam[2][3] := 25
        aSam[1][4] := 50 ; aSam[2][4] := 30
        aSam[1][7] := DIR_RT ; aSam[2][7] := DIR_LF

    Case nLevel == 2
        For i := 20 To 60
            NSet( 25, i, aColor[3] )
        Next
        aSam[1][3] := 7  ; aSam[2][3] := 43
        aSam[1][4] := 60 ; aSam[2][4] := 20
        aSam[1][7] := DIR_LF ; aSam[2][7] := DIR_RT

    Case nLevel == 3
        For i := 10 To 40
            NSet( i, 20, aColor[3] )
            NSet( i, 60, aColor[3] )
        Next
        aSam[1][3] := 25 ; aSam[2][3] := 25
        aSam[1][4] := 50 ; aSam[2][4] := 30
        aSam[1][7] := DIR_UP ; aSam[2][7] := DIR_DN

    Case nLevel == 4
        For i := 4 To 30
            NSet( i, 20, aColor[3] )
            NSet( 53 - i, 60, aColor[3] )
        Next
        For i := 2 To 40
            NSet( 38, i, aColor[3] )
            NSet( 15, 81 - i, aColor[3] )
        Next
        aSam[1][3] := 7  ; aSam[2][3] := 43
        aSam[1][4] := 60 ; aSam[2][4] := 20
        aSam[1][7] := DIR_LF ; aSam[2][7] := DIR_RT

    Case nLevel == 5
        For i := 13 To 39
            NSet( i, 21, aColor[3] )
            NSet( i, 59, aColor[3] )
        Next
        For i := 23 To 57
            NSet( 11, i, aColor[3] )
            NSet( 41, i, aColor[3] )
        Next
        aSam[1][3] := 25 ; aSam[2][3] := 25
        aSam[1][4] := 50 ; aSam[2][4] := 30
        aSam[1][7] := DIR_UP ; aSam[2][7] := DIR_DN

    Case nLevel == 6
        For i := 4 To 49
            If i > 30 .Or. i < 23
                NSet( i, 10, aColor[3] )
                NSet( i, 20, aColor[3] )
                NSet( i, 30, aColor[3] )
                NSet( i, 40, aColor[3] )
                NSet( i, 50, aColor[3] )
                NSet( i, 60, aColor[3] )
                NSet( i, 70, aColor[3] )
            EndIf
        Next
        aSam[1][3] := 7  ; aSam[2][3] := 43
        aSam[1][4] := 65 ; aSam[2][4] := 15
        aSam[1][7] := DIR_DN ; aSam[2][7] := DIR_UP

    Case nLevel == 7
        For i := 4 To 49 Step 2
            NSet( i, 40, aColor[3] )
        Next
        aSam[1][3] := 7  ; aSam[2][3] := 43
        aSam[1][4] := 65 ; aSam[2][4] := 15
        aSam[1][7] := DIR_DN ; aSam[2][7] := DIR_UP

    Case nLevel == 8
        For i := 4 To 40
            NSet( i, 10, aColor[3] )
            NSet( 53 - i, 20, aColor[3] )
            NSet( i, 30, aColor[3] )
            NSet( 53 - i, 40, aColor[3] )
            NSet( i, 50, aColor[3] )
            NSet( 53 - i, 60, aColor[3] )
            NSet( i, 70, aColor[3] )
        Next
        aSam[1][3] := 7  ; aSam[2][3] := 43
        aSam[1][4] := 65 ; aSam[2][4] := 15
        aSam[1][7] := DIR_DN ; aSam[2][7] := DIR_UP

    Case nLevel == 9
        For i := 6 To 47
            NSet( i, i, aColor[3] )
            NSet( i, i + 28, aColor[3] )
        Next
        aSam[1][3] := 40 ; aSam[2][3] := 15
        aSam[1][4] := 75 ; aSam[2][4] := 5
        aSam[1][7] := DIR_UP ; aSam[2][7] := DIR_DN

    Otherwise
        For i := 4 To 49 Step 2
            NSet( i,     10, aColor[3] )
            NSet( i + 1, 20, aColor[3] )
            NSet( i,     30, aColor[3] )
            NSet( i + 1, 40, aColor[3] )
            NSet( i,     50, aColor[3] )
            NSet( i + 1, 60, aColor[3] )
            NSet( i,     70, aColor[3] )
        Next
        aSam[1][3] := 7  ; aSam[2][3] := 43
        aSam[1][4] := 65 ; aSam[2][4] := 15
        aSam[1][7] := DIR_DN ; aSam[2][7] := DIR_UP
    EndCase
Return

// ---------------------------------------------------------------------------
// Loop principal do jogo
// ---------------------------------------------------------------------------

/*/{Protheus.doc} NPlay
    SUB PlayNibbles — loop de uma partida completa (ate zerar as vidas).
    aSam[i] = {head,length,row,col,lives,score,direction,alive,scolor}
    aBody[b][i] = {row,col} do anel circular (snakeBody do original).
/*/
Static Function NPlay()
    Local aBody := {}
    Local aSam  := {}
    Local a, b, i, k, nTail
    Local lGameOver, lDied, lNoNum
    Local nNum, nNumR, nNumC, nNumRR, nSisR
    Local aTok, cK

    // DIM sammyBody(MAXSNAKELENGTH - 1, 1 TO 2)
    aBody := Array( MAXSNAKE )
    For b := 1 To MAXSNAKE
        aBody[b] := { { 0, 0 }, { 0, 0 } }
    Next

    // snaketype: head length row col lives score direction alive scolor
    aSam := { { 1, 2, 0, 0, 5, 0, DIR_RT, .T., aColor[1] }, ;
              { 1, 2, 0, 0, 5, 0, DIR_LF, .T., aColor[2] } }

    NLevel( STARTOVER, aSam )

    lGameOver := .F.
    Do While !lGameOver .And. !lQuit
        If nPlayers == 1
            aSam[2][3] := 0
        EndIf

        nNum   := 1
        lNoNum := .T.
        nNumRR := 0
        nNumC  := 0

        lDied := .F.
        NScore( aSam )
        Tone()
        NSpacePause( "     Level" + Str( nLevel, 3 ) + ",  Push Space" )
        If lQuit
            Exit
        EndIf

        Do While !lDied .And. !lQuit
            // sorteia o numero se nao houver um no campo
            If lNoNum
                Do While .T.
                    nNumR := Int( Randomize( 0, 47 ) ) + 3
                    nNumC := Int( Randomize( 0, 78 ) ) + 2
                    nSisR := nNumR + NSister( nNumR )
                    If !NPoint( nNumR, nNumC, aColor[4] ) .And. !NPoint( nSisR, nNumC, aColor[4] )
                        Exit
                    EndIf
                EndDo
                nNumRR := NRealR( nNumR )
                lNoNum := .F.
                NTxt( nNumC, nNumRR, Right( Str( nNum ), 1 ), aColor[1], aColor[4] )
            EndIf

            // 'Delay game' — FOR a# = 1 TO curSpeed do original vira Sleep
            Sleep( nDelay )

            // INKEY$ -> tokens do stream
            aTok := NKeys()
            For k := 1 To Len( aTok )
                cK := aTok[k]
                Do Case
                Case cK == "W" .Or. cK == "w"
                    If aSam[2][7] != DIR_DN ; aSam[2][7] := DIR_UP ; EndIf
                Case cK == "S" .Or. cK == "s"
                    If aSam[2][7] != DIR_UP ; aSam[2][7] := DIR_DN ; EndIf
                Case cK == "A" .Or. cK == "a"
                    If aSam[2][7] != DIR_RT ; aSam[2][7] := DIR_LF ; EndIf
                Case cK == "D" .Or. cK == "d"
                    If aSam[2][7] != DIR_LF ; aSam[2][7] := DIR_RT ; EndIf
                Case cK == "UP"
                    If aSam[1][7] != DIR_DN ; aSam[1][7] := DIR_UP ; EndIf
                Case cK == "DN"
                    If aSam[1][7] != DIR_UP ; aSam[1][7] := DIR_DN ; EndIf
                Case cK == "LF"
                    If aSam[1][7] != DIR_RT ; aSam[1][7] := DIR_LF ; EndIf
                Case cK == "RT"
                    If aSam[1][7] != DIR_LF ; aSam[1][7] := DIR_RT ; EndIf
                Case cK == "P" .Or. cK == "p"
                    NSpacePause( " Game Paused ... Push Space  " )
                Case cK == "Q" .Or. cK == "q"
                    lQuit := .T.
                EndCase
            Next
            If lQuit
                Exit
            EndIf

            // move as cobras
            For a := 1 To nPlayers
                Do Case
                Case aSam[a][7] == DIR_UP ; aSam[a][3] -= 1
                Case aSam[a][7] == DIR_DN ; aSam[a][3] += 1
                Case aSam[a][7] == DIR_LF ; aSam[a][4] -= 1
                Case aSam[a][7] == DIR_RT ; aSam[a][4] += 1
                EndCase

                // comeu o numero?
                If nNumRR == Int( ( aSam[a][3] + 1 ) / 2 ) .And. nNumC == aSam[a][4]
                    Tone()
                    If aSam[a][2] < MAXSNAKE - 30
                        aSam[a][2] += nNum * 4
                    EndIf
                    aSam[a][6] += nNum
                    NScore( aSam )
                    nNum += 1
                    If nNum == 10
                        NEraseSnake( aSam, aBody, 1 )
                        NEraseSnake( aSam, aBody, 2 )
                        NLevel( NEXTLEVEL, aSam )
                        NScore( aSam )
                        NSpacePause( "     Level" + Str( nLevel, 3 ) + ",  Push Space" )
                        If nPlayers == 1
                            aSam[2][3] := 0
                        EndIf
                        nNum := 1
                        If cDiff == "P"          // dead code do original
                            nDelay -= 10
                        EndIf
                    EndIf
                    lNoNum := .T.
                    If nDelay < 1
                        nDelay := 1
                    EndIf
                EndIf
            Next

            // colisao e desenho
            For a := 1 To nPlayers
                If NPoint( aSam[a][3], aSam[a][4], aColor[4] ) ;
                   .Or. ( aSam[1][3] == aSam[2][3] .And. aSam[1][4] == aSam[2][4] )
                    Tone()
                    lDied := .T.
                    aSam[a][8] := .F.
                    aSam[a][5] -= 1
                Else
                    aSam[a][1] := Mod( aSam[a][1], MAXSNAKE ) + 1
                    aBody[ aSam[a][1] ][a] := { aSam[a][3], aSam[a][4] }
                    nTail := Mod( aSam[a][1] + MAXSNAKE - aSam[a][2], MAXSNAKE ) + 1
                    NSet( aBody[nTail][a][1], aBody[nTail][a][2], aColor[4] )
                    aBody[nTail][a] := { 0, 0 }
                    NSet( aSam[a][3], aSam[a][4], aSam[a][9] )
                EndIf
            Next
        EndDo

        If lQuit
            Exit
        EndIf

        // morreu alguem nesta rodada?
        For a := 1 To nPlayers
            NEraseSnake( aSam, aBody, a )
            If !aSam[a][8]
                aSam[a][6] -= 10
                NScore( aSam )
                If a == 1
                    NSpacePause( " Sammy Dies! Push Space! --->" )
                Else
                    NSpacePause( " <---- Jake Dies! Push Space " )
                EndIf
            EndIf
        Next
        If lQuit
            Exit
        EndIf

        NLevel( SAMELEVEL, aSam )
        NScore( aSam )

        lGameOver := aSam[1][5] <= 0 .Or. aSam[2][5] <= 0
    EndDo
Return
