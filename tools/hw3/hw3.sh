#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# SYNOPSIS
#   tools/hw3/hw3.sh kit    --out DIR [--3dsx FILE]
#   tools/hw3/hw3.sh azahar [--3dsx FILE] [--hold SEC] [--timeout SEC] [--keep-home]
#
# DESCRIPTION
#   Hardware run 3 (M3): the runtime's engine, render and title checks in one app start, then
#   frame times on the synthetic title scene and a window for trying HOME and sleep mode
#   (tools/hw3/hw3.rb). Only synthetic files from this repository go onto the SD card.
#     kit     writes the SD card layout to DIR/sd: sd/3ds/rmxp3ds/mkxp-z.3dsx (Homebrew Launcher)
#             and sd/rmxp3ds/game (mkxp.json, the check scripts, generated images). Copy the
#             contents of DIR/sd to the SD card root and start mkxp-z from the Homebrew Launcher
#             or with 3dslink. Results: sdmc:/rmxp3ds/test/hw3.txt (plus mkxp.txt, render.txt,
#             title.txt, *-results.txt and mkxp-stderr.txt in sdmc:/rmxp3ds).
#     azahar  runs the same layout in headless Azahar (tests/smoke/azahar-smoke.sh) and passes
#             when hw3.txt reports PASS; frame times from the emulator do not count.
#
# OPTIONS
#   --out DIR       kit output directory
#   --3dsx FILE     runtime app (default: runtime/build-3ds/mkxp/mkxp-z.3dsx)
#   --hold SEC      azahar: HOME/sleep window in seconds (default: 0, skipped)
#   --timeout SEC   azahar: timeout (default: 900)
#   --keep-home     azahar: keep Azahar's temporary HOME (virtual SD with all result files)
#   -h, --help      show this help
#
# EXAMPLE
#   tools/hw3/hw3.sh azahar
#   tools/hw3/hw3.sh kit --out build/hw3
set -euo pipefail

usage() {
  sed -n '3,/^set -euo/{/^set -euo/d;s/^# \{0,1\}//;p}' "$0"
}

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
[ $# -gt 0 ] || { usage >&2; exit 2; }
case "$1" in
  kit|azahar) MODE="$1"; shift ;;
  -h|--help) usage; exit 0 ;;
  *) echo "hw3.sh: unknown mode: $1" >&2; usage >&2; exit 2 ;;
esac
OUT=""
APP="$REPO/runtime/build-3ds/mkxp/mkxp-z.3dsx"
HOLD=0
TIMEOUT=900
KEEP=()
while [ $# -gt 0 ]; do
  case "$1" in
    --out) OUT="$(realpath -m "${2:?--out needs a value}")"; shift 2 ;;
    --3dsx) APP="$(realpath -m "${2:?--3dsx needs a value}")"; shift 2 ;;
    --hold) HOLD="${2:?--hold needs a value}"; shift 2 ;;
    --timeout) TIMEOUT="${2:?--timeout needs a value}"; shift 2 ;;
    --keep-home) KEEP=(--keep-home); shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "hw3.sh: unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done
[ -f "$APP" ] || { echo "hw3.sh: $APP missing (build the runtime first, see AGENTS.md)" >&2; exit 1; }
[ "$MODE" = azahar ] || [ -n "$OUT" ] || { echo "hw3.sh: kit needs --out DIR" >&2; exit 2; }
case "$HOLD" in ''|*[!0-9]*) echo "hw3.sh: --hold must be a number of seconds" >&2; exit 2 ;; esac
case "$OUT" in "$REPO"/build|"$REPO"/build/*|"") ;; "$REPO"|"$REPO"/*) echo "hw3.sh: --out inside the repository must be under build/ (ignored by git)" >&2; exit 2 ;; esac

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# make_game DIR: writes the game directory (config, scripts, generated images) to DIR.
make_game() {
  local game="$1"
  mkdir -p "$game/Graphics/Titles" "$game/Graphics/Windowskins"
  cat > "$game/mkxp.json" <<'JSON'
// SPDX-License-Identifier: GPL-3.0-or-later
// mkxp-z-3ds config (JSON5) for hardware run 3: RGSS1, run hw3.rb (see tools/hw3).
{
  "rgssVersion": 1,
  // rmxp3ds D15: render the game screen at 3DS height (640x480 -> 320x240), bitmaps at full size
  "enableHires": true,
  "framebufferScalingFactor": 0.5,
  "textureScalingFactor": 1.0,
  "customScript": "hw3.rb"
}
JSON
  cp "$HERE/hw3.rb" "$REPO/tests/runtime/enginecheck/enginecheck.rb" \
    "$REPO/tests/runtime/rendercheck/rendercheck.rb" "$REPO/tests/runtime/titlecheck/titlecheck.rb" "$game/"
  ruby "$REPO/tests/runtime/rendercheck/make-transmap.rb" --out "$game/trans-map.png"
  ruby "$REPO/tests/runtime/titlecheck/make-assets.rb" --out-dir "$WORK/assets"
  cp "$WORK/assets/title.png" "$game/Graphics/Titles/"
  cp "$WORK/assets/windowskin.png" "$game/Graphics/Windowskins/"
}

case "$MODE" in
  kit)
    rm -rf "$OUT/sd"
    mkdir -p "$OUT/sd/3ds/rmxp3ds" "$OUT/sd/rmxp3ds/test"
    cp "$APP" "$OUT/sd/3ds/rmxp3ds/mkxp-z.3dsx"
    make_game "$OUT/sd/rmxp3ds/game"
    echo "kit: $OUT/sd (copy its contents to the SD card root)"
    ;;
  azahar)
    make_game "$WORK/game"
    echo "$HOLD" > "$WORK/hw3-hold.txt"
    SD=(--sd-file "$WORK/hw3-hold.txt=rmxp3ds/test/hw3-hold.txt")
    while IFS= read -r f; do
      SD+=(--sd-file "$f=rmxp3ds/game/${f#"$WORK/game/"}")
    done < <(find "$WORK/game" -type f | sort)
    "$REPO/tests/smoke/azahar-smoke.sh" --3dsx "$APP" --result rmxp3ds/test/hw3.txt \
      --expect '^RMXP3DS_TEST hw3 PASS' "${SD[@]}" --timeout "$TIMEOUT" "${KEEP[@]}"
    ;;
esac
