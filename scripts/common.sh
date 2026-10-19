#!/bin/sh
# Shared helpers. Source from other scripts: . "$(dirname "$0")/common.sh"
set -eu
TOP=$(cd "$(dirname "$0")/.." && pwd)
. "$TOP/versions.env"
DL="$TOP/dl"
BUILD="$TOP/build"
OUT="$TOP/out"
HOSTTOOLS="$BUILD/host"
JOBS=${JOBS:-$(nproc 2>/dev/null || echo 2)}
export PATH="$HOSTTOOLS/bin:$BUILD/toolchain/i486-linux-musl-cross/bin:$PATH"
# Reproducibility: fixed timestamps / build identity.
export SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH:-1767225600}   # 2026-01-01T00:00:00Z
export KBUILD_BUILD_VERSION=1 KBUILD_BUILD_USER=tc32 KBUILD_BUILD_HOST=tc32 KBUILD_BUILD_TIMESTAMP="@${SOURCE_DATE_EPOCH}"
mkdir -p "$DL" "$BUILD" "$OUT"

log() { printf '==> %s\n' "$*" >&2; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

# fetch URL SHA256 -> prints local path
fetch() {
    url=$1 sum=$2 f="$DL/$(basename "$1")"
    if [ ! -f "$f" ]; then
        log "downloading $url"
        curl -fL --retry 3 -o "$f.part" "$url" && mv "$f.part" "$f"
    fi
    echo "$sum  $f" | sha256sum -c --quiet - >&2 || die "checksum mismatch: $f"
    echo "$f"
}

# unpack TARBALL into $BUILD once (stamp file), then apply
# patches/<name>/*.patch. The stamp records the patches' sha256, so adding
# or changing a patch re-unpacks the tree (tar keeps upstream mtimes, so an
# out-of-tree build only recompiles what the patches touch).
unpack() {
    tb=$1 dir=$2
    pdir="$TOP/patches/${dir%%-[0-9]*}"
    psum=""   # empty stamp = no patches
    if ls "$pdir"/*.patch >/dev/null 2>&1; then
        psum=$(cat "$pdir"/*.patch | sha256sum | cut -d' ' -f1)
    fi
    if [ ! -f "$BUILD/.unpacked-$dir" ] || [ "$(cat "$BUILD/.unpacked-$dir")" != "$psum" ]; then
        rm -rf "${BUILD:?}/$dir"
        log "unpacking $(basename "$tb")"
        tar -C "$BUILD" -xf "$tb"
        if [ -d "$pdir" ]; then
            for p in "$pdir"/*.patch; do
                [ -f "$p" ] || continue
                log "applying $(basename "$p")"
                patch -d "$BUILD/$dir" -p1 -s < "$p" || die "patch failed: $p"
            done
        fi
        echo "$psum" > "$BUILD/.unpacked-$dir"
    fi
}
