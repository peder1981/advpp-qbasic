# Requirements — `qbasic.prg` (camada de compatibilidade QBasic→AdvPP)

## Objetivo
Emular a API do QBasic sobre as primitivas do AdvPP, de modo que programas `.bas`
de console/texto rodem com tradução mínima (renomear declarações) em vez de reescrita.

## Escopo (prioridade P0 — usado pelos 2 jogos portados)
| QBasic | Spec de implementação | Status prova |
|---|---|---|
| `SCREEN 0/9`, `WIDTH`, `CLS` | alt-screen + grade de células ANSI | 🟢 |
| `LOCATE r,c`, `PRINT`, `COLOR f,b` | cursor ANSI + `38;5;f;48;5;bm` | 🟢 |
| `INPUT`, `LINE INPUT` | `ConIn(prompt)` | 🟢 |
| `INKEY$` | key-stream `/tmp/qb_key.bin` (reader bash+stty) | 🟢 |
| `RND(n)`, `RANDOMIZE` | `Randomize(1, Int(x)+1)` | 🟢 |
| `TIMER`, `SLEEP`, `PLAY` | `Seconds()`, `Sleep(ms)`, `Tone()` | 🟢 |
| `PSET/LINE/CIRCLE/PAINT/POINT` | sobre grade material + célula (método gorilla) | 🟢 |
| `GET/PUT` sprites | arrays de células UTF-8 (método sprite) | 🟢 |
| `DIM SHARED`, `TYPE` | `Private` + arrays-posição | 🟢 |

## Escopo P1 (emulável com esforço)
- `BEEP`/`SOUND` → `\a` ou player externo
- `DEF FN`, `GOSUB/RETURN` → funções Static
- Strings BASIC (`LEFT$` etc.) → já existem (`Left`/`SubStr`/`Val`/`Str`)
- `%` → `Mod()`, `!`/`#`/`&` tipos → dinâmico

## Fora de escopo (limites AdvPP)
- PEEK/POKE, DEF SEG, OUT, CALL ABSOLUTE (hardware DOS)
- SCREEN 12/13 pixel-buffer real (paleta VGA, páginas)
- PLAY com frequências (só bell)

## API proposta (nomes)
```
QbScreen(n)   QbCls()         QbLocate(r,c)      QbPrint(cTxt)
QbColor(f,b)  QbPset(x,y,c)   QbPoint(x,y)       QbLine(x1,y1,x2,y2,c[,bf])
QbCircle(x,y,r,c)             QbPaint(x,y,c)     QbGet/QbPut(x,y,aSpr)
QbInkey()     QbInput(cPr)    QbLineInput(cPr)   QbSleep(s)
QbTimer()     QbRnd(n)        QbPlay(cMml)       QbTone()
```
Estado em `Private` de `QbInit()`; mesma disciplina de grade dos ports atuais.

## Critério de aceite
`GORILLAS.BAS` e `NIBBLES.BAS` rodam traduzidos mecanicamente (rename de keywords)
com gameplay idêntico aos ports manuais já validados.
