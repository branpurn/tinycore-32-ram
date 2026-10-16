#!/bin/sh
# Static busybox for i486 (musl), config = allnoconfig + config/busybox.applets
. "$(dirname "$0")/common.sh"
tb=$(fetch "$BUSYBOX_URL" "$BUSYBOX_SHA256"); unpack "$tb" "busybox-$BUSYBOX_VER"
B="$BUILD/busybox-$BUSYBOX_VER"
cd "$B"
log "configuring busybox $BUSYBOX_VER"
make -s allnoconfig >/dev/null
grep -vE '^\s*(#|$)' "$TOP/config/busybox.applets" | while IFS= read -r l; do
    case $l in
        *=*) n=${l%%=*}; v=${l#*=}; sed -i "/^# CONFIG_$n is not set\$/d; /^CONFIG_$n=/d" .config; echo "CONFIG_$n=$v" >> .config ;;
        *)   sed -i "/^# CONFIG_$l is not set\$/d; /^CONFIG_$l=/d" .config; echo "CONFIG_$l=y" >> .config ;;
    esac
done
sed -i 's|^CONFIG_CROSS_COMPILER_PREFIX=.*|CONFIG_CROSS_COMPILER_PREFIX="'"$MUSL_TC_PREFIX"'"|' .config
sed -i 's|^CONFIG_EXTRA_CFLAGS=.*|CONFIG_EXTRA_CFLAGS="-march=i486 -mtune=i486 -Os -fno-pie"|' .config
sed -i 's|^CONFIG_EXTRA_LDFLAGS=.*|CONFIG_EXTRA_LDFLAGS="-no-pie"|' .config
yes "" | make -s oldconfig >/dev/null 2>&1
# Verify
grep -vE '^\s*(#|$)' "$TOP/config/busybox.applets" | while IFS= read -r l; do
    case $l in *=*) n=${l%%=*};; *) n=$l;; esac
    grep -q "^CONFIG_$n=" .config || echo "  busybox: CONFIG_$n not applied (dependency?)" >&2
done
log "building busybox"
make -s -j"$JOBS" busybox >/dev/null
"${MUSL_TC_PREFIX}strip" -s busybox
cp busybox "$OUT/busybox"; cp .config "$OUT/busybox.config"
log "busybox: $(stat -c %s busybox) bytes, $(./busybox --list 2>/dev/null | wc -l || true) applets"
