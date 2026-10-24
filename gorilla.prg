/*
{Protheus.doc} gorilla.prg
    @type        source
    @author      AdvPP reconstruction
    @description Reconstrucao integral do QBasic GORILLAS.BAS (Copyright IBM 1991)
                 em AdvPL puro, compilado pelo AdvPP (advplc).

                 Dois gorilas sobre os predios de uma cidade se enfrentam
                 arremessando bananas explosivas. O jogador informa angulo e
                 velocidade; o arremesso e afetado por vento e gravidade.

    @rendering   Terminal ANSI em tela alternativa (UiAltScreenEnter). Cada
                 celula de texto equivale a um "pixel" do original; a grade
                 material (aMat) substitui o POINT() do QBasic para colisao.
    @physics     Espaco virtual 640x350 identico ao modo EGA do original;
                 formulas de trajetoria preservadas literalmente.
    @input       ConIn() substitui INPUT/INKEY$ (o AdvPP nao expoe polling
                 de tecla nao-bloqueante). Enter confirma cada valor.
    @sound       PLAY -> Tone() (bell do terminal).
*/

// Materiais da grade de colisao
#define MAT_SKY    0
#define MAT_BUILD  1
#define MAT_SUN    3
#define MAT_GOR    10        // gorila do jogador i = MAT_GOR + i

// Cores ANSI-256
#define COL_SKY    17        // fundo azul escuro
#define COL_TXT    231       // texto branco
#define COL_TITLE  220       // titulo amarelo
#define COL_SUN    226       // sol amarelo vivo
#define COL_GOR    130       // gorila marrom
#define COL_BAN    220       // banana
#define COL_EX1    196       // explosao vermelha
#define COL_EX2    208       // explosao laranja
#define COL_WINL   227       // janela acesa
#define COL_WIND   240       // janela apagada
#define COL_ARROW  46        // seta de vento

#define GOR_W      9
#define GOR_H      5
#define SPI        3.14159265
#define NSTEPS     0.1       // passo de tempo da trajetoria (como no original)

/*/{Protheus.doc} Main
    Ponto de entrada. Equivale ao bloco principal do .bas:
    InitVars -> Intro -> loop (GetInputs -> GorillaIntro -> PlayGame -> again?)
/*/
User Function Main()
    // "DIM SHARED" do original: Private = escopo dinamico descendente
    Private nW      := 120          // largura em colunas do terminal
    Private nH      := 40           // altura em linhas do terminal
    Private aMat    := {}           // grade de material (colisao)
    Private aScr    := {}           // grade renderizada (celula -> {char, fg})
    Private aGor    := {{0,0},{0,0}}// {col,linha} topo-esq de cada gorila
    Private aBld    := {}           // predios: {xIni, largura, yTopo}
    Private aWins   := {0,0}        // TotalWins(1..2)
    Private nWind   := 0            // Wind
    Private nGrav   := 9.8          // gravity#
    Private cP1     := "Player 1"
    Private cP2     := "Player 2"
    Private nGames  := 3            // NumGames
    Private cEsc    := Chr(27)
    Private lQuit   := .F.          // EOF no stdin -> encerra com limpeza
    Private lSunHit := .F.          // SunHit

    Local lAgain := .F.

    GTermSize()
    GScrInit()

    UiAltScreenEnter()
    ConOutRaw(cEsc + "[?25l" + cEsc + "[2J")

    GIntro()
    Do While !lQuit
        GInputs()
        If lQuit
            Exit
        EndIf
        GGorIntro()
        If lQuit
            Exit
        EndIf
        GPlay()
        If lQuit
            Exit
        EndIf
        lAgain := GAgain()
        If lQuit .Or. !lAgain
            Exit
        EndIf
    EndDo

    ConOutRaw(cEsc + "[?25h" + cEsc + "[0m")
    UiAltScreenExit()
Return .T.

// ---------------------------------------------------------------------------
// Primitivas de tela
// ---------------------------------------------------------------------------

/*/{Protheus.doc} GI2S
    Int -> string trimada (auxiliar para sequencias ANSI).
/*/
Static Function GI2S( n )
Return AllTrim( Str( Int( n ) ) )

