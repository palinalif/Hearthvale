#!/usr/bin/env python3
"""Author Hearthvale's nine procedural furniture styles as MagicaVoxel .vox sources.

These are the hamlet furniture styles the runtime used to build from primitive
nodes (``_append_bench``, ``_append_signpost``, ``_append_well`` and friends in
``scripts/m2_hamlet_visual.gd``).  Authoring them as voxel sources lets the baked
mesh replace the primitives while the placement footprint, collision box and save
record stay exactly as they are.

Every dimension below is copied from the procedural builder it replaces, so the
baked mesh occupies the same volume the game already reserves:

======================  =============================  =====================
style                   procedural source              authored footprint
======================  =============================  =====================
bench                   ``_append_bench``            1.25 x 0.375 x 0.8125
signpost                ``_append_signpost``         1.00 x 0.125 x 1.750
lamp_post               ``_append_lamp_post``        0.50 x 0.250 x 2.750
maypole                 ``_append_maypole``          1.00 x 1.000 x 2.500
notice_board            ``_append_notice_board``     1.25 x 0.250 x 1.625
pumpkin_post            ``_append_pumpkin_post``     1.25 x 0.500 x 0.750
hay_cart                ``_append_hay_cart``         2.25 x 1.000 x 1.250
well                    ``_append_well``             1.75 x 1.750 x 2.750
lantern                 ``_append_lantern``          0.375 x 0.375 x 1.9375
======================  =============================  =====================

Presentation grid: ``0.0625``.  These are decorative props with no terrain
footprint, so the finer presentation grid is the canonical one for them (see
``assets/source/magicavoxel/README.md``); every dimension above is a multiple of
it, and the mesh test asserts that.

The facelift is voxel detail the primitives never had: chamfered timber, iron
bands, shingled roofs, spoked wheels, rope twist, layered hay, and a hollow
stone well curb with a bucket.

Usage:
    tools/magicavoxel/author_furniture.py                # write all nine
    tools/magicavoxel/author_furniture.py --only bench   # one style
    tools/magicavoxel/author_furniture.py --check        # grid + footprint audit
"""
from __future__ import annotations

import argparse
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from author_props import PALETTE, Builder  # noqa: E402

UNIT = 0.0625  # decorative presentation grid

# Palette indices from author_props.PALETTE.
WOOD_DARK, WOOD_MID, WOOD_LIGHT = 2, 3, 4
IRON, IRON_LIGHT, STONE_DARK = 5, 6, 7
STONE_MID, GLASS, FLAME, CLOTH, HAY, LEATHER = 8, 9, 10, 11, 12, 13
PAINT, COPPER, ROPE, PUMPKIN, SHINGLE, FOLIAGE = 14, 15, 16, 17, 18, 19
EMBER, COPPER_GLOW, GLASS_PANE = 20, 21, 22


def _idx(n: float) -> int:
    return round(n / UNIT)


