#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# SYNOPSIS
#   install-tools.sh --prefix DIR [--jobs N] [--only LIST]
#
# DESCRIPTION
#   Installs the pinned non-devkitPro tools into DIR:
#     DIR/ruby      host Ruby (converter, baseruby for the CRuby cross build), via ruby-build
#     DIR/azahar    Azahar emulator, AppImage extracted (no FUSE needed)
#     DIR/bin       makerom, bannertool
#   Versions and checksums come from environment variables, which the Dockerfile sets from its
#   ARGs and tools/setup-workspace.sh parses from the Dockerfile:
#     RUBY_VERSION RUBY_BUILD_VERSION AZAHAR_VERSION AZAHAR_SHA256
#     MAKEROM_VERSION MAKEROM_SHA256 BANNERTOOL_VERSION BANNERTOOL_SHA256
#   Every download is checked against its sha256. Components that are already installed in the
#   pinned version are skipped (a .version stamp file per component).
#
# OPTIONS
#   --prefix DIR   installation prefix (required)
#   --jobs N       parallel make jobs for the Ruby build (default: nproc)
#   --only LIST    comma-separated subset of: ruby,azahar,makerom,bannertool (default: all)
#   -h, --help     show this help
#
# EXAMPLE
#   RUBY_VERSION=3.1.3 ... install-tools.sh --prefix /opt/tools --jobs 4
set -euo pipefail

usage() {
  sed -n '3,/^set -euo/{/^set -euo/d;s/^# \{0,1\}//;p}' "$0"
}

PREFIX=""
JOBS="$(nproc)"
ONLY="ruby,azahar,makerom,bannertool"
while [ $# -gt 0 ]; do
  case "$1" in
    --prefix) PREFIX="${2:?--prefix needs a value}"; shift 2 ;;
    --jobs) JOBS="${2:?--jobs needs a value}"; shift 2 ;;
    --only) ONLY="${2:?--only needs a value}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "install-tools.sh: unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done
[ -n "$PREFIX" ] || { echo "install-tools.sh: --prefix is required" >&2; usage >&2; exit 2; }

# want COMPONENT: succeeds if COMPONENT is in --only.
want() { case ",$ONLY," in *",$1,"*) return 0 ;; *) return 1 ;; esac; }

# need_vars VAR...: fails with a message if any of the named environment variables is empty.
need_vars() {
  local v
  for v in "$@"; do
    [ -n "${!v:-}" ] || { echo "install-tools.sh: $v is not set" >&2; exit 2; }
  done
}

# is_current COMPONENT VERSION: succeeds if PREFIX/.stamps/COMPONENT holds VERSION.
is_current() { [ "$(cat "$PREFIX/.stamps/$1" 2>/dev/null || true)" = "$2" ]; }
# stamp COMPONENT VERSION: records the installed VERSION of COMPONENT.
stamp() { mkdir -p "$PREFIX/.stamps"; printf '%s\n' "$2" >"$PREFIX/.stamps/$1"; }

# fetch URL SHA256 FILE: downloads URL to FILE and verifies its sha256.
fetch() {
  curl -fsSL --retry 3 -o "$3" "$1"
  echo "$2  $3" | sha256sum -c --quiet - || { echo "install-tools.sh: checksum mismatch for $1" >&2; exit 1; }
}

mkdir -p "$PREFIX/bin"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

if want ruby; then
  need_vars RUBY_VERSION RUBY_BUILD_VERSION
  if is_current ruby "$RUBY_VERSION/$RUBY_BUILD_VERSION"; then
    echo "ruby $RUBY_VERSION: up to date"
  else
    git -c advice.detachedHead=false clone -q --depth 1 --branch "$RUBY_BUILD_VERSION" \
      https://github.com/rbenv/ruby-build.git "$WORK/ruby-build"
    rm -rf "$PREFIX/ruby"
    MAKE_OPTS="-j$JOBS" RUBY_CONFIGURE_OPTS="--disable-install-doc" \
      "$WORK/ruby-build/bin/ruby-build" "$RUBY_VERSION" "$PREFIX/ruby"
    stamp ruby "$RUBY_VERSION/$RUBY_BUILD_VERSION"
  fi
fi

if want azahar; then
  need_vars AZAHAR_VERSION AZAHAR_SHA256
  if is_current azahar "$AZAHAR_VERSION"; then
    echo "azahar $AZAHAR_VERSION: up to date"
  else
    fetch "https://github.com/azahar-emu/azahar/releases/download/$AZAHAR_VERSION/azahar.AppImage" \
      "$AZAHAR_SHA256" "$WORK/azahar.AppImage"
    chmod +x "$WORK/azahar.AppImage"
    # --appimage-extract is handled by the AppImage runtime itself and needs no FUSE.
    (cd "$WORK" && ./azahar.AppImage --appimage-extract >/dev/null)
    rm -rf "$PREFIX/azahar"
    mv "$WORK/squashfs-root" "$PREFIX/azahar"
    stamp azahar "$AZAHAR_VERSION"
  fi
fi

if want makerom; then
  need_vars MAKEROM_VERSION MAKEROM_SHA256
  if is_current makerom "$MAKEROM_VERSION"; then
    echo "makerom $MAKEROM_VERSION: up to date"
  else
    fetch "https://github.com/3DSGuy/Project_CTR/releases/download/makerom-$MAKEROM_VERSION/makerom-$MAKEROM_VERSION-ubuntu_x86_64.zip" \
      "$MAKEROM_SHA256" "$WORK/makerom.zip"
    unzip -q -o "$WORK/makerom.zip" makerom -d "$WORK/makerom"
    install -m 755 "$WORK/makerom/makerom" "$PREFIX/bin/makerom"
    stamp makerom "$MAKEROM_VERSION"
  fi
fi

if want bannertool; then
  need_vars BANNERTOOL_VERSION BANNERTOOL_SHA256
  if is_current bannertool "$BANNERTOOL_VERSION"; then
    echo "bannertool $BANNERTOOL_VERSION: up to date"
  else
    fetch "https://github.com/Epicpkmn11/bannertool/releases/download/$BANNERTOOL_VERSION/bannertool.zip" \
      "$BANNERTOOL_SHA256" "$WORK/bannertool.zip"
    unzip -q -o "$WORK/bannertool.zip" linux-x86_64/bannertool -d "$WORK/bannertool"
    install -m 755 "$WORK/bannertool/linux-x86_64/bannertool" "$PREFIX/bin/bannertool"
    stamp bannertool "$BANNERTOOL_VERSION"
  fi
fi
