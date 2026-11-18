#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# SYNOPSIS
#   tools/setup-workspace.sh [--toolchain-dir DIR] [--skip-apt] [--jobs N]
#
# DESCRIPTION
#   Installs the dev container's toolchain directly on a Debian trixie host without Docker
#   (the maintainer's Coder workspace, docs/DECISIONS.md D10), with the same pinned versions:
#     - Debian packages from .devcontainer/apt-packages.txt (sudo apt-get)
#     - /opt/devkitpro, extracted from the pinned devkitpro/devkitarm image via the Docker Hub
#       registry API (layer sha256 verified; devkitPro's own servers reject cloud IPs)
#     - /opt/tools (Ruby, Azahar, makerom, bannertool) via .devcontainer/install-tools.sh
#     - /usr/local/bin/azahar-headless
#   Pins are read from the ARG lines of .devcontainer/Dockerfile. Everything is installed into
#   DIR (persistent volume); /opt/devkitpro and /opt/tools are symlinks to it. Idempotent: re-run
#   it after a workspace restart to restore the symlinks and apt packages (seconds when nothing
#   changed). Prints the environment to source at the end and writes it to DIR/env.sh.
#   Uses memguard for the Ruby build if available.
#
# OPTIONS
#   --toolchain-dir DIR  installation directory (default: $HOME/volume/.toolchain)
#   --skip-apt           do not install Debian packages
#   --jobs N             parallel build jobs (default: workspace CPUs from `memguard --info`,
#                        else nproc)
#   -h, --help           show this help
#
# EXAMPLE
#   tools/setup-workspace.sh && . ~/volume/.toolchain/env.sh
set -euo pipefail

usage() {
  sed -n '3,/^set -euo/{/^set -euo/d;s/^# \{0,1\}//;p}' "$0"
}

REPO="$(cd "$(dirname "$0")/.." && pwd)"
TC="${HOME}/volume/.toolchain"
SKIP_APT=0
# default_jobs: prints the workspace's CPU count (memguard knows the container limit; nproc shows
# the node), falling back to nproc.
default_jobs() {
  local n=""
  if command -v memguard >/dev/null; then
    n="$(memguard --info 2>/dev/null | sed -n 's/^cpus: *\([0-9][0-9]*\)$/\1/p')"
  fi
  printf '%s' "${n:-$(nproc)}"
}
JOBS="$(default_jobs)"
while [ $# -gt 0 ]; do
  case "$1" in
    --toolchain-dir) TC="${2:?--toolchain-dir needs a value}"; shift 2 ;;
    --skip-apt) SKIP_APT=1; shift ;;
    --jobs) JOBS="${2:?--jobs needs a value}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "setup-workspace.sh: unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

DOCKERFILE="$REPO/.devcontainer/Dockerfile"

# dockerfile_arg NAME: prints the default value of `ARG NAME=value` in the Dockerfile.
dockerfile_arg() {
  local v
  v="$(sed -n "s/^ARG $1=\(.*\)$/\1/p" "$DOCKERFILE" | head -n1)"
  [ -n "$v" ] || { echo "setup-workspace.sh: ARG $1 not found in $DOCKERFILE" >&2; exit 1; }
  printf '%s' "$v"
}

