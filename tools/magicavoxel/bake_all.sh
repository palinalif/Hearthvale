#!/usr/bin/env bash
# Bake every authored MagicaVoxel source the starter-hamlet runtime consumes.
#
# There is no manifest: each author script declares the assets it owns, and
# this script enumerates those declarations.  Adding a .vox plus an author
# script entry is all that is needed to bring a new asset into the bake.
#
# Grids follow the project contract: 0.125 for structural geometry, 0.0625 for
# decorative presentation.  A baked ".res" is a plain binary resource and needs
# no ".import" companion, unlike the ".vox" sources (which Godot imports as
# PackedScenes).
set -euo pipefail
PROJ="${1:-$PWD}"
GODOT="${GODOT:-godot}"
STAGE="assets/models/magicavoxel"
cd "$PROJ"
mkdir -p "$STAGE"

pairs=$(python3 tools/magicavoxel/bake_targets.py)

for pair in $pairs; do
  base="${pair%%=*}"
  grid="${pair##*=}"
  src_vox="assets/source/magicavoxel/${base}.vox"
  out_res="$STAGE/${base}.res"
  if [ ! -f "$src_vox" ]; then
    echo "SKIP $base (no authored .vox source)"
    continue
  fi
  # bake_mesh.gd reads OS.get_cmdline_user_args(), so its arguments must
  # follow a "--" separator.  It derives the intermediate OBJ path itself.
  "$GODOT" --headless --path . --script res://tools/magicavoxel/bake_mesh.gd -- \
    "res://$src_vox" "res://$out_res" "$grid" 2>&1 |
    { grep -E "Baked|ERROR" || true; } | head -3
done

echo "=== verifying baked meshes ==="
status=0
for pair in $pairs; do
  base="${pair%%=*}"
  if [ -f "$STAGE/${base}.res" ]; then
    echo "OK   $base"
  else
    echo "MISS $base"
    status=1
  fi
done
exit "$status"