/*/{Protheus.doc} GTermSize
    Detecta tamanho do terminal: largura via UiTermWidth, altura via
    `tput lines` (ProcRun). Defaults 120x40.
/*/
Static Function GTermSize()
    Local cLines := ""
    Local nHgt   := 0

    nW := UiTermWidth( 120 )
    If ProcRun( "tput", { "lines" }, {|cL| cLines := cL } ) == 0
        nHgt := Int( Val( AllTrim( cLines ) ) )
    EndIf
    If nHgt <= 0
        nHgt := 40
    EndIf
    nH := nHgt
    nW := Max( 60, Min( 200, nW ) )
    nH := Max( 28, Min( 60,  nH ) )
Return

/*/{Protheus.doc} GScrInit
    Aloca as grades aMat/aScr zeradas (ceu).
/*/
Static Function GScrInit()
    Local i, j
    aMat := Array( nH )
    aScr := Array( nH )
    For i := 1 To nH
        aMat[i] := Array( nW )
        aScr[i] := Array( nW )
        For j := 1 To nW
            aMat[i][j] := MAT_SKY
            aScr[i][j] := { " ", COL_SKY }
        Next
    Next
Return

/*/{Protheus.doc} GAt
    Move o cursor para (x,y) — LOCATE do QBasic.
/*/
Static Function GAt( x, y )
    ConOutRaw( cEsc + "[" + GI2S(y) + ";" + GI2S(x) + "H" )
Return

/*/{Protheus.doc} GCol
    Emite codigo de cor ANSI-256 (fg + bg do ceu).
/*/
Static Function GCol( fg )
    ConOutRaw( cEsc + "[38;5;" + GI2S(fg) + ";48;5;" + GI2S(COL_SKY) + "m" )
Return

/*/{Protheus.doc} GPraw
    Desenho transiente: emite na tela SEM tocar aScr/aMat
    (banana, explosao, texto de input).
/*/
Static Function GPraw( x, y, cCh, fg )
    If x < 1 .Or. y < 1 .Or. x > nW .Or. y > nH
        Return
    EndIf
    GAt( x, y )
    GCol( fg )
    ConOutRaw( cCh )
Return

/*/{Protheus.doc} GPut
    Desenho permanente: atualiza aScr (e aMat quando nMat >= 0) e emite.
/*/
Static Function GPut( x, y, cCh, fg, nMat )
    If x < 1 .Or. y < 1 .Or. x > nW .Or. y > nH
        Return
    EndIf
    If nMat >= 0
        aMat[y][x] := nMat
    EndIf
    aScr[y][x] := { cCh, fg }
    GPraw( x, y, cCh, fg )
Return

/*/{Protheus.doc} GDraw
    Reemite o conteudo estatico da celula (apaga transientes).
/*/
Static Function GDraw( x, y )
    Local aC
    If x < 1 .Or. y < 1 .Or. x > nW .Or. y > nH
        Return
    EndIf
    aC := aScr[y][x]
    GPraw( x, y, aC[1], aC[2] )
Return

/*/{Protheus.doc} GRect
    Repinta um retangulo com o conteudo estatico de aScr.
/*/
Static Function GRect( x1, y1, x2, y2 )
    Local i, j
    For j := y1 To y2
        For i := x1 To x2
            GDraw( i, j )
        Next
    Next
Return

/*/{Protheus.doc} GClrRect
    Transforma area em ceu (material + render) e repinta.
/*/
Static Function GClrRect( x1, y1, x2, y2 )
    Local i, j
    For j := y1 To y2
        For i := x1 To x2
            If i >= 1 .And. i <= nW .And. j >= 1 .And. j <= nH
                aMat[j][i] := MAT_SKY
                aScr[j][i] := { " ", COL_SKY }
            EndIf
        Next
    Next
    GRect( x1, y1, x2, y2 )
Return

/*/{Protheus.doc} GCls
    Limpa tela inteira e zera grades (SCREEN 0 + CLS).
/*/
Static Function GCls()
    GScrInit()
    ConOutRaw( cEsc + "[2J" + cEsc + "[H" )
Return

/*/{Protheus.doc} GTxt
    Texto permanente (nao altera material — como PRINT no texto do original).
/*/
Static Function GTxt( x, y, cTxt, fg )
    Local i
    For i := 1 To Len( cTxt )
        If x + i - 1 >= 1 .And. x + i - 1 <= nW .And. y >= 1 .And. y <= nH
            aScr[y][ x + i - 1 ] := { SubStr( cTxt, i, 1 ), fg }
        EndIf
    Next
    GAt( x, y )
    GCol( fg )
    ConOutRaw( cTxt )
Return

