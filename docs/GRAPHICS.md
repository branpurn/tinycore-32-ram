# Graphics second stage (D3): TinyX Xfbdev + jwm from the CF card

Status: **built and tested in QEMU** (`make test-gfx`, both display paths
10/10); **not yet run on the real 755C**. Sections 1-2 are the design,
3-5 the measured results, 6 the install steps, 7 the caveats.

The floppies do not change. Everything here is a set of Tiny Core-style
`.tcz` extensions in `/mnt/sda1/tce/optional/` on the 755C's CF card,
loaded with `tce-load -i` (or `onboot.lst`) and started with `startx`.

## 1. Display path: what the WD90C24A can do

* The 755C video BIOS has **no VESA VBE** (IBM shipped VBE as a DOS TSR).
  So `vesafb` (needs VBE 2.0 with a linear framebuffer) **cannot work on
  the real 755C**, and neither can Xvesa's VBE modes. Without VBE the BIOS
  only offers standard VGA modes (640x480x4 planar is the best).
* `vga16fb` works on any VGA, but it is 4 bpp **planar**
  (`FB_TYPE_VGA_PLANES`). TinyX Xfbdev only drives packed-pixel
  framebuffers (`fbdev.c` aborts with "Unsupported frame buffer type").
* The sister repo **thinkpad-755c-drivers** (tc755) already has a native
  **`wd90c24fb`** module (`fb-wd90c24.tcz`): 640x480, **8 bpp packed,
  256-colour pseudocolour**, through the chip's PR0(A) banking with a
  300 KiB shadow that `mmap()` gets. That is exactly what Xfbdev needs,
  and it falls back to vga16fb by itself. tc32's Xfbdev tells the driver
  what it drew and lets the chip's BITBLT engine do screen copies and big
  fills (section 5, "Speed"); any other mmap client gets the shadow
  copied whole at 10 Hz.
  It needs the **tc755 kernel** (`6.18.57-tc755`: fbdev helpers built in,
  modules on disk), not the stock tc32 kernel, which refuses those modules.

X also needs **AF_UNIX sockets**, and tc32's kernel has `CONFIG_NET` off
(a floppy-size choice). So on hardware the graphics stage boots its own
kernel from the CF card: **`/boot/vmlinuz.x` = the tc755 kernel +
`config/kernel-xnet.fragment` (`NET=y`, `UNIX=y`, no IPv4/packet/netdevs),
vermagic `6.18.57-tc755x`** (`make gfx-755c`, pinned tc755 commit), with
`fb-wd90c24.tcz`, `trackpoint.tcz` (psmouse + mousedev) and `modutils.tcz`
built against it, plus the X extensions from this repo. It is built from
the same patched source tree, so **`atkbd.xlate=2` works in it unchanged**.
The floppies and the default boot label are untouched: X is an extra
extlinux label `x`.

QEMU has no WD90C24 (its banking registers are ignored), so the QEMU test
uses a **test-only kernel** (`make gfx-kernel`, never put on a floppy):
the tc32 config plus `FB=y`, `FB_VESA=y`, `psmouse`/`mousedev` built in
and the same xnet fragment,
booted with `vga=0x301` (VBE 640x480x8 from SeaVGABIOS, `-vga std` on
`-M isapc`). Xfbdev sees the same thing it gets from wd90c24fb on the
755C: a 640x480 8 bpp packed `/dev/fb0` with a 640-byte line. The test
also boots the real 755C kernel with `wd90c24fb.fake=2` (QEMU's VGA
treated as a WD90C24): driver, X and apps all run, but QEMU does not emulate
the PR0(A) bank register, so only bank 0 (the top 102 lines) reaches the
screen in that mode's screendumps.

## 2. Components

