#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# SYNOPSIS
#   tools/m2/m2.sh host   --game DIR [--bench NAME] [--env KEY=VALUE]...
#   tools/m2/m2.sh azahar --game DIR [--bench NAME] [--env KEY=VALUE]... [--3dsx FILE]
#                         [--timeout SEC] [--keep-home]
#   tools/m2/m2.sh kit    --out DIR [--bench NAME] [--env KEY=VALUE]... [--3dsx FILE]
#
# DESCRIPTION
#   Runs a game's scripts headlessly (tools/m2: load_game.rb + rgss_headless.rb) with a
#   benchmark, for the M2 go/no-go measurements:
#     host    with the host Ruby (same version as the 3DS Ruby)
#     azahar  in headless Azahar via tools/bench's bench.3dsx: harness and the game's Data/ go to
#             the virtual SD (sdmc:/rmxp3ds/m2, sdmc:/rmxp3ds/games/essentials), main.rb runs it;
#             passes when the app reports PASS (tests/smoke/azahar-smoke.sh)
#     kit     writes an SD card layout for the console to DIR/sd (app, harness, env.txt), without
#             game files: copy the game's Data/ to sdmc:/rmxp3ds/games/essentials/Data yourself
#   Game files are only read from DIR and never copied into the repository.
#
# OPTIONS
#   --game DIR        game directory containing Data/Scripts.rxdata
#   --bench NAME      benchmark in tools/m2: essentials (default) or synthetic
#   --env KEY=VALUE   setting for the benchmark (repeatable); host mode ignores these keys from
#                     the calling environment, like the 3DS does.
#                     essentials: OVERWORLD_FRAMES=N, MAPS=41,31 (empty: no maps), BATTLES=N
#                     synthetic:  FRAMES=N, EXPECT_DIGEST=N, REQUIRE_DIGEST=1
#                     both:       SIM_FPS=N (game clock, default 30)
#   --3dsx FILE       test app (default: build/bench/bench.3dsx)
#   --timeout SEC     Azahar timeout (default: 900)
#   --keep-home       keep Azahar's temporary HOME (virtual SD with stderr and stage files)
#   --out DIR         kit output directory
#   -h, --help        show this help
#
# EXAMPLE
#   ruby tests/fixtures/make-game.rb --out build/m2/synthetic-game
#   tools/m2/m2.sh host --game build/m2/synthetic-game --bench synthetic
#   tools/m2/m2.sh azahar --game ~/games/essentials --env BATTLES=2
set -euo pipefail

usage() {
  sed -n '3,/^set -euo/{/^set -euo/d;s/^# \{0,1\}//;p}' "$0"
}

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
[ $# -gt 0 ] || { usage >&2; exit 2; }
case "$1" in
  host|azahar|kit) MODE="$1"; shift ;;
  -h|--help) usage; exit 0 ;;
  *) echo "m2.sh: unknown mode: $1" >&2; usage >&2; exit 2 ;;
esac
GAME=""
OUT=""
BENCH=essentials
ENVS=()
APP="$REPO/build/bench/bench.3dsx"
TIMEOUT=900
KEEP=()
while [ $# -gt 0 ]; do
  case "$1" in
    --game) GAME="$(realpath "${2:?--game needs a value}")"; shift 2 ;;
    --bench) BENCH="${2:?--bench needs a value}"; shift 2 ;;
    --env) ENVS+=("${2:?--env needs KEY=VALUE}"); shift 2 ;;
    --3dsx) APP="$(realpath "${2:?--3dsx needs a value}")"; shift 2 ;;
    --timeout) TIMEOUT="${2:?--timeout needs a value}"; shift 2 ;;
    --keep-home) KEEP=(--keep-home); shift ;;
    --out) OUT="$(realpath -m "${2:?--out needs a value}")"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "m2.sh: unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done
case "$BENCH" in
  essentials|synthetic) BENCH_RB="${BENCH}_bench.rb" ;;
  *) echo "m2.sh: unknown benchmark: $BENCH" >&2; exit 2 ;;
esac
for kv in "${ENVS[@]}"; do
  case "$kv" in *=*) ;; *) echo "m2.sh: --env needs KEY=VALUE: $kv" >&2; exit 2 ;; esac
done
if [ "$MODE" = kit ]; then
  [ -n "$OUT" ] || { echo "m2.sh: kit needs --out DIR" >&2; exit 2; }
else
  [ -f "$GAME/Data/Scripts.rxdata" ] || { echo "m2.sh: no Data/Scripts.rxdata in --game DIR" >&2; exit 2; }
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
ruby "$HERE/decode-rpg1.rb" --out "$WORK/rpg1.rb" >/dev/null
HARNESS=(rgss_headless.rb load_game.rb "$BENCH_RB")

# write_env FILE: writes the --env settings and the benchmark choice as KEY=VALUE lines.
write_env() {
  { echo "M2_BENCH=$BENCH_RB"; printf '%s\n' "${ENVS[@]}"; } >"$1"
}

case "$MODE" in
  host)
    (unset OVERWORLD_FRAMES MAPS BATTLES FRAMES EXPECT_DIGEST REQUIRE_DIGEST SIM_FPS
     for kv in "${ENVS[@]}"; do export "${kv?}"; done
     ruby "$HERE/load_game.rb" "$GAME" "$WORK/rpg1.rb" "$HERE/$BENCH_RB")
    ;;
  azahar)
    [ -f "$APP" ] || { echo "m2.sh: $APP missing (build tools/bench first)" >&2; exit 1; }
    write_env "$WORK/env.txt"
    SD=(--sd-file "$HERE/main.rb=rmxp3ds/test/main.rb" --sd-file "$WORK/env.txt=rmxp3ds/m2/env.txt"
        --sd-file "$WORK/rpg1.rb=rmxp3ds/m2/rpg1.rb")
    for f in "${HARNESS[@]}"; do SD+=(--sd-file "$HERE/$f=rmxp3ds/m2/$f"); done
    while IFS= read -r -d '' f; do
      SD+=(--sd-file "$f=rmxp3ds/games/essentials/Data/${f#"$GAME/Data/"}")
    done < <(find "$GAME/Data" -type f -print0 | sort -z)
    "$REPO/tests/smoke/azahar-smoke.sh" --3dsx "$APP" --result rmxp3ds/test/rubybench.txt \
      --expect '^RMXP3DS_TEST rubybench PASS' --timeout "$TIMEOUT" "${KEEP[@]}" "${SD[@]}"
    ;;
  kit)
    [ -f "$APP" ] || { echo "m2.sh: $APP missing (build tools/bench first)" >&2; exit 1; }
    rm -rf "$OUT/sd"
    mkdir -p "$OUT/sd/3ds/rmxp3ds" "$OUT/sd/rmxp3ds/test" "$OUT/sd/rmxp3ds/m2" \
      "$OUT/sd/rmxp3ds/games/essentials/Data"
    cp "$APP" "$OUT/sd/3ds/rmxp3ds/"
    cp "$HERE/main.rb" "$OUT/sd/rmxp3ds/test/main.rb"
    cp "$WORK/rpg1.rb" "$OUT/sd/rmxp3ds/m2/"
    for f in "${HARNESS[@]}"; do cp "$HERE/$f" "$OUT/sd/rmxp3ds/m2/"; done
    write_env "$OUT/sd/rmxp3ds/m2/env.txt"
    echo "kit: $OUT/sd (copy the game's Data/ files to sd/rmxp3ds/games/essentials/Data)"
    ;;
esac
