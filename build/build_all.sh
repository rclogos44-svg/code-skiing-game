#!/usr/bin/env bash
# Full automated pipeline: environment -> tools -> assets -> import -> validate/test -> export -> package.
# Usage: build/build_all.sh [--skip-assets] [--skip-tests]
set -euo pipefail
B="$(cd "$(dirname "$0")" && pwd)"
SKIP_ASSETS=0; SKIP_TESTS=0
for a in "$@"; do case $a in --skip-assets) SKIP_ASSETS=1;; --skip-tests) SKIP_TESTS=1;; esac; done
bash "$B/00_check_env.sh"
bash "$B/01_get_tools.sh"
[ $SKIP_ASSETS -eq 1 ] || bash "$B/02_gen_assets.sh"
bash "$B/03_import.sh"
[ $SKIP_TESTS -eq 1 ] || bash "$B/04_validate_and_test.sh"
bash "$B/05_export.sh"
bash "$B/06_package.sh"
bash "$B/07_web.sh"
echo "BUILD COMPLETE"
