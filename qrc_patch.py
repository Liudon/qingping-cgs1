#!/usr/bin/env python3
"""Replace one resource of the Qt qrc bundle inside an ELF, in place.

Usage: qrc_patch.py <orig_elf> <INDEX.tsv> <resource_path> <new_content_file> <out_elf>

The new blob must fit in the old slot (resource blobs are packed with no gaps).
Compressed resources are re-deflated (qCompress layout: 4-byte BE raw length + zlib).
The 4-byte length prefix is updated and the unused tail of the slot is zero-filled.
Nothing outside the slot is touched.
"""
import struct
import sys
import zlib

elf_path, index_path, res_path, new_path, out_path = sys.argv[1:6]
elf = bytearray(open(elf_path, "rb").read())
new_raw = open(new_path, "rb").read()

row = None
for line in list(open(index_path))[1:]:
    p = line.rstrip("\n").split("\t")
    if p[0] == "0" and p[1] == res_path:
        row = p
        break
if row is None:
    sys.exit("resource not found in bundle 0: " + res_path)

flags, off, stored = int(row[2]), int(row[3]), int(row[4])
assert struct.unpack(">I", elf[off:off + 4])[0] == stored, "length prefix mismatch"

if flags & 1:
    payload = struct.pack(">I", len(new_raw)) + zlib.compress(new_raw, 9)
else:
    payload = new_raw

print("slot %d bytes, new payload %d bytes, spare %d" % (stored, len(payload), stored - len(payload)))
if len(payload) > stored:
    sys.exit("DOES NOT FIT by %d bytes" % (len(payload) - stored))

elf[off:off + 4] = struct.pack(">I", len(payload))
elf[off + 4:off + 4 + stored] = payload + b"\x00" * (stored - len(payload))
assert len(elf) == len(open(elf_path, "rb").read())
open(out_path, "wb").write(elf)
print("wrote", out_path)
