#!/bin/sh
# Runs ON the 755C (tc32 busybox sh): install the graphics second stage from
# a directory holding the delivered files (a mounted transfer floppy, or /tmp
# after tools/send-gfx.sh), then add the extlinux label "x".
#   sh gfx-setup.sh [SRCDIR]     SRCDIR defaults to this script's directory
# Copies vmlinuz.x to /boot and *.tcz to the tce dir, checks each against
# SRCDIR/sha256.txt when present, appends "LABEL x" (KERNEL /boot/vmlinuz.x,
# APPEND copied from the current DEFAULT label) unless it exists, and adds
# Xfbdev.tcz to onboot.lst (startx lives there). DEFAULT is never changed.
# Safe to re-run, e.g. once per transfer floppy.
set -e
say() { echo "gfx-setup: $*"; }
src=${1:-$(dirname "$0")}
TCE=$(readlink /etc/sysconfig/tcedir 2>/dev/null) || { say "no tce dir: boot with tce=sda1"; exit 1; }
root=${TCE%/tce}; boot=$root/boot; cfg=$boot/extlinux/extlinux.conf
[ -f "$cfg" ] || { say "$cfg not found (tce dir $TCE is not the boot disk?)"; exit 1; }
mkdir -p "$TCE/optional"
ok() {      # FILE: matches its line in sha256.txt (or there is none)
    [ -f "$src/sha256.txt" ] || return 0
    l=$(grep " $(basename "$1")\$" "$src/sha256.txt" | cut -d' ' -f1)
    [ -z "$l" ] && return 0
    [ "$(sha256sum "$1" | cut -d' ' -f1)" = "$l" ] || { say "BAD CHECKSUM: $1"; return 1; }
}
n=0
for f in "$src"/vmlinuz.x "$src"/*.tcz; do
    [ -f "$f" ] || continue
    ok "$f" || exit 1
    case $f in */vmlinuz.x) d=$boot/vmlinuz.x ;; *) d=$TCE/optional/$(basename "$f") ;; esac
    if ! [ "$f" -ef "$d" ]; then cp "$f" "$d.new"; mv "$d.new" "$d"; fi
    ok "$d" || exit 1
    say "installed $d"; n=$((n + 1))
done
sync
grep -qx 'Xfbdev.tcz' "$TCE/onboot.lst" 2>/dev/null || { echo Xfbdev.tcz >> "$TCE/onboot.lst"; say "Xfbdev.tcz added to onboot.lst"; }
if grep -qiE '^[[:space:]]*LABEL[[:space:]]+x[[:space:]]*$' "$cfg"; then
    say "extlinux label x already present"
else
    def=$(awk 'toupper($1)=="DEFAULT"{print $2; exit}' "$cfg")
    app=$(awk -v d="$def" 'toupper($1)=="LABEL"{l=($2==d)} l && toupper($1)=="APPEND"{sub(/^[ \t]*[Aa][Pp][Pp][Ee][Nn][Dd][ \t]+/,""); print; exit}' "$cfg")
    [ -n "$app" ] || app="initrd=/boot/core.xz floppy=thinkpad atkbd.xlate=2 console=tty0 console=ttyS0,9600n8 tce=sda1"
    cp "$cfg" "$cfg.pre-x"
    printf 'LABEL x\n  KERNEL /boot/vmlinuz.x\n  APPEND %s\n' "$app" >> "$cfg"
    sync
    say "added extlinux label x (APPEND $app); old config in $cfg.pre-x"
fi
[ -f "$boot/vmlinuz.x" ] || say "note: /boot/vmlinuz.x is not there yet (deliver it, then re-run)"
say "$n file(s) installed. Reboot, type x at the boot: prompt, then run startx."
