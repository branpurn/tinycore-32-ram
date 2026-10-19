#!/bin/sh
# Send a file to tc32 over its serial console with XMODEM-1K (sx -> busybox rx),
# switching both ends to a faster rate for the transfer, then verify sha256.
#
#   tools/send-file.sh [-b BAUD] [-c BAUD] FILE TTY [REMOTE_PATH]
#     FILE         local file
#     TTY          the console serial line, e.g. /dev/ttyUSB0
#     REMOTE_PATH  destination on tc32 (default /tmp/<name of FILE>)
#     -b BAUD      transfer rate (default 57600; equal to -c = no switching)
#     -c BAUD      console rate (default 9600, as configured on tc32)
#
# Before running: tc32 must be at a shell prompt on that console, and no
# terminal program may hold the port (quit picocom with C-a C-q, which leaves
# the line alone, or C-a C-x). Needs sx/lsx (lrzsz); `make tools` builds one
# into build/host/bin if the host has none. Exit status 0 = checksum match.
set -eu
usage() { sed -n '5,10s/^# \{0,1\}//p' "$0" >&2; exit 2; }
# 57600: at 115200 the 755C's UART overruns (measured 1.9 KB/s with many CRC
# retries for a 1 MiB kernel); 57600 should give ~4.5 KB/s (estimate).
baud=57600 cbaud=9600
while getopts b:c:h o; do
    case $o in b) baud=$OPTARG ;; c) cbaud=$OPTARG ;; *) usage ;; esac
done
shift $((OPTIND - 1))
[ $# -ge 2 ] && [ $# -le 3 ] || usage
file=$1 tty=$2 remote=${3:-/tmp/$(basename "$1")}
[ -f "$file" ] && [ -r "$file" ] || { echo "send-file: $file: not a readable file" >&2; exit 1; }
[ -c "$tty" ] || { echo "send-file: $tty: not a character device" >&2; exit 1; }
here=$(cd "$(dirname "$0")/.." && pwd)
SX=${SX:-$(command -v sx || command -v lsx || command -v lrzsz-sx || echo "$here/build/host/bin/sx")}
[ -x "$SX" ] || { echo "send-file: no sx found (install lrzsz, or run 'make tools')" >&2; exit 1; }

size=$(stat -c %s "$file")
sum=$(sha256sum "$file" | cut -d' ' -f1)
tmp=$(mktemp -d); catpid=""
trap 'exec 3>&-; [ -n "$catpid" ] && kill "$catpid" 2>/dev/null; rm -rf "$tmp"' EXIT INT TERM
# XMODEM pads the last block with ^Z and busybox rx strips >= 3 trailing ^Z,
# so the received size is not exact. Send a copy padded with zeros to a 1 KiB
# multiple (at least one zero byte) and cut it back to $size with head -c.
pad=$((1024 - size % 1024))
{ cat "$file"; head -c "$pad" /dev/zero; } > "$tmp/payload"

line() { stty -F "$tty" "$1" cs8 -cstopb -parenb clocal -crtscts -ixon -ixoff raw -echo min 1 time 0; }
exec 3<>"$tty"
line "$cbaud"
part="$remote.part"
# rx's error messages go to a file, not into the XMODEM stream on the same
# line. (busybox 1.37 rx exits 1 on success, so its status is not used; the
# size and sha256 checks below decide.)
# Kernel messages on the console (e.g. "random: crng init done") would land
# in the middle of the protocol, so the console loglevel is lowered to 1 for
# the transfer and restored afterwards (7, or 4 when booted with quiet).
# rx sends its first 'C' (start request) at once and only repeats it after
# 10 s, so tc32 sleeps until this end has finished reading the echo and is
# listening at the transfer rate.
w=$(( 400 * 20 / cbaud + 1 ))         # seconds to let the echoed command line drain
rx="sleep $((w + 1)); rx $part 2>/tmp/rx.err"
if [ "$baud" = "$cbaud" ]; then
    rcmd="$rx"
else
    rcmd="stty $baud; $rx; stty $cbaud"
fi
rcmd="mkdir -p $(dirname "$remote"); L=7; grep -qw quiet /proc/cmdline && L=4; [ -r /proc/sys/kernel/printk ] && read L x < /proc/sys/kernel/printk; dmesg -n 1; $rcmd; dmesg -n \$L"
# The marker is printed as XFER-END<n>=done (n = bytes received); the echoed
# command line reads XFER-END"$n"=done, which does not match the pattern.
rcmd="$rcmd; n=\$(wc -c < $part); head -c $size $part > $remote; rm -f $part; cat /tmp/rx.err; sha256sum $remote; echo XFER-END\"\$n\"=done"
echo "send-file: $file ($size bytes) -> $remote, console $cbaud, transfer $baud baud"
printf '\025%s\r' "$rcmd" >&3         # ^U clears anything half-typed at the prompt
# Let the command echo back at console speed while tc32 switches its UART.
timeout "$w" cat <&3 > /dev/null || true
line "$baud"
t0=$(date +%s.%N)
if "$SX" -k "$tmp/payload" <&3 >&3; then sxrc=0; else sxrc=$?; fi
t1=$(date +%s.%N)
line "$cbaud"
cat <&3 > "$tmp/out" & catpid=$!
i=0
until grep -qE 'XFER-END[0-9]+=done' "$tmp/out" 2>/dev/null; do
    i=$((i + 1)); [ $i -lt 1200 ] || break
    sleep 0.25
done
kill "$catpid" 2>/dev/null || true; catpid=""
got=$(grep -oE 'XFER-END[0-9]+=done' "$tmp/out" | head -1 | tr -dc 0-9)
rsum=$(grep -oE "^[0-9a-f]{64}  $remote" "$tmp/out" | head -1 | cut -d' ' -f1 || true)
secs=$(echo "$t0 $t1" | awk '{printf "%.1f", $2 - $1}')
rate=$(echo "$t0 $t1 $size" | awk '{d = $2 - $1; printf "%d", (d > 0 ? $3 / d : 0)}')
grep -E '^rx: ' "$tmp/out" | sed 's/^/send-file: remote /' || true
echo "send-file: sx exit $sxrc, received ${got:-?} of $((size + pad)) bytes; $size bytes in $secs s = $rate B/s at $baud baud"
echo "send-file: local  sha256 $sum"
echo "send-file: remote sha256 ${rsum:-<none>}"
if [ "$sxrc" = 0 ] && [ "$rsum" = "$sum" ]; then
    echo "send-file: OK, checksums match"
else
    echo "send-file: FAILED (see output above; retry, or use a lower -b)" >&2; exit 1
fi
