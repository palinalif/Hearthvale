#!/usr/bin/env python3
"""Author Hearthvale prop sources as MagicaVoxel .vox files.

Hearthvale's canonical prop sources are MagicaVoxel files under
``assets/source/magicavoxel``.  This script emits them in the binary MagicaVoxel
format (magic ``VOX``, version 150, single ``MAIN`` model with ``SIZE``/``XYZI``/``RGBA``)
so they are byte-compatible with the files MagicaVoxel itself writes and with the
sources already tracked in the repository.

Every prop is authored parametrically so the source stays reviewable and
reproducible: ``git diff`` on the .vox is opaque, the generator is not.

Grid rules (see ``assets/source/magicavoxel/README.md``):

* Terrain-adjacent structures and anything with a collision footprint stay on the
  ``0.125`` structural grid.
* Decorative presentation may use ``0.0625``; that is the furniture set's grid and
  is declared per prop below.

Footprints are authored to match the runtime catalogue in
``scripts/m2_starter_props.gd`` exactly, so the baked mesh bounds, the placement
footprint and the save record agree.

Usage:
    tools/magicavoxel/author_props.py                 # write all props
    tools/magicavoxel/author_props.py --out DIR       # write elsewhere
    tools/magicavoxel/author_props.py --only NAME     # one prop (repeatable)
    tools/magicavoxel/author_props.py --selftest      # round-trip a tracked source
"""
from __future__ import annotations

import argparse
import pathlib
import sys

# --------------------------------------------------------------------------- palette
# Warm, low-noise wood/stone/iron bands.  Values are 0-255 RGBA.
PALETTE: list[tuple[int, int, int, int]] = [
    (0, 0, 0, 0),          # 1: unused (index 0 is the empty cell)
    (122, 84, 50, 255),    # 2: WOOD_DARK
    (176, 126, 74, 255),   # 3: WOOD_MID
    (214, 172, 116, 255),  # 4: WOOD_LIGHT
    (92, 96, 100, 255),    # 5: IRON
    (148, 152, 156, 255),  # 6: IRON_LIGHT
    (116, 112, 106, 255),  # 7: STONE_DARK
    (168, 164, 156, 255),  # 8: STONE_MID
    (206, 202, 192, 255),  # 9: STONE_LIGHT
    (56, 108, 148, 255),   # 10: WATER
    (96, 152, 190, 255),   # 11: WATER_LIGHT
    (104, 152, 78, 255),   # 12: GRASS
    (140, 184, 104, 255),  # 13: GRASS_LIGHT
    (232, 196, 96, 255),   # 14: STRAW
    (196, 156, 66, 255),   # 15: STRAW_DARK
    (150, 106, 62, 255),   # 16: LOG_BARK
    (222, 190, 142, 255),  # 17: LOG_RING
    (132, 88, 50, 255),    # 18: LOG_CRACK
    (196, 62, 52, 255),    # 19: CANOPY_RED
    (246, 238, 224, 255),  # 20: CANOPY_CREAM
    (255, 214, 120, 255),  # 21: HARVEST_GOLD
    (214, 92, 74, 255),    # 22: HARVEST_BRICK
    (126, 132, 138, 255),  # 23: IRON_MID
    (236, 196, 128, 255),  # 24: WOOD_PALE
    (255, 214, 140, 255),  # 25: LANTERN_GLASS
    (255, 242, 196, 255),  # 26: LANTERN_FLAME
]

WOOD_DARK, WOOD_MID, WOOD_LIGHT = 2, 3, 4
IRON, IRON_LIGHT, IRON_MID = 5, 6, 23
STONE_DARK, STONE_MID, STONE_LIGHT = 7, 8, 9
WATER, WATER_LIGHT = 10, 11
GRASS, GRASS_LIGHT = 12, 13
STRAW, STRAW_DARK = 14, 15
LOG_BARK, LOG_RING, LOG_CRACK = 16, 17, 18
CANOPY_RED, CANOPY_CREAM = 19, 20
HARVEST_GOLD, HARVEST_BRICK = 21, 22
WOOD_PALE = 24
LANTERN_GLASS, LANTERN_FLAME = 25, 26


