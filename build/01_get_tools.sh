#!/usr/bin/env bash
# Step 2: download the official Godot editor + export templates into tools/ (checksum verified),
# install templates in self-contained mode, and fetch Mesa lavapipe (software Vulkan, for tests).
set -euo pipefail
source "$(dirname "$0")/env.sh"
VER=4.6.3-stable
BASE="https://github.com/godotengine/godot/releases/download/$VER"
mkdir -p "$SUMMIT_ROOT/tools/dl" "$SUMMIT_ROOT/tools/godot"
cd "$SUMMIT_ROOT/tools/dl"
curl -sSL -o SHA512-SUMS.txt "$BASE/SHA512-SUMS.txt"
if [ ! -x "$GODOT" ]; then
  curl -sSL -o godot_linux.zip "$BASE/Godot_v${VER}_linux.x86_64.zip"
  grep " Godot_v${VER}_linux.x86_64.zip" SHA512-SUMS.txt | awk '{print $1"  godot_linux.zip"}' | sha512sum -c -
  unzip -q -o godot_linux.zip -d "$SUMMIT_ROOT/tools/godot"
  chmod +x "$GODOT"
fi
touch "$SUMMIT_ROOT/tools/godot/._sc_"
TPL="$SUMMIT_ROOT/tools/godot/editor_data/export_templates/${VER/-/.}"
if [ ! -f "$TPL/windows_release_x86_64.exe" ]; then
  curl -sSL -o templates.tpz "$BASE/Godot_v${VER}_export_templates.tpz"
  grep " Godot_v${VER}_export_templates.tpz" SHA512-SUMS.txt | awk '{print $1"  templates.tpz"}' | sha512sum -c -
  rm -rf tx && mkdir tx && unzip -q templates.tpz -d tx
  mkdir -p "$TPL"
  for f in windows_release_x86_64.exe windows_debug_x86_64.exe windows_release_x86_64_console.exe windows_debug_x86_64_console.exe \
           linux_release.x86_64 linux_debug.x86_64 macos.zip version.txt icudt_godot.dat; do cp "tx/templates/$f" "$TPL/"; done
  rm -rf tx templates.tpz
fi
if [ ! -f "$SUMMIT_ROOT/tools/lavapipe/usr/lib/x86_64-linux-gnu/libvulkan_lvp.so" ]; then
  mkdir -p "$SUMMIT_ROOT/tools/lavapipe"
  curl -sSL -o mvd.deb https://archive.ubuntu.com/ubuntu/pool/main/m/mesa/mesa-vulkan-drivers_25.2.8-0ubuntu0.24.04.4_amd64.deb || true
  [ -f mvd.deb ] && dpkg-deb -x mvd.deb "$SUMMIT_ROOT/tools/lavapipe" || echo "lavapipe unavailable: rendered tests will use OpenGL"
  printf '{ "ICD": { "api_version": "1.4.318", "library_path": "%s" }, "file_format_version": "1.0.1" }\n' \
    "$SUMMIT_ROOT/tools/lavapipe/usr/lib/x86_64-linux-gnu/libvulkan_lvp.so" > "$SUMMIT_ROOT/tools/lavapipe/lvp_icd_local.json"
fi
"$GODOT" --headless --version