/*/{Protheus.doc} GTxtT
    Texto transiente (prompts de input) — nao toca aScr.
/*/
Static Function GTxtT( x, y, cTxt, fg )
    GAt( x, y )
    GCol( fg )
    ConOutRaw( cTxt )
Return

/*/{Protheus.doc} GCenter
    SUB Center do original.
/*/
Static Function GCenter( nRow, cTxt )
    GTxt( Int( nW / 2 - Len( cTxt ) / 2 ), nRow, cTxt, COL_TXT )
Return

/*/{Protheus.doc} GRest
    SUB Rest do original — pausa em segundos.
/*/
Static Function GRest( nSec )
    Sleep( Int( nSec * 1000 ) )
Return

/*/{Protheus.doc} GRnd
    DEF FnRan(x) = INT(RND(1) * x) + 1 — inteiro em [1, x].
    Randomize(min,max) do AdvPP retorna [min,max); logo max = x+1.
/*/
Static Function GRnd( x )
Return Int( Randomize( 1, Int( x ) + 1 ) )

/*/{Protheus.doc} GWaitKey
    "Press any key" — no AdvPP, Enter via ConIn. EOF sinaliza saida.
/*/
Static Function GWaitKey()
    Local x := ConIn( "" )
    If IsNil( x )
        lQuit := .T.
    EndIf
Return

/*/{Protheus.doc} GInpNum
    Le um numero na posicao (x,y) via ConIn. Recusa > 360 (como GetNum#).
    EOF no stdin -> lQuit e retorna 0.
/*/
Static Function GInpNum( cPrompt, x, y )
    Local cIn  := ""
    Local nVal := 0

    Do While .T.
        GTxtT( x, y, Space( 26 ), COL_TXT )
        ConOutRaw( cEsc + "[?25h" )
        GAt( x, y )
        cIn := ConIn( cPrompt )
        ConOutRaw( cEsc + "[?25l" )
        If IsNil( cIn )
            lQuit := .T.
            Return 0
        EndIf
        cIn := AllTrim( cIn )
        If Empty( cIn )
            nVal := 0
            Exit
        EndIf
        nVal := Val( cIn )
        If nVal > 360
            Loop
        EndIf
        Exit
    EndDo
    GRect( x, y, Min( x + 26, nW ), y )
Return nVal

// ---------------------------------------------------------------------------
// Telas de texto
// ---------------------------------------------------------------------------

/*/{Protheus.doc} GSparkle
    SparklePause — borda de asteriscos animada; depois aguarda Enter.
/*/
Static Function GSparkle()
    Local a, b, i
    Local cPat := "*    *    *    *    *    *    *    *    *    *    *    *    *    *    *    *    *    "

    For i := 1 To 3
        For a := 1 To 5
            GTxtT( 1, 1,   SubStr( cPat, a, Min( Len( cPat ) - a + 1, nW ) ), 196 )
            GTxtT( 1, nH,  SubStr( cPat, 6 - a, Min( Len( cPat ) - 5 + a, nW ) ), 196 )
            For b := 2 To nH - 1
                If Mod( a + b, 5 ) == 1
                    GTxtT( nW, b, "*", 196 )
                    GTxtT( 1, nH + 1 - b, "*", 196 )
                Else
                    GTxtT( nW, b, " ", 196 )
                    GTxtT( 1, nH + 1 - b, " ", 196 )
                EndIf
            Next
            Sleep( 60 )
        Next
    Next
    GWaitKey()
Return

/*/{Protheus.doc} GIntro
    SUB Intro — tela de abertura.
/*/
Static Function GIntro()
    GCls()
    GCenter( 4,  "Q B a s i c    G O R I L L A S" )
    GCenter( 6,  "Copyright (C) IBM Corporation 1991" )
    GCenter( 8,  "Your mission is to hit your opponent with the exploding" )
    GCenter( 9,  "banana by varying the angle and power of your throw, taking" )
    GCenter( 10, "into account wind speed, gravity, and the city skyline." )
    GCenter( 11, "The wind speed is shown by a directional arrow at the bottom" )
    GCenter( 12, "of the playing field, its length relative to its strength." )
    GCenter( 14, "(reconstruido em AdvPL / AdvPP)" )
    GCenter( nH - 2, "Pressione Enter para continuar" )
    GSparkle()
Return

