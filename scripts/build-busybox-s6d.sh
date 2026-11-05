#!/bin/sh
# Static busybox for the SEPARATE S6d floppy. Writes out/busybox-s6d only.
# Does not overwrite out/busybox (recovery).
. "$(dirname "$0")/common.sh"
APPLETS=${BUSYBOX_S6D_APPLETS:-$TOP/config/busybox-s6d.applets}
[ -f "$APPLETS" ] || die "missing $APPLETS"
tb=$(fetch "$BUSYBOX_URL" "$BUSYBOX_SHA256"); unpack "$tb" "busybox-$BUSYBOX_VER"
SRC="$BUILD/busybox-$BUSYBOX_VER"
DST="$BUILD/busybox-s6d-$BUSYBOX_VER"
# Fresh copy so recovery busybox tree/config stays usable
if [ ! -f "$DST/.s6d-src-stamp" ] || [ "$(cat "$DST/.s6d-src-stamp")" != "$(cat "$BUILD/.unpacked-busybox-$BUSYBOX_VER")" ]; then
    log "cloning busybox tree for s6d build"
    rm -rf "$DST"
    mkdir -p "$BUILD"
    cp -a "$SRC" "$DST"
    echo "$(cat "$BUILD/.unpacked-busybox-$BUSYBOX_VER")" > "$DST/.s6d-src-stamp"
fi
cd "$DST"
log "configuring busybox-s6d $BUSYBOX_VER"
make -s distclean >/dev/null 2>&1 || true
make -s allnoconfig >/dev/null
grep -vE '^\s*(#|$)' "$APPLETS" | while IFS= read -r l; do
    case $l in
        *=*) n=${l%%=*}; v=${l#*=}; sed -i "/^# CONFIG_$n is not set\$/d; /^CONFIG_$n=/d" .config; echo "CONFIG_$n=$v" >> .config ;;
        *)   sed -i "/^# CONFIG_$l is not set\$/d; /^CONFIG_$l=/d" .config; echo "CONFIG_$l=y" >> .config ;;
    esac
done
sed -i 's|^CONFIG_CROSS_COMPILER_PREFIX=.*|CONFIG_CROSS_COMPILER_PREFIX="'"$MUSL_TC_PREFIX"'"|' .config
sed -i 's|^CONFIG_EXTRA_CFLAGS=.*|CONFIG_EXTRA_CFLAGS="-march=i486 -mtune=i486 -Os -fno-pie"|' .config
sed -i 's|^CONFIG_EXTRA_LDFLAGS=.*|CONFIG_EXTRA_LDFLAGS="-no-pie"|' .config
yes "" | make -s oldconfig >/dev/null 2>&1
grep -vE '^\s*(#|$)' "$APPLETS" | while IFS= read -r l; do
    case $l in *=*) n=${l%%=*};; *) n=$l;; esac
    grep -q "^CONFIG_$n=" .config || echo "  busybox-s6d: CONFIG_$n not applied (dependency?)" >&2
done
# Confirm drops stayed off
for n in VI AWK FDISK LESS GZIP GUNZIP UNXZ TAR CPIO MKE2FS MKFS_VFAT MKSWAP SWAPON SWAPOFF BLOCKDEV; do
    if grep -q "^CONFIG_$n=y" .config; then die "drop leaked back on: CONFIG_$n"; fi
done
log "building busybox-s6d"
make -s -j"$JOBS" busybox >/dev/null
"${MUSL_TC_PREFIX}strip" -s busybox
cp busybox "$OUT/busybox-s6d"; cp .config "$OUT/busybox-s6d.config"
log "busybox-s6d: $(stat -c %s busybox) bytes, $(./busybox --list 2>/dev/null | wc -l || true) applets"
