#!/bin/sh
cd "$(dirname "$0")" || exit 1
if ! command -v python3 >/dev/null 2>&1; then
  echo 'Python 3 is required: https://www.python.org/downloads/'
  echo 'Alternatively, use the hosted GitHub Pages game once enabled.'
  read -r answer
  exit 1
fi
python3 start_game.py
