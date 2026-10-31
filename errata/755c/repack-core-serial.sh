#!/bin/sh
# repack-core-serial.sh: add a serial login (getty on ttyS0) to a Tiny Core
# initramfs, writing a NEW file. The input is never modified.
#
#   sudo ./repack-core-serial.sh [-b BAUD] [-r] [-s] [-o OUT] [CORE]
#     CORE     input initramfs, gzip (stock TC core.gz) or xz (tc32 core.xz);
#              default ./core.gz
#     -o OUT   output file (default: core-serial.gz / core-serial.xz next to CORE)
#     -b BAUD  getty rate (default 115200); must match console=ttyS0,BAUD
#     -r       replace an existing active ttyS0 entry instead of keeping it
#     -s       also allow root logins on ttyS0 (uncomment it in etc/securetty)
#
# Runs on the host (or on a TC box with enough RAM), as root, so that file
# owners, modes and device nodes in the archive survive the round trip. See
# serial-getty.md for why and for what was checked against TC 16.x/17.x.
set -eu
usage() { sed -n '5,12s/^# \{0,1\}//p' "$0" >&2; exit 2; }
die() { echo "repack-core-serial: $*" >&2; exit 1; }

baud=115200 replace="" securetty="" out=""
while getopts b:rso:h o; do
    case $o in
        b) baud=$OPTARG ;; r) replace=1 ;; s) securetty=1 ;; o) out=$OPTARG ;;
        *) usage ;;
    esac
done
shift $((OPTIND - 1))
[ $# -le 1 ] || usage
in=${1:-core.gz}
case $baud in ''|*[!0-9]*) die "-b: BAUD must be a number" ;; esac
[ "$(id -u)" = 0 ] || die "must run as root (sudo), to keep owners and device nodes"
[ -f "$in" ] && [ -r "$in" ] || die "$in: not a readable file"
for t in cpio find gzip; do command -v "$t" >/dev/null || die "$t not found"; done

# Compression by magic bytes, not by file name.
magic=$(dd if="$in" bs=1 count=6 2>/dev/null | od -An -tx1 | tr -d ' \n')
case $magic in
    1f8b*)        fmt=gz; unpack="gzip -dc";  pack="gzip -9" ;;
    fd377a585a00) fmt=xz; unpack="xz -dc"
                  # tc32's own settings (scripts/mkrootfs.sh): the kernel's
                  # xz decoder needs CRC32 (or no) integrity checks.
                  pack="xz -9e --check=crc32 --lzma2=dict=1MiB -T1"
                  command -v xz >/dev/null || die "xz not found" ;;
    *) die "$in: neither gzip nor xz (magic $magic)" ;;
esac
[ -n "$out" ] || out="$(dirname "$in")/core-serial.$fmt"

inabs=$(cd "$(dirname "$in")" && pwd -P)/$(basename "$in")
outdir=$(cd "$(dirname "$out")" 2>/dev/null && pwd -P) || die "$(dirname "$out"): no such directory"
outabs=$outdir/$(basename "$out")
[ "$inabs" != "$outabs" ] || die "output would overwrite the input; pick another -o"

tmp=$(mktemp -d "${TMPDIR:-/tmp}/repack-core.XXXXXX")
[ -n "$tmp" ] && [ -d "$tmp" ] || die "mktemp failed"
trap 'rm -rf "$tmp"' EXIT INT TERM
mkdir "$tmp/root"

echo "repack-core-serial: unpacking $in ($fmt) ..."
$unpack "$in" | (cd "$tmp/root" && cpio -i -H newc -d -m 2>/dev/null) || die "unpack failed"
tab=$tmp/root/etc/inittab
[ -f "$tab" ] || die "no etc/inittab in $in (not a Tiny Core initramfs?)"

# An "active" ttyS0 entry: a non-comment inittab line for ttyS0 (busybox
# inittab: id::action:process, id = tty name without /dev/).
line="ttyS0::respawn:/sbin/getty -L $baud ttyS0 vt100"
cur=$(grep -E '^[[:space:]]*ttyS0:' "$tab" || true)
changed=""
if [ -z "$cur" ]; then
    [ -e "$tmp/root/sbin/getty" ] || [ -L "$tmp/root/sbin/getty" ] || die "no /sbin/getty in $in"
    printf '%s\n' "# Serial login on COM1 (added by repack-core-serial.sh)" "$line" >> "$tab"
    echo "repack-core-serial: added: $line"
    changed=1
elif [ -z "$replace" ]; then
    echo "repack-core-serial: $in already has a ttyS0 entry, left unchanged:"
    printf '  %s\n' "$cur"
    echo "repack-core-serial: (use -r to replace it, e.g. to change the rate)"
else
    if printf '%s\n' "$cur" | grep -q '/sbin/tc32-getty ttyS0 '; then
        # tc32: keep its autologin wrapper, change only the rate field.
        sed -i "s|^\([[:space:]]*ttyS0::respawn:/sbin/tc32-getty ttyS0 \)[0-9]*|\1$baud|" "$tab"
    else
        sed -i "s|^[[:space:]]*ttyS0:.*|$line|" "$tab"
    fi
    echo "repack-core-serial: ttyS0 entry now:"
    grep -E '^[[:space:]]*ttyS0:' "$tab" | sed 's/^/  /'
    changed=1
fi

st=$tmp/root/etc/securetty
if [ -n "$securetty" ]; then
    if [ -f "$st" ] && grep -qE '^#[[:space:]]*ttyS0[[:space:]]*$' "$st"; then
        sed -i 's/^#[[:space:]]*ttyS0[[:space:]]*$/ttyS0/' "$st"
        echo "repack-core-serial: etc/securetty: ttyS0 enabled for root"
        changed=1
    elif [ -f "$st" ] && grep -qE '^ttyS0[[:space:]]*$' "$st"; then
        echo "repack-core-serial: etc/securetty already lists ttyS0"
    else
        echo "repack-core-serial: etc/securetty has no ttyS0 line; not changed" >&2
    fi
fi

if [ -z "$changed" ]; then
    echo "repack-core-serial: nothing to change; no output written."
    exit 0
fi

echo "repack-core-serial: repacking -> $out ..."
part="$outabs.part.$$"
(cd "$tmp/root" && find . | cpio -o -H newc 2>/dev/null) | $pack > "$part" || { rm -f "$part"; die "repack failed"; }
mv "$part" "$outabs"
# Read it back: must decompress and contain the new inittab.
$unpack "$outabs" | (mkdir "$tmp/check" && cd "$tmp/check" && cpio -i -H newc -d "*etc/inittab" 2>/dev/null) \
    || die "read-back of $out failed"
cmp -s "$tab" "$tmp/check/etc/inittab" || die "read-back of $out: inittab differs"
echo "repack-core-serial: OK. $(wc -c < "$inabs") -> $(wc -c < "$outabs") bytes; $in untouched."
if command -v sha256sum >/dev/null; then sha256sum "$outabs" | sed 's|  .*/|  |'; fi
