#!/bin/sh
# install-dualcf: set up the ThinkPad 755C dual-CF layout from the tc32
# installer floppy. busybox ash; builds on install-to-disk. See INSTALL.md.
#
#   install-dualcf [-b BAUD] [-s MB] [-w MB] [-f MB] [-t HEX] [-n] detect|prepare|finish
#     detect   list the IDE disks (master/slave), change nothing
#     prepare  ERASE both cards: master = tc32 boot disk (install-to-disk),
#              slave = p1 FAT32 for Win98 SE + p2 ext2 LABEL=tcdata
#     finish   verify incoming/SHA256SUMS on tcdata, install the received
#              files, write the menu extlinux.conf (tc / win98 / rescue)
#     -b BAUD  serial console speed in extlinux.conf (default 9600)
#     -s MB    master boot partition (default 256)  -w MB  master swap (default 64)
#     -f MB    slave FAT32 partition (default 2048) -t HEX FAT type (default 0b)
#     -n       dry run (detect + plan only)
#
# libata (pata_legacy) names the IDE master sda and the slave sdb; the old
# hda/hdb names do not exist on this kernel. Nothing is written before the
# exact confirmation text is typed.
PATH=/usr/sbin:/usr/bin:/sbin:/bin; export PATH
set -u
SHARE=/usr/share/tc32
BAUD=9600 P1MB=256 SWAPMB=64 FATMB=2048 FATTYPE=0b DRY=""
BOOTMNT=/mnt/tc32-target DATAMNT=/mnt/tcdata
die() { echo "install-dualcf: $*" >&2; exit 1; }
usage() { sed -n '5,15s/^# \{0,1\}//p' "$0"; exit 2; }
while getopts b:s:w:f:t:nh o; do
    case $o in
        b) BAUD=$OPTARG ;; s) P1MB=$OPTARG ;; w) SWAPMB=$OPTARG ;;
        f) FATMB=$OPTARG ;; t) FATTYPE=$OPTARG ;; n) DRY=1 ;; *) usage ;;
    esac
done
shift $((OPTIND - 1))
[ $# -eq 1 ] || usage
CMD=$1
case $BAUD$P1MB$SWAPMB$FATMB in *[!0-9]*) die "numbers only for -b/-s/-w/-f" ;; esac
case $FATTYPE in 0b|0c|0B|0C) ;; *) die "-t: 0b (FAT32 CHS) or 0c (FAT32 LBA)" ;; esac
[ "$(id -u)" = 0 ] || die "must run as root"

# --- detect: map sdX to IDE master/slave via the SCSI address H:C:T:L ----
MASTER="" SLAVE=""
detect() {
    echo "IDE disks seen by the kernel:"
    for s in /sys/block/sd*; do
        [ -d "$s/device" ] || continue
        d=${s##*/}
        hctl=$(cd "$s/device" 2>/dev/null && pwd -P); hctl=${hctl##*/}
        t=$(echo "$hctl" | cut -d: -f3)
        mb=$(( $(cat "$s/size") / 2048 ))
        model=$(sed 's/ *$//' "$s/device/model" 2>/dev/null)
        case $t in 0) role=master ;; 1) role=slave ;; *) role="target $t" ;; esac
        echo "  /dev/$d  $role  ($hctl)  $mb MB  ${model:-?}"
        if [ "$t" = 0 ] && [ -z "$MASTER" ]; then MASTER=$d; fi
        if [ "$t" = 1 ] && [ -z "$SLAVE" ]; then SLAVE=$d; fi
    done
    echo "Kernel messages:"
    dmesg | grep -iE 'ata[0-9]|sd[a-z]|hd[a-z]|pata' | sed 's/^/  /' | tail -n 20
    echo "/proc/partitions:"
    sed 's/^/  /' /proc/partitions
    echo "Master: ${MASTER:-NOT FOUND}   Slave: ${SLAVE:-NOT FOUND}"
}

# shellcheck disable=SC2059 # octal escape built on purpose
oct() { for b; do printf "\\$(printf %03o "$b")"; done; }
le32() { oct $(($1 & 255)) $(($1 >> 8 & 255)) $(($1 >> 16 & 255)) $(($1 >> 24 & 255)); }
chs() {
    c=$(($1 / 1008)) h=$(($1 / 63 % 16)) s=$(($1 % 63 + 1))
    if [ "$c" -gt 1023 ]; then oct 254 255 255; else oct "$h" $((s | (c >> 2 & 192))) $((c & 255)); fi
}
part() { oct "$1"; chs "$3"; oct "$2"; chs $(($3 + $4 - 1)); le32 "$3"; le32 "$4"; }