/*/{Protheus.doc} GInputs
    SUB GetInputs — nomes, pontos da partida e gravidade.
/*/
Static Function GInputs()
    Local cIn

    GCls()
    GTxt( 10, 8, "Nome do Jogador 1 (default = 'Player 1'): ", COL_TXT )
    ConOutRaw( cEsc + "[?25h" )
    cIn := ConIn( "" )
    If IsNil( cIn ); lQuit := .T.; Return; EndIf
    cP1 := IIf( Empty( cIn ), "Player 1", Left( AllTrim( cIn ), 10 ) )

    GTxt( 10, 10, "Nome do Jogador 2 (default = 'Player 2'): ", COL_TXT )
    cIn := ConIn( "" )
    If IsNil( cIn ); lQuit := .T.; Return; EndIf
    cP2 := IIf( Empty( cIn ), "Player 2", Left( AllTrim( cIn ), 10 ) )
    ConOutRaw( cEsc + "[?25l" )

    nGames := 0
    Do While .T.
        GTxtT( 10, 12, Space( 50 ), COL_TXT )
        ConOutRaw( cEsc + "[?25h" )
        GAt( 10, 12 )
        cIn := ConIn( "Jogar ate quantos pontos (default = 3)? " )
        If IsNil( cIn ); lQuit := .T.; Return; EndIf
        nGames := Int( Val( Left( AllTrim( cIn ), 2 ) ) )
        If nGames > 0 .Or. Empty( cIn )
            Exit
        EndIf
    EndDo
    If nGames == 0
        nGames := 3
    EndIf

    nGrav := 0
    Do While .T.
        GTxtT( 10, 14, Space( 50 ), COL_TXT )
        GAt( 10, 14 )
        cIn := ConIn( "Gravidade em m/s (Terra = 9.8)? " )
        If IsNil( cIn ); lQuit := .T.; Return; EndIf
        nGrav := Val( AllTrim( cIn ) )
        If nGrav > 0 .Or. Empty( cIn )
            Exit
        EndIf
    EndDo
    If nGrav <= 0
        nGrav := 9.8
    EndIf
    ConOutRaw( cEsc + "[?25l" )
Return

/*/{Protheus.doc} GSprite
    Sprite do gorila (9x5) por pose: 1=danca esq, 2=danca dir, 3=bracos baixos.
    Equivalente aos GET arrays GorL&, GorR&, GorD&.
/*/
Static Function GSprite( nPose )
    // Sprites como arrays de celulas (1 char UTF-8 por elemento) — SubStr e
    // byte-based no AdvPP, entao nao podemos fatiar strings com glifos wide.
    Local aD := { ;
        {" "," ","▄","█","█","█","▄"," "," "}, ;
        {" "," ","█","o","_","o","█"," "," "}, ;
        {" ","█","█","▄","▄","▄","█","█"," "}, ;
        {" ","█"," ","█","█","█"," ","█"," "}, ;
        {" "," "," ","█"," ","█"," "," "," "} }
    Local aL := { ;
        {"█"," ","▄","█","█","█","▄"," "," "}, ;
        {"█"," ","█","o","_","o","█"," "," "}, ;
        {" "," ","█","▄","▄","▄","█","█"," "}, ;
        {" "," ","█","█","█"," ","█"," "," "}, ;
        {" "," "," ","█"," ","█"," "," "," "} }
    Local aR := { ;
        {" ","▄","█","█","█","▄"," ","█"," "}, ;
        {" "," ","█","o","_","o","█"," ","█"}, ;
        {" ","█","█","▄","▄","▄","█"," "," "}, ;
        {" "," ","█"," ","█","█","█"," "," "}, ;
        {" "," "," ","█"," ","█"," "," "," "} }
    Do Case
    Case nPose == 1
        Return aL
    Case nPose == 2
        Return aR
    EndCase
Return aD

/*/{Protheus.doc} GDrawGor
    DrawGorilla + PUT — desenha pose e marca material do gorila.
    nPose: 1 braco esq levantado, 2 braco dir levantado, 3 bracos baixos.
/*/
Static Function GDrawGor( nPl, nPose )
    Local aSp := GSprite( nPose )
    Local i, j, x, y, cCh

    For j := 1 To GOR_H
        For i := 1 To GOR_W
            x := aGor[nPl][1] + i - 1
            y := aGor[nPl][2] + j - 1
            If x < 1 .Or. x > nW .Or. y < 1 .Or. y > nH
                Loop
            EndIf
            cCh := aSp[j][i]
            If cCh != " "
                GPut( x, y, cCh, COL_GOR, MAT_GOR + nPl )
            ElseIf aMat[y][x] == MAT_GOR + nPl
                GPut( x, y, " ", COL_SKY, MAT_SKY )
            EndIf
        Next
    Next