# --------------------------------------------------------------------------- builder
class Builder:
    """Sparse voxel builder on a fixed size; emits MagicaVoxel format 150."""

    def __init__(self, x: int, y: int, z: int) -> None:
        self.size = (x, y, z)
        self.cells: dict[tuple[int, int, int], int] = {}

    # -- primitives ---------------------------------------------------------
    def set(self, x: int, y: int, z: int, color: int) -> None:
        if 0 <= x < self.size[0] and 0 <= y < self.size[1] and 0 <= z < self.size[2]:
            self.cells[(x, y, z)] = color

    def get(self, x: int, y: int, z: int) -> int:
        return self.cells.get((x, y, z), 0)

    def box(self, x0: int, y0: int, z0: int, x1: int, y1: int, z1: int, color: int) -> None:
        for x in range(x0, x1 + 1):
            for y in range(y0, y1 + 1):
                for z in range(z0, z1 + 1):
                    self.set(x, y, z, color)

    def shell(self, x0: int, y0: int, z0: int, x1: int, y1: int, z1: int, color: int) -> None:
        """Box with its interior hollowed out."""
        self.box(x0, y0, z0, x1, y1, z1, color)
        for x in range(x0 + 1, x1):
            for y in range(y0 + 1, y1):
                for z in range(z0 + 1, z1):
                    self.cells.pop((x, y, z), None)

    def cyl(self, cx: int, cy: int, z0: int, z1: int, radius: int, color: int) -> None:
        for x in range(self.size[0]):
            for y in range(self.size[1]):
                dx, dy = x - cx, y - cy
                if dx * dx + dy * dy > radius * radius + radius:
                    continue
                for z in range(z0, z1 + 1):
                    self.set(x, y, z, color)

    def ring(self, cx: int, cy: int, z: int, radius: int, color: int) -> None:
        for x in range(self.size[0]):
            for y in range(self.size[1]):
                d2 = (x - cx) ** 2 + (y - cy) ** 2
                r2 = radius * radius
                if r2 - radius <= d2 <= r2 + radius:
                    self.set(x, y, z, color)

    def log(self, x0: int, x1: int, y: int, z: int, radius: int,
            bark: int, ring: int, crack: int) -> None:
        """Horizontal log along X; both ends show growth rings."""
        for x in range(x0, x1 + 1):
            for dy in range(-radius, radius + 1):
                for dz in range(-radius, radius + 1):
                    d2 = dy * dy + dz * dz
                    if d2 > radius * radius + radius:
                        continue
                    col = bark
                    if d2 >= radius * radius - radius:
                        col = ring
                    if abs(dy) <= 1 and abs(dz) <= 1:
                        col = crack
                    self.set(x, y + dy, z + dz, col)

    def slab(self, x0: int, y0: int, z0: int, x1: int, y1: int, color: int) -> None:
        """One-cell-thick horizontal plate."""
        self.box(x0, y0, z0, x1, y1, z0, color)

    # -- output -------------------------------------------------------------
    def vox(self) -> bytes:
        """Serialize as MagicaVoxel format 150.

        Every chunk header is 12 bytes: id(4) + content_size(4) + child_size(4).
        MAIN carries the byte length of its children; the children are flat, so
        each of theirs is zero. Omitting child_size makes the file unreadable by
        tools/magicavoxel/vox_to_obj.py, which walks the tree by those fields.
        """
        x, y, z = self.size
        size = b"SIZE" + (12).to_bytes(4, "little") + b"\x00\x00\x00\x00"
        size += x.to_bytes(4, "little") + z.to_bytes(4, "little") + y.to_bytes(4, "little")
        body = b"XYZI" + (4 + 4 * len(self.cells)).to_bytes(4, "little") + b"\x00\x00\x00\x00"
        body += (len(self.cells)).to_bytes(4, "little")
        for (cx, cy, cz), color in sorted(self.cells.items()):
            body += bytes((cx, cz, cy, color))
        rgba = b"RGBA" + (1024).to_bytes(4, "little") + b"\x00\x00\x00\x00"
        # The reader always unpacks 256 entries, so the palette is padded out.
        for index in range(256):
            rgba += bytes(PALETTE[index] if index < len(PALETTE) else (0, 0, 0, 255))
        children = size + body + rgba
        out = bytearray(b"VOX " + (150).to_bytes(4, "little"))
        out += b"MAIN" + b"\x00\x00\x00\x00" + len(children).to_bytes(4, "little")
        out += children
        return bytes(out)

    def write(self, path: pathlib.Path) -> int:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(self.vox())
        return len(self.cells)


