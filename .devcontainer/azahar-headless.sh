#!/bin/sh
# Run Azahar on a virtual X display (Xvfb) inside the dev container.
#   azahar-headless build/xp3ds.3dsx
# Display defaults to $AZAHAR_DISPLAY (:99). For parallel instances use different displays
# and separate HOME dirs so configs/virtual SD cards don't collide, e.g.
#   AZAHAR_DISPLAY=:100 HOME=/tmp/az1 azahar-headless game.3dsx
# Screenshot of the running instance:
#   DISPLAY=:99 import -window root shot.png
set -eu

DISPLAY_NUM="${AZAHAR_DISPLAY:-:99}"

if ! xdpyinfo -display "$DISPLAY_NUM" >/dev/null 2>&1; then
  Xvfb "$DISPLAY_NUM" -screen 0 1280x720x24 -nolisten tcp \
    >"/tmp/xvfb-${DISPLAY_NUM#:}.log" 2>&1 &
  i=0
  until xdpyinfo -display "$DISPLAY_NUM" >/dev/null 2>&1; do
    i=$((i + 1))
    if [ "$i" -gt 50 ]; then
      echo "azahar-headless: Xvfb on $DISPLAY_NUM did not start" >&2
      exit 1
    fi
    sleep 0.1
  done
fi

export DISPLAY="$DISPLAY_NUM"
export QT_QPA_PLATFORM=xcb

exec /opt/azahar/AppRun "$@"
