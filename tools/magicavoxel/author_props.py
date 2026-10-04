#!/usr/bin/env python3
"""Author Hearthvale standalone prop .vox sources parametrically.

The MagicaVoxel MCP is a development convenience, not a build dependency: its
tool surface and save location have changed several times, so the canonical
sources for these props are generated here instead. Output is a plain
MagicaVoxel 1.0.1 file, byte-compatible with the reader in vox_to_obj.py and
with MagicaVoxel itself, so the normal pipeline (bake_mesh.gd -> OBJ ->
ArrayMesh) consumes it unchanged.

Grid contract (assets/source/magicavoxel/README.md): 1 voxel cell = 0.125
world unit for structural props. Dimensions are chosen on that grid.
"""

from __future__ import annotations

import argparse
import struct
import sys
from pathlib import Path

# MagicaVoxel format 150: "VOX " + version + a MAIN node whose MODEL children
# carry SIZE, RGBA and an XYZI voxel list. This is the format the MagicaVoxel
# MCP writes and the format vox_to_obj.py reads, so generated sources are
# interchangeable with hand-authored ones.
MAGIC = b"VOX "
VERSION = 150
CELL_UNITS = 0.125


def _node(chunk: bytes, content: bytes, children: bytes) -> bytes:
    return chunk + struct.pack("<II", len(content), len(children)) + content + children


def write_vox(path: Path, size: tuple[int, int, int], voxels: dict[tuple[int, int, int], int],
              palette: list[tuple[int, int, int]]) -> None:
    """Write a single-model MagicaVoxel format-150 file.

    XYZI stores 1-based palette indices; index 0 is empty and is not written.
    """
    sx, sy, sz = size
    for (x, y, z), idx in voxels.items():
        if not (0 <= x < sx and 0 <= y < sy and 0 <= z < sz):
            raise ValueError(f"voxel {(x, y, z)} outside model {size}")
        if not 0 <= idx < 255:
            raise ValueError(f"palette index {idx} out of range (1-255 are usable)")

    size_node = _node(b"SIZE", struct.pack("<III", sx, sy, sz), b"")
    rgba = b"".join(bytes((rgb[0], rgb[1], rgb[2], 255))
                    for rgb in (list(palette) + [(0, 0, 0)] * 256)[:256])
    rgba_node = _node(b"RGBA", rgba, b"")
    ordered = sorted(voxels.items(), key=lambda kv: (kv[0][2], kv[0][1], kv[0][0]))
    xyzi = struct.pack("<I", len(ordered)) + b"".join(
        bytes((x, y, z, idx + 1)) for (x, y, z), idx in ordered)
    xyzi_node = _node(b"XYZI", xyzi, b"")

    model_children = size_node + xyzi_node + rgba_node
    out = MAGIC + struct.pack("<I", VERSION) + _node(b"MAIN", b"", model_children)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(out)


def read_vox(path: Path) -> tuple[tuple[int, int, int], dict[tuple[int, int, int], int], list]:
    """Format-150 reader used by the round-trip self-test (mirrors vox_to_obj.py).

    The MagicaVoxel MCP writes SIZE/XYZI/RGBA as direct MAIN children, so the
    traversal is flat and generated files match hand-authored ones.
    """
    data = path.read_bytes()
    if data[:4] != MAGIC:
        raise ValueError(f"{path}: not a MagicaVoxel VOX file")
    version = struct.unpack_from("<I", data, 4)[0]
    if version != VERSION:
        raise ValueError(f"{path}: unsupported VOX version {version}")
    chunk, content_size, children_size = struct.unpack_from("<4sII", data, 8)
    if chunk != b"MAIN":
        raise ValueError("VOX MAIN chunk missing")
    cursor = 20 + content_size
    end = cursor + children_size
    size = None
    voxels: dict[tuple[int, int, int], int] = {}
    palette = [(0, 0, 0, 0)] * 256
    while cursor < end:
        chunk, content_size, child_size = struct.unpack_from("<4sII", data, cursor)
        content = cursor + 12
        if chunk == b"SIZE":
            size = struct.unpack_from("<III", data, content)
        elif chunk == b"XYZI":
            count = struct.unpack_from("<I", data, content)[0]
            for i in range(count):
                x, y, z, color = struct.unpack_from("<BBBB", data, content + 4 + i * 4)
                if color:
                    voxels[(x, y, z)] = color - 1
        elif chunk == b"RGBA":
            palette = [struct.unpack_from("<BBBB", data, content + i * 4) for i in range(256)]
        cursor = content + content_size + child_size
    if size is None or not voxels:
        raise ValueError("VOX file has no usable model")
    return size, voxels, palette


