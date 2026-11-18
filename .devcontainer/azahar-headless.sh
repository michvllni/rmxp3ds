#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
#
# SYNOPSIS
#   azahar-headless [azahar options] [file.3dsx|file.cia|...]
#
# DESCRIPTION
#   Runs Azahar on a virtual X display (Xvfb), starting Xvfb if none is running on that display.
#   Environment:
#     AZAHAR_DISPLAY  X display to use (default :99)
#     AZAHAR_HOME     extracted Azahar AppImage (default /opt/tools/azahar)
#   For parallel instances use different displays and separate HOME dirs so configs and virtual
#   SD cards (~/.local/share/azahar-emu/sdmc) don't collide.
#   Screenshot of a running instance: DISPLAY=:99 import -window root shot.png
#
# OPTIONS
#   -h, --help  show this help (Azahar's own help: azahar-headless -- --help)
#   All other arguments are passed to Azahar unchanged.
#
# EXAMPLE
#   AZAHAR_DISPLAY=:100 HOME=/tmp/az1 azahar-headless build/hello.3dsx
set -eu

usage() {
  sed -n '3,/^set -eu/{/^set -eu/d;s/^# \{0,1\}//;p}' "$0"
}

case "${1:-}" in
  -h|--help) usage; exit 0 ;;
  --) shift ;;
esac

DISPLAY_NUM="${AZAHAR_DISPLAY:-:99}"
AZAHAR_HOME="${AZAHAR_HOME:-/opt/tools/azahar}"

if [ ! -x "$AZAHAR_HOME/AppRun" ]; then
  echo "azahar-headless: $AZAHAR_HOME/AppRun not found (set AZAHAR_HOME)" >&2
  exit 1
fi

if ! xdpyinfo -display "$DISPLAY_NUM" >/dev/null 2>&1; then
  Xvfb "$DISPLAY_NUM" -screen 0 1280x720x24 -nolisten tcp \
    >"${TMPDIR:-/tmp}/xvfb-${DISPLAY_NUM#:}.log" 2>&1 &
  XVFB_PID=$!
  i=0
  until xdpyinfo -display "$DISPLAY_NUM" >/dev/null 2>&1; do
    # Our Xvfb died (e.g. another one took the display in the meantime): don't attach to a
    # foreign server.
    if ! kill -0 "$XVFB_PID" 2>/dev/null; then
      echo "azahar-headless: Xvfb on $DISPLAY_NUM exited, see ${TMPDIR:-/tmp}/xvfb-${DISPLAY_NUM#:}.log" >&2
      exit 1
    fi
    i=$((i + 1))
    if [ "$i" -gt 50 ]; then
      echo "azahar-headless: Xvfb on $DISPLAY_NUM did not start" >&2
      exit 1
    fi
    sleep 0.1
  done
fi

if [ -n "${XVFB_PID:-}" ] && ! kill -0 "$XVFB_PID" 2>/dev/null; then
  echo "azahar-headless: Xvfb on $DISPLAY_NUM exited (display taken by another server?)" >&2
  exit 1
fi

export DISPLAY="$DISPLAY_NUM"
export QT_QPA_PLATFORM=xcb

exec "$AZAHAR_HOME/AppRun" "$@"
