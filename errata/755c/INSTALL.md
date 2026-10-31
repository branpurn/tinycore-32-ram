# Installing the 755C dual-CF setup, step by step

The result: the master CF holds tc32 and the boot menu, and the slave CF
holds Win98 SE plus the `tcdata` store (see [README.md](README.md#hardware-layout)).
Commands marked `host$` run on the Linux host, and `tc#` runs on the 755C
serial console. Steps marked **(unverified)** have only been run in QEMU
(`make`-built image, `-M isapc -cpu 486 -m 32`, 4 GiB + 128 GiB disks), not on
the real 755C.

> `prepare` erases **both** cards. Copy anything you want to keep off them
> first.

## You need

- The 755C, with COM1 enabled in its BIOS setup (0x3F8, IRQ 4).
- A dual CF-to-IDE adapter, set up with a 4 GB CF as **master** and a
  128 GB CF (True IDE capable) as **slave**.
- A 1.44 MB floppy disk, and a way to write it (a USB floppy drive on the
  host).
- An FTDI USB serial adapter and a **null-modem** cable.
- A Linux host with `picocom` and `lrzsz` (`sx`). If the host has no
  lrzsz, `make tools` builds `sx`.
- For Windows 98 SE: a Win98 SE boot floppy, plus the `\WIN98` folder from
  the CD (the 755C has no CD-ROM drive), and a USB CF reader on the host.

## A. Build and write the floppy (host)

1. Build the image. It is reproducible (`SOURCE_DATE_EPOCH`, `TZ=UTC`), so
   the same tree gives the same sha256:
   ```sh
   host$ make installer                     # kernel, core.xz, install.xz, syslinux 4.07
   host$ errata/755c/build-floppy.sh -N     # -> out/tc755c-installer.img (1,474,560 bytes)
   ```
   It contains `vmlinuz` (i486), `core.xz`, `install.xz` and `e755c.xz`
   (`install-dualcf`). That leaves about 20 KB free, too little for
   menu.c32 and chain.c32, so those two go over serial in step 12.
2. Optional: run the QEMU test:
   `python3 errata/755c/test-qemu.py --full`. It should print 25 `PASS`.
3. Write the floppy and read it back:
   ```sh
   host$ sudo dd if=out/tc755c-installer.img of=/dev/sdX bs=18k conv=fsync   # sdX = the USB floppy
   host$ sudo cmp -n 1474560 out/tc755c-installer.img /dev/sdX && echo floppy OK
   ```
   Old disks have bad sectors. If `cmp` reports a difference, use another
   disk.

## B. Boot the installer (755C)

4. Connect the FTDI adapter and null-modem cable to COM1 on the 755C, then
   open the console on the host:
   `host$ picocom -b 9600 /dev/ttyUSB0`
5. Insert the floppy and power on. On the serial console you will see
   `tc32 755C dual-CF installer: boots in 3 s.` Press Enter, or wait, to
   get the `install` entry. After the kernel loads (about a minute from
   floppy, **unverified** timing), a root shell appears on both COM1 and
   the screen, under the `tc32 INSTALLER, ThinkPad 755C dual-CF edition`
   banner.
   - If the serial console stays silent, check the null-modem cable and
     the COM1 BIOS setting. The VGA console works either way.
6. Detect the disks (this writes nothing):
   ```
   tc# install-dualcf detect
   ```
   You should see `/dev/sda master (0:0:0:0) ... MB` and
   `/dev/sdb slave (0:0:1:0) ... MB`. These names come from libata, so
   there is no `hda` or `hdb` here. If the slave is missing, check the
   jumper and True IDE mode, and look at
   `dmesg | grep -iE 'ata|sd[a-z]'` for `ata1.01`. **(unverified with the
   real cards)**
7. Dry run: `tc# install-dualcf -n prepare` prints the plan and writes
   nothing. Defaults: `sda1` 256 MB boot plus `sda2` 64 MB swap; `sdb1`
   2048 MB FAT32 type `0b`, active; `sdb2` the rest of the card as ext2
   `tcdata`. Change them with `-s`, `-w`, `-f` and `-t 0c`.

## C. Partition and format both cards

8. Run the installer:
   ```
   tc# install-dualcf prepare
   ```
   Type exactly **`ERASE sda sdb`**. Any other answer (including `YES`,
   lower case, or an empty line) prints `Aborted; nothing was written.`
   The installer then:
   - runs `install-to-disk` on sda (MBR, ext2 `TC32`, swap, vmlinuz and
     core.xz, extlinux);
   - writes the MBR and partitions on sdb;
   - runs `mkfs.vfat` on sdb1 (a placeholder, see step 15);
   - runs `mke2fs -L tcdata` on sdb2;
   - creates `tce/ home/ opt/ incoming/` and writes a menu-less
     `extlinux.conf`.

   It takes 5 s in QEMU. On a 486 with a 128 GB card, `mke2fs` will take
   much longer **(unverified: minutes to tens of minutes)**. It ends with
   `Done. Send files to sdb2:/incoming ...`.
9. Check the result:
   ```
   tc# fdisk -l /dev/sda /dev/sdb
   tc# cat /proc/partitions
   ```
   Expected: `sda1 *` type 83, `sda2` type 82, `sdb1 *` type b, `sdb2`
   type 83.

## D. Send menu.c32 and chain.c32 over serial

10. On the 755C, mount tcdata and stay at the prompt:
    ```
    tc# mkdir -p /mnt/tcdata && mount -t ext2 /dev/sdb2 /mnt/tcdata
    ```
11. Quit picocom with **C-a C-q**, which leaves the line settings alone.
    Only one program may hold the port.
12. Send the two syslinux 4.07 modules. They must be the **same version**
    as the extlinux on sda1, and the build tree has exactly that version:
    ```sh
    host$ sudo errata/755c/host-send.sh /dev/ttyUSB0 \
            build/syslinux-4.07/com32/menu/menu.c32 \
            build/syslinux-4.07/com32/chain/chain.c32
    ```
    Each file goes by XMODEM-1K at 38400 (the default). `tools/send-file.sh`
    compares sha256 on both ends, and then host-send.sh sends a
    `SHA256SUMS` list. The 755C manages about 1.9 KB/s, so the two files
    (94 KB) take about a minute. You can add files to the same command:
    - a newer `vmlinuz` or `core.xz`;
    - a repacked core (see [serial-getty.md](serial-getty.md));
    - `onboot.lst`;
    - `*.tcz` extensions, which go to `sdb2:/tce/optional`.
    Use `-b 9600` if 38400 fails.
13. Reconnect (`host$ picocom -b 9600 /dev/ttyUSB0`) and install the files:
    ```
    tc# install-dualcf finish
    ```
    `finish` does the following:
    - checks `SHA256SUMS` (strict format, then `sha256sum -c`). If
      anything does not match, it stops with `checksum mismatch: resend
      the files` and installs nothing;
    - copies each file into place (`*.c32` to `/boot/extlinux`) through a
      `.new` file plus `mv`;
    - writes the menu `extlinux.conf`, the same as
      [extlinux.conf.example](extlinux.conf.example);
    - remounts read-only and checks the files.

    It ends with `Verified. Remove the floppy and type: reboot`.
    Use `-b BAUD` here only if you also changed the core's getty speed.
14. Remove the floppy, then `tc# reboot`. The `ThinkPad 755C` menu appears
    on screen and on COM1 with three entries, and `tc` boots after 5 s:
    - `tc`: Tiny Core, `tce=sdb2`, so extensions and `onboot.lst` load
      from tcdata. Check with `readlink /etc/sysconfig/tcedir`, which
      should print `/mnt/sdb2/tce`.
    - `win98`: `chain.c32 hd1 1 swap`. This boots sdb1 with the BIOS disks
      swapped, so Windows sees its card as disk 0x80.
    - `rescue`: the same core, with `tce=sda1 norestore`.

    In QEMU, the menu and the default `tc` boot were checked. **On the
    real 755C, the menu rendering on VGA and serial is unverified.**

## E. Windows 98 SE on sdb1 (unverified)

None of this part has been tested, in QEMU or on the 755C.

15. Format sdb1 from DOS. The placeholder FAT32 from `mkfs.vfat` has no DOS
    boot code. Boot the **Win98 SE boot floppy** in the 755C, without CD
    support. sda has no DOS partition, so DOS should give **C:** to sdb1.
    Check with `DIR C:`: the volume label should be `WIN98SE`. Then:
    ```
    A:\> FORMAT C: /S
    ```
    This writes the FAT32 boot sector (with hidden sectors = 2048, the
    partition start) and the system files. **Do not run `FDISK /MBR`**,
    because disk 0x80 is the tc32 card.
16. Copy the Win98 SE setup files onto the card. Over serial at 1.9 KB/s,
    `\WIN98` (over 100 MB) would take many hours. Instead, shut down, take
    the slave CF out, and on the host copy the CD's `\WIN98` folder to
    `sdb1` (it shows up as a FAT32 partition through a USB CF reader). Then
    put the card back as slave.
17. Boot the Win98 boot floppy again, then
    `C:\> CD \WIN98` and `C:\> SETUP`.
    Windows Setup reboots several times. At each reboot, **pick `win98`
    in the menu**, because the default `tc` starts after 5 s. Setup may
    write its own boot code to the MBR of disk 0x80, which is the tc32
    master card. If the menu is gone afterwards, follow recovery step R2.
18. Check from Linux that Windows did not touch tcdata: boot `tc`, then
    `tc# fdisk -l /dev/sdb` and `tc# ls /mnt/sdb2/tce`.

Known caveats for Win98 **(unverified)**:
- The 755C BIOS may only reach the first 504 MB of each card. Win98's
  protected-mode IDE driver handles the rest. If you see "Invalid system
  disk" or a hang after `win98`, try `APPEND hd1 1 swap setbpb` in
  extlinux.conf (chain.c32 then patches the BPB geometry and drive number).
  You can also try type `0c` (`install-dualcf -t 0c prepare`, which
  re-erases both cards).
- Win98 drive letters with two disks: Windows itself is C: (it sees its
  card first because of `swap`). The tc32 card has no FAT partition, so it
  gets no letter.

## Recovery

| Problem | Fix |
|---|---|
| **R1**: you need a shell on the installed system without its own boot | Boot the floppy (`install` entry), then `mkdir -p /mnt/b /mnt/d && mount /dev/sda1 /mnt/b && mount /dev/sdb2 /mnt/d`. |
| **R2**: no menu or boot prompt from the master card (Windows or `FDISK /MBR` replaced the MBR, or extlinux is broken) | Floppy, `install` entry, then `install-to-disk -u /dev/sda` and type `YES`. This rewrites the MBR boot code (keeping the partition table and disk id), extlinux, vmlinuz and core.xz, and leaves tce data alone. Then run `install-dualcf finish`: the files and `SHA256SUMS` are still in `sdb2:/incoming`, so it reinstalls the .c32 modules and the menu config. |
| **R3**: the menu shows, but `tc` hangs or panics | Pick `rescue` (the same kernel, no tcdata), or press Tab in the menu to edit the command line. A bad extension in tcdata can stop boot: from rescue, `mount /dev/sdb2 /mnt/d` and edit `/mnt/d/tce/onboot.lst`. |
| **R4**: menu.c32 fails (`: not a COM32R image`, or the screen goes blank) | A .c32 does not match ldlinux. Use R1, then `sed -i '/^UI menu.c32/d' /mnt/b/boot/extlinux/extlinux.conf` to get the plain `boot:` prompt (type `tc`, `win98` or `rescue`). Then resend the 4.07 modules from `build/syslinux-4.07` (step 12) and run `install-dualcf finish`. |
| **R5**: garbage on the serial console after the kernel starts | The baud rates do not match (`SERIAL`, `console=` and the core's getty). Reconnect at 9600. If you repacked the core to another speed, use R1 and run `install-dualcf -b <that speed> finish`, or resend the original `core.xz`. |
| **R6**: `finish` says checksum mismatch or a bad line format | Resend the files (step 12). Partial files are never installed. To start over: `rm /mnt/tcdata/incoming/*`. |
| **R7**: the slave card is not detected | Check the jumper, True IDE mode and the card in another adapter. `install-dualcf` refuses to run without both disks. The tc32-only installer (`install-to-disk /dev/sda`, docs/INSTALL.md) still works on the master alone. |
| **R8**: start over completely | Run `install-dualcf prepare` again. Same layout, and everything on both cards is erased again. |

## What has and has not been verified

QEMU checks, with `errata/755c/test-qemu.py --full`:
- The floppy boots a 486 with 32 MB, gives a shell and the tc32-getty on
  ttyS0, and sees sda as master and sdb as slave.
- Every confirmation answer except the exact text is refused, and the
  disks stay unchanged.
- The layout and the tcdata tree are created.
- Serial transfer works, a corrupted file is refused, and finish installs
  and verifies.
- The disk boots into the menu, then `tc` with `tce=sdb2`.

Not verified (real 755C hardware):
- floppy boot time, and the detection of the real CF cards;
- `mke2fs` time on 128 GB;
- BIOS access to sdb1 (504 MB limit, `0b` vs `0c`);
- menu.c32 on the 755C's VGA and serial;
- all of part E (Win98 SE install and boot, and whether Windows Setup
  overwrites the master MBR);
- the speeds above 9600 for the console.