class Prop(Builder):
    """Builder addressed in world units, centred on x/y and resting on z = 0."""

    def __init__(self, w: float, d: float, h: float) -> None:
        self.w, self.d, self.h = w, d, h
        super().__init__(_idx(w), _idx(d), _idx(h) + 1)

    def at(self, x: float, y: float, z: float, color: int) -> None:
        self.set(_idx(x + self.w / 2), _idx(y + self.d / 2), _idx(z), color)

    def block(self, x0: float, y0: float, z0: float, x1: float, y1: float, z1: float, color: int) -> None:
        self.box(_idx(x0 + self.w / 2), _idx(y0 + self.d / 2), _idx(z0),
                 _idx(x1 + self.w / 2), _idx(y1 + self.d / 2), _idx(z1), color)

    def shell(self, x0: float, y0: float, z0: float, x1: float, y1: float, z1: float, color: int) -> None:
        super().shell(_idx(x0 + self.w / 2), _idx(y0 + self.d / 2), _idx(z0),
                      _idx(x1 + self.w / 2), _idx(y1 + self.d / 2), _idx(z1), color)

    def cyl_at(self, cx: float, cy: float, z0: float, z1: float, radius: float, color: int) -> None:
        self.cyl(_idx(cx + self.w / 2), _idx(cy + self.d / 2), _idx(z0), _idx(z1),
                 max(1, _idx(radius)), color)

    def ring_at(self, cx: float, cy: float, z: float, radius: float, color: int) -> None:
        self.ring(_idx(cx + self.w / 2), _idx(cy + self.d / 2), _idx(z), max(1, _idx(radius)), color)

    def ball(self, cx: float, cy: float, cz: float, radius: float, color: int) -> None:
        r = max(1, _idx(radius))
        for ix in range(self.size[0]):
            for iy in range(self.size[1]):
                for iz in range(self.size[2]):
                    dx, dy, dz = ix - _idx(cx + self.w / 2), iy - _idx(cy + self.d / 2), iz - _idx(cz)
                    if dx * dx + dy * dy + dz * dz <= r * r:
                        self.set(ix, iy, iz, color)


# --------------------------------------------------------------------------- styles
def build_bench() -> Prop:
    p = Prop(1.25, 0.375, 0.8125)
    # Chamfered seat: full slab with the outer cells dropped at the top edge.
    p.block(-0.625, -0.1875, 0.375, 0.625, 0.1875, 0.4375, WOOD_MID)
    p.block(-0.5625, -0.125, 0.4375, 0.5625, 0.125, 0.5, WOOD_LIGHT)
    # Back rail with two uprights, slatted rather than a solid panel.
    p.block(-0.625, -0.1875, 0.4375, -0.5625, -0.125, 0.8125, WOOD_DARK)
    p.block(0.5625, -0.1875, 0.4375, 0.625, -0.125, 0.8125, WOOD_DARK)
    for rail_z in (0.5625, 0.6875):
        p.block(-0.5625, -0.1875, rail_z, 0.5625, -0.125, rail_z + 0.0625, WOOD_MID)
    # Legs with iron shoes.
    for lx in (-0.5, 0.5):
        for ly in (-0.125, 0.125):
            p.block(lx - 0.0625, ly - 0.0625, 0.0, lx + 0.0625, ly + 0.0625, 0.375, WOOD_DARK)
            p.block(lx - 0.0625, ly - 0.0625, 0.0, lx + 0.0625, ly + 0.0625, 0.0625, IRON)
    return p


def build_signpost() -> Prop:
    p = Prop(1.0, 0.125, 1.75)
    p.block(-0.0625, -0.0625, 0.0, 0.0625, 0.0625, 1.75, WOOD_MID)
    # Iron band and a stone kerb so it reads as planted, not floating.
    p.block(-0.125, -0.125, 0.0, 0.125, 0.125, 0.125, STONE_MID)
    p.block(-0.0625, -0.0625, 0.5, 0.0625, 0.0625, 0.5625, IRON)
    # Board with a frame and three carved lines.
    p.block(-0.5, -0.0625, 1.0, 0.5, 0.0625, 1.5, WOOD_DARK)
    p.block(-0.4375, -0.125, 1.0625, 0.4375, 0.125, 1.4375, WOOD_LIGHT)
    for line in (1.1875, 1.25, 1.3125):
        p.block(-0.3125, -0.125, line, 0.3125, -0.0625, line + 0.0625, WOOD_MID)
    # Pointing arm.
    p.block(0.5, -0.0625, 1.1875, 0.625, 0.0625, 1.3125, WOOD_MID)
    p.at(0.625, 0.0, 1.25, WOOD_MID)
    return p


