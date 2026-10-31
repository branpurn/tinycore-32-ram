# errata/755c: one specific ThinkPad 755C build

The repo owner's own 755C setup, kept apart from the generic tc32 tree: a dual
CompactFlash-to-IDE adapter carrying Tiny Core (tc32) on one card and
Windows 98 SE on the other, a boot menu, a dual-card installer floppy, an
FTDI serial console, and notes for future PicoPCMCIA work. Everything here
builds on the main tree (same kernel, `core.xz`, `install-to-disk`, extlinux
4.07, `tools/send-file.sh`). Nothing in this folder changes the stock
floppies.

**Status:** built and tested in QEMU (`-M isapc -cpu 486 -m 32`, 4 GiB +
128 GiB IDE disks), 25 checks: see [Testing](#testing). **Not yet tried on
the real 755C.** Items marked *(unverified)* still need the hardware.

## Hardware layout

| Position | Card | Linux name | BIOS disk | Partitions |
|---|---|---|---|---|
| IDE **master** | 4 GB CF | `sda` | `hd0` / 0x80 | `sda1` 256 MiB ext2 `TC32`, bootable: syslinux/extlinux 4.07, `vmlinuz`, `core.xz`, the fallback `/tce`; `sda2` 64 MiB swap; rest unused |
| IDE **slave** | 128 GB CF (**True IDE** mode) | `sdb` | `hd1` / 0x81 | `sdb1` 2 GiB FAT32, active: Windows 98 SE (at the start of the card, where the BIOS can reach it); `sdb2` rest of the card, ext2 **`tcdata`**: `tce/`, `home/`, `opt/`, `incoming/` |

* **Disk names:** this kernel uses libata (`pata_legacy`), so the IDE master
  is **`sda`** and the slave is **`sdb`**. The old `hda`/`hdb` names come from
  `drivers/ide`, which was removed in Linux 5.14. They do not exist here, so
  `tce=hda1`-style boot codes will not work.
* The installer tells master from slave by the libata SCSI address
  (`H:C:T:L`, target 0 = master, 1 = slave), not by the order the disks show
  up in.
* The CF cards must support **True IDE** mode, and the adapter's
  master/slave jumper or switch must be set. Many cheap cards only work as
  master *(unverified for the cards in use)*.
* **BIOS reach** *(unverified)*: a 1994 BIOS may only address the first
  504 MiB (1024 cyl x 16 heads x 63 sectors) through INT 13h. Everything
  tc32 boots from (`sda1`) lies inside it. `sdb1` starts at 1 MiB, so the
  Win98 boot sector and `IO.SYS` are in reach, but the rest of the 2 GiB
  partition is not. Windows 98 then needs its own 32-bit disk driver
  (`ESDI_506.PDR`) to reach the rest. Partition type `0b` (FAT32, CHS) is
  the default because this BIOS has no INT 13h extensions *(unverified)*.
  `install-dualcf -t 0c` writes `0c` (FAT32 LBA) instead.
* **RAM:** stock Tiny Core `core.gz` needs about 46 MB, and the 755C holds
  at most 36 MB (docs/FEASIBILITY.md). So the system on the cards is
  tc32's own `core.xz` (about 24 MB free after boot at 32 MB).
  [extlinux.conf.example](extlinux.conf.example) keeps a `core.gz` entry
  commented out, for reference.

## Files

| File | What it is |
|---|---|
| [INSTALL.md](INSTALL.md) | **Step by step**, from blank cards to a booting system, including recovery |
| [build-floppy.sh](build-floppy.sh) | builds `out/tc755c-installer.img`, the 1.44 MB dual-CF installer floppy (reproducible; images are never committed) |
| [install-dualcf.sh](install-dualcf.sh) | the installer on that floppy (`install-dualcf detect / prepare / finish`), busybox ash, uses `install-to-disk` for the master |
| [host-send.sh](host-send.sh) | host side: send files to `sdb2:/incoming` over the serial console (XMODEM via `tools/send-file.sh`) plus a `SHA256SUMS` list |
| [extlinux.conf.example](extlinux.conf.example) | menu.c32 boot menu: `tc` (default), `win98` (`chain.c32 hd1 1 swap`), `rescue` |
| [serial-getty.md](serial-getty.md), [repack-core-serial.sh](repack-core-serial.sh) | serial login on COM1: what tc32 already has, and how to add or change a ttyS0 getty in a `core.gz` / `core.xz` |
| [installer.txt](installer.txt) | login banner on the installer floppy |
| [test-qemu.py](test-qemu.py) | the QEMU test (`--full` = install end to end) |

## Bring-up checklist (real hardware)

Run these from the installer floppy (or any tc32 boot) **before formatting**:

1. `install-dualcf detect` should show `/dev/sda master` (about 4 GB) and
   `/dev/sdb slave` (about 128 GB).
2. `dmesg | grep -iE 'ata|sd[a-z]'`: both `ata1.00` and `ata1.01` should be on
   the primary port (0x1f0, irq 14). If `ata1.01` is missing, check the
   jumper and True IDE mode. (`dmesg | grep -i hd` from older guides will
   find nothing, because the disks are `sd*`.)
3. `cat /proc/partitions` should list `sda` and `sdb` with sizes that match
   the cards. Write down any existing partitions you want to keep.
4. `install-dualcf -n prepare` prints the plan and writes nothing.
5. Only then run `install-dualcf prepare` (see INSTALL.md). It does the
   fdisk, mkfs and seed steps: `mke2fs -L tcdata /dev/sdb2`,
   `mkdir -p tce/optional home opt incoming`, and it copies the fallback
   `tce` from `sda1`.

## Serial console (FTDI)

A USB serial adapter with an FTDI FT232R chip, plus a **null-modem** cable,
goes to the 755C's 9-pin port (COM1, 0x3F8, IRQ 4, enabled in the BIOS).
On the host: `picocom -b 9600 /dev/ttyUSB0`. tc32 runs the syslinux prompt,
the kernel console and an autologin root shell on COM1 at **9600 8N1**.
File transfers switch to 38400 (`tools/send-file.sh`). The repo measured
115200 as unreliable on the 755C's UART (CRC retries, and no faster in
practice: about 1.9 KB/s), so 115200 is an option here, not the default. See
[serial-getty.md](serial-getty.md).

