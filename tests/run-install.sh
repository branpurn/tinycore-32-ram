#!/bin/sh
# make test-install: installer -> 2 GB IDE disk -> boot without floppy ->
# serial (XMODEM) transfer. Logs in out/test-logs/ (serial-install.log,
# serial-diskboot*.log, send-file-*.log, result-install.json).
set -u
TOP=$(cd "$(dirname "$0")/.." && pwd)
cd "$TOP"
[ -f out/installer.img ] || { echo "out/installer.img missing: run 'make installer' first"; exit 2; }
command -v qemu-system-i386 >/dev/null || { echo "qemu-system-i386 not found"; exit 2; }
export PATH="$TOP/build/host/bin:$PATH:/usr/sbin:/sbin"
command -v sx >/dev/null || command -v lsx >/dev/null || { echo "sx (lrzsz) not found: run 'make tools'"; exit 2; }
mkdir -p out/test-logs
{ python3 tests/install.py "$@"; echo $? > out/test-logs/.install-rc; } | tee out/test-logs/console-install.txt
rc=$(cat out/test-logs/.install-rc); rm -f out/test-logs/.install-rc
# The 2 GB disk is sparse; keep it on failure for inspection (make run-disk
# style: qemu ... -drive if=ide,format=raw,file=out/test-install-disk.img).
[ "$rc" = 0 ] && rm -f out/test-install-disk.img
exit "$rc"
