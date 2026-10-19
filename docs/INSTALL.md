# Installing tc32 onto the 755C's IDE disk, and serial file transfer

The 755C's disk can be any IDE device: here a 2 GB CompactFlash card in a
CF-to-IDE adapter, which the BIOS treats as an ordinary hard disk. The
**installer floppy** (`out/installer.img`) replaces whatever is on that disk
(e.g. Windows 95) with a tc32 install that boots without the floppy.

## Why a separate installer floppy

The rescue floppy (`out/tc32.img`) stays the minimal boot-and-rescue core.
`installer.img` uses the **same** `vmlinuz` and `core.xz`, which are also
what gets copied to the disk, plus a small second initramfs, `install.xz`
(about 69 KiB), loaded with `initrd=core.xz,install.xz`. It contains only:

* `/usr/sbin/install-to-disk`, the install script (busybox ash);
* `/usr/sbin/extlinux`, the syslinux 4.07 extlinux installer, static i486 musl;
* `/usr/share/tc32/mbr.bin` (syslinux 4.07 MBR code) and the
  `extlinux.conf` template;
* a login banner.

Putting this on the rescue floppy would have used more than half of its
free space. As a separate image, the rescue floppy's budget is untouched
(only the `rx`/`sha256sum`/`md5sum`/`blockdev` applets were added to the
shared busybox, about 3 KiB). The installer floppy also has a `rescue`
label that boots plain tc32 without the overlay.

The driver side needed nothing new. The kernel has carried libata
`pata_legacy` (ISA/legacy IDE at 0x1f0/irq 14 and 0x170/irq 15), SCSI disk,
MSDOS partitions, ext2 and 8250 serial since phase 1 (`config/kernel-hdd.fragment`).

**IDE driver choice.** The old `drivers/ide` (`/dev/hda`) was removed from
Linux in 5.14, so on 6.18 the disk is libata's **`/dev/sda`**. The 755C has
no PCI. `ata_generic` and `ata_piix` are PCI drivers, and `pata_isapnp` needs
ISA PnP, so **`pata_legacy`** is the right driver for a 486 ISA IDE port. The
kernel is built without PCI, so `pata_legacy` probes the primary and
secondary legacy ports directly. That works on QEMU's `-M isapc` (plain
ISA IDE) and on `-M pc`, where the PIIX sits at the legacy addresses in
compatibility mode. Both are tested.

## Disk layout

| Sectors (512 B) | Size | Contents |
|---|---:|---|
| 0 | | syslinux `mbr.bin` + MBR partition table (disk id `7c320486`) |
| 1–2047 | 1 MiB | zeroed gap (old Win95 boot code wiped) |
| `sda1` 2048 + 256 MiB | 256 MiB | **ext2**, label `TC32`, **bootable**: `/boot/vmlinuz`, `/boot/core.xz`, `/boot/sha256.txt`, `/boot/extlinux/{ldlinux.sys,extlinux.conf}`, `/tce/optional/`, `/tce/onboot.lst` |
| `sda2` next 64 MiB | 64 MiB | Linux swap (type 82, auto-enabled by rcS) |
| rest | ~1.5 GiB of a 2 GB card | **unpartitioned**, reserved for the future second stage |

Notes on the choices:

* tc32 still runs from RAM, the Tiny Core "frugal" way. The disk holds the
  kernel and `core.xz` (which contains the busybox userland) plus the
  `tce` directory. The installed boot line adds `tce=sda1`, so extensions
  in `/tce/optional` and `onboot.lst` load from disk, as the second stage
  will.
* **Everything the BIOS must read lies inside the first 504 MiB**
  (1024 cyl × 16 heads × 63 sectors). A 1994 BIOS without LBA or
  translation can only reach that much of the disk. The partition table's
  CHS fields use 16 heads × 63 sectors. `mbr.bin` and `ldlinux.sys` use the
  LBA values (EDD when the BIOS has it, CHS otherwise).
* ext2 has no journal (fewer CF writes) and is supported by extlinux 4.07.
  The filesystem is made by busybox `mke2fs` with 1 KiB blocks and 1%
  reserved.
* Swap matters at 32 MB. Use `-w 0` to skip it if you'd rather spare the CF
  card. `-s MB` sets the size of `sda1`.
* The unpartitioned rest can become `sda3` later. Nothing in tc32 touches it.

## Running the installer

1. Write the image: `dd if=out/installer.img of=/dev/fdX bs=512 conv=fsync && cmp out/installer.img /dev/fdX`.
2. Boot it on the 755C (BIOS boot order: floppy first). The `install`
   label boots by itself after 3 s, with the console on VGA and COM1 at
   9600, and `noswap`, so the target disk is not in use.
3. At the root shell:
   ```sh
   install-to-disk -n /dev/sda     # dry run: disk model/size, current table, new layout
   install-to-disk /dev/sda        # type YES (capitals) when asked
   ```
   The script:
   1. copies `vmlinuz` and `core.xz` from the floppy into RAM and checks them
      against the floppy's `sha256.txt`, so a bad floppy stops it *before*
      anything is written;
   2. prints the plan and requires **`YES`**. Any other answer aborts with
      nothing written;
   3. releases the disk (swapoff, umount);
   4. zeroes the first MiB, writes `mbr.bin` + the new table, and re-reads it;
   5. runs `mke2fs` on `sda1` and `mkswap` on `sda2`;
   6. copies the files and writes `extlinux.conf`;
   7. runs `extlinux --install /boot/extlinux`;
   8. remounts and verifies the sha256 sums from the disk.
