#!/bin/bash
# Compara a tela final do interpretador (QB_DUMP) com a do QBASIC original (oraculo).
# Uso: compare.sh caso.bas [dir_saida]
cd "$(dirname "$0")/../../.." || exit 1
BAS="$1"; NAME="$(basename "${BAS%.bas}")"
WORK="${2:-${SCRATCH:-/tmp}/oracle_$NAME}"
mkdir -p "$WORK"
tests/qbi/oracle/run_original.sh "$BAS" "$WORK/orig" >/dev/null 2>&1 || { echo "SKIP $NAME (oraculo falhou)"; exit 2; }
if [[ "$NAME" == *oracle* ]]; then
  # programas que gravam resultados em arquivo (GFXRES.TXT) em vez da tela
  mkdir -p "$WORK/ours"
  REPO="$(pwd)"
  (cd "$WORK/ours" && QB_FILE="$REPO/$BAS" timeout 60 advplc run "$REPO/qbi.prg" </dev/null > "$WORK/ours.txt" 2>&1) || true
  sed 's/[[:space:]]*$//' "$WORK/ours/GFXRES.TXT" > "$WORK/ours.scr" 2>/dev/null || : > "$WORK/ours.scr"
  sed 's/[[:space:]]*$//' "$WORK/orig/c/GFXRES.TXT" > "$WORK/orig.scr" 2>/dev/null || : > "$WORK/orig.scr"
else
QB_DUMP=1 QB_FILE="$BAS" timeout 60 advplc run qbi.prg < <(printf '%b' "${ORACLE_OURS_IN:-}") > "$WORK/ours.txt" 2>&1
tail -25 "$WORK/ours.txt" | sed 's/[[:space:]]*$//' > "$WORK/ours.scr"
iconv -f CP437 -t UTF-8 "$WORK/orig/SCR.TXT" | sed 's/[[:space:]]*$//' > "$WORK/orig.scr"
# atributos de cor: o oraculo grava ATR.TXT; comparamos tambem
QB_DUMP=2 QB_FILE="$BAS" timeout 60 advplc run qbi.prg < <(printf '%b' "${ORACLE_OURS_IN:-}") > "$WORK/ours_attr.txt" 2>&1
tail -25 "$WORK/ours_attr.txt" | sed 's/[[:space:]]*$//' > "$WORK/ours.atr"
sed 's/[[:space:]]*$//' "$WORK/orig/ATR.TXT" > "$WORK/orig.atr"
if ! cmp -s "$WORK/ours.atr" "$WORK/orig.atr"; then
  echo "ATRIBUTOS DIFERENTES $NAME"; diff "$WORK/orig.atr" "$WORK/ours.atr" | head -6
fi
fi
if cmp -s "$WORK/ours.scr" "$WORK/orig.scr"; then echo "IGUAL $NAME"; exit 0; fi
echo "DIFERENTE $NAME"; diff "$WORK/orig.scr" "$WORK/ours.scr" | head -20; exit 1
