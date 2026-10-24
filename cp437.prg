/*
{Protheus.doc} cp437.prg
    @type        source
    @description Tabela CP437 (code page do DOS/QBasic) -> glifo Unicode (UTF-8).
                 Compartilhada pelo runtime (qbasic.prg: CHR$/ASC) e pelo
                 transpilador (bas2prg.prg: literais com bytes CP437).
*/
#ifndef QB_CP437
#define QB_CP437

/*/{Protheus.doc} QCpTable
    Retorna array de 256 glifos: aTab[n+1] = glifo do byte CP437 n.
/*/
Static Function QCpTable()
    Local aTab := Array( 256 ), aLo := Nil, aHi := Nil, i := Nil
    aLo := StrTokArr2( "☺ ☻ ♥ ♦ ♣ ♠ • ◘ ○ ◙ ♂ ♀ ♪ ♫ ☼ ► ◄ ↕ ‼ ¶ § ▬ ↨ ↑ ↓ → ← ∟ ↔ ▲ ▼", " " )
    aHi := StrTokArr2( "Ç ü é â ä à å ç ê ë è ï î ì Ä Å " + ;
                       "É æ Æ ô ö ò û ù ÿ Ö Ü ¢ £ ¥ ₧ ƒ " + ;
                       "á í ó ú ñ Ñ ª º ¿ ⌐ ¬ ½ ¼ ¡ « » " + ;
                       "░ ▒ ▓ │ ┤ ╡ ╢ ╖ ╕ ╣ ║ ╗ ╝ ╜ ╛ ┐ " + ;
                       "└ ┴ ┬ ├ ─ ┼ ╞ ╟ ╚ ╔ ╩ ╦ ╠ ═ ╬ ╧ " + ;
                       "╨ ╤ ╥ ╙ ╘ ╒ ╓ ╫ ╪ ┘ ┌ █ ▄ ▌ ▐ ▀ " + ;
                       "α ß Γ π Σ σ µ τ Φ Θ Ω δ ∞ φ ε ∩ " + ;
                       "≡ ± ≥ ≤ ⌠ ⌡ ÷ ≈ ° ∙ · √ ⁿ ² ■", " " )
    aTab[1] := " "
    For i := 1 To 31
        aTab[ i + 1 ] := aLo[i]
    Next
    For i := 32 To 126
        aTab[ i + 1 ] := Chr( i )
    Next
    aTab[128] := "⌂"
    For i := 1 To 127
        aTab[ 128 + i ] := aHi[i]
    Next
    aTab[256] := " "
Return aTab

#endif
