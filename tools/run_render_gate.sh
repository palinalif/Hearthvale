#!/usr/bin/env bash
# Standalone render gate (Mobile renderer, Xvfb). Reads nothing from env besides DISPLAY.
set -u
GODOT=/opt/data/tools/godot/Godot_v4.7.2-stable_linux.x86_64
cd "$(dirname "$0")/.."
export DISPLAY=:99
export LIBGL_ALWAYS_SOFTWARE=1
OUT=/tmp/render_gate.log
: > "$OUT"
run() {
  local t="$1"
  timeout 420 "$GODOT" --max-fps 60 --path . --renderer mobile --script "tests/${t}.gd" > "/tmp/render_${t}.log" 2>&1
  local e=$?
  local l
  l=$(grep -oiE 'checks=[0-9]+ failures=[0-9]+' "/tmp/render_${t}.log" | tail -1)
  [ -z "$l" ] && l="(no checks line) raw=$(grep -viE 'ALSA|snd_func' "/tmp/render_${t}.log" | tail -1)"
  echo "${t} exit=${e} | ${l}" | tee -a "$OUT"
}
for t in scene_boot_gate_test cottage_detail_render_test facade_depth_render_test joined_roof_course_render_test m2_hamlet_composition_render_test; do
  run "$t"
done
echo "RENDER GATE DONE" | tee -a "$OUT"
