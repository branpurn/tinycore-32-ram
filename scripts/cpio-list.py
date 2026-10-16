#!/usr/bin/env python3
"""Emit a gen_init_cpio list for a staging dir. Everything is root:root
except /home/tc (uid 1001, gid 50, as on Tiny Core)."""
import os, stat, sys
root = sys.argv[1]
out = []
for dp, dns, fns in os.walk(root):
    dns.sort(); fns.sort()
    for n in [None] + dns + fns:
        p = dp if n is None else os.path.join(dp, n)
        rel = "/" + os.path.relpath(p, root)
        if rel == "/.": continue
        st = os.lstat(p)
        if n is not None and stat.S_ISDIR(st.st_mode): continue  # emitted on visit
        m = stat.S_IMODE(st.st_mode)
        mode = "755" if (stat.S_ISDIR(st.st_mode) or m & 0o100) else "644"
        uid, gid = (1001, 50) if rel.startswith("/home/tc") else (0, 0)
        if rel == "/tmp": mode = "1777"
        if stat.S_ISDIR(st.st_mode): out.append(f"dir {rel} {mode} {uid} {gid}")
        elif stat.S_ISLNK(st.st_mode): out.append(f"slink {rel} {os.readlink(p)} 777 {uid} {gid}")
        elif stat.S_ISREG(st.st_mode): out.append(f"file {rel} {p} {mode} {uid} {gid}")
print("\n".join(out))
