"""Promote the reviewed MCP planter sources and use Hearthvale's existing exporter.

No geometry is generated here. --promote reads only the four explicitly named
MCP staging files. The only source adjustment is SIZE metadata: the MCP writer
shrinks it after edits, so restore the common even 12x14x12 authoring volume.
XYZI and RGBA payloads must remain byte-identical. Default invocation re-exports
the canonical, editable sources without requiring the development MCP server.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import struct
from pathlib import Path

from vox_to_obj import convert, read_vox

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "assets/source/magicavoxel"
OUTPUT = ROOT / "assets/models/magicavoxel"
STAGING = ROOT / ".tools/magicavoxel/vox"
NAMES = ("hearthvale_planter_flowers", "hearthvale_planter_herbs", "hearthvale_planter_light")
VOLUME = (12, 14, 12)
UNIT = 0.0625


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def restore_volume(data: bytes) -> bytes:
    if data[:4] != b"VOX " or struct.unpack_from("<I", data, 4)[0] != 150:
        raise ValueError("Expected a VOX 150 source from the pinned MCP")
    result = bytearray(data)
    cursor = 20
    found = 0
    while cursor < len(result):
        chunk, content_size, child_size = struct.unpack_from("<4sII", result, cursor)
        if chunk == b"SIZE":
            if content_size != 12:
                raise ValueError("Unexpected SIZE payload")
            struct.pack_into("<III", result, cursor + 12, *VOLUME)
            found += 1
        cursor += 12 + content_size + child_size
    if found != 1:
        raise ValueError("Planters must have exactly one editable voxel model")
    return bytes(result)


def promote() -> None:
    records = []
    pairs = [(name, name) for name in NAMES]
    pairs.append(("hearthvale_planter_barrel_v2", "hearthvale_planter_barrel"))
    SOURCE.mkdir(parents=True, exist_ok=True)
    for staged_name, canonical_name in pairs:
        staged = STAGING / (staged_name + ".vox")
        raw = staged.read_bytes()
        dimensions, voxels, palette = read_vox(staged)
        if any(any(cell[a] >= VOLUME[a] for a in range(3)) for cell in voxels):
            raise ValueError(f"{staged_name}: voxel outside the declared authoring volume")
        canonical = SOURCE / (canonical_name + ".vox")
        normalized = restore_volume(raw)
        if canonical.exists() and canonical.read_bytes() != normalized:
            raise ValueError(f"Refusing to overwrite a different canonical source: {canonical.name}")
        canonical.write_bytes(normalized)
        new_dimensions, new_voxels, new_palette = read_vox(canonical)
        if new_dimensions != VOLUME or new_voxels != voxels or new_palette != palette:
            raise ValueError("Promotion changed geometry or palette")
        records.append({"source": canonical.name, "staged_source": staged.name,
                        "staged_sha256": digest(raw), "source_sha256": digest(normalized),
                        "staged_dimensions": dimensions, "declared_dimensions": VOLUME,
                        "voxels": len(voxels), "geometry_and_palette_unchanged": True})
    capture_dir = ROOT / "reports/screenshots/m2-planters/magicavoxel"
    capture_dir.mkdir(parents=True, exist_ok=True)
    for suffix in ("barrel-v2", "flowers", "herbs", "light"):
        filename = f"hearthvale-planter-{suffix}-review-20260913.png"
        shutil.copy2(ROOT / ".tools/magicavoxel/previews" / filename, capture_dir / filename)
    authoring = {
        "authored_utc_date": "2026-09-13", "tool": "MagicaVoxel MCP v2",
        "upstream_tool_commit": "710671d49bdc89e4e3d1ff7c60541c1d0383ac16",
        "provenance": "Created and edited directly through connected MagicaVoxel MCP v2 tools; not runtime procedural geometry or image generation",
        "operations": ["create_voxel_model", "set_palette_color", "copy_model", "fill_box", "clear_region", "copy_region", "place_voxel", "find_connected_components", "render_model_turntable", "take_snapshot"],
        "base": "Tapered octagonal barrel; eight one-cell-deep stave seams; two continuous iron hoops; separate overhanging rim; soil inset two cells below rim top",
        "planting": {"flowers": "Four flower heads at Y=9,10,11,12 with branched asymmetric leaf sprays", "herbs": "Two broad stepped leaf sprays plus a taller offset herb shoot; no flowers", "light": "Two sparse shoots and one cream flower; exposed soil and negative space"},
        "palette": {"1": "79563f", "2": "638348", "3": "486d46", "4": "87a657", "5": "df9a8b", "6": "c7b897", "7": "9a795c", "8": "594337", "9": "4b514d", "10": "6b6f64", "11": "473629"},
        "voxel_unit": UNIT, "pivot_voxels": [6, 0, 6],
        "promotion": "SIZE metadata only restored to a common even horizontal volume; no voxel moved, rescaled, removed or recoloured",
        "mcp_components": {"flowers": 1, "herbs": 1, "light": 1},
        "raw_preview_caveat": "MCP orthographic contact sheets display increasing Y downward; these are source inspections, not Godot captures or visual approval",
        "license": "Project-authored; development MCP upstream is MIT",
        "records": records,
    }
    (SOURCE / "planters.authoring.json").write_text(json.dumps(authoring, indent=2) + "\n", encoding="utf-8", newline="\n")


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
