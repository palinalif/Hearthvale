#!/usr/bin/env python3
"""Reader/writer for the MagicaVoxel chunked ``VOX `` v150 files this repo stores.

Every ``.vox`` under ``assets/source/magicavoxel`` is MagicaVoxel's own output:
version 150, a flat ``MAIN`` containing ``SIZE``, ``XYZI`` and ``RGBA``, with
four-byte voxel records (x, y, z, material).  The older ``MagicVA`` layout that
``vox_write.py`` emits is a different file, so sources authored here must go
through this module to stay openable in MagicaVoxel.

Verified by round-tripping a shipped file byte-for-byte (see round_trip_check).
"""
from __future__ import annotations

import struct
import sys
from pathlib import Path

VERSION = 150
PALETTE_SIZE = 256


def read_vox(path: Path) -> tuple[tuple[int, int, int], list[tuple[int, int, int, int]], list[tuple[int, int, int, int]]]:
    """Return (size, voxels, palette) for a MagicaVoxel v150 file."""
    data = Path(path).read_bytes()
    if data[:4] != b"VOX ":
        raise ValueError(f"{path} is not a chunked VOX file (magic {data[:4]!r})")
    version = struct.unpack_from("<i", data, 4)[0]
    if version != VERSION:
        raise ValueError(f"{path} is version {version}, expected {VERSION}")

    size = None
    voxels: list[tuple[int, int, int, int]] = []
    palette: list[tuple[int, int, int, int]] = []

    # Chunks start straight after the 8-byte header; v150 has no total-bytes field.
    off = data.find(b"SIZE")
    if off < 0:
        raise ValueError(f"{path} has no SIZE chunk")
    size = struct.unpack_from("<3i", data, off + 12)

    off = data.find(b"XYZI")
    if off < 0:
        raise ValueError(f"{path} has no XYZI chunk")
    content_len = struct.unpack_from("<i", data, off + 4)[0]
    count = struct.unpack_from("<i", data, off + 12)[0]
    stride = 4 if 4 + 4 * count == content_len else 3
    for i in range(count):
        rec = struct.unpack_from("<%dB" % stride, data, off + 16 + stride * i)
        voxels.append((rec[0], rec[1], rec[2], rec[3] if stride == 4 else 1))

    off = data.find(b"RGBA")
    if off < 0:
        raise ValueError(f"{path} has no RGBA chunk")
    palette = [struct.unpack_from("<4B", data, off + 12 + 4 * i) for i in range(PALETTE_SIZE)]

    return tuple(size), voxels, palette


def write_vox(path: Path, voxels: dict[tuple[int, int, int], int], palette: list[tuple[int, int, int, int]],
              size: tuple[int, int, int] | None = None) -> int:
    """Write voxels {(x, y, z): colour} in MagicaVoxel's v150 layout.

    ``palette`` is indexed by colour (index 0 is air).  Coordinates must be
    non-negative and below ``size``.
    """
    if not voxels:
        raise ValueError("no voxels to write")
    xs = [v[0] for v in voxels]
    ys = [v[1] for v in voxels]
    zs = [v[2] for v in voxels]
    if min(xs) < 0 or min(ys) < 0 or min(zs) < 0:
        raise ValueError("voxel coordinates must be non-negative")
    if size is None:
        size = (max(xs) + 1, max(ys) + 1, max(zs) + 1)
    for (x, y, z), colour in voxels.items():
        if x >= size[0] or y >= size[1] or z >= size[2]:
            raise ValueError("voxel %r exceeds size %r" % ((x, y, z), size))
        if colour < 1 or colour >= PALETTE_SIZE:
            raise ValueError("palette index %r out of range at %r" % (colour, (x, y, z)))

    # MagicaVoxel orders voxels by z, then y, then x within each layer.
    ordered = sorted(voxels.items(), key=lambda item: (item[0][2], item[0][1], item[0][0]))
    xyzi = struct.pack("<i", len(ordered))
    xyzi += b"".join(struct.pack("<4B", x, y, z, colour) for (x, y, z), colour in ordered)
    rgba = b"".join(struct.pack("<4B", *(palette[i] if i < len(palette) else (0, 0, 0, 0)))
                    for i in range(PALETTE_SIZE))

    children = b"".join([
        b"SIZE" + struct.pack("<ii", 12, 0) + struct.pack("<3i", *size),
        b"XYZI" + struct.pack("<ii", len(xyzi), 0) + xyzi,
        b"RGBA" + struct.pack("<ii", len(rgba), 0) + rgba,
    ])
    # MagicaVoxel's own writer reports MAIN's children length excluding its
    # 12-byte header; matching it byte-for-byte keeps the file indistinguishable.
    main = b"MAIN" + struct.pack("<ii", 0, len(children) - 12)
    out = b"VOX " + struct.pack("<i", VERSION) + main + children
    Path(path).write_bytes(out)
    return len(ordered)


def round_trip_check(path: Path) -> bool:
    """Re-write a shipped file and require the bytes to be identical."""
    size, voxels, palette = read_vox(path)
    cells = {(x, y, z): colour for x, y, z, colour in voxels}
    if len(cells) != len(voxels):
        raise ValueError(f"{path} has duplicate voxel coordinates")
    tmp = Path(path).with_suffix(".roundtrip.vox")
    write_vox(tmp, cells, palette, size)
    same = tmp.read_bytes() == path.read_bytes()
    tmp.unlink()
    return same


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__)
        return 2
    target = Path(sys.argv[1])
    size, voxels, palette = read_vox(target)
    print(f"{target.name}: size={size} voxels={len(voxels)}")
    print(f"  byte-identical round trip: {round_trip_check(target)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
