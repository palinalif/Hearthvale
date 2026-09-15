#!/usr/bin/env bash
set -u
GODOT=/opt/data/tools/godot/Godot_v4.7.2-stable_linux.x86_64
cd /opt/data/sandboxes/Hearthvale-visual
export DISPLAY=:99
export LIBGL_ALWAYS_SOFTWARE=1
OUT=/tmp/roof_head.log
: > "$OUT"
echo "HEAD=$(git rev-parse --short HEAD) BRANCH=$(git rev-parse --abbrev-ref HEAD)" | tee -a "$OUT"
timeout 420 "$GODOT" --max-fps 60 --path . --renderer mobile --script tests/joined_roof_course_render_test.gd > /tmp/roof_head_raw.log 2>&1
echo "godot_exit=$?" | tee -a "$OUT"
grep -iE 'checks=|failures=|FAIL:' /tmp/roof_head_raw.log | grep -viE 'ALSA|snd_func' | tail -12 | tee -a "$OUT"
echo "=== JOINT_COURSE_RENDER json ===" | tee -a "$OUT"
grep -oE 'JOINED_COURSE_RENDER \{.*\}' /tmp/roof_head_raw.log | tail -1 | tee -a "$OUT"
echo "ROOF_HEAD_RUN_DONE" | tee -a "$OUT"