def build_lamp_post() -> Prop:
    p = Prop(0.5, 0.25, 2.75)
    p.block(-0.125, -0.125, 0.0, 0.125, 0.125, 0.125, STONE_DARK)
    p.block(-0.09375, -0.09375, 0.125, 0.09375, 0.09375, 0.1875, IRON)
    p.block(-0.03125, -0.03125, 0.1875, 0.03125, 0.03125, 2.25, IRON)
    # Curved arm: stepped rather than a single box.
    for step, z in enumerate((2.25, 2.3125, 2.375, 2.4375, 2.5)):
        p.block(-0.03125 + step * 0.03125, -0.03125, z, 0.03125 + step * 0.03125, 0.03125, z + 0.0625, IRON)
    # Cage: four quarter ribs around the bulb.
    for rx in (-0.0625, 0.0625):
        p.block(0.09375 + rx, -0.03125, 2.5, 0.125 + rx, 0.03125, 2.6875, IRON)
    p.ring_at(0.125, 0.0, 2.5, 0.0625, IRON)
    p.ring_at(0.125, 0.0, 2.6875, 0.0625, IRON)
    p.ball(0.125, 0.0, 2.5625, 0.0625, EMBER)
    return p


def build_maypole() -> Prop:
    p = Prop(1.0, 1.0, 2.5)
    p.block(-0.25, -0.25, 0.0, 0.25, 0.25, 0.125, STONE_MID)
    p.block(-0.0625, -0.0625, 0.125, 0.0625, 0.0625, 2.5, WOOD_MID)
    # Iron collar bands.
    for band in (0.5, 1.25, 2.0):
        p.block(-0.09375, -0.09375, band, 0.09375, 0.09375, band + 0.0625, IRON)
    # Eight ribbons braided down the pole, alternating cloth colours.
    import math
    for ribbon in range(8):
        angle = ribbon * math.tau / 8
        color = CLOTH if ribbon % 2 == 0 else PAINT
        for step in range(0, 20):
            z = 2.375 - step * 0.1
            twist = angle + step * 0.35
            x, y = 0.125 * math.cos(twist), 0.125 * math.sin(twist)
            p.at(x, y, z, color)
    # Crown.
    p.ball(0.0, 0.0, 2.5, 0.125, CLOTH)
    return p


def build_notice_board() -> Prop:
    p = Prop(1.25, 0.25, 1.625)
    for px in (-0.5625, 0.5625):
        p.block(px - 0.0625, -0.0625, 0.0, px + 0.0625, 0.0625, 1.5, WOOD_DARK)
    # Board with a frame and pinned notices.
    p.block(-0.625, -0.0625, 0.75, 0.625, 0.0625, 1.5, WOOD_MID)
    p.block(-0.5625, -0.125, 0.8125, 0.5625, 0.125, 1.4375, WOOD_LIGHT)
    for i, (nx, nz) in enumerate(((-0.375, 1.125), (-0.0625, 1.25), (0.25, 1.0625))):
        p.block(nx, -0.125, nz, nx + 0.25, -0.0625, nz + 0.1875, PAINT if i != 1 else CLOTH)
    # Shingled roof overhanging the board.
    p.block(-0.6875, -0.1875, 1.5, 0.6875, 0.1875, 1.5625, SHINGLE)
    p.block(-0.625, -0.125, 1.5625, 0.625, 0.125, 1.625, SHINGLE)
    return p


def build_pumpkin_post() -> Prop:
    p = Prop(1.25, 0.5, 0.75)
    for px in (-0.5, 0.0, 0.5):
        p.block(px - 0.0625, -0.0625, 0.0, px + 0.0625, 0.0625, 0.5, WOOD_DARK)
        p.ring_at(px, 0.0, 0.5, 0.09375, IRON)
    # Three ribbed pumpkins with stems.
    for i, px in enumerate((-0.5, 0.0, 0.5)):
        p.ball(px, 0.0, 0.6875, 0.25, PUMPKIN)
        for rib in (-0.1875, 0.0, 0.1875):
            p.block(px + rib - 0.03125, -0.25, 0.625, px + rib + 0.03125, 0.25, 0.75, WOOD_MID)
        p.at(px, 0.0, 0.9375, FOLIAGE)
    return p


