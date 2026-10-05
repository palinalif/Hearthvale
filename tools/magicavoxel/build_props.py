#!/usr/bin/env python3
"""Stage procedural prop models as MagicaVoxel .vox sources and bake runtime assets.

Reads the JSON emitted by .tools/magicavoxel/emit_props.mjs (Node procedural
generators) and, for each model:

  1. writes a MagicaVoxel 150 .vox into the staging directory
  2. bakes the runtime OBJ/MTL/asset manifest with tools/magicavoxel/vox_to_obj.py

Nothing is written into canonical source/runtime directories; promotion is a
separate, explicitly approved step.

Usage: build_props.py /tmp/props.json STAGING_DIR [--unit 0.125] [--greedy]
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from vox_to_asset import write_vox  # noqa: E402
from vox_to_obj import main as bake  # noqa: E402


def hex_to_rgba(value: str) -> tuple[int, int, int, int]:
    value = value.lstrip("#")
    if len(value) == 3:
        value = "".join(c * 2 for c in value)
    return int(value[0:2], 16), int(value[2:4], 16), int(value[4:6], 16), 255


def build(props_path: Path, staging: Path, unit: float, greedy: bool) -> int:
    data = json.loads(props_path.read_text())
    palette = [((0, 0, 0, 0))] * 256
    for key, hex_value in data["palette"].items():
        palette[int(key)] = hex_to_rgba(hex_value)

    staging.mkdir(parents=True, exist_ok=True)
    rows = []
    for name, model in data["models"].items():
        vox_path = staging / f"hearthvale_{name}.vox"
        voxels = [(v["x"], v["y"], v["z"], v["c"]) for v in model["voxels"]]
        write_vox(vox_path, model["size"], voxels, palette)
        obj_path = staging / f"hearthvale_{name}.obj"
        argv = ["vox_to_obj.py", str(vox_path), str(obj_path), "--unit", str(unit)]
        if greedy:
            argv.append("--greedy")
        sys.argv = argv
        # vox_to_obj.main() returns None on success and signals failure by
        # raising SystemExit with a non-zero/string code; comparing its return
        # value against 0 would report every successful bake as a failure.
        try:
            bake()
        except SystemExit as exc:
            if exc.code:
                print(f"bake failed for {name}", file=sys.stderr)
                return 1
        rows.append((name, len(voxels), vox_path.name))

    for name, count, vox_name in rows:
        print(f"{name}: {count} voxels -> {vox_name}")
    return 0


def main() -> int:
    import argparse

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("props_json", type=Path)
    parser.add_argument("staging", type=Path)
    parser.add_argument("--unit", type=float, default=0.125)
    parser.add_argument("--greedy", action="store_true")
    args = parser.parse_args()
    return build(args.props_json, args.staging, args.unit, args.greedy)


if __name__ == "__main__":
    raise SystemExit(main())
