#!/usr/bin/env python3
"""Parse and extract Qt resource (qrc) bundles embedded in an ELF executable.

Usage: qrc_dump.py <elf> <outdir>
Finds qt_resource_{struct,name,data} symbols via `nm`, parses each bundle,
extracts every file, writes an index. Read-only on the ELF.
"""
import os
import struct
import subprocess
import sys
import zlib

ELF = sys.argv[1]
OUT = sys.argv[2]

blob = open(ELF, "rb").read()


def sections():
    out = subprocess.check_output(["readelf", "-S", "-W", ELF], text=True)
    secs = []
    for line in out.splitlines():
        line = line.replace("[ ", "[")
        p = line.split()
        if len(p) > 6 and p[0].startswith("[") and p[1].startswith("."):
            try:
                secs.append((p[1], int(p[3], 16), int(p[4], 16), int(p[5], 16)))
            except ValueError:
                pass
    return secs


SECS = sections()


def v2o(vaddr):
    for _, va, off, size in SECS:
        if va <= vaddr < va + size:
            return vaddr - va + off
    raise ValueError(hex(vaddr))


def symbols():
    out = subprocess.check_output(["nm", "-C", ELF], text=True)
    d = {"struct": [], "name": [], "data": []}
    for line in out.splitlines():
        p = line.split()
        if len(p) == 3 and p[2].startswith("qt_resource_"):
            d[p[2][len("qt_resource_"):]].append(int(p[0], 16))
    for k in d:
        d[k].sort()
    return d


def u16(o):
    return struct.unpack(">H", blob[o:o + 2])[0]


def u32(o):
    return struct.unpack(">I", blob[o:o + 4])[0]


def name_at(name_off):
    ln = u16(name_off)
    s = blob[name_off + 6:name_off + 6 + ln * 2].decode("utf-16-be")
    return s


class Bundle:
    def __init__(self, st, nm, dt, esize):
        self.st, self.nm, self.dt, self.esize = st, nm, dt, esize

    def entry(self, idx):
        o = self.st + idx * self.esize
        name_off = u32(o)
        flags = u16(o + 4)
        if flags & 2:
            return name_off, flags, u32(o + 6), u32(o + 10)  # count, first child
        return name_off, flags, u16(o + 6), u32(o + 10)  # country, ... data off at +10

    def walk(self, idx=0, path=""):
        name_off, flags, a, b = self.entry(idx)
        name = name_at(self.nm + name_off) if idx else ""
        full = path + "/" + name if idx else ""
        if flags & 2:
            for i in range(a):
                yield from self.walk(b + i, full)
        else:
            yield full, flags, b

    def read(self, flags, data_off):
        o = self.dt + data_off
        ln = u32(o)
        raw = blob[o + 4:o + 4 + ln]
        if flags & 1:
            raw = zlib.decompress(raw[4:])
        return raw, o, ln


def try_bundle(st, nm, dt):
    for esize in (14, 22):
        try:
            b = Bundle(st, nm, dt, esize)
            n0, f0, cnt, first = b.entry(0)
            if not (f0 & 2) or cnt == 0 or cnt > 200 or n0 != 0:
                continue
            items = list(b.walk())
            if items and all(p.startswith("/") for p, _, _ in items):
                return b, items
        except Exception:
            continue
    return None, None


def main():
    sy = symbols()
    print("symbols:", {k: [hex(x) for x in v] for k, v in sy.items()})
    os.makedirs(OUT, exist_ok=True)
    idx = open(os.path.join(OUT, "INDEX.tsv"), "w")
    idx.write("bundle\tpath\tflags\tdata_file_off\tstored_len\tsize\n")
    for bi, st in enumerate(sy["struct"]):
        # match the nearest name/data symbols laid out together
        nm = min(sy["name"], key=lambda x: abs(x - st))
        dt = min(sy["data"], key=lambda x: abs(x - st))
        b, items = try_bundle(v2o(st), v2o(nm), v2o(dt))
        if not b:
            print("bundle", bi, hex(st), "could not parse")
            continue
        print("bundle", bi, "struct", hex(st), "entry size", b.esize, "files", len(items))
        for path, flags, doff in items:
            try:
                data, o, ln = b.read(flags, doff)
            except Exception as e:
                print("  read fail", path, e)
                continue
            dest = os.path.join(OUT, "b%d" % bi, path.lstrip("/"))
            os.makedirs(os.path.dirname(dest), exist_ok=True)
            open(dest, "wb").write(data)
            idx.write("%d\t%s\t%d\t%d\t%d\t%d\n" % (bi, path, flags, o, ln, len(data)))
    idx.close()


main()