def build_hay_cart() -> Prop:
    p = Prop(2.25, 1.0, 1.25)
    # Spoked wheels.
    import math
    for wx in (-0.75, 0.75):
        for spoke in range(8):
            a = spoke * math.tau / 8
            p.block(wx + 0.3125 * math.cos(a) - 0.03125, 0.3125 * math.sin(a) - 0.03125,
                    0.375 + 0.3125 * math.sin(a) - 0.03125,
                    wx + 0.3125 * math.cos(a) + 0.03125, 0.3125 * math.sin(a) + 0.03125,
                    0.375 + 0.3125 * math.sin(a) + 0.03125, WOOD_DARK)
        p.ring_at(wx, 0.0, 0.375, 0.375, IRON)
        p.ball(wx, 0.0, 0.375, 0.09375, WOOD_MID)
    # Bed with side planks and iron corner brackets.
    p.block(-0.875, -0.5, 0.5, 0.875, 0.5, 0.625, WOOD_MID)
    for sy in (-0.5, 0.4375):
        p.block(-0.875, sy, 0.625, 0.875, sy + 0.0625, 0.8125, WOOD_DARK)
    for sx in (-0.875, 0.8125):
        p.block(sx, -0.5, 0.625, sx + 0.0625, 0.5, 0.6875, IRON)
    # Layered hay with a loose top course.
    p.block(-0.8125, -0.4375, 0.625, 0.8125, 0.4375, 0.9375, HAY)
    for i in range(9):
        x = -0.75 + i * 0.1875
        p.at(x, -0.25 + (i % 3) * 0.25, 1.0, HAY)
        p.at(x + 0.0625, 0.0, 1.0625, LEATHER)
    # Two bales lashed to the bed.
    for bx in (-0.5, 0.5):
        p.block(bx - 0.25, -0.375, 0.9375, bx + 0.25, 0.375, 1.1875, HAY)
        p.block(bx - 0.25, -0.375, 1.0, bx + 0.25, 0.375, 1.0625, ROPE)
    # Tow bar.
    p.block(-1.125, -0.0625, 0.4375, -0.875, 0.0625, 0.5, WOOD_DARK)
    return p


def build_well() -> Prop:
    p = Prop(1.75, 1.75, 2.75)
    # Hollow octagonal curb: stone ring with an inner void.
    for z in range(0, 8):
        p.ring_at(0.0, 0.0, z * 0.0625, 0.875, STONE_MID)
        p.ring_at(0.0, 0.0, z * 0.0625, 0.75, STONE_DARK)
    p.block(-0.9375, -0.9375, 0.0, 0.9375, 0.9375, 0.125, STONE_DARK)
    p.ring_at(0.0, 0.0, 0.5, 0.875, STONE_MID)
    # Two posts, a crossbeam and a crank.
    for px in (-0.625, 0.625):
        p.block(px - 0.0625, -0.0625, 0.5, px + 0.0625, 0.0625, 2.0, WOOD_DARK)
    p.block(-0.6875, -0.0625, 2.0, 0.6875, 0.0625, 2.125, WOOD_MID)
    p.block(0.6875, -0.25, 1.9375, 0.8125, -0.125, 2.0625, IRON)
    # Shingled roof.
    for step in range(8):
        w = 0.9375 - step * 0.109375
        z = 2.125 + step * 0.078125
        p.block(-w, -0.875 + step * 0.0625, z, w, 0.875 - step * 0.0625, z + 0.078125, SHINGLE)
    # Rope and bucket.
    p.block(-0.03125, -0.03125, 1.25, 0.03125, 0.03125, 2.0, ROPE)
    p.shell(-0.1875, -0.1875, 0.9375, 0.1875, 0.1875, 1.25, WOOD_MID)
    p.ring_at(0.0, 0.0, 1.25, 0.1875, IRON)
    return p


