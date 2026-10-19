#!/bin/sh
# Assemble the initramfs: busybox + rootfs/ overlay -> out/core.xz
# Built with the kernel's gen_init_cpio, so no root/fakeroot is needed and all
# files are owned by root:root with fixed timestamps.
. "$(dirname "$0")/common.sh"
K="$BUILD/linux-$LINUX_VER"; KO="$BUILD/kernel-obj"
[ -x "$KO/usr/gen_init_cpio" ] || die "build the kernel first (needs usr/gen_init_cpio)"
[ -x "$OUT/busybox" ] || die "build busybox first"
S="$BUILD/rootfs-stage"; rm -rf "$S"; mkdir -p "$S"
for d in bin sbin usr/bin usr/sbin etc etc/sysconfig dev proc sys tmp mnt root home/tc opt usr/local/bin usr/local/tce.installed var/run; do mkdir -p "$S/$d"; done
cp "$OUT/busybox" "$S/bin/busybox"
"$OUT/busybox" --list-full | while read -r a; do
    [ -e "$S/$a" ] || ln -s /bin/busybox "$S/$a"
done
cp -a "$TOP/rootfs/." "$S/"
find "$S" -exec touch -h -d "@$SOURCE_DATE_EPOCH" {} +
# Build a gen_init_cpio list: dir contents (uid/gid mapped to 0) + device nodes.
L="$BUILD/rootfs.list"
{
  echo "nod /dev/console 0600 0 0 c 5 1"
  echo "nod /dev/null 0666 0 0 c 1 3"
  python3 "$TOP/scripts/cpio-list.py" "$S"
} > "$L"
"$KO/usr/gen_init_cpio" -t "$SOURCE_DATE_EPOCH" "$L" > "$BUILD/core.cpio"
xz -9e --check=crc32 --lzma2=dict=1MiB -T1 -c "$BUILD/core.cpio" > "$OUT/core.xz"
log "core.cpio: $(stat -c %s "$BUILD/core.cpio") bytes, core.xz: $(stat -c %s "$OUT/core.xz") bytes"
