# Architect — Arquitetura do projeto

## Visão (C4-nível 1)
```
gorilla.bas ─┐
             ├─ port manual ─▶ gorilla.prg ─┐
nibbles.bas ─┘                  nibbles.prg ─┼─▶ advplc (compilador AdvPP/Go)
                                            │        └─▶ terminal ANSI (tty)
                                            └─▶ qbasic.prg (lib proposta — emula API QBasic)
```

## Camadas do port (padrão replicável) 🟢
1. **Física/estado** — espaço virtual do legado (640×350 px, 80×50 pts) desacoplado do terminal
2. **Grade** — `aMat` (material/colisão) + `aScr`/`aArena` (render estável)
3. **Render** — ANSI-256 célula a célula: GPut/GDraw permanente, GPraw transiente, GRect restauração
4. **Input** — ConIn (linha) p/ turno; key-stream arquivo p/ tempo-real
5. **Tempo/som** — Sleep(ms), Seconds(), Tone()

## Matriz de impacto Spec→Código 🟢
| Capacidade | gorilla | nibbles |
|---|---|---|
| Grade material | ✔ | ✔ (via cor da arena) |
| Células UTF-8 (arrays) | ✔ gorila/sol | ✔ arena |
| Key-stream INKEY$ | — | ✔ |
| Cratera/pixel-erase | ✔ | ✔ tail-erase |
| Input por linha | ✔ | ✔ |

## Specs-organization: `module` → `_reversa_sdd/{gorillas,nibbles}/`
