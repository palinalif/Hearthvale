#!/usr/bin/env bash
# Bake every authored MagicaVoxel source the starter-hamlet runtime consumes.
#
# There is no manifest: each author script declares the assets it owns, and
# this script enumerates those declarations.  Adding a .vox plus an author
# script entry is all that is needed to bring a new asset into the bake.
#
# Pipeline per asset:
#   .vox  --(vox_to_obj.py: greedy meshing, per-palette materials, receipt)-->  .obj
#   .obj  --(Godot import)-->  imported Mesh
#   Mesh  --(bake_mesh.gd: grid snap, ground pivot, authored emissive)-->  .res
#
# The OBJ intermediate is what keeps each palette role its own surface with its
# own material; baking the .vox directly collapses the model to one material.
#
# Grids follow the project contract: 0.125 for structural geometry, 0.0625 for
# decorative presentation.  A baked ".res" is a plain binary resource and needs
# no ".import" companion, unlike the ".vox" and ".obj" intermediates.
set -euo pipefail
PROJ="${1:-$PWD}"
GODOT="${GODOT:-godot}"
STAGE="assets/models/magicavoxel"
cd "$PROJ"
mkdir -p "$STAGE"

pairs=$(python3 tools/magicavoxel/bake_targets.py)

for pair in $pairs; do
  base="${pair%%=*}"
  spec="${pair#*=}"
  grid="${spec%%:*}"
  rest="${spec#*:}"
  emissive=""
  energy=""
  if [ "$rest" != "$spec" ]; then
    emissive="${rest%%:*}"
    energy="${rest#*:}"
  fi
  src_vox="assets/source/magicavoxel/${base}.vox"
  out_obj="$STAGE/${base}.obj"
  out_res="$STAGE/${base}.res"
  if [ ! -f "$src_vox" ]; then
    echo "SKIP $base (no authored .vox source)"
    continue
  fi
  args=(--unit "$grid" --greedy)
  if [ -n "$emissive" ]; then
    args+=(--emissive "$emissive" --emissive-energy "$energy")
  fi
  if ! python3 tools/magicavoxel/vox_to_obj.py "$src_vox" "$out_obj" "${args[@]}" >/dev/null; then
    echo "FAIL $base (vox -> obj)"
    continue
  fi
done

# Import the generated OBJ intermediates once, before any bake reads them.
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
status=0

for pair in $pairs; do
  base="${pair%%=*}"
  spec="${pair#*=}"
  grid="${spec%%:*}"
  src_vox="assets/source/magicavoxel/${base}.vox"
  out_obj="$STAGE/${base}.obj"
  out_res="$STAGE/${base}.res"
  [ -f "$src_vox" ] && [ -f "$out_obj" ] || continue
  # Keep the previous bake so the gate can roll back.  A mesher regression
  # produces on-grid, plausible vertex counts, so it is invisible to a count.
  backup=""
  if [ -f "$out_res" ]; then
    backup="$(mktemp)"
    cp "$out_res" "$backup"
  fi
  # bake_mesh.gd reads OS.get_cmdline_user_args(), so its arguments must
  # follow a "--" separator.
  "$GODOT" --headless --path . --script res://tools/magicavoxel/bake_mesh.gd -- \
    "res://$out_obj" "res://$out_res" "$grid" 2>&1 |
    { grep -E '"ok":true|ERROR' || true; } | head -3
  if ! "$GODOT" --headless --path . --script res://tools/magicavoxel/check_bake.gd -- \
      "res://$out_res" "$grid" 2>&1 | grep -q '"ok":true'; then
    echo "REJECT $base (baked mesh does not match its authored source)"
    if [ -n "$backup" ]; then
      cp "$backup" "$out_res"
      echo "RESTORED $base (previous bake kept)"
    fi
    [ -n "$backup" ] && rm -f "$backup"
    status=1
    continue
  fi
  [ -n "$backup" ] && rm -f "$backup"
  echo "BAKED  $base"
done

echo "=== verifying baked meshes ==="
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
