#!/bin/sh
# Static check: no i586/i686-only instructions in userland binaries.
# QEMU's TCG "-cpu 486" does NOT reliably trap every post-486 opcode
# (historically CMOV & co. executed fine), so a QEMU pass alone is not proof.
#   fatal : cmov*, fcmov*, f(u)comi*, sysenter/sysexit, multi-byte nop (nopl/nopw),
#           rdtsc/rdpmc, cmpxchg8b, SSE/MMX register use
#   info  : cpuid (present on DX4 and later 486s, not on early 486DX)
. "$(dirname "$0")/common.sh"
rc=0
for b in "${@:-$OUT/busybox}"; do
    d=$(objdump -d --no-show-raw-insn "$b")
    bad=$(printf '%s\n' "$d" | grep -cE '\s(cmov[a-z]*|fcmov[a-z]*|fu?comip?|sysenter|sysexit|nop[lw]|rdtsc|rdpmc|cmpxchg8b)\s|%xmm|%mm[0-7]' || true)
    cpuid=$(printf '%s\n' "$d" | grep -cE '\scpuid' || true)
    if [ "$bad" -ne 0 ]; then
        log "FAIL $(basename "$b"): $bad post-486 instructions:"
        printf '%s\n' "$d" | grep -E '\s(cmov[a-z]*|fcmov[a-z]*|fu?comip?|sysenter|sysexit|nop[lw]|rdtsc|rdpmc|cmpxchg8b)\s|%xmm|%mm[0-7]' | head -5 >&2
        rc=1
    else
        log "OK   $(basename "$b"): no post-486 instructions (cpuid: $cpuid)"
    fi
done
exit $rc