def build_lantern() -> Prop:
    """Furniture lantern: same footprint as the procedural builder, authored glass."""
    p = Prop(0.375, 0.375, 1.9375)
    p.block(-0.125, -0.125, 0.0, 0.125, 0.125, 0.0625, IRON)
    p.block(-0.03125, -0.03125, 0.0625, 0.03125, 0.03125, 1.5625, IRON)
    p.block(-0.1875, -0.1875, 1.5625, 0.1875, 0.1875, 1.625, IRON)
    for cx in (-0.125, 0.125):
        for cy in (-0.125, 0.125):
            p.block(cx - 0.03125, cy - 0.03125, 1.625, cx, cy, 1.8125, IRON)
    # Inset glass shell with a 0.0625 collar at floor and ceiling.
    p.shell(-0.125, -0.125, 1.6875, 0.125, 0.125, 1.75, GLASS_PANE)
    p.block(-0.0625, -0.0625, 1.71875, 0.0625, 0.0625, 1.75, EMBER)
    # Finial.
    p.block(-0.03125, -0.03125, 1.8125, 0.03125, 0.03125, 1.875, IRON)
    p.at(0.0, 0.0, 1.9375, IRON)
    return p


FURNITURE: dict[str, dict] = {
    "bench": dict(build=build_bench, unit=UNIT, footprint=(1.25, 0.375, 0.8125)),
    "signpost": dict(build=build_signpost, unit=UNIT, footprint=(1.0, 0.125, 1.75)),
    "lamp_post": dict(build=build_lamp_post, unit=UNIT, footprint=(0.5, 0.25, 2.75)),
    "maypole": dict(build=build_maypole, unit=UNIT, footprint=(1.0, 1.0, 2.5)),
    "notice_board": dict(build=build_notice_board, unit=UNIT, footprint=(1.25, 0.25, 1.625)),
    "pumpkin_post": dict(build=build_pumpkin_post, unit=UNIT, footprint=(1.25, 0.5, 0.75)),
    "hay_cart": dict(build=build_hay_cart, unit=UNIT, footprint=(2.25, 1.0, 1.25)),
    "well": dict(build=build_well, unit=UNIT, footprint=(1.75, 1.75, 2.75)),
    "lantern": dict(build=build_lantern, unit=UNIT, footprint=(0.375, 0.375, 1.9375)),
}


def source_name(style: str) -> str:
    return "hearthvale_furniture_%s" % style


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="assets/source/magicavoxel")
    ap.add_argument("--only", action="append", default=[])
    ap.add_argument("--check", action="store_true", help="audit grid and footprint only")
    args = ap.parse_args(argv)

    out_dir = pathlib.Path(args.out)
    styles = args.only or list(FURNITURE)
    for style in styles:
        if style not in FURNITURE:
            print("unknown style %s" % style)
            return 2

    bad = 0
    for style in styles:
        spec = FURNITURE[style]
        prop = spec["build"]()
        w, d, h = spec["footprint"]
        # Grid audit: every authored dimension must be a whole number of cells.
        for label, value in zip("wzh", (w, d, h)):
            if abs(value / spec["unit"] - round(value / spec["unit"])) > 1e-9:
                print("FAIL %s: %s=%s is off the %s grid" % (style, label, value, spec["unit"]))
                bad += 1
        if abs(prop.w - w) > 1e-9 or abs(prop.d - d) > 1e-9:
            print("FAIL %s: authored footprint %.4f x %.4f != declared %.4f x %.4f"
                  % (style, prop.w, prop.d, w, d))
            bad += 1
        if args.check:
            print("%-14s %3d cells  %.4f x %.4f x %.4f" % (style, len(prop.cells), w, d, h))
            continue
        out_dir.mkdir(parents=True, exist_ok=True)
        path = out_dir / (source_name(style) + ".vox")
        path.write_bytes(prop.vox())
        print("%-14s %5d cells -> %s" % (style, len(prop.cells), path.name))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
