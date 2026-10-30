#!/usr/bin/env bash
# Step 6/7: validate scripts/resources/inputs/layout, run physics tests and (if a display can be
# emulated) rendered screenshot + smoke tests.
set -uo pipefail
source "$(dirname "$0")/env.sh"
LOG="$SUMMIT_ROOT/build/.cache/test_report.txt"
mkdir -p "$SUMMIT_ROOT/previews/shots"
: > "$LOG"
fail=0
echo "== validate" | tee -a "$LOG"
"$GODOT" --headless --path "$PROJECT" res://scenes/validate.tscn 2>&1 | grep -E "VALIDATE|SCRIPT ERROR" | tee -a "$LOG"
[ "${PIPESTATUS[0]}" -eq 0 ] || fail=1
echo "== physics" | tee -a "$LOG"
"$GODOT" --headless --path "$PROJECT" -- --test=physics 2>&1 | grep -E "\[TEST\]|SCRIPT ERROR" | tee -a "$LOG"
grep -q "0 failures" "$LOG" || fail=1
if command -v xvfb-run >/dev/null; then
  echo "== rendered smoke test" | tee -a "$LOG"
  timeout 900 xvfb-run -a -s "-screen 0 1280x720x24" "$GODOT" --path "$PROJECT" --resolution 960x540 -- --test=smoke --seconds=40 \
    --out="$SUMMIT_ROOT/previews/shots" 2>&1 | grep -E "\[TEST\]|SCRIPT ERROR|Vulkan|OpenGL" | tee -a "$LOG"
fi
grep -q "SCRIPT ERROR" "$LOG" && fail=1
echo "== result: $([ $fail -eq 0 ] && echo PASS || echo FAIL)" | tee -a "$LOG"
exit $fail
