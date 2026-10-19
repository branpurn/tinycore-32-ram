#!/usr/bin/env python3
"""tc32 installer test (stdlib only).

1. Builds a 2,000,000,000-byte IDE disk that looks like the 755C's CF card
   (one FAT32 "Windows 95" partition), unless --keep-disk.
2. Boots out/installer.img (TCG, -M isapc -cpu 486 -m 32) and runs
   install-to-disk over COM1: dry run, a refused confirmation, a full install,
   a second full install (idempotent), and an update (-u) that keeps /tce.
3. Boots the disk with NO floppy, default extlinux entry, no keypress, and
   checks the shell, tce=sda1, swap; then sends files with tools/send-file.sh
   over the same console (QEMU COM1 on a pty), at 115200 and at 9600, and
   checks the sha256 on both ends.
4. Boots the disk once more on QEMU's default PIIX machine (-M pc).
"""
import argparse, hashlib, os, re, subprocess, sys, time, termios, tty

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from harness import Guest, TOP  # noqa: E402

DISK_BYTES = 2_000_000_000          # "2 GB" CF card; 3,906,250 sectors


class PtyGuest(Guest):
    """QEMU with COM1 on a pty, so tools/send-file.sh can use it like
    /dev/ttyUSB0. QEMU starts paused (-S) until the pty is open."""

    def __init__(self, cmd, logpath):
        self.log = open(logpath, "wb")
        cmd = cmd + ["-chardev", "pty,id=con0", "-serial", "chardev:con0", "-S", "-monitor", "stdio"]
        self.p = subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                  stderr=subprocess.STDOUT, bufsize=0)
        self.buf = b""
        self.t0 = time.time()
        acc = b""
        while True:
            d = os.read(self.p.stdout.fileno(), 4096)
            if not d:
                raise EOFError("qemu exited: " + acc.decode("latin-1"))
            acc += d
            m = re.search(rb"char device redirected to (/dev/pts/\d+)", acc)
            if m:
                self.pty = m.group(1).decode()
                break
        self.fd = os.open(self.pty, os.O_RDWR | os.O_NOCTTY)
        tty.setraw(self.fd)
        self.mon = self.p.stdin
        self.mon.write(b"cont\n"); self.mon.flush()

    def _pump(self, timeout):
        import select
        r, _, _ = select.select([self.fd], [], [], timeout)
        if r:
            try:
                d = os.read(self.fd, 65536)
            except OSError:
                d = b""
            if not d:
                if self.p.poll() is not None:
                    raise EOFError("qemu exited")
                time.sleep(0.05)
                return
            self.buf += d
            self.log.write(d); self.log.flush()

    def send(self, s, slow=False):
        for ch in s.encode():
            os.write(self.fd, bytes([ch]))
            time.sleep(0.02 if slow else 0.005)

    def close(self):
        try:
            os.close(self.fd)
        except Exception:
            pass
        super().close()


def qemu_base(mem, machine="isapc"):
    return ["qemu-system-i386", "-accel", "tcg", "-M", machine, "-cpu", "486", "-m", str(mem),
            "-display", "none", "-no-reboot"]


