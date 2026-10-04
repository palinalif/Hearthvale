"""Reconstruct a MagicaVoxel ``.vox`` from a committed generated ``.obj``.

Best-effort, not byte-exact: the OBJ is a *lossy* projection of the voxel set
(fully enclosed voxels leave no faces, and the greedy coplanar merge is not
invertible), so a reconstructed model reproduces the visible surface and the
palette, not the original file bytes. ``main`` only prints VERIFIED when the
regenerated OBJ is byte-identical; treat anything else as an approximation and
re-author the model in MagicaVoxel instead of shipping it.

Usage: python3 tools/magicavoxel/obj_to_vox.py <obj> <out.vox> [--unit auto]
"""

The forward pipeline (tools/magicavoxel/vox_to_obj.py) maps voxel cell (x,y,z) to
world space as ((x - size.x/2) * unit, y * unit, (z - size.z/2) * unit) and emits
one axis-aligned quad per exposed cell face, grouped by palette index. That mapping
is invertible for the axis-aligned meshes MagicaVoxel produces, so a lost source can
be rebuilt from its committed OBJ and verified by regenerating the OBJ byte-for-byte.

Usage: tools/magicavoxel/obj_to_vox.py <in.obj> <out.vox> [--unit auto|0.125|0.0625]
"""

from __future__ import annotations

import argparse
import hashlib
import re
import struct
import sys
from collections import defaultdict
from pathlib import Path

AXES = {"x": 0, "y": 1, "z": 2}


def parse_obj(path: Path):
    verts: list[tuple[float, float, float]] = []
    normals: list[tuple[int, int, int]] = []
    quads: list[tuple[int, int, tuple[int, int, int]]] = []  # (palette, quad verts, normal)
    group: int | None = None
    for line in path.read_text(encoding="utf-8").splitlines():
        if line.startswith("g "):
            name = line.split()[1]
            match = re.fullmatch(r"palette_(\d+)", name)
            group = int(match.group(1)) if match else None
        elif line.startswith("v "):
            verts.append(tuple(float(v) for v in line.split()[1:4]))  # type: ignore[arg-type]
        elif line.startswith("vn "):
            normals.append(tuple(int(float(v)) for v in line.split()[1:4]))  # type: ignore[arg-type]
        elif line.startswith("f "):
            parts = line.split()[1:5]
            vi = int(parts[0].split("//")[0]) - 1
            ni = int(parts[0].split("//")[1]) - 1
            if group is None:
                raise ValueError(f"{path.name}: face outside a palette_* group")
            quads.append((group, [verts[vi + k] for k in range(4)], normals[ni]))
    return quads


def parse_mtl(path: Path) -> dict[int, tuple[int, int, int]]:
    palette: dict[int, tuple[int, int, int]] = {}
    index: int | None = None
    for line in path.read_text(encoding="utf-8").splitlines():
        if line.startswith("newmtl "):
            match = re.fullmatch(r"palette_(\d+)", line.split()[1])
            index = int(match.group(1)) if match else None
        elif line.startswith("Kd ") and index is not None:
            # vox_to_obj writes Kd as channel/255 with six decimals.
            palette[index] = tuple(round(float(c) * 255) for c in line.split()[1:4])  # type: ignore[assignment]
    return palette


def pick_unit(quads) -> float:
    """Choose the grid tier whose half-cell lattice the vertices actually sit on."""
    for unit in (0.125, 0.0625):
        if all(abs(v / unit * 2 - round(v / unit * 2)) < 1e-6 for q in quads for v in _coords(q)):
            return unit
    raise ValueError("vertices do not sit on a 0.125 or 0.0625 lattice")


def _coords(quad):
    for v in quad[1]:
        yield from v


def quantize(quads, unit: float):
    """Invert the world mapping into integer cell coordinates per axis."""
    # Y has no offset; X and Z are shifted by -size/2, recovered from the vertex span.
    lo = [min(v[a] for q in quads for v in q[1]) for a in range(3)]
    hi = [max(v[a] for q in quads for v in q[1]) for a in range(3)]
    span = [round((hi[a] - lo[a]) / unit) for a in range(3)]
    # Declared size is the tight bounding box; the forward mapping centres X/Z on size/2.
    size = span
    offset = [size[0] / 2.0, 0.0, size[2] / 2.0]
    cells: list[tuple[int, int, int, int, tuple[int, int, int]]] = []
    for palette, quad, normal in quads:
        corners = []
        for v in quad:
            c = tuple(round(v[a] / unit + offset[a]) for a in range(3))
            corners.append(c)
        cells.append((palette, corners, normal))
    return size, cells


def solid_cells(size, cells):
    """A cell is solid when a +X ray from its centre crosses an odd number of faces."""
    # Axis-aligned faces only: X-plane crossings are bucketed by the cell column they sit in.
    buckets: dict[tuple[int, int], list[float]] = defaultdict(list)
    for _palette, corners, normal in cells:
        if normal[0] == 0:
            continue
        plane_x = corners[0][0]
        # Merged faces span several cells: iterate the whole integer span, not just corners.
        y0, y1 = min(c[1] for c in corners), max(c[1] for c in corners)
        z0, z1 = min(c[2] for c in corners), max(c[2] for c in corners)
        for y in range(y0, y1):
            for z in range(z0, z1):
                buckets[(y, z)].append(plane_x)
    for bucket in buckets.values():
        bucket.sort()
    solid: set[tuple[int, int, int]] = set()
    for y in range(size[1]):
        for z in range(size[2]):
            crossings = buckets.get((y, z), [])
            for x in range(size[0]):
                centre = x + 0.5
                import bisect

                if (len(crossings) - bisect.bisect_right(crossings, centre)) % 2 == 1:
                    solid.add((x, y, z))
    return solid


def face_owned_cells(size, cells):
    """A lattice cell exists iff a face bounds it: a +axis face at plane P owns cell P-1,
    a -axis face owns the cell at P. This is the inverse of the generator's parity rule
    and needs no volume fill."""
    owned = set()
    for _palette, corners, normal in cells:
        axis = next(a for a in range(3) if normal[a])
        plane = corners[0][axis]
        fixed = plane - 1 if normal[axis] > 0 else plane
        free = [a for a in range(3) if a != axis]
        span = [(min(c[a] for c in corners), max(c[a] for c in corners)) for a in free]
        for u in range(span[0][0], span[0][1]):
            for v in range(span[1][0], span[1][1]):
                coord = [0, 0, 0]
                coord[axis] = fixed
                coord[free[0]] = u
                coord[free[1]] = v
                cell = (coord[0], coord[1], coord[2])
                if all(0 <= coord[a] < size[a] for a in range(3)):
                    owned.add(cell)
    return owned


def color_cells(size, cells, solid):
    """Each exposed face names the palette of the solid cell it bounds."""
    votes: dict[tuple[int, int, int], dict[int, int]] = defaultdict(lambda: defaultdict(int))
    for palette, corners, normal in cells:
        axis = next(a for a in range(3) if normal[a])
        plane = corners[0][axis]
        # A +axis face bounds the cell one step below the plane; a -axis face the cell at it.
        fixed = plane - 1 if normal[axis] > 0 else plane
        free = [a for a in range(3) if a != axis]
        span = [(min(c[a] for c in corners), max(c[a] for c in corners)) for a in free]
        for u in range(span[0][0], span[0][1]):
            for v in range(span[1][0], span[1][1]):
                cell = [0, 0, 0]
                cell[axis] = fixed
                cell[free[0]] = u
                cell[free[1]] = v
                key = (cell[0], cell[1], cell[2])
                if key in solid:
                    votes[key][palette] += 1
    colored: dict[tuple[int, int, int], int] = {}
    for cell, tally in votes.items():
        colored[cell] = max(tally.items(), key=lambda kv: (kv[1], -kv[0]))[0]
    return colored


def write_vox(path: Path, size, colored, palette):
    xyz = b"".join(
        struct.pack("<BBBB", x, y, z, color)
        for (x, y, z), color in sorted(colored.items())
        if 1 <= color <= 255
    )
    rgba = b"".join(
        bytes(palette.get(color, (255, 255, 255))) + b"\xff"
        for color in range(256)
    )
    size_chunk = _chunk(b"SIZE", struct.pack("<III", *size))
    xyzi_chunk = _chunk(b"XYZI", struct.pack("<I", len(colored)) + xyz)
    rgba_chunk = _chunk(b"RGBA", rgba)
    children = size_chunk + xyzi_chunk + rgba_chunk
    path.write_bytes(b"VOX " + struct.pack("<I", 150) + b"MAIN" + struct.pack("<II", 0, len(children)) + children)
    return len(colored)


def _chunk(tag: bytes, content: bytes) -> bytes:
    return tag + struct.pack("<II", len(content), 0) + content


def boundary_shell(region):
    """Keep the cells touching the surface on both sides (MagicaVoxel models are hollow shells)."""
    shell = set()
    for x, y, z in region:
        neighbours = (
            (x - 1, y, z), (x + 1, y, z),
            (x, y - 1, z), (x, y + 1, z),
            (x, y, z - 1), (x, y, z + 1),
        )
        if any(n not in region for n in neighbours):
            shell.add((x, y, z))
            shell.update(n for n in neighbours if n not in region)
    return shell


def rebuild(obj: Path, out: Path, unit: float):
    quads = parse_obj(obj)
    size, cells = quantize(quads, unit)
    solid = face_owned_cells(size, cells)
    colored = color_cells(size, cells, solid)
    palette = parse_mtl(obj.with_suffix(".mtl"))
    count = write_vox(out, size, colored, palette)
    return size, count


def geometry_lines(path: Path):
    """OBJ content minus the provenance header, which names the source file and digest."""
    return [
        line
        for line in path.read_text(encoding="utf-8").splitlines()
        if not line.startswith("# ")
    ]


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("obj", type=Path)
    parser.add_argument("out", type=Path)
    parser.add_argument("--unit", default="auto")
    parser.add_argument("--greedy", action="store_true")
    args = parser.parse_args()

    sys.path.insert(0, str(Path(__file__).resolve().parent))
    import vox_to_obj

    candidates = [float(args.unit)] if args.unit != "auto" else [0.125, 0.0625]
    for unit in candidates:
        size, count = rebuild(args.obj, args.out, unit)
        probe = args.out.with_suffix(".probe.obj")
        vox_to_obj.convert(args.out, probe, unit, greedy=True)
        if geometry_lines(probe) == geometry_lines(args.obj):
            recorded = ""
            for line in args.obj.read_text(encoding="utf-8").splitlines()[:4]:
                if line.startswith("# source_sha256"):
                    recorded = line.split()[-1]
            digest = hashlib.sha256(args.out.read_bytes()).hexdigest()
            probe.unlink()
            print(
                f"{args.out.name}: VERIFIED unit={unit} size={size} voxels={count} "
                f"regenerated OBJ is byte-identical; source_sha256 recorded={recorded or 'none'} "
                f"reconstructed={digest}"
            )
            return
        args.out.unlink()
    raise SystemExit(f"no grid tier reproduces {args.obj.name}; reconstructed geometry differs")


if __name__ == "__main__":
    main()