Return

/*/{Protheus.doc} GGorIntro
    GorillaIntro — menu V/P e danca de apresentacao dos dois gorilas.
/*/
Static Function GGorIntro()
    Local cIn, i

    GCls()
    GCenter( 9,  "--------------" )
    GCenter( 11, "V = Ver Intro" )
    GCenter( 12, "P = Jogar" )
    GCenter( 14, "Sua escolha?" )

    aGor[1] := { Int( nW / 2 ) - 11, Int( nH / 2 ) + 3 }
    aGor[2] := { Int( nW / 2 ) + 3,  Int( nH / 2 ) + 3 }
    GDrawGor( 1, 3 )
    GDrawGor( 2, 3 )

    ConOutRaw( cEsc + "[?25h" )
    cIn := ConIn( "" )
    ConOutRaw( cEsc + "[?25l" )
    If IsNil( cIn )
        lQuit := .T.
        Return
    EndIf

    If Upper( Left( AllTrim( cIn ), 1 ) ) == "V"
        GCenter( 2, "Q B A S I C   G O R I L L A S" )
        GCenter( 5, "STARRING:" )
        GCenter( 7, cP1 + " AND " + cP2 )
        For i := 1 To 5
            GDrawGor( 1, 1 )
            GDrawGor( 2, 2 )
            Tone()
            GRest( .25 )
            GDrawGor( 1, 2 )
            GDrawGor( 2, 1 )
            Tone()
            GRest( .25 )
        Next
        GDrawGor( 1, 3 )
        GDrawGor( 2, 3 )
        GCenter( nH - 2, "Pressione Enter para comecar" )
        GWaitKey()
    EndIf
Return

// ---------------------------------------------------------------------------
// Cidade / sol / gorilas
// ---------------------------------------------------------------------------

/*/{Protheus.doc} GCity
    MakeCityScape — gera o skyline (incluido o dead-code CASE 4 do original)
    e a seta de vento.
/*/
Static Function GCity()
    Local nSlope, nNewHt, x, bw, bh, nBCol, nTop
    Local wx, wy, nLen, cArr
    Local nInc  := Max( 1, Round( nH * 10  / 350, 0 ) )
    Local nDefW := Max( 5, Round( nW * 37  / 640, 0 ) )
    Local nRndH := Max( 3, Round( nH * 120 / 350, 0 ) )
    Local nBot  := nH - 2
    Local nMaxT := 5
    Local aBCol := { 245, 160, 37 }

    GCls()
    aBld := {}

    nSlope := GRnd( 6 )
    Do Case
    Case nSlope == 1
        nNewHt := Max( 2, Round( nH * 15 / 350, 0 ) )   // subindo
    Case nSlope == 2
        nNewHt := Round( nH * 130 / 350, 0 )            // descendo
    Case nSlope <= 5
        nNewHt := Max( 2, Round( nH * 15 / 350, 0 ) )   // "V" (mais comum)
    Otherwise
        nNewHt := Round( nH * 130 / 350, 0 )            // "V" invertido
    EndCase

    x := 2
    Do While x <= nW - nInc - 2
        Do Case
        Case nSlope == 1
            nNewHt += nInc
        Case nSlope == 2
            nNewHt -= nInc
        Case nSlope >= 3 .And. nSlope <= 5
            If x > Int( nW / 2 )
                nNewHt -= 2 * nInc
            Else
                nNewHt += 2 * nInc
            EndIf
        EndCase

        bw := GRnd( nDefW ) + nDefW
        If x + bw > nW
            bw := nW - x - 1
        EndIf

        bh := GRnd( nRndH ) + nNewHt
        If bh < nInc
            bh := nInc
        EndIf
        nTop := nBot - bh
        If nTop <= nMaxT
            bh  := nBot - nMaxT
            nTop := nMaxT
        EndIf

        AAdd( aBld, { x, bw, nTop } )
        nBCol := aBCol[ GRnd( 3 ) ]

        For wy := nTop To nBot
            For wx := x To x + bw - 1
                GPut( wx, wy, "█", nBCol, MAT_BUILD )
            Next
        Next

        // janelas
        For wx := x + 1 To x + bw - 2 Step 3
            For wy := nTop + 1 To nBot - 1 Step 2
                If GRnd( 4 ) == 1
                    GPut( wx, wy, "░", COL_WIND, MAT_BUILD )
                Else
                    GPut( wx, wy, "░", COL_WINL, MAT_BUILD )
                EndIf
            Next
        Next

        x += bw + 2
    EndDo

    // vento — formula identica ao original
    nWind := GRnd( 10 ) - 5
    If GRnd( 3 ) == 1
        If nWind > 0
            nWind += GRnd( 10 )
        Else
            nWind -= GRnd( 10 )
        EndIf
    EndIf

    If nWind != 0
        nLen := Min( Int( Abs( nWind ) * 2 ), 24 )
        cArr := IIf( nWind > 0, Replicate( "─", nLen ) + "►", ;
                                "◄" + Replicate( "─", nLen ) )
        GTxtT( Int( nW / 2 ) - IIf( nWind > 0, 0, nLen ), nH, cArr, COL_ARROW )
        GTxtT( 2, nH, "Vento:", COL_TXT )
    EndIf
