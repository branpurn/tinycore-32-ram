#!/bin/sh
# Build the W98SERIAL boot floppy: the Win98 SE CD's own boot floppy image
# (El Torito), with the console moved to COM1 9600 8N1 and the check and
# setup batch files from floppy/. No root needed (mtools).
#
#   mk-win98-floppy.sh WIN98SE.ISO [OUTPUT.img]
#     OUTPUT  default ./w98serial.img
#
# Needs: xorriso, mtools, cabextract. The output is not committed: it
# contains Microsoft files. Write it with dd (see WIN98-INSTALL.md).
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
[ $# -ge 1 ] || { sed -n '5,7s/^# \{0,1\}//p' "$0"; exit 2; }
ISO=$1 IMG=${2:-w98serial.img}
for t in xorriso mcopy cabextract; do command -v $t >/dev/null || die "$t not found"; done
export TZ=UTC MTOOLS_SKIP_CHECK=1
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT

# 1. The El Torito floppy image (1.44 MB emulation; extract_boot_images
#    rounds it up to 2 KB blocks, so keep the first 2880 sectors).
xorriso -osirrox on -indev "$ISO" -extract_boot_images "$T/et" >/dev/null 2>&1 ||
    die "cannot extract the boot image from $ISO"
BI=$(ls "$T"/et/*img1* 2>/dev/null | head -1)
[ -n "$BI" ] || die "no boot image found in $ISO"
head -c 1474560 "$BI" > "$T/f.img"
mdir -a -i "$T/f.img" ::IO.SYS >/dev/null 2>&1 || die "boot image has no IO.SYS"

# 2. DOS tools from the CD's cabinet set. The Win98 cabinets form one
#    spanned set, so extract the whole \WIN98 folder (about 175 MB in $T).
mkdir "$T/x"
xorriso -osirrox on -indev "$ISO" -extract /win98 "$T/w98" >/dev/null 2>&1 ||
    die "cannot extract /win98"
chmod -R u+w "$T/w98"
for f in mode.com fc.exe find.exe debug.exe mem.exe sys.com; do
    cabextract -q -F "$f" -d "$T/x" "$T/w98/BASE4.CAB" >/dev/null 2>&1 || true
    [ -s "$T/x/$f" ] || die "$f not found in the cabinets"
done

# 3. Text files with CRLF line ends.
for f in "$HERE"/floppy/*; do sed 's/\r*$/\r/' "$f" > "$T/$(basename "$f")"; done

# 4. Into the image: replace CONFIG.SYS and AUTOEXEC.BAT (no CD-ROM
#    menu, no RAM drive), add the tools and batch files. The CD-ROM
#    drivers and EBD.CAB stay; they are simply not loaded.
mattrib -i "$T/f.img" -r -s -h ::CONFIG.SYS ::AUTOEXEC.BAT 2>/dev/null || true
# JO.SYS is the CD's "Boot from Hard Disk / Boot from CD-ROM" menu; IO.SYS
# runs it first when present and it defaults to the hard disk. Remove it so
# the floppy goes straight to DOS (and the COM1 console) with no input.
mattrib -i "$T/f.img" -r -s -h ::JO.SYS 2>/dev/null || true
mdel -i "$T/f.img" ::JO.SYS 2>/dev/null || true
mdir -a -i "$T/f.img" ::JO.SYS >/dev/null 2>&1 && die "JO.SYS still in image"
for f in "$T"/x/* "$T"/CONFIG.SYS "$T"/AUTOEXEC.BAT "$T"/*.BAT "$T"/GEO.SCR "$T"/README.TXT; do
    n=$(basename "$f" | tr a-z A-Z)
    mcopy -o -m -i "$T/f.img" "$f" "::$n" || die "mcopy $n"
done
mlabel -i "$T/f.img" ::W98SERIAL
mdir -i "$T/f.img" -w :: >&2
cp "$T/f.img" "$IMG"
printf '%s  %s\n' "$(sha256sum < "$IMG" | cut -d' ' -f1)" "$IMG"
