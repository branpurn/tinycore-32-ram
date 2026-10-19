#!/bin/sh
# Build the graphics second stage (docs/GRAPHICS.md) for i486 musl:
# TinyX Xfbdev (static), shared X client libs, jwm, rxvt, xclock/xcalc/xeyes.
# Installs into build/gfx/sysroot (prefix /usr/local, Tiny Core layout).
# Usage: scripts/build-gfx.sh [STEP ...]   (default: all steps, stamped)
. "$(dirname "$0")/common.sh"
. "$TOP/gfx/versions.env"
GDL="$DL/gfx"; G="$BUILD/gfx"; SRC="$G/src"; SYSROOT="$G/sysroot"; P=/usr/local
HOSTP="$G/host"                       # host autotools (autoreconf for TinyX)
mkdir -p "$GDL" "$SRC" "$SYSROOT" "$HOSTP"
[ -x "$BUILD/toolchain/i486-linux-musl-cross/bin/i486-linux-musl-gcc" ] || scripts/host-tools.sh
T=i486-linux-musl
export PATH="$HOSTP/bin:$PATH"
export CC=$T-gcc AR=$T-ar RANLIB=$T-ranlib STRIP=$T-strip CC_FOR_BUILD=gcc
export CFLAGS="-Os -march=i486 -mtune=i486 -pipe -ffunction-sections -fdata-sections -fno-asynchronous-unwind-tables"
export CPPFLAGS="-I$SYSROOT$P/include"
export LDFLAGS="-L$SYSROOT$P/lib -Wl,-rpath-link,$SYSROOT$P/lib -Wl,--gc-sections -Wl,-O1"
export PKG_CONFIG_LIBDIR="$SYSROOT$P/lib/pkgconfig:$SYSROOT$P/share/pkgconfig"
export PKG_CONFIG_SYSROOT_DIR="$SYSROOT" PKG_CONFIG_PATH=""
export ACLOCAL_PATH="$SYSROOT$P/share/aclocal:/usr/share/aclocal"

# gfetch NAME -> local tarball (NAME_URL, NAME_SHA256, optional NAME_FILE)
gfetch() {
    eval "u=\$${1}_URL s=\$${1}_SHA256 f=\${${1}_FILE:-}"
    [ -n "$f" ] || f=$(basename "$u"); f="$GDL/$f"
    [ -f "$f" ] || { log "downloading $u"; curl -fL --retry 3 -o "$f.part" "$u" && mv "$f.part" "$f"; }
    echo "$s  $f" | sha256sum -c --quiet - >&2 || die "checksum mismatch: $f"
    echo "$f"
}
# gsrc NAME -> fresh source dir (patches from gfx/patches/<dir-without-version>/)
gsrc() {
    tb=$(gfetch "$1"); d=$(tar -tf "$tb" | head -1 | cut -d/ -f1)
    rm -rf "${SRC:?}/$d"; tar -C "$SRC" -xf "$tb"
    pd="$TOP/gfx/patches/$(echo "$d" | sed -E 's/-[0-9a-f.]+$//')"
    for p in "$pd"/*.patch; do [ -f "$p" ] && { log "  patch $(basename "$p")"; patch -d "$SRC/$d" -p1 -s < "$p" || die "patch $p"; }; done
    echo "$SRC/$d"
}
done_() { [ -f "$G/.done-$1" ]; }
mark() { touch "$G/.done-$1"; }
noarch() { find "$SYSROOT" -name '*.la' -delete; }
# ac NAME [configure args]: generic autotools cross build + DESTDIR install
ac() {
    n=$1; shift
    done_ "$n" && return 0
    log "gfx: $n"
    d=$(gsrc "$(echo "$n" | tr a-z- A-Z_)")
    # old tarballs (rxvt 2.7.10) predate musl: refresh config.sub/guess
    for c in $(find "$d" -name config.sub); do rm -f "$c" "${c%.sub}.guess"; cp "$HOSTP"/share/automake-*/config.sub "$c"; cp "$HOSTP"/share/automake-*/config.guess "${c%.sub}.guess"; done
    ( cd "$d" && ./configure --host=$T --build="$(gcc -dumpmachine)" --prefix=$P \
        --sysconfdir=/etc --localstatedir=/var --disable-dependency-tracking "$@" > "$G/$n.configure.log" 2>&1 \
      || { tail -30 "$G/$n.configure.log"; exit 1; }
      make -j"$JOBS" > "$G/$n.make.log" 2>&1 || { tail -40 "$G/$n.make.log"; exit 1; }
      make DESTDIR="$SYSROOT" install > "$G/$n.install.log" 2>&1 || { tail -20 "$G/$n.install.log"; exit 1; } ) || die "$n failed (logs in $G)"
    noarch; mark "$n"
}
# host autotools: plain native builds into $HOSTP
hostac() {
    n=$1; done_ "host-$n" && return 0
    log "gfx: host $n"
    d=$(gsrc "$(echo "$n" | tr a-z- A-Z_)")
    ( cd "$d" && env -u CC -u AR -u RANLIB -u STRIP -u CFLAGS -u CPPFLAGS -u LDFLAGS -u PKG_CONFIG_LIBDIR -u PKG_CONFIG_SYSROOT_DIR \
        sh -c "./configure --prefix='$HOSTP' >'$G/host-$n.log' 2>&1 && make -j$JOBS >>'$G/host-$n.log' 2>&1 && make install >>'$G/host-$n.log' 2>&1" ) \
      || { tail -20 "$G/host-$n.log"; die "host $n failed"; }
    mark "host-$n"
}

