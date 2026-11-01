#!/usr/bin/env bash
# Capture d'écran du jeu (rendu interne agrandi ×2) :
#   tools/shot.sh SORTIE.png SECONDES [arguments du jeu...]
# Exemple : tools/shot.sh /tmp/a.png 6 --autopilot --start_s=20000
set -euo pipefail
out="$1"; at="$2"; shift 2
GODOT="${GODOT:-godot}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
raw="${out%.png}_raw.png"
xvfb-run -a -s "-screen 0 1280x1024x24" "$GODOT" --path "$ROOT" --rendering-driver opengl3 \
	--quit-after 2000 -- --capture="$raw" --capture_at="$at" "$@" 2>&1 | grep -E "SCRIPT ERROR|^ERROR" -A3 | grep -vE "audio|alsa|status < 0" || true
ffmpeg -v error -y -i "$raw" -vf scale=iw*2:ih*2:flags=neighbor "$out"
rm -f "$raw"
