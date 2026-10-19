#!/bin/sh
# Send the graphics second stage to the 755C over the serial console, one
# file at a time with tools/send-file.sh, into /mnt/sda1/gfx/ (sha256 checked
# per file). Then, on the 755C:  sh /mnt/sda1/gfx/gfx-setup.sh
#
#   tools/send-gfx.sh [-b BAUD] [-a] [-n] TTY [FILE...]
#     TTY      console serial line, e.g. /dev/ttyUSB0 (often needs sudo/dialout)
#     FILE...  only these (names as in the plan, e.g. Xlibs.tcz) to resume
#     -b BAUD  transfer rate (default 38400: the only rate reliable on the 755C)
#     -a       also send Xaw-apps.tcz (xclock, xcalc, xeyes; optional)
#     -n       print the plan and time estimates only (no TTY used)
# Files come from out/gfx (make gfx) and out/gfx/755c (make gfx-755c).
set -eu
here=$(cd "$(dirname "$0")/.." && pwd)
usage() { sed -n '6,12s/^# \{0,1\}//p' "$0" >&2; exit 2; }
baud=38400 all= dry= dest=/mnt/sda1/gfx
while getopts b:anh o; do
    case $o in b) baud=$OPTARG ;; a) all=1 ;; n) dry=1 ;; *) usage ;; esac
done
shift $((OPTIND - 1))
[ -n "$dry" ] || [ $# -ge 1 ] || usage
tty=${1:-}; [ $# -ge 1 ] && shift
G=$here/out/gfx K=$here/out/gfx/755c
# smallest first: the setup script and drivers arrive early, the kernel last
files="$here/tools/gfx-setup.sh $K/trackpoint.tcz $G/rxvt.tcz $K/fb-wd90c24.tcz $G/jwm.tcz $K/modutils.tcz $G/Xfbdev.tcz"
[ -n "$all" ] && files="$files $G/Xaw-apps.tcz"
files="$files $G/Xlibs.tcz $K/vmlinuz.x"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT INT TERM
for f in $files; do [ -f "$f" ] || { echo "send-gfx: missing $f (make gfx gfx-755c)" >&2; exit 1; }; done
( for f in $files; do printf '%s  %s\n' "$(sha256sum "$f" | cut -d' ' -f1)" "$(basename "$f")"; done ) > "$tmp/sha256.txt"
files="$tmp/sha256.txt $files"
# B/s measured on the 755C: its side caps 115200/57600/38400 at ~1.9 KB/s
# (~1.4 KB/s while X runs; X_RUNNING=1 uses that). 19200/9600 = estimates.
# .dep files are not sent: startx loads the dependencies itself.
rate() {
    if [ -n "$X_RUNNING" ]; then echo 1400; return; fi
    case $1 in 115200|57600|38400) echo 1900 ;; 19200) echo 1700 ;; 9600) echo 900 ;; *) echo $(($1 / 13)) ;; esac
}
r=$(rate "$baud")
tot=0 sel=
for f in $files; do
    b=$(basename "$f")
    if [ $# -gt 0 ]; then case " $* " in *" $b "*) ;; *) continue ;; esac; fi
    sel="$sel $f"; s=$(stat -c %s "$f"); tot=$((tot + s))
    printf 'send-gfx: %-16s %8d bytes  ~%4d s at %s baud\n' "$b" "$s" $(( (s + 1023) / r + 4 )) "$baud"
done
n=$(echo $sel | wc -w)
printf 'send-gfx: %d files, %d bytes, ~%d min at %s baud (%d B/s; 38400 and up = measured, ~1400 with X running)\n' \
    "$n" "$tot" $(( (tot / r + n * 4 + 59) / 60 )) "$baud" "$r"
[ -z "$dry" ] || exit 0
for f in $sel; do
    "$here/tools/send-file.sh" -b "$baud" "$f" "$tty" "$dest/$(basename "$f")" \
        || { echo "send-gfx: $(basename "$f") failed; resume with: $0 -b $baud $tty $(basename "$f") ..." >&2; exit 1; }
done
echo "send-gfx: done. On the 755C:  sh $dest/gfx-setup.sh $dest   (then reboot, label x, startx)"
