#!/usr/bin/env python3
"""Rewrite PNGs as 24-bit RGB at maximum compression (#57).

Play refuses a feature graphic with an alpha channel, and the screenshots
carry one they do not need. Standard library only; the image must be 8-bit
RGBA (colour type 6) or already RGB (type 2, left as is). Alpha is
dropped, not blended: every pixel these files hold is opaque.

Usage:  tools/png_strip_alpha.py FILE.png [...]
Exit:   0 written, 1 a file is not an 8-bit RGB or RGBA PNG
"""
import struct
import sys
import zlib

SIGNATURE = b"\x89PNG\r\n\x1a\n"


def chunks(data: bytes):
    at = 8
    while at < len(data):
        n, kind = struct.unpack(">I4s", data[at:at + 8])
        yield kind, data[at + 8:at + 8 + n]
        at += 12 + n


def unfilter(raw: bytes, width: int, height: int, bpp: int) -> list:
    stride = width * bpp
    rows, prev = [], bytearray(stride)
    for y in range(height):
        f = raw[y * (stride + 1)]
        row = bytearray(raw[y * (stride + 1) + 1:(y + 1) * (stride + 1)])
        for x in range(stride):
            a = row[x - bpp] if x >= bpp else 0
            b = prev[x]
            c = prev[x - bpp] if x >= bpp else 0
            if f == 1:
                row[x] = (row[x] + a) & 255
            elif f == 2:
                row[x] = (row[x] + b) & 255
            elif f == 3:
                row[x] = (row[x] + (a + b) // 2) & 255
            elif f == 4:
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                row[x] = (row[x] + (a if pa <= pb and pa <= pc else b if pb <= pc else c)) & 255
        rows.append(row)
        prev = row
    return rows


def chunk(kind: bytes, body: bytes) -> bytes:
    return struct.pack(">I", len(body)) + kind + body + struct.pack(">I", zlib.crc32(kind + body))


def strip(path: str) -> None:
    data = open(path, "rb").read()
    if data[:8] != SIGNATURE:
        sys.exit(f"png_strip_alpha: {path} is not a PNG")
    parts = list(chunks(data))
    w, h, depth, ctype = struct.unpack(">IIBB", dict(parts)[b"IHDR"][:10])
    if (depth, ctype) == (8, 2):
        return
    if (depth, ctype) != (8, 6):
        sys.exit(f"png_strip_alpha: {path} is depth {depth} type {ctype}")
    raw = zlib.decompress(b"".join(body for kind, body in parts if kind == b"IDAT"))
    out = bytearray()
    for row in unfilter(raw, w, h, 4):
        out += b"\x00"
        for i in range(0, len(row), 4):
            out += row[i:i + 3]
    open(path, "wb").write(
        SIGNATURE
        + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(bytes(out), 9))
        + chunk(b"IEND", b"")
    )


if __name__ == "__main__":
    for p in sys.argv[1:]:
        strip(p)
