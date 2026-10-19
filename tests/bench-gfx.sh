#!/bin/sh
# make bench-gfx: X speed on the 755C kernel in QEMU, old path vs new
# (docs/GRAPHICS.md "Speed"). QEMU runs at about DX4-100 speed (-icount
# shift=4); wd90c24fb.fake_kbps models the VL-bus window (QEMU maps A0000
# as RAM, so copies would otherwise be free). Results: out/test-logs/bench-*.json
#   old   xaccel=0: Xfbdev gets the 10 Hz whole-frame flush (as before tc755 PR)
#   dmg   fake=2: damage rectangles only (what a plain WD90C24 gets)
#   blt   fake=4: damage + BITBLT, engine taking no CPU time (as on the chip)
#   model fake=3: damage + BITBLT on a RAM model, checked against the frame
. "$(dirname "$0")/../scripts/common.sh"
KBPS=${KBPS:-8192}
S="$BUILD/gfx/sysroot/usr/local"
PATH="$BUILD/toolchain/i486-linux-musl-cross/bin:$PATH" i486-linux-musl-gcc -Os -march=i486 \
    -I"$S/include" -L"$S/lib" -Wl,-rpath-link,"$S/lib" -o "$BUILD/gfx/xbench" "$TOP/tests/xbench/xbench.c" -lX11 \
    || die "xbench build failed"
"$TOP/tests/mk-gfx-disk.sh" "$BUILD/gfx/xbench"
rc=0
for c in "old 2 wd90c24fb.xaccel=0" "dmg 2" "blt 4" "model 3"; do
    set -- $c
    python3 "$TOP/tests/gfx-bench.py" --fake "$2" --tag "$1-kb$KBPS" --extra "wd90c24fb.fake_kbps=$KBPS ${3:-}" || rc=1
done
exit $rc