step_host() { hostac autoconf; hostac automake; hostac libtool; }
step_proto() {
    ac utilmacros
    ac xorgproto --disable-specs --without-xmlto --without-fop --without-xsltproc
    ac xtrans --disable-docs --without-xmlto --without-fop
    ac xcbproto
}
step_libs() {
    # xcb-proto's .pc variables are not sysroot-relative: point them in.
    sed -i "s|^prefix=/usr/local|prefix=$SYSROOT/usr/local|" "$SYSROOT$P/share/pkgconfig/xcb-proto.pc"
    ac libxau --enable-static --enable-shared
    ac libxcb --enable-static --disable-devel-docs --without-doxygen --without-launchd \
      --disable-composite --disable-damage --disable-dbe --disable-dpms --disable-dri2 --disable-dri3 \
      --disable-glx --disable-present --disable-randr --disable-record --disable-render \
      --disable-resource --disable-screensaver --disable-shape --disable-shm --disable-sync \
      --disable-xevie --disable-xfixes --disable-xfree86-dri --disable-xinerama --disable-xinput \
      --disable-xkb --disable-xprint --disable-selinux --disable-xtest --disable-xv --disable-xvmc --disable-ge
    ac libx11 --enable-static --disable-specs --without-xmlto --without-fop --without-xsltproc \
      --disable-xkb --disable-xf86bigfont --disable-loadable-i18n --disable-loadable-xcursor \
      --disable-composecache --enable-malloc0returnsnull --disable-lint-library \
      --disable-xcms --disable-ipv6 --disable-tcp-transport --disable-local-transport
    ac libxext --enable-static --disable-specs --without-xmlto --without-fop --enable-malloc0returnsnull
}
step_xaw() {
    ac libice --disable-static --disable-docs --disable-specs --without-xmlto --without-fop --without-xsltproc
    ac libsm --disable-static --disable-docs --without-xmlto --without-fop --without-xsltproc --without-libuuid
    ac libxt --disable-static --disable-specs --without-xmlto --without-fop --without-xsltproc --enable-malloc0returnsnull --disable-xkb
    ac libxmu --disable-static --disable-docs --without-xmlto --without-fop --without-xsltproc
    ac libxpm --disable-static --disable-open-zfile --disable-stat-zfile
    ac libxaw --disable-static --disable-xaw6 --disable-specs --without-xmlto --without-fop --without-xsltproc
}
step_fontlibs() {
    if ! done_ zlib; then
        log "gfx: zlib"; d=$(gsrc ZLIB)
        ( cd "$d" && CHOST=$T ./configure --prefix=$P --static >"$G/zlib.log" 2>&1 && make -j"$JOBS" libz.a >>"$G/zlib.log" 2>&1 \
          && make DESTDIR="$SYSROOT" install >>"$G/zlib.log" 2>&1 ) || { tail -20 "$G/zlib.log"; die zlib; }
        mark zlib
    fi
    ac libxdmcp --enable-static --disable-shared --disable-docs --without-xmlto --without-fop --without-xsltproc
    # headers only: drop the lib + .pc so nothing (libxcb) starts linking XDM auth
    rm -f "$SYSROOT$P/lib/libXdmcp.a" "$SYSROOT$P/lib/pkgconfig/xdmcp.pc"
    ac libfontenc --enable-static --disable-shared --with-encodingsdir=$P/share/fonts/X11/encodings
    ac libxfont --enable-static --disable-shared --disable-devel-docs --without-xmlto --without-fop \
      --disable-freetype --disable-type1 --disable-speedo --disable-bdfformat --disable-snfformat \
      --enable-pcfformat --enable-builtins --disable-fc --disable-ipv6 --disable-tcp-transport --disable-local-transport
}
step_tinyx() {
    done_ tinyx && return 0
    log "gfx: tinyx (Xfbdev)"
    d=$(gsrc TINYX)
    ( cd "$d" && autoreconf -fi > "$G/tinyx.autoreconf.log" 2>&1 \
      && ./configure --host=$T --build="$(gcc -dumpmachine)" --prefix=$P --disable-dependency-tracking \
        --disable-xvesa --enable-xfbdev --disable-xdmcp --disable-xdm-auth-1 --disable-xres \
        --disable-screensaver --disable-dpms --disable-xf86bigfont --disable-dbe --disable-install-setuid \
        --with-int10=stub --with-default-font-path="built-ins" \
        --with-vendor-name="tc32 TinyX" PKG_CONFIG="pkg-config --static" > "$G/tinyx.configure.log" 2>&1 \
      && make -j"$JOBS" LDFLAGS="$LDFLAGS -all-static" > "$G/tinyx.make.log" 2>&1 ) \
      || { tail -40 "$G/tinyx.make.log" "$G/tinyx.configure.log" 2>/dev/null | tail -60; die "tinyx failed (logs in $G)"; }
    install -D -m 755 "$d/kdrive/fbdev/Xfbdev" "$SYSROOT$P/bin/Xfbdev"
    mark tinyx
}
step_apps() {
    ac jwm --sysconfdir=$P/etc --disable-xft --disable-xrender --disable-png --disable-jpeg --disable-xpm --disable-cairo \
      --disable-rsvg --disable-xinerama --disable-fribidi --disable-nls --disable-debug --enable-shape --disable-xmu
    ac rxvt --disable-utmp --disable-wtmp --disable-lastlog --disable-xpm-background --disable-menubar \
      --disable-xim --disable-backspace-key --disable-delete-key --disable-resources --enable-smart-resize \
      --enable-ttygid=no --with-term=rxvt ac_cv_func_setpgrp_void=yes
    ac xclock --without-xft --without-xkb --with-appdefaultdir=$P/share/X11/app-defaults
    ac xcalc --with-appdefaultdir=$P/share/X11/app-defaults
    ac xeyes --without-xrender --with-appdefaultdir=$P/share/X11/app-defaults
}
steps=${*:-host proto libs xaw fontlibs tinyx apps}
for s in $steps; do "step_$s"; done
log "gfx: sysroot ready: $SYSROOT$P"
