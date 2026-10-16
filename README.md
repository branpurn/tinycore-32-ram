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

Status: **Phase 1**. Boots to a shell in QEMU (`-cpu 486`) from 10 MB up, and
passes every automated check at 12–32 MB. Not yet tried on real hardware.
See [docs/FEASIBILITY.md](docs/FEASIBILITY.md) for research, budgets and
decision points.

| | size |
|---|---:|
| kernel (`vmlinuz`) | ~1008 KiB |
| initramfs (`core.xz`) | ~209 KiB |
| free space left on the floppy | ~167 KiB |
| RAM free after boot at 32 MB | ~24 MB |

## Build

```sh
make            # -> out/tc32.img (1,474,560 bytes)
make test       # QEMU boot test at 32 MB, logs in out/test-logs/
make sweep      # + headroom runs at 24/16/12/10/8 MB
make run        # interactive QEMU (VGA window); `make run-serial` = COM1 in this terminal
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

The default entry boots on its own after **3 seconds**, no keypress
needed. Its console is on **both** the VGA screen and **COM1 at 9600 8N1**
(`console=tty0 console=ttyS0,9600n8`). The syslinux `boot:` prompt is
mirrored on COM1 too (`SERIAL 0 9600`). Once booted, there is a root shell
on **both ttyS0 and tty1**: busybox `getty -n` with autologin, respawned by
init. There are no passwords; tc32 is single-user and runs from RAM. If
COM1 is missing or disabled, its getty backs off instead of flooding the
console.

At the `boot:` prompt (optional):
* `Enter` or wait 3 s: default (VGA + COM1)
* `vga`: VGA-only kernel console, `quiet` (a COM1 shell is still started)
* `tc32 tce=hda1`: default entry plus boot codes. Use `/dev/hda1`…`sda1` as
  the extension/persistence dir (`tce=fd0` for the floppy itself)
* other codes: `noswap`, `host=NAME`, `quiet`

### Serial console: connecting to the 755C

You need:
* **Host:** a USB-to-RS-232 adapter (FTDI FT232R-based adapters are the
  most trouble-free on Linux). It appears as `/dev/ttyUSB0`.
* **Cable:** a **null-modem** cable (crossed TX/RX, DB9 female–female, or
  the adapter plus a null-modem adapter) to the ThinkPad's 9-pin serial
  port. A straight-through cable will not work.
* **ThinkPad BIOS:** make sure the serial port is enabled as COM1
  (I/O 0x3F8, IRQ 4).
* **Terminal:**
  ```sh
  picocom -b 9600 /dev/ttyUSB0        # exit: Ctrl-A Ctrl-X
  ```
  (your user may need to be in the `dialout` group). 8N1, no flow control.

You should see the syslinux banner and `boot:` prompt, then the full kernel
log, then a `root@box:~#` shell.

**Why 9600 baud:** it is the most conservative rate for 1994-era
UARTs/BIOS setups and long or cheap cables, and it matches the syslinux and
BIOS defaults. The cost is speed. The kernel log (~5 KB) takes about
5–6 s to print, and printk to a serial console is synchronous, so a
verbose boot is a few seconds slower. 115200 is likely fine if the 755C's
UART is a 16550A, but it is not verified. To try it, change both
`SERIAL 0 9600` and `ttyS0,9600n8` in `boot/syslinux.cfg` and the `9600`
in `rootfs/etc/inittab`.

## Testing

`tests/run.sh` (or `make test`) runs two 32 MB boots. The first types
`tc32 tce=sda1` at the prompt with the IDE test disk attached (19 checks).
The second is a no-keypress, no-disk run of the default entry, exactly as
on first real boot (15 checks). Both use
`qemu-system-i386 -accel tcg -M isapc -cpu 486 -m 32`. KVM can't present a
486 to the guest, so tests always use TCG. A stdlib-only Python harness
(`tests/harness.py`, no pexpect needed) drives the syslinux prompt and the
shell over the emulated COM1. It also attaches a generated IDE test disk
(ext2 with `.tcz` extensions, plus a swap partition). It checks: syslinux prompt on COM1, kernel log on COM1,
`/proc/consoles` (tty0 + ttyS0 as `/dev/console`), autologin shells on
ttyS0 **and** tty1, tty1 respawn after kill, boot to a
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
