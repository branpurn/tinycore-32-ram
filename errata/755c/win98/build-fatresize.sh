#!/bin/sh
# Build a static i486 fatresize (libparted's FAT resizer) that runs under
# tc32 on the 755C. Used to grow Win98's C: (sdb1) in place; see
# ../WIN98-INSTALL.md "C: grown to the BIOS limit". Host-side, no root.
#   errata/755c/win98/build-fatresize.sh [WORKDIR]   -> WORKDIR/fatresize
# WORKDIR defaults to build/fatresize. Sources already in WORKDIR/dl are
# used as they are; anything missing is downloaded. Needs a C compiler
# toolchain host (make, autoreconf, pkg-config, git, curl).
set -eu
W=$(mkdir -p "${1:-build/fatresize}" && cd "${1:-build/fatresize}" && pwd)
DL=$W/dl SR=$W/sysroot
mkdir -p "$DL" "$W/src"
fetch() { [ -f "$DL/$2" ] || curl -fL --retry 3 -o "$DL/$2" "$1/$2"; }
fetch https://musl.cc i486-linux-musl-cross.tgz              # gcc 11.2.1 + musl
fetch https://ftp.gnu.org/gnu/parted parted-3.6.tar.xz
fetch https://www.kernel.org/pub/linux/utils/util-linux/v2.40 util-linux-2.40.2.tar.xz
[ -d "$DL/fatresize" ] || git clone -q https://github.com/ya-mouse/fatresize.git "$DL/fatresize"
# Checked when this was written (musl.cc rebuilds its tarballs now and then;
# a mismatch there is a warning, not an error).
( cd "$DL" && sha256sum -c <<'S' ) || echo "build-fatresize: checksum mismatch above (musl.cc toolchain can change)" >&2
3b43dbe33cca0f9a18601ebab56b7852b128ec1a3df3a9b30ccde5e73359e612  parted-3.6.tar.xz
d78b37a66f5922d70edf3bdfb01a6b33d34ed3c3cafd6628203b2a2b67c8e8b3  util-linux-2.40.2.tar.xz
1b7eceb2022f4a664028dd314c5c44332b601bd271e40f0934b4bc8fd3b0fcf5  i486-linux-musl-cross.tgz
S
cd "$W/src"
[ -d i486-linux-musl-cross ] || tar xzf "$DL/i486-linux-musl-cross.tgz"
PATH=$W/src/i486-linux-musl-cross/bin:$PATH
export PATH CC=i486-linux-musl-gcc CFLAGS="-Os -march=i486 -mtune=i486 -ffunction-sections -fdata-sections"
J=$(nproc 2>/dev/null || echo 2)

# libuuid only (libparted needs it)
rm -rf util-linux-2.40.2 && tar xJf "$DL/util-linux-2.40.2.tar.xz"
( cd util-linux-2.40.2 && ./configure -q --host=i486-linux-musl --prefix="$SR" \
    --disable-all-programs --enable-libuuid --disable-shared --enable-static --disable-nls \
    --without-python --without-systemd --without-tinfo --without-ncurses --disable-bash-completion \
  && make -s -j"$J" && make -s install )

# libparted + libparted-fs-resize, static, no device-mapper/readline/NLS
rm -rf parted-3.6 && tar xJf "$DL/parted-3.6.tar.xz"
( cd parted-3.6 && ./configure -q --host=i486-linux-musl --prefix="$SR" \
    CPPFLAGS="-I$SR/include" LDFLAGS="-L$SR/lib" \
    --disable-shared --enable-static --disable-device-mapper --without-readline \
    --disable-nls --disable-pc98 --disable-dynamic-loading \
  && make -s -j"$J" -C lib && make -s -j"$J" -C libparted && make -s -C libparted install \
  && make -s -C include install )

# fatresize 1.1.0 at the commit that was tested on the 755C. Static
# libparted-fs-resize.a and libparted.a both carry hfs/probe.o (the same
# source built twice), hence --allow-multiple-definition; libuuid last.
rm -rf fatresize && git clone -q "$DL/fatresize" fatresize
( cd fatresize && git checkout -q 75cbc38 && autoreconf -fi >/dev/null 2>&1 \
  && ./configure -q --host=i486-linux-musl \
       PARTED_CFLAGS="-I$SR/include" PARTED_LIBS="-L$SR/lib -lparted-fs-resize -lparted -luuid" \
       LDFLAGS="-static -Wl,--gc-sections -Wl,--allow-multiple-definition" \
  && make -s )
i486-linux-musl-strip -o "$W/fatresize" fatresize/fatresize
file "$W/fatresize" 2>/dev/null || true
ls -l "$W/fatresize"
