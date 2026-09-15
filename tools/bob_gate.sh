#!/usr/bin/env bash
# Bob's test gate — runs the required headless + mobile-render tests and prints
# one line each: "<test> exit=<e> | checks=N failures=M"
set -u
GODOT=/opt/data/tools/godot/Godot_v4.7.2-stable_linux.x86_64
cd "$(dirname "$0")/.."
OUT="${GATE_OUT:-/tmp/gate.log}"
: > "$OUT"
run() {
  local t="$1"
  local args="$2"
  timeout 400 "$GODOT" --max-fps 60 --path . --script "tests/${t}.gd" ${args} > "/tmp/gate_${t}.log" 2>&1
  local e=$?
  local l
  l=$(grep -oiE 'checks=[0-9]+ failures=[0-9]+' "/tmp/gate_${t}.log" | tail -1)
  [ -z "$l" ] && l="(no checks line) raw_last=$(grep -viE 'ALSA|snd_func' "/tmp/gate_${t}.log" | tail -1)"
  echo "${t} exit=${e} | ${l}" | tee -a "$OUT"
}
# headless tests
for t in foliage_asset_test magicavoxel_asset_test backend_test visual_lighting_profile_test; do
  run "$t" "--headless"
done
# mobile render tests (need Xvfb :99)
if [ -n "${GATE_RENDER:-}" ]; then
  export DISPLAY=:99 LIBGL_ALWAYS_SOFTWARE=1
  for t in cottage_detail_render_test facade_depth_render_test joined_roof_course_render_test; do
    run "$t" "--renderer mobile"
  done
fi
# acceptance (long, headless)
run m1_acceptance_test "--headless"
echo "GATE DONE" | tee -a "$OUT"
