# Windows 98 SE on the 755C slave card, driven over serial

This replaces steps 15 to 17 of [INSTALL.md](INSTALL.md#e-windows-98-se-on-sdb1-unverified).
**Tiny Core stays the main system; Windows is extra.** The procedure only
writes to:

* `sdb1` (the slave card's FAT32 `WIN98SE`, 2 GiB in the plan), and
* `sda1` (the master's ext2 boot partition), **additively**: a backup copy
  of `extlinux.conf`, one new menu entry, `DEFAULT` switched for the
  install and switched back, and backup files.

It never writes to `sdb2` (`tcdata`), the master's MBR or partition table,
or `sda2`. Windows Setup is told not to touch the MBR (`/IR`).

Status (2026-11-01): **Windows 98 SE is installed on `sdb1` and boots to
the desktop on the real 755C.** The floppy, `MSBATCH.INF` and the
unattended Setup below did the install. The BIOS reach, the size of C:
and the boot entry came out differently from the plan; the next section
has what worked. The step-by-step sections after it are the plan as it
was written before the hardware, kept for reference.

## What worked on the real 755C

### BIOS geometry: about 7.9 GB, not 504 MiB

grub4dos's `geometry` command reports:

| BIOS disk | Card | Cylinders / heads / sectors | Sectors |
|---|---|---|---|
| 0x80 | master (tc32) | 7736 / 128 / 63 (as reported) | |
| 0x81 | slave (Win98 + tcdata) | **1022 / 240 / 63** | **15,452,640** (about 7.9 GB, 7.37 GiB) |

So real-mode DOS and Windows reach the slave up to LBA 15452639, and the
504 MiB guard ([BIOS reach](#bios-reach-504-mib-and-the-2-gib-partition),
`HIFILL*.BIN`) was not needed. The partition table's CHS fields must use
the 240-head geometry: `install-dualcf` used to assume 16 heads, which
gives the wrong CHS for type `0b` (fixed, with `-g C/H/S`; tested by
[test-chs.sh](test-chs.sh)). The master's own MBR comes from
`install-to-disk`, and syslinux's `mbr.bin` reads by LBA, so its CHS
fields do not matter.

### C: grown to the BIOS limit

`sdb1` now runs from LBA 2048 to **15452639**, type `0b`, FAT32 with
4 KiB clusters, label `WINDOWS` (about 7.4 GB). `sdb2` (`tcdata`) was
re-created as ext2 behind it. A fresh `install-dualcf prepare` now writes
this layout by default (`-f max`).

C: was grown in place with **fatresize** (libparted's FAT resizer), built
static for i486 so it runs under tc32 on the 755C:
[win98/build-fatresize.sh](win98/build-fatresize.sh) (fatresize 1.1.0
at commit 75cbc38, libparted 3.6, libuuid from util-linux 2.40.2, musl.cc
i486 toolchain; about 480 KB). The binary is not in the repo. Outline,
from a tc32 root shell with Windows shut down cleanly:
```sh
# Copy whatever you need off sdb2 first: growing sdb1 overwrites it.
dd if=/dev/sdb of=/mnt/sda1/sdb-first1MiB.bak bs=512 count=2048   # MBR + gap
umount /dev/sdb1 /dev/sdb2 2>/dev/null
fdisk -lu /dev/sdb                       # note sdb1's start (2048)
# Delete sdb2 with fdisk, then grow sdb1 and its FAT32 to end at LBA 15452639.
# -s is in bytes: (15452640 - 2048 - 1) * 512. libparted counts the end
# sector inclusively, so one sector less than the partition gives the exact end.
./fatresize -f -n 1 -s 7910702592 /dev/sdb
fdisk -lu /dev/sdb                       # sdb1 2048..15452639, type b
```
(Checked on an image file laid out like the card: the partition ends at
15452639, the FAT32 grows to 15,450,592 sectors, and `fsck.vfat -n` is
clean.)
* libparted resets the boot sector's volume label to `NO NAME`. Put it
  back with `LABEL C: WINDOWS` in DOS or Windows (or `fatlabel` on a Linux
  host).
* If the partition type changed, set it back to `b` with fdisk.
* Then re-create `sdb2` from the next MiB boundary (LBA 15454208) to the
  end of the card, type `83`, and
  `mke2fs -F -L tcdata -m 1 -i 262144 -I 128 /dev/sdb2`;
  `mkdir -p tce/optional home opt incoming` on it, and restore.

### Boot entry: grub4dos loads IO.SYS from the slave, no drive swap

This entry in `extlinux.conf` boots Win98 SE (`grub.exe` from a grub4dos
release, copied to `/boot` on `sda1`; not built here):
```
LABEL w98n
  MENU LABEL Windows 98 SE (sdb1, grub4dos, no drive swap)
  KERNEL /boot/grub.exe
  APPEND --config-file="root (hd1,0);chainloader /io.sys;boot"
```
The master has no FAT partition, so DOS and Windows give C: to `sdb1`
even though it stays BIOS disk 0x81. The label used on the 755C also
points grub4dos's own terminal at COM1 first; that part is optional.

What did not work:
* **A grub4dos drive swap** (`map (hd0) (hd1)`, `map (hd1) (hd0)`,
  `map --hook`): Windows stops with a `KRNL386.EXE` access-denied error.
  grub.exe marks its INT 13h hook as a "safe MBR hook" (`$INT13SF`
  signature, `smhflgs=1`), so Windows 98 bypasses the hook, and with it
  the swap.
* **Chainloading the `sdb1` boot sector** without a swap: it hangs. The
  boot sector's BPB drive number is `80h`, so its code reads disk 0x80
  (the tc32 card) instead of 0x81.

The plan's `win98` / `win98s` (`chain.c32 ... swap`) entries are
superseded by `w98n`.

### CF cards in the PC Card slot

Tiny Core reads them through `pcmcia-755c.tcz`
([README.md](README.md#pc-card-verified)). In Windows 98, a CF card in
a CF-to-PC Card adapter that was formatted **without a partition table**
(a "superfloppy": FAT32 on the whole device) shows up in FDISK as a bogus
disk of about 69 MB and gets no drive letter. Fix, from Linux (this
erases the card):
```sh
D=/dev/sdX                                   # the CF card, check with fdisk -l first
echo 'start=63, type=c' | sfdisk "$D"        # MBR + one FAT32 LBA (0c) partition at sector 63
mkfs.vfat -F 32 "${D}1"
```
(busybox `fdisk` works too: `n`, `p`, `1`, first sector `63`, `t`, `c`,
`w`.) Windows 98 then binds the card to "Standard IDE/ESDI Hard Disk
Controller" and mounts it as the next drive letter.

### Experimental: a DOS prompt on COM1 under Windows

Windows 98 can run a `COMMAND.COM` on COM1 from `RunServices`, which
starts before the logon dialog:

`C:\SERCON.BAT`:
```
MODE COM1:9600,N,8,1
CTTY COM1
```
`SERCON.REG` (import with `REGEDIT SERCON.REG`):
```
REGEDIT4

[HKEY_LOCAL_MACHINE\Software\Microsoft\Windows\CurrentVersion\RunServices]
"SerCon"="C:\\COMMAND.COM /K C:\\SERCON.BAT"
```
Before logon, the prompt on COM1 works both ways. **After logon, input
drops characters** (output is fine), so treat it as a read-mostly console.
To remove it, delete the `SerCon` value.


## The pieces

| File | What it does |
|---|---|
| [win98/mk-win98-floppy.sh](win98/mk-win98-floppy.sh) | Builds `w98serial.img`, the boot floppy. It takes the El Torito floppy image from the Win98 SE CD, so the boot sector, `IO.SYS`, `COMMAND.COM`, `HIMEM.SYS` and the CD drivers are Microsoft's own. It replaces `CONFIG.SYS`/`AUTOEXEC.BAT` and adds `MODE`, `FIND`, `FC`, `DEBUG`, `MEM` and `SYS` from the CD's cabinets, plus the batch files below. No root needed (mtools, cabextract, xorriso). |
| [win98/floppy/](win98/floppy/) | Files for the floppy (stored with LF; the script converts them to CRLF). `AUTOEXEC.BAT` runs `MODE COM1:9600,N,8,1`, then `CTTY AUX`, so the DOS prompt is on COM1 at 9600 8N1, the same as the Tiny Core console. |
| [win98/MSBATCH.INF.in](win98/MSBATCH.INF.in), [win98/mk-msbatch.sh](win98/mk-msbatch.sh) | The unattended Setup script. `mk-msbatch.sh` fills in the product key from an env file and writes `\WIN98\MSBATCH.INF` with CRLF line ends. The key is never printed and never passed on a command line. |
| [win98/mk-probes.sh](win98/mk-probes.sh) | Places the BIOS reach probes and filler files on `sdb1` (see [BIOS reach](#bios-reach-504-mib-and-the-2-gib-partition)). |

Floppy commands (typed on the serial console):

| Command | What it does |
|---|---|
| `CHK` | `VOL C:` (expect `WIN98SE`), `DIR` of `C:\WIN98\SETUP.EXE` and `MSBATCH.INF`, `MEM`, BIOS disk geometry (`DEBUG < GEO.SCR`), then `PROBE` |
| `PROBE` | `FIND "W98PROBE"` on each of `C:\PROBE\P0400.TXT` ... `P2040.TXT` |
| `UNFILL` | Deletes `C:\PROBE\HIFILL*.BIN`. Run it **only** if every probe passed. |
| `W98SETUP` | `CTTY CON`, then `SETUP.EXE C:\WIN98\MSBATCH.INF /IS /IQ /IE /IM /IR /IV /NF`. Serial output ends here. |
| `SYS C:` | Fallback only: puts DOS boot files on C: (see [Recovery](#recovery)). |

### Setup switches

Checked against the Windows 98 Resource Kit (Table 2.18, Setup switches):

| Switch | Meaning |
|---|---|
| `C:\WIN98\MSBATCH.INF` | The batch script. It must be an 8.3 name, given with its full path. |
| `/IS` | No ScanDisk. |
| `/IQ` | No ScanDisk cross-linked-file check (pairs with `/IS`). |
| `/IE` | Skip the Startup Disk screen (`EBD=0` in the INF as well). |
| `/IM` | Skip the low-conventional-memory check. |
| **`/IR`** | **Do not update the master boot record.** Without it, Setup writes its own boot code into the MBR of BIOS disk 0x80. While DOS is booted from the floppy, 0x80 is the **tc32 master card**, so this would remove the syslinux boot loader. |
| `/IV` | No billboards (fewer redraws on the 755C's slow video). |
| `/NF` | Don't ask to remove the floppy at the end of the DOS phase. |

`/C` (no SmartDrive) is **not** used: Setup loads SmartDrive itself, and
without it the DOS-phase copy is much slower.

### MSBATCH.INF

The settings are: `Express=1` (no questions); `InstallDir="C:\WINDOWS"`; `InstallType=1` (Typical);
`EBD=0` (no startup disk); `ShowEula=0`; `Uninstall=0`; `NoDirWarn=1`;
`TimeZone="Eastern"` (the Resource Kit's list has `Eastern`; `US Eastern` is
Indiana); `ComputerName="THINKPAD755C"`, `Workgroup="WORKGROUP"`; name
`ThinkPad 755C`, no organisation, no personal data; and the
`Skip.PCMCIA.Wizard` AddReg from the CD's Batch 98 tool.

* `ShowEula` and `ProductKey` are not in the Resource Kit's appendix, but
  Batch 98 (`\tools\reskit\batch` on the CD) writes them. Their spelling is
  taken from its `batch.exe`.
* `NoPrompt2Boot=1`: the appendix wording is ambiguous ("0 = Do not
  prompt"), while Batch 98's "reboot automatically" writes `1`. If Setup
  stops at "Setup will restart your computer, press Enter", press Enter on
  the 755C keyboard.

## Host side (a Linux PC, before the 755C)

H1. **Build the floppy image** (no root):
```sh
PATH=$HOME/win98se/tools/mt/usr/bin:$PATH   # mtools, if not installed
errata/755c/win98/mk-win98-floppy.sh ~/win98se/win98se.iso ~/win98se/boot/w98serial.img
```
The build is reproducible (`TZ=UTC`, fixed sources). The image built on
2026-11-01 has sha256
`08b40a38fa58fc77fe436a64e74e0b8c7288f1d3d946d5687b5fd62755a36743`.

H2. **Write it to a floppy.** The USB floppy belongs to group `disk`. Run
these in a terminal that has the group (`sg disk -c '...'`, or log in
again). The first command keeps a copy of whatever was on the disk:
```sh
F=/dev/disk/by-id/usb-TEAC_TEAC_FD-05PUB
cd ~/win98se/boot
sg disk -c "dd if=$F of=floppy-before.img bs=18k"
sg disk -c "dd if=w98serial.img of=$F bs=18k conv=fsync"
sg disk -c "dd if=$F of=readback.img bs=18k"
sha256sum w98serial.img readback.img        # both must match
```

H3. **Prepare sdb1** (the slave card in the USB CF reader). Mount **only
partition 1**. If the desktop automounts the ext4 `tcdata` partition,
unmount it at once (`udisksctl unmount -b /dev/sdX2`) and do not write to
it.
```sh
D=/dev/sdX                                  # check with lsblk: 2 partitions, WIN98SE + tcdata
udisksctl mount -b ${D}1                    # e.g. /media/$USER/WIN98SE
M=/media/$USER/WIN98SE
ls $M/WIN98/SETUP.EXE                       # the CD's \WIN98 folder
errata/755c/win98/mk-msbatch.sh ~/.secrets/win98se.env $M/WIN98/MSBATCH.INF
errata/755c/win98/mk-probes.sh $M ${D}1     # prints where each probe landed
sync; udisksctl unmount -b ${D}1; udisksctl power-off -b $D
```
`mk-probes.sh` fills almost all of the free space past ~500 MiB with
`\PROBE\HIFILL*.BIN`. That is deliberate (see below).

## On the 755C

### T. Tiny Core, over serial (before the Windows install)

By hand: put the 128 GB card back in the 755C as **slave**. Take the floppy
**out**. Power on. Tiny Core boots (`DEFAULT x`).

On the serial console (root shell). This adds a menu entry and makes it
the default for the install. The backups go to `sda1`, never to `sdb2`.
```sh
grep -q ' /mnt/sda1 ' /proc/mounts || { mkdir -p /mnt/sda1; mount /dev/sda1 /mnt/sda1; }
cd /mnt/sda1/boot/extlinux
cp -p extlinux.conf extlinux.conf.pre-win98
mkdir -p /mnt/sda1/backup-win98
dd if=/dev/sda of=/mnt/sda1/backup-win98/sda-first1MiB.bin bs=512 count=2048
dd if=/dev/sdb of=/mnt/sda1/backup-win98/sdb-first1MiB.bin bs=512 count=2048
dd if=/dev/sdb1 of=/mnt/sda1/backup-win98/sdb1-first64.bin bs=512 count=64
md5sum /mnt/sda1/backup-win98/*.bin
cat >> extlinux.conf <<'X'

# Windows 98 SE with the BPB fixed up in memory (errata/755c/WIN98-INSTALL.md).
LABEL win98s
  MENU LABEL Windows 98 SE (sdb1, setbpb)
  COM32 chain.c32
  APPEND hd1 1 swap setbpb
X
sed -i 's/^DEFAULT x$/DEFAULT win98s/' extlinux.conf
grep -n '^DEFAULT\|^LABEL' extlinux.conf     # DEFAULT win98s, and labels x tc-text tc win98 rescue win98s
cd /; sync; umount /mnt/sda1; poweroff
```
* `setbpb` (chain.c32 4.07) patches the boot sector **in memory**: hidden
  sectors, BIOS geometry and drive number. `mkfs.vfat` and Setup wrote the
  BPB with the USB reader's or DOS's view of the card, and the MS FAT32
  (`0b`) boot code finds `IO.SYS` through the BPB's CHS geometry. Nothing
  is written to disk (that would be `save`).
* The old `win98` label (no `setbpb`) stays as it was.

### D. DOS from the floppy, over serial

By hand: put the **W98SERIAL** floppy in and power on. The BIOS boots the
floppy before the hard disks.

On serial, after a few seconds:
`=== W98SERIAL boot floppy (ThinkPad 755C) ...`, the `VER` line and an
`A:\>` prompt. In the floppy's DOS, BIOS disk 0x80 is the tc32 master (no
DOS partition, so no letter) and 0x81 is the slave, so **C: = sdb1**.

1. `CHK`, then read the output:
   * `Volume in drive C is WIN98SE`. **Anything else: stop** (C: is not
     sdb1).
   * `SETUP.EXE` and `MSBATCH.INF` listed under `C:\WIN98`.
   * The DEBUG register dumps, one after each `int 3`:
     * 80h and 81h, `AH=08`: max cylinder = `CH | (CL & C0h) << 2`,
       sectors = `CL & 3Fh`, heads = `DH + 1`. Reachable size =
       (max cylinder + 1) x heads x sectors x 512. Example: `CX=FFFF
       DX=0F02` is 1024 x 16 x 63 = **504 MiB**.
     * 81h, `AH=41`, `BX=55AA`: `NC` with `BX=AA55` means the BIOS has
       INT 13h extensions (LBA) for the slave; `CY` means it has none.
   * The probes: each `---------- C:\PROBE\Pnnnn.TXT` line should be
     followed by a `W98PROBE Pnnnn ...` line. A missing line, an "Abort,
     Retry, Fail?" prompt (answer `F`) or garbage means the BIOS **cannot
     reach** that part of the card.
2. Decide:
   * **All five probes pass** (the BIOS translates past 504 MiB): run
     `UNFILL`, then `W98SETUP`.
   * **P0400 and P0500 pass, P0520 and later fail**: the BIOS stops at
     504 MiB. **Do not run `UNFILL`.** Run `W98SETUP` with the `HIFILL`
     files in place. They hold everything past ~500 MiB, so neither DOS
     nor Setup can put a file where real-mode code cannot read it back.
     About 320 MB is free below the limit, enough for a Typical install
     (Setup checks space first). See the next section for what that means
     later.
   * **P0400 or P0500 fails**: stop and report. Something else is wrong
     (geometry or BPB).
3. `W98SETUP`. It says it is handing the console back, then runs `CTTY
   CON` and Setup. **From here on, serial shows nothing.** Setup runs on
   the 755C screen.

By hand: once the blue Setup screen is up, **take the floppy out**. Setup
does not need A: again (`/NF`). If it is left in, the next reboot starts
the floppy again, and the `W98SERIAL` banner on serial tells us so; take
it out and reset.

### R. Setup's reboots

Setup restarts several times. Each restart goes through the syslinux menu,
whose `DEFAULT` is now `win98s`. It boots by itself after 5 s, with the
slave swapped to 0x80, so Windows sees its own card as C:. On serial, each
restart shows the syslinux menu, then nothing while Windows runs.

* If Setup stops at a "press Enter to restart" prompt (the
  `NoPrompt2Boot` ambiguity), press Enter on the 755C.
* The PC Card wizard is turned off for batch setup. Batch 98 warns that if
  **real-mode** PC Card support is active after the first restart, Setup
  fails. The floppy loads no PC Card drivers, and Setup writes its own
  `CONFIG.SYS`.

### F. After Setup (Tiny Core again)

When Windows has reached the desktop, shut it down from Start. Power on and
pick **`x`** (or `tc`) in the menu on serial (arrow keys or Tab, then
Enter) within 5 s. Then:
```sh
grep -q ' /mnt/sda1 ' /proc/mounts || { mkdir -p /mnt/sda1; mount /dev/sda1 /mnt/sda1; }
cd /mnt/sda1/boot/extlinux
sed -i 's/^DEFAULT win98s$/DEFAULT x/' extlinux.conf    # the win98s label stays in the menu
grep -n '^DEFAULT' extlinux.conf
dd if=/dev/sda bs=446 count=1 2>/dev/null | md5sum             # MBR boot code: both sums must match
dd if=/mnt/sda1/backup-win98/sda-first1MiB.bin bs=446 count=1 2>/dev/null | md5sum
fdisk -l /dev/sdb; ls /mnt/sdb2/tce                     # tcdata intact
cd /; sync
```
(`cp -p extlinux.conf.pre-win98 extlinux.conf` also gets you back to
exactly the old menu, without `win98s`.)

### K. Remove the product key

`MSBATCH.INF` holds the product key in plain text. After the install,
power off, put the slave card in the host's USB reader, mount **only**
partition 1, and:
```sh
M=/media/$USER/WIN98SE
rm -f $M/WIN98/MSBATCH.INF
# List (names only) any other file that still has the key in it, e.g. Setup's logs:
sed -n 's/^WIN98SE_PRODUCT_KEY=//p' ~/.secrets/win98se.env | tr -d "\"'\r" |
    grep -rlaF -f - $M --exclude-dir=PROBE 2>/dev/null
sync; udisksctl unmount -b /dev/sdX1; udisksctl power-off -b /dev/sdX
shred -u ~/.secrets/win98se.env        # last, once nothing above needs it
```
The registry (`HKLM\Software\Microsoft\Windows\CurrentVersion`,
`ProductKey`) keeps a copy. Windows needs it, so it stays.

## BIOS reach: 504 MiB and the 2 GiB partition

**Answered on the 755C:** the BIOS reaches the slave up to about 7.9 GB
(1022/240/63, [above](#bios-geometry-about-79-gb-not-504-mib)), so the
guard below was not needed and C: was later grown to that limit. Kept for
other machines.

`sdb1` stays at 2 GiB (no repartitioning). The risk is that a 1994 BIOS
only reaches 1024 cylinders x 16 heads x 63 sectors = **504 MiB**
(disk LBA 1032192) through INT 13h. Partition type `0b` (FAT32, CHS)
makes DOS 7.1 and the real-mode part of Windows read through INT 13h CHS.
So if the BIOS stops at 504 MiB:

* DOS reads past it return the **wrong sector**, and writes go to the
  **wrong sector** (the cylinder number wraps around). That would corrupt
  the lower part of the card, including the FAT.
* Windows' protected-mode IDE driver (`ESDI_506.PDR`) reaches the whole
  card, so Windows itself would run fine. But **real-mode boot** reads
  `IO.SYS`, `MSDOS.SYS`, `WIN.COM`, `VMM32.VXD` and the registry
  (`SYSTEM.DAT`, rewritten on every boot) through INT 13h. Whenever one of
  those lands past 504 MiB, Windows stops booting.

The guard: `mk-probes.sh` (host, before the 755C) leaves `HIFILL*.BIN`
files covering ~500 MiB to the end of `sdb1`. While they exist, nothing
can be allocated past the limit, so the DOS phase is safe even before we
know the answer, and the probes tell us whether the BIOS stops at 504 MiB.
Test on a loop image with the same layout (start LBA 2048, 4 KiB clusters):
predicted and actual positions matched exactly (P0400 at LBA 819184,
P0500 1023984, P0520 1064944, P1024 2097136, P2040 4177904; `HIFILL0`
from LBA 1023992, just under 500 MiB). About 320 MB stays free below the limit.

If the 755C turns out to be limited, **keep the HIFILL files for as long
as Windows lives on this card**. Windows then has ~320 MB on C:. Deleting
the `\WIN98` source folder after Setup (about 175 MB, all below the limit)
frees more room. Changing the partition to type `0c` (LBA) does not help
on a BIOS without INT 13h extensions.

## Risks

| Risk | Mitigation |
|---|---|
| Setup rewrites the MBR of disk 0x80 (tc32) | `/IR`. The MBR and first MiB of both cards are backed up to `sda1` first. Restore: [Recovery](#recovery) |
| BIOS reach (504 MiB with 2 GiB) | HIFILL guard, probes and the decision rule above. On the 755C: not limited (about 7.9 GB) |
| BPB geometry or drive number from the USB reader | `setbpb` in the `win98s` entry |
| Setup in floppy DOS sees C: on the second BIOS disk (0x81) while later boots see it as 0x80 | Setup's boot files go to C: and are booted through `swap`. If Windows will not start, see Recovery R-W2 |
| `FORMAT C: /S` (old step 15) is skipped (it would wipe `\WIN98`) | Setup writes the boot sector and system files itself; `SYS C:` on the floppy is the fallback |
| `NoPrompt2Boot` meaning is unclear | Press Enter on the 755C if Setup waits |
| Real-mode PC Card support during setup | The floppy loads none; the wizard is skipped |
| No serial output during Setup | Expected after `CTTY CON`; watch the 755C screen |
| Floppy left in at a restart | The `W98SERIAL` banner shows on serial; take the floppy out and reset |
| The host's desktop automounts `tcdata` when the card is in the reader | Unmount sdb2 at once; never write to it |
| Product key in plain text on the card | Step K |

## Recovery

* **R-W1, the syslinux menu is gone** (Setup wrote the MBR anyway): boot
  the TC755C installer floppy, then restore only the boot code (the first
  446 bytes; the partition table is untouched):
  `dd if=/mnt/sda1/backup-win98/sda-first1MiB.bin of=/dev/sda bs=446 count=1`.
  Or follow [INSTALL.md](INSTALL.md#recovery) R2 (reinstall syslinux's
  `mbr.bin`).
* **R-W2, `win98s` gives "Invalid system disk", "Missing operating
  system" or a hang**: boot the W98SERIAL floppy, check that `DIR C:\ /A`
  shows `IO.SYS` and `MSDOS.SYS`, run `SYS C:`, then try `win98s` again.
  Also try the plain `win98` entry (no `setbpb`).
* **R-W3, back to Tiny Core only**: pick `x` in the menu, and
  `cp -p extlinux.conf.pre-win98 extlinux.conf` on `sda1`. `sdb1` can be
  left as it is or reformatted later; nothing else depends on it.
