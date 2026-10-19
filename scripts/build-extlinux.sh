#!/bin/sh
# Static i486 extlinux 4.07 installer (runs on the target, from install.xz)
# plus syslinux's MBR boot code. -> out/extlinux, out/mbr.bin
# The installer embeds ldlinux.sys/ldlinux.bss from the tarball (prebuilt),
# so only plain C is compiled here; no nasm needed.
. "$(dirname "$0")/common.sh"
tb=$(fetch "$SYSLINUX_URL" "$SYSLINUX_SHA256"); unpack "$tb" "syslinux-$SYSLINUX_VER"
S="$BUILD/syslinux-$SYSLINUX_VER"
[ -f "$S/libinstaller/ldlinux_bin.c" ] || make -C "$S/libinstaller" bootsect_bin.c ldlinux_bin.c >/dev/null
log "building extlinux $SYSLINUX_VER (static, i486 musl)"
cd "$S/extlinux"
# -include sys/sysmacros.h: musl has no major()/minor() in sys/types.h
"${MUSL_TC_PREFIX}gcc" -march=i486 -mtune=i486 -Os -static -no-pie -fno-pie \
    -ffunction-sections -fdata-sections -Wl,--gc-sections -w \
    -include sys/sysmacros.h -D_FILE_OFFSET_BITS=64 -I. -I.. -I../libinstaller \
    main.c mountinfo.c ../libinstaller/syslxmod.c ../libinstaller/syslxopt.c \
    ../libinstaller/syslxcom.c ../libinstaller/setadv.c ../libinstaller/advio.c \
    ../libinstaller/bootsect_bin.c ../libinstaller/ldlinux_bin.c -o "$OUT/extlinux"
"${MUSL_TC_PREFIX}strip" -s "$OUT/extlinux"
cp "$S/mbr/mbr.bin" "$OUT/mbr.bin"
[ "$(stat -c %s "$OUT/mbr.bin")" -eq 440 ] || die "mbr.bin is not 440 bytes"
log "extlinux: $(stat -c %s "$OUT/extlinux") bytes, mbr.bin: 440 bytes"