| role | pick | why (vs. the candidates) |
|---|---|---|
| X server | **TinyX Xfbdev** (tinycorelinux/tinyx, kdrive from xorg-server 1.2) | the server Tiny Core itself uses; no XKB, no XInput, no GL; libXfont 1.x **built-in `fixed` + `cursor` fonts**, so no font files are needed. Static. |
| client libs | libX11 1.8 + libxcb + libXau + libXext, **shared** against musl `libc.so` | 6 clients share one copy of Xlib. Measured: a static jwm alone is 1.01 MB, vs 154 KB shared; shared text pages also save RAM |
| window manager | **jwm 2.4** (Xlib only, everything optional disabled) | built-in root menu (click the desktop) and a taskbar with a launcher menu, configured by one small `~/.jwmrc`. twm needs Xt/Xmu/ICE/SM *and* has no app menu by default without config; evilwm has no menu; 9wm's menu only launches one terminal; flwm needs FLTK (C++) |
| terminal | **rxvt 2.7.10** (Xlib only, core fonts) | 67 KB, no Xft/fontconfig/freetype. `st` needs Xft+fontconfig (~1 MB more); `aterm` is an rxvt fork with more deps; xterm needs Xaw |
| apps | **xclock, xcalc, xeyes** (X.org) on Xt + Xmu + Xaw(7) + Xpm + SM + ICE | the classics; the Xt/Xaw stack is shared by all three and is a **separate, optional** extension |
| mouse | `psmouse` (TrackPoint protocol) + `mousedev` -> `/dev/input/mice` | the 755C TrackPoint is the i8042 AUX port; `trackpoint.tcz` from tc755. Xfbdev is always given `-mouse /dev/input/mice` (its default probe list ends in `/dev/ttyS0`, which would steal the serial console) |
| keyboard | the kernel console keymap (kdrive reads the VT in medium-raw) | no XKB data needed; uses whatever atkbd decodes, so the `atkbd.xlate=2` fix applies unchanged |

Toolchain: the repo's i486 musl cross gcc, `-march=i486 -Os`, stripped.

## 3. Packaging: `.tcz` (squashfs xz, 128 KiB blocks), not tar.xz

The kernel already has squashfs (xz) + loop built in and `tce-load` mounts
`.tcz`. A mounted squashfs is **read on demand**: only the pages a process
touches are decompressed into the page cache, and the kernel can drop them
again under memory pressure. A `tar.xz` unpacked into the RAM rootfs would
pin the full installed size (3.6 MB) in tmpfs, which can only be swapped,
never dropped. Block size, measured on the whole set: 4 KiB 2068480 bytes,
16 KiB 1880064, 64 KiB ~1777664, **128 KiB 1712128** (chosen: -17% vs 4 KiB,
and every byte costs serial time; one 128 KiB block decompresses in well
under a second on a 486). `scripts/mktcz-gfx.sh` (`GFX_BLOCK=` to change)
strips everything, checks every ELF with `check-i486.sh` and writes
`.tcz`, `.dep`, `.list`, `.md5.txt`, `.sha256.txt`.

## 4. Measured sizes and transfer times

`make gfx` (out/gfx/sizes.txt). Transfer = XMODEM-1K via
`tools/send-file.sh`. **Measured on the 755C: its side caps throughput at
~1.9 KB/s at 115200, 57600 and 38400 alike**, ~1.33-1.41 KB/s while X is
running. 115200 gives CRC retries, 57600 once lost a block (caught by the
checksum), 38400 was reliable for every file, so **38400 is the default**
of `send-file.sh`/`send-gfx.sh`. The 57600/38400 columns below are the
old estimates: use the 115200 column (1.9 KB/s) for all three rates.

| file | from | `.tcz` bytes | installed | 115200 (meas.) | 57600 (est.) | 38400 (est.) |
|---|---|---:|---:|---:|---:|---:|
| `vmlinuz.x` (tc755x kernel) | `make gfx-755c` | 1225216 | - | 10m45s | 4m32s | 6m11s |
| `Xlibs.tcz` (musl libc, libX11, xcb, Xau, Xext) | `make gfx` | 872448 | 1659524 | 7m39s | 3m13s | 4m24s |
| `Xfbdev.tcz` (server, startx, xinitrc) | `make gfx` | 376832 | 765093 | 3m18s | 1m23s | 1m54s |
| `jwm.tcz` | `make gfx` | 73728 | 156119 | 0m38s | 0m16s | 0m22s |
| `rxvt.tcz` (+ rclock) | `make gfx` | 36864 | 85384 | 0m19s | 0m08s | 0m11s |
| `modutils.tcz` | `make gfx-755c` | 73728 | | 0m38s | 0m16s | 0m22s |
| `fb-wd90c24.tcz` | `make gfx-755c` | 53248 | | 0m28s | 0m12s | 0m16s |
| `trackpoint.tcz` | `make gfx-755c` | 20480 | | 0m11s | 0m05s | 0m06s |
| **minimum set** (above) | | **2732544** | | **~24 min** | **~11 min** | **~14 min** |
| `Xaw-apps.tcz` (optional: Xt/Xaw stack, xclock, xcalc, xeyes) | `make gfx` | 352256 | 893572 | 3m05s | 1m18s | 1m46s |

