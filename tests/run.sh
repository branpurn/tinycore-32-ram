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
for m in $MEMS; do
    python3 tests/harness.py --mem "$m" | tee "out/test-logs/console-m$m.txt"
    st=$?; [ $st -eq 0 ] || rc=1
    tail -1 "out/test-logs/console-m$m.txt" >> "$summary"
done
# Default boot path exactly as on real hardware: no keypress, no disk.
python3 tests/harness.py --mem 32 --nokey | tee out/test-logs/console-m32-nokey.txt
[ $? -eq 0 ] || rc=1
tail -1 out/test-logs/console-m32-nokey.txt >> "$summary"
for m in $SWEEP; do
    python3 tests/harness.py --mem "$m" --boot-timeout 120 | tee "out/test-logs/console-m$m.txt"
    tail -1 "out/test-logs/console-m$m.txt" | sed 's/$/  [headroom run, non-fatal]/' >> "$summary"
done
echo; echo "===== tc32 test summary ====="; cat "$summary"
exit $rc