## Future: PicoPCMCIA driver work (tracked here)

[PicoPCMCIA](https://github.com/yyzkevin/PicoPCMCIA) (yyzkevin) is an
open-source RP2350-based Type II, 5 V, 16-bit PC Card. Its emulated devices
include NE2000 networking over Wi-Fi, a dial-up modem, Sound Blaster / GUS /
MPU-401 audio, a CD-ROM and storage. Things to do for the 755C:

- [ ] The tc32 kernel has **no PC Card support** today (`# CONFIG_PCCARD is
      not set`). Add a `pcmcia` kernel fragment (PCCARD, PCMCIA, the ISA PCIC
      driver for the 755C's socket controller) as loadable modules in
      [thinkpad-755c-drivers](https://github.com/branpurn/thinkpad-755c-drivers).
      Identify the controller on the real machine first *(unverified which
      chip the 755C uses)*.
- [ ] NE2000 emulation, through the `pcnet_cs` driver, plus `pcmciautils` /
      CIS handling in a `.tcz`.
- [ ] Storage emulation as an ATA card (`pata_pcmcia`), which would show up
      as a third `sd*` disk.
- [ ] Audio: Sound Blaster emulation needs ALSA (`snd-sb*`), a bigger
      kernel, which belongs in the X second stage, not on the floppy.
- [ ] Measure the power draw in the 755C (the project quotes a 150 mA budget
      for networking plus storage).

## Testing

```sh
make installer && errata/755c/build-floppy.sh -N     # -> out/tc755c-installer.img
python3 errata/755c/test-qemu.py                      # boot, ttyS0 shell, detect, refusals
python3 errata/755c/test-qemu.py --full               # + prepare, serial send, finish, disk boot
```

The quick run (14 checks) boots the floppy with a sparse 4 GiB master and a
sparse 128 GiB slave. It checks:
* the syslinux prompt and a root shell on ttyS0 (the inittab getty);
* a 486 CPU;
* `detect` reports sda = master, 4096 MB, and sdb = slave, 131072 MB;
* `prepare` refuses `YES`, `ERASE sda`, lower case and an empty answer, and
  the first 2 MiB of both disks stay unchanged.

`--full` (25 checks) goes on to:
* run `prepare`, and check the partition table and the tcdata tree;
* send `vmlinuz`, `core.xz`, `menu.c32` and `chain.c32` with `host-send.sh`
  over the COM1 pty;
* check that `finish` refuses a corrupted file, then installs and verifies;
* boot the master card with no floppy. The menu.c32 menu appears on COM1,
  and the default `tc` entry comes up with `tce=sdb2` (tcedir
  `/mnt/sdb2/tce`).
