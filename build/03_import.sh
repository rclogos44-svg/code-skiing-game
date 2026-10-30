#!/usr/bin/env bash
# Step 5: import resources with the headless editor (twice: first creates .import files,
# then our texture parameters are applied and the textures re-imported).
set -euo pipefail
source "$(dirname "$0")/env.sh"
"$GODOT" --headless --path "$PROJECT" --import 2>&1 | grep -E "ERROR|SCRIPT" || true
python3 -I "$SUMMIT_ROOT/build/set_import_params.py" "$PROJECT"
"$GODOT" --headless --path "$PROJECT" --import 2>&1 | grep -E "ERROR|SCRIPT" || true
