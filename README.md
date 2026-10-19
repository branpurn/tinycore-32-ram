# tc32: Tiny Core–style Linux on one 1.44 MB floppy, for a 486 with 32 MB

tc32 is a small Linux system aimed at the **IBM ThinkPad 755C** (i486DX4-75,
up to 36 MB RAM, 3.5" floppy, IDE disk). It is modeled on
[Tiny Core Linux](http://tinycorelinux.net): it runs from RAM, uses TC boot
codes, a `tce` directory, `.tcz` squashfs extensions, `onboot.lst` and
`bootlocal.sh`. Everything has been shrunk to fit **one floppy**:

* Linux **6.18 LTS** (the last LTS line with i486 support), `tinyconfig` +
  i486 + VGA/serial console, AT keyboard, floppy, FAT, IDE (`pata_legacy`),
  ext2, swap, loop + squashfs, APM, loadable modules (drivers ship as
  `.tcz`, see [thinkpad-755c-drivers](https://github.com/branpurn/thinkpad-755c-drivers)).
  Boots with `floppy=thinkpad` (the 755C inverts the floppy disk-change
  line) and `atkbd.xlate=2` (its keyboard controller claims raw mode but
  sends set-1 codes; small kernel patch, see docs/INSTALL.md); use the
  `generic` boot label on other PCs. xz-compressed.
* **busybox 1.37** built statically against musl for `-march=i486`.
* syslinux **4.07** on FAT12.

Status: **Phase 1** plus a **disk installer**. Boots to a shell in QEMU
(`-cpu 486`) from 10 MB up, and passes every automated check at 12–32 MB.
The installer floppy installs tc32 onto the IDE disk (the 755C's
CompactFlash card) so it boots without the floppy. Files can be sent over
the COM1 serial link (XMODEM). See [docs/INSTALL.md](docs/INSTALL.md). Not
yet tried on real hardware.
See [docs/FEASIBILITY.md](docs/FEASIBILITY.md) for research, budgets and
decision points.

| | size |
|---|---:|
| kernel (`vmlinuz`, with loadable module support) | ~1060 KiB |
| initramfs (`core.xz`) | ~213 KiB |
| free space left on the floppy | ~112 KiB (114,688 bytes) |
| installer floppy: + `install.xz` overlay / free | ~69 KiB / ~42 KiB |
| RAM free after boot at 32 MB | ~24 MB |

## Build

```sh
make            # -> out/tc32.img (rescue) + out/installer.img, 1,474,560 bytes each
make test       # QEMU boot test at 32 MB, logs in out/test-logs/
make sweep      # + headroom runs at 24/16/12/10/8 MB
make installer  # just out/installer.img (same kernel + core.xz, + install.xz)
make test-install  # QEMU: install onto a 2 GB IDE disk, boot it with no floppy,
                   #       XMODEM transfer over COM1 + sha256 check
make run-installer # interactive installer + scratch disk; `make run-disk` boots that disk
make run        # interactive QEMU (VGA window); `make run-serial` = COM1 in this terminal
make scan       # public-repo hygiene scan (run before pushing)
```

Host requirements: Linux x86_64 with `gcc`, `make`, `perl`, `python3`,
`curl`, `xz`, `cpio`, `mkfs.fat`, and `qemu-system-i386` for tests (plus
`mke2fs`/`sfdisk`/`mkswap` for the test disks). Missing `m4`, `flex`, `bison`,
`mtools`, `mksquashfs` and `sx` (lrzsz) are built locally under `build/host/`,
so no root is needed. The i486 musl cross toolchain comes from musl.cc, pinned by
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
* `tc32 tce=sda1`: default entry plus boot codes. Use that partition as
  the extension/persistence dir. IDE disks are `sdX` under libata
  `pata_legacy`; use `tce=fd0` for the floppy itself.
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

## Install onto the IDE disk / CF card

```sh
dd if=out/installer.img of=/dev/fdX bs=512 conv=fsync    # boot it, then on the 755C:
install-to-disk -n /dev/sda      # dry run
install-to-disk /dev/sda         # type YES; then remove the floppy and reboot
```

This wipes the disk (e.g. Windows 95) and creates `sda1`, 256 MiB ext2,
bootable: kernel, `core.xz`, extlinux 4.07 and `/tce`. It adds `sda2`,
64 MiB swap, and leaves the rest unpartitioned for a future second stage.
The disk boots with the same 9600 COM1 + VGA console and `tce=sda1`. Re-running
is safe, and `-u` refreshes only the boot files. To send files over the
serial console, use `tools/send-file.sh FILE /dev/ttyUSB0 [REMOTE]` (XMODEM
via busybox `rx`, temporarily at 115200, sha256-verified). Details,
layout rationale, throughput and a real-hardware checklist are in
[docs/INSTALL.md](docs/INSTALL.md).

## Testing

`tests/run.sh` (or `make test`) runs four 32 MB boots. The first types
`tc32 floppy=0,thinkpad tce=sda1` at the prompt with the IDE test disk
attached (26 checks). The second is a no-keypress, no-disk run of the
default entry, exactly as on first real boot (19 checks). Two short
keyboard runs boot with `i8042.direct=1` (a non-translating controller,
which is how the 755C's looks to Linux): `generic` must keep a genuine raw
set-2 keyboard working (8 checks), and `tc32` must switch to translated
decoding with `atkbd.xlate=2` (7 checks). QEMU's floppy
controller has a normal disk-change line, so the typed run undoes the
755C's `floppy=thinkpad`; the default-entry run checks that the option is
on the command line and skips the `/dev/fd0` mount, which needs the real
755C. Both use
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
(gzip), the PS/2 keyboard (text typed with QEMU `sendkey` must reach the
tty1 shell, with no `Unknown key`), and an APM power-off. You get a pass/fail summary in
`out/test-logs/summary.txt`, plus serial logs and JSON results.

`tests/run-install.sh` (`make test-install`, 29 checks) builds a
2,000,000,000-byte IDE disk with a FAT32 "Windows 95" partition and boots
the installer. It runs `install-to-disk` over COM1 four ways: a dry run, a
refused confirmation, a full install, and a second full install that must
give an identical MBR. Then `-u` must keep `/tce`. Next it boots the disk
with **no floppy**, with no keypress, and checks the shell, `tce=sda1`, and
swap. It sends 192 KiB at 115200 and 1.5 KB at 9600 with
`tools/send-file.sh` over the same COM1 (a QEMU pty), checking sha256 on
both ends. Finally it boots the disk once more on `-M pc` (PIIX IDE).

QEMU's 486 model is not a strict 486, so `scripts/check-i486.sh` also
statically rejects post-486 opcodes (CMOV, NOPL, RDTSC, CX8, MMX/SSE...)
in userland binaries.

## Layout

```
versions.env          pinned sources (+sha256)
config/               kernel fragments (base, hdd, tce) + busybox applet list
patches/linux/        kernel patches (atkbd.xlate for the 755C keyboard)
rootfs/               init, inittab, rcS (trimmed tc-config), tce-load, ...
installer/            install.xz overlay: install-to-disk, login banner
boot/syslinux.cfg     boot menu (rescue floppy)
boot/installer.cfg    boot menu (installer floppy)
boot/extlinux.conf    boot menu template for the installed disk
scripts/              host-tools, build-kernel, build-busybox, build-extlinux, mkrootfs, mkfloppy, mkinstaller, checks
tools/send-file.sh    host side of the serial (XMODEM) file transfer
tests/                QEMU harness, test-disk builder, runners (run.sh, run-install.sh)
docs/FEASIBILITY.md   research, budgets, risks, decisions
docs/INSTALL.md       disk installer, layout, serial transfer, 755C checklist
```

## License

Build scripts and configs: GPL-2.0 (see [LICENSE](LICENSE)). The images
contain Linux (GPL-2.0), BusyBox (GPL-2.0), syslinux (GPL-2.0) and musl
(MIT). Sources are fetched from upstream at the pinned versions. tc32 is not
affiliated with the Tiny Core Linux project.