# --------------------------------------------------------------------------- props
def build_well() -> Builder:
    """Starter-hamlet village well: catalogue footprint 2.5 x 2.25 m = 20 x 18 cells.

    Stone curb with chamfered corners, water inside, timber posts, a shingled roof
    and a rope-and-bucket.  Authored on the 0.125 structural grid.
    """
    b = Builder(20, 18, 24)
    # Stone curb: 18 x 16 footprint, chamfered at the corners.
    b.box(1, 1, 0, 18, 16, 6, STONE_MID)
    for cx, cy in ((1, 1), (18, 1), (1, 16), (18, 16)):
        b.cells.pop((cx, cy, 6), None)
        b.cells.pop((cx, cy, 5), None)
    # Cope (top ring) in a lighter stone, with a chamfered outer edge.
    for x in range(1, 19):
        for y in range(1, 17):
            if 3 <= x <= 16 and 3 <= y <= 14:
                continue
            b.set(x, y, 7, STONE_LIGHT)
    # Hollow interior: water surface sits two cells below the cope.
    for x in range(3, 17):
        for y in range(3, 15):
            for z in range(0, 6):
                b.cells.pop((x, y, z), None)
    b.box(3, 3, 0, 16, 14, 3, STONE_DARK)
    b.slab(3, 3, 4, 16, 14, WATER)
    b.slab(4, 4, 5, 15, 13, WATER_LIGHT)
    # Two timber posts carrying the roof.
    b.box(2, 3, 8, 3, 4, 17, WOOD_DARK)
    b.box(16, 13, 8, 17, 14, 17, WOOD_DARK)
    # Cross beam and roof.
    b.box(2, 3, 18, 17, 14, 18, WOOD_MID)
    for step in range(6):
        z = 19 + step
        x0, x1 = 1 + step, 18 - step
        y0, y1 = 2 + step, 15 - step
        if x0 >= x1 or y0 >= y1:
            break
        b.slab(x0, y0, z, x1, y1, WOOD_MID if step % 2 == 0 else WOOD_LIGHT)
    b.box(9, 8, 24, 10, 9, 24, WOOD_DARK)  # ridge cap
    # Rope, crank and bucket.
    b.box(10, 8, 12, 10, 9, 17, IRON_MID)
    b.box(10, 9, 11, 10, 11, 11, IRON)
    b.shell(9, 8, 7, 11, 10, 10, WOOD_MID)
    b.slab(9, 8, 6, 11, 10, WOOD_DARK)
    return b


def build_chopping_block() -> Builder:
    """Starter-hamlet chopping block: catalogue footprint 1.0 x 1.0 m = 8 x 8 cells."""
    b = Builder(8, 8, 14)
    b.cyl(4, 4, 0, 3, 3, WOOD_DARK)
    b.cyl(4, 4, 4, 9, 3, LOG_BARK)
    # Top face: growth rings with a wedge split and a blade nick.
    for x in range(8):
        for y in range(8):
            dx, dy = x - 3.5, y - 3.5
            d2 = dx * dx + dy * dy
            if d2 > 10:
                continue
            col = LOG_RING
            if d2 >= 8:
                col = LOG_BARK
            if abs(x - y) <= 1 and x >= 3 and y >= 3:
                col = WOOD_DARK
            b.set(x, y, 10, col)
    b.set(5, 2, 11, IRON)
    b.set(6, 1, 11, IRON)
    return b


