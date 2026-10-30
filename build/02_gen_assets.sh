#!/usr/bin/env bash
# Step 3/4: generate the world (terrain, maps, vegetation, layout), textures and sounds.
set -euo pipefail
source "$(dirname "$0")/env.sh"
cd "$SUMMIT_ROOT/build"
mkdir -p .cache
gcc -O3 -march=x86-64-v2 -shared -fPIC -o .cache/libterrain.so terrain_kernels.c -lm
python3 -I gen_terrain.py "$PROJECT" "$@"
python3 -I gen_textures.py "$PROJECT"
python3 -I gen_audio.py "$PROJECT"
"$GODOT" --headless --script godot_tools/rasterize_icon.gd -- "$PROJECT/icon.svg" "$PROJECT/icon.png" 256
convert "$PROJECT/icon.png" -define icon:auto-resize=256,128,64,48,32,16 "$PROJECT/icon.ico" || true
