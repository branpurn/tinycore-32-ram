#!/usr/bin/env python3
"""tc32 QEMU test harness (stdlib only, no pexpect needed).

Boots out/tc32.img in qemu-system-i386 with TCG and `-cpu 486` (KVM cannot
present a 486 to the guest), drives the syslinux prompt and the shell over
the emulated COM1, runs assertions and writes logs under out/test-logs/.
"""
import argparse, os, re, select, subprocess, sys, time

TOP = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


class Guest:
    def __init__(self, cmd, logpath):
        self.log = open(logpath, "wb")
        self.p = subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                  stderr=subprocess.STDOUT, bufsize=0)
        self.buf = b""
        self.t0 = time.time()

    def _pump(self, timeout):
        r, _, _ = select.select([self.p.stdout], [], [], timeout)
        if r:
            d = os.read(self.p.stdout.fileno(), 65536)
            if not d:
                raise EOFError("qemu exited")
            self.buf += d
            self.log.write(d); self.log.flush()

    def expect(self, pattern, timeout):
        rx = re.compile(pattern.encode() if isinstance(pattern, str) else pattern)
        end = time.time() + timeout
        while True:
            m = rx.search(self.buf)
            if m:
                out = self.buf[:m.end()]
                self.buf = self.buf[m.end():]
                return out.decode("latin-1"), m
            left = end - time.time()
            if left <= 0:
                raise TimeoutError(f"timeout waiting for {pattern!r}")
            self._pump(min(left, 0.5))

    def send(self, s, slow=False):
        # The guest UART has a tiny FIFO; type slowly so nothing is dropped.
        for ch in s.encode():
            self.p.stdin.write(bytes([ch])); self.p.stdin.flush()
            time.sleep(0.02 if slow else 0.005)

    def run(self, cmd, timeout=60):
        """Run a shell command; return (output, exit status)."""
        tag = "__TC32_%d__" % int(time.time() * 1000 % 1e9)
        self.send(f"{cmd}; echo {tag}=$?\r")
        out, m = self.expect(tag + r"=(\d+)\r?\n", timeout)
        body = out.rsplit(tag, 1)[0]
        if body.startswith(cmd):            # echoed command (if echo is on)
            body = body.split("\n", 1)[1] if "\n" in body else ""
        if body.startswith("# "):           # prompt printed before output
            body = body[2:]
        return body.replace("\r", ""), int(m.group(1))

    def close(self):
        try:
            self.p.kill()
        except Exception:
            pass
        self.p.wait()
        self.log.close()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--mem", type=int, default=32)
    ap.add_argument("--img", default=os.path.join(TOP, "out/tc32.img"))
    ap.add_argument("--disk", default=os.path.join(TOP, "out/test-disk.img"),
                    help="IDE test disk with tce/optional/*.tcz (optional)")
    ap.add_argument("--machine", default="isapc")
    ap.add_argument("--logdir", default=os.path.join(TOP, "out/test-logs"))
    ap.add_argument("--boot-timeout", type=int, default=300)
    ap.add_argument("--nokey", action="store_true",
                    help="do not type at the boot prompt (tests default auto-boot); no IDE disk")
    a = ap.parse_args()
    os.makedirs(a.logdir, exist_ok=True)
    name = f"m{a.mem}" + ("-nokey" if a.nokey else "")
    logpath = os.path.join(a.logdir, f"serial-{name}.log")
    cmd = ["qemu-system-i386", "-accel", "tcg", "-M", a.machine, "-cpu", "486",
           "-m", str(a.mem), "-drive", f"if=floppy,index=0,format=raw,file={a.img},readonly=on",
           "-boot", "a", "-display", "none", "-serial", "stdio", "-monitor", "none",
           "-no-reboot"]
    have_disk = os.path.exists(a.disk) and not a.nokey
    if have_disk:
        cmd += ["-drive", f"if=ide,index=0,format=raw,file={a.disk},snapshot=on"]
    results = []

    def check(desc, ok, detail=""):
        results.append((desc, bool(ok), detail))
        print(f"  [{'PASS' if ok else 'FAIL'}] {desc}" + (f"  ({detail})" if detail else ""), flush=True)
        return ok

    print(f"== tc32 test: -m {a.mem} -M {a.machine} -cpu 486 (TCG){' + IDE test disk' if have_disk else ''}")
    g = Guest(cmd, logpath)
    metrics = {"mem": a.mem}
    try:
        g.expect(r"boot: ", 60)
        check("syslinux prompt on COM1", True)
        if a.nokey:
            # Default entry, no keypress: must auto-boot after TIMEOUT.
            bootdesc = "default entry, no keypress"
        else:
            # Default label + extra boot codes (same kernel cmdline + tce=).
            g.send("tc32" + (" tce=sda1" if have_disk else "") + "\r", slow=True)
            bootdesc = "typed 'tc32" + (" tce=sda1" if have_disk else "") + "'"
        t_boot = time.time()
        try:
            out, _ = g.expect(r"tc32: ready\.", a.boot_timeout)
        except (TimeoutError, EOFError) as e:
            tail = g.buf.decode("latin-1")[-600:]
            check("kernel boots to rcS on serial console", False, str(e))
            print(tail)
            return finish(results, metrics, a, name)
        metrics["boot_s"] = round(time.time() - t_boot, 1)
        check("kernel boots to rcS on serial console", True, f"{bootdesc}; {metrics['boot_s']} s after boot prompt")
        check("kernel log on serial (console=ttyS0)", "Linux version" in out)
        m = re.search(r"Memory: (\d+)K/(\d+)K available \((\d+)K kernel code, (\d+)K rwdata, (\d+)K rodata, (\d+)K init, (\d+)K bss, (\d+)K reserved", out)
        if m:
            metrics["dmesg_memory"] = m.group(0)
        g.expect(r"root@box:[^\n#]*# ", 60)
        check("getty autologin root shell on ttyS0", True)
        g.run("stty -echo 2>/dev/null; export PS1='# '", 20)
        g.expect(r"# ", 10)

        o, rc = g.run("cat /proc/consoles")
        check("/proc/consoles: tty0 + ttyS0 (ttyS0 = /dev/console)",
              re.search(r"^ttyS0 .*C", o, re.M) and re.search(r"^tty0 ", o, re.M), " | ".join(l.split()[0] for l in o.strip().splitlines()))
        fdmap = "for p in /proc/[0-9]*; do t=$(readlink $p/fd/0 2>/dev/null) && echo ${p#/proc/} $t; done"
        o, rc = g.run(fdmap)
        ttys = {}
        for line in o.split("\n"):
            f = line.split()
            if len(f) == 2 and f[1] in ("/dev/ttyS0", "/dev/tty1"):
                ttys.setdefault(f[1], []).append(f[0])
        check("login shells on both ttyS0 and tty1", "/dev/ttyS0" in ttys and "/dev/tty1" in ttys,
              ", ".join(f"{k}: pid {' '.join(v)}" for k, v in sorted(ttys.items())))
        if "/dev/tty1" in ttys:
            old = set(ttys["/dev/tty1"])
            g.run("kill -9 " + " ".join(old) + "; sleep 3")
            o, rc = g.run(fdmap)
            new = {l.split()[0] for l in o.split("\n") if l.endswith(" /dev/tty1")}
            check("tty1 shell respawned by init", bool(new) and not (new & old), f"old {sorted(old)} -> new {sorted(new)}")
        o, rc = g.run("uname -m")
        check("uname -m is i486", rc == 0 and o.strip() == "i486", o.strip())
        metrics["uname"] = g.run("uname -sr")[0].strip()

        o, rc = g.run("free")
        mm = re.search(r"Mem:\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)", o)
        if check("free reports memory", rc == 0 and mm, o.strip().splitlines()[1] if mm else o.strip()):
            metrics.update(total_kb=int(mm.group(1)), used_kb=int(mm.group(2)),
                           free_kb=int(mm.group(3)), shared_kb=int(mm.group(4)),
                           buffcache_kb=int(mm.group(5)), avail_kb=int(mm.group(6)))
            metrics["free_raw"] = o.strip()

        o, rc = g.run("mount")
        check("/proc, /sys, /dev mounted",
              all(re.search(rf" on {p} type", o) for p in ("/proc", "/sys", "/dev")), "")
        o, rc = g.run("head -1 /proc/cpuinfo >/dev/null && grep -c . /proc/meminfo")
        check("procfs readable", rc == 0 and int(o.strip() or 0) > 5)

        o, rc = g.run("echo tc32-ok > /tmp/t1 && cat /tmp/t1 && rm /tmp/t1")
        check("create/read/delete file in /tmp (tmpfs)", rc == 0 and "tc32-ok" in o)
        o, rc = g.run("dd if=/dev/zero of=/tmp/big bs=1k count=2048 2>/dev/null && ls -l /tmp/big | awk '{print $5}'; rm -f /tmp/big")
        check("write 2 MB to RAM fs", rc == 0 and "2097152" in o, o.strip())

        o, rc = g.run("mkdir -p /mnt/fd0 && mount -t vfat -o ro /dev/fd0 /mnt/fd0 && ls /mnt/fd0; umount /mnt/fd0", 120)
        check("floppy driver + FAT mount (boot floppy)", rc == 0 and "vmlinuz" in o, " ".join(o.split()))

        if have_disk:
            o, rc = g.run("readlink /etc/sysconfig/tcedir; ls /usr/local/tce.installed")
            check("IDE disk mounted via tce=sda1 (pata_legacy, ext2)", "/mnt/sda1/tce" in o, " ".join(o.split()))
            o, rc = g.run("cat /proc/swaps")
            check("swap partition auto-enabled", "/dev/sda2" in o, " ".join(o.split()[-5:]))
            o, rc = g.run("hello-tcz")
            check("tce extension auto-loaded from onboot.lst (squashfs/xz)", rc == 0 and "hello from tcz" in o, o.strip())
            o, rc = g.run("tce-load -i /mnt/sda1/tce/optional/hellogz.tcz && hellogz-tcz")
            check("tce-load -i (squashfs/gzip, TC default)", rc == 0 and "hello from gz tcz" in o, " ".join(o.split()))
            o, rc = g.run("free | awk '/Mem:/{print $3, $4}'")
            metrics["after_tce_used_free_kb"] = o.strip()

        o, rc = g.run("busybox | head -1")
        metrics["busybox"] = o.strip()

        g.send("poweroff\r")
        try:
            o, _ = g.expect(r"(reboot: Power down|reboot: System halted|System halted|Power down)", 90)
            check("clean poweroff/halt", True, o.strip().splitlines()[-1])
        except (TimeoutError, EOFError) as e:
            check("clean poweroff/halt", False, str(e))
    except (TimeoutError, EOFError) as e:
        check("harness step", False, str(e))
        print(g.buf.decode("latin-1")[-600:])
    finally:
        g.close()
    return finish(results, metrics, a, name)


def finish(results, metrics, a, name):
    import json
    ok = all(r[1] for r in results) and results
    metrics["pass"] = bool(ok)
    metrics["results"] = [{"check": d, "pass": p, "detail": x} for d, p, x in results]
    with open(os.path.join(a.logdir, f"result-{name}.json"), "w") as f:
        json.dump(metrics, f, indent=2)
    print(f"== -m {a.mem}{' (nokey)' if a.nokey else ''}: {'PASS' if ok else 'FAIL'} "
          f"({sum(r[1] for r in results)}/{len(results)} checks)"
          + (f", free {metrics.get('free_kb')} kB of {metrics.get('total_kb')} kB" if 'free_kb' in metrics else ""))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
