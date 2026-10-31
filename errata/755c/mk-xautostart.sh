#!/bin/sh
# Build xautostart.tcz: starts X at boot on the 755C (see xautostart/xautostart).
#   errata/755c/mk-xautostart.sh [OUTDIR]     default: out/
# Install: copy it to <tce>/optional/ and add "xautostart.tcz" to onboot.lst
# after Xfbdev.tcz. Boot a kernel with Unix sockets (vmlinuz.x, label x).
set -eu
here=$(cd "$(dirname "$0")" && pwd)
out=${1:-$here/../../out}
command -v mksquashfs >/dev/null || { echo "mk-xautostart: needs mksquashfs (squashfs-tools)" >&2; exit 1; }
st=$(mktemp -d); chmod 755 "$st"; trap 'rm -rf "$st"' EXIT INT TERM
mkdir -p "$st/usr/local/tce.installed" "$out"
cp "$here/xautostart/xautostart" "$st/usr/local/tce.installed/xautostart"
chmod 755 "$st/usr/local/tce.installed/xautostart"
rm -f "$out/xautostart.tcz"
mksquashfs "$st" "$out/xautostart.tcz" -comp xz -b 4K -noappend -all-root -no-xattrs -quiet >/dev/null
( cd "$out" && sha256sum xautostart.tcz )
