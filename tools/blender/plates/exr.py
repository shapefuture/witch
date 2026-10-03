"""Minimal reader for uncompressed scanline OpenEXR, single or multi-part (Blender 5 writes one
part per render pass when the codec is NONE)."""
import struct

import numpy as np


def _header(data, pos):
    header = {}
    while True:
        end = data.index(b"\0", pos)
        name = data[pos:end].decode()
        pos = end + 1
        if not name:
            return header, pos
        end = data.index(b"\0", pos)
        typ = data[pos:end].decode()
        pos = end + 1
        size = struct.unpack_from("<i", data, pos)[0]
        pos += 4
        header[name] = (typ, data[pos:pos + size])
        pos += size


def _channels(chl):
    chans, p = [], 0
    while chl[p] != 0:
        end = chl.index(b"\0", p)
        cname = chl[p:end].decode()
        p = end + 1
        chans.append((cname, struct.unpack_from("<i", chl, p)[0]))
        p += 16
    return sorted(chans)


def read(path):
    data = open(path, "rb").read()
    assert struct.unpack_from("<I", data, 0)[0] == 20000630, "not an EXR"
    flags = struct.unpack_from("<I", data, 4)[0]
    multipart = bool(flags & 0x1000)
    pos = 8
    headers = []
    while True:
        h, pos = _header(data, pos)
        headers.append(h)
        if not multipart:
            break
        if data[pos] == 0:
            pos += 1
            break
    parts = []
    for h in headers:
        assert h["compression"][1][0] == 0, "compressed EXR (use codec NONE)"
        x0, y0, x1, y1 = struct.unpack("<iiii", h["dataWindow"][1])
        w, hh = x1 - x0 + 1, y1 - y0 + 1
        n = struct.unpack("<i", h["chunkCount"][1])[0] if "chunkCount" in h else hh
        offsets = struct.unpack_from("<%dQ" % n, data, pos)
        pos += 8 * n
        parts.append((h, w, hh, y0, offsets))
    out = {}
    for pi, (h, w, hh, y0, offsets) in enumerate(parts):
        chans = _channels(h["channels"][1])
        arrs = {c: np.zeros((hh, w), np.float32) for c, _ in chans}
        for off in offsets:
            q = off + (4 if multipart else 0)
            y = struct.unpack_from("<i", data, q)[0] - y0
            q += 8
            for cname, ptype in chans:
                if ptype == 2:
                    arrs[cname][y] = np.frombuffer(data, "<f4", w, q)
                    q += 4 * w
                elif ptype == 1:
                    arrs[cname][y] = np.frombuffer(data, "<f2", w, q).astype(np.float32)
                    q += 2 * w
                else:
                    q += 4 * w
        out.update(arrs)
    return out
