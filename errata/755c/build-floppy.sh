#!/bin/sh
# Build the ThinkPad 755C dual-CF installer floppy (1.44 MB, i486).
#
#   errata/755c/build-floppy.sh [-N] [OUTPUT.img]
#     OUTPUT  default out/tc755c-installer.img (images are never committed)
#     -N      do not run `make installer` first (reuse out/)
#
# The floppy is the stock installer floppy (out/installer.img: vmlinuz,
# core.xz, install.xz) plus a third initramfs, e755c.xz, that adds
# /usr/sbin/install-dualcf, the example extlinux.conf and a login banner.
# Same kernel, same console defaults (COM1 9600 8N1), same SOURCE_DATE_EPOCH,
# so the result is reproducible byte for byte.
set -eu
TOP=$(cd "$(dirname "$0")/../.." && pwd)
HERE=$TOP/errata/755c
BUILD=$TOP/build OUT=$TOP/out
export SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-1767225600}"
# FAT stores local time: pin the zone so the image does not depend on the host.
export TZ=UTC
export PATH="$BUILD/host/bin:$PATH:/usr/sbin:/sbin"
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
log() { printf '==> %s\n' "$*" >&2; }
MAKE=1
while getopts Nh o; do
    case $o in N) MAKE="" ;; *) sed -n '4,6s/^# \{0,1\}//p' "$0"; exit 2 ;; esac
done
shift $((OPTIND - 1))
IMG=${1:-$OUT/tc755c-installer.img}
case $IMG in /*) ;; *) IMG=$(pwd)/$IMG ;; esac

[ -n "$MAKE" ] && make -C "$TOP" installer
for f in bzImage core.xz install.xz; do [ -f "$OUT/$f" ] || die "missing out/$f (run make installer)"; done
GIC=$BUILD/kernel-obj/usr/gen_init_cpio
[ -x "$GIC" ] || die "missing $GIC (run make kernel)"
for t in mkfs.fat mcopy mdir syslinux-mtools xz python3; do
    command -v "$t" >/dev/null || die "host tool $t not found"
done

S=$BUILD/e755c-stage; rm -rf "$S"
mkdir -p "$S/usr/sbin" "$S/usr/share/tc32/755c"
cp "$HERE/install-dualcf.sh" "$S/usr/sbin/install-dualcf"; chmod 755 "$S/usr/sbin/install-dualcf"
cp "$HERE/installer.txt" "$S/usr/share/tc32/installer.txt"
cp "$HERE/extlinux.conf.example" "$S/usr/share/tc32/755c/"
find "$S" -exec touch -h -d "@$SOURCE_DATE_EPOCH" {} +
python3 "$TOP/scripts/cpio-list.py" "$S" > "$BUILD/e755c.list"
"$GIC" -t "$SOURCE_DATE_EPOCH" "$BUILD/e755c.list" > "$BUILD/e755c.cpio"
xz -9e --check=crc32 --lzma2=dict=1MiB -T1 -c "$BUILD/e755c.cpio" > "$OUT/e755c.xz"

T=$BUILD/e755c-floppy; rm -rf "$T"; mkdir -p "$T"
cp "$OUT/bzImage" "$T/vmlinuz"; cp "$OUT/core.xz" "$OUT/install.xz" "$OUT/e755c.xz" "$T/"
sed -e 's/initrd=core.xz,install.xz /initrd=core.xz,install.xz,e755c.xz /' \
    -e 's/^SAY tc32 installer:/SAY tc32 755C dual-CF installer:/' \
    "$TOP/boot/installer.cfg" > "$T/syslinux.cfg"
[ "$(grep -c 'e755c.xz' "$T/syslinux.cfg")" -eq 2 ] || die "boot/installer.cfg changed; update build-floppy.sh"
( cd "$T" && sha256sum vmlinuz core.xz install.xz e755c.xz > sha256.txt )
touch -d "@$SOURCE_DATE_EPOCH" "$T"/*

export MTOOLS_SKIP_CHECK=1
mkdir -p "$(dirname "$IMG")"
rm -f "$IMG.part"
dd if=/dev/zero of="$IMG.part" bs=1024 count=1440 status=none
mkfs.fat -F 12 -n TC755C -i 7c320755 --invariant "$IMG.part" >/dev/null 2>&1 \
  || mkfs.fat -F 12 -n TC755C -i 7c320755 "$IMG.part" >/dev/null
syslinux-mtools --install "$IMG.part"
mcopy -m -i "$IMG.part" "$T/syslinux.cfg" "$T/vmlinuz" "$T/core.xz" "$T/install.xz" \
    "$T/e755c.xz" "$T/sha256.txt" ::/ || die "files do not fit on the floppy"
mv "$IMG.part" "$IMG"
free=$(mdir -i "$IMG" ::/ | awk '/bytes free/{gsub(/[^0-9]/,""); print}')
log "$IMG: $(stat -c %s "$IMG") bytes, e755c.xz $(stat -c %s "$OUT/e755c.xz") bytes, free on FAT: $free bytes"
sha256sum "$IMG"
