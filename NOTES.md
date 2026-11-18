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
| Dev container base | `debian:trixie-20261027-slim@sha256:f6b08b09a05725f9431502d3b5714f5c4576e82c1a84fa1debe0c24a7e0c3ec4` (glibc 2.41) | Docker Hub tags API |
| devkitARM image (source of `/opt/devkitpro`) | `devkitpro/devkitarm:20260610`, index digest `sha256:116afba8df8453961de2936ffab20dd441edf4d682856c1ec8b0e53d7ed0bbf5` (amd64 manifest `sha256:15b79ce7…0761b`), itself Debian bookworm; its binaries run on trixie | Docker Hub tags API; image config history; hello-world build in the workspace |
| devkitARM | r68 (arm-none-eabi-gcc 16.1.0) | pacman local db in image |
| libctru / citro3d / citro2d | 2.7.0 / 1.7.1 / 1.7.0 | pacman local db in image |
| tex3ds / picasso / 3dstools / 3dslink | 2.3.0 / 2.7.2 / 1.3.1 / 0.6.3 | pacman local db in image |
| 3DS portlibs (in image via `3ds-portlibs`) | 3ds-zlib 1.3.1, 3ds-libpng 1.6.53, 3ds-freetype 2.14.1, 3ds-libogg 1.3.6, 3ds-libvorbisidec 1.2.1 (Tremor; no full libvorbis), 3ds-bzip2 1.0.8, 3ds-physfs 3.2.0, 3ds-libiconv 1.17, 3ds-pkg-config 0.28 | pacman local db in image |

| ruby-build | `v20261023` | github.com/rbenv/ruby-build/releases |
| Ruby (runtime + host baseruby) | **3.1.3** (upstream `ruby/ruby` tag `v3_1_3` + mkxp-z patches), not 3.1.6 | `runtime/subprojects/ruby-3.1.wrap` line 2; `runtime/meson_options.txt` line 1 `mri_version='3.1'` (mkxp-z `dev` @ 3c7c47c) |
| Azahar | `2126.2` (2026-10-08), `azahar.AppImage` sha256 `af037f8b775198f636b14bcfe63fb401b02246ebfefe1025bb905ce042556960`; needs glibc ≥ 2.38 (not bookworm) | github.com/azahar-emu/azahar/releases/tag/2126.2 |
| Azahar paths | config `~/.config/azahar-emu/qt-config.ini`, user dir `~/.local/share/azahar-emu/` (sdmc/, nand/); `./user/` in CWD = portable mode | Azahar 2126.2 `src/common/file_util.cpp` 966–1030, `src/citra_qt/configuration/config.cpp` 107 |
| Azahar CLI | `azahar [options] <file>`; no headless flag, needs an X display | `src/citra_qt/citra_qt.cpp` 270–395 @ 2126.2 |
| makerom | `v0.19.0` (2026-01-18), `makerom-v0.19.0-ubuntu_x86_64.zip` sha256 `287b809dec064e0ad597e3d272c49ecb7eed41693d5ee6fef9d8a8aa24c2497e`, binary at zip root; needs glibc ≥ 2.38 | github.com/3DSGuy/Project_CTR/releases |
| GitHub Actions | checkout v7.0.1 `3d3c42e5`, setup-buildx-action v4.4.1 `f87e5991`, build-push-action v7.4.0 `c3c9e263` (pinned by SHA) | GitHub releases API |
| bannertool | Epicpkmn11 `v1.2.2` (2022-05-18), `bannertool.zip` sha256 `e4259c08fe8944ebadd5f4b96f9a8603e5427338074cfc46323fbbc3410d51ed` (computed, not published), binary `linux-x86_64/bannertool` | github.com/Epicpkmn11/bannertool/releases |

### Notes on the pins
- Azahar's extracted AppImage still needs host libraries (libEGL, libGLX, libOpenGL, libX11-xcb,
  libxcb-dri3, libwayland-client, libdrm, libSM, libICE); found with `ldd` on trixie, listed in
  `.devcontainer/apt-packages.txt`.
- ruby-build's 3.1.3 definition builds its own OpenSSL 3.0.18 only for OpenSSL < 1.0.2 or > 3.x;
  trixie's OpenSSL 3.5 is used. ruby-build warns that 3.1.3 is end-of-life; we keep it because
  the runtime must match mkxp-z's embedded Ruby (host Ruby is a local build tool only).