`tools/send-gfx.sh -n` prints the same plan for any `-b`. Per-file
overhead (command echo at 9600, rx start) is ~4 s.

**Floppy alternative:** `make gfx-floppies` packs the minimum set onto
**two** 1.44 MB FAT floppies (`out/gfx/floppy-gfx-{1,2}.img`, a third with
`Xaw-apps` given `-a`), each with `gfx-setup.sh` and `sha256.txt`. Writing
and reading a floppy takes about a minute each, faster than serial.

## 5. Measured RAM and speed (QEMU, `-M isapc -cpu 486 -m 36`)

MemTotal 32484-32756 kB (36 MB minus the ISA hole and kernel).

| state | used | buff/cache | available |
|---|---:|---:|---:|
| booted, no X | 4264 kB | | |
| X + jwm + rxvt + xclock + xcalc + xeyes (vesafb kernel) | 7852 kB | 6340 kB | **22172 kB** |
| same on the 755C kernel (wd90c24fb + 300 KiB shadow, modules) | 9776 kB | 7044 kB | **20448 kB** |

RSS (kB, shared library pages counted in every process): Xfbdev 1132
(1580 with wd90c24fb), jwm 1556, rxvt 1160, xclock 2156, xcalc 2300,
xeyes 1824. Swap was not touched. X + session start in ~5 s in QEMU TCG
(expect several times that on a 33 MHz 486, mostly squashfs page-ins).
Build: ~10 min for `make gfx` from clean on 16 cores, ~3 min per kernel.

Screendumps (out/gfx/, `make test-gfx`): `x-vesa-1-terminal.png` (desktop,
taskbar, rxvt with `uname -a`), `x-vesa-2-menu.png` (jwm root menu opened
by a mouse click), `x-vesa-3-apps.png` (xclock started from the menu,
xcalc, xeyes); `x-wd-*.png` the same on the 755C kernel (bank 0 only).

### Speed

