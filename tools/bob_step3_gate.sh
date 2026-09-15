#!/usr/bin/env bash
# Step-3 verification gate (Bob, 2026-09-15). Runs exactly the six required
# checks from the brief plus the two known-count suites, one line each:
#   <test> exit=<e> | checks=N failures=M
# Render checks get DISPLAY=:99 LIBGL_ALWAYS_SOFTWARE=1 --renderer mobile.
set -u
GODOT=/opt/data/tools/godot/Godot_v4.7.2-stable_linux.x86_64
cd "$(dirname "$0")/.."
LOG_DIR=/tmp/step3-gate
mkdir -p "$LOG_DIR"
: > "$LOG_DIR/summary.txt"

run() {
  local name="$1"
  local render="$2"
  local log="$LOG_DIR/${name}.log"
  if [ "$render" = "render" ]; then
    DISPLAY=:99 LIBGL_ALWAYS_SOFTWARE=1 timeout 900 "$GODOT" --max-fps 60 --path . --renderer mobile --script "tests/${name}.gd" > "$log" 2>&1
  else
    timeout 900 "$GODOT" --headless --max-fps 60 --path . --script "tests/${name}.gd" > "$log" 2>&1
  fi
  local exit_code=$?
  local line
  line=$(grep -oE 'checks=[0-9]+ failures=[0-9]+' "$log" | tail -1)
  [ -z "$line" ] && line="(no checks line)"
  echo "${name} exit=${exit_code} | ${line}" | tee -a "$LOG_DIR/summary.txt"
}

run backend_test            headless
run visual_lighting_profile_test headless
run m1_acceptance_test      headless
run cottage_detail_render_test   render
run m2_hamlet_composition_render_test render
run facade_depth_render_test     render
run foliage_asset_test      headless
run joined_roof_course_render_test render
echo "STEP3 GATE DONE" | tee -a "$LOG_DIR/summary.txt"
