# Shared build environment for SUMMIT (sourced by build scripts)
SUMMIT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT="$SUMMIT_ROOT/tools/godot/Godot_v4.6.3-stable_linux.x86_64"
PROJECT="$SUMMIT_ROOT/project"
DIST="$SUMMIT_ROOT/dist"
export VK_ICD_FILENAMES="$SUMMIT_ROOT/tools/lavapipe/lvp_icd_local.json"
