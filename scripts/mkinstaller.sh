#!/bin/sh
# Build the installer floppy out/installer.img:
#   vmlinuz + core.xz   identical to the rescue floppy (and to what gets installed)
#   install.xz          overlay initramfs: install-to-disk, extlinux, mbr.bin,
#                       extlinux.conf template, login banner (/root/.profile)
#   sha256.txt          checked by install-to-disk before it touches the disk
#   syslinux.cfg        boot/installer.cfg (default label: install)
. "$(dirname "$0")/common.sh"
KO="$BUILD/kernel-obj"; IMG="$OUT/installer.img"
for f in bzImage core.xz extlinux mbr.bin; do [ -f "$OUT/$f" ] || die "missing out/$f"; done
S="$BUILD/installer-stage"; rm -rf "$S"; mkdir -p "$S/usr/share/tc32"
cp -a "$TOP/installer/." "$S/"
cp "$OUT/extlinux" "$S/usr/sbin/extlinux"
cp "$OUT/mbr.bin" "$TOP/boot/extlinux.conf" "$S/usr/share/tc32/"
find "$S" -exec touch -h -d "@$SOURCE_DATE_EPOCH" {} +
python3 "$TOP/scripts/cpio-list.py" "$S" > "$BUILD/install.list"
"$KO/usr/gen_init_cpio" -t "$SOURCE_DATE_EPOCH" "$BUILD/install.list" > "$BUILD/install.cpio"
xz -9e --check=crc32 --lzma2=dict=1MiB -T1 -c "$BUILD/install.cpio" > "$OUT/install.xz"

export MTOOLS_SKIP_CHECK=1
rm -f "$IMG"
dd if=/dev/zero of="$IMG" bs=1024 count=1440 status=none
mkfs.fat -F 12 -n TC32INST -i 7c320487 --invariant "$IMG" >/dev/null 2>&1 \
  || mkfs.fat -F 12 -n TC32INST -i 7c320487 "$IMG" >/dev/null
T="$BUILD/installer-floppy"; rm -rf "$T"; mkdir -p "$T"
cp "$OUT/bzImage" "$T/vmlinuz"; cp "$OUT/core.xz" "$OUT/install.xz" "$T/"
cp "$TOP/boot/installer.cfg" "$T/syslinux.cfg"
( cd "$T" && sha256sum vmlinuz core.xz install.xz > sha256.txt )
touch -d "@$SOURCE_DATE_EPOCH" "$T"/*
syslinux-mtools --install "$IMG"
mcopy -m -i "$IMG" "$T/syslinux.cfg" "$T/vmlinuz" "$T/core.xz" "$T/install.xz" "$T/sha256.txt" ::/ \
  || die "files do not fit on the installer floppy"
free=$(mdir -i "$IMG" ::/ | awk '/bytes free/{gsub(/[^0-9]/,""); print}')
log "installer.img: install.xz $(stat -c %s "$OUT/install.xz") bytes (cpio $(stat -c %s "$BUILD/install.cpio")), free on FAT: ${free} bytes"
