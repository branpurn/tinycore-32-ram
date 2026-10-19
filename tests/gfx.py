#!/usr/bin/env python3
"""Graphics second-stage test (docs/GRAPHICS.md) in QEMU: -M isapc -cpu 486.

Boots a kernel (-kernel) with out/core.xz and the gfx test disk
(tests/mk-gfx-disk.sh), runs `startx` from the serial shell, drives the
PS/2 mouse and keyboard through the QEMU monitor, takes PNG screendumps
and measures RAM under X.
  --mode vesa : out/gfx/bzImage (test kernel, vesafb vga=0x301) -- screenshots
  --mode wd   : the 755C kernel (tc755x) + modutils/fb-wd90c24/trackpoint .tcz,
                wd90c24fb.fake=2 (QEMU has no WD90C24: functional run only,
                the picture is not meaningful)
"""
import argparse, json, os, re, socket, sys, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from harness import Guest, TOP


class Mon:
    def __init__(self, path):
        for _ in range(50):
            try:
                self.s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
                self.s.connect(path)
                break
            except OSError:
                time.sleep(0.2)
        self.s.settimeout(2)
        self.read()

    def read(self):
        d = b""
        try:
            while True:
                c = self.s.recv(65536)
                if not c:
                    break
                d += c
                if d.endswith(b"(qemu) "):
                    break
        except socket.timeout:
            pass
        return d.decode("latin-1")

    def cmd(self, c, wait=0.0):
        self.s.sendall((c + "\n").encode())
        r = self.read()
        if wait:
            time.sleep(wait)
        return r

    def keys(self, text):
        q = {" ": "spc", "-": "minus", "/": "slash", ".": "dot", "\n": "ret", "=": "equal"}
        for ch in text:
            k = q.get(ch) or ("shift-" + ch.lower() if ch.isupper() else ch)
            self.cmd("sendkey " + k, 0.25)