4. Remove the floppy and `reboot`. The disk shows the same `boot:` prompt
   (also on COM1) and auto-boots after 3 s. Labels: `tc32` (default),
   `vga`, `generic` (non-ThinkPad), `notce`.

Re-running is safe. A full install always produces the same layout and an
identical MBR. `install-to-disk -u /dev/sda` keeps the partitions and `/tce`
and only refreshes the kernel, `core.xz`, `extlinux.conf`, `ldlinux.sys` and
the MBR boot code. Use it after rebuilding the floppy. `-S DIR` takes the
kernel and `core.xz` from a directory instead of the floppy. The script
refuses partitions (`/dev/sda1`), the floppy and loop/ram devices.

## Serial file transfer (COM1, XMODEM)

**Yes, files can go over the RS-232 link.** busybox `rx` (XMODEM receive,
CRC, 1 KiB blocks) is in the shared busybox. So are `sha256sum` and
`md5sum`, for checking. The host sends with `sx` from lrzsz. Because XMODEM
pads the last block, the receiver cuts the file back to its exact size.

The link is the console line itself: a StarTech ICUSB232FTN (FTDI, built-in
null-modem wiring) as `/dev/ttyUSB0` on the host. The **console stays at
9600** by default. Bulk transfers switch both ends to 115200 and back again.

### With the helper (recommended)

Quit picocom first (`C-a C-q`), with the 755C sitting at its shell prompt:

```sh
tools/send-file.sh second-stage.tcz /dev/ttyUSB0 /mnt/sda1/tce/optional/second-stage.tcz
#   -b 115200 (default) transfer rate; -b 9600 = no switching; -c 9600 console rate
```

It types this one command line on the 755C:
1. lower the console loglevel (so kernel messages can't land in the
   protocol stream);
2. `stty 115200; rx FILE.part; stty 9600`;
3. cut the file to its exact size;
4. `sha256sum`.

Meanwhile it runs `sx -k` at 115200, switches back to 9600, compares the
remote sha256 with the local one, and exits 0 only if they match. It
prints the time and bytes/s. If you see retries or a mismatch, try
`-b 57600` or `-b 38400`. Without lrzsz on the host, `make tools` builds
`sx` into `build/host/bin`.

### By hand with picocom

```sh
picocom -b 9600 --send-cmd "sx -k -vv" /dev/ttyUSB0
```
On the 755C type `rx /tmp/file`. Within 100 s press `C-a C-s` and give the
local file name. Afterwards, compare `sha256sum /tmp/file` with the host's
`sha256sum`. To go faster, type `stty 115200; rx /tmp/file; stty 9600` on the
755C, then press `C-a C-u` in picocom until it reports 115200, send, and
step back down to 9600 with `C-a C-d`. XMODEM may leave up to two `^Z` pad bytes at the
end. The helper avoids this, and `.tcz`/`.xz`/`.gz` files tolerate it.

### Expected throughput

| Rate | Line maximum | XMODEM-1K, realistic | 1 MiB takes |
|---|---:|---:|---:|
| 9600 8N1 | 960 B/s | ~900 B/s | ~19 min |
| 115200 8N1 | 11,520 B/s | ~10–11 KB/s if the UART keeps up | ~1.5–2 min |

XMODEM is stop-and-wait with CRC, so a dropped byte costs a 1 KiB block
retry, not corruption. Whether the 755C's UART (16450 or 16550A) keeps up
at 115200 is not verified yet. In QEMU (`make test-install`) a 192 KiB
transfer reaches about 55–70 KB/s, faster than any real line. QEMU's UART
doesn't pace data at the configured baud, so that figure shows the
protocol and helper working, not real-hardware speed.

## Real-hardware checklist (755C)

1. **BIOS setup** (Easy-Setup / F1 at power-on): serial port **enabled**
   as COM1 (0x3F8, IRQ 4); IDE disk detected; boot order **floppy (A:)
   first**, then the hard disk. Note the disk size the BIOS reports. If it
   shows only ~504/528 MB, the BIOS has no LBA. That is fine, because the
   tc32 boot area lies inside the first 504 MiB.
2. **Host:** plug the ICUSB232FTN into the 755C's 9-pin serial port.
   It is already a null-modem, so add no extra null-modem adapter. On the
   host, `picocom -b 9600 /dev/ttyUSB0` (user in group `dialout`). Expect
   the syslinux banner + `boot:` (on COM1 at 9600), the kernel log, and
   then the `root@box:~#` prompt plus the installer banner.
3. Boot the installer floppy, `install-to-disk -n /dev/sda`, and check
   the model and size (a "2 GB" card is about 1907 MiB). Then run
   `install-to-disk /dev/sda` and type `YES`.
4. Remove the floppy and `reboot`. On picocom you should see the extlinux
   `SAY` line `tc32 (disk): boots in 3 s ...` and `boot:`, then the same
   kernel log and a shell. Check that `cat /proc/swaps` shows `sda2` and
   `readlink /etc/sysconfig/tcedir` shows `/mnt/sda1/tce`.
5. If the disk does not boot: check the BIOS boot order and that the
   adapter/card is set as **master**. As a fallback, boot the floppy's
   `rescue` label with `tce=sda1` to reach the installed files.
6. Transfer test: send a small file at 9600 first, then at 115200
   (`tools/send-file.sh -b 9600 ...`, then the default).
