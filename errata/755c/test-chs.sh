#!/bin/sh
# Unit test for install-dualcf's partition-table helpers (chs, part): the
# CHS fields it writes for the slave must match the 755C BIOS's view.
#   errata/755c/test-chs.sh        (any POSIX sh; also busybox ash)
set -u
here=$(dirname "$0")
# Pull oct/le32/chs/part out of the installer (the script itself would
# start probing disks), then use them with the geometry under test.
eval "$(sed -n '/^oct()/,/^part()/p' "$here/install-dualcf.sh")"
fails=0
bytes() { od -An -tu1 | tr -s ' \n' '  ' | sed 's/^ //; s/ $//'; }
expect() { # name, expected bytes, command...
    n=$1 want=$2; shift 2
    got=$("$@" | bytes)
    if [ "$got" = "$want" ]; then echo "ok    $n"; else echo "FAIL  $n: got '$got', want '$want'"; fails=$((fails + 1)); fi
}

# 755C slave, INT 13h AH=08: 1022 cylinders, 240 heads, 63 sectors
GH=240 GS=63
expect "LBA 0 is 0/0/1"                      "0 1 0"     chs 0
expect "LBA 2048 is c0 h32 s33"              "32 33 0"   chs 2048
expect "LBA 15452639 (last BIOS sector) is c1021 h239 s63" "239 255 253" chs 15452639
expect "cylinder bits 8-9 go to the sector byte (c1000 h0 s1)" "0 193 232" chs $((1000 * 240 * 63))
expect "past cylinder 1023 is 1023/239/63"   "239 255 255" chs 250069679
# The sdb1 entry on the real card: active, 0b, LBA 2048 to 15452639
expect "sdb1 entry" "128 32 33 0 11 239 255 253 0 8 0 0 224 193 235 0" part 128 11 2048 15450592

# 16-head geometry (what the old code assumed, and QEMU's small disks)
# shellcheck disable=SC2034  # read by the chs() pulled in above
GH=16 GS=63
expect "16 heads: LBA 2048 is c2 h0 s33"     "0 33 2"    chs 2048
expect "16 heads: past cylinder 1023"        "15 255 255" chs 1032192

if [ "$fails" -ne 0 ]; then echo "test-chs: $fails failed"; exit 1; fi
echo "test-chs: all passed"