release() { # unmount / swapoff every partition of $1
    awk -v d="$1" '$4 ~ "^"d"[0-9]+$" {print $4}' /proc/partitions | while read -r p; do
        swapoff "/dev/$p" 2>/dev/null
        awk -v p="/dev/$p" '$1 == p {print $2}' /proc/mounts | while read -r m; do umount "$m" || umount -l "$m"; done
    done
    grep -q "^/dev/$1[0-9]* " /proc/mounts && die "a partition of /dev/$1 is still mounted"
    return 0
}

write_extlinux() { # $1 = mounted boot partition
    b=$1/boot e=$b/extlinux c=$e/extlinux.conf
    if [ -f "$b/core.gz" ]; then
        TCI="initrd=/boot/core.gz tce=LABEL=tcdata home=LABEL=tcdata opt=LABEL=tcdata"
    else
        TCI="initrd=/boot/core.xz floppy=thinkpad atkbd.xlate=2 tce=${SLAVE}2"
    fi
    RCI="initrd=/boot/core.xz floppy=thinkpad atkbd.xlate=2 tce=${MASTER}1 norestore"
    CON="console=tty0 console=ttyS0,${BAUD}n8"
    {
        echo "# ThinkPad 755C dual CF (written by install-dualcf). See errata/755c."
        echo "SERIAL 0 $BAUD"
        [ -f "$e/menu.c32" ] && { echo "UI menu.c32"; echo "MENU TITLE ThinkPad 755C"; }
        echo "DEFAULT tc"
        echo "PROMPT 1"
        echo "TIMEOUT 50"
        echo "SAY 755C: tc (default, 5 s)  win98  rescue"
        echo "LABEL tc"
        echo "  MENU LABEL Tiny Core (tce on ${SLAVE}2 tcdata)"
        echo "  KERNEL /boot/vmlinuz"
        echo "  APPEND $TCI $CON"
        echo "LABEL win98"
        echo "  MENU LABEL Windows 98 SE (${SLAVE}1, BIOS disk 1)"
        echo "  COM32 chain.c32"
        echo "  APPEND hd1 1 swap"
        echo "LABEL rescue"
        echo "  MENU LABEL Rescue (core.xz, tce on ${MASTER}1, no restore)"
        echo "  KERNEL /boot/vmlinuz"
        echo "  APPEND $RCI $CON"
    } > "$c.new" || die "cannot write $c"
    mv "$c.new" "$c" || die "cannot write $c"
    [ -f "$e/chain.c32" ] || echo "  note: $e/chain.c32 missing; win98 will not boot until 'finish' installs it"
    return 0
}

detect
[ -n "$MASTER" ] || die "no IDE master disk"
[ -n "$SLAVE" ] || die "no IDE slave disk"
case $CMD in
detect) exit 0 ;;
prepare)
    SEC=$(cat "/sys/block/$SLAVE/size")
    S1=2048 N1=$((FATMB * 2048)); S2=$((S1 + N1)); S2=$(( (S2 + 2047) / 2048 * 2048 ))
    N2=$((SEC - S2))
    [ "$N2" -ge $((64 * 2048)) ] || die "/dev/$SLAVE too small for ${FATMB} MB FAT32 + tcdata"
    echo
    echo "Plan:"
    echo "  /dev/$MASTER  install-to-disk -s $P1MB -w $SWAPMB: ${MASTER}1 ext2 TC32 boot + extlinux + MBR, ${MASTER}2 swap"
    echo "  /dev/$SLAVE  ${SLAVE}1 $FATMB MB FAT32 (type $FATTYPE, active) for Win98 SE"
    echo "              ${SLAVE}2 $((N2 / 2048)) MB ext2 LABEL=tcdata (tce/ home/ opt/ incoming/)"
    install-to-disk -n -s "$P1MB" -w "$SWAPMB" "/dev/$MASTER" >/dev/null || die "install-to-disk dry run failed"
    [ -n "$DRY" ] && { echo "Dry run (-n): nothing written."; exit 0; }
    echo
    echo "*** ALL DATA ON /dev/$MASTER AND /dev/$SLAVE WILL BE DESTROYED. ***"
    want="ERASE $MASTER $SLAVE"
    printf 'Type "%s" to continue, anything else aborts: ' "$want"
    read -r ans || ans=""
    [ "$ans" = "$want" ] || { echo "Aborted; nothing was written."; exit 1; }
    echo YES | install-to-disk -s "$P1MB" -w "$SWAPMB" "/dev/$MASTER" || die "install-to-disk failed"
    release "$SLAVE"
    D=/dev/$SLAVE
    echo "Partitioning $D ..."
    dd if=/dev/zero of="$D" bs=512 count=2048 2>/dev/null || die "write error on $D"
    dd if=/dev/zero of="$D" bs=512 seek="$S1" count=64 2>/dev/null
    dd if=/dev/zero of="$D" bs=512 seek="$S2" count=64 2>/dev/null
    { cat "$SHARE/mbr.bin"; oct 135 4 50 124 0 0
      part 128 $((0x$FATTYPE)) "$S1" "$N1"; part 0 131 "$S2" "$N2"
      dd if=/dev/zero bs=32 count=1 2>/dev/null; oct 85 170; } > /tmp/slave.mbr
    [ "$(wc -c < /tmp/slave.mbr)" -eq 512 ] || die "internal error: MBR is not 512 bytes"
    dd if=/tmp/slave.mbr of="$D" bs=512 count=1 2>/dev/null || die "cannot write the MBR of $D"
    sync; blockdev --rereadpt "$D" || die "kernel did not re-read $D"
    i=0; while [ ! -b "${D}2" ] && [ $i -lt 10 ]; do sleep 1; i=$((i + 1)); done
    [ -b "${D}2" ] || die "${D}2 did not appear"
    echo "Making FAT32 on ${D}1 (placeholder; Win98 FORMAT C: /S rewrites it) ..."
    mkfs.vfat -n WIN98SE "${D}1" >/dev/null || die "mkfs.vfat failed"
    echo "Making ext2 tcdata on ${D}2 (slow on a 486 for a large card) ..."
    mke2fs -F -L tcdata -m 1 -i 262144 -I 128 "${D}2" >/dev/null || die "mke2fs failed"
    mkdir -p "$BOOTMNT" "$DATAMNT"
    mount -t ext2 "${D}2" "$DATAMNT" || die "cannot mount ${D}2"
    mkdir -p "$DATAMNT/tce/optional" "$DATAMNT/home" "$DATAMNT/opt" "$DATAMNT/incoming"
    : > "$DATAMNT/tce/onboot.lst"
    mount -t ext2 "/dev/${MASTER}1" "$BOOTMNT" || die "cannot mount /dev/${MASTER}1"
    [ -d "$BOOTMNT/tce" ] && cp -a "$BOOTMNT/tce/." "$DATAMNT/tce/"
    write_extlinux "$BOOTMNT"
    sync; umount "$BOOTMNT"; umount "$DATAMNT"
    echo "Done. Send files to ${SLAVE}2:/incoming (host-send.sh), then run: install-dualcf finish"
    ;;
