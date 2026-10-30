#!/usr/bin/env bash
# Step 10: browser build (WebAssembly + WebGL 2, single-threaded) packaged as a hostable page with
# <15 MB chunks reassembled in the browser (see web/page_template.html).
set -euo pipefail
source "$(dirname "$0")/env.sh"
mkdir -p "$DIST/build/web"
"$GODOT" --headless --path "$PROJECT" --export-release "Web" "$DIST/build/web/SUMMIT.html" 2>&1 | grep -E "ERROR" || true
python3 -I "$SUMMIT_ROOT/build/web_package.py" "$DIST/build/web" "$DIST/web_artifact"
