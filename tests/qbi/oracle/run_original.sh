#!/bin/bash
# Oraculo: roda um .bas no QBASIC.EXE original (DOSBox-X) e despeja a tela de texto.
# Uso: run_original.sh programa.bas SAIDA_DIR
# Saida: SAIDA_DIR/SCR.TXT (25 linhas, caracteres) e SAIDA_DIR/ATR.TXT (atributos por celula)
# Requer: QBASIC.EXE (QB_EXE, default scratchpad/olddos_x), dosbox-x extraido em ~/.local/opt/dosbox-x
set -e
SRC="$1"; OUT="$2"
QB_EXE="${QB_EXE:?defina QB_EXE com o caminho de QBASIC.EXE}"
DBX="${DBX:-$HOME/.local/opt/dosbox-x/root/usr/bin/dosbox-x}"
DBXLIB="$HOME/.local/opt/dosbox-x/root/usr/lib/x86_64-linux-gnu"
mkdir -p "$OUT/c"
rm -f "$OUT/c/SCR.TXT" "$OUT/c/ATR.TXT"
cp "$QB_EXE" "$OUT/c/QBASIC.EXE"
# programa + bloco de despejo (executa ao chegar ao fim do programa)
python3 - "$SRC" "$OUT/c/TEST.BAS" <<'PY'
import os, re, sys
src, dst = sys.argv[1], sys.argv[2]
lines = open(src, 'rb').read().decode('cp1252', 'replace').replace('\r', '').split('\n')
out = []
in_type = False
cls_done = False
DECL = re.compile(r'^\s*(\d+\s+)?(DECLARE|CONST|DIM|REM|\'|$)', re.I)
for l in lines:
    if not cls_done:
        if re.match(r'^\s*(\d+\s+)?TYPE\s', l, re.I):
            in_type = True
        elif in_type:
            if re.match(r'^\s*(\d+\s+)?END\s+TYPE', l, re.I):
                in_type = False
        elif not DECL.match(l):
            # CLS antes da primeira instrucao executavel (o original nao limpa a tela ao iniciar)
            out.append('CLS')
            cls_done = True
    l = re.sub(r'^(\s*(\d+\s+)?)END\s*$', r'\1GOSUB OraDump: END', l)
    out.append(l)
if not cls_done:
    out.append('CLS')
out += ['GOSUB OraDump', os.environ.get('ORACLE_END', 'END'), 'OraDump:',
        'DEF SEG = &HB800', 'OPEN "SCR.TXT" FOR OUTPUT AS #9',
        'FOR oraR = 0 TO 24', '  oraS$ = ""', '  FOR oraC = 0 TO 79',
        '    oraS$ = oraS$ + CHR$(PEEK(2 * (oraR * 80 + oraC)))', '  NEXT oraC',
        '  PRINT #9, RTRIM$(oraS$)', 'NEXT oraR', 'CLOSE #9',
        'OPEN "ATR.TXT" FOR OUTPUT AS #8',
        'FOR oraR = 0 TO 24', '  oraS$ = ""', '  FOR oraC = 0 TO 79',
        '    oraS$ = oraS$ + STR$(PEEK(2 * (oraR * 80 + oraC) + 1)) + ","', '  NEXT oraC',
        '  PRINT #8, oraS$', 'NEXT oraR', 'CLOSE #8', 'DEF SEG', 'RETURN']
open(dst, 'wb').write(('\r\n'.join(out) + '\r\n').encode('cp1252'))
PY
mkdir -p "$OUT/caps"
if [ -n "$ORACLE_AUDIO" ]; then RUNLINE='dx-capture /A qbasic /RUN TEST.BAS'; else RUNLINE='qbasic /RUN TEST.BAS'; fi
cat > "$OUT/dosbox.conf" <<CONF
[sdl]
fullscreen=false
[dosbox]
title=ORACLE_QB
captures=$OUT/caps
[cpu]
cycles=max
[autoexec]
mount c $OUT/c
c:
$RUNLINE
CONF
(LD_LIBRARY_PATH="$DBXLIB" DISPLAY="${DISPLAY:-:1}" timeout 180 "$DBX" -conf "$OUT/dosbox.conf" >/dev/null 2>&1 &)
# teclas para programas que esperam entrada (ORACLE_KEYS: palavras separadas por espaco,
# letras/digitos sao enviados um a um; "Return" = Enter)
if [ -n "$ORACLE_KEYS" ]; then
  sleep 15
  W=$(DISPLAY="${DISPLAY:-:1}" xdotool search --name ORACLE_QB | head -1)
  DISPLAY="${DISPLAY:-:1}" xdotool windowfocus --sync "$W" 2>/dev/null || true
  for tok in $ORACLE_KEYS; do
    if [ ${#tok} -eq 1 ] || [ "$tok" = "Return" ]; then
      DISPLAY="${DISPLAY:-:1}" xdotool key --delay 150 "$tok"; sleep 1
    else
      for ((ci=0; ci<${#tok}; ci++)); do DISPLAY="${DISPLAY:-:1}" xdotool key --delay 150 "${tok:ci:1}"; sleep 0.5; done
    fi
  done
fi
for i in $(seq 1 180); do
  if [ -s "$OUT/c/ATR.TXT" ] && [ -s "$OUT/c/SCR.TXT" ]; then sleep 1; break; fi
  sleep 1
done
# encerra o DOSBox que este script iniciou
for p in $(ps -eo pid,comm | awk '$2=="dosbox-x"{print $1}'); do kill -9 "$p" 2>/dev/null || true; done
if [ -n "$ORACLE_AUDIO" ]; then
  # espera o DX-CAPTURE fechar o WAV (o programa termina com SYSTEM)
  for i in $(seq 1 40); do ls "$OUT/caps"/*.wav >/dev/null 2>&1 && break; sleep 1; done
  sleep 3
fi
if [ -s "$OUT/c/SCR.TXT" ]; then cp "$OUT/c/SCR.TXT" "$OUT/SCR.TXT"; cp "$OUT/c/ATR.TXT" "$OUT/ATR.TXT" 2>/dev/null || true; echo "ok $OUT/SCR.TXT"; else echo "FALHOU: sem SCR.TXT"; exit 1; fi
