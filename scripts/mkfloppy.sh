#!/bin/sh
# Build out/tc32.img: 1.44 MB FAT12 floppy with syslinux 4.07, vmlinuz, core.xz
. "$(dirname "$0")/common.sh"
IMG="$OUT/tc32.img"
for f in bzImage core.xz; do [ -f "$OUT/$f" ] || die "missing out/$f"; done
export MTOOLS_SKIP_CHECK=1
rm -f "$IMG"
dd if=/dev/zero of="$IMG" bs=1024 count=1440 status=none
mkfs.fat -F 12 -n TC32 -i 7c320486 --invariant "$IMG" >/dev/null 2>&1 \
  || mkfs.fat -F 12 -n TC32 -i 7c320486 "$IMG" >/dev/null
T="$BUILD/floppy-stage"; rm -rf "$T"; mkdir -p "$T"
cp "$OUT/bzImage" "$T/vmlinuz"; cp "$OUT/core.xz" "$T/core.xz"
cp "$TOP/boot/syslinux.cfg" "$T/syslinux.cfg"
touch -d "@$SOURCE_DATE_EPOCH" "$T"/*
syslinux-mtools --install "$IMG"
mcopy -m -i "$IMG" "$T/syslinux.cfg" "$T/vmlinuz" "$T/core.xz" ::/ \
  || die "files do not fit on the floppy"
free=$(mdir -i "$IMG" ::/ | awk '/bytes free/{gsub(/ /,"",$0); sub(/bytesfree/,""); print}')
log "tc32.img: $(stat -c %s "$IMG") bytes; vmlinuz $(stat -c %s "$T/vmlinuz"), core.xz $(stat -c %s "$T/core.xz"), free on FAT: ${free} bytes"
mdir -i "$IMG" ::/ >&2
