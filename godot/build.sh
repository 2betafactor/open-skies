#!/usr/bin/env bash
# Export Open Skies. Usage: ./build.sh [web|linux|windows|all]
# Needs the Godot 4.7 editor binary (GODOT env var or ~/godot/Godot_v4.7.2-stable_linux.x86_64)
# and the matching export templates installed in ~/.local/share/godot/export_templates/.
set -euo pipefail
cd "$(dirname "$0")"
GODOT="${GODOT:-$HOME/godot/Godot_v4.7.2-stable_linux.x86_64}"
what="${1:-web}"
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
mkdir -p ../play ../dist
case "$what" in
  web)     "$GODOT" --headless --path . --export-release Web ../play/index.html
           gzip -9 -kf ../play/index.wasm ../play/index.pck ../play/index.js ;;
  linux)   "$GODOT" --headless --path . --export-release Linux ../dist/openskies-linux.x86_64 ;;
  windows) "$GODOT" --headless --path . --export-release Windows ../dist/openskies-windows.exe ;;
  all)     "$0" web; "$0" linux; "$0" windows ;;
  *) echo "unknown target $what"; exit 1 ;;
esac
echo "export done: $what"