Return

/*/{Protheus.doc} GPlaceGor
    PlaceGorillas — 2o/3o predio a partir de cada borda.
/*/
Static Function GPlaceGor()
    Local i, nB, aB
    For i := 1 To 2
        nB := IIf( i == 1, GRnd( 2 ) + 1, Len( aBld ) - GRnd( 2 ) )
        nB := Max( 1, Min( Len( aBld ), nB ) )
        aB := aBld[ nB ]
        aGor[i] := { aB[1] + Int( aB[2] / 2 ) - Int( GOR_W / 2 ), aB[3] - GOR_H }
        GDrawGor( i, 3 )
    Next
Return

/*/{Protheus.doc} GSun
    DoSun — sol sorrindo (1) ou chocado (2), 3 linhas no topo central.
/*/
Static Function GSun( nMood )
    Local i, j, x, y, cCh
    Local x0 := Int( nW / 2 ) - 4
    Local aHappy := { ;
        {" ","\\"," ","|"," ","/"," "," "," "}, ;
        {}, ;
        {" ","/"," ","|"," ","\\"," "," "," "} }
    Local aMouth := IIf( nMood == 2, ;
        {"-","("," ","O"," ",")","-"," "," "}, ;
        {"-","(","_","‿","_",")","-"," "," "} )

    // apaga sol anterior
    For j := 1 To 3
        For i := x0 To x0 + 8
            If aMat[j][i] == MAT_SUN
                GPut( i, j, " ", COL_SKY, MAT_SKY )
            EndIf
        Next
    Next

    aHappy[2] := aMouth
    For j := 1 To 3
        For i := 1 To 9
            x := x0 + i - 1
            y := j
            cCh := aHappy[j][i]
            If cCh != " "
                GPut( x, y, cCh, COL_SUN, MAT_SUN )
            EndIf
        Next
    Next
Return

/*/{Protheus.doc} GNames
    Nomes no topo + placar na penultima linha.
/*/
Static Function GNames()
    GTxt( 1, 1, cP1, COL_TXT )
    GTxt( nW - Len( cP2 ), 1, cP2, COL_TXT )
    GScore()
Return

/*/{Protheus.doc} GScore
    Center 23, LTRIM$(STR$(w1)) + ">Score<" + LTRIM$(STR$(w2))
/*/
Static Function GScore()
    Local cTxt := GI2S( aWins[1] ) + ">Score<" + GI2S( aWins[2] )
    GTxt( Int( nW / 2 - Len( cTxt ) / 2 ), nH - 1, cTxt, COL_TXT )
Return

// ---------------------------------------------------------------------------
// Tiro / fisica / explosao
// ---------------------------------------------------------------------------

/*/{Protheus.doc} GCell2VX / GCell2VY
    Celula -> coordenada virtual (espaco 640x350 do original).
/*/
Static Function GCell2VX( cx )
Return ( cx - .5 ) * 640 / nW
Static Function GCell2VY( cy )
Return ( cy - .5 ) * 350 / nH

/*/{Protheus.doc} GShot
    DoShot — le angulo e velocidade do jogador e dispara.
    Retorna o gorila atingido (1/2) ou 0.
/*/
Static Function GShot( nPl )
    Local x     := IIf( nPl == 1, 1, nW - 27 )
    Local nAng  := 0
    Local nVel  := 0
    Local nHit  := 0

    nAng := GInpNum( "Angulo: ",    x, 2 )
    If lQuit ; Return 0 ; EndIf
    nVel := GInpNum( "Velocidade: ", x, 3 )
    If lQuit ; Return 0 ; EndIf

    If nPl == 2
        nAng := 180 - nAng
    EndIf

    lSunHit := .F.
    nHit := GPlot( nPl, nAng, nVel )
    If lSunHit
        GSun( 1 )
    EndIf
