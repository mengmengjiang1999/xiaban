#!/bin/bash
# Use GODOT_BIN to override the editor location if it is installed elsewhere.
set -euo pipefail

game_root="$(cd "$(dirname "$0")/.." && pwd)"
godot_bin="${GODOT_BIN:-}"
if [[ -z "$godot_bin" ]]; then
  for candidate in "/Applications/Godot.app/Contents/MacOS/Godot" \
    "$HOME/Applications/Godot.app/Contents/MacOS/Godot" \
    "$HOME/Downloads/Godot.app/Contents/MacOS/Godot"; do
    if [[ -x "$candidate" ]]; then
      godot_bin="$candidate"
      break
    fi
  done
fi
if [[ ! -x "$godot_bin" ]]; then
  echo 'Godot not found. Set GODOT_BIN to the executable inside Godot.app.' >&2
  exit 1
fi
exec "$godot_bin" --path "$game_root/game" "$@"
