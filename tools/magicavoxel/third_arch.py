"""Deterministic 1/3 decimation of the approved canonical MagicaVoxel arch.

Reads the VOX 150 source (120x144x72 cells @ 0.0625), maps every 3x3x3 block
to a single cell by majority palette vote (ties to the lowest palette index,
empty blocks dropped), and writes the 40x48x24 result to the ignored MCP
staging directory. The 0.0625 presentation cell is preserved: this changes
cell counts, not cell size. No palette bytes are altered.

Default: assets/source/magicavoxel/hearthvale_flower_arch.vox ->
.tools/magicavoxel/vox/hearthvale_flower_arch_third.vox
"""

from __future__ import annotations

import sys
from collections import Counter
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from scale_arch import read_vox, write_vox  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "assets/source/magicavoxel/hearthvale_flower_arch.vox"
STAGING = ROOT / ".tools/magicavoxel/vox/hearthvale_flower_arch_third.vox"
FACTOR = 3


def main() -> None:
    size, voxels, palette = read_vox(SOURCE)
    if tuple(size) != (FACTOR * 40, FACTOR * 48, FACTOR * 24):
        raise SystemExit(f"unexpected source size {size}; expected 120x144x72")
    out_size = tuple(s // FACTOR for s in size)
    result: dict[tuple[int, int, int], int] = {}
    by_block: dict[tuple[int, int, int], Counter] = {}
    for x, y, z, color in voxels:
        by_block.setdefault((x // FACTOR, y // FACTOR, z // FACTOR), Counter())[color] += 1
    for (bx, by, bz), votes in by_block.items():
        # Most frequent palette wins; deterministic tie-break on lowest index.
        result[(bx, by, bz)] = min(votes, key=lambda c: (-votes[c], c))
    written = [(*pos, color) for pos, color in sorted(result.items())]
    write_vox(STAGING, out_size, written, palette)
    y_max = max(p[1] for p in result) + 1
    x0 = min(p[0] for p in result)
    x1 = max(p[0] for p in result) + 1
    z0 = min(p[2] for p in result)
    z1 = max(p[2] for p in result) + 1
    print(f"{SOURCE.name} {size} {len(voxels)} voxels -> {STAGING.name} {out_size} {len(written)} voxels")
    print(
        f"occupied: x {x0}..{x1} ({(x1 - x0) * 0.0625}m) "
        f"y {0}..{y_max} ({y_max * 0.0625}m) "
        f"z {z0}..{z1} ({(z1 - z0) * 0.0625}m)"
    )


if __name__ == "__main__":
    main()
