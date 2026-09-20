"""Promote the reviewed MCP garden-plot sources and export their meshes.

The six plots cover every garden style/size the M2 placement rules allow. No
geometry is generated here: --promote copies the named staging files byte-for-
byte (the MCP already stores the declared even horizontal volume) and records
provenance in garden-plots.authoring.json. The default invocation re-exports
the canonical sources without the development MCP server.

Usage:
  python3 tools/magicavoxel/garden_assets.py            # re-export meshes
  python3 tools/magicavoxel/garden_assets.py --promote  # promote + re-export
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

from vox_to_obj import convert, read_vox

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "assets/source/magicavoxel"
OUTPUT = ROOT / "assets/models/magicavoxel"
STAGING = ROOT / ".tools/magicavoxel/vox"
UNIT = 0.0625

NAMES = (
    "hearthvale_garden_kitchen_48x28",
    "hearthvale_garden_kitchen_56x40",
    "hearthvale_garden_flowers_16x32",
    "hearthvale_garden_flowers_48x32",
    "hearthvale_garden_herbs_24x16",
    "hearthvale_garden_herbs_36x36",
)

PALETTE = {"1": "8a6a4a", "2": "6b4a31", "3": "4e7142", "4": "86a258"}
ACCENTS = {"flowers": "d8a2a0", "kitchen": "c96f43", "herbs": "9d8fa6"}


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def promote() -> None:
    records = []
    for name in NAMES:
        staged = STAGING / (name + ".vox")
        raw = staged.read_bytes()
        dimensions, voxels, palette = read_vox(staged)
        if dimensions[0] % 2 or dimensions[2] % 2:
            raise ValueError(f"{name}: horizontal declared volume must stay even")
        if any(cell[a] >= dimensions[a] for a in range(3) for cell in voxels):
            raise ValueError(f"{name}: voxel outside the declared volume")
        if len(voxels) < 400:
            raise ValueError(f"{name}: plot is sparser than expected ({len(voxels)} cells)")
        canonical = SOURCE / (name + ".vox")
        if canonical.exists() and canonical.read_bytes() != raw:
            raise ValueError(f"Refusing to overwrite a different canonical source: {name}")
        canonical.write_bytes(raw)
        if read_vox(canonical)[1:] != (voxels, palette):
            raise ValueError(f"Promotion changed geometry or palette: {name}")
        style = "flowers" if "flowers" in name else "kitchen" if "kitchen" in name else "herbs"
        records.append({
            "source": canonical.name,
            "staged_source": staged.name,
            "staged_sha256": digest(raw),
            "source_sha256": digest(raw),
            "declared_dimensions": list(dimensions),
            "voxel_count": len(voxels),
            "palette": {**PALETTE, "5": ACCENTS[style]},
        })
    authoring = {
        "authored_utc_date": "2026-09-20",
        "tool": "MagicaVoxel MCP",
        "provenance": "Six plots authored through MagicaVoxel MCP batched fill_box calls; the deterministic pattern script is .tools/magicavoxel/garden_plots_gen.js (ignored staging). MCP raw snapshots were taken for every model.",
        "operations": ["create_voxel_model", "set_palette_color", "fill_box", "take_snapshot"],
        "generation": "Scripted deterministic layout (drifted flower rows, three raised vegetable rows, divided herb quadrants) issued as MCP fill_box batches — the same authoring channel as every other Hearthvale voxel asset, with the 0.0625 presentation grid",
        "sizes": {
            "kitchen_rows:3.0x1.75": "hearthvale_garden_kitchen_48x28",
            "kitchen_rows:3.5x2.5": "hearthvale_garden_kitchen_56x40",
            "cottage_flowers:1.0x2.0": "hearthvale_garden_flowers_16x32",
            "cottage_flowers:3.0x2.0": "hearthvale_garden_flowers_48x32",
            "herb_garden:1.5x1.0": "hearthvale_garden_herbs_24x16",
            "herb_garden:2.25x2.25": "hearthvale_garden_herbs_36x36",
        },
        "voxel_unit": UNIT,
        "placement": "scripts/m2_composition_visual.gd GARDEN_MESHES; the mesh AABB bottom snaps to the terrain surface and yaw rotates around the model centre",
        "raw_preview_caveat": "render_vox.py orthographic sheets are source inspections, not Godot captures or visual approval",
        "license": "Project-authored; development MCP upstream is MIT",
        "records": records,
    }
    (SOURCE / "garden-plots.authoring.json").write_text(json.dumps(authoring, indent=2) + "\n", encoding="utf-8", newline="\n")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--promote", action="store_true")
    args = parser.parse_args()
    if args.promote:
        promote()
    receipts = [convert(SOURCE / (name + ".vox"), OUTPUT / (name + ".obj"), UNIT, greedy=True) for name in NAMES]
    print(json.dumps({"ok": True, "assets": [{"name": r["asset"], "voxels": r["voxel_count"], "triangles": r["triangles"], "sha256": r["source_sha256"]} for r in receipts]}, sort_keys=True))


if __name__ == "__main__":
    main()
