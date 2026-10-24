# Archaeologist — Módulo `nibbles`

## Identidade 🟢
Snake real-time 1-2 jogadores: comer números cresce a cobra e o placar; bater
em muro/cobra custa vida. Original: `nibbles.bas` (721 linhas, MS 1990, texto 80×25
com pseudo-pixels 80×50). Port: `nibbles.prg` (930 linhas, AdvPL/AdvPP).

## Estrutura do legado 🟢
- **Entry**: `RANDOMIZE`→`Intro`→`GetInputs`→`SetColors`→`DrawScreen`→loop(`PlayNibbles` while `StillWantsToPlay`)
- **Arena** (`arenaType`, 50×80): cada char = 2 pontos; `realRow=INT((r+1)/2)`, `sister=(r%2)*2−1`; render via COLOR fg/bg + chr(219/220/223)
- **Cobra** (`snaketype`): buffer circular 1000, head/length/row/col/direction/lives/score/scolor/alive
- **Input**: `INKEY$` setas (P1) + WASD (P2), 'P' pausa — polling não-bloqueante
- **Níveis**: 10 layouts CASE 1-9+ELSE; speed=(100−skill)*2+1 calibrado por benchmark FOR/NEXT

## Arquitetura do port 🟢
| Legado | Port |
|---|---|
| chr(219/220/223) + COLOR | `'▀'` U+2580 fg=ponto-ímpar(topo), bg=ponto-par(base) |
| POINT/Set | `NSet`/`NPoint` com `aArena[r][c]` de cor |
| INKEY$ | **key-stream**: `/tmp/nib_read.sh` (`stty -icanon -echo`, `read -sn1` no `/dev/tty`) → `/tmp/nib_key.bin`; consumo `FOpen/FSeek/FReadStr` com offset; ESC[A-D→setas |
| speed calibrada | `Sleep(nDelay)`; `nDelay≈(100−skill)ms` |
| PLAY | `Tone()` (bell) |
| SpacePause/StillWants | `NBox`+`NKWait` sobre o stream; `Q` sai em qualquer ponto |

## Regras de negócio 🟢
1. Eat: `score+=num`, `length+=num*4` (cap 970), `num++`; `num==10`→NEXTLEVEL
2. Colisão: `NPoint(r,c,bg)` ou cabeças iguais → morte (−1 vida, −10 score)
3. Vidas=5; `lives≤0` → GAME OVER → Play Again (Y/N→Y/S)
4. Dead-code `diff$="P"` preservado (Y/N nunca casa — aceleração nunca aplica)
5. 1 jogador: `aSam[2].row=0` (cobra 2 inerte, não desenhada)

## Decisões 🟡
- Reader auto-encerra por flag `/tmp/nib_run` ou `kill -0 <pid-VM>`; restaura `stty -g`
- Sem tty (pipe): `UiTermWidth(0)==0`→sem reader, pausas via ConIn — smoke-testável
- `nNumRR` em linhas-reais; digit NTxt não marca material (número "atravessável", fiel)
