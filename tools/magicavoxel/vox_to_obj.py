"""Convert simple VOX 150 files emitted by the pinned MCP into Godot-ready OBJ."""

from __future__ import annotations

import argparse
import hashlib
import json
import struct
from collections import defaultdict
from pathlib import Path

MCP_SOURCE = "https://github.com/Mahinika/magicavoxel-mcp"
MCP_COMMIT = "710671d49bdc89e4e3d1ff7c60541c1d0383ac16"
SUPPORTED_UNITS = (0.125, 0.0625)


def read_vox(path: Path):
    data = path.read_bytes()
    if data[:4] != b"VOX ":
        raise ValueError("not a MagicaVoxel VOX file")
    version = struct.unpack_from("<I", data, 4)[0]
    if version != 150:
        raise ValueError(f"unsupported VOX version {version}")
    chunk, content_size, children_size = struct.unpack_from("<4sII", data, 8)
    if chunk != b"MAIN":
        raise ValueError("VOX MAIN chunk missing")
    cursor = 20 + content_size
    end = cursor + children_size
    size = None
    voxels = {}
    palette = [(0, 0, 0, 0)] * 256
    while cursor < end:
        chunk, content_size, child_size = struct.unpack_from("<4sII", data, cursor)
        content = cursor + 12
        if chunk == b"SIZE":
            size = struct.unpack_from("<III", data, content)
        elif chunk == b"XYZI":
            count = struct.unpack_from("<I", data, content)[0]
            for index in range(count):
                x, y, z, color = struct.unpack_from("<BBBB", data, content + 4 + index * 4)
                if color:
                    if (x, y, z) in voxels:
                        raise ValueError("duplicate occupied VOX coordinate")
                    voxels[(x, y, z)] = color
        elif chunk == b"RGBA":
            palette = [struct.unpack_from("<BBBB", data, content + index * 4) for index in range(256)]
        cursor = content + content_size + child_size
    if size is None or not voxels:
        raise ValueError("VOX file has no usable model")
    if any(any(cell[a] >= size[a] for a in range(3)) for cell in voxels):
        raise ValueError("occupied VOX coordinate exceeds declared SIZE")
    return size, voxels, palette


# Counter-clockwise corners viewed from outside; the MCP documents Y as up.
FACES = {
    (1, 0, 0): lambda x0, y0, z0, x1, y1, z1: [(x1, y0, z0), (x1, y1, z0), (x1, y1, z1), (x1, y0, z1)],
    (-1, 0, 0): lambda x0, y0, z0, x1, y1, z1: [(x0, y0, z1), (x0, y1, z1), (x0, y1, z0), (x0, y0, z0)],
    (0, 1, 0): lambda x0, y0, z0, x1, y1, z1: [(x0, y1, z1), (x1, y1, z1), (x1, y1, z0), (x0, y1, z0)],
    (0, -1, 0): lambda x0, y0, z0, x1, y1, z1: [(x0, y0, z0), (x1, y0, z0), (x1, y0, z1), (x0, y0, z1)],
    (0, 0, 1): lambda x0, y0, z0, x1, y1, z1: [(x1, y0, z1), (x1, y1, z1), (x0, y1, z1), (x0, y0, z1)],
    (0, 0, -1): lambda x0, y0, z0, x1, y1, z1: [(x0, y0, z0), (x0, y1, z0), (x1, y1, z0), (x1, y0, z0)],
}


def merge_faces(faces):
    """Merge only adjacent coplanar rectangles with identical palette/normal."""
    merged = defaultdict(list)
    for color, group in faces.items():
        planes = defaultdict(set)
        for normal, corners in group:
            axis = next(a for a in range(3) if normal[a])
            u, v = (axis + 1) % 3, (axis + 2) % 3
            # Work in integer cell coordinates, before conversion to world units.
            planes[(normal, corners[0][axis])].add((min(c[u] for c in corners), min(c[v] for c in corners)))
        for (normal, plane), cells in sorted(planes.items()):
            axis = next(a for a in range(3) if normal[a])
            u, v = (axis + 1) % 3, (axis + 2) % 3
            while cells:
                start_u, start_v = min(cells)
                width = 1
                while (start_u + width, start_v) in cells:
                    width += 1
                height = 1
                while all((start_u + du, start_v + height) in cells for du in range(width)):
                    height += 1
                cells.difference_update((start_u + du, start_v + dv) for du in range(width) for dv in range(height))
                low = [0, 0, 0]
                high = [0, 0, 0]
                low[axis] = plane - (1 if normal[axis] > 0 else 0)
                high[axis] = low[axis] + 1
                low[u], high[u] = start_u, start_u + width
                low[v], high[v] = start_v, start_v + height
                merged[color].append((normal, FACES[normal](*low, *high)))
    return merged


