# Archaeologist — Módulo `gorillas`

## Identidade 🟢
Artilharia turno-a-turno: 2 gorilas sobre prédios se atacam com banana explosiva.
Original: `gorilla.bas` (2301 linhas, IBM 1991, QBasic/EGA 640×350).
Port: `gorilla.prg` (976 linhas, AdvPL/AdvPP).

## Estrutura do legado 🟢
- **Entry**: `InitVars`→`Intro`→loop(`GetInputs`→`GorillaIntro`→`PlayGame`→again?)
- **Física** (`PlotShot`): `x=x0+vx·t+½·(wind/5)·t²`, `y=y0−vy·t+½·g·t²·(ScrH/350)`, `t+=0.1`
- **Colisão** (`POINT(x,y)`): 0=céu; SUNATTR→sunshock+atravessa; OBJECTCOLOR→gorila; demais→impacto
- **Cidade** (`MakeCityScape`): 6 slopes (1 sobe, 2 desce, 3-5 "V", 6 invertido); dead-code `CASE 4` preservado
- **Estado global**: `DIM SHARED` GorillaX/Y, Wind, gravity, Mode, sprites GET (GorD/L/R, bananas)

## Arquitetura do port 🟢
| Legado | Port |
|---|---|
| SCREEN 9 640×350 | Espaço virtual idêntico; render célula↔pixel por escala nW/nH |
| POINT() | `aMat[l][c]` materiais (0 céu,1 prédio,3 sol,10+i gorila) |
| GET/PUT sprites | `GSprite()` arrays de células UTF-8 9×5 (3 poses) |
| CIRCLE explosão | `GRing()` anel + `GCrater()` (material→céu, banana atravessa) |
| INKEY$/INPUT | `ConIn()` linha; EOF→`lQuit` |
| PLAY/TIMER | `Tone()`/`Sleep(ms)` |
| Sun SUNHAPPY/SHOCK | `GSun(1|2)` sprite 9×3 |

## Regras de negócio 🟢
1. Ângulo P2 espelhado (`180−a`); velocity<2 → self-hit
2. Rodadas: `NumGames` cidades; 1 acerto = 1 ponto por rodada; maior score vence
3. Adaptação consciente: self-hit pontua o OPONENTE (bug original `UpdateScores` Results=TRUE≠HITSELF)
4. Ventos: `rand(10)−5`, 1/3 chance reforço ±rand(10); seta ∝ força

## Decisões 🟡 (documentadas no código)
- Materiais de gorila com owner (`10+i`) — melhor que heurística x<metade do original
- Sol marca TODAS células não-espaço como material (raios incluídos, como original)