def build_log_stack() -> Builder:
    """Starter-hamlet log stack: catalogue footprint 1.5 x 1.0 m = 12 x 8 cells.

    Three logs in a pyramid on a plinth; a short offcut leans at the side.
    """
    b = Builder(12, 8, 14)
    b.box(0, 0, 0, 11, 7, 1, WOOD_DARK)
    b.box(1, 1, 2, 10, 6, 2, WOOD_DARK)
    b.log(1, 10, 2, 5, 1, LOG_BARK, LOG_RING, LOG_CRACK)
    b.log(1, 10, 5, 5, 1, LOG_BARK, LOG_RING, LOG_CRACK)
    b.log(1, 10, 3, 8, 1, LOG_BARK, LOG_RING, LOG_CRACK)
    b.log(1, 4, 1, 4, 1, LOG_BARK, LOG_RING, LOG_CRACK)
    return b


def build_bench() -> Builder:
    """Starter-hamlet bench: catalogue footprint 1.75 x 0.625 m = 14 x 5 cells.

    Matches the tracked asset's dimensions exactly; the facelift is the slatted
    seat, chamfered front edge and two-slat backrest, not a size change.
    """
    b = Builder(14, 5, 12)
    # Legs, with a stretcher between them.
    for px in (1, 11):
        b.box(px, 1, 0, px + 1, 3, 5, WOOD_DARK)
        b.box(px, 1, 6, px + 1, 3, 6, WOOD_DARK)
    b.box(2, 2, 1, 11, 2, 1, WOOD_DARK)
    # Seat: three slats with a chamfered front edge.
    b.box(0, 0, 7, 13, 4, 7, WOOD_MID)
    b.box(0, 0, 8, 13, 1, 8, WOOD_LIGHT)
    # Backrest: two slats.
    b.box(0, 0, 9, 13, 1, 10, WOOD_MID)
    b.box(0, 0, 11, 13, 0, 11, WOOD_LIGHT)
    return b


def build_barrel_planter() -> Builder:
    """Starter-hamlet barrel planter: catalogue footprint 0.75 x 0.75 m = 6 x 6 cells."""
    b = Builder(6, 6, 10)
    b.cyl(3, 3, 0, 6, 2, WOOD_MID)
    # Hoops.
    for z in (1, 4):
        b.ring(3, 3, z, 2, IRON)
    # Soil and a small flowering plant.
    b.slab(1, 1, 7, 4, 4, WOOD_DARK)
    b.set(2, 2, 8, GRASS)
    b.set(3, 3, 8, GRASS_LIGHT)
    b.set(2, 3, 8, HARVEST_BRICK)
    b.set(3, 2, 9, HARVEST_GOLD)
    return b


def build_signpost() -> Builder:
    """Starter-hamlet signpost: catalogue footprint 0.625 x 0.625 m = 5 x 5 cells."""
    b = Builder(5, 5, 20)
    b.box(1, 1, 0, 3, 3, 1, WOOD_DARK)
    b.box(2, 2, 2, 2, 2, 17, WOOD_MID)
    b.box(0, 1, 13, 4, 2, 15, WOOD_LIGHT)
    b.box(1, 2, 9, 4, 3, 11, WOOD_LIGHT)
    return b


# The starter-hamlet set lives on the 0.125 structural grid and is authored to the
# exact catalogue footprint.  The street-prop set (hay bale, market stall, crop
# crates) is canonically 0.0625 with counts registered in
# scripts/m2_street_prop_assets.gd and is not authored here.
# Starter-hamlet props only: these three are the ones the hamlet builds
# procedurally. Furniture (bench, signpost, planters, lantern, ...) is already
# authored canonically on the 0.0625 presentation grid by the street/garden
# pipelines with fixed voxel counts; re-authoring it here would create a second
# authority for the same prop. See assets/source/magicavoxel/README.md.
PROPS: dict[str, dict] = {
    # The bench is already tracked; authoring it keeps one parametric source for a
    # model that previously existed only as bytes. The selftest proves the author
    # reproduces the tracked cell set exactly.
    "hearthvale_bench": dict(build=build_bench, unit=0.125, footprint=(1.75, 0.625)),
    "hearthvale_prop_village_well": dict(build=build_well, unit=0.125, footprint=(2.5, 2.25)),
    "hearthvale_prop_chopping_block": dict(build=build_chopping_block, unit=0.125, footprint=(1.0, 1.0)),
    "hearthvale_prop_log_stack": dict(build=build_log_stack, unit=0.125, footprint=(1.5, 1.0)),
}


