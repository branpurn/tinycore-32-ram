# tc32 feasibility study (Phase 1)

Goal: a Tiny Core Linux–derived system that boots and is usable on an
**IBM ThinkPad 755C** with **32 MB RAM**, ideally from **one 1.44 MB floppy**
written with `dd`.

**Bottom line: the single-floppy target works.** A Linux 6.18 LTS kernel
built for i486 plus a static musl busybox initramfs with trimmed Tiny Core–style
init scripts fits on one floppy with about 170 KiB to spare. In QEMU
(`-cpu 486`, TCG) it boots to a shell at 32 MB with about 24 MB free. Stock Tiny
Core cannot run this way. Its `core.gz` alone is about 14 MB compressed, and
the FAQ minimum is 46 MB. So tc32 keeps Tiny Core's *design* (boot codes,
`tce` directory, `.tcz` = squashfs loop-mounted and symlinked into `/`,
`onboot.lst`, `bootlocal.sh`), not its binaries.

---

## 1. Research findings

### 1.1 Tiny Core RAM and CPU requirements
| Fact | Source |
|---|---|
| Official minimum: **46 MB** for TinyCore, **28 MB** for Microcore; minimum CPU **i486DX** (needs an FPU); recommended P2 + 128 MB | [TC FAQ](http://www.tinycorelinux.net/faq.html) |
| Current release **17.1** (Jul 2026), kernel **6.18.35**; x86 `core.gz` = 14.1 MB, `rootfs.gz` = 3.7 MB, `modules.gz` = 10.4 MB, `vmlinuz` = 6.1 MB | [17.x release dir](http://tinycorelinux.net/17.x/x86/release/distribution_files/), [17.1 announcement](https://forum.tinycorelinux.net/index.php?topic=28211.0) |
| TC 17 x86 kernel config: `CONFIG_M486=y`, `X86_GENERIC`, `SMP`, `HIGHMEM`, gzip | [config-6.18.35-tinycore](http://tinycorelinux.net/17.x/x86/release/src/kernel/linux-6.18.35/) |
| TC 17 x86 userland (glibc 2.42 etc.) is compiled with `-march=i486 -mtune=i686 -Os`; the extension wiki asks for the same flags | [compile_tc17_x86](http://tinycorelinux.net/17.x/x86/release/src/toolchain/), [wiki: creating extensions](https://wiki.tinycorelinux.net/doku.php?id=wiki%3Acreating_extensions) |
| TC 15 needs more than 64 MB with default boot codes; `udev.children-max=1` and `nozswap` help. The bootloader-loaded initrd stays in RAM while it unpacks; TC's `/init` copies the rootfs into a second tmpfs (so roughly 2x at peak) | [forum 27458](https://forum.tinycorelinux.net/index.php/topic,27458.0.html), [forum 27902](https://forum.tinycorelinux.net/index.php?topic=27902.0) |
| Stock Core panics at 32 MB on a 486 even when stripped. A HDD "scatter" install (`root=` on ext2) works below 32 MB but departs from TC's run-from-RAM design | [forum 27902](https://forum.tinycorelinux.net/index.php?topic=27902.0) |
| The 2.x series had a known 486 boot bug (glibc). Forum note: QEMU's 486 emulation does not strictly trap i686 opcodes, so Bochs is the better test | [forum 4908](https://forum.tinycorelinux.net/index.php?topic=4908.0) |

**Which TC release last supports i486?** All current releases, up to and
including **TC 17.x** (6.18 kernel with `M486`, i486-targeted glibc).
Mainline Linux removed `CONFIG_M486/M486SX/MELAN` in **7.1**
([Phoronix](https://www.phoronix.com/news/Linux-7.1-Begins-Removing-i486),
[merge commit](https://github.com/torvalds/linux/commit/0972ba5605a0a0cd8a9e74558b97a9c9626adfb5),
[LWN 7.1-rc1](https://lwn.net/Articles/1069721/)). In **7.2** TSC and CX8 became
unconditional, and the DX4 has neither
([Phoronix](https://www.phoronix.com/news/Linux-7.2-x86)). So 6.18 LTS is
the last kernel line with 486 support. kernel.org projects its EOL for
**Dec 2028** ([releases](https://www.kernel.org/category/releases.html)). A
future TC 18 on a ≥ 7.1 kernel would drop the 486 (an inference; not
announced). Note: the FLOPPINUX 2025 write-up says 6.15 dropped i486. That
is wrong. 6.18 still has `M486`, and tc32 builds with it.

### 1.2 IBM ThinkPad 755C (machine type 9545)
| Item | Finding | Source |
|---|---|---|
| CPU | SL-Enhanced 486DX2-50 (3.3 V) or **IntelDX4-75** on a processor card. Has an FPU and CPUID; no TSC, no CMOV, no CX8, no PAE | [IBM announcement 194-168](https://sharktastica.co.uk/resources/docs/txt/IBM_194-168_TP755C-TP755Cs-Announce_1994_IBM.txt), [IBM product overview](http://ps-2.kev009.com/pcpartnerinfo/ctstips/370e.htm) |
| RAM | **4 MB on the system board** (not 8 MB). Expansion is either an IC DRAM card (max 20 MB total) or a DIMM card adapter with 4/16 MB DIMMs (**max 36 MB**, so 32 MB of expansion) | same; [oldthinkpad 9545](https://oldthinkpad.com/parts/9545) |
| Bus | AT (ISA) bus + VESA local bus for video. **No PCI** | IBM product overview |
| Video | **Western Digital WD90C24A/A2**, 1 MB, 10.4" TFT 640x480 (256 of 256K colors). **Not Trident** | [Wikipedia](https://en.wikipedia.org/wiki/ThinkPad_755), [manualsdump](https://manualsdump.com/en/manuals/ibm-720-720c-700-700c-510cs/120359/58) |
| Audio | Crystal CS4248 (on board) | Wikipedia |
| Floppy | Removable 3.5" drive: 3-mode 1.44 MB, or 4-mode with 2.88 MB on some units | IBM product overview, Wikipedia |
| HDD | Removable 2.5" IDE, 170/340/540 MB | IBM product overview |
| PC Card | 2x Type II or 1x Type III (PCMCIA 2.1). The 750 series used an Intel 82365SL-class controller | IBM docs; [oldthinkpad](https://oldthinkpad.com/parts/9545) |
| Power | APM BIOS (era-typical; no ACPI) | inferred; tc32's APM driver detects "APM BIOS 1.2" in QEMU, not yet on the 755C |

Not verified yet: the exact IDE controller/chipset, and whether this
BIOS boots syslinux 4.07 from the removable drive. Both need real-hardware
tests.

### 1.3 Single-floppy prior art
* **FLOPPINUX 2025** (v0.3.1): kernel 6.14.11 `tinyconfig` + `M486`, xz.
  bzImage 881 KiB, busybox 1.36.1 rootfs 137 KiB xz, 253 KiB free. Runs on
  a 486DX-33 with 20 MB
  ([write-up](https://krzysztofjankowski.com/floppinux/floppinux-2025.html),
  [repo](https://github.com/w84death/floppinux)).
* **Ginebra Linux**: a two-floppy FLOPPINUX fork with modules, NICs and a
  TinyX framebuffer X server. Advises **syslinux 4.x** because 6.x is too
  big for a floppy ([repo](https://github.com/csepulveda/ginebra-linux/)).
* Kernel docs on trimming: `tinyconfig`, `CC_OPTIMIZE_FOR_SIZE`,
  `KERNEL_XZ`, `SLUB_TINY`.

## 2. Approach chosen and why

| Option | Verdict |
|---|---|
| A. Pin an older TC release | **Rejected.** No TC release ever fit on one floppy or ran in-RAM at 32 MB. Older releases also carry 486 bugs and outdated kernels. |
| B. Remaster TC 17 `core.gz` (strip modules/glibc) | **Rejected for the floppy.** glibc + libs alone are several MB. A good fit for a later HDD-backed "full TC userland" mode (see §6). |
| **C. Custom 6.18 LTS i486 kernel + static musl busybox initramfs + TC-style scripts** | **Chosen.** It's the only approach that fits 1.44 MB with room left over and boots at 32 MB with about 24 MB free. Tiny Core's conventions are kept so a fuller TC userland can be layered on from disk later. |

What "TC-derived" means right now:
`/etc/init.d/rcS` is a trimmed take on TC's `tc-config`. It handles the
boot codes `tce=`, `noswap`, `host=` and `quiet`, auto-enables swap
partitions, uses `/etc/sysconfig/tcedir`, and runs `onboot.lst` and
`/opt/bootlocal.sh`. `tce-load -i` loop-mounts `.tcz` (squashfs, gzip or xz)
under `/tmp/tcloop/<ext>` and symlinks the files into `/`, the same way TC
does. The `tc` user, `staff` group and `/usr/local/tce.installed` follow
TC's layout. No TC binaries ship.

One deliberate difference from TC: there is no copy of the rootfs into a
second tmpfs. The kernel already unpacks the initramfs into tmpfs-backed
rootfs, so TC's copy only doubles peak RAM.

## 3. Floppy size budget (measured, current build)

| Item | Bytes | KiB |
|---|---:|---:|
| 1.44 MB floppy | 1,474,560 | 1440 |
| FAT12 metadata (boot sector, 2 FATs, root dir) + syslinux 4.07 `ldlinux.sys` + cfg | ~55,000 | ~54 |
| `vmlinuz`: Linux 6.18.57, i486, xz (base + IDE/ext2 + squashfs/loop + APM) | 1,032,704 | 1008 |
| `core.xz`: initramfs (busybox 1.37.0 static musl, 91 applets + scripts) | 212,236 | 207 |
| **Free on the floppy FAT** (persistence, a `.tcz` or two) | **174,080** | **170** |

Kernel cost per feature group (measured):
* base (console, keyboard, serial, floppy, FAT, tmpfs, initrd): 905,728 B
* + IDE (libata `pata_legacy`, SCSI disk) + ext2: +90 KiB
* + `.tcz` support (loop + squashfs zlib/xz): +16 KiB
* + APM (real power-off; needs `SUSPEND`/`PM_SLEEP`): +20 KiB

Size opportunities, not taken yet:
1. **perf events** (about 200 KB of uncompressed text, about 60–70 KB on
   disk) are force-selected by `arch/x86`. Making the select conditional
   breaks the build, because hw_breakpoint/ptrace depend on perf. This
   needs a real patch.
2. Embedding the initramfs in the kernel image saves a few KiB (one xz
   stream), but you lose the ability to swap `core.xz` independently.
3. Busybox applet pruning (each big applet such as `awk`, `vi`, `fdisk`,
   `mke2fs` or `top` is about 5–30 KB).
4. A 1.68 MB (DMF-style) or 2.88 MB format: the 755C's 4-mode drive could
   read 2.88 MB media, but the media is rare. Not pursued.

## 4. RAM budget (measured in QEMU, TCG, `-cpu 486`, `-M isapc`)

At `-m 32`, the kernel reports `Memory: 28432K/32376K available (1652K
code, 182K rwdata, 316K rodata, 200K init, 92K bss, 3644K reserved)`.

| `-m` | MemTotal | used | free (after boot) | result |
|---:|---:|---:|---:|---|
| 32 | 29,140 kB | ~3.9 MB | **24,684 kB** | all 15 checks pass |
| 24 | 21,012 kB | ~3.9 MB | 16,260 kB | all pass |
| 16 | 12,896 kB | ~3.9 MB | 8,220 kB | all pass |
| 12 | 8,832 kB | ~3.9 MB | 4,532 kB | all pass |
| 10 | 6,788 kB | ~3.8 MB | 2,544 kB | boots; the 2 MB `/tmp` write fails (tmpfs is capped at 25% of RAM) |
| 8 | 4,772 kB | ~3.2 MB | 1,140 kB | boots to a shell; OOM panic on the 2 MB write |

The 755C's 4 MB base RAM alone is not enough. Any 755C with a memory card
(at least 8 MB total) boots tc32. At 32 MB, about 24 MB is left for
applications, a RAM disk, or extensions.

Two important kernel fixes came out of this testing:
* `CONFIG_PHYSICAL_START=0x100000`. The default 16 MB load address makes
  every machine with less than about 19 MB hang silently after the
  bootloader.
* `CONFIG_COMPAT_32BIT_TIME=y`. musl on i386 uses the legacy time
  syscalls. Without them busybox `init` busy-spins and ignores
  poweroff/reboot.

## 5. Risks

* **Emulation is not hardware.** QEMU TCG `-cpu 486` may execute
  post-486 opcodes without faulting. `scripts/check-i486.sh` statically
  rejects CMOV/FCMOV/FCOMI/NOPL/RDTSC/CX8/MMX/SSE in userland: busybox
  has 0 hits, and the kernel `vmlinux` has 0 CMOV/NOPL. Real-hardware
  testing is still needed (86Box/Bochs would be a closer emulator
  check).
* **Floppy read speed and reliability**: about 1.25 MB is read through
  BIOS int13 at boot. On a real drive expect 30–60 s, and old media
  fail. Use fresh, verified disks (`dd`, then `cmp`).
* **IDE on the 755C** uses `pata_legacy` (ISA ports 0x1f0/0x170). If
  the controller needs VLB-specific handling, there are `pata_legacy`
  options (`pata_legacy.all=1`, ...). Untested on hardware.
* **Display**: VGA text console (80x25) only. The WD90C24A has no
  modern kernel fb driver. `vga=` text modes (80x50) should work via the
  BIOS.
* **Kernel line**: 6.18 is the last 486-capable LTS (EOL Dec 2028). After
  that, we'd have to maintain our own fork.
* **TC extensions are glibc binaries.** `.tcz` files from TC's repo
  mount fine, but their programs need TC's glibc/libs (from `core.gz`),
  which won't fit on the floppy. See decision D2.

## 6. Decision points for Brandon

* **D1 – Scope of "Tiny Core".** Is TC's *mechanism* (boot codes,
  tce dir, `.tcz` loop+symlink, onboot.lst, bootlocal) enough, or do you
  need *binary compatibility* with TC's x86 repo?
* **D2 – TC repo compatibility** (if needed). Proposal: a "tc-glibc" HDD
  mode where the floppy boots the kernel and a `tce=hda1` directory holds
  a `glibc_base.tcz` cut from TC 17's `core.gz`, so stock TC 17 `.tcz`
  files run. RAM cost: glibc pages are loop-mounted from disk and paged
  in, not copied to RAM.
* **D3 – X / FLWM.** **Not possible on a single floppy, and very
  unlikely in-RAM at 32 MB in TC's form.** Xvesa + FLTK + FLWM are several
  MB as glibc binaries, and the WD90C24A only gives you VESA/VGA 640x480x8
  through the BIOS. A tiny framebuffer X (TinyX/Xfbdev, as in Ginebra
  Linux) from the HDD might run at 32 MB with swap. This is a separate
  phase.
* **D4 – Networking.** None in phase 1. Options are PCMCIA (needs PCMCIA
  core + i82365 + a card driver, roughly 60–100 KiB, so likely a second
  floppy or the HDD) or a parallel-port PLIP link.
* **D5 – Persistence.** Use the floppy's ~170 KiB free FAT space
  (`tce=fd0`), or the HDD?
* **D6 – Audio, PCMCIA, suspend.** Out of scope unless you want them.

Fallback layouts, if feature creep pushes past 1.44 MB:
1. **Two floppies**: boot floppy (kernel + small initramfs) plus a root
   floppy (squashfs or a cpio loaded by the init script).
2. **Floppy bootloader + HDD/CF**: the floppy carries syslinux + kernel
   and the rest lives on the 755C's IDE disk (or a CF-to-2.5" IDE
   adapter), e.g. `tce=hda1`. This is closest to TC's frugal install.
3. **HDD only**: syslinux/extlinux on the IDE disk, no floppy.

## 7. Next steps

1. Boot the floppy on the real 755C. Capture any panic with a phone
   photo, or over COM1 with the `serial` boot label.
2. Decide D1–D5.
3. Patch out the perf events properly (about 60–70 KiB of floppy space).
4. Try the HDD path on hardware (`tce=hda1`, swap partition).
5. If D2 is wanted, build the glibc-from-TC-17 extension and test stock
   `.tcz` packages.
6. Optional: run an 86Box/Bochs strict-486 CI step.
