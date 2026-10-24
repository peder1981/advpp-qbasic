# Reviewer — Revisão cruzada das specs

## Consistências verificadas 🟢
- `gorillas/analysis.md` ↔ código: física virtual 640×350, materiais 0/1/3/10+i,
  dead-code CASE 4, self-hit documentado como adaptação (não bug)
- `nibbles/analysis.md` ↔ código: arena 80×50 por `▀` fg/bg, sister=(r%2)*2−1,
  key-stream com watchdog kill -0, dead-code diff$="P"
- `decisions.md` ↔ ambos: ADR-001..004 cobrem todas as decisões estruturais
- `qbasic/requirements.md` ↔ `design.md`: API P0 100% coberta por prova real nos ports

## Reclassificações
- Sprite de sol 9×3 usa `‿` (U+203F) — 🟡 INFERIDO que todos os terminais
  renderizam; fallback documentado (boca "u"/"-")
- Key-stream depende de `bash`, `stty`, `read -sn1`, `/dev/tty` — 🟢 no alvo
  (Linux), 🔴 LACUNA em Windows/terminals minimal — fallback ConIn já existe

## Gaps aceitos (fora de escopo declarado) 🟢
- PLAY sonoro, gráfico VGA real, PEEK/POKE — limites do AdvPP, não do port

## Veredito
Specs consistentes, sem ambiguidades bloqueantes. O inventário P0 da lib
`qbasic.prg` está completo e validado por prova real em 2 programas distintos.
