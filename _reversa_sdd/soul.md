# Soul — qbasic-games-advpl

## Propósito 🟢
Reconstruir jogos clássicos do QBasic (GORILLAS.BAS, NIBBLES.BAS) em AdvPL puro
compilado pelo AdvPP (advplc), preservando fidelidade de gameplay e servindo como
prova de capacidade do compilador para programas console/TUI.

## Entidades centrais 🟢
- **advpp.json** — manifesto (`projects.{nibbles,gorillas}`, main *.prg)
- **gorilla.prg** — turn-based: grade material de colisão (substitui POINT()),
  física em espaço virtual 640x350, render ANSI-256 célula a célula
- **nibbles.prg** — real-time: arena 80x50 pontos (U+2580 fg/bg), key-stream
  `/tmp/nib_key.bin` via reader bash + `stty -icanon -echo` (substitui INKEY$)

## Decisões fundadoras 🟢
1. Renderização = terminal ANSI em alt-screen; sprites = arrays de células
   UTF-8 (SubStr/Len são byte-based — strings fatiáveis só ASCII)
2. ConIn() substitui INPUT/INKEY$ onde não há polling; para real-time, o
   key-stream em arquivo é a única via (documentada em memória/Joplin)
3. PLAY → Tone() (bell); TIMER/FOR-delay → Sleep(ms)
4. Bugs intencionais do legado preservados (CASE 4 morto, diff$="P")

## Além dos jogos: reconstruir o QBasic sobre o AdvPP?
Ver `_reversa_sdd/qbasic-on-advpp-feasibility.md`.
