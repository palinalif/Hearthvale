#!/usr/bin/env bash
# Bake the starter-hamlet furniture meshes from the authored MagicaVoxel sources.
#
# Sources are the .vox files authored by tools/magicavoxel/author_furniture.py
# for the nine furniture styles the runtime used to build from primitives;
# outputs go to the canonical mesh library as "hearthvale_furniture_<style>.res".
# These are decorative presentation props, so they bake on the 0.0625 grid.
#
# A baked ".res" is a plain binary resource: it needs no ".import" companion
# (unlike the ".vox" sources, which Godot imports as PackedScenes).
set -euo pipefail
PROJ="${1:-$PWD}"
GODOT="${GODOT:-godot}"
STAGE="assets/models/magicavoxel"
cd "$PROJ"
mkdir -p "$STAGE"

pairs=$(python3 -c "import sys; sys.path.insert(0,'tools/magicavoxel'); import author_furniture as af; print(' '.join(af.FURNITURE))")

for mesh in $pairs; do
  src_vox="assets/source/magicavoxel/hearthvale_furniture_${mesh}.vox"
  out_res="$STAGE/hearthvale_furniture_${mesh}.res"
  if [ ! -f "$src_vox" ]; then
    echo "SKIP $mesh (no authored .vox source)"
    continue
  fi
  # bake_mesh.gd reads OS.get_cmdline_user_args(), so its arguments must
  # follow a "--" separator.  It derives the intermediate OBJ path itself.
  "$GODOT" --headless --path . --script res://tools/magicavoxel/bake_mesh.gd -- \
    "res://$src_vox" "res://$out_res" 0.0625 2>&1 |
    { grep -E "Baked|ERROR" || true; } | head -3
done

echo "=== verifying baked meshes ==="
status=0
for mesh in $pairs; do
  if [ -f "$STAGE/hearthvale_furniture_${mesh}.res" ]; then
    echo "OK   $mesh"
  else
    echo "MISS $mesh"
    status=1
  fi
done
exit "$status"