class Builder:
    """Sparse voxel builder with a named palette."""

    def __init__(self, sx: int, sy: int, sz: int):
        self.size = (sx, sy, sz)
        self.voxels: dict[tuple[int, int, int], int] = {}
        self.palette: list[tuple[int, int, int]] = []
        self._colors: dict[tuple[int, int, int], int] = {}

    def color(self, rgb: tuple[int, int, int]) -> int:
        if rgb not in self._colors:
            if len(self._colors) >= 256:
                raise ValueError("palette full")
            self._colors[rgb] = len(self.palette)
            self.palette.append(rgb)
        return self._colors[rgb]

    def set(self, x: int, y: int, z: int, rgb: tuple[int, int, int]) -> None:
        self.voxels[(x, y, z)] = self.color(rgb)

    def box(self, x0: int, y0: int, z0: int, x1: int, y1: int, z1: int, rgb: tuple[int, int, int]) -> None:
        idx = self.color(rgb)
        for z in range(z0, z1 + 1):
            for y in range(y0, y1 + 1):
                for x in range(x0, x1 + 1):
                    self.voxels[(x, y, z)] = idx

    def cylinder(self, cx: int, cy: int, z0: int, z1: int, radius: int, rgb: tuple[int, int, int],
                 shell_only: bool = False) -> None:
        idx = self.color(rgb)
        r2 = radius * radius
        for z in range(z0, z1 + 1):
            for y in range(cy - radius, cy + radius + 1):
                for x in range(cx - radius, cx + radius + 1):
                    d = (x - cx) ** 2 + (y - cy) ** 2
                    if d > r2:
                        continue
                    if shell_only and d < (radius - 1) ** 2:
                        continue
                    self.voxels[(x, y, z)] = idx

    def log(self, x0: int, x1: int, cy: int, cz: int, radius: int,
            body: tuple[int, int, int], face: tuple[int, int, int], core: tuple[int, int, int]) -> None:
        """A log lying along +X with a cut end face at x1."""
        for z in range(cz - radius, cz + radius + 1):
            for y in range(cy - radius, cy + radius + 1):
                d = (y - cy) ** 2 + (z - cz) ** 2
                if d > radius * radius:
                    continue
                for x in range(x0, x1):
                    self.set(x, y, z, body)
                self.set(x1, y, z, face)
                if d <= 1:
                    self.set(x1, y, z, core)

    def save(self, path: Path) -> None:
        write_vox(path, self.size, self.voxels, self.palette)


# Palette shared by the starter-hamlet props.
STONE = (110, 110, 120)
STONE_DK = (74, 74, 82)
STONE_LT = (150, 150, 158)
WOOD = (122, 82, 51)
WOOD_DK = (92, 58, 34)
WOOD_LT = (169, 116, 76)
IRON = (58, 58, 68)
SHINGLE = (104, 66, 44)
MOSS = (90, 122, 66)
STRAW = (217, 180, 90)
ROPE = (190, 168, 120)


def build_well() -> Builder:
    """Village well: stone curb, two posts, shingled roof, rope, bucket."""
    b = Builder(16, 16, 24)
    # stone curb with a hollow shaft
    b.box(3, 3, 0, 12, 12, 3, STONE)
    b.box(5, 5, 0, 10, 10, 4, STONE_DK)
    b.box(6, 6, 0, 9, 9, 5, (20, 18, 22))
    # coping stones on the curb rim
    for x in range(3, 13):
        b.set(x, 3, 4, STONE_LT)
        b.set(x, 12, 4, STONE_LT)
    for y in range(4, 12):
        b.set(3, y, 4, STONE_LT)
        b.set(12, y, 4, STONE_LT)
    # posts
    b.box(3, 4, 4, 4, 5, 15, WOOD_DK)
    b.box(11, 4, 4, 12, 5, 15, WOOD_DK)
    b.box(3, 10, 4, 4, 11, 15, WOOD_DK)
    b.box(11, 10, 4, 12, 11, 15, WOOD_DK)
    # crossbeams and windlass
    b.box(3, 6, 15, 12, 7, 16, WOOD)
    b.box(3, 8, 15, 12, 9, 16, WOOD)
    b.box(6, 7, 17, 9, 8, 18, IRON)
    b.set(5, 7, 17, IRON)
    b.set(10, 8, 18, IRON)
    # shingled roof, stepping in toward the ridge
    b.box(2, 2, 17, 13, 13, 18, SHINGLE)
    b.box(3, 3, 19, 12, 12, 20, SHINGLE)
    b.box(4, 4, 21, 11, 11, 22, WOOD)
    b.box(5, 5, 23, 10, 10, 23, WOOD_DK)
    # rope and bucket
    b.box(7, 7, 12, 8, 8, 16, ROPE)
    b.cylinder(8, 8, 8, 11, 2, WOOD)
    b.box(6, 6, 12, 9, 9, 12, WOOD_DK)
    # moss at the base
    b.box(3, 12, 3, 5, 13, 4, MOSS)
    return b


