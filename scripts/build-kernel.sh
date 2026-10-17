#!/bin/sh
# Build an i486 bzImage from tinyconfig + config/kernel-*.fragment.
# Usage: build-kernel.sh [fragment-name ...]   (default: base hdd tce modules)
. "$(dirname "$0")/common.sh"
FRAGS=${*:-${KERNEL_FRAGMENTS:-base hdd tce modules}}
tb=$(fetch "$LINUX_URL" "$LINUX_SHA256"); unpack "$tb" "linux-$LINUX_VER"
K="$BUILD/linux-$LINUX_VER"
KO="$BUILD/kernel-obj"
mkdir -p "$KO"
set --
for f in $FRAGS; do set -- "$@" "$TOP/config/kernel-$f.fragment"; done
cd "$K"
log "configuring linux $LINUX_VER (tinyconfig + $FRAGS)"
make -s O="$KO" ARCH=i386 tinyconfig
KCONFIG_CONFIG="$KO/.config" scripts/kconfig/merge_config.sh -m -O "$KO" "$KO/.config" "$@" >/dev/null
make -s O="$KO" ARCH=i386 olddefconfig
# Verify every requested option survived dependency resolution.
bad=0
for frag in "$@"; do
  grep -E '^(CONFIG_|# CONFIG_)' "$frag" | while IFS= read -r line; do
    grep -qxF "$line" "$KO/.config" || { echo "  kconfig mismatch: want '$line', got '$(grep -E "(^|# )${line#\# }" "$KO/.config" | head -1; grep -E "^$(echo "$line" | sed -E 's/^# //; s/[= ].*//')[= ]" "$KO/.config")'" >&2; }
  done
done
log "building bzImage (-j$JOBS)"
make -s O="$KO" ARCH=i386 -j"$JOBS" bzImage
cp "$KO/arch/x86/boot/bzImage" "$OUT/bzImage"
cp "$KO/.config" "$OUT/kernel.config"
log "bzImage: $(stat -c %s "$OUT/bzImage") bytes"
