#!/bin/sh
# BIOS reach probes for the 755C's Win98 partition (sdb1, FAT32 type 0b).
# Run on the host with the slave card in a USB reader and ONLY sdb1 mounted
# (udisksctl mount -b /dev/sdX1). No root needed.
#
#   mk-probes.sh MOUNTPOINT PARTDEV     place probes, fill the far end
#   mk-probes.sh -r MOUNTPOINT          remove \PROBE (probes and fillers)
#
# A 1994 BIOS may only reach 1024 cyl x 16 heads x 63 sectors = 504 MiB of
# a disk through INT 13h. DOS (and Setup's DOS phase) reach type-0b FAT32
# through INT 13h CHS, so past that limit a read returns the wrong sector
# and a write lands on the wrong sector (cylinder wrap: lower on the card).
# This places small text files at about 400, 500, 520, 1024 and 2040 MiB
# of the CARD (not the partition); PROBE.BAT on the W98SERIAL floppy reads
# them with FIND. Filler files hold the space between them: LOFILL* (below
# 504 MiB) are deleted at the end, HIFILL* (from ~500 MiB to the end of
# sdb1) stay, so until UNFILL.BAT deletes them DOS can only allocate below
# 504 MiB.
#
# Where a file lands: vfat has no FIEMAP for users, so positions are
# predicted from statfs. Linux allocates FAT clusters in order after the
# last one it used, so on a volume that was formatted and then only filled
# (no deletions), the next cluster is 2 + clusters in use. If PARTDEV is
# readable (run under `sg disk -c`), the real clusters are read back with
# mshowfat/minfo (mtools) and printed too; otherwise the error of the
# prediction is "files land later than predicted, if the volume has holes".
set -eu
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
usage() { sed -n '6,7s/^# \{0,1\}//p' "$0"; exit 2; }
if [ "${1:-}" = -r ]; then
    [ $# -eq 2 ] || usage
    [ -d "$2/PROBE" ] || die "no $2/PROBE"
    rm -f "$2"/PROBE/*; rmdir "$2/PROBE"; sync; echo "removed $2/PROBE"; exit 0
fi
[ $# -eq 2 ] || usage
M=$1 P=$2 pn=$(basename "$2")
awk -v p="$P" -v m="$M" '$1 == p && $2 == m && $3 == "vfat" {f=1} END {exit !f}' /proc/mounts ||
    die "$P is not mounted as vfat on $M"
START=$(cat "/sys/class/block/$pn/start") SIZE=$(cat "/sys/class/block/$pn/size")
END=$((START + SIZE))
CL=$(stat -f -c %S "$M") TOTCL=$(stat -f -c %b "$M")
SPC=$((CL / 512))
# statfs f_blocks = data clusters - 2 (FAT entries 0 and 1); the data area
# may also have a few trailing sectors (< SPC), so this can be early by < SPC.
DS=$((SIZE - (TOTCL + 2) * SPC))
EXACT=
if [ -r "$P" ] && command -v mshowfat >/dev/null; then
    export MTOOLS_SKIP_CHECK=1
    DS=$(minfo -i "$P" :: | awk '/^reserved \(boot\) sectors:/ {r=$4} /^fats:/ {f=$2}
        /^Big fatlen=/ {sub(/.*=/, ""); l=$0} END {print r + f * l}')
    EXACT=1
fi
used() { stat -f -c '%b %f' "$M" | awk '{print $1 - $2}'; }
nextlba() { echo $((START + DS + $(used) * SPC)); }
realba() { # disk LBA of the first cluster of \PROBE\$1, or "-"
    [ -n "$EXACT" ] || { echo -; return; }
    c=$(mshowfat -i "$P" "::PROBE/$1" | sed -n 's/.*<\([0-9]*\).*/\1/p')
    echo $((START + DS + (c - 2) * SPC))
}
D=$M/PROBE
[ -e "$D" ] && die "$D exists; remove it first with -r"
mkdir "$D"; sync

echo "partition: start LBA $START, $SIZE sectors, end LBA $END; cluster $CL bytes;" \
     "data area at partition LBA $DS${EXACT:+ (read from the BPB)}"
echo "504 MiB CHS limit (1024x16x63) = disk LBA 1032192"
printf '%-7s %10s %9s %10s\n' file predicted MiB actual
for spec in LOFILL1:400:P0400 LOFILL2:500:P0500 HIFILL0:520:P0520 HIFILL1:1024:P1024 HIFILL2:2040:P2040; do
    fl=${spec%%:*} rest=${spec#*:}; mib=${rest%%:*} pr=${rest#*:}
    t=$((mib * 2048))
    [ $t -lt $END ] || die "target $mib MiB is past the end of the partition"
    n=$(( (t - $(nextlba)) / SPC * CL ))
    [ $n -gt 0 ] || die "next free LBA $(nextlba) is already past $mib MiB"
    head -c "$n" /dev/zero > "$D/$fl.BIN" || die "filler $fl failed (disk full?)"
    sync
    lba=$(nextlba)
    printf 'W98PROBE %s at about %s MiB of the slave card (disk LBA %d)\r\n\032' \
        "$pr" "$mib" "$lba" > "$D/$pr.TXT"
    sync
    printf '%-7s %10d %9s %10s\n' "$pr" "$lba" \
        "$(awk -v l="$lba" 'BEGIN {printf "%.1f", l / 2048}')" "$(realba "$pr.TXT")"
done
# Hold the rest of the partition.
cat /dev/zero > "$D/HIFILL3.BIN" 2>/dev/null || true
sync
for f in HIFILL0 HIFILL1 HIFILL2 HIFILL3; do
    printf '%-7s starts at disk LBA %10s (actual)\n' $f "$(realba $f.BIN)"
done
rm -f "$D/LOFILL1.BIN" "$D/LOFILL2.BIN"; sync
ls -l "$D"
df -B1M "$M" | tail -1
