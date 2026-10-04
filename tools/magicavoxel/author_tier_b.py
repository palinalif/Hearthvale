#!/usr/bin/env python3
"""Author the Tier B garden props as MagicaVoxel .vox sources.

Tier B is the set the runtime used to build procedurally from boxes:
fence, bush, hedge, flower, grass tuft, rock. Those are standalone
presentation props, so per the project contract they are authored as
voxel assets; the runtime now only imports the baked result.

Every dimension is on the 0.125 structural grid and matches the
placement records the builder emits, so existing saves keep their
objects. Cells are added and removed to shape the silhouette; nothing
is stretched.

Voxels are (x, y, z) with y = height above the ground, which is the
axis order the project's importer reads.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from vox_write import write_vox  # noqa: E402

SIZE = 0.125
PALETTE = [(0, 0, 0, 0)] + [
    (104, 74, 44, 255),   # 1 wood
    (142, 104, 62, 255),  # 2 light wood
    (122, 122, 128, 255), # 3 iron
    (46, 106, 46, 255),   # 4 leaf dark
    (62, 132, 58, 255),   # 5 leaf
    (86, 156, 70, 255),   # 6 leaf light
    (122, 116, 104, 255), # 7 stone
    (146, 140, 126, 255), # 8 stone light
    (96, 92, 84, 255),    # 9 stone dark
    (214, 172, 62, 255),  # 10 flower gold
    (206, 96, 118, 255),  # 11 flower rose
    (152, 176, 96, 255),  # 12 stem
    (176, 160, 128, 255), # 13 thatch
]


def box(x0, y0, z0, x1, y1, z1, colour):
    return {(x, y, z): colour
            for x in range(x0, x1 + 1)
            for y in range(y0, y1 + 1)
            for z in range(z0, z1 + 1)}


def fence():
    """One 1.000 x 0.125 x 0.875 fence section: two posts, two rails."""
    v = {}
    for px in (0, 7):
        for y in range(7):
            v[(px, y, 0)] = 1 if y < 5 else 2
        v[(px, 5, 0)] = 2
        v[(px, 6, 0)] = 2
    v |= box(1, 4, 0, 6, 4, 0, 2)
    v |= box(1, 2, 0, 6, 2, 0, 1)
    return (8, 7, 1), v


def bush():
    """A rounded 0.750 cube of foliage: wide middle, clipped corners."""
    v = {}
    rings = [(0, 5, 1, 4), (0, 5, 0, 5), (1, 4, 0, 5), (1, 4, 0, 5), (2, 3, 1, 4)]
    for y, (x0, x1, z0, z1) in enumerate(rings):
        for x in range(x0, x1 + 1):
            for z in range(z0, z1 + 1):
                v[(x, y, z)] = 4 if (x + z) % 3 == 0 else 5
    for x in range(2, 4):
        for z in range(2, 4):
            v[(x, 5, z)] = 6
    for (x, z) in ((1, 2), (4, 3)):
        v[(x, 0, z)] = 9
    return (6, 6, 6), v


def hedge():
    """A 1.000 x 0.250 x 0.750 clipped hedge wall with an uneven top."""
    v = {}
    for y in range(6):
        for x in range(8):
            for z in range(2):
                v[(x, y, z)] = 4 if (x + z + y) % 3 == 0 else 5
    for x in range(8):
        cap = 6 if x % 3 == 1 else 5
        for y in range(6, cap):
            for z in range(2):
                v[(x, y, z)] = 6
    return (8, 6, 2), v


def flower():
    """A 0.375 stem with a five-cell head and two leaves."""
    v = {}
    for y in range(2):
        v[(1, y, 1)] = 12
    v[(1, 2, 1)] = 10
    for (x, z) in ((0, 1), (2, 1), (1, 0), (1, 2)):
        v[(x, 2, z)] = 11
    v[(0, 1, 1)] = 12
    v[(1, 1, 2)] = 12
    return (3, 3, 3), v


def grass():
    """A 0.375 tuft: a tight base fanning to five blades."""
    v = {}
    for x in range(2):
        for z in range(2):
            v[(x, 0, z)] = 4
    for (x, z, y) in ((0, 0, 2), (2, 0, 1), (1, 2, 2), (0, 2, 1), (2, 2, 2), (1, 1, 1)):
        v[(x, y, z)] = 5
    for (x, z) in ((0, 0), (2, 2)):
        v[(x, 2, z)] = 6
    return (3, 3, 3), v


def rock():
    """A 0.500 x 0.375 x 0.250 boulder with a lit shoulder and a dark foot."""
    v = {}
    for x in range(4):
        for z in range(3):
            v[(x, 0, z)] = 9 if x in (0, 3) else 7
    for x in range(1, 3):
        for z in range(1, 2):
            v[(x, 1, z)] = 8
    v[(1, 1, 0)] = 8
    v[(2, 1, 2)] = 7
    return (4, 2, 3), v


BUILDERS = {
    "fence": fence,
    "bush": bush,
    "hedge": hedge,
    "flower": flower,
    "grass": grass,
    "rock": rock,
}


def main(argv):
    out_dir = argv[1] if len(argv) > 1 else os.path.dirname(__file__)
    for name, builder in BUILDERS.items():
        size, voxels = builder()
        path = os.path.join(out_dir, "hearthvale_prop_%s.vox" % name)
        count = write_vox(path, voxels, PALETTE)
        dims = " x ".join("%.3f" % (c * SIZE) for c in size)
        print("%-8s %5d cells  size %s  dims %s" % (name, count, size, dims))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
