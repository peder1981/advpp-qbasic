#!/bin/sh
# Roda os casos de teste do interpretador qbi.prg e compara a saida com .expected.
#   - tests/qbi/NOME.stdin (opcional): entrada padrao do caso
#   - casos com "screen" no nome: QB_DUMP=1 (ao fim, imprime o buffer de tela 80x25)
cd "$(dirname "$0")/../.." || exit 1
pass=0; fail=0
for bas in tests/qbi/*.bas; do
    # programas de oraculo gravam em arquivo e sao validados por tests/qbi/oracle/compare.sh
    case "$bas" in *oracle*) continue ;; esac
    name="${bas%.bas}"
    stdin_file=/dev/null
    [ -f "$name.stdin" ] && stdin_file="$name.stdin"
    dump=0
    case "$bas" in *screen*) dump=1 ;; esac
    snd=0
    case "$bas" in *sound*) snd=1 ;; esac
    out="$(mktemp)"
    if [ -f "tests/qbi/$(basename "$name").ide" ]; then
        # caso de IDE: inicia sem arquivo (tela de edicao) e o teclado vem de .stdin
        env -u QB_FILE QB_DUMP=1 timeout 60 advplc run qbi.prg < "$stdin_file" > "$out" 2>&1
    else
        QB_DUMP=$dump QB_SOUNDLOG=$snd QB_FILE="$bas" timeout 60 advplc run qbi.prg < "$stdin_file" > "$out" 2>&1
    fi
    if cmp -s "$out" "$name.expected"; then
        pass=$((pass+1)); echo "PASS $bas"
    else
        fail=$((fail+1)); echo "FAIL $bas"; diff "$name.expected" "$out" | head -40
    fi
    rm -f "$out"
done
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
