#!/usr/bin/env bash
# Step 9: package each platform as SUMMIT/ (game + README + LICENSES) in a ZIP.
set -euo pipefail
source "$(dirname "$0")/env.sh"
VER=$(grep -oP 'config/version="\K[^"]+' "$PROJECT/project.godot")
LIC="$SUMMIT_ROOT/build/.cache/licenses"
"$GODOT" --headless --script "$SUMMIT_ROOT/build/godot_tools/dump_licenses.gd" -- "$LIC" >/dev/null
cp "$SUMMIT_ROOT/build/package_files/SUMMIT_CONTENT.txt" "$LIC/"
STAGE="$DIST/stage"
rm -rf "$STAGE" && mkdir -p "$STAGE"
pack() {  # $1 = platform label, rest = files to copy into SUMMIT/
  local label=$1; shift
  local dir="$STAGE/$label/SUMMIT"
  mkdir -p "$dir/LICENSES"
  cp -a "$@" "$dir/"
  cp "$SUMMIT_ROOT/build/package_files/README.txt" "$dir/"
  cp "$LIC"/*.txt "$dir/LICENSES/"
  (cd "$STAGE/$label" && rm -f "$DIST/SUMMIT-$VER-$label.zip" && zip -qry9 "$DIST/SUMMIT-$VER-$label.zip" SUMMIT)
  echo "packaged $DIST/SUMMIT-$VER-$label.zip ($(du -h "$DIST/SUMMIT-$VER-$label.zip" | cut -f1))"
}
pack Windows-x64 "$DIST/build/windows/SUMMIT.exe" "$DIST/build/windows/SUMMIT.pck"
pack Linux-x64 "$DIST/build/linux/SUMMIT.x86_64" "$DIST/build/linux/SUMMIT.pck"
rm -rf "$STAGE/macapp" && mkdir -p "$STAGE/macapp" && unzip -q "$DIST/build/macos/SUMMIT.zip" -d "$STAGE/macapp"
chmod +x "$STAGE/macapp/SUMMIT.app/Contents/MacOS/SUMMIT"
pack macOS-universal "$STAGE/macapp/SUMMIT.app"
rm -rf "$STAGE"
