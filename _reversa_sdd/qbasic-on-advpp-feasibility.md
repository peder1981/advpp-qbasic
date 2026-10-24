# Spec — Reconstruir QBasic através do compilador AdvPP

**Pergunta do operador:** é possível reconstruir o QBasic (linguagem/ambiente)
usando o AdvPP como base? Resposta a partir da experiência dos 2 ports.

## Veredito: 🟡 PARCIALMENTE — como camada de compatibilidade, não como engine

O AdvPP é um compilador/VM AdvPL com saída console + TUI (huh/lipgloss),
web-SSE e Fyne. O QBasic é um dialeto BASIC com tela modo-texto e modos
gráficos (CGA/EGA/VGA), INPUT/INKEY$, PLAY sonoro, GET/PUT sprites.

### O que já está provado como portável 🟢
| Recurso QBasic | Equivalente validado |
|---|---|
| PRINT/LOCATE/COLOR/CLS | ConOutRaw + sequências ANSI |
| SCREEN texto 80x25 | Alt-screen + GTxt/NCenter |
| CIRCLE/LINE/PAINT/POINT | Grade material + células (gorilla.prg) |
| Arena pseudo-gráfica 80x50 | U+2580 fg/bg (nibbles.prg) |
| INPUT/LINE INPUT | ConIn (raw-mode editor) |
| PLAY | Tone() (bell — sem notas reais) |
| TIMER/SLEEP/REST | Sleep(ms)/Seconds() |
| RANDOMIZE/RND | Randomize(min,max) |
| GET/PUT sprites | Arrays de células UTF-8 |

### Gaps reais 🔴
1. **INKEY$** — não existe polling não-bloqueante nativo. Resolvido por
   key-stream externo (bash/stty/arquivo), não por primitiva.
2. **Gráfico real** (SCREEN 9/12/13, GET/PUT bit-a-bit, PALETTE) — inexistente;
   só via texto/ANSI ou janela Fyne (que não expõe canvas de pixels ao AdvPL).
3. **PLAY sonoro** — só bell; sem síntese de notas.
4. **PEEK/POKE/DEF SEG/OUT** — sem sentido fora do DOS (NumLock etc. = no-ops).

### Caminho viável de reconstrução 🟡
Não escrever um novo interpretador — escrever uma **lib AdvPL `qbasic.prg`**
que emule a API: SCREEN/LOCATE/PRINT/COLOR sobre ANSI; CIRCLE/LINE/PSET/POINT
sobre grade material + células; INKEY$ sobre o key-stream; INPUT sobre ConIn;
PLAY → Tone ou tabela de frequências externa (speaker-test/beep). Com isso,
programas .bas como GORILLAS/NIBBLES rodam quase sem tradução manual — a
diferença vs. ports atuais é só a camada de nomes/semântica.

**Estimativa de cobertura:** ~80% dos programas QBasic de console/texto;
modos gráficos EGA/VGA ficariam limitados à emulação por blocos (como a arena
80x50 já demonstra ser suficiente para os clássicos).

## Próximo passo sugerido
`reversa-archaeologist` nos dois pares .bas/.prg para gerar spec da API-mínima
`qbasic.prg` (inventário completo de comandos usados vs. mapeamento AdvPP).
