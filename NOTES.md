<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
# NOTES — status, findings, measurements, sources

Newest first within each section. Dates are absolute. Replaces `docs/STATUS.md` from PLAN §10.

## Status
- **2026-11-18:** Bootstrap. Repo layout, submodule `runtime/` → mkxp-z-3ds `dev` @ `3c7c47c`.
  Environment decided (D10). M0 in progress.

## Environment findings (2026-11-18)
- **Coder workspace:** Kubernetes pod (AKS), Debian 13, 4 GiB memory limit, 3 CPUs, no Docker, no
  `/dev/dri`, no route to the maintainer's LAN (3dslink must run from a LAN machine). Only
  `/home/vscode/volume` persists across restarts.
- **devkitPro hosts block cloud IPs:** `devkitpro.org`, `apt.devkitpro.org`, `pkg.devkitpro.org`
  return HTTP 403 from the workspace. Docker Hub and GitHub work. Consequence: no `dkp-pacman`
  anywhere; the toolchain comes from the `devkitpro/devkitarm` image.
- **Coder dev container options** (Coder docs v2.39, envbuilder v1.3.0):
  - Dev Containers integration needs Docker in the workspace (Sysbox/privileged).
    https://coder.com/docs/admin/templates/managing-templates/devcontainers ,
    https://coder.com/docs/admin/templates/extending-templates/docker-in-workspaces
  - envbuilder needs no daemon but is in maintenance mode; it ignores `mounts`, `runArgs`,
    `initializeCommand`. https://github.com/coder/envbuilder/blob/main/docs/devcontainer-spec-support.md
  - devcontainer CLI: a missing bind-mount source fails container creation
    (https://github.com/devcontainers/cli/issues/613); `initializeCommand` runs on the host
    (https://containers.dev/implementors/json_reference/); multiple configs as
    `.devcontainer/<name>/devcontainer.json` (https://containers.dev/implementors/spec/).

## Pinned versions and sources
| Item | Value | Source |
|---|---|---|
| devkitARM image | `devkitpro/devkitarm:20260610`, index digest `sha256:116afba8df8453961de2936ffab20dd441edf4d682856c1ec8b0e53d7ed0bbf5` (amd64 manifest `sha256:15b79ce7…0761b`), base Debian bookworm | Docker Hub tags API; image config history |
| devkitARM | r68 (arm-none-eabi-gcc 16.1.0) | pacman local db in image |
| libctru / citro3d / citro2d | 2.7.0 / 1.7.1 / 1.7.0 | pacman local db in image |
| tex3ds / picasso / 3dstools / 3dslink | 2.3.0 / 2.7.2 / 1.3.1 / 0.6.3 | pacman local db in image |
| 3DS portlibs (in image via `3ds-portlibs`) | 3ds-zlib 1.3.1, 3ds-libpng 1.6.53, 3ds-freetype 2.14.1, 3ds-libogg 1.3.6, 3ds-libvorbisidec 1.2.1 (Tremor; no full libvorbis), 3ds-bzip2 1.0.8, 3ds-physfs 3.2.0, 3ds-libiconv 1.17, 3ds-pkg-config 0.28 | pacman local db in image |

### Pending pins (M0 dev environment PR)
| Item | Value | Source |
|---|---|---|
| Ruby (runtime + host baseruby) | **3.1.3** (upstream `ruby/ruby` tag `v3_1_3` + mkxp-z patches), not 3.1.6 | `runtime/subprojects/ruby-3.1.wrap` line 2; `runtime/meson_options.txt` line 1 `mri_version='3.1'` (mkxp-z `dev` @ 3c7c47c) |
| Azahar | `2126.2` (2026-10-08), `azahar.AppImage` sha256 `af037f8b775198f636b14bcfe63fb401b02246ebfefe1025bb905ce042556960`; needs glibc ≥ 2.38 (not bookworm) | github.com/azahar-emu/azahar/releases/tag/2126.2 |
| Azahar paths | config `~/.config/azahar-emu/qt-config.ini`, user dir `~/.local/share/azahar-emu/` (sdmc/, nand/); `./user/` in CWD = portable mode | Azahar 2126.2 `src/common/file_util.cpp` 966–1030, `src/citra_qt/configuration/config.cpp` 107 |
| Azahar CLI | `azahar [options] <file>`; no headless flag, needs an X display | `src/citra_qt/citra_qt.cpp` 270–395 @ 2126.2 |
| makerom | `v0.19.0` (2026-01-18), `makerom-v0.19.0-ubuntu_x86_64.zip` sha256 `287b809dec064e0ad597e3d272c49ecb7eed41693d5ee6fef9d8a8aa24c2497e`, binary at zip root; needs glibc ≥ 2.38 | github.com/3DSGuy/Project_CTR/releases |
| bannertool | Epicpkmn11 `v1.2.2` (2022-05-18), `bannertool.zip` sha256 `e4259c08fe8944ebadd5f4b96f9a8603e5427338074cfc46323fbbc3410d51ed` (computed, not published), binary `linux-x86_64/bannertool` | github.com/Epicpkmn11/bannertool/releases |

## Measurements
_None yet. Console numbers only, with date, commits of both repos and settings._
