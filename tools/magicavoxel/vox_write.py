#!/usr/bin/env python3
"""Author a MagicaVoxel .vox file from a voxel dict.

Writes the container documented in assets/source/magicavoxel/README.md:
MagicVAE / Compressed 3D, one layer, RLE chunks, a 98-entry RGBA palette and a
pivot. That is the format the project's importer reads, and the format
tools/magicavoxel/author_props.py and author_tier_b.py emit.

Voxels are given as {(x, y, z): palette_index} with 0-based integer
coordinates. Index 0 is air and is never written.
"""

import struct
import sys
from collections import defaultdict

PALETTE_SIZE = 98


def encode_rle(values):
    """MagicaVoxel run-length encoding: a count byte (1..127) then the value."""
    out = bytearray()
    i = 0
    while i < len(values):
        value = values[i]
        run = 1
        while run < 127 and i + run < len(values) and values[i + run] == value:
            run += 1
        out.append(run)
        out.append(value)
        i += run
    return bytes(out)


def write_vox(path, voxels, palette, pivot=(0.0, 0.0, 0.0), origin=(0, 0, 0)):
    """palette: list of (r, g, b, a) with index 0 = air. Returns the voxel count."""
    if not voxels:
        raise ValueError("no voxels to write")
    for (x, y, z), colour in voxels.items():
        if colour < 1 or colour >= len(palette):
            raise ValueError("palette index %r out of range at %r" % (colour, (x, y, z)))
        if x < origin[0] or y < origin[1] or z < origin[2]:
            raise ValueError("voxel %r is below the origin" % ((x, y, z),))

    xs = [v[0] for v in voxels]
    ys = [v[1] for v in voxels]
    zs = [v[2] for v in voxels]
    size = (max(xs) + 1 - origin[0], max(ys) + 1 - origin[1], max(zs) + 1 - origin[2])

    # One RLE chunk per 128-cube column, matching how MagicaVoxel lays out layers.
    columns = defaultdict(dict)
    for (x, y, z), colour in voxels.items():
        columns[(x, y)][z] = colour

    chunks = []
    for (x, y), column in sorted(columns.items()):
        zs = sorted(column)
        if zs[-1] - zs[0] + 1 != len(column) and len(column) > 1:
            # A chunk is one contiguous run; a gap in z needs a second chunk.
            run_start = zs[0]
            for a, b in zip(zs, zs[1:] + [zs[-1] + 2]):
                if b != a + 1:
                    values = [column[z] for z in zs if run_start <= z <= a]
                    chunks.append(((x, y, run_start), encode_rle(values)))
                    run_start = b
        else:
            values = [column[z] for z in zs]
            chunks.append(((x, y, zs[0]), encode_rle(values)))

    out = bytearray()
    out += b"MagicVAE\x00"
    out += b"Compressed 3D\x00"
    out += struct.pack("<3i", *size)
    out += struct.pack("<i", 1)  # numLayers
    out += struct.pack("<3i", *size)
    out += struct.pack("<i", len(chunks))
    for pos, data in chunks:
        out += struct.pack("<3i", *pos)
        out += struct.pack("<i", len(data))
        out += data

    padded = list(palette[:PALETTE_SIZE])
    while len(padded) < PALETTE_SIZE:
        padded.append((0, 0, 0, 0))
    for r, g, b, a in padded:
        out += struct.pack("<4B", r, g, b, a)
    out += struct.pack("<3f", *pivot)

    with open(path, "wb") as handle:
        handle.write(out)
    return len(voxels)


def main(argv):
    if len(argv) != 1:
        print(__doc__)
        return 2
    print("use as a library: write_vox(path, voxels, palette, pivot)")
    print("verification: tools/magicavoxel/vox_to_obj.py prints a model's cells")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
