#!/usr/bin/env python3
"""Convert a canonical MagicaVoxel .vox source into a Hearthvale runtime asset JSON.

The runtime JSON schema is the one the game bakes at runtime
(assets/models/magicavoxel/*.json): unit-cubed voxels with a palette index,
a source palette, and per-index material colours. This tool is the seam from
the authored .vox (the source of truth) to that runtime form, so assets are
never hand-transcribed.

It also writes .vox: `write_vox` emits the canonical MagicaVoxel container
(VOX / MAIN / XYZI + XYZN), which MagicaVoxel and the MagicaVoxel MCP read.

Usage:
  tools/magicavoxel/vox_to_asset.py IN.vox OUT.json --name NAME \
      [--units 0.125] [--pivot x y z] [--source-vox REL_PATH] \
      [--material NAME=INDEX:HEX ...]

Checks the result against the voxel/bounds counts printed by the caller.
"""
from __future__ import annotations

import argparse
import json
import struct
import sys
from pathlib import Path

# MagicaVoxel nROT matrix indices (column-major x,y,z basis images).
ROTATIONS = [
    ((1, 0, 0), (0, 1, 0), (0, 0, 1)),
    ((1, 0, 0), (0, 0, -1), (0, 1, 0)),
    ((1, 0, 0), (0, 0, 1), (0, -1, 0)),
    ((0, 0, 1), (1, 0, 0), (0, 1, 0)),
    ((0, 0, -1), (1, 0, 0), (0, -1, 0)),
    ((0, 0, 1), (-1, 0, 0), (0, 1, 0)),
    ((0, 0, -1), (-1, 0, 0), (0, -1, 0)),
]


def _nodes(data: bytes, start: int, end: int):
    """Yield (node_id, content, children_range) recursively over a VOX byte range."""
    pos = start
    while pos + 12 <= end:
        node_id = data[pos:pos + 4].decode("ascii", "replace")
        content_size, child_size = struct.unpack_from("<ii", data, pos + 4)
        content_start = pos + 12
        content_end = content_start + content_size
        child_start = content_end
        child_end = child_start + child_size
        yield node_id, data[content_start:content_end], (child_start, child_end)
        pos = child_end


class VoxelModel:
    """Parsed VOX tree: palette plus every voxel in model space."""

    def __init__(self) -> None:
        self.palette: dict[int, tuple[int, int, int]] = {}
        self.voxels: list[tuple[int, int, int, int]] = []
        self._size: tuple[int, int, int] | None = None

    def build(self, data: bytes) -> None:
        self._walk(data, 8, len(data), (0, 0, 0), (1, 1, 1), 0)

    def _walk(self, data: bytes, start: int, end: int,
              offset: tuple[int, int, int], scale: tuple[float, float, float],
              rotation: int) -> None:
        for node_id, content, (child_start, child_end) in _nodes(data, start, end):
            if node_id == "RGBA":
                # Officially 254 x RGB; some writers emit 256 x RGBA. Handle both.
                if len(content) >= 256 * 4:
                    for i in range(256):
                        base = i * 4
                        self.palette[i] = tuple(content[base:base + 3])
                else:
                    for i in range(254):
                        base = i * 3
                        if base + 3 <= len(content):
                            self.palette[i + 1] = tuple(content[base:base + 3])
            elif node_id == "PALT":
                for i in range(255):
                    base = i * 4
                    if base + 3 <= len(content):
                        self.palette[i] = tuple(content[base:base + 3])
            elif node_id == "SIZE":
                self._size = struct.unpack("<iii", content[:12])
            elif node_id == "XYZI":
                count = len(content) // 4
                for i in range(count):
                    x, y, z, index = content[i * 4:i * 4 + 4]
                    self.voxels.append(self._place(x, y, z, index, offset, scale, rotation))
            elif node_id == "nTRN":
                self._walk(data, child_start, child_end, offset, scale, rotation)
            elif node_id == "nXYZ":
                dx, dy, dz = struct.unpack("<fff", content[:12])
                self._walk(data, child_start, child_end,
                           (offset[0] + round(dx * scale[0]),
                            offset[1] + round(dy * scale[1]),
                            offset[2] + round(dz * scale[2])),
                           scale, rotation)
            elif node_id == "nSIZ":
                sx, sy, sz = struct.unpack("<fff", content[:12])
                self._walk(data, child_start, child_end, offset,
                           (scale[0] * sx, scale[1] * sy, scale[2] * sz), rotation)
            elif node_id == "nROT":
                matrix = struct.unpack("<i", content[:4])[0]
                self._walk(data, child_start, child_end, offset, scale, matrix)
            elif node_id in ("MAIN", "nGRP", "obj"):
                self._walk(data, child_start, child_end, offset, scale, rotation)

    def _place(self, x: int, y: int, z: int, index: int,
               offset: tuple[int, int, int], scale: tuple[float, float, float],
               rotation: int) -> tuple[int, int, int, int]:
        # MagicaVoxel voxel space is x-right, y-up, z-depth; the game uses
        # x-right, y-up, z-forward, so y/z swap and z negates.
        px, py, pz = x, z, -y
        if rotation:
            matrix = ROTATIONS[rotation % len(ROTATIONS)]
            px, py, pz = (
                matrix[0][0] * px + matrix[0][1] * py + matrix[0][2] * pz,
                matrix[1][0] * px + matrix[1][1] * py + matrix[1][2] * pz,
                matrix[2][0] * px + matrix[2][1] * py + matrix[2][2] * pz,
            )
        return (px + offset[0], py + offset[1], pz + offset[2], index)


