#!/bin/sh
# Assemble SEPARATE S6d initramfs → out/core-s6d.xz (does not overwrite out/core.xz).
. "$(dirname "$0")/common.sh"
K="$BUILD/linux-$LINUX_VER"; KO="$BUILD/kernel-obj"
[ -x "$KO/usr/gen_init_cpio" ] || die "build the kernel first (needs usr/gen_init_cpio)"
[ -x "$OUT/busybox-s6d" ] || die "build busybox-s6d first"
S="$BUILD/rootfs-s6d-stage"; rm -rf "$S"; mkdir -p "$S"
for d in bin sbin usr/bin usr/sbin etc etc/sysconfig dev proc sys tmp mnt root home/tc opt usr/local/bin usr/local/tce.installed var/run; do mkdir -p "$S/$d"; done
cp "$OUT/busybox-s6d" "$S/bin/busybox"
# busybox --list-full needs the i386 binary; use qemu if needed
if "$OUT/busybox-s6d" --list-full >/dev/null 2>&1; then
  LIST_CMD="$OUT/busybox-s6d --list-full"
elif command -v qemu-i386 >/dev/null; then
  LIST_CMD="qemu-i386 $OUT/busybox-s6d --list-full"
else
  die "cannot list busybox-s6d applets"
fi
eval "$LIST_CMD" | while read -r a; do
    [ -e "$S/$a" ] || ln -s /bin/busybox "$S/$a"
done
cp -a "$TOP/rootfs/." "$S/"
# Overlay S6d-specific files (rcS without fdisk/swapon)
cp -a "$TOP/rootfs-s6d/." "$S/"
chmod 755 "$S/etc/init.d/rcS" "$S/init" 2>/dev/null || true
find "$S" -exec touch -h -d "@$SOURCE_DATE_EPOCH" {} +
L="$BUILD/rootfs-s6d.list"
{
  echo "nod /dev/console 0600 0 0 c 5 1"
  echo "nod /dev/null 0666 0 0 c 1 3"
  python3 "$TOP/scripts/cpio-list.py" "$S"
} > "$L"
"$KO/usr/gen_init_cpio" -t "$SOURCE_DATE_EPOCH" "$L" > "$BUILD/core-s6d.cpio"
xz -9e --check=crc32 --lzma2=dict=1MiB -T1 -c "$BUILD/core-s6d.cpio" > "$OUT/core-s6d.xz"
log "core-s6d.cpio: $(stat -c %s "$BUILD/core-s6d.cpio") bytes, core-s6d.xz: $(stat -c %s "$OUT/core-s6d.xz") bytes"
# Verify keeps present as applets
for a in ash getty rx sha256sum dmesg mknod stty mount umount losetup find; do
    [ -L "$S/bin/$a" ] || [ -L "$S/sbin/$a" ] || [ -L "$S/usr/bin/$a" ] || [ -L "$S/usr/sbin/$a" ] \
      || die "missing keep applet symlink: $a"
done
for a in vi awk fdisk less gzip gunzip tar cpio mke2fs blockdev swapon; do
    if [ -e "$S/bin/$a" ] || [ -e "$S/sbin/$a" ] || [ -e "$S/usr/bin/$a" ] || [ -e "$S/usr/sbin/$a" ]; then
        die "dropped applet still present: $a"
    fi
done
log "applet keep/drop checks OK"
