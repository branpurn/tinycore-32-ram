#!/bin/sh
# Write \WIN98\MSBATCH.INF (CRLF) from MSBATCH.INF.in, with the product key
# read from an env file. The key is never printed or passed on a command
# line (it goes through the environment of awk only).
#
#   mk-msbatch.sh ENVFILE OUTPUT
#     ENVFILE  a file with a line WIN98SE_PRODUCT_KEY=XXXXX-XXXXX-XXXXX-XXXXX-XXXXX
#     OUTPUT   e.g. /media/$USER/WIN98SE/WIN98/MSBATCH.INF
#
# After Setup has finished, delete C:\WIN98\MSBATCH.INF (it holds the key).
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
[ $# -eq 2 ] || { sed -n '5,8s/^# \{0,1\}//p' "$0"; exit 2; }
[ -r "$1" ] || die "cannot read $1"
K=$(sed -n 's/^[[:space:]]*\(export[[:space:]]\{1,\}\)\{0,1\}WIN98SE_PRODUCT_KEY=//p' "$1" |
    tail -1 | tr -d "\"' \r\t")
printf '%s\n' "$K" | grep -Eq '^[A-Za-z0-9]{5}(-[A-Za-z0-9]{5}){4}$' ||
    die "WIN98SE_PRODUCT_KEY in $1 is missing or not in XXXXX-XXXXX-XXXXX-XXXXX-XXXXX form"
K=$K awk '{ gsub(/@WIN98SE_PRODUCT_KEY@/, ENVIRON["K"]); sub(/\r*$/, "\r"); print }' \
    "$HERE/MSBATCH.INF.in" > "$2.tmp"
grep -q '@WIN98SE_PRODUCT_KEY@' "$2.tmp" && die "placeholder left in output"
mv "$2.tmp" "$2"
echo "wrote $2 ($(wc -c < "$2") bytes; product key filled in, not shown)"
