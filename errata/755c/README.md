# errata/755c: one specific ThinkPad 755C build

The repo owner's own 755C setup, kept apart from the generic tc32 tree: a dual
CompactFlash-to-IDE adapter carrying Tiny Core (tc32) on one card and
Windows 98 SE on the other, a boot menu, a dual-card installer floppy, an
FTDI serial console, and PC Card notes. Everything here
builds on the main tree (same kernel, `core.xz`, `install-to-disk`, extlinux
4.07, `tools/send-file.sh`). Nothing in this folder changes the stock
floppies.

**Status:** built and tested in QEMU (`-M isapc -cpu 486 -m 32`, 4 GiB +
128 GiB IDE disks), 25 checks: see [Testing](#testing). On the real 755C,
Tiny Core boots from the master with `tce` on `sdb2`, Windows 98 SE boots
from `sdb1` ([WIN98-INSTALL.md](WIN98-INSTALL.md#what-worked-on-the-real-755c)),
and PC Card CF cards work ([PC Card](#pc-card-verified)). Items still
marked *(unverified)* have not been checked on the hardware.

## Hardware layout

| Position | Card | Linux name | BIOS disk | Partitions |
|---|---|---|---|---|
| IDE **master** | 4 GB CF | `sda` | `hd0` / 0x80 | `sda1` 256 MiB ext2 `TC32`, bootable: syslinux/extlinux 4.07, `vmlinuz`, `core.xz`, the fallback `/tce`; `sda2` 64 MiB swap; rest unused |
| IDE **slave** | 128 GB CF (**True IDE** mode) | `sdb` | `hd1` / 0x81 | `sdb1` FAT32 (`0b`), active, LBA 2048 to 15452639 (about 7.4 GB, up to the last sector the BIOS reaches): Windows 98 SE; `sdb2` rest of the card, ext2 **`tcdata`**: `tce/`, `home/`, `opt/`, `incoming/` |

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
* **BIOS reach** (measured): the 755C BIOS gives the 128 GB slave a
  geometry of **1022 cylinders x 240 heads x 63 sectors** = 15,452,640
  sectors (about 7.9 GB) through INT 13h, not the 504 MiB (16 heads) that
  was feared. `install-dualcf` writes the slave's partition table in that
  geometry (`-g`) and sizes `sdb1` to end at the limit (`-f max`), so DOS
  and real-mode Windows can read all of C:. Partition type `0b` (FAT32,
  CHS) is the default because this BIOS has no INT 13h extensions
  *(unverified)*. `install-dualcf -t 0c` writes `0c` (FAT32 LBA)
  instead.
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
| [extlinux.conf.example](extlinux.conf.example) | menu.c32 boot menu: `x` (default once the graphics stage is installed), `tc-text`, `tc`, `w98n` (grub4dos, Win98 SE as it boots on the 755C), `rescue` |
| [WIN98-INSTALL.md](WIN98-INSTALL.md), [win98/](win98/) | Windows 98 SE on `sdb1`, driven over serial: the W98SERIAL boot floppy (`mk-win98-floppy.sh`, DOS console on COM1), unattended `MSBATCH.INF` (`mk-msbatch.sh`), BIOS reach probes (`mk-probes.sh`), a static i486 `fatresize` to grow C: (`build-fatresize.sh`), and what worked on the real 755C. Tiny Core stays the default |
| [xautostart/](xautostart/xautostart), [mk-xautostart.sh](mk-xautostart.sh) | `xautostart.tcz`: starts X at boot from `onboot.lst` (skipped with `notx` or on the stock kernel); see docs/GRAPHICS.md section 6 "X by default" |
| [serial-getty.md](serial-getty.md), [repack-core-serial.sh](repack-core-serial.sh) | serial login on COM1: what tc32 already has, and how to add or change a ttyS0 getty in a `core.gz` / `core.xz` |
| [installer.txt](installer.txt) | login banner on the installer floppy |
| [test-qemu.py](test-qemu.py) | the QEMU test (`--full` = install end to end) |
| [test-chs.sh](test-chs.sh) | unit test for the CHS fields `install-dualcf` writes into the slave's partition table |

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

## PC Card (verified)

The tc32 kernel has no PC Card support (`# CONFIG_PCCARD is not set`, a
floppy-size choice). The graphics-stage kernel does, as modules:
`pcmcia-755c.tcz` from
[thinkpad-755c-drivers](https://github.com/branpurn/thinkpad-755c-drivers)
(PC Card core, `i82365`, `pata_pcmcia` for CF/ATA cards, `serial_cs` for
modems), built against `vmlinuz.x` by `scripts/build-gfx-kernel.sh 755c`
into `out/gfx/755c/`. Its load hook gives the sockets their I/O and memory
windows (on an ISA-only machine nothing else does) and prints one line.

Install: copy `pcmcia-755c.tcz` and `.tcz.dep` to `/mnt/sdb2/tce/optional`
and add it to `onboot.lst` **after** `modutils.tcz` (tc32's `tce-load`
does not read `.dep` files). To try it without a reboot:
`tce-load -i modutils.tcz pcmcia-755c.tcz`, or run
`/usr/local/tce.installed/pcmcia-755c` again (it is idempotent). Check
`ls /sys/class/pcmcia_socket`,
`cat /sys/class/pcmcia_socket/*/available_resources_setup_done` (`yes`),
`lsmod` and `dmesg`.

Seen on the 755C (kernel `6.18.57-tc755x`):
* the controller probes as **"Intel i82365sl B step" at 0x3e0, 2
  sockets**, card IRQs 3,5,7,9,11,15, status change IRQ 15;
* the memory window 0xd0000-0xdffff probes clean;
* a SanDisk CF card (8 GB, 15,625,216 sectors) in a CF-to-PC Card adapter
  gets IRQ 3 and comes up as `ata2` (PIO0, cmd 0x110, ctl 0x11e) and
  **`sdc`**, with its FAT32 `sdc1` mountable (tested read-only);
* Windows 98 needs such a card partitioned, not a superfloppy:
  [WIN98-INSTALL.md](WIN98-INSTALL.md#cf-cards-in-the-pc-card-slot).

Details, module load order and kernel notes (vermagic, `TRIM_UNUSED_KSYMS`,
`tcic`, `pd6729`) are in that repo's `docs/HARDWARE.md`.

Still to do with a [PicoPCMCIA](https://github.com/yyzkevin/PicoPCMCIA)
(open-source RP2350-based Type II, 5 V, 16-bit PC Card that emulates
NE2000 networking over Wi-Fi, a modem, Sound Blaster / GUS / MPU-401 audio,
a CD-ROM and storage):

- [ ] NE2000 emulation through `pcnet_cs`; needs TCP/IP (`CONFIG_INET`),
      which the X kernel leaves out (it has `NET` for AF_UNIX only).
- [ ] Its storage emulation as an ATA card (`pata_pcmcia`, already in
      `pcmcia-755c.tcz`).
- [ ] Audio: Sound Blaster emulation needs ALSA (`snd-sb*`), a bigger
      kernel, which belongs in the X second stage, not on the floppy.
- [ ] Measure the power draw in the 755C (the project quotes a 150 mA budget
      for networking plus storage).

## Testing

```sh
make installer && errata/755c/build-floppy.sh -N     # -> out/tc755c-installer.img
python3 errata/755c/test-qemu.py                      # boot, ttyS0 shell, detect, refusals
python3 errata/755c/test-qemu.py --full               # + prepare, serial send, finish, disk boot
errata/755c/test-chs.sh                               # partition-table CHS for the 755C geometry (no QEMU)
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
