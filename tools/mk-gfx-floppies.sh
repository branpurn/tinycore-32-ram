#!/bin/sh
# Sneakernet alternative to tools/send-gfx.sh: pack the graphics second
# stage onto 1.44 MB FAT transfer floppies (out/gfx/floppy-gfx-N.img), each
# with gfx-setup.sh and sha256.txt. Writing a floppy takes ~1 min; the
# serial link needs ~11 min at 57600 (estimate) for the same files.
#   tools/mk-gfx-floppies.sh [-a]     -a: include Xaw-apps.tcz (optional apps)
# Write:   dd if=out/gfx/floppy-gfx-1.img of=/dev/fdX bs=512 conv=fsync
# On the 755C, per floppy:
#   mkdir -p /mnt/fd0 && mount /dev/fd0 /mnt/fd0 && sh /mnt/fd0/gfx-setup.sh && umount /mnt/fd0
set -eu
here=$(cd "$(dirname "$0")/.." && pwd)
PATH=$here/build/host/bin:$PATH:/usr/sbin:/sbin
export MTOOLS_SKIP_CHECK=1
all=; [ "${1:-}" = -a ] && all=1
G=$here/out/gfx K=$here/out/gfx/755c
files="$K/vmlinuz.x $G/Xlibs.tcz $G/Xfbdev.tcz $K/modutils.tcz $G/jwm.tcz $K/fb-wd90c24.tcz $G/rxvt.tcz $K/trackpoint.tcz"
[ -n "$all" ] && files="$files $G/Xaw-apps.tcz"
for f in $files; do [ -f "$f" ] || { echo "mk-gfx-floppies: missing $f (make gfx gfx-755c)" >&2; exit 1; }; done
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT INT TERM
( for f in $files; do printf '%s  %s\n' "$(sha256sum "$f" | cut -d' ' -f1)" "$(basename "$f")"; done ) > "$T/sha256.txt"
# first-fit decreasing; usable FAT12 space minus room for the two small files
cap=$((1440 * 1024 - 33 * 512 - 8192))
n=0
for f in $(for f in $files; do echo "$(stat -c %s "$f") $f"; done | sort -rn | cut -d' ' -f2); do
    s=$(stat -c %s "$f"); c=$(( (s + 511) / 512 * 512 )); i=1 put=
    while [ $i -le $n ]; do
        u=$(cat "$T/used$i")
        if [ $((u + c)) -le $cap ]; then echo $((u + c)) > "$T/used$i"; echo "$f" >> "$T/list$i"; put=1; break; fi
        i=$((i + 1))
    done
    [ -n "$put" ] || { n=$((n + 1)); echo $c > "$T/used$n"; echo "$f" > "$T/list$n"; }
done
rm -f "$G"/floppy-gfx-*.img
i=1
while [ $i -le $n ]; do
    img=$G/floppy-gfx-$i.img
    dd if=/dev/zero of="$img" bs=1024 count=1440 status=none
    mkfs.fat -F 12 -n TC32GFX$i --invariant "$img" >/dev/null 2>&1 || mkfs.fat -F 12 -n TC32GFX$i "$img" >/dev/null
    mcopy -i "$img" "$here/tools/gfx-setup.sh" "$T/sha256.txt" $(cat "$T/list$i") ::/
    free=$(mdir -i "$img" ::/ | awk '/bytes free/{gsub(/ /,""); sub(/bytesfree/,""); print}')
    echo "floppy-gfx-$i.img: $(for f in $(cat "$T/list$i"); do printf '%s ' "$(basename "$f")"; done)(${free} bytes free)"
    i=$((i + 1))
done
echo "mk-gfx-floppies: $n floppies in $G; see the header of $0 for the 755C steps"
