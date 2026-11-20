#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# SYNOPSIS
#   tools/title/title.sh azahar --game DIR [--scene title|map|battle] [--patch FILE]... [--height PX]
#                               [--3dsx FILE] [--timeout SEC] [--screenshot PNG] [--keep-home]
#   tools/title/title.sh kit    --out DIR [--scene title|map|battle] [--patch FILE]... [--height PX]
#                               [--3dsx FILE]
#
# DESCRIPTION
#   Runs a local RPG Maker XP game (never part of this repository) in the 3DS runtime with a
#   probe (an mkxp-z preloadScript) that reports on one scene. The game directory is copied as
#   is; added in the copy: mkxp.json (RGSS1, the game screen scaled to 3DS height,
#   docs/DECISIONS.md D15, no path cache), the probe and any --patch scripts. The game's own mkxp.json is replaced in
#   the copy only.
#     --scene title  (M3 exit, docs/DECISIONS.md D16) tools/title/title_probe.rb reports when
#                    the title screen is up: sdmc:/rmxp3ds/test/realtitle.txt, step log
#                    realtitle-log.txt.
#     --scene map    (M4 baseline) tools/title/map_probe.rb starts a new Pokémon Essentials v21
#                    game instead of the title and walks the player around two demo maps,
#                    measuring frame times: sdmc:/rmxp3ds/test/realmap.txt, step log
#                    realmap-log.txt.
#     --scene battle (M6 exit) tools/title/battle_probe.rb starts a new Pokémon Essentials v21
#                    game with a level 100 Pokémon and plays one wild battle with scripted
#                    input until it ends: sdmc:/rmxp3ds/test/realbattle.txt, step log
#                    realbattle-log.txt. The game's MIDI music is not rendered here (use
#                    convert/rmxp3ds-convert --preload tools/title/battle_probe.rb for that).
#     azahar  runs it in headless Azahar (tests/smoke/azahar-smoke.sh); passes when the probe
#             reports. Frame rates from the emulator do not count.
#     kit     writes the SD card layout to DIR/sd without any game file: sd/3ds/rmxp3ds/mkxp-z.3dsx
#             and the added files in sd/rmxp3ds/game. Copy the game's own folder contents to
#             sdmc:/rmxp3ds/game first, then the kit on top (its mkxp.json replaces the game's).
#
# OPTIONS
#   --game DIR        azahar: game directory (Game.ini, Data/, Graphics/ ...)
#   --scene NAME      title (default), map or battle
#   --patch FILE      rmxp3ds patch script run as a preload script before the probe, in the
#                     given order (e.g. patches/essentials-v21/tilemap_renderer.rb, D17)
#   --height PX       height of the game's screen in pixels (default 480; Pokémon Essentials: 384,
#                     it calls Graphics.resize_screen(512, 384)); the scaling factor is 240/PX
#   --3dsx FILE       runtime app (default: runtime/build-3ds/mkxp/mkxp-z.3dsx)
#   --timeout SEC     azahar: timeout (default: 600)
#   --screenshot PNG  azahar: screenshot when the probe reports (default: build/real<scene>.png)
#   --keep-home       azahar: keep Azahar's temporary HOME (virtual SD with logs)
#   --out DIR         kit output directory
#   -h, --help        show this help
#
# EXAMPLE
#   tools/title/title.sh azahar --game ~/volume/games/essentials --height 384
#   tools/title/title.sh kit --height 384 --out build/title-kit
#   tools/title/title.sh azahar --game ~/volume/games/essentials --height 384 --scene map \
#     --patch patches/essentials-v21/tilemap_renderer.rb
set -euo pipefail

usage() {
  sed -n '3,/^set -euo/{/^set -euo/d;s/^# \{0,1\}//;p}' "$0"
}

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
[ $# -gt 0 ] || { usage >&2; exit 2; }
case "$1" in
  azahar|kit) MODE="$1"; shift ;;
  -h|--help) usage; exit 0 ;;
  *) echo "title.sh: unknown mode: $1" >&2; usage >&2; exit 2 ;;
esac
GAME=""
OUT=""
HEIGHT=480
APP="$REPO/runtime/build-3ds/mkxp/mkxp-z.3dsx"
TIMEOUT=600
SCENE=title
SHOT=""
KEEP=()
PATCHES=()
while [ $# -gt 0 ]; do
  case "$1" in
    --game) GAME="$(realpath "${2:?--game needs a value}")"; shift 2 ;;
    --patch) PATCHES+=("$(realpath -m "${2:?--patch needs a file}")"); shift 2 ;;
    --scene) SCENE="${2:?--scene needs a value}"; shift 2 ;;
    --height) HEIGHT="${2:?--height needs a value}"; shift 2 ;;
    --3dsx) APP="$(realpath -m "${2:?--3dsx needs a value}")"; shift 2 ;;
    --timeout) TIMEOUT="${2:?--timeout needs a value}"; shift 2 ;;
    --screenshot) SHOT="$(realpath -m "${2:?--screenshot needs a value}")"; shift 2 ;;
    --keep-home) KEEP=(--keep-home); shift ;;
    --out) OUT="$(realpath -m "${2:?--out needs a value}")"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "title.sh: unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done
