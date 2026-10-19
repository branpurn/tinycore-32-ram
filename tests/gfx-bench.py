#!/usr/bin/env python3
"""X / framebuffer benchmark in QEMU (-M isapc -cpu 486, TCG) on the 755C
kernel with wd90c24fb (docs/GRAPHICS.md "Speed"; tests/bench-gfx.sh runs
the standard set).

QEMU has no WD90C24: wd90c24fb.fake=2 drives its VGA as one (CPU copies
only), fake=3 also emulates the BITBLT engine on a RAM model of video
memory and checks the model against the frame after the run (the X
damage/acceleration protocol must leave them identical), fake=4 accepts
engine operations without spending CPU on them (timing). QEMU maps the
A0000 window as RAM, so --extra wd90c24fb.fake_kbps=N models the VL-bus;
-icount shift=4 makes the guest about as fast as a DX4-100. The numbers
are a model, not the 755C: compare runs with each other.
  tests/gfx-bench.py [--fake 2|3|4] [--tag NAME] [--kernel K] [--disk D] [--extra ARGS]
Writes out/test-logs/bench-NAME.json.
"""
import argparse, json, os, re, sys, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from harness import Guest, TOP


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--fake", type=int, default=2)
    ap.add_argument("--tag", default="")
    ap.add_argument("--kernel", default=os.path.join(TOP, "out/gfx/755c/vmlinuz.x"))
    ap.add_argument("--disk", default=os.path.join(TOP, "out/gfx/test-disk-gfx.img"))
    ap.add_argument("--mem", type=int, default=36)
    ap.add_argument("--extra", default="", help="more kernel arguments")
    ap.add_argument("--icount", type=int, default=4,
                    help="QEMU -icount shift (4: ~60 MIPS, about a DX4-100); -1 = off")
    a = ap.parse_args()
    name = "bench-" + (a.tag or f"fake{a.fake}")
    logdir = os.path.join(TOP, "out/test-logs"); os.makedirs(logdir, exist_ok=True)
    append = (f"console=tty0 console=ttyS0,9600n8 tce=sda1 atkbd.xlate=2 "
              f"wd90c24fb.fake={a.fake} wd90c24fb.trial=0 {a.extra}").strip()
    cmd = ["qemu-system-i386", "-accel", "tcg", "-M", "isapc", "-cpu", "486", "-m", str(a.mem),
           "-vga", "std", "-display", "none", "-serial", "stdio", "-no-reboot",
           "-kernel", a.kernel, "-initrd", os.path.join(TOP, "out/core.xz"), "-append", append,
           "-drive", f"if=ide,index=0,format=raw,file={a.disk},snapshot=on"]
    if a.icount >= 0:
        cmd[3:3] = ["-icount", f"shift={a.icount},sleep=on"]
    r = {"tag": name, "fake": a.fake, "append": append}
    print(f"== {name}: {append}", flush=True)
    g = Guest(cmd, os.path.join(logdir, f"serial-{name}.log"))
    ok = False
    try:
        g.expect(r"tc32: ready\.", 400)
        g.expect(r"root@box:[^\n#]*# ", 60)
        g.run("stty -echo 2>/dev/null; dmesg -n 1; export PS1='# '", 20)
        g.expect(r"# ", 10)
        g.run("for e in modutils fb-wd90c24; do tce-load -i /mnt/sda1/tce/optional/$e.tcz >/dev/null 2>&1; done; sleep 2", 120)
        r["dmesg"] = g.run("dmesg | grep -E 'wd90c24fb|fb0' | tail -4")[0].strip()
        st = "/sys/module/wd90c24fb/parameters/stats"
        def stats():
            o, rc = g.run(f"cat {st} 2>/dev/null")
            return dict(re.findall(r"(\w+)=(\d+)", o))
        def busy(sec):
            o, _ = g.run(f"head -1 /proc/stat; sleep {sec}; head -1 /proc/stat", sec + 30)
            v = [list(map(int, l.split()[1:])) for l in o.strip().split("\n") if l.startswith("cpu ")]
            d = [y - x for x, y in zip(v[0], v[1])]
            idle = d[3] + (d[4] if len(d) > 4 else 0)
            return round(100.0 * (sum(d) - idle) / max(1, sum(d)), 1)
        # 1) raw full-frame flush: write() of whole frames on the console fb
        o, _ = g.run("s=$(cut -d' ' -f1 /proc/uptime); i=0; while [ $i -lt 30 ]; do dd if=/dev/zero of=/dev/fb0 bs=307200 count=1 2>/dev/null; i=$((i+1)); done; e=$(cut -d' ' -f1 /proc/uptime); echo \"$s $e\" | awk '{print ($2-$1)*1000}'", 600)
        ms = float(o.strip().split()[-1])
        r["fbwrite_full_frame_ms"] = round(ms / 30.0, 1)
        print(f"  write(): {r['fbwrite_full_frame_ms']} ms per 300 KiB frame", flush=True)
        # 2) X
        g.run("startx > /tmp/startx.log 2>&1 < /dev/null & sleep 1")
        for _ in range(120):
            o, rc = g.run("cat /tmp/startx.log; pidof jwm rxvt")
            if "Xfbdev running" in o and len(o.strip().split("\n")[-1].split()) >= 2:
                break
            if re.search(r"failed|no /dev/fb0|not found|did not start", o):
                raise RuntimeError(o)
            time.sleep(3)
        time.sleep(20)
        r["x_idle_busy_pct"] = busy(10)
        print(f"  X idle: {r['x_idle_busy_pct']}% CPU busy", flush=True)
        r["xbench"], r["stats"], raw = {}, {}, ""
        for t in ("scroll", "fill", "text", "move"):
            s0 = stats()
            o, rc = g.run(f"head -1 /proc/stat; DISPLAY=:0 /mnt/sda1/tce/optional/xbench {t} 2>&1; head -1 /proc/stat; sleep 1", 600)
            v = [list(map(int, l.split()[1:])) for l in o.split("\n") if l.startswith("cpu ")]
            dd = [y - x for x, y in zip(v[0], v[1])] if len(v) == 2 else [0] * 5
            sysirq = sum(dd[2:3]) + sum(dd[5:7])
            cpu = f"user {100 * dd[0] // max(1, sum(dd))}% sys+irq {100 * sysirq // max(1, sum(dd))}% idle {100 * (dd[3] + dd[4]) // max(1, sum(dd))}%"
            s1 = stats()
            raw += o
            for m in re.findall(r"xbench (\S+) (\d+) (\d+) ([\d.]+)", o):
                r["xbench"][m[0]] = {"ops": int(m[1]), "ms": int(m[2]), "ops_s": float(m[3])}
                d = {k: int(s1[k]) - int(s0.get(k, 0)) if k not in ("accel", "client")
                     else int(s1[k]) for k in s1} if s0 and s1 else {}
                d["cpu"] = cpu
                r["stats"][m[0]] = d
                print(f"  xbench {m[0]:12s} {float(m[3]):8.1f} ops/s  ({m[1]} in {m[2]} ms)  {d}", flush=True)
        r["xbench_raw"] = raw
        time.sleep(3)
        o, _ = g.run("cat /sys/module/wd90c24fb/parameters/verify 2>/dev/null || echo n/a")
        r["verify"] = o.strip()
        print(f"  model vs frame: {r['verify']}", flush=True)
        r["Xfbdev_log"] = g.run("tail -5 /tmp/Xfbdev.log")[0].strip()
        ok = len(r["xbench"]) == 4 and (a.fake != 3 or r["verify"].startswith("0 "))
    except (TimeoutError, EOFError, RuntimeError) as e:
        r["error"] = str(e)
        print("  ERROR", e, g.buf.decode("latin-1")[-600:])
    finally:
        g.close()
    r["pass"] = ok
    with open(os.path.join(logdir, name + ".json"), "w") as f:
        json.dump(r, f, indent=2)
    print(f"== {name}: {'PASS' if ok else 'FAIL'}")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