def ppm2png(src, dst):
    """Binary PPM (P6, maxval 255) -> PNG with the stdlib only."""
    import struct, zlib
    d = open(src, "rb").read()
    hdr = []
    i = 0
    while len(hdr) < 4:
        while d[i:i+1].isspace():
            i += 1
        if d[i:i+1] == b"#":
            i = d.index(b"\n", i) + 1
            continue
        j = i
        while not d[j:j+1].isspace():
            j += 1
        hdr.append(d[i:j]); i = j
    i += 1
    if hdr[0] != b"P6":
        return False
    w, h = int(hdr[1]), int(hdr[2])
    px = d[i:i + w * h * 3]
    raw = b"".join(b"\0" + px[y * w * 3:(y + 1) * w * 3] for y in range(h))
    def chunk(t, b):
        return struct.pack(">I", len(b)) + t + b + struct.pack(">I", zlib.crc32(t + b) & 0xffffffff)
    open(dst, "wb").write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
                         + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))
    return True


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--mode", choices=["vesa", "wd"], default="vesa")
    ap.add_argument("--kernel")
    ap.add_argument("--mem", type=int, default=36)
    ap.add_argument("--vga", default="std")
    ap.add_argument("--disk", default=os.path.join(TOP, "out/gfx/test-disk-gfx.img"))
    ap.add_argument("--out", default=os.path.join(TOP, "out/gfx"))
    a = ap.parse_args()
    kern = a.kernel or os.path.join(TOP, "out/gfx/bzImage" if a.mode == "vesa" else "out/gfx/755c/vmlinuz.x")
    logdir = os.path.join(TOP, "out/test-logs"); os.makedirs(logdir, exist_ok=True)
    name = f"gfx-{a.mode}-m{a.mem}"
    mon = os.path.join(logdir, f"monitor-{name}.sock")
    if os.path.exists(mon):
        os.unlink(mon)
    append = "console=tty0 console=ttyS0,9600n8 tce=sda1 atkbd.xlate=2"
    if a.mode == "vesa":
        append += " vga=0x301 video=vesafb:vgapal"   # program the VGA DAC (QEMU VBE has no PMI)
    else:
        append += " wd90c24fb.fake=2 wd90c24fb.trial=0"
    cmd = ["qemu-system-i386", "-accel", "tcg", "-M", "isapc", "-cpu", "486", "-m", str(a.mem),
           "-vga", a.vga, "-display", "none", "-serial", "stdio", "-no-reboot",
           "-monitor", f"unix:{mon},server=on,wait=off",
           "-kernel", kern, "-initrd", os.path.join(TOP, "out/core.xz"), "-append", append,
           "-drive", f"if=ide,index=0,format=raw,file={a.disk},snapshot=on"]
    res, metrics = [], {"mode": a.mode, "mem": a.mem, "kernel": os.path.basename(kern)}

    def check(d, ok, x=""):
        res.append({"check": d, "pass": bool(ok), "detail": x})
        print(f"  [{'PASS' if ok else 'FAIL'}] {d}" + (f"  ({x})" if x else ""), flush=True)
        return ok

    print(f"== gfx test ({a.mode}): -M isapc -cpu 486 -m {a.mem} -vga {a.vga}")
    g = Guest(cmd, os.path.join(logdir, f"serial-{name}.log"))
    m = None
    try:
        t0 = time.time()
        g.expect(r"tc32: ready\.", 400)
        g.expect(r"root@box:[^\n#]*# ", 60)
        check("boots to a root shell", True, f"{time.time()-t0:.0f} s")
        m = Mon(mon)
        g.run("stty -echo 2>/dev/null; dmesg -n 1; export PS1='# '", 20)
        g.expect(r"# ", 10)
        metrics["uname"] = g.run("uname -r")[0].strip()
        o, rc = g.run("cat /proc/meminfo | head -2; free | sed -n 2p")
        metrics["meminfo_boot"] = o.strip()
        def fbchecks():
            o, rc = g.run("cat /proc/fb; cat /sys/class/graphics/fb0/bits_per_pixel /sys/class/graphics/fb0/virtual_size /sys/class/graphics/fb0/stride")
            metrics["fb"] = " | ".join(o.split("\n")).strip()
            check("/dev/fb0 is 640x480, 8 bpp, 640-byte lines", re.search(r"^8$", o, re.M) and "640,480" in o and re.search(r"^640$", o, re.M), metrics["fb"])
            o, rc = g.run("ls /dev/input/mice && dmesg | grep -iE 'psmouse|mice|PS/2' | tail -3")
            check("PS/2 mouse (i8042 AUX -> psmouse -> /dev/input/mice)", rc == 0, " ".join(o.split())[:160])
        if a.mode == "vesa":
            fbchecks()       # built into the test kernel
        o, rc = g.run("free | sed -n 2,3p")
        metrics["free_before_x"] = o.strip()

        o, rc = g.run("[ -d /mnt/sda1/deliver ] && sh /mnt/sda1/deliver/gfx-setup.sh /mnt/sda1/deliver"
                      " && tce-load -i Xfbdev && tail -4 /mnt/sda1/boot/extlinux/extlinux.conf", 120)
        if "gfx-setup" in o:
            metrics["gfx_setup"] = o.strip()
            check("tools/gfx-setup.sh installs the files + extlinux label x", rc == 0 and "LABEL x" in o
                  and "KERNEL /boot/vmlinuz.x" in o and "BAD" not in o, " | ".join(o.split("\n"))[-300:])
        t1 = time.time()
        g.run("startx > /tmp/startx.log 2>&1 < /dev/null & sleep 1")
        up = False
        for _ in range(120):
            o, rc = g.run("cat /tmp/startx.log; pidof jwm rxvt")
            if re.search(r"Xfbdev failed|startx: no /dev/fb0|vga16fb \(4 bpp|Xfbdev not found|did not start", o):
                break
            if "Xfbdev running" in o and len(o.strip().split("\n")[-1].split()) >= 2:
                up = True
                break
            time.sleep(3)
        metrics["startx_log"] = o.strip()
        metrics["x_start_s"] = round(time.time() - t1)
        check("startx: Xfbdev + jwm + rxvt running", up, f"{metrics['x_start_s']} s; " + " | ".join(o.strip().split("\n")))
        if not up:
            print(g.run("tail -20 /tmp/Xfbdev.log")[0])
            raise RuntimeError("X did not start")
        if a.mode == "wd":
            fbchecks()       # loaded by startx: modutils + fb-wd90c24 + trackpoint
            metrics["wd_dmesg"] = g.run("dmesg | grep -iE 'wd90c24fb|vga16fb|fb0' | tail -6")[0].strip()
        time.sleep(25)
        # type into the terminal (focused): PS/2 keyboard -> VT -> X -> rxvt
        m.keys("uname -a\n")
        m.keys("ls /usr/local/bin\n")
        time.sleep(15)
        shots = []
        def shot(tag):
            p = os.path.join(a.out, f"x-{a.mode}-{tag}.png")
            if os.path.exists(p):
                os.unlink(p)
            ppm = p[:-4] + ".ppm"
            m.cmd(f"screendump {ppm}", 3)        # QEMU 8.2 HMP: PPM only
            ok = os.path.exists(ppm) and ppm2png(ppm, p)
            # QEMU's VGA has no WD90C24 PR0(A) bank register, so in wd mode only
            # bank 0 (the top 102 lines) lands on screen: the PNG proves the real
            # palette and bank 0, the rest is checked by process/menu state.
            ok = ok and (a.mode == "wd" or os.path.getsize(p) > 2000)
            if os.path.exists(ppm):
                os.unlink(ppm)
            shots.append(p)
            return ok, p
        metrics["procs_at_shot1"] = g.run("pidof rxvt jwm Xfbdev")[0].strip()
        ok, p = shot("1-terminal")
        check("screendump: desktop + rxvt", ok, p)
        # Root menu with the mouse. kdrive autodetects the mouse protocol
        # from the first packets, so wiggle first, then move right of rxvt.
        for i in range(30):
            m.cmd("mouse_move %d 0" % (2 if i % 2 else -2), 0.2)
        for _ in range(13):
            m.cmd("mouse_move 20 0", 0.3)
        time.sleep(3)
        m.cmd("mouse_button 1", 0.3); m.cmd("mouse_button 0", 6)
        ok, p = shot("2-menu")
        check("screendump: jwm root menu opened by a mouse click", ok, p)
        # pick "Clock (xclock)" (2nd entry) with the keyboard
        m.cmd("sendkey down", 1); m.cmd("sendkey down", 1); m.cmd("sendkey ret", 1)
        launched = False
        for _ in range(30):
            if g.run("pidof xclock")[1] == 0:
                launched = True
                break
            time.sleep(3)
        check("menu entry launches xclock", launched)
        g.run("export DISPLAY=:0; xcalc -geometry +400+150 & xeyes -geometry 150x100+470+20 & "
              + ("" if launched else "xclock -geometry +500+300 &") + " sleep 1")
        for _ in range(30):
            if g.run("pidof xcalc && pidof xeyes && pidof xclock")[1] == 0:
                break
            time.sleep(3)
        time.sleep(40)
        for _ in range(3):
            m.cmd("mouse_move -40 -30", 0.4)      # let the eyes follow
        time.sleep(10)
        ok, p = shot("3-apps")
        check("screendump: xclock, xcalc, xeyes", ok, p)

        o, rc = g.run("free | sed -n 2,3p; grep -E 'MemAvailable|SwapFree|SwapTotal' /proc/meminfo")
        metrics["free_under_x"] = o.strip()
        rss = {}
        for prog in ("Xfbdev", "jwm", "rxvt", "xclock", "xcalc", "xeyes"):
            o2, rc2 = g.run(f"for p in $(pidof {prog}); do grep -E 'VmRSS' /proc/$p/status; done")
            mm = re.findall(r"VmRSS:\s+(\d+)", o2)
            if mm:
                rss[prog] = sum(int(x) for x in mm)
        metrics["rss_kb"] = rss
        mb = re.search(r"Mem:\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)", o)
        check("RAM under X measured", bool(rss) and mb, f"RSS kB {rss}; free: {' '.join(o.split()[:7])}")

        g.run("kill $(pidof jwm)")
        time.sleep(8)
        o, rc = g.run("cat /tmp/startx.log; pidof Xfbdev || echo no-x")
        check("Exit: X stops with the session", "no-x" in o, o.strip().split("\n")[-1])
    except (TimeoutError, EOFError, RuntimeError) as e:
        check("harness step", False, str(e))
        print(g.buf.decode("latin-1")[-800:])
    finally:
        g.close()
        if os.path.exists(mon):
            os.unlink(mon)
    ok = all(r["pass"] for r in res) and res
    metrics["pass"] = bool(ok); metrics["results"] = res
    with open(os.path.join(logdir, f"result-{name}.json"), "w") as f:
        json.dump(metrics, f, indent=2)
    print(f"== {name}: {'PASS' if ok else 'FAIL'} ({sum(r['pass'] for r in res)}/{len(res)} checks)")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
