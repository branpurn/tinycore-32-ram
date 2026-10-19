#!/bin/sh
# Kernels for the graphics stage (docs/GRAPHICS.md). Neither goes on a floppy.
#   scripts/build-gfx-kernel.sh test   QEMU-only: tc32 config + vesafb + psmouse
#                                      built in + AF_UNIX -> out/gfx/bzImage
#   scripts/build-gfx-kernel.sh 755c   the 755C kernel "6.18.57-tc755x": the
#       thinkpad-755c-drivers (tc755) kernel + its modules/.tcz (wd90c24fb,
#       trackpoint, modutils, ...) rebuilt with AF_UNIX. Output: out/gfx/755c/
#       {vmlinuz.x, *.tcz}. Uses a pinned export of the tc755 repo (TC755_GIT:
#       local clone or URL), with its own vermagic so the stock tc755 .tcz
#       (no NET) can never be loaded into it by mistake.
. "$(dirname "$0")/common.sh"
TC755_GIT=${TC755_GIT:-$( [ -d "$TOP/../thinkpad-755c-drivers/.git" ] && cd "$TOP/../thinkpad-755c-drivers" && pwd || echo https://github.com/branpurn/thinkpad-755c-drivers)}
TC755_COMMIT=${TC755_COMMIT:-22164b2}
case ${1:-test} in
test)
    KERNEL_OBJ="$BUILD/kernel-gfxtest" KERNEL_OUT="$OUT/gfx" \
      "$TOP/scripts/build-kernel.sh" base hdd tce modules gfxtest xnet
    ;;
755c)
    W="$BUILD/gfx/tc755x"; rm -rf "$W"; mkdir -p "$W"
    if [ -d "$TC755_GIT" ]; then git -C "$TC755_GIT" archive "$TC755_COMMIT" | tar -C "$W" -x
    else git clone -q "$TC755_GIT" "$W.git" && git -C "$W.git" archive "$TC755_COMMIT" | tar -C "$W" -x; rm -rf "$W.git"; fi
    sed -i 's/^CONFIG_LOCALVERSION="-tc755"$/CONFIG_LOCALVERSION="-tc755x"/' "$W/config/kernel-modules.fragment"
    grep -q 'LOCALVERSION="-tc755x"' "$W/config/kernel-modules.fragment" || die "tc755 LOCALVERSION line not found"
    cp "$TOP/config/kernel-xnet.fragment" "$W/config/kernel-xnet.fragment"
    # reuse the downloads and this checkout's kernel tree (has the atkbd.xlate patch)
    mkdir -p "$W/dl"; for f in "$DL"/*; do [ -f "$f" ] && ln -sf "$f" "$W/dl/"; done
    make -C "$W" TC32_DIR="$TOP" ADDON_FRAGMENTS="modules drivers xnet" kernel tcz
    D="$OUT/gfx/755c"; rm -rf "$D"; mkdir -p "$D"
    cp "$W/out/bzImage" "$D/vmlinuz.x"
    for e in modutils fb-wd90c24 fb-vga16 trackpoint wd90c24-probe apm-tools; do
        cp "$W/out/tcz/$e.tcz" "$D/"; [ -f "$W/out/tcz/$e.tcz.dep" ] && cp "$W/out/tcz/$e.tcz.dep" "$D/"
    done
    ( cd "$D" && sha256sum vmlinuz.x *.tcz > sha256.txt )
    log "755C kernel $(cat "$W/build/kernel-obj/include/config/kernel.release"): $(stat -c %s "$D/vmlinuz.x") bytes"
    ;;
*) die "usage: $0 test|755c" ;;
esac