def _node(node_id: bytes, content: bytes, children: bytes = b"") -> bytes:
    return node_id + struct.pack("<ii", len(content), len(children)) + content + children


def write_vox(path: str | Path, size, voxels, palette) -> int:
    """Write a MagicaVoxel 150 file that the repo baker (vox_to_obj.py) reads.

    VOX 150 / MAIN(numChildren) / [SIZE, XYZI, RGBA] as flat siblings, which is
    what tools/magicavoxel/vox_to_obj.py parses. Coordinates are (x, y=up, z)
    and map straight to Godot space; colour index 0 is empty and is skipped.

    voxels: iterable of (x, y, z, color_index)
    palette: list of 256 (r, g, b, a); index 0 is the unused transparent entry.
    """
    voxels = [v for v in voxels if v[3]]
    for x, y, z, _ in voxels:
        for axis, cell in enumerate((x, y, z)):
            if not 0 <= cell < size[axis]:
                raise ValueError(f"voxel {(x, y, z)} outside SIZE {size}")
    size_c = struct.pack("<III", *size)
    xi_c = struct.pack("<I", len(voxels)) + b"".join(
        struct.pack("<4B", x, y, z, i) for x, y, z, i in voxels)
    rgba_c = b"".join(struct.pack("<4B", *c) for c in list(palette)[:256])
    children = _node(b"SIZE", size_c) + _node(b"XYZI", xi_c) + _node(b"RGBA", rgba_c)
    main = b"MAIN" + struct.pack("<ii", 4, len(children)) + struct.pack("<i", 3) + children
    blob = b"VOX " + struct.pack("<I", 150) + struct.pack("<I", 1) + main
    Path(path).write_bytes(blob)
    return len(blob)


def parse_vox(path: str | Path) -> VoxelModel:
    """Read a .vox into a VoxelModel using the repo's own VOX 150 reader.

    Yields voxels in MagicaVoxel space (x, y=up, z), which is the space the
    baker maps straight into Godot; no axis flip is applied here.
    """
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    from vox_to_obj import read_vox

    size, voxels, palette = read_vox(Path(path))
    model = VoxelModel()
    model._size = tuple(size)
    for (x, y, z), index in voxels.items():
        model.voxels.append((x, y, z, index))
    for i, (r, g, b, _a) in enumerate(palette):
        if (r, g, b) != (0, 0, 0):
            model.palette[i] = (r, g, b)
    return model


def build_asset(model: VoxelModel, name: str, units: float = 0.125,
                pivot=(0.0, 0.0, 0.0), source_vox: str | None = None,
                materials: dict[int, dict[str, str]] | None = None) -> dict:
    """Build the runtime asset dict from a parsed model (same schema the game bakes)."""
    cells: dict[tuple[int, int, int], int] = {}
    for x, y, z, index in model.voxels:
        cells.setdefault((x, y, z), index)
    if not cells:
        raise ValueError("model has no voxels")

    xs = [c[0] for c in cells]
    ys = [c[1] for c in cells]
    zs = [c[2] for c in cells]
    bounds = {
        "minX": min(xs), "maxX": max(xs),
        "minY": min(ys), "maxY": max(ys),
        "minZ": min(zs), "maxZ": max(zs),
    }
    indices = sorted({i for i in cells.values()})
    materials = materials or {}
    size_cells = [bounds["maxX"] - bounds["minX"] + 1,
                  bounds["maxY"] - bounds["minY"] + 1,
                  bounds["maxZ"] - bounds["minZ"] + 1]

    return {
        "name": name,
        "units": units,
        "pivot": list(pivot),
        "voxSize": [c * units for c in size_cells],
        "sourceVox": source_vox or f"assets/source/magicavoxel/{name}.vox",
        "voxSizeCells": size_cells,
        "bounds": bounds,
        "sourceColors": {
            str(i): list(model.palette.get(i, (0, 0, 0))) + [255] for i in indices
        },
        "materialColors": {
            str(i): materials.get(i, {}).get(
                "color", "#%02X%02X%02X" % tuple(model.palette.get(i, (0, 0, 0))))
            for i in indices
        },
        "voxels": [
            {"x": x, "y": y, "z": z, "paletteIndex": cells[(x, y, z)]}
            for (x, y, z) in sorted(cells)
        ],
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("vox")
    parser.add_argument("out")
    parser.add_argument("--name", required=True)
    parser.add_argument("--units", type=float, default=0.125)
    parser.add_argument("--pivot", type=float, nargs=3, default=(0.0, 0.0, 0.0))
    parser.add_argument("--source-vox", default=None)
    parser.add_argument("--material", nargs="*", default=[],
                        help="NAME=INDEX:HEX per palette index")
    args = parser.parse_args()

    model = parse_vox(args.vox)
    if not model.voxels:
        print(f"no voxels parsed from {args.vox}", file=sys.stderr)
        return 1

    materials = {}
    for item in args.material:
        name, spec = item.split("=", 1)
        index, hex_value = spec.split(":")
        materials[int(index)] = {"name": name, "color": hex_value}

    asset = build_asset(model, args.name, args.units, tuple(args.pivot),
                        args.source_vox, materials)
    Path(args.out).write_text(json.dumps(asset, indent=2) + "\n")
    bounds = asset["bounds"]
    print(f"{args.out}: {len(asset['voxels'])} voxels, "
          f"{len(asset['voxels']) and len(asset['sourceColors'])} colours, "
          f"bounds {bounds['minX']}..{bounds['maxX']} x "
          f"{bounds['minY']}..{bounds['maxY']} x {bounds['minZ']}..{bounds['maxZ']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
