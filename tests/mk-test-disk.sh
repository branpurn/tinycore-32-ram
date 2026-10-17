#!/bin/sh
# Build out/test-disk.img: a small IDE disk standing in for the 755C's HDD.
#   sda1  ext2 (8 MB)  tce/optional/{hello,hellogz}.tcz + tce/onboot.lst
#   sda2  swap (4 MB)  exercised by rcS swap auto-detection
# No root needed (mke2fs -d, sfdisk and mkswap all work on plain files).
. "$(dirname "$0")/../scripts/common.sh"
PATH=$PATH:/usr/sbin:/sbin
T="$BUILD/test-disk"; rm -rf "$T"; mkdir -p "$T/ext" "$T/hello/usr/local/bin" "$T/hellogz/usr/local/bin"
printf '#!/bin/sh\necho hello from tcz\n' > "$T/hello/usr/local/bin/hello-tcz"
printf '#!/bin/sh\necho hello from gz tcz\n' > "$T/hellogz/usr/local/bin/hellogz-tcz"
# Install scripts: hello uses the Tiny Core convention
# (usr/local/tce.installed/<name>), hellogz the older tc32 <name>.sh fallback.
mkdir -p "$T/hello/usr/local/tce.installed" "$T/hellogz/usr/local/tce.installed"
printf '#!/bin/sh\necho tc > /tmp/hello.installed\n' > "$T/hello/usr/local/tce.installed/hello"
printf '#!/bin/sh\necho sh > /tmp/hellogz.installed\n' > "$T/hellogz/usr/local/tce.installed/hellogz.sh"
chmod 755 "$T"/hello*/usr/local/bin/* "$T"/hello*/usr/local/tce.installed/*
mkdir -p "$T/ext/tce/optional"
mksquashfs "$T/hello"   "$T/ext/tce/optional/hello.tcz"   -comp xz   -noappend -all-root -quiet >/dev/null
mksquashfs "$T/hellogz" "$T/ext/tce/optional/hellogz.tcz" -comp gzip -noappend -all-root -quiet >/dev/null
echo hello.tcz > "$T/ext/tce/onboot.lst"
dd if=/dev/zero of="$T/p1" bs=1M count=8 status=none
mke2fs -q -t ext2 -O ^resize_inode,^dir_index,^ext_attr -b 1024 -d "$T/ext" -E root_owner=0:0 "$T/p1"
dd if=/dev/zero of="$T/p2" bs=1M count=4 status=none
chmod 600 "$T/p2"; mkswap "$T/p2" >/dev/null
IMG="$OUT/test-disk.img"
dd if=/dev/zero of="$IMG" bs=1M count=13 status=none
printf 'label: dos\nstart=2048, size=16384, type=83\nstart=18432, size=8192, type=82\n' | sfdisk -q "$IMG"
dd if="$T/p1" of="$IMG" bs=512 seek=2048 conv=notrunc status=none
dd if="$T/p2" of="$IMG" bs=512 seek=18432 conv=notrunc status=none
log "test disk: $IMG"