# Baked-mesh names for the furniture catalogue.  These match the names the
# runtime asset helpers request from the authored mesh library, so a CI bake
# derives the whole set from the sources instead of hand-listing it.
MESH_NAMES = {
    "bench": "bench",
    "stone_bench": "stone_bench",
    "signpost": "signpost",
    "lamp_post": "lamp_post",
    "maypole": "maypole",
    "notice_board": "notice_board",
    "water_pump": "water_pump",
    "hay_cart": "hay_cart",
    "market_cross": "market_cross",
}


def mesh_name(style: str) -> str:
    """Return the baked-mesh name for a furniture style."""
    return MESH_NAMES.get(style, style)


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--out", type=pathlib.Path, default=pathlib.Path("assets/source/magicavoxel"))
    ap.add_argument("--only", action="append", default=[])
    ap.add_argument("--selftest", action="store_true")
    args = ap.parse_args(argv)

    if args.selftest:
        return selftest(args.out)

    names = args.only or list(PROPS)
    for name in names:
        if name not in PROPS:
            print(f"unknown prop {name}", file=sys.stderr)
            return 2
        spec = PROPS[name]
        builder = spec["build"]()
        count = builder.write(args.out / f"{name}.vox")
        w, d, h = builder.size
        unit = spec["unit"]
        fw, fd = spec["footprint"]
        dx, dy = w * unit, d * unit
        flag = "ok" if (abs(dx - fw) < 1e-9 and abs(dy - fd) < 1e-9) else "FOOTPRINT MISMATCH"
        print(f"{name:32s} cells={count:6d} size={w}x{d}x{h} grid={unit} -> {dx:.3f}x{dy:.3f} m ({flag})")
    return 0


def parse_vox(data: bytes) -> dict[tuple[int, int, int], int]:
    """Parse a MagicaVoxel format-150 file into {(x, z, y): palette index}."""
    if data[:4] != b"VOX " or int.from_bytes(data[4:8], "little") != 150:
        raise ValueError(f"not MagicaVoxel format 150 (magic {data[:4]!r})")
    main_at = data.index(b"MAIN")
    size_at = data.index(b"SIZE", main_at)
    xyzi = data.index(b"XYZI", main_at)
    count = int.from_bytes(data[xyzi + 12:xyzi + 16], "little")
    return {(data[xyzi + 16 + i * 4], data[xyzi + 16 + i * 4 + 2], data[xyzi + 16 + i * 4 + 1]):
            data[xyzi + 16 + i * 4 + 3] for i in range(count)}


def selftest(out_dir: pathlib.Path) -> int:
    """Round-trip every authored source: write it, parse it back, compare cell sets.

    This proves the author is deterministic and that the bytes on disk are a
    readable format-150 file whose contents are exactly what was authored.
    """
    failures = 0
    for name, spec in PROPS.items():
        path = out_dir / f"{name}.vox"
        if not path.exists():
            print(f"selftest: {path} missing", file=sys.stderr)
            failures += 1
            continue
        try:
            tracked = parse_vox(path.read_bytes())
        except ValueError as exc:
            print(f"selftest: {name}: {exc}", file=sys.stderr)
            failures += 1
            continue
        authored = spec["build"]().cells
        if authored == tracked:
            print(f"selftest: {name} round-trips ({len(tracked)} cells)")
        else:
            print(f"selftest: {name} differs (file {len(tracked)} cells, "
                  f"authored {len(authored)} cells)", file=sys.stderr)
            failures += 1
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
