# Serial login on COM1 (ttyS0)

Short version: **tc32 already has one.** Its `core.xz` starts an autologin
root shell on ttyS0 at 9600 baud. `repack-core-serial.sh` exists for two
cases: changing that speed, and adding a ttyS0 login to a stock Tiny Core
`core.gz`.

## What each core does (checked, not assumed)

| | tc32 `core.xz` (this repo) | stock Tiny Core 16.x / 17.x `core.gz` |
|---|---|---|
| ttyS0 entry in `/etc/inittab` | `ttyS0::respawn:/sbin/tc32-getty ttyS0 9600 vt100 -L` (autologin root, backs off if COM1 is missing) | none (only `tty1::respawn:/sbin/getty -nl /sbin/autologin 38400 tty1`) |
| getty | `/sbin/getty` = busybox | `/sbin/getty -> ../bin/busybox` |
| `etc/securetty` | not used (autologin) | `# ttyS0` is commented out, so no root login on ttyS0 |
| logins | root, no password | user `tc` has an empty password; root's password is `*` (locked) |
| fits the 755C (36 MB max) | yes, about 24 MB free at 32 MB | **no**, needs about 46 MB (`docs/FEASIBILITY.md`) |

The stock column was read from the TC 16.x and 17.x x86 `core.gz` files
(`distribution_files/core.gz`; 17.x has 1875 archive entries). Busybox getty usage
was checked against busybox 1.37 `getty.c`:
`getty [OPTIONS] BAUD_RATE[,BAUD_RATE]... TTY [TERMTYPE]`, where `-L` means
a local line (ignore carrier detect).

## The speed has to match in three places

1. syslinux: `SERIAL 0 <baud>` in `extlinux.conf`
2. kernel: `console=ttyS0,<baud>n8` on the `APPEND` line
3. init: the getty line in `/etc/inittab` inside the core

`install-dualcf -b <baud>` writes items 1 and 2. Item 3 is inside the
initramfs, so it needs a repacked core. On the 755C, **9600** (the default)
is the safe choice. The repo measured file transfers at about 1.9 KB/s alike at
115200, 57600 and 38400, because the 755C is the bottleneck. 115200 gave
CRC retries, and 38400 was reliable (docs/GRAPHICS.md section 4). A faster console does not make the machine
faster.

## repack-core-serial.sh

```sh
# stock core.gz: add "ttyS0::respawn:/sbin/getty -L 115200 ttyS0 vt100"
sudo errata/755c/repack-core-serial.sh core.gz            # -> core-serial.gz
sudo errata/755c/repack-core-serial.sh -s core.gz         # + allow root on ttyS0
# tc32 core.xz: change the existing 9600 entry to 38400 (only the baud field)
sudo errata/755c/repack-core-serial.sh -r -b 38400 out/core.xz   # -> out/core-serial.xz
```

* It never modifies the input; it writes `core-serial.gz` / `core-serial.xz`
  (or `-o OUT`). It refuses when OUT is the same file as the input.
* It must run as root, so file owners, modes and device nodes (e.g.
  `dev/console`) survive `cpio -i -H newc -d -m` / `cpio -o -H newc`.
* It detects the compression from the magic bytes. gzip is repacked with
  `gzip -9`. xz is repacked with tc32's own flags
  (`xz -9e --check=crc32 --lzma2=dict=1MiB`), because the kernel's xz
  decoder needs CRC32.
* It appends the line only if there is no active `ttyS0:` entry. `-r`
  replaces an entry: a tc32-getty line keeps its autologin and only its
  baud changes. If nothing would change, it writes nothing and exits 0.
* At the end it extracts `etc/inittab` from the new archive, compares it,
  and prints both sizes and the new sha256.

Checked with `set -eu`, `bash -n` and `shellcheck -s sh`. Tested on the real
TC 17.x `core.gz`, where the line was added, the original was unchanged
(md5), all 1875 entries were kept, and a second run changed nothing. It was
also tested on a tc32 `core.xz`, where `-r` turned 9600 into 115200.

### Installing a repacked core

`install-dualcf finish` installs files by name, so rename the repacked
core to `core.xz` (keep the original elsewhere). Then check the new speed
on the host:

```sh
xzcat core.xz | cpio -i --quiet --to-stdout '*etc/inittab' | grep ttyS0
```

Send it with `host-send.sh /dev/ttyUSB0 core.xz`, then run
`install-dualcf -b 38400 finish` on the 755C, giving the same speed as in
the new inittab. `finish` cannot read the speed out of the core, so a
mismatch shows up as garbage on the terminal after the kernel starts. To
recover, see INSTALL.md.
