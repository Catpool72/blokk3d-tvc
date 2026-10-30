#!/usr/bin/env python3
"""Wrap a BASIC-area image (loaded at $19EF) into a TVC .CAS file (unbuffered, autorun)."""
import sys

src, dst = sys.argv[1], sys.argv[2]
data = open(src, "rb").read()
size = len(data)
body = bytearray(16)
body[0] = 0x00
body[1] = 0x01                 # program file
body[2] = size & 0xFF
body[3] = size >> 8
body[4] = 0xFF                 # autorun
body[15] = 0x00                # version
body += data
blocks, last = divmod(len(body), 128)
if last:
    blocks += 1
hdr = bytearray(128)
hdr[0] = 0x11                  # unbuffered
hdr[1] = 0x00                  # not protected
hdr[2] = blocks & 0xFF
hdr[3] = blocks >> 8
hdr[4] = last
open(dst, "wb").write(hdr + body)
print(f"{dst}: program {size} bytes, file {len(hdr) + len(body)} bytes", file=sys.stderr)
