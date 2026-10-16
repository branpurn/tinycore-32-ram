# tc32: Tiny Core–style Linux on one 1.44 MB floppy, for a 486 with 32 MB

tc32 is a small Linux system aimed at the **IBM ThinkPad 755C** (i486DX4-75,
up to 36 MB RAM, 3.5" floppy, IDE disk). It is modeled on
[Tiny Core Linux](http://tinycorelinux.net): it runs from RAM, uses TC boot
codes, a `tce` directory, `.tcz` squashfs extensions, `onboot.lst` and
`bootlocal.sh`. Everything has been shrunk to fit **one floppy**:

* Linux **6.18 LTS** (the last LTS line with i486 support), `tinyconfig` +
  i486 + VGA/serial console, AT keyboard, floppy, FAT, IDE (`pata_legacy`),
  ext2, swap, loop + squashfs, APM. xz-compressed.
* **busybox 1.37** built statically against musl for `-march=i486`.
* syslinux **4.07** on FAT12.

Status: **Phase 1**. Boots to a shell in QEMU (`-cpu 486`) from 8 MB up, and
passes every automated check at 12–32 MB. Not yet tried on real hardware.
See [docs/FEASIBILITY.md](docs/FEASIBILITY.md) for research, budgets and
decision points.

| | size |
|---|---:|
| kernel (`vmlinuz`) | ~1008 KiB |
| initramfs (`core.xz`) | ~207 KiB |
| free space left on the floppy | ~170 KiB |
| RAM free after boot at 32 MB | ~24 MB |

## Build

```sh
make            # -> out/tc32.img (1,474,560 bytes)
make test       # QEMU boot test at 32 MB, logs in out/test-logs/
make sweep      # + headroom runs at 24/16/12/10/8 MB
make run        # interactive QEMU (VGA window); `make run-serial` for a terminal
make scan       # public-repo hygiene scan (run before pushing)
```

Host requirements: Linux x86_64 with `gcc`, `make`, `perl`, `python3`,
`curl`, `xz`, `cpio`, `mkfs.fat`, and `qemu-system-i386` for tests (plus
`mke2fs`/`sfdisk`/`mkswap` for the test disk). Missing `m4`, `flex`, `bison`,
`mtools` and `mksquashfs` are built locally under `build/host/`, so no root
is needed. The i486 musl cross toolchain comes from musl.cc, pinned by
sha256. Alternatively, `make docker` builds inside `docker/Dockerfile`.

All sources are pinned with sha256 in [`versions.env`](versions.env). Builds
use a fixed `SOURCE_DATE_EPOCH`. Rebuilding on the same host gives a
bit-identical image (verified). Cross-host reproducibility is not verified yet.

## Write and boot

```sh
dd if=out/tc32.img of=/dev/fdX bs=512 conv=fsync && cmp out/tc32.img /dev/fdX
```

At the `boot:` prompt:
* `Enter`: normal boot (VGA console)
* `serial`: console on COM1 at 9600 baud (debugging)
* `tc32 tce=hda1`: use `/dev/hda1`…`sda1` as the extension/persistence
  dir (`tce=fd0` for the floppy itself)
* other codes: `noswap`, `host=NAME`, `quiet`

## Testing

`tests/run.sh` (or `make test`) boots the image with
`qemu-system-i386 -accel tcg -M isapc -cpu 486 -m 32`. KVM can't present a
486 to the guest, so tests always use TCG. A stdlib-only Python harness
(`tests/harness.py`, no pexpect needed) drives the syslinux prompt and the
shell over the emulated COM1. It also attaches a generated IDE test disk
(ext2 with `.tcz` extensions, plus a swap partition). It checks: boot to a
shell, `uname -m` = `i486`, `free`, `/proc` `/sys` `/dev` mounts, tmpfs file
I/O, the floppy driver + FAT, the IDE disk via `tce=sda1`, swap
auto-detection, `.tcz` auto-load from `onboot.lst` (xz) and `tce-load -i`
(gzip), and an APM power-off. You get a pass/fail summary in
`out/test-logs/summary.txt`, plus serial logs and JSON results.

QEMU's 486 model is not a strict 486, so `scripts/check-i486.sh` also
statically rejects post-486 opcodes (CMOV, NOPL, RDTSC, CX8, MMX/SSE...)
in userland binaries.

## Layout

```
versions.env          pinned sources (+sha256)
config/               kernel fragments (base, hdd, tce) + busybox applet list
rootfs/               init, inittab, rcS (trimmed tc-config), tce-load, ...
boot/syslinux.cfg     boot menu
scripts/              host-tools, build-kernel, build-busybox, mkrootfs, mkfloppy, checks
tests/                QEMU harness, test-disk builder, runner
docs/FEASIBILITY.md   research, budgets, risks, decisions
```

## License

Build scripts and configs: GPL-2.0 (see [LICENSE](LICENSE)). The images
contain Linux (GPL-2.0), BusyBox (GPL-2.0), syslinux (GPL-2.0) and musl
(MIT). Sources are fetched from upstream at the pinned versions. tc32 is not
affiliated with the Tiny Core Linux project.
