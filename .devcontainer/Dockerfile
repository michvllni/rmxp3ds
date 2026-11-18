# SPDX-License-Identifier: GPL-3.0-or-later
# Dev container for rmxp3ds: devkitARM + libctru/citro3d + 3DS portlibs, host Ruby (converter,
# baseruby for the CRuby cross build), 3DS packaging tools and a headless Azahar emulator.
#
# All pins live in the ARGs below. tools/setup-workspace.sh parses them to install the same
# versions in the Coder workspace (docs/DECISIONS.md D10), so keep the `ARG NAME=value` format.
# Sources for every value: NOTES.md "Pinned versions and sources".
#
# Base is Debian trixie, not the bookworm-based devkitarm image: Azahar 2126.2 and makerom 0.19.0
# need glibc >= 2.38. devkitPro's toolchain is copied from its image (devkitPro's package servers
# reject cloud IPs, so dkp-pacman is never used).

ARG DEVKITARM_IMAGE=devkitpro/devkitarm:20260610@sha256:116afba8df8453961de2936ffab20dd441edf4d682856c1ec8b0e53d7ed0bbf5
ARG BASE_IMAGE=debian:trixie-20261027-slim@sha256:f6b08b09a05725f9431502d3b5714f5c4576e82c1a84fa1debe0c24a7e0c3ec4

FROM ${DEVKITARM_IMAGE} AS devkitpro

FROM ${BASE_IMAGE}

# Must match the Ruby version mkxp-z embeds (runtime/subprojects/ruby-3.1.wrap), so ISeq binaries load.
ARG RUBY_VERSION=3.1.3
ARG RUBY_BUILD_VERSION=v20261023
ARG AZAHAR_VERSION=2126.2
ARG AZAHAR_SHA256=af037f8b775198f636b14bcfe63fb401b02246ebfefe1025bb905ce042556960
ARG MAKEROM_VERSION=v0.19.0
ARG MAKEROM_SHA256=287b809dec064e0ad597e3d272c49ecb7eed41693d5ee6fef9d8a8aa24c2497e
ARG BANNERTOOL_VERSION=v1.2.2
ARG BANNERTOOL_SHA256=e4259c08fe8944ebadd5f4b96f9a8603e5427338074cfc46323fbbc3410d51ed

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8

COPY apt-packages.txt /tmp/apt-packages.txt
RUN apt-get update \
    && grep -vE '^[[:space:]]*(#|$)' /tmp/apt-packages.txt | xargs apt-get install -y --no-install-recommends \
    && rm -rf /var/lib/apt/lists/* /tmp/apt-packages.txt

COPY --from=devkitpro /opt/devkitpro /opt/devkitpro

COPY install-tools.sh /usr/local/lib/rmxp3ds/install-tools.sh
RUN RUBY_VERSION="${RUBY_VERSION}" RUBY_BUILD_VERSION="${RUBY_BUILD_VERSION}" \
    AZAHAR_VERSION="${AZAHAR_VERSION}" AZAHAR_SHA256="${AZAHAR_SHA256}" \
    MAKEROM_VERSION="${MAKEROM_VERSION}" MAKEROM_SHA256="${MAKEROM_SHA256}" \
    BANNERTOOL_VERSION="${BANNERTOOL_VERSION}" BANNERTOOL_SHA256="${BANNERTOOL_SHA256}" \
    /usr/local/lib/rmxp3ds/install-tools.sh --prefix /opt/tools

COPY azahar-headless.sh /usr/local/bin/azahar-headless
RUN chmod 755 /usr/local/bin/azahar-headless

ENV DEVKITPRO=/opt/devkitpro \
    DEVKITARM=/opt/devkitpro/devkitARM \
    AZAHAR_HOME=/opt/tools/azahar \
    AZAHAR_DISPLAY=:99 \
    GEM_HOME=/home/dev/.gem \
    PATH=/home/dev/.gem/bin:/opt/tools/bin:/opt/tools/ruby/bin:/opt/devkitpro/tools/bin:/opt/devkitpro/devkitARM/bin:${PATH}

# Fail the build early if a key tool is missing or cannot run on this base.
RUN arm-none-eabi-gcc --version >/dev/null \
    && tex3ds --help >/dev/null \
    && 3dsxtool 2>&1 | grep -q Usage \
    && for t in 3dslink smdhtool picasso; do command -v "$t" >/dev/null || exit 1; done \
    && makerom 2>&1 | grep -qi makerom \
    && bannertool 2>&1 | grep -qi bannertool \
    && ruby -e 'exit(RUBY_VERSION == ENV.fetch("RUBY_VERSION") ? 0 : 1)' \
    && test -x /opt/tools/azahar/AppRun \
    && ! ldd /opt/tools/azahar/usr/bin/azahar | grep 'not found'

# Non-root user for local Docker and CI (devcontainer CLI maps it to the host UID). /opt/tools is
# root-owned, so gems go to GEM_HOME in the user's home (set above).
RUN useradd --create-home --shell /bin/bash --uid 1000 dev
USER dev
WORKDIR /workspaces/rmxp3ds