case "$SCENE" in title|map|battle) ;; *) echo "title.sh: --scene must be title, map or battle" >&2; exit 2 ;; esac
SHOT="${SHOT:-$REPO/build/real$SCENE.png}"
PROBE="$HERE/${SCENE}_probe.rb"
[ "$MODE" = kit ] || [ -f "$GAME/Game.ini" ] || { echo "title.sh: no Game.ini in --game DIR" >&2; exit 2; }
case "$HEIGHT" in ''|*[!0-9]*|0*) echo "title.sh: --height must be a positive number" >&2; exit 2 ;; esac
[ -f "$APP" ] || { echo "title.sh: $APP missing (build the runtime first, see AGENTS.md)" >&2; exit 1; }
[ "$MODE" = azahar ] || [ -n "$OUT" ] || { echo "title.sh: kit needs --out DIR" >&2; exit 2; }
case "$OUT" in "$REPO"/build|"$REPO"/build/*|"") ;; "$REPO"|"$REPO"/*) echo "title.sh: --out inside the repository must be under build/ (ignored by git)" >&2; exit 2 ;; esac

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
# patches: copied as rmxp3ds_patch_<n>.rb, run before the probe in the given order
PRELOADS=""
PATCH_FILES=()
for i in "${!PATCHES[@]}"; do
  [ -f "${PATCHES[$i]}" ] || { echo "title.sh: patch not found: ${PATCHES[$i]}" >&2; exit 2; }
  PRELOADS="$PRELOADS\"rmxp3ds_patch_$i.rb\", "
  PATCH_FILES+=("${PATCHES[$i]}=rmxp3ds/game/rmxp3ds_patch_$i.rb")
done
FACTOR="$(awk -v h="$HEIGHT" 'BEGIN { printf "%.6f", 240 / h }')"
cat > "$WORK/mkxp.json" <<JSON
// mkxp-z-3ds config written by rmxp3ds tools/title/title.sh (replaces the game's own in this copy)
{
  "rgssVersion": 1,
  // rmxp3ds D15: the game screen at 3DS height (240 / $HEIGHT), bitmaps at full size
  "enableHires": true,
  "framebufferScalingFactor": $FACTOR,
  "textureScalingFactor": 1.0,
  // no path cache: the 3DS SD card (FAT) already matches names without case, and listing all
  // of Essentials' 7606 files took minutes at start (NOTES.md M3, console attempt 4)
  "pathCache": false,
  "preloadScript": [$PRELOADS"rmxp3ds_probe.rb"]
}
JSON

case "$MODE" in
  azahar)
    mkdir -p "$(dirname "$SHOT")"
    PATCH_ARGS=()
    for spec in "${PATCH_FILES[@]}"; do PATCH_ARGS+=(--sd-file "$spec"); done
    "$REPO/tests/smoke/azahar-smoke.sh" --3dsx "$APP" --result "rmxp3ds/test/real$SCENE.txt" \
      --expect "^RMXP3DS_TEST real$SCENE PASS" --sd-dir "$GAME=rmxp3ds/game" \
      --sd-file "$WORK/mkxp.json=rmxp3ds/game/mkxp.json" \
      --sd-file "$PROBE=rmxp3ds/game/rmxp3ds_probe.rb" \
      "${PATCH_ARGS[@]}" \
      --timeout "$TIMEOUT" --screenshot "$SHOT" "${KEEP[@]}"
    ;;
  kit)
    rm -rf "$OUT/sd"
    mkdir -p "$OUT/sd/3ds/rmxp3ds" "$OUT/sd/rmxp3ds/test" "$OUT/sd/rmxp3ds/game"
    cp "$APP" "$OUT/sd/3ds/rmxp3ds/mkxp-z.3dsx"
    cp "$WORK/mkxp.json" "$OUT/sd/rmxp3ds/game/mkxp.json"
    cp "$PROBE" "$OUT/sd/rmxp3ds/game/rmxp3ds_probe.rb"
    for spec in "${PATCH_FILES[@]}"; do cp "${spec%=*}" "$OUT/sd/${spec##*=}"; done
    echo "kit: $OUT/sd (no game files: copy the game's folder to sdmc:/rmxp3ds/game first, then the kit)"
    ;;
esac
