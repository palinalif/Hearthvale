#!/usr/bin/env bash
# Bake the starter-hamlet furniture meshes from the authored MagicaVoxel sources.
#
# Sources are the staging .vox files named by author_props.MESH_NAMES; outputs
# go to the canonical, tracked mesh library using the same
# "hearthvale_prop_<mesh>.res" naming as the other 44 prop meshes.
#
# A baked ".res" is a plain binary resource: it needs no ".import" companion
# (unlike the ".vox" sources, which Godot imports as PackedScenes).
set -euo pipefail
PROJ="${1:-$PWD}"
GODOT="${GODOT:-godot}"
STAGE="assets/models/magicavoxel"
cd "$PROJ"
mkdir -p "$STAGE"

pairs=$(python3 -c "import sys; sys.path.insert(0,'tools/magicavoxel'); import author_props as ap; print(' '.join(ap.MESH_NAMES))")

for mesh in $pairs; do
  src_vox="assets/source/magicavoxel/hearthvale_${mesh}.vox"
  out_res="$STAGE/hearthvale_prop_${mesh}.res"
  if [ ! -f "$src_vox" ]; then
    echo "SKIP $mesh (no authored .vox source)"
    continue
  fi
  # bake_mesh.gd reads OS.get_cmdline_user_args(), so its arguments must
  # follow a "--" separator.  It derives the intermediate OBJ path itself.
  "$GODOT" --headless --path . --script res://tools/magicavoxel/bake_mesh.gd -- \
    "res://$src_vox" "res://$out_res" 0.125 2>&1 |
    { grep -E "Baked|ERROR" || true; } | head -3
done

echo "=== verifying baked meshes ==="
status=0
for mesh in $pairs; do
  if [ -f "$STAGE/hearthvale_prop_${mesh}.res" ]; then
    echo "OK   $mesh"
  else
    echo "MISS $mesh"
    status=1
  fi
done
exit "$status"
