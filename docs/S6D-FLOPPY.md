# S6d separate floppy (tc755-s6d)

Parallel to recovery `tc32.img` / `core.xz` / `busybox`. **Do not** replace those
with S6d outputs; CF boot stays OFF; 755C burn is a later Pop-GNOME step.

## Build

```bash
scripts/build-busybox-s6d.sh   # config/busybox-s6d.applets → out/busybox-s6d
scripts/mkrootfs-s6d.sh        # rootfs-s6d overlay + noswap rcS → out/core-s6d.xz
# vmlinuz = S6d-export bzImage-6.18.57-tc755x (see 755c-research/out-s6d-exports/)
PATH=/sbin:$PATH scripts/mkfloppy-s6d.sh   # → out/tc755-s6d.img
```

Tier1+2+3 busybox drops (Brandon OK t426s1393): editors/awk/fdisk/less;
gzip/unxz/tar/cpio helpers; mkfs/swap/blockdev. Boot APPEND `noswap`; S6d
`rcS` does not call fdisk/swapon.

## Stage / burn

Staged copy + checksums + burn notes:
`/workspace/755c-research/out-s6d-exports/floppy/` (`README.md`, `SHA256SUMS`).