finish)
    mkdir -p "$BOOTMNT" "$DATAMNT"
    grep -q " $DATAMNT " /proc/mounts || mount -t ext2 "/dev/${SLAVE}2" "$DATAMNT" || die "cannot mount /dev/${SLAVE}2"
    IN=$DATAMNT/incoming
    [ -s "$IN/SHA256SUMS" ] || die "$IN/SHA256SUMS missing"
    grep -vqE '^[0-9a-f]{64}  [A-Za-z0-9._+-]+$' "$IN/SHA256SUMS" && die "$IN/SHA256SUMS: bad line format"
    ( cd "$IN" && sha256sum -c SHA256SUMS ) || die "checksum mismatch: resend the files"
    echo "Checksums OK. Files to install:"
    sed 's/^[0-9a-f]*  /  /' "$IN/SHA256SUMS"
    [ -n "$DRY" ] && { echo "Dry run (-n): nothing installed."; exit 0; }
    grep -q " $BOOTMNT " /proc/mounts || mount -t ext2 "/dev/${MASTER}1" "$BOOTMNT" || die "cannot mount /dev/${MASTER}1"
    B=$BOOTMNT/boot
    while read -r _ f; do
        case $f in
            vmlinuz|core.gz|core.xz) dst=$B/$f ;;
            menu.c32|chain.c32|libutil.c32|libcom32.c32) dst=$B/extlinux/$f ;;
            onboot.lst) dst=$DATAMNT/tce/$f ;;
            *.tcz|*.tcz.dep|*.tcz.md5.txt) dst=$DATAMNT/tce/optional/$f ;;
            *) echo "  skip $f (unknown)"; continue ;;
        esac
        cp "$IN/$f" "$dst.new" || die "install $f failed"
        mv "$dst.new" "$dst" || die "install $f failed"
        echo "  $f -> $dst"
    done < "$IN/SHA256SUMS"
    write_extlinux "$BOOTMNT"
    ( cd "$B" && sha256sum vmlinuz core.* > sha256.txt )
    [ -f "$B/core.gz" ] && [ "$(awk '/MemTotal/{print $2}' /proc/meminfo)" -lt 47104 ] \
        && echo "  WARNING: core.gz (stock Tiny Core) needs about 46 MB RAM; the 755C has at most 36 MB"
    sync; umount "$BOOTMNT"; umount "$DATAMNT"
    mount -t ext2 -o ro "/dev/${MASTER}1" "$BOOTMNT" || die "cannot remount"
    ( cd "$BOOTMNT/boot" && sha256sum -c -s sha256.txt ); ok=$?
    umount "$BOOTMNT"
    [ $ok -eq 0 ] || die "verification FAILED on /dev/${MASTER}1"
    echo "Verified. Remove the floppy and type: reboot"
    ;;
*) usage ;;
esac
