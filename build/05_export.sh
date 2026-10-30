#!/usr/bin/env bash
# Step 8: export native release builds (Windows x64, Linux x64, macOS universal).
set -euo pipefail
source "$(dirname "$0")/env.sh"
mkdir -p "$DIST/build/windows" "$DIST/build/linux" "$DIST/build/macos"
rm -f "$DIST/build/macos/SUMMIT.zip"
"$GODOT" --headless --path "$PROJECT" --export-release "Windows" "$DIST/build/windows/SUMMIT.exe" 2>&1 | grep -E "ERROR|WARNING" || true
"$GODOT" --headless --path "$PROJECT" --export-release "Linux" "$DIST/build/linux/SUMMIT.x86_64" 2>&1 | grep -E "ERROR|WARNING" || true
"$GODOT" --headless --path "$PROJECT" --export-release "macOS" "$DIST/build/macos/SUMMIT.zip" 2>&1 | grep -E "ERROR|WARNING" || true
for f in windows/SUMMIT.exe windows/SUMMIT.pck linux/SUMMIT.x86_64 linux/SUMMIT.pck macos/SUMMIT.zip; do
  [ -s "$DIST/build/$f" ] || { echo "EXPORT FAILED: $f missing"; exit 1; }
done
# smoke-test the exported Linux binary (same game data as the other platforms)
"$DIST/build/linux/SUMMIT.x86_64" --headless -- --test=physics 2>&1 | grep -E "done:" | grep -q "0 failures" \
  && echo "exported build: physics tests PASS" || { echo "exported build: tests FAILED"; exit 1; }
