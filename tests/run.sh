#!/bin/sh
# tc32 test runner.  Usage: tests/run.sh [MEM_MB ...]   (default: 32)
#   TC32_SWEEP=1 tests/run.sh   -> also 24 16 12 8 (headroom, non-fatal)
# Logs + JSON results: out/test-logs/
set -u
TOP=$(cd "$(dirname "$0")/.." && pwd)
cd "$TOP"
[ -f out/tc32.img ] || { echo "out/tc32.img missing: run 'make' first"; exit 2; }
command -v qemu-system-i386 >/dev/null || { echo "qemu-system-i386 not found"; exit 2; }
sh tests/mk-test-disk.sh >/dev/null 2>&1 || echo "warning: could not build IDE test disk; skipping tce/HDD checks"
mkdir -p out/test-logs
MEMS=${*:-32}
SWEEP=""
[ "${TC32_SWEEP:-0}" = 1 ] && SWEEP="24 16 12 10 8"
rc=0
summary=out/test-logs/summary.txt; : > "$summary"
# hrun LOGNAME NOTE ARGS...: run the harness, keep its exit status (not tee's;
# a harness crash counts as a failure), append its last line to the summary.
hrun() {
    log=out/test-logs/console-$1.txt note=$2; shift 2
    { python3 tests/harness.py "$@"; echo $? > out/test-logs/.rc; } | tee "$log"
    st=$(cat out/test-logs/.rc); rm -f out/test-logs/.rc
    if tail -1 "$log" | grep -q '^== -m'; then tail -1 "$log" | sed "s/\$/$note/" >> "$summary"
    else echo "== $* : FAIL (harness crashed, exit $st)$note" >> "$summary"; fi
    return "$st"
}
for m in $MEMS; do
    hrun "m$m" "" --mem "$m" || rc=1
done
# Default boot path exactly as on real hardware: no keypress, no disk.
hrun m32-nokey "" --mem 32 --nokey || rc=1
# Keyboard on a non-translating i8042 (i8042.direct=1), which is how the
# 755C's controller looks to Linux. raw = a genuine raw set-2 keyboard still
# works with the auto default; forced = atkbd.xlate=2 decodes it as translated.
for k in raw forced; do
    hrun "m32-kbd-$k" "" --mem 32 --kbd "$k" || rc=1
done
for m in $SWEEP; do
    hrun "m$m" "  [headroom run, non-fatal]" --mem "$m" --boot-timeout 120 || :
done
echo; echo "===== tc32 test summary ====="; cat "$summary"
exit $rc
