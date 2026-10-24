# Design — `qbasic.prg`

## Camadas
1. **Runtime de estado** — `Private` em `QbInit()`: `aQbMat[H][W]` (material),
   `aQbScr[H][W]` ({char,fg,bg}), `nQbW/nQbH`, `cQbEsc`, `lQbTTY`, `nQbKeyOff`
2. **Render** — `QbPut/QbDraw/QbRect/QbCls` (permanente) e `QbPraw` (transiente);
   mesma disciplina dos ports (transiente nunca toca aScr)
3. **Input** — `QbConIn` (linha) e `QbKeyInit/Read/Stop` (key-stream idem nibbles)
4. **Sprites** — arrays de células UTF-8 (nunca SubStr em string wide)

## Mapeamento de namespace BASIC→AdvPL
```
SUB/FUNCTION → Static Function ; CALL → chamada direta
DIM SHARED → Private em Main  ; DEF FN → Static Function 1-linha
GOSUB x: → chamada + labels viram funções  ; SELECT CASE → Do Case
TYPE → array posicional documentado (ex: {row,col})
GET/PUT de área → array de {char,fg} + região
```

## Tarefas (tasks.md resumido)
1. `QbInit/QbTerm` + grade + ANSI base (portar helpers G*/N* unificados)
2. `QbLocate/Print/Color/Cls/Center` (texto)
3. `QbConIn` + validação numérica (INPUT/INPUT$)
4. `QbKeyInit/Read/Stop` (key-stream; ESC[A-D; Q global)
5. `QbPset/Point/Line/Circle/Paint` sobre grade material
6. `QbGet/Put` sprites (área retangular ↔ array células)
7. `QbSleep/Timer/Rnd/Randomize/Tone`
8. `QbPlay` — parser MML mínimo (T,O,L,notas) → sequência de Tone (bell: só ritmo) — P1
9. `QbPause/QbMsg` helpers de dialogo estilo SparklePause/SpacePause
10. Tradutor mecânico `bas2prg`: regras de rename + relatório de não-suportados — P1

## Riscos
- `read -sn1` depende de bash no tty; sem tty → stubs (QbInkey="")
- 2 células/ponto (80×50) vs 1 célula/ponto (gorilla): a lib precisa de ambos os modos — `QbScreen` escolhe densidade
- PLAY real fora de escopo (P1 usa bell/ritmo)