The 755C has no linear aperture (docs/HARDWARE.md in tc755): every pixel
reaches video memory through the 64 KiB window, copied by the CPU over
the VL-bus. Before, wd90c24fb copied Xfbdev's whole 300 KiB frame 10
times a second whether anything changed or not: about a third of the CPU
with X idle, and a picture that changed only 10 times a second. Now
(gfx/patches/tinyx/0003, 0004 + tc755's `WDFB_IOC_OPS`):

* Xfbdev reports **damage** (the rectangles it drew) before it sleeps;
  only those are copied, merged, and paced so that a client drawing flat
  out still leaves half the CPU (next update at least twice the last
  one's cost later, at most ~66/s);
* **CopyArea and window moves** (scrolling in rxvt/xedit, dragging) and
  **big solid fills** (window backgrounds, clears) go to the WD90C24A
  BITBLT engine: no bus copy at all;
* nothing else changes: drawing still happens in the shadow by fb, so
  the picture is the same; `TC32X_NOWDACCEL=1 startx` or
  `echo 0 > /sys/module/wd90c24fb/parameters/xaccel` (before startx)
  gives the old path for comparison.

`make bench-gfx` (QEMU at about DX4-100 speed with an 8 MiB/s bus model;
ops/s, higher is better; `tests/xbench`):

| test | old: 10 Hz flush | damage only (plain C24) | damage + BITBLT (C24A) |
|---|---:|---:|---:|
| X idle, CPU busy | 26.5 % | 0.1 % | 0.1 % |
| scroll 600x403 (CopyArea + fill + text) | 125.8 | 116.4 | 142.2 |
| fill 200x150 | 584.7 | 540.3 | 733.7 |
| 80-column ImageText | 670.7 | 628.2 | 624.7 |
| move a 300x200 window | 238.1 | 195.6 | 231.9 |
| bytes to video memory, scroll test | 10.8 MB | 7.1 MB | 2.2 MB |
| picture updates | 10/s, whole frame | each change (paced) | each change (paced) |

The old column's ops/s are flattering: it shows a tenth of a second's
drawing at a time and drops the rest. What changes on the 755C is mostly
the idle cost (gone), latency (an update is on screen when X goes idle,
not up to 100 ms later), and scrolling/dragging (the engine instead of a
copy over the bus). How much depends on the 755C's real window speed:
measure it with docs/HW-CHECKLIST.md 1.6 in tc755 (`stats`). Solid-colour
outline moves are already what jwm does (MoveMode/ResizeMode outline).

Not done, and why: a linear aperture (none wired on the 755C's VL-bus
board as far as the docs show), a hardware cursor (no datasheet for the
C24A's cursor registers; the software cursor costs two small rectangles
per move), dual banking (PR0A/PR0B read/write windows: the shadow means
the CPU never reads video memory, so one window is enough).

## 6. Installing on the 755C

The 755C keeps booting its current default label; nothing on the floppies
changes. Build on the host: `make gfx gfx-755c`.

**Over serial** (quit picocom first; the 755C at its shell prompt):

```sh
tools/send-gfx.sh -n                     # plan + estimates, no port used
sudo tools/send-gfx.sh /dev/ttyUSB0      # default 38400 (reliable); -a adds Xaw-apps
#   resume after a failure with:  sudo tools/send-gfx.sh /dev/ttyUSB0 Xlibs.tcz vmlinuz.x
```

Every file lands in `/mnt/sda1/gfx/` and is sha256-checked by
`send-file.sh`. **Or by floppy:** `make gfx-floppies`, then
`dd if=out/gfx/floppy-gfx-N.img of=/dev/fdX bs=512 conv=fsync` for each.

Then on the 755C:

```sh
sh /mnt/sda1/gfx/gfx-setup.sh /mnt/sda1/gfx          # serial delivery
# or, per floppy:
mkdir -p /mnt/fd0 && mount /dev/fd0 /mnt/fd0 && sh /mnt/fd0/gfx-setup.sh && umount /mnt/fd0
reboot          # at the boot: prompt type  x
startx          # jwm menu: click the desktop or the "tc32" button, or Alt+F1
```

`gfx-setup.sh` checks each file against `sha256.txt`, copies `vmlinuz.x` to
`/boot` and the `.tcz` files to `/mnt/sda1/tce/optional/`, adds `Xfbdev.tcz`
to `onboot.lst`, and appends to `extlinux.conf` (backup `.pre-x`):

```
LABEL x
  KERNEL /boot/vmlinuz.x
  APPEND <the APPEND line of the current DEFAULT label>
```

`DEFAULT` stays as it is; to make X the default later, change it to `x`.
After a serial delivery `rm -r /mnt/sda1/gfx` frees the staging copies.
`startx` loads the extensions, `modutils`, `fb-wd90c24` and `trackpoint`
itself. Leave X with the jwm menu entry **Exit X** (Alt+F1).
`make test-gfx` runs this same `gfx-setup.sh` procedure in QEMU.

## 7. Caveats for the real hardware

* wd90c24fb runs X on the 755C. It no longer has a trial period by
  default; boot with `wd90c24fb.trial=30` to get one when trying risky
  settings (text mode comes back by itself unless
  `echo 1 > /sys/module/wd90c24fb/parameters/keep`; startx reminds you).
  If it falls back to vga16fb, startx refuses to start (4 bpp planar);
  check `dmesg | grep wd90c24fb`.
* Blanking: X's screen saver and `echo 1..4 > /sys/class/graphics/fb0/blank`
  go to wd90c24fb: 1 blacks the picture, 2-4 also switch the panel and
  its backlight off (tc755 docs/WD90C24.md "Blank levels").
* QEMU screendumps look dim: QEMU's VBE mode has a fixed palette (static
  pseudocolour). wd90c24fb has a real programmable palette (the `x-wd-*`
  shots show true colours).
* `vmlinuz.x` is 1.2 MB, the biggest single transfer (~11 min at
  1.9 KB/s, measured). Keep the old kernel and labels as they are; if `x` does not
  boot, the default label still does.
* Mouse: the TrackPoint is 2 buttons, so Xfbdev runs with `-2button`
  (press both for a middle click). Without a mouse X still starts,
  keyboard only.
* Keyboard: X uses the console keymap (no XKB); `atkbd.xlate=2` is in the
  `x` label's APPEND because it is copied from the default label.
* Only the built-in `fixed` font exists (no font files). xeyes' title shows
  as `C'xeyes` (a compound-text quirk of the minimal locale).
* The graphics kernel adds 172 KiB (NET + UNIX) to the tc755 kernel; it
  has no IP networking.

## 755C: hardware cursor, rxvt scrolling (round 2)

- Xfbdev uses the WD90C24A hardware cursor when the driver offers it
  (`wd90c24fb.hwcursor`, default 1; check it with `cursor_test`, see
  thinkpad-755c-drivers docs/HW-CHECKLIST.md). With `hwcursor=0`, or
  `TC32X_SOFTCURSOR=1`, the software cursor (TinyX patch 0005).
- rxvt scrolls with XCopyArea (one BITBLT copy) also when its window is
  partly covered (gfx/patches/rxvt). Before, it redrew all text unless jwm
  reported it fully unobscured, so `copies=` stayed 0 on the 755C. Lines
  that differ in 8 or fewer characters are still redrawn (rxvt's rule).
- `tests/xbench`: `XBENCH_MANAGED=1` (a normal jwm window) and
  `XBENCH_GEXP=1` (graphics exposures) for checking the copy path.
- Text goes to the panel by BITBLT colour expansion (`wd90c24fb.cexp`,
  default 1, self-tested at load with automatic fallback): the driver
  sends two-colour damage one bit per pixel, so no TinyX change is needed.

## 8. Real 755C results and known issues (round 3, driver d8c5bda)

Measured on the real ThinkPad 755C (WD90C24A/A2, 486 DX4-100):

- **Serial:** ~1.9 KB/s cap on the 755C side at 115200/57600/38400,
  ~1.33-1.41 KB/s while X runs; 38400 is the reliable default (section 4).
  `send-gfx.sh` does not send `.dep` files; that is fine, `startx` loads
  the dependencies itself.
- **Replacing loaded packages:** while a `.tcz` in `tce/optional` is
  loop-mounted, replace it with `mv` (rename) from the staging directory,
  never `cp` over it.
- **Boot:** extlinux prints `boot:` after the SYSLINUX banner (TIMEOUT 30
  = 3 s). Automation must match that prompt, not the `reboot:` in the
  shutdown text (that once picked the default label). X does not start by
  itself: run `startx`.
- **Speed:** shadow flush to video memory through PR0A banking ~8.6 MB/s
  (50.5 MB in 5.86 s). Damage + BITBLT works (Xfbdev log "damage, BITBLT
  copies, BITBLT fills to the driver"; "feels smoother"). With the rxvt
  patch, `copies=` is above 0 in real use (2 in a short session; 0 after
  75k rects before).
- **Hardware cursor:** works, pixel-exact, no `hwc_xoff`/`hwc_yoff` needed;
  "very smooth cursor".
- **Colour expansion:** only variant 0 passes on the chip; the port write
  (~0.3 us) makes it no faster than the memory copy (est. 1.0x), so
  `cexp=1` leaves it off. See the driver repo's docs/WD90C24.md.
- **Screen saver:** X's idle saver blanks fb0 (seen at levels 3 and 4).
- **Memory:** kernel reports 32732 kB; ~21-22 MB available under X with
  jwm, rxvt and the Xaw apps.

Known issues / open:

- **Backlight:** no blank level turns it off on this unit (levels 3/4 left
  it on with the brightness slider at max; an earlier "off" at level 3 was
  the slider at minimum). APM display standby probably needs the battery,
  which is not installed. Fn+F3 does turn it off. Parked.
- **poweroff** hangs at "reboot: Power down" (APM BIOS 1.0, flags 0x03).
  Disks are synced and stopped before that, so switching off by hand is
  safe. Open follow-up.
- **No CMOS battery:** keep the machine warm and avoid cold boots during a
  session (settings and clock are lost).
