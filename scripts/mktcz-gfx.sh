#!/bin/sh
# Package build/gfx/sysroot into Tiny Core-style .tcz extensions in out/gfx/
# (squashfs, xz). Usage: scripts/mktcz-gfx.sh   [GFX_BLOCK=128K]
#   Xlibs.tcz     musl libc.so as /lib/ld-musl-i386.so.1 + libX11/xcb/Xau/Xext
#   Xfbdev.tcz    TinyX Xfbdev (static) + startx + default xinitrc
#   jwm.tcz       jwm + /usr/local/etc/system.jwmrc (root menu)
#   rxvt.tcz      rxvt + rclock
#   Xaw-apps.tcz  Xt/Xmu/Xaw7/Xpm/SM/ICE + xclock, xcalc, xeyes
. "$(dirname "$0")/common.sh"
S="$BUILD/gfx/sysroot"; P=/usr/local; ST="$BUILD/gfx/tcz"; O="$OUT/gfx"
B=${GFX_BLOCK:-128K}
TC="$BUILD/toolchain/i486-linux-musl-cross"
[ -x "$S$P/bin/Xfbdev" ] || die "run scripts/build-gfx.sh first"
rm -rf "$ST"; mkdir -p "$ST" "$O"
# put SRC DEST-IN-EXT: copy one file (symlinks resolved), stripped if ELF
put() {
    e=$1 src=$2 dst=$ST/$1$3
    mkdir -p "$(dirname "$dst")"; cp -L "$src" "$dst"
    if head -c4 "$dst" | grep -q ELF; then
        case $dst in *.so*) i486-linux-musl-strip --strip-unneeded -R .comment "$dst" ;;
                     *) i486-linux-musl-strip -s -R .comment "$dst" ;; esac
    fi
}
lib() { e=$1; shift; for l; do put "$e" "$S$P/lib/$l" "$P/lib/$l"; done; }
bin() { e=$1; shift; for b; do put "$e" "$S$P/bin/$b" "$P/bin/$b"; done; }

put Xlibs "$TC/i486-linux-musl/lib/libc.so" /lib/ld-musl-i386.so.1
lib Xlibs libX11.so.6 libxcb.so.1 libXau.so.6 libXext.so.6
# Xlib locale data: only C (Xt apps warn and send COMPOUND_TEXT titles without it)
put Xlibs "$TOP/gfx/files/X11/locale/locale.dir" $P/share/X11/locale/locale.dir
put Xlibs "$TOP/gfx/files/X11/locale/locale.alias" $P/share/X11/locale/locale.alias
put Xlibs "$S$P/share/X11/locale/C/XLC_LOCALE" $P/share/X11/locale/C/XLC_LOCALE
put Xlibs "$S$P/share/X11/locale/C/XI18N_OBJS" $P/share/X11/locale/C/XI18N_OBJS
# (XErrorDB, 42 KB of error texts, left out: Xlib then prints numeric codes)

bin Xfbdev Xfbdev
put Xfbdev "$TOP/gfx/files/startx" $P/bin/startx
put Xfbdev "$TOP/gfx/files/X11/xinitrc" $P/etc/X11/xinitrc
chmod 755 "$ST/Xfbdev$P/bin/startx" "$ST/Xfbdev$P/etc/X11/xinitrc"

bin jwm jwm
put jwm "$TOP/gfx/files/system.jwmrc" $P/etc/system.jwmrc

bin rxvt rxvt rclock

lib Xaw-apps libICE.so.6 libSM.so.6 libXt.so.6 libXmu.so.6 libXpm.so.4 libXaw7.so.7
ln -s libXaw7.so.7 "$ST/Xaw-apps$P/lib/libXaw.so.7"
bin Xaw-apps xclock xcalc xeyes
for a in XClock XCalc; do
    [ -f "$S$P/share/X11/app-defaults/$a" ] && put Xaw-apps "$S$P/share/X11/app-defaults/$a" $P/share/X11/app-defaults/$a
done

deps() { case $1 in jwm|rxvt|Xaw-apps) echo Xlibs.tcz ;; Xfbdev) : ;; Xlibs) : ;; esac; }
bad=0
for e in Xlibs Xfbdev jwm rxvt Xaw-apps; do
    for f in $(find "$ST/$e" -type f); do head -c4 "$f" | grep -q ELF && { scripts/check-i486.sh "$f" 2>&1 | grep -q '^==> OK' || { scripts/check-i486.sh "$f"; bad=1; }; }; done
    rm -f "$O/$e.tcz"
    mksquashfs "$ST/$e" "$O/$e.tcz" -comp xz -b "$B" -noappend -all-root -no-xattrs -quiet >/dev/null
    deps "$e" | tr ' ' '\n' | sed '/^$/d' > "$O/$e.tcz.dep"
    ( cd "$ST/$e" && find . ! -type d | sed 's|^\.||' | sort ) > "$O/$e.tcz.list"
    ( cd "$O" && md5sum "$e.tcz" > "$e.tcz.md5.txt" && sha256sum "$e.tcz" > "$e.tcz.sha256.txt" )
done
[ $bad = 0 ] || die "post-486 instructions found"
# Sizes and serial time (XMODEM-1K, tools/send-file.sh). 115200: 1.9 KB/s
# MEASURED on the 755C (UART overruns, many CRC retries); 57600 ~4.5 KB/s
# and 38400 ~3.3 KB/s are ESTIMATES (line max 5.76 / 3.84 KB/s); 9600 0.9.
rates="1900 4500 3300 900"
{
printf '%-14s %9s %10s %9s %9s %9s %9s\n' extension tcz_bytes installed t_115200 t_57600 t_38400 t_9600
tot=0 itot=0
for e in Xlibs Xfbdev jwm rxvt Xaw-apps; do
    z=$(stat -c %s "$O/$e.tcz"); i=$(du -sb --apparent-size "$ST/$e" | cut -f1)
    tot=$((tot+z)); itot=$((itot+i))
    echo "$e $z $i"
done
echo "TOTAL $tot $itot"
} | awk -v r="$rates" 'function t(z,b){s=z/b; return sprintf("%dm%02ds", s/60, s%60)}
  BEGIN{split(r,R," ")} NR==1{print; next}
  {printf "%-14s %9d %10d %9s %9s %9s %9s\n", $1, $2, $3, t($2,R[1]), t($2,R[2]), t($2,R[3]), t($2,R[4])}' | tee "$O/sizes.txt"
