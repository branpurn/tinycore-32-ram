#!/bin/sh
# Print the size budget of the current build.
. "$(dirname "$0")/common.sh"
img=$OUT/tc32.img
k=$(stat -c %s "$OUT/bzImage"); i=$(stat -c %s "$OUT/core.xz"); c=$(stat -c %s "$BUILD/core.cpio")
fatfree() { MTOOLS_SKIP_CHECK=1 mdir -i "$1" ::/ 2>/dev/null | awk '/bytes free/{gsub(/[^0-9]/,""); print}'; }
free=$(fatfree "$img")
echo; printf '  %-28s %9s bytes (%4d KiB)\n' "kernel (vmlinuz, xz)" "$k" $((k/1024)) \
  "initramfs (core.xz)" "$i" $((i/1024)) "initramfs uncompressed" "$c" $((c/1024)) \
  "floppy image" "$(stat -c %s "$img")" $(( $(stat -c %s "$img")/1024 )) \
  "free on floppy FAT" "$free" $((free/1024))
if [ -f "$OUT/installer.img" ] && [ -f "$OUT/install.xz" ] && [ "$OUT/installer.img" -nt "$OUT/core.xz" ]; then
    x=$(stat -c %s "$OUT/install.xz"); ifree=$(fatfree "$OUT/installer.img")
    printf '  %-28s %9s bytes (%4d KiB)\n' "installer overlay (install.xz)" "$x" $((x/1024)) \
      "free on installer FAT" "$ifree" $((ifree/1024))
fi
