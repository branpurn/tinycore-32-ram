#!/bin/sh
# Print the size budget of the current build.
. "$(dirname "$0")/common.sh"
img=$OUT/tc32.img
k=$(stat -c %s "$OUT/bzImage"); i=$(stat -c %s "$OUT/core.xz"); c=$(stat -c %s "$BUILD/core.cpio")
free=$(MTOOLS_SKIP_CHECK=1 mdir -i "$img" ::/ 2>/dev/null | awk '/bytes free/{gsub(/[^0-9]/,""); print}')
echo; printf '  %-28s %9s bytes (%4d KiB)\n' "kernel (vmlinuz, xz)" "$k" $((k/1024)) \
  "initramfs (core.xz)" "$i" $((i/1024)) "initramfs uncompressed" "$c" $((c/1024)) \
  "floppy image" "$(stat -c %s "$img")" $(( $(stat -c %s "$img")/1024 )) \
  "free on floppy FAT" "$free" $((free/1024))
