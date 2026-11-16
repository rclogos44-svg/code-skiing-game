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
# the rider's clothes and gear (meshes + texture atlases), then the Godot mesh resources.  The
# clothes are draped in Blender by blender/build_rider.py; its output (rider_garments.npz) is
# committed, so no Blender is needed here: lining, weights, atlases and the gear are finished in
# Python.  (gen_rider.py alone still builds the older all-procedural outfit.)
gcc -O3 -shared -fPIC -o .cache/librider.so rider_kernels.c -lm
python3 -I rider_from_blender.py "$PROJECT" rider_garments.npz
"$GODOT" --headless --path "$PROJECT" --script "$SUMMIT_ROOT/build/godot_tools/import_rider.gd" -- "$SUMMIT_ROOT/build/.cache/rider_raw.json" "$SUMMIT_ROOT/build/.cache/rider_raw.bin"
"$GODOT" --headless --script godot_tools/rasterize_icon.gd -- "$PROJECT/icon.svg" "$PROJECT/icon.png" 256
convert "$PROJECT/icon.png" -define icon:auto-resize=256,128,64,48,32,16 "$PROJECT/icon.ico" || true
