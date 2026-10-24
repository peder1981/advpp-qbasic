#!/bin/bash
# Oraculo de som: captura o original com DX-CAPTURE /A, detecta as notas do WAV e compara
# com o log do interpretador (QB_SOUNDLOG=1). Uso: compare_sound.sh caso.bas [dir]
cd "$(dirname "$0")/../../.." || exit 1
BAS="$1"; NAME="$(basename "${BAS%.bas}")"
WORK="${2:-${SCRATCH:-/tmp}/oracle_snd_$NAME}"
mkdir -p "$WORK"
ORACLE_AUDIO=1 ORACLE_END=SYSTEM tests/qbi/oracle/run_original.sh "$BAS" "$WORK/orig" >/dev/null 2>&1
WAV=$(ls "$WORK"/orig/caps/*.wav 2>/dev/null | head -1)
[ -n "$WAV" ] || { echo "SKIP $NAME (sem captura de audio)"; exit 2; }
QB_SOUNDLOG=1 QB_FILE="$BAS" timeout 60 advplc run qbi.prg </dev/null > "$WORK/ours_sound.txt" 2>&1
python3 tests/qbi/oracle/audio_compare.py "$WORK/ours_sound.txt" tests/qbi/oracle/audio_notes.py "$WAV"