def build_chopping_block() -> Builder:
    """Chopping block: stone footing, stump with growth rings, chips, moss."""
    b = Builder(16, 16, 14)
    b.cylinder(8, 8, 0, 2, 6, STONE)
    b.cylinder(8, 8, 3, 3, 5, STONE_DK)
    b.cylinder(8, 8, 4, 9, 4, WOOD)
    b.cylinder(8, 8, 10, 10, 4, WOOD_LT)
    b.cylinder(8, 8, 11, 11, 3, WOOD)
    b.cylinder(8, 8, 12, 12, 2, WOOD_LT)
    b.cylinder(8, 8, 13, 13, 1, WOOD_DK)
    # bark band around the stump
    b.cylinder(8, 8, 4, 9, 4, WOOD_DK, shell_only=True)
    # moss and wood chips
    b.box(3, 12, 3, 5, 13, 4, MOSS)
    b.box(13, 9, 3, 14, 10, 4, WOOD_LT)
    b.box(12, 12, 3, 13, 13, 4, WOOD)
    return b


def build_log_stack() -> Builder:
    """Log stack: pallet, straw, and a 3-2-1 pyramid of cut logs."""
    b = Builder(16, 14, 20)
    # pallet: deck boards on stringers
    b.box(1, 1, 0, 14, 12, 1, WOOD_DK)
    b.box(1, 1, 2, 3, 12, 3, WOOD_DK)
    b.box(12, 1, 2, 14, 12, 3, WOOD_DK)
    b.box(4, 1, 3, 11, 2, 4, STRAW)
    # 3 / 2 / 1 pyramid, logs lying along +X with cut faces at +X
    r = 2
    b.log(2, 13, 3, 7, r, WOOD, WOOD_LT, WOOD_DK)
    b.log(2, 13, 7, 7, r, WOOD, WOOD_LT, WOOD_DK)
    b.log(2, 13, 11, 7, r, WOOD, WOOD_LT, WOOD_DK)
    b.log(2, 13, 5, 12, r, WOOD, WOOD_LT, WOOD_DK)
    b.log(2, 13, 9, 12, r, WOOD, WOOD_LT, WOOD_DK)
    b.log(2, 13, 7, 17, r, WOOD, WOOD_LT, WOOD_DK)
    return b


PROPS = {
    "hearthvale_prop_village_well": build_well,
    "hearthvale_prop_chopping_block": build_chopping_block,
    "hearthvale_prop_log_stack": build_log_stack,
}


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--out", required=True, help="directory to write .vox sources into")
    ap.add_argument("--only", help="author just this prop name")
    ap.add_argument("--selftest", action="store_true", help="round-trip a tracked .vox through the writer")
    args = ap.parse_args()

    if args.selftest:
        src = Path("assets/source/magicavoxel/hearthvale_bench.vox")
        size, voxels, palette = read_vox(src)
        tmp = Path(args.out) / "roundtrip.vox"
        write_vox(tmp, size, voxels, palette)
        size2, voxels2, palette2 = read_vox(tmp)
        ok = size == size2 and voxels == voxels2 and palette == palette2
        tmp.unlink()
        print(f"round-trip {'PASS' if ok else 'FAIL'}: {len(voxels)} voxels, size {size}")
        sys.exit(0 if ok else 1)

    out = Path(args.out)
    for name, fn in PROPS.items():
        if args.only and name != args.only:
            continue
        b = fn()
        path = out / f"{name}.vox"
        b.save(path)
        print(f"{name}: {len(b.voxels)} voxels, size {b.size}, {path}")


if __name__ == "__main__":
    main()
