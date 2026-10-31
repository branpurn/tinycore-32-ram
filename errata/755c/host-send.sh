#!/bin/sh
# Send files from the host to the 755C's tcdata partition over the serial
# console, then send a SHA256SUMS list that `install-dualcf finish` checks.
#
#   errata/755c/host-send.sh [-b BAUD] [-c BAUD] [-d DIR] TTY FILE...
#     TTY     the host's serial port to the 755C, e.g. /dev/ttyUSB0 (FTDI)
#     FILE    vmlinuz, core.xz or core.gz, menu.c32, chain.c32, onboot.lst, *.tcz
#     -b/-c   transfer / console baud, passed to tools/send-file.sh (38400 / 9600)
#     -d DIR  target directory (default /mnt/tcdata/incoming)
#
# On the 755C first: mkdir -p /mnt/tcdata && mount -t ext2 /dev/sdb2 /mnt/tcdata
# and leave it at the shell prompt. Each file is checked by send-file.sh
# (sha256 on both ends); install-dualcf finish checks them all again.
set -eu
usage() { sed -n '5,10s/^# \{0,1\}//p' "$0" >&2; exit 2; }
here=$(cd "$(dirname "$0")/../.." && pwd)
opts="" dir=/mnt/tcdata/incoming
while getopts b:c:d:h o; do
    case $o in
        b) opts="$opts -b $OPTARG" ;; c) opts="$opts -c $OPTARG" ;;
        d) dir=$OPTARG ;; *) usage ;;
    esac
done
shift $((OPTIND - 1))
[ $# -ge 2 ] || usage
tty=$1; shift
for f; do
    case $(basename "$f") in *[!A-Za-z0-9._+-]*) echo "host-send: $f: rename it (letters, digits, . _ + - only)" >&2; exit 1 ;; esac
    [ -f "$f" ] || { echo "host-send: $f: not a file" >&2; exit 1; }
done
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT INT TERM
for f; do
    echo "== $(basename "$f") ($(stat -c %s "$f") bytes)"
    # shellcheck disable=SC2086 # $opts holds separate words on purpose
    "$here/tools/send-file.sh" $opts "$f" "$tty" "$dir/$(basename "$f")"
    ( cd "$(dirname "$f")" && sha256sum "$(basename "$f")" ) >> "$tmp/SHA256SUMS"
done
echo "== SHA256SUMS"
# shellcheck disable=SC2086
"$here/tools/send-file.sh" $opts "$tmp/SHA256SUMS" "$tty" "$dir/SHA256SUMS"
echo "All sent. On the 755C run: install-dualcf finish"