def convert(source: Path, output: Path, unit: float, greedy: bool = False) -> dict:
    if unit not in SUPPORTED_UNITS:
        raise ValueError("Hearthvale assets require the 0.125 terrain/structure tier or 0.0625 prop/detail tier")
    size, voxels, palette = read_vox(source)
    source_digest = hashlib.sha256(source.read_bytes()).hexdigest()
    faces = defaultdict(list)
    for (x, y, z), color in sorted(voxels.items()):
        for normal, corners in FACES.items():
            neighbor = (x + normal[0], y + normal[1], z + normal[2])
            if neighbor not in voxels:
                faces[color].append((normal, corners(x, y, z, x + 1, y + 1, z + 1)))

    exposed_quads = sum(len(group) for group in faces.values())
    if greedy:
        faces = merge_faces(faces)

    output.parent.mkdir(parents=True, exist_ok=True)
    material_path = output.with_suffix(".mtl")
    material_lines = []
    for color in sorted(faces):
        r, g, b, _a = palette[color]
        material_lines.extend([f"newmtl palette_{color}", f"Kd {r / 255:.6f} {g / 255:.6f} {b / 255:.6f}", "Ks 0 0 0", "Ns 1", ""])
    material_path.write_text("\n".join(material_lines), encoding="utf-8", newline="\n")

    lines = [f"# Generated from {source.name}", f"# source_sha256 {source_digest}", f"mtllib {material_path.name}", "o hearthvale_magicavoxel_asset"]
    vertex_index = 1
    normal_index = 1
    for color in sorted(faces):
        lines.extend([f"g palette_{color}", f"usemtl palette_{color}"])
        for normal, corners in faces[color]:
            for x, y, z in corners:
                x, y, z = (x - size[0] * 0.5) * unit, y * unit, (z - size[2] * 0.5) * unit
                lines.append(f"v {x:.6f} {y:.6f} {z:.6f}")
            lines.append(f"vn {normal[0]} {normal[1]} {normal[2]}")
            lines.append(f"f {vertex_index}//{normal_index} {vertex_index + 1}//{normal_index} {vertex_index + 2}//{normal_index} {vertex_index + 3}//{normal_index}")
            vertex_index += 4
            normal_index += 1
    output.write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")

    receipt = {
        "asset": output.stem,
        "source": source.name,
        "source_sha256": source_digest,
        "tool": MCP_SOURCE,
        "tool_commit": MCP_COMMIT,
        "license": "Project-authored; MCP development tool is MIT",
        "voxel_unit": unit,
        "voxel_tier": "prop/detail" if unit == 0.0625 else "terrain/structure",
        "declared_dimensions": list(size),
        "occupied_bounds": {"min": [min(v[a] for v in voxels) for a in range(3)], "max": [max(v[a] for v in voxels) + 1 for a in range(3)]},
        "voxel_count": len(voxels),
        "exposed_quads": exposed_quads,
        "triangles": sum(len(group) for group in faces.values()) * 2,
        "palette_indices": sorted(faces),
        "orientation": "MCP documented Y-up mapped directly to Godot Y-up",
    }
    if greedy:
        receipt["meshing"] = "greedy coplanar same-palette rectangles; exact exposed-cell coverage"
        receipt["emitted_quads"] = sum(len(group) for group in faces.values())
    output.with_suffix(".asset.json").write_text(json.dumps(receipt, indent=2, sort_keys=True) + "\n", encoding="utf-8", newline="\n")
    return receipt


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--unit", type=float, default=0.125)
    parser.add_argument("--greedy", action="store_true")
    args = parser.parse_args()
    if not 0 < args.unit <= 1:
        raise SystemExit("unit must be in (0, 1]")
    print(json.dumps(convert(args.source.resolve(), args.output.resolve(), args.unit, args.greedy), sort_keys=True))


if __name__ == "__main__":
    main()