- The bannertool `v1.2.2` release binary prints `bannertool v1.2.0`; the sha256 pins the file.
- First CI image build (PR #2, 2026-11-18): 4m50s on ubuntu-24.04, all build-time checks pass.
- `tools/setup-workspace.sh` (2026-11-18, workspace): full install peak 2.8 GiB (Ruby build), re-run
  1.5 s when nothing changed.

## Verification log
- **2026-11-18, workspace (rmxp3ds `feat/m0-dev-environment`):** devkitPro example
  `graphics/printing/hello-world` builds; `azahar-headless hello.3dsx` (Azahar 2126.2, Xvfb, Mesa
  llvmpipe, OpenGL) shows "Hello World!" on the top screen, status bar "App: 60 FPS" (emulator, not
  a performance number). Launched manually; mcp-azahar is not configured yet.

- **2026-11-18, workspace (rmxp3ds `feat/m0-hello-smoke`):** `tools/hello` (CMake, devkitPro
  `3DS.cmake`, `-Werror`) builds; `tests/smoke/azahar-smoke.sh` passes twice in a row
  (`RMXP3DS_TEST hello PASS frames=60 new3ds=1`, Azahar reports New 3DS by default), negative check
  (`--expect '^NOPE'`) fails with exit 1, no processes left behind. ~5 s per run.
- Azahar behaviour (2126.2): stays open (game list) after a 3dsx returns from `main`; SIGTERM
  makes it abort (exit 134 / SIGSEGV). `setsid` is unreliable for process-group cleanup (it forks
  if the caller leads a process group); bash job control (`set -m`) gives PGID = `$!`.

## M1 research: CRuby 3.1.3 on 3DS (2026-11-18, desk research, nothing built yet)
- **Prior art:** no CRuby on 3DS; RGSS-on-3DS projects use mruby
  (github.com/Disclored/RPG-Maker-XP-for-3DS, github.com/roperario233/rgss1-3ds). CRuby 3.1 on
  newlib targets: mkxp-z Switch port (github.com/Cheeenxiii/rmxp-modern
  `patches/mkxp-z-switch/0002-ruby-libnx.patch`, GPL-2.0+, emulator only), Vita ports
  github.com/Asukate/mkxp-z-vita (`deps/ruby-vita-a2d396e-clean.patch`, GPL-2.0+, ran on hardware)
  and github.com/Pinol0/LISA-Vita (Ruby 3.1.6, GPL-2.0). Licenses compatible with the fork; record
  in THIRD_PARTY.md before reusing any code.
- **Toolchain facts (verified in the image):** devkitARM `libsysbase.a` implements `pthread_*`,
  `clock_gettime`, `nanosleep`, `getcwd` on libctru `__syscall_thread_create`; no `dlopen`, `mmap`,
  `sigaction`, `sys/mman.h`. Ruby 3.1 has no `thread_none.c` (added in 3.2).
- **Configure (proposal):** `--host=arm-none-eabi --disable-shared --with-static-linked-ext
  --disable-dln --disable-jit-support --disable-rubygems --without-gmp --with-coroutine=arm32`,
  ext zlib only (RGSS1 needs Marshal = core, Zlib = ext; mkxp-z `binding/binding-mri.cpp:288`),
  `-specs=3dsx.specs` in LDFLAGS (link tests), `ac_cv_*` overrides for fork/mmap/sigaction/dlopen.
- **Expected patches:** shim for `sys/mman.h`/`waitpid`/`pthread_kill`/`pipe`; stack bounds
  (`ruby_init_stack` finds no size → overflow detection off); no signal-based timer; arm32
  coroutine must save d8–d15 under hard-float AAPCS (Asukate patch); devkitARM short enums break
  `compile.c` `IS_INSN_ID` (Vita report, short enums confirmed with `_Static_assert`); transient
  heap 32 MB → 4 MB; `sdmc:/` as absolute path; optional `PS_GenerateRandomBytes` seeding.
- **Risks:** stack sizes (libctru main thread 32 KB, SDL2 n3ds threads 80 KB default); GVL hand-off
  on the 3DS app core (no time slicing between equal priorities, unverified); app memory for .3dsx
  on New 3DS (unverified); encoding tables size; libctru 2.7.1 (2026-11-01) newer than pinned 2.7.0.

## Measurements
_None yet. Console numbers only, with date, commits of both repos and settings._
