#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# SYNOPSIS
#   tests/smoke/azahar-smoke.sh --3dsx FILE --result PATH --expect REGEX
#                               [--timeout SEC] [--screenshot PNG] [--display :N] [--keep-home]
#
# DESCRIPTION
#   Runs a self-reporting .3dsx in headless Azahar (azahar-headless) and checks its result file.
#   Uses a fresh HOME (own Azahar config and virtual SD card) and creates
#   sdmc:/rmxp3ds/test/autoexit so the app exits after reporting. Waits until
#   sdmc:/PATH exists, prints it, and succeeds if a line matches REGEX (grep -E).
#   Seeds .devcontainer/azahar/qt-config.ini if the repo has one.
#   Exit codes: 0 pass, 1 fail (no match / timeout / emulator died), 2 usage error.
#   Azahar keeps running after the app exits and aborts on SIGTERM; its exit status is ignored,
#   the result file is the verdict.
#
# OPTIONS
#   --3dsx FILE        homebrew to boot
#   --result PATH      result file, relative to the virtual SD root (e.g. rmxp3ds/test/hello.txt)
#   --expect REGEX     extended regex a result line must match
#   --timeout SEC      seconds to wait for the result file (default 120)
#   --screenshot PNG   save a screenshot of the display when the result appears or on timeout
#   --display :N       X display for Xvfb (default $AZAHAR_DISPLAY or :99)
#   --keep-home        keep the temporary HOME (Azahar logs, virtual SD) and print its path
#   -h, --help         show this help
#
# EXAMPLE
#   tests/smoke/azahar-smoke.sh --3dsx build/hello/hello.3dsx \
#     --result rmxp3ds/test/hello.txt --expect '^RMXP3DS_TEST hello PASS' --screenshot hello.png
set -euo pipefail

usage() {
  sed -n '3,/^set -euo/{/^set -euo/d;s/^# \{0,1\}//;p}' "$0"
}

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
FILE="" RESULT="" EXPECT="" TIMEOUT=120 SHOT="" KEEP=0
DISPLAY_NUM="${AZAHAR_DISPLAY:-:99}"
while [ $# -gt 0 ]; do
  case "$1" in
    --3dsx) FILE="${2:?--3dsx needs a value}"; shift 2 ;;
    --result) RESULT="${2:?--result needs a value}"; shift 2 ;;
    --expect) EXPECT="${2:?--expect needs a value}"; shift 2 ;;
    --timeout) TIMEOUT="${2:?--timeout needs a value}"; shift 2 ;;
    --screenshot) SHOT="${2:?--screenshot needs a value}"; shift 2 ;;
    --display) DISPLAY_NUM="${2:?--display needs a value}"; shift 2 ;;
    --keep-home) KEEP=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "azahar-smoke.sh: unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done
if [ -z "$FILE" ] || [ -z "$RESULT" ] || [ -z "$EXPECT" ]; then
  echo "azahar-smoke.sh: --3dsx, --result and --expect are required" >&2; usage >&2; exit 2
fi
[ -f "$FILE" ] || { echo "azahar-smoke.sh: $FILE not found" >&2; exit 2; }
case "$TIMEOUT" in ''|*[!0-9]*) echo "azahar-smoke.sh: --timeout must be a number" >&2; exit 2 ;; esac
FILE="$(cd "$(dirname "$FILE")" && pwd)/$(basename "$FILE")"

AZ_HOME="$(mktemp -d)"
SDMC="$AZ_HOME/.local/share/azahar-emu/sdmc"
mkdir -p "$SDMC/rmxp3ds/test"
: >"$SDMC/rmxp3ds/test/autoexit"
if [ -f "$REPO/.devcontainer/azahar/qt-config.ini" ]; then
  mkdir -p "$AZ_HOME/.config/azahar-emu"
  cp "$REPO/.devcontainer/azahar/qt-config.ini" "$AZ_HOME/.config/azahar-emu/"
fi

PGID=""
# shellcheck disable=SC2317 # invoked via trap
# cleanup: stops the emulator's process group (Azahar, and Xvfb if it started it) and removes
# the temporary HOME unless --keep-home.
cleanup() {
  if [ -n "$PGID" ]; then
    kill -TERM -- "-$PGID" 2>/dev/null || true
    sleep 1
    kill -KILL -- "-$PGID" 2>/dev/null || true
    # wait until the group is gone, so a next run can reuse the display
    for _ in $(seq 50); do pgrep -g "$PGID" >/dev/null || break; sleep 0.1; done
  fi
  if [ "$KEEP" -eq 1 ]; then echo "azahar-smoke.sh: kept HOME $AZ_HOME"; else rm -rf "$AZ_HOME"; fi
}
trap cleanup EXIT

# screenshot: saves the X display to --screenshot, if requested.
screenshot() {
  [ -n "$SHOT" ] || return 0
  DISPLAY="$DISPLAY_NUM" import -window root "$SHOT" 2>/dev/null \
    && echo "azahar-smoke.sh: screenshot $SHOT" || echo "azahar-smoke.sh: screenshot failed" >&2
}

# Job control gives the background job its own process group (PGID = $!), so cleanup reaches
# Azahar and the Xvfb that azahar-headless may start. (setsid is unreliable here: it forks when the
# caller already leads a process group, and then $! is not the group.)
ulimit -c 0 # Azahar crashes on SIGTERM; no core files
set -m
HOME="$AZ_HOME" AZAHAR_DISPLAY="$DISPLAY_NUM" azahar-headless "$FILE" >"$AZ_HOME/azahar.log" 2>&1 &
PGID=$!
set +m
disown "$PGID" # no job status message ("Aborted") when Azahar dies on SIGTERM

status=1
deadline=$((SECONDS + TIMEOUT))
until [ -s "$SDMC/$RESULT" ]; do
  if ! kill -0 "$PGID" 2>/dev/null; then
    echo "azahar-smoke.sh: emulator exited before writing $RESULT; last log lines:" >&2
    tail -n 20 "$AZ_HOME/azahar.log" >&2
    exit 1
  fi
  if [ "$SECONDS" -ge "$deadline" ]; then
    echo "azahar-smoke.sh: timeout after ${TIMEOUT}s waiting for $RESULT" >&2
    screenshot
    exit 1
  fi
  sleep 1
done
screenshot # right away: the app exits a few seconds after reporting
sleep 1    # let the app finish writing
echo "azahar-smoke.sh: result ($RESULT):"
sed 's/^/  /' "$SDMC/$RESULT"
if grep -Eq -- "$EXPECT" "$SDMC/$RESULT"; then
  echo "azahar-smoke.sh: PASS"
  status=0
else
  echo "azahar-smoke.sh: FAIL (no line matches $EXPECT)" >&2
fi
exit "$status"
