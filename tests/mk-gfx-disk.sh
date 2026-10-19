#!/bin/sh
# out/gfx/test-disk-gfx.img: IDE disk for the graphics QEMU test, laid out
# like the 755C's CF card (smaller): sda1 ext2 with tce/optional/*.tcz,
# sda2 swap. Usage: tests/mk-gfx-disk.sh [--deliver] [EXTRA.tcz ...]
# --deliver: the files sit in /deliver with tools/gfx-setup.sh and
# sha256.txt (as on a transfer floppy) next to a stock disk extlinux.conf,
# so the test runs the 755C install procedure itself.
. "$(dirname "$0")/../scripts/common.sh"
PATH=$PATH:/usr/sbin:/sbin
deliver=; [ "${1:-}" = --deliver ] && { deliver=1; shift; }
T="$BUILD/gfx/test-disk"; rm -rf "$T"; mkdir -p "$T/ext/tce/optional"
for e in Xlibs Xfbdev jwm rxvt Xaw-apps; do cp "$OUT/gfx/$e.tcz" "$OUT/gfx/$e.tcz.dep" "$T/ext/tce/optional/"; done
# the 755C kernel's driver extensions (scripts/build-gfx-kernel.sh 755c), if built
for x in modutils fb-wd90c24 trackpoint; do [ -f "$OUT/gfx/755c/$x.tcz" ] && cp "$OUT/gfx/755c/$x.tcz" "$T/ext/tce/optional/"; done
for x in "$@"; do cp "$x" "$T/ext/tce/optional/"; done
if [ -n "$deliver" ]; then
    D="$T/ext/deliver"; mkdir -p "$D" "$T/ext/boot/extlinux"
    mv "$T/ext/tce/optional/"*.tcz "$D/"; rm -f "$T/ext/tce/optional/"*.dep
    cp "$TOP/tools/gfx-setup.sh" "$D/"
    ( cd "$D" && sha256sum *.tcz > sha256.txt )
    sed 's/@TCEDEV@/sda1/g' "$TOP/boot/extlinux.conf" > "$T/ext/boot/extlinux/extlinux.conf"
else
    echo Xfbdev.tcz > "$T/ext/tce/onboot.lst"     # as on the 755C: startx is in Xfbdev.tcz
fi
dd if=/dev/zero of="$T/p1" bs=1M count=24 status=none
mke2fs -q -t ext2 -O ^resize_inode,^dir_index,^ext_attr -b 1024 -d "$T/ext" -E root_owner=0:0 "$T/p1"
dd if=/dev/zero of="$T/p2" bs=1M count=32 status=none
chmod 600 "$T/p2"; mkswap "$T/p2" >/dev/null
IMG="$OUT/gfx/test-disk-gfx.img"
dd if=/dev/zero of="$IMG" bs=1M count=58 status=none
printf 'label: dos\nstart=2048, size=49152, type=83\nstart=51200, size=65536, type=82\n' | sfdisk -q "$IMG"
dd if="$T/p1" of="$IMG" bs=512 seek=2048 conv=notrunc status=none
dd if="$T/p2" of="$IMG" bs=512 seek=51200 conv=notrunc status=none
log "gfx test disk: $IMG"
