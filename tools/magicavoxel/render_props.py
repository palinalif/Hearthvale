#!/usr/bin/env python3
"""Render baked prop meshes to a contact sheet for visual review.

Reads the bake's OBJ/MTL intermediates (the same geometry the runtime loads,
before the Godot pivot/grid pass) and draws each asset as shaded polygons in
its authored palette colours.  This is a review aid for the desktop loop; it
is not the mobile renderer and is not acceptance evidence.
"""

from __future__ import annotations

import sys
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
from matplotlib.collections import PolyCollection


def read_mtl(path: Path) -> dict[str, tuple[float, float, float]]:
    colors: dict[str, tuple[float, float, float]] = {}
    current = None
    for line in path.read_text().splitlines():
        parts = line.split()
        if not parts:
            continue
        if parts[0] == "newmtl":
            current = parts[1]
        elif parts[0] == "Kd" and current:
            colors[current] = tuple(float(v) for v in parts[1:4])
    return colors


def read_obj(path: Path):
    verts: list[tuple[float, float, float]] = []
    groups: list[tuple[str, list[tuple[int, int, int]]]] = []
    current: list[tuple[int, int, int]] = []
    material = "default"
    for line in path.read_text().splitlines():
        parts = line.split()
        if not parts:
            continue
        if parts[0] == "v":
            verts.append(tuple(float(v) for v in parts[1:4]))
        elif parts[0] == "usemtl":
            if current:
                groups.append((material, current))
            current = []
            material = parts[1]
        elif parts[0] == "f":
            idx = tuple(int(p.split("/")[0]) - 1 for p in parts[1:])
            # Greedy meshing emits quads; fan-triangulate so both quads and
            # triangles reach the renderer.
            for i in range(1, len(idx) - 1):
                current.append((idx[0], idx[i], idx[i + 1]))
    if current:
        groups.append((material, current))
    return verts, groups


def draw(ax: plt.Axes, obj: Path, mtl: Path, title: str) -> None:
    verts, groups = read_obj(obj)
    colors = read_mtl(mtl)
    pts = np.asarray(verts)
    light = np.array([0.42, 0.78, 0.46])
    ax.set_aspect("equal")
    ax.axis("off")
    for material, faces in groups:
        base = np.asarray(colors.get(material, (0.75, 0.75, 0.75)))
        polys = []
        shades = []
        for a, b, c in faces:
            p = pts[[a, b, c]]
            normal = np.cross(p[1] - p[0], p[2] - p[0])
            length = np.linalg.norm(normal)
            shade = 0.55 if length == 0 else 0.42 + 0.58 * abs(normal @ light) / length
            polys.append(p[:, [0, 1]])
            shades.append(base * shade)
        ax.add_collection(
            PolyCollection(polys, facecolors=shades, edgecolors=(0, 0, 0, 0.25), linewidths=0.3)
        )
    if len(pts):
        ax.set_xlim(pts[:, 0].min() - 0.1, pts[:, 0].max() + 0.1)
        ax.set_ylim(pts[:, 1].min() - 0.1, pts[:, 1].max() + 0.1)
    ax.set_title(title, fontsize=8)


def main() -> int:
    stage = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("assets/models/magicavoxel")
    names = sys.argv[2:]
    fig, axes = plt.subplots(3, 4, figsize=(13, 9), facecolor="#101014")
    for ax, name in zip(axes.ravel(), names):
        obj, mtl = stage / f"{name}.obj", stage / f"{name}.mtl"
        if obj.exists() and mtl.exists():
            draw(ax, obj, mtl, name.replace("hearthvale_", ""))
        else:
            ax.axis("off")
            ax.set_title(f"{name} (missing)", fontsize=8)
    fig.tight_layout()
    out = Path("reports/magicavoxel-props.png")
    out.parent.mkdir(exist_ok=True)
    fig.savefig(out, dpi=110, facecolor=fig.get_facecolor())
    print("wrote", out)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
