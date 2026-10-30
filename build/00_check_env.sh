#!/usr/bin/env bash
# Step 1: report OS, architecture and available tools.
set -u
echo "== Environment"
uname -srm
[ -f /etc/os-release ] && grep PRETTY_NAME /etc/os-release
echo "CPU cores: $(nproc)"
for t in python3 curl unzip zip gcc xvfb-run convert; do
  if command -v "$t" >/dev/null 2>&1; then echo "  [ok] $t"; else echo "  [missing] $t"; fi
done
python3 -c "import numpy, PIL; print('  [ok] numpy', numpy.__version__, '/ Pillow', PIL.__version__)" 2>/dev/null || echo "  [missing] numpy/Pillow (pip install --user numpy pillow)"