def make_win95_disk(path):
    """Sparse 2 GB raw disk with an MS-DOS label and one FAT32 (LBA) partition."""
    with open(path, "wb") as f:
        f.truncate(DISK_BYTES)
    sect = DISK_BYTES // 512
    subprocess.run(["sfdisk", "-q", path], input=f"label: dos\nstart=63, size={sect - 63}, type=c, bootable\n",
                   text=True, check=True, env={**os.environ, "PATH": os.environ["PATH"] + ":/usr/sbin:/sbin"})
    subprocess.run(["mkfs.fat", "-F", "32", "-n", "WIN95", "--offset", "63", path, str((sect - 63) // 2)],
                   check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                   env={**os.environ, "PATH": os.environ["PATH"] + ":/usr/sbin:/sbin"})


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--mem", type=int, default=32)
    ap.add_argument("--img", default=os.path.join(TOP, "out/installer.img"))
    ap.add_argument("--disk", default=os.path.join(TOP, "out/test-install-disk.img"))
    ap.add_argument("--keep-disk", action="store_true", help="reuse --disk (skip phase 1 rebuild)")
    ap.add_argument("--xfer-kib", type=int, default=192, help="size of the 115200-baud test file")
    ap.add_argument("--logdir", default=os.path.join(TOP, "out/test-logs"))
    a = ap.parse_args()
    os.makedirs(a.logdir, exist_ok=True)
    results, metrics = [], {"mem": a.mem, "disk_bytes": DISK_BYTES}

    def check(desc, ok, detail=""):
        results.append((desc, bool(ok), detail))
        print(f"  [{'PASS' if ok else 'FAIL'}] {desc}" + (f"  ({detail})" if detail else ""), flush=True)
        return ok

    def shell(g, timeout=90):
        g.expect(r"root@box:[^\n#]*# ", timeout)
        g.run("stty -echo 2>/dev/null; export PS1='# '", 20)
        g.expect(r"# ", 10)

    def interactive(g, cmd, answer, timeout=900):
        tag = "__TC32_%d__" % int(time.time() * 1000 % 1e9)
        g.send(f"{cmd}; echo {tag}=$?\r")
        out, _ = g.expect(r"Type YES[^\n]*: ", 300)
        g.send(answer + "\r")
        out2, m = g.expect(tag + r"=(\d+)\r?\n", timeout)
        return (out + out2).replace("\r", ""), int(m.group(1))

    def poweroff(g):
        g.send("poweroff\r")
        try:
            g.expect(r"(reboot: Power down|System halted|Power down)", 120)
            return True
        except (TimeoutError, EOFError):
            return False

    # ---------------------------------------------------------------- phase 1
    if not a.keep_disk:
        make_win95_disk(a.disk)
    check("2 GB IDE disk prepared (FAT32 'Windows 95' partition)", os.path.getsize(a.disk) == DISK_BYTES,
          f"{os.path.getsize(a.disk):,} bytes")
    print(f"== installer: -m {a.mem} -M isapc -cpu 486 (TCG) + {DISK_BYTES:,}-byte IDE disk")
    cmd = qemu_base(a.mem) + ["-drive", f"if=floppy,index=0,format=raw,file={a.img},readonly=on",
                              "-drive", f"if=ide,index=0,format=raw,file={a.disk}", "-boot", "a",
                              "-serial", "stdio", "-monitor", "none"]
    g = Guest(cmd, os.path.join(a.logdir, "serial-install.log"))
    try:
        g.expect(r"boot: ", 60)
        check("installer: syslinux prompt on COM1", True)
        # QEMU's FDC has a normal disk-change line: undo floppy=thinkpad.
        g.send("install floppy=0,thinkpad\r", slow=True)
        out, _ = g.expect(r"tc32: ready\.", 400)
        o2, _ = g.expect(r"root@box:[^\n#]*# ", 90)
        check("installer boots to a root shell on COM1", True)
        check("installer banner shown at login (/root/.profile)", "tc32 INSTALLER" in out + o2)
        g.run("stty -echo 2>/dev/null; export PS1='# '", 20); g.expect(r"# ", 10)
        o, rc = g.run("cat /proc/cmdline; cat /proc/swaps | wc -l")
        check("installer: noswap, no swap enabled on the target", "noswap" in o and o.split()[-1] == "1", o.split()[-1])
        o, rc = g.run("cat /sys/block/sda/size; cat /sys/block/sda/device/model")
        check("pata_legacy sees the disk as /dev/sda, 3906250 sectors", o.split()[0] == "3906250", " ".join(o.split()))
        o, rc = g.run("ls /sys/bus/platform/drivers/ 2>/dev/null | grep -i pata; dmesg | grep -iE 'pata_legacy|ata1' | head -3")
        metrics["ide_dmesg"] = o.strip()
        mbr0, _ = g.run("dd if=/dev/sda bs=512 count=1 2>/dev/null | sha256sum")
        o, rc = g.run("install-to-disk -n /dev/sda", 300)
        check("install-to-disk -n: dry run shows the plan, exits 0", rc == 0 and "Dry run" in o and "sda1" in o,
              " / ".join(l.strip() for l in o.splitlines() if "MB" in l)[:200])
        o, rc = interactive(g, "install-to-disk /dev/sda", "yes")
        mbr1, _ = g.run("dd if=/dev/sda bs=512 count=1 2>/dev/null | sha256sum")
        check("confirmation: answering 'yes' (not YES) aborts, disk untouched",
              rc == 1 and "Aborted" in o and mbr0 == mbr1, f"rc={rc}")
        t = time.time()
        o, rc = interactive(g, "install-to-disk /dev/sda", "YES")
        metrics["install_s"] = round(time.time() - t, 1)
        check("full install (typed YES) completes and verifies", rc == 0 and "Verified" in o,
              f"rc={rc}, {metrics['install_s']} s" + ("" if rc == 0 else " | " + o.strip()[-300:]))
        o, rc = g.run("fdisk -l /dev/sda")
        p1 = re.search(r"^/dev/sda1\s+\*\s+.*\b83\b", o, re.M); p2 = re.search(r"^/dev/sda2\s+.*\b82\b", o, re.M)
        check("MBR: sda1 bootable Linux (83), sda2 swap (82), no Win95 partition",
              p1 and p2 and " c " not in o and "sda3" not in o, " | ".join(l for l in o.splitlines() if l.startswith("/dev/")))
        mbr2, _ = g.run("dd if=/dev/sda bs=512 count=1 2>/dev/null | sha256sum")
        o, rc = g.run("mkdir -p /mnt/t && mount -t ext2 /dev/sda1 /mnt/t && ls /mnt/t/boot /mnt/t/boot/extlinux "
                      "&& echo keep-me > /mnt/t/tce/marker; df -k /mnt/t | tail -1; umount /mnt/t")
        check("sda1 ext2: boot/{vmlinuz,core.xz,extlinux/ldlinux.sys,extlinux.conf}",
              all(x in o for x in ("vmlinuz", "core.xz", "ldlinux.sys", "extlinux.conf")), " ".join(o.split())[:200])
        o, rc = interactive(g, "install-to-disk /dev/sda", "YES")
        mbr3, _ = g.run("dd if=/dev/sda bs=512 count=1 2>/dev/null | sha256sum")
        o2, _ = g.run("mount -t ext2 /dev/sda1 /mnt/t && ls /mnt/t/tce; umount /mnt/t")
        check("re-run full install: succeeds, identical MBR, fresh filesystem",
              rc == 0 and mbr2 == mbr3 and "marker" not in o2, f"rc={rc}")
        g.run("mount -t ext2 /dev/sda1 /mnt/t && echo keep-me > /mnt/t/tce/marker; umount /mnt/t")
        o, rc = interactive(g, "install-to-disk -u /dev/sda", "YES")
        mbr4, _ = g.run("dd if=/dev/sda bs=512 count=1 2>/dev/null | sha256sum")
        o2, _ = g.run("mount -t ext2 /dev/sda1 /mnt/t && cat /mnt/t/tce/marker; umount /mnt/t")
        check("install-to-disk -u: refreshes boot files, keeps /tce data and the MBR",
              rc == 0 and "keep-me" in o2 and mbr4 == mbr3, f"rc={rc}")
        o, rc = g.run("install-to-disk /dev/sda1 2>&1; install-to-disk /dev/fd0 2>&1")
        check("refuses a partition or the floppy as target", "not a whole disk" in o and "not a hard disk" in o)
        check("installer: clean poweroff", poweroff(g))
    except (TimeoutError, EOFError) as e:
        check("installer step", False, str(e)); print(g.buf.decode("latin-1")[-800:])
    finally:
        g.close()

    # ---------------------------------------------------------------- phase 2
    print("== disk boot: no floppy, default extlinux entry, no keypress; COM1 on a pty")
    cmd = qemu_base(a.mem) + ["-drive", f"if=ide,index=0,format=raw,file={a.disk}", "-boot", "c"]
    g = PtyGuest(cmd, os.path.join(a.logdir, "serial-diskboot.log"))
    try:
        g.expect(r"boot: ", 90)
        check("disk: extlinux boot: prompt on COM1 (MBR + extlinux, no floppy)", True)
        t = time.time()
        out, _ = g.expect(r"tc32: ready\.", 400)
        metrics["disk_boot_s"] = round(time.time() - t, 1)
        check("disk: default entry auto-boots to rcS", "Linux version" in out, f"{metrics['disk_boot_s']} s after boot:")
        shell(g)
        check("disk: autologin root shell on ttyS0", True)
        o, rc = g.run("cat /proc/cmdline")
        check("disk: cmdline = serial console + tce=sda1", "console=ttyS0,9600n8" in o and "tce=sda1" in o, o.strip())
        o, rc = g.run("readlink /etc/sysconfig/tcedir; cat /mnt/sda1/tce/marker; grep sda1 /proc/mounts")
        check("disk: /mnt/sda1/tce is the extension dir (ext2), data kept", "/mnt/sda1/tce" in o and "keep-me" in o
              and "ext2" in o, " ".join(o.split()))
        o, rc = g.run("cat /proc/swaps")
        check("disk: swap on /dev/sda2 auto-enabled", "/dev/sda2" in o)
        o, rc = g.run("uname -m; free | awk '/Mem:/{print $4}'")
        check("disk: uname -m = i486", o.split()[0] == "i486", " ".join(o.split()))
        # --- serial transfer over the console, as on real hardware ---------
        sendfile = os.path.join(TOP, "tools/send-file.sh")
        for label, size, baud, tail in (("115200", a.xfer_kib * 1024 + 37, "115200", b""),
                                         ("9600", 1500, "9600", b"\x1a" * 5)):
            path = os.path.join(a.logdir, f"xfer-{label}.bin")
            data = os.urandom(size - len(tail)) + tail
            open(path, "wb").write(data)
            want = hashlib.sha256(data).hexdigest()
            r = subprocess.run([sendfile, "-b", baud, path, g.pty, f"/tmp/xfer-{label}.bin"],
                               capture_output=True, text=True, timeout=1800)
            open(os.path.join(a.logdir, f"send-file-{label}.log"), "w").write(r.stdout + r.stderr)
            rate = re.search(r"(\d+) bytes in ([\d.]+) s = (\d+) B/s", r.stdout)
            if rate:
                metrics[f"xfer_{label}_Bps"] = int(rate.group(3)); metrics[f"xfer_{label}_s"] = float(rate.group(2))
            g.buf = b""
            o, rc = g.run(f"sha256sum /tmp/xfer-{label}.bin; wc -c < /tmp/xfer-{label}.bin; stty -a | head -1", 120)
            ok = r.returncode == 0 and want in o and str(size) in o.split()
            check(f"send-file.sh {size} bytes at {baud} baud (XMODEM-1K, sx -> rx): sha256 match on both ends",
                  ok, (rate.group(0) if rate else r.stdout.strip()[-200:]) + ("; trailing ^Z kept" if tail else ""))
            check(f"console back at 9600 after the {label} transfer", "speed 9600" in o, o.strip().splitlines()[-1] if o.strip() else "")
        check("disk: clean poweroff", poweroff(g))
    except (TimeoutError, EOFError, subprocess.TimeoutExpired) as e:
        check("disk-boot step", False, str(e)); print(g.buf.decode("latin-1")[-800:])
    finally:
        g.close()

    # ---------------------------------------------------------------- phase 3
    print("== disk boot on -M pc (PIIX IDE in legacy mode at 0x1f0/irq 14)")
    cmd = qemu_base(a.mem, "pc") + ["-drive", f"if=ide,index=0,format=raw,file={a.disk},snapshot=on",
                                     "-boot", "c", "-serial", "stdio", "-monitor", "none"]
    g = Guest(cmd, os.path.join(a.logdir, "serial-diskboot-pc.log"))
    try:
        g.expect(r"tc32: ready\.", 400)
        shell(g)
        o, rc = g.run("grep sda1 /proc/mounts; cat /proc/swaps | grep -c sda2")
        check("-M pc: boots from disk, sda1 mounted, swap on", "ext2" in o and o.split()[-1] == "1", " ".join(o.split()[:3]))
        poweroff(g)
    except (TimeoutError, EOFError) as e:
        check("-M pc disk boot", False, str(e)); print(g.buf.decode("latin-1")[-800:])
    finally:
        g.close()

    import json
    ok = bool(results) and all(r[1] for r in results)
    metrics["pass"] = ok
    metrics["results"] = [{"check": d, "pass": p, "detail": x} for d, p, x in results]
    json.dump(metrics, open(os.path.join(a.logdir, "result-install.json"), "w"), indent=2)
    print(f"== install test: {'PASS' if ok else 'FAIL'} ({sum(r[1] for r in results)}/{len(results)} checks)"
          + (f", 115200-baud transfer {metrics.get('xfer_115200_Bps')} B/s" if "xfer_115200_Bps" in metrics else ""))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
