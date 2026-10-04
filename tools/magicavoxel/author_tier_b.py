#!/usr/bin/env python3
"""Author the Tier B starter-hamlet garden props as MagicaVoxel sources.

These six props used to be boxes and cylinders assembled in GDScript.  They are
now authored voxel assets so they get the same treatment as everything else the
hamlet places: a reviewable .vox source, per-part colours from the shared
palette, greedy-meshed geometry, and a Mobile-friendly material per part.

Grid: the project contract puts native terrain and authoritative structure on
0.125, and allows decorative presentation down to 0.0625.  These props are
decorative, so they are authored on 0.125 and bake on 0.0625 like the rest of
the presentation set.  Sizes below are in cells of 0.125 m.

Authoring uses the Builder in author_props.py, which is the only writer in this
repo that emits MagicaVoxel format 150 -- the format Godot's voxel importer can
read.  Files written by the legacy MagicaVASE writer in vox_write.py are not
importable by Godot.
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from author_props import Builder

CELL = 0.125

# The accepted Tier A props are authored at 0.25 m per voxel, and the runtime
# scales authored meshes by 0.5. Drawing on that same cell keeps every prop in
# the hamlet at one resolution; the designs below are drawn on 0.125 cells and
# emitted at double resolution, so they land at the accepted size.
AUTHOR_CELL = 0.25
UPSCALE = int(round(AUTHOR_CELL / CELL))


def authored(model: Builder) -> Builder:
    """Re-draw a 0.125-cell design on the 0.25 m cell the Tier A props use."""
    if UPSCALE == 1:
        return model
    out = Builder(*(d * UPSCALE for d in model.size))
    for (x, y, z), colour in model.cells.items():
        for dx in range(UPSCALE):
            for dy in range(UPSCALE):
                for dz in range(UPSCALE):
                    out.cells[(x * UPSCALE + dx, y * UPSCALE + dy, z * UPSCALE + dz)] = colour
    return out

# Shared palette indices, taken from author_props.PALETTE so the props match
# the colours the rest of the hamlet already uses.
WOOD = 15        # (150, 106, 62)
WOOD_DARK = 1    # (122, 84, 50)
LEAF = 11        # (104, 152, 78)
LEAF_LIGHT = 12  # (140, 184, 104)
STONE = 22       # (126, 132, 138)
STONE_LIGHT = 7  # (168, 164, 156)
PETAL_RED = 18
PETAL_YELLOW = 13
PETAL_WHITE = 19
PETAL_PINK = 3


def fence() -> Builder:
    """One 1.000 x 0.875 fence section: two posts, two rails, chamfered post tops.

    Width along x, depth along y, height along z.  The rails sit at the front
    face so a row of sections reads as a continuous fence from the walk side.
    """
    b = Builder(8, 1, 7)
    for post_x in (0, 7):
        for z in range(7):
            b.set(post_x, 0, z, WOOD if z % 3 else WOOD_DARK)
        # Chamfered post cap.
        b.cells.pop((post_x, 0, 6), None)
    for rail_z in (2, 4):
        for x in range(1, 7):
            b.set(x, 0, rail_z, WOOD_DARK)
    return b


def bush() -> Builder:
    """A 0.625 m bush: a 5 x 5 x 4 mass with every top corner clipped."""
    b = Builder(5, 5, 4)
    for x in range(5):
        for y in range(5):
            for z in range(4):
                # Taper the base and clip the top corners so it is not a cube.
                if z == 0 and (x == 0 and y == 0 or x == 4 and y == 0
                               or x == 0 and y == 4 or x == 4 and y == 4):
                    continue
                if z == 3 and (x + y) in (0, 8):
                    continue
                shade = LEAF_LIGHT if (x + y + z) % 3 == 0 else LEAF
                b.set(x, y, z, shade)
    return b


def hedge() -> Builder:
    """A 1.000 x 0.375 x 0.500 hedge with a clipped, two-tone top face."""
    b = Builder(8, 3, 4)
    for x in range(8):
        for y in range(3):
            for z in range(4):
                if z == 3 and (x == 0 or x == 7):
                    continue
                shade = LEAF_LIGHT if z == 3 or (x + y) % 4 == 0 else LEAF
                b.set(x, y, z, shade)
    return b


def flower() -> Builder:
    """A 0.375 m flower: stem, two leaves, five-cell head with a pollen centre."""
    b = Builder(4, 4, 5)
    b.set(1, 1, 0, LEAF)
    b.set(1, 1, 1, LEAF)
    b.set(1, 1, 2, LEAF)
    b.set(0, 1, 1, LEAF_LIGHT)
    b.set(1, 2, 2, LEAF_LIGHT)
    for x, y in ((0, 0), (2, 0), (1, 1), (0, 2), (2, 2)):
        b.set(x, y, 3, PETAL_RED)
    b.set(1, 1, 3, PETAL_YELLOW)
    b.set(1, 1, 4, PETAL_YELLOW)
    return b


def grass() -> Builder:
    """A 0.500 x 0.500 x 0.375 grass tuft: nine blades of staggered height."""
    b = Builder(4, 4, 3)
    heights = {(0, 0): 2, (0, 2): 3, (1, 1): 3, (2, 0): 2, (2, 2): 3,
               (3, 1): 2, (1, 3): 2, (3, 3): 3, (0, 3): 1}
    for (x, y), top in heights.items():
        for z in range(top + 1):
            b.set(x, y, z, LEAF_LIGHT if z == top else LEAF)
    return b


def rock() -> Builder:
    """A 0.500 x 0.500 x 0.375 boulder: a chamfered, two-tone stone mass."""
    b = Builder(4, 4, 3)
    for x in range(4):
        for y in range(4):
            for z in range(3):
                if z == 2 and (x + y) in (0, 6):
                    continue
                if z == 0 and (x == 0 and y == 0 or x == 3 and y == 3):
                    continue
                top = z == 2 or (z == 1 and x >= 2 and y >= 2)
                b.set(x, y, z, STONE_LIGHT if top else STONE)
    return b


MODELS = {
    "fence": fence,
    "bush": bush,
    "hedge": hedge,
    "flower": flower,
    "grass": grass,
    "rock": rock,
}


def main(argv: list[str]) -> int:
    out = Path(argv[0]) if argv else Path("assets/source/magicavoxel")
    out.mkdir(parents=True, exist_ok=True)
    for name, builder in MODELS.items():
        model = authored(builder())
        path = out / ("hearthvale_prop_%s.vox" % name)
        count = model.write(path)
        x, y, z = model.size
        print(f"{name:11s} {count:5d} cells  {x * AUTHOR_CELL:.3f} x {z * AUTHOR_CELL:.3f} x {y * AUTHOR_CELL:.3f} m")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