Return nHit

/*/{Protheus.doc} GPlot
    PlotShot — laco da trajetoria com vento e gravidade (formulas do original
    no espaco virtual 640x350) e colisao via grade material.
/*/
Static Function GPlot( nPl, nAng, nVel )
    Local nRad   := nAng / 180 * SPI
    Local nVX    := Cos( nRad ) * nVel
    Local nVY    := Sin( nRad ) * nVel
    Local nX0    := GCell2VX( aGor[nPl][1] + Int( GOR_W / 2 ) )
    Local nY0    := GCell2VY( aGor[nPl][2] ) - 8
    Local t      := 0
    Local xv, yv, cx, cy, m, nVict
    Local ox := -1, oy := -1, oRot := 0
    Local lImpact := .F., lInSun := .F., lOn := .T.
    Local nHitGor := 0, lSelf := .F.
    Local aRot := { "─", "\", "│", "/" }
    Local nDir := IIf( nVX >= 0, 1, -1 )

    If nVel < 2
        lSelf := .T.          // tiro fraco: cai na propria cabeca
        lOn   := .F.
    Else
        GDrawGor( nPl, IIf( nPl == 1, 1, 2 ) )  // braco do arremesso
        Tone()
        GRest( .1 )
        GDrawGor( nPl, 3 )
    EndIf

    Do While !lImpact .And. lOn
        GRest( .018 )

        If ox > 0
            GDraw( ox, oy )    // apaga banana anterior
            ox := -1
        EndIf

        xv := nX0 + ( nVX * t ) + ( .5 * ( nWind / 5 ) * t * t )
        yv := nY0 - ( nVY * t ) + ( .5 * nGrav * t * t )

        cx := Int( xv * nW / 640 ) + 1
        cy := Int( yv * nH / 350 ) + 1

        If cx < 1 .Or. cx > nW .Or. cy > nH
            lOn := .F.
            Loop
        EndIf

        If cy >= 1
            // checa celula + borda de ataque (LookX/LookY do original)
            m := aMat[cy][cx]
            If cx + nDir >= 1 .And. cx + nDir <= nW .And. m == MAT_SKY
                m := aMat[cy][cx + nDir]
            EndIf

            If m == MAT_SUN
                If !lInSun
                    GSun( 2 )         // SUNSHOCK
                EndIf
                lSunHit := .T.
                lInSun  := .T.
            ElseIf m == MAT_BUILD
                lImpact := .T.
            ElseIf m >= MAT_GOR
                nHitGor := m - MAT_GOR
                lImpact := .T.
            Else
                // ceu: sai do sol?
                If lInSun .And. ( Abs( Int( nW / 2 ) - cx ) > 6 .Or. cy > 4 )
                    lInSun := .F.
                EndIf
                If !lInSun
                    oRot := Mod( Int( t * 10 ), 4 ) + 1
                    GPraw( cx, cy, aRot[oRot], COL_BAN )
                    ox := cx
                    oy := cy
                EndIf
            EndIf
        EndIf

        t += NSTEPS
    EndDo

    If ox > 0
        GDraw( ox, oy )
    EndIf

    nVict := 0
    If lSelf
        GExplode( nPl )
        nVict := nPl
    ElseIf nHitGor > 0
        GExplode( nHitGor )
        nVict := nHitGor
    ElseIf lImpact
        GBoom( cx, cy )
    EndIf
Return nVict

/*/{Protheus.doc} GRing
    Anel de caracteres (raio nR em celulas, achatado na vertical p/ aspecto).
/*/
Static Function GRing( cx, cy, nR, cCh, fg )
    Local i, px, py
    Local nSt := Max( 10, Int( nR * 9 ) )
    For i := 0 To nSt - 1
        px := Int( cx + nR * Cos( i * 2 * SPI / nSt ) + .5 )
        py := Int( cy + nR * Sin( i * 2 * SPI / nSt ) * .6 + .5 )
        GPraw( px, py, cCh, fg )
    Next
Return

/*/{Protheus.doc} GCrater
    Abre cratera: vira ceu toda celula dentro do raio (predio/gorila; sol fica).
/*/
Static Function GCrater( cx, cy, nR )
    Local i, j
    For j := Max( 1, Int( cy - nR ) ) To Min( nH, Int( cy + nR ) + 1 )
        For i := Max( 1, Int( cx - nR ) - 1 ) To Min( nW, Int( cx + nR ) + 1 )
            If ( i - cx ) * ( i - cx ) + ( ( j - cy ) / .6 ) * ( ( j - cy ) / .6 ) <= nR * nR
                If aMat[j][i] != MAT_SUN
                    aMat[j][i] := MAT_SKY
                    aScr[j][i] := { " ", COL_SKY }
                EndIf
            EndIf
        Next
    Next
    GRect( Max( 1, Int( cx - nR ) - 1 ), Max( 1, Int( cy - nR ) ), ;
           Min( nW, Int( cx + nR ) + 1 ), Min( nH, Int( cy + nR ) + 1 ) )
Return

/*/{Protheus.doc} GBoom
    DoExplosion — circulos expandindo (predio atingido).
/*/
Static Function GBoom( cx, cy )
    Local r
    Local nR := Max( 2.0, nH / 10.0 )

    Tone()
    For r := .5 To nR Step .6
        GRing( cx, cy, r, "*", IIf( Mod( Int( r * 2 ), 2 ) == 0, COL_EX1, COL_EX2 ) )
        Sleep( 25 )
    Next
    GCrater( cx, cy, nR )
Return

/*/{Protheus.doc} GExplode
    ExplodeGorilla — flash + cratera maior na posicao do gorila.
/*/
Static Function GExplode( nVict )
    Local r, i
    Local cx := aGor[nVict][1] + Int( GOR_W / 2 )
    Local cy := aGor[nVict][2] + Int( GOR_H / 2 )
    Local nR := Max( 4.0, nH / 7.0 )

    Tone()
    For i := 1 To 3
        For r := .5 To nR Step 1.0
            GRing( cx, cy, r, "*", IIf( Mod( i, 2 ) == 1, COL_EX1, COL_EX2 ) )
        Next
        Sleep( 60 )
    Next
    GCrater( cx, cy, nR )
Return nVict

/*/{Protheus.doc} GDance
    VictoryDance — alterna bracos 4 vezes.
/*/
Static Function GDance( nPl )
    Local i
    For i := 1 To 4
        GDrawGor( nPl, 1 )
        Tone()
        GRest( .2 )
        GDrawGor( nPl, 2 )
        Tone()
        GRest( .2 )
    Next
    GDrawGor( nPl, 3 )
Return

/*/{Protheus.doc} GPlay
    PlayGame — loop principal: nGames rodadas, cidades novas a cada rodada,
    turnos alternados ate o primeiro acerto.
/*/
Static Function GPlay()
    Local nRnd, nJ := 1, nTosser, nVict, nWinner

    aWins := { 0, 0 }
    For nRnd := 1 To nGames
        If lQuit
            Exit
        EndIf
        GCity()
        GPlaceGor()
        GSun( 1 )
        GNames()

        nVict := 0
        Do While nVict == 0 .And. !lQuit
            nJ      := 1 - nJ
            nTosser := nJ + 1
            nVict   := GShot( nTosser )
            If nVict > 0
                nWinner := IIf( nVict == nTosser, 3 - nTosser, nTosser )
                aWins[nWinner] += 1
                GScore()
                GDance( nWinner )
            EndIf
        EndDo
        If lQuit
            Exit
        EndIf
        Sleep( 800 )
    Next

    If !lQuit
        GCls()
        GCenter( 8,  "GAME OVER!" )
        GCenter( 10, "Score:" )
        GTxt( Int( nW / 2 ) - 10, 11, cP1 + " " + GI2S( aWins[1] ), COL_TXT )
        GTxt( Int( nW / 2 ) - 10, 12, cP2 + " " + GI2S( aWins[2] ), COL_TXT )
        GCenter( nH - 2, "Pressione Enter para continuar" )
        GSparkle()
    EndIf
Return

/*/{Protheus.doc} GAgain
    "Would you like to play again?" — s/n via ConIn.
/*/
Static Function GAgain()
    Local cIn
    GCls()
    GCenter( 11, "Gostaria de jogar novamente? (s/n)" )
    ConOutRaw( cEsc + "[?25h" )
    cIn := ConIn( "" )
    ConOutRaw( cEsc + "[?25l" )
    If IsNil( cIn )
        lQuit := .T.
        Return .F.
    EndIf
Return Upper( Left( AllTrim( cIn ), 1 ) ) $ "SY"