# install_apt: installs the packages of .devcontainer/apt-packages.txt that are missing.
install_apt() {
  local missing=() p
  while read -r p; do
    dpkg-query -W -f='${Status}' "$p" 2>/dev/null | grep -q 'install ok installed' || missing+=("$p")
  done < <(grep -vE '^[[:space:]]*(#|$)' "$REPO/.devcontainer/apt-packages.txt")
  if [ ${#missing[@]} -eq 0 ]; then
    echo "apt: all packages installed"
    return
  fi
  echo "apt: installing ${#missing[@]} packages"
  sudo apt-get update -qq
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends "${missing[@]}" >/dev/null
}

# registry_token REPO: prints an anonymous Docker Hub pull token for REPO.
registry_token() {
  curl -fsS "https://auth.docker.io/token?service=registry.docker.io&scope=repository:$1:pull" | jq -r .token
}

# install_devkitpro IMAGE DEST: extracts /opt/devkitpro of the linux/amd64 variant of IMAGE
# (name:tag@sha256:digest) into DEST, applying layer whiteouts. Skips if DEST is stamped with IMAGE.
install_devkitpro() {
  local image="$1" dest="$2" repo digest token accept manifest layers layer media tmp wh target patterns
  if [ "$(cat "$dest/.rmxp3ds-image" 2>/dev/null || true)" = "$image" ]; then
    echo "devkitpro: up to date"
    return
  fi
  repo="${image%%:*}"; digest="${image##*@}"
  [ "$digest" != "$image" ] || { echo "setup-workspace.sh: DEVKITARM_IMAGE must be pinned by digest" >&2; exit 1; }
  case "$repo" in */*) ;; *) repo="library/$repo" ;; esac
  token="$(registry_token "$repo")"
  accept='application/vnd.oci.image.index.v1+json,application/vnd.docker.distribution.manifest.list.v2+json,application/vnd.oci.image.manifest.v1+json,application/vnd.docker.distribution.manifest.v2+json'
  manifest="$(curl -fsS -H "Authorization: Bearer $token" -H "Accept: $accept" "https://registry-1.docker.io/v2/$repo/manifests/$digest")"
  if [ "$(jq -r '.manifests != null' <<<"$manifest")" = true ]; then
    digest="$(jq -r '.manifests[] | select(.platform.os=="linux" and .platform.architecture=="amd64") | .digest' <<<"$manifest")"
    manifest="$(curl -fsS -H "Authorization: Bearer $token" -H "Accept: $accept" "https://registry-1.docker.io/v2/$repo/manifests/$digest")"
  fi
  layers="$(jq -r '.layers[] | "\(.digest) \(.mediaType)"' <<<"$manifest")"
  # Leftovers of an earlier failed run, then a temp dir removed on any exit from here on.
  rm -rf "$(dirname "$dest")"/.dkp.*
  tmp="$(mktemp -d "$(dirname "$dest")/.dkp.XXXXXX")"
  local qtmp
  printf -v qtmp '%q' "$tmp"
  # shellcheck disable=SC2064 # expand $tmp now: it is local to this function
  trap "rm -rf $qtmp" EXIT
  mkdir -p "$tmp/root"
  while read -r layer media; do
    case "$media" in
      application/vnd.oci.image.layer.v1.tar+gzip|application/vnd.docker.image.rootfs.diff.tar.gzip) ;;
      *) echo "setup-workspace.sh: unsupported layer type $media in $image" >&2; exit 1 ;;
    esac
    curl -fsSL --retry 3 -H "Authorization: Bearer $token" -o "$tmp/layer.tgz" \
      "https://registry-1.docker.io/v2/$repo/blobs/$layer"
    echo "${layer#sha256:}  $tmp/layer.tgz" | sha256sum -c --quiet -
    # Only opt/devkitpro (and whiteouts directly in opt/, which may delete it) is needed: skip
    # layers without it. The listing goes to a file so a tar error fails the script (set -e).
    tar -tzf "$tmp/layer.tgz" >"$tmp/list"
    # tar fails if a pattern matches nothing, so pass only the patterns this layer contains.
    patterns=()
    if grep -q '^opt/devkitpro' "$tmp/list"; then patterns+=('opt/devkitpro*'); fi
    if grep -q '^opt/\.wh\.' "$tmp/list"; then patterns+=('opt/.wh.*'); fi
    if [ ${#patterns[@]} -gt 0 ]; then
      tar -xzf "$tmp/layer.tgz" -C "$tmp/root" --no-same-owner --wildcards "${patterns[@]}"
    fi
    rm -f "$tmp/layer.tgz"
    # Whiteouts: .wh.NAME deletes NAME from lower layers; .wh..wh..opq empties the directory.
    while IFS= read -r -d '' wh; do
      case "$(basename "$wh")" in
        .wh..wh..opq) echo "setup-workspace.sh: opaque whiteout in $wh is not supported" >&2; exit 1 ;;
        *) target="$(dirname "$wh")/$(basename "$wh" | sed 's/^\.wh\.//')"
           rm -rf "${target:?}" "$wh" ;;
      esac
    done < <(find "$tmp/root" -name '.wh.*' -print0)
  done <<<"$layers"
  [ -x "$tmp/root/opt/devkitpro/devkitARM/bin/arm-none-eabi-gcc" ] \
    || { echo "setup-workspace.sh: devkitARM not found in $image" >&2; exit 1; }
  rm -rf "$dest"
  mv "$tmp/root/opt/devkitpro" "$dest"
  rm -rf "$tmp"
  trap - EXIT
  printf '%s\n' "$image" >"$dest/.rmxp3ds-image"
  echo "devkitpro: installed from $image"
}

mkdir -p "$TC"
[ "$SKIP_APT" -eq 1 ] || install_apt
command -v jq >/dev/null || { echo "setup-workspace.sh: jq is required" >&2; exit 1; }

install_devkitpro "$(dockerfile_arg DEVKITARM_IMAGE)" "$TC/devkitpro"

export RUBY_VERSION RUBY_BUILD_VERSION AZAHAR_VERSION AZAHAR_SHA256 \
  MAKEROM_VERSION MAKEROM_SHA256 BANNERTOOL_VERSION BANNERTOOL_SHA256
for v in RUBY_VERSION RUBY_BUILD_VERSION AZAHAR_VERSION AZAHAR_SHA256 \
         MAKEROM_VERSION MAKEROM_SHA256 BANNERTOOL_VERSION BANNERTOOL_SHA256; do
  printf -v "$v" '%s' "$(dockerfile_arg "$v")"
done
INSTALL=("$REPO/.devcontainer/install-tools.sh" --prefix "$TC/tools" --jobs "$JOBS")
if command -v memguard >/dev/null; then
  memguard -- "${INSTALL[@]}"
else
  "${INSTALL[@]}"
fi

# link TARGET LINK: points the symlink LINK at TARGET; refuses to replace a real file or directory
# (ln -sfn would create the link inside an existing directory instead).
link() {
  if [ -e "$2" ] && [ ! -L "$2" ]; then
    echo "setup-workspace.sh: $2 exists and is not a symlink; move it away and re-run" >&2
    exit 1
  fi
  sudo ln -sfn "$1" "$2"
}
link "$TC/devkitpro" /opt/devkitpro
link "$TC/tools" /opt/tools
link "$REPO/.devcontainer/azahar-headless.sh" /usr/local/bin/azahar-headless

if [ -f "$REPO/.devcontainer/azahar/qt-config.ini" ] && [ ! -f "$HOME/.config/azahar-emu/qt-config.ini" ]; then
  mkdir -p "$HOME/.config/azahar-emu"
  cp "$REPO/.devcontainer/azahar/qt-config.ini" "$HOME/.config/azahar-emu/"
fi

cat >"$TC/env.sh" <<'ENV'
# Generated by tools/setup-workspace.sh; same environment as the dev container image.
export DEVKITPRO=/opt/devkitpro
export DEVKITARM=/opt/devkitpro/devkitARM
export AZAHAR_HOME=/opt/tools/azahar
export AZAHAR_DISPLAY="${AZAHAR_DISPLAY:-:99}"
case ":$PATH:" in
  *":/opt/devkitpro/tools/bin:"*) ;;
  *) export PATH="/opt/tools/bin:/opt/tools/ruby/bin:/opt/devkitpro/tools/bin:/opt/devkitpro/devkitARM/bin:$PATH" ;;
esac
ENV
echo "done. Load the environment with:  . $TC/env.sh"
