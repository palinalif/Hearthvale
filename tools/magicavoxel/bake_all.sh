#!/usr/bin/env bash
# Rebuild every authored MagicaVoxel runtime mesh from its .vox source.
#
# Chain per asset:  .vox -> .obj/.mtl (tools/magicavoxel/vox_to_obj.py)
#                          -> .mesh/.res (tools/magicavoxel/bake_mesh.gd)
#
# Each asset carries its own scale and light-source palettes in the receipt
# vox_to_obj.py writes (`voxel_unit`, `emissive_palette_indices`), so the plan
# is derived from the assets themselves rather than a global unit. A source
# with no receipt yet is baked on the 0.125 structural tier.
#
# Godot 4 has no runtime OBJ loader, so the .obj files are imported once
# (the built-in wavefront_obj importer) before the bake reads them.
set -euo pipefail
cd "$(dirname "$0")/../.."

SOURCE_DIR=assets/source/magicavoxel
MESH_DIR=assets/models/magicavoxel
PLAN=/tmp/hearthvale-bake-plan.tsv

# 1. Author the script-built sources.
python3 tools/magicavoxel/author_props.py
python3 tools/magicavoxel/author_furniture.py

# 2. Vectorize every .vox into an OBJ, carrying the unit, emissive palettes and
#    meshing mode recorded in that asset's own receipt.
#
#    Meshing mode matters: greedy coplanar merging is what keeps a dense canopy
#    inside the triangle budget (the orchard tree is 5618 triangles greedy,
#    32832 without). Baking a greedy asset without the flag silently ships a
#    6x more expensive mesh, so the mode is read back from the receipt rather
#    than assumed.
rm -f "$PLAN"
while read -r vox; do
  name=$(basename "$vox" .vox)
  receipt="$MESH_DIR/$name.asset.json"
  unit=0.125
  emissive=""
  energy=1.5
  greedy=0
  if [ -f "$receipt" ]; then
    unit=$(python3 -c "import json;print(json.load(open('$receipt')).get('voxel_unit',0.125))")
    emissive=$(python3 -c "import json;print(','.join(map(str,json.load(open('$receipt')).get('emissive_palette_indices',[]))))")
    energy=$(python3 -c "import json;print(json.load(open('$receipt')).get('emissive_energy',1.5))")
    greedy=$(python3 -c "import json;print(1 if str(json.load(open('$receipt')).get('meshing','')).startswith('greedy') else 0)")
  fi
  python3 tools/magicavoxel/vox_to_obj.py --unit "$unit" \
    ${emissive:+--emissive "$emissive"} --emissive-energy "$energy" \
    ${greedy:+--greedy} \
    "$vox" "$MESH_DIR/$name.obj" >/dev/null
  printf '%s\t%s\t%s\t%s\n' "$name" "$unit" "$emissive" "$energy" >> "$PLAN"
done < <(find "$SOURCE_DIR" -name '*.vox' | sort)

# 3. Import the OBJs so Godot can load them, then bake every mesh in one pass.
#    bake_mesh.gd takes positional args: -- SOURCE OUTPUT [UNIT]. Per-palette
#    materials (including the light sources' emission, written into the .mtl by
#    vox_to_obj.py) survive the bake, so each asset keeps one surface per palette.
timeout 600 godot --headless --path . --import >/dev/null 2>&1 || true
baked=0
while IFS=$'\t' read -r name unit emissive energy; do
  echo "baking $name (unit $unit, emissive ${emissive:-none})"
  timeout 300 godot --headless --path . -s tools/magicavoxel/bake_mesh.gd -- \
    "res://$MESH_DIR/$name.obj" "res://$MESH_DIR/$name.res" "$unit" \
    | tail -1 | python3 -c 'import json,sys; d=json.loads(sys.stdin.read()); print("  ->", d["surfaces"], "surfaces,", d["vertices"], "vertices, ok=", d["ok"])'
  baked=$((baked + 1))
done < "$PLAN"
echo "baked $baked mesh(es)"

# 4. The .obj/.mtl stay committed: they are the source the .obj.import sidecar
#    refers to, and the baked .res is derived from them.
find "$MESH_DIR" -maxdepth 1 -name '*.obj.tmp' -delete
