#!/bin/sh
# Build missing host tools into build/host (no root required):
#   flex, bison  (kernel kconfig/build), mtools (FAT image without loop mounts),
#   syslinux 4.07 mtools-based installer, musl i486 cross toolchain.
. "$(dirname "$0")/common.sh"
mkdir -p "$HOSTTOOLS/bin"

need() { command -v "$1" >/dev/null 2>&1; }

autotools_build() { # name ver url sum
    name=$1 ver=$2
    tb=$(fetch "$3" "$4"); unpack "$tb" "$name-$ver"
    log "building host $name $ver"
    ( cd "$BUILD/$name-$ver" && ./configure --prefix="$HOSTTOOLS" --disable-nls >/dev/null \
      && make -j"$JOBS" >/dev/null && make install >/dev/null ) || die "building $name failed"
}

need m4    || autotools_build m4    "$M4_VER"    "$M4_URL"    "$M4_SHA256"
need flex  || autotools_build flex  "$FLEX_VER"  "$FLEX_URL"  "$FLEX_SHA256"
need bison || autotools_build bison "$BISON_VER" "$BISON_URL" "$BISON_SHA256"
need mcopy || autotools_build mtools "$MTOOLS_VER" "$MTOOLS_URL" "$MTOOLS_SHA256"

# syslinux 4.07: the tarball ships prebuilt ldlinux.sys/ldlinux.bss, but the
# prebuilt installer is a 32-bit glibc binary; rebuild only the mtools
# installer natively (pure C + perl, no nasm needed).
if [ ! -x "$HOSTTOOLS/bin/syslinux-mtools" ]; then
    tb=$(fetch "$SYSLINUX_URL" "$SYSLINUX_SHA256"); unpack "$tb" "syslinux-$SYSLINUX_VER"
    log "building syslinux $SYSLINUX_VER mtools installer"
    ( cd "$BUILD/syslinux-$SYSLINUX_VER" && rm -f mtools/syslinux mtools/*.o \
      && make -C libinstaller bootsect_bin.c ldlinux_bin.c >/dev/null \
      && make -C mtools >/dev/null ) || die "syslinux installer build failed"
    cp "$BUILD/syslinux-$SYSLINUX_VER/mtools/syslinux" "$HOSTTOOLS/bin/syslinux-mtools"
fi

# mksquashfs (gzip + xz) for building .tcz test extensions
if ! need mksquashfs; then
    tb=$(fetch "$SQUASHFS_URL" "$SQUASHFS_SHA256"); unpack "$tb" "squashfs-tools-$SQUASHFS_VER"
    log "building host mksquashfs"
    ( cd "$BUILD/squashfs-tools-$SQUASHFS_VER/squashfs-tools" && \
      make -j"$JOBS" GZIP_SUPPORT=1 XZ_SUPPORT=1 LZO_SUPPORT=0 LZ4_SUPPORT=0 ZSTD_SUPPORT=0 LZMA_XZ_SUPPORT=0 XATTR_SUPPORT=0 mksquashfs >/dev/null \
      && cp mksquashfs "$HOSTTOOLS/bin/" ) || die "mksquashfs build failed"
fi

# musl cross toolchain (i486)
if [ ! -x "$BUILD/toolchain/i486-linux-musl-cross/bin/${MUSL_TC_PREFIX}gcc" ]; then
    tb=$(fetch "$MUSL_TC_URL" "$MUSL_TC_SHA256")
    mkdir -p "$BUILD/toolchain"; log "unpacking musl toolchain"
    tar -C "$BUILD/toolchain" -xzf "$tb"
fi
log "host tools ready: $(command -v flex) $(command -v bison) $(command -v mcopy) ${MUSL_TC_PREFIX}gcc"
