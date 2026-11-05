#!/bin/sh
# Build out/tc755-s6d.img: SEPARATE S6d floppy (does not overwrite out/tc32.img).
# vmlinuz = S6d-export tc755x kernel; initrd = core-s6d.xz.
. "$(dirname "$0")/common.sh"
IMG="$OUT/tc755-s6d.img"
VMLINUZ=${S6D_VMLINUZ:-/workspace/755c-research/out-s6d-exports/bzImage-6.18.57-tc755x}
CORE=${S6D_CORE:-$OUT/core-s6d.xz}
CFG=${S6D_SYSLINUX:-$TOP/boot/syslinux-s6d.cfg}
[ -f "$VMLINUZ" ] || die "missing vmlinuz: $VMLINUZ"
[ -f "$CORE" ] || die "missing core: $CORE (run mkrootfs-s6d.sh)"
[ -f "$CFG" ] || die "missing $CFG"
export MTOOLS_SKIP_CHECK=1
rm -f "$IMG"
dd if=/dev/zero of="$IMG" bs=1024 count=1440 status=none
/sbin/mkfs.fat -F 12 -n TC755S6D -i 7355006d --invariant "$IMG" >/dev/null 2>&1 \
  || /sbin/mkfs.fat -F 12 -n TC755S6D -i 7355006d "$IMG" >/dev/null
T="$BUILD/floppy-s6d-stage"; rm -rf "$T"; mkdir -p "$T"
cp "$VMLINUZ" "$T/vmlinuz"
cp "$CORE" "$T/core.xz"
cp "$CFG" "$T/syslinux.cfg"
touch -d "@$SOURCE_DATE_EPOCH" "$T"/*
syslinux-mtools --install "$IMG"
mcopy -m -i "$IMG" "$T/syslinux.cfg" "$T/vmlinuz" "$T/core.xz" ::/ \
  || die "S6d files do not fit on the floppy (need more core shrink or Brandon OK for tier4)"
free=$(mdir -i "$IMG" ::/ | awk '/bytes free/{gsub(/[^0-9]/,""); print}')
echo "$free" > "$OUT/tc755-s6d-floppy-free.txt"
log "tc755-s6d.img: $(stat -c %s "$IMG") bytes; vmlinuz $(stat -c %s "$T/vmlinuz"), core.xz $(stat -c %s "$T/core.xz"), free on FAT: ${free} bytes"
mdir -i "$IMG" ::/ >&2
