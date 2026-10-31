#!/usr/bin/env python3
"""QEMU test of the 755C dual-CF installer floppy (stdlib only).

  errata/755c/test-qemu.py [--img out/tc755c-installer.img] [--full]

Boots the floppy with TCG, -M isapc -cpu 486 -m 32, a sparse 4 GB IDE master
and a sparse 128 GB IDE slave, console on COM1 (logged to
out/test-logs/755c-*.log), and checks: syslinux prompt and a root shell on
ttyS0, both disks detected as master/slave, and that `install-dualcf
prepare` writes nothing unless the exact confirmation is typed.
--full also runs prepare, sends vmlinuz, core.xz, menu.c32 and chain.c32
(syslinux 4.07) with host-send.sh over the COM1 pty, runs finish, and boots
the master card without the floppy (menu.c32 menu, default entry).
"""
import argparse, os, re, subprocess, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
TOP = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, os.path.join(TOP, "tests"))
from harness import Guest  # noqa: E402
from install import PtyGuest  # noqa: E402

SIZES = {"master": 4 * 1024**3, "slave": 128 * 1024**3}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--img", default=os.path.join(TOP, "out/tc755c-installer.img"))
    ap.add_argument("--workdir", default=os.path.join(TOP, "out"))
    ap.add_argument("--full", action="store_true")
    a = ap.parse_args()
    logdir = os.path.join(a.workdir, "test-logs"); os.makedirs(logdir, exist_ok=True)
    disks = {}
    for role, size in SIZES.items():
        p = os.path.join(a.workdir, f"755c-{role}.img")
        with open(p, "wb") as f:
            f.truncate(size)            # sparse, all zeros
        disks[role] = p
    results = []

    def check(desc, ok, detail=""):
        results.append(bool(ok))
        print(f"  [{'PASS' if ok else 'FAIL'}] {desc}" + (f"  ({detail})" if detail else ""), flush=True)

    def qemu(boot, floppy=True, pty=False):
        c = ["qemu-system-i386", "-accel", "tcg", "-M", "isapc", "-cpu", "486", "-m", "32",
             "-display", "none", "-no-reboot"]
        if not pty:
            c += ["-monitor", "none", "-serial", "stdio"]
        if floppy:
            c += ["-drive", f"if=floppy,index=0,format=raw,file={a.img},readonly=on"]
        c += ["-drive", f"if=ide,index=0,format=raw,file={disks['master']}",
              "-drive", f"if=ide,index=1,format=raw,file={disks['slave']}", "-boot", boot]
        return c

    def shell(g):
        g.run("stty -echo 2>/dev/null; export PS1='# '", 20); g.expect(r"# ", 10)

    def interactive(g, cmd, answer, timeout=600):
        tag = "__TC32_%d__" % int(time.time() * 1000 % 1e9)
        g.send(f"{cmd}; echo {tag}=$?\r")
        out, _ = g.expect(r"Type [^\n]*: ", 300)
        g.send(answer + "\r")
        out2, m = g.expect(tag + r"=(\d+)\r?\n", timeout)
        return (out + out2).replace("\r", ""), int(m.group(1))

    def mbrs(g):
        o, _ = g.run("for d in sda sdb; do dd if=/dev/$d bs=512 count=4096 2>/dev/null | sha256sum; done")
        return o.split()

    print(f"== floppy {a.img}: -M isapc -cpu 486 -m 32, IDE master 4 GiB + slave 128 GiB (sparse)")
    log = os.path.join(logdir, "755c-installer.log")
    g = PtyGuest(qemu("a", pty=True), log) if a.full else Guest(qemu("a"), log)
    try:
        g.expect(r"boot: ", 60)
        check("syslinux boot: prompt on COM1", True)
        g.send("install floppy=0,thinkpad\r", slow=True)   # QEMU's FDC has a disk-change line
        out, _ = g.expect(r"root@box:[^\n#]*# ", 600)
        check("kernel + 3 initramfs boot on a 486 / 32 MB, root shell on COM1", True,
              f"{time.time() - g.t0:.0f} s wall clock, TCG")
        check("755C banner from e755c.xz shown at login", "755C dual-CF" in out)
        shell(g)
        o, _ = g.run("readlink /proc/$$/fd/0; ps | grep '[g]etty' | grep -c ttyS0; grep ttyS0 /etc/inittab")
        check("shell runs on ttyS0, spawned by the inittab ttyS0 getty", o.split()[0] == "/dev/ttyS0" and o.split()[1] != "0",
              " ".join(o.split()))
        o, _ = g.run("uname -m; grep -m1 'model name' /proc/cpuinfo; free | grep Mem")
        check("guest CPU is a 486", "486" in o, " ".join(o.split()))
        o, rc = g.run("install-dualcf detect", 60)
        print("    " + o.strip().replace("\n", "\n    "))
        check("detect: sda = IDE master, 4096 MB", re.search(r"/dev/sda\s+master\s+\(\S+\)\s+4096 MB", o), "")
        check("detect: sdb = IDE slave, 131072 MB", re.search(r"/dev/sdb\s+slave\s+\(\S+\)\s+131072 MB", o), "")
        check("detect exits 0", rc == 0)
        m0 = mbrs(g)
        o, rc = g.run("install-dualcf -n prepare", 120)
        check("prepare -n: plan only, exits 0", rc == 0 and "Dry run" in o and "tcdata" in o)
        for ans in ("YES", "ERASE sda", "erase sda sdb", ""):
            o, rc = interactive(g, "install-dualcf prepare", ans)
            check(f"prepare refuses answer {ans!r}: exit 1, 'Aborted'", rc == 1 and "Aborted; nothing was written" in o,
                  f"rc={rc}")
        check("first 2 MiB of sda and sdb unchanged after the refusals", mbrs(g) == m0)
        if a.full:
            t = time.time()
            o, rc = interactive(g, "install-dualcf prepare", "ERASE sda sdb", 7200)
            check("prepare with 'ERASE sda sdb' completes", rc == 0 and "Done." in o,
                  f"rc={rc}, {time.time() - t:.0f} s" + ("" if rc == 0 else " | " + o[-400:]))
            o, _ = g.run("fdisk -l /dev/sda /dev/sdb | grep '^/dev/'")
            print("    " + o.strip().replace("\n", "\n    "), flush=True)
            check("sdb1 FAT32 active (0b), sdb2 Linux (83)",
                  re.search(r"^/dev/sdb1\s+\*.*\bb\b", o, re.M) and re.search(r"^/dev/sdb2\s.*\b83\b", o, re.M))
            g.run("mkdir -p /mnt/tcdata && mount -t ext2 /dev/sdb2 /mnt/tcdata")
            o, rc = g.run("ls /mnt/tcdata /mnt/tcdata/tce")
            check("tcdata (ext2) has tce home opt incoming", rc == 0 and all(x in o for x in ("tce", "home", "opt", "incoming", "optional")))
            stage = os.path.join(TOP, "build/e755c-floppy"); sl = os.path.join(TOP, "build/syslinux-4.07/com32")
            files = [os.path.join(stage, "vmlinuz"), os.path.join(stage, "core.xz"),
                     os.path.join(sl, "menu/menu.c32"), os.path.join(sl, "chain/chain.c32")]
            t = time.time()
            r = subprocess.run([os.path.join(HERE, "host-send.sh"), "-b", "115200", g.pty] + files,
                               capture_output=True, text=True, timeout=3600)
            open(os.path.join(logdir, "755c-host-send.log"), "w").write(r.stdout + r.stderr)
            g.buf = b""
            check("host-send.sh: 4 files + SHA256SUMS over the COM1 pty (XMODEM-1K), each sha256-checked",
                  r.returncode == 0 and r.stdout.count("OK, checksums match") == 5, f"rc={r.returncode}, {time.time() - t:.0f} s")
            g.run("cd /mnt/tcdata/incoming && cp core.xz /tmp/c && echo x >> core.xz; cd /")
            o, rc = g.run("install-dualcf finish 2>&1", 300)
            check("finish refuses a corrupted file (checksum mismatch)", rc != 0 and "mismatch" in o, f"rc={rc}")
            g.run("cp /tmp/c /mnt/tcdata/incoming/core.xz")
            o, rc = g.run("install-dualcf finish 2>&1", 300)
            check("finish installs + verifies", rc == 0 and "Verified" in o, f"rc={rc}" + ("" if rc == 0 else " | " + o[-400:]))
            g.run("mkdir -p /mnt/d")
            o, _ = g.run("mount -t ext2 -o ro /dev/sda1 /mnt/d && cat /mnt/d/boot/extlinux/extlinux.conf; umount /mnt/d")
            check("extlinux.conf: UI menu.c32, tc/win98/rescue, tce=sdb2, chain hd1 1 swap",
                  all(x in o for x in ("UI menu.c32", "LABEL tc", "LABEL win98", "LABEL rescue", "tce=sdb2", "APPEND hd1 1 swap")))
            o, _ = g.run("mount -t ext2 -o ro /dev/sda1 /mnt/d && ls /mnt/d/boot/extlinux; umount /mnt/d")
            check("menu.c32 + chain.c32 installed next to ldlinux.sys", all(x in o for x in ("menu.c32", "chain.c32", "ldlinux.sys")))
            g.send("poweroff\r")
            try:
                g.expect(r"(Power down|System halted)", 120)
            except (TimeoutError, EOFError):
                pass
            g.close()
            print("== boot the master card, no floppy, no keypress")
            g = Guest(qemu("c", floppy=False), os.path.join(logdir, "755c-diskboot.log"))
            out, _ = g.expect(r"Tiny Core \(tce on sdb2", 120)
            check("menu.c32 menu on COM1 from sda (title, 3 entries)",
                  "ThinkPad 755C" in out or "ThinkPad 755C" in g.buf.decode("latin-1"), "")
            out2, _ = g.expect(r"Rescue", 30)
            check("menu lists Windows 98 SE and Rescue", "Windows 98 SE" in out2)
            out, _ = g.expect(r"root@box:[^\n#]*# ", 600)
            shell(g)
            o, _ = g.run("cat /proc/cmdline; grep -c '^/dev/sdb2 /mnt/sdb2 ext2' /proc/mounts; readlink /etc/sysconfig/tcedir")
            check("default label tc boots: sdb2 mounted, tcedir -> /mnt/sdb2/tce",
                  "tce=sdb2" in o and o.split()[-2] == "1" and o.split()[-1] == "/mnt/sdb2/tce",
                  " | ".join(o.strip().splitlines()))
    except (TimeoutError, EOFError) as e:
        check("step", False, str(e)); print(g.buf.decode("latin-1")[-1200:])
    finally:
        g.close()
        for p in disks.values():
            os.remove(p)
    print(f"== {sum(results)}/{len(results)} checks passed")
    return 0 if all(results) else 1


if __name__ == "__main__":
    sys.exit(main())
