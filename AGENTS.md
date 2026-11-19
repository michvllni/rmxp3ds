<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
# AGENTS.md — rmxp3ds

Guide for coding agents. Plan: [docs/PLAN.md](docs/PLAN.md). Decisions: [docs/DECISIONS.md](docs/DECISIONS.md).
Status, findings, measurements, sources: [NOTES.md](NOTES.md).

## Repositories
- **rmxp3ds** (this repo, GPL-3.0): plan, converter, patch sets, depth profiles, tools, CI.
- **mkxp-z-3ds** (`runtime/`, git submodule, GPL-2.0-or-later): fork of mkxp-z, the 3DS runtime.
  Default branch `dev`. Runtime changes: PR on the fork first, then a separate PR here that
  bumps the submodule pointer.
- **mcp-azahar** (maintainer's repo): MCP server + CLI that drives Azahar. Use it, never change it;
  request missing features from the maintainer.

## Layout
```
.devcontainer/   Dockerfile (all version pins), apt-packages.txt, install-tools.sh (shared with the
                 workspace setup), devcontainer.json (portable), linux-host/ (opt-in /dev/dri + host
                 network), azahar-headless.sh, azahar/ (qt-config.ini seed)
.github/         CI workflows
runtime/         submodule: mkxp-z-3ds
convert/         converter (Ruby)                      — from M5
tools/           setup-workspace.sh, bench/ (Ruby test app), m2/ (headless game harness, M2),
                 sdlcheck/ (SDL2 utility libraries test app, M3), hw3/ (hardware run 3 kit, M3),
                 title/ (real game to its title screen, M3 exit)
tests/           fixtures (synthetic only), golden images
docs/            PLAN.md, DECISIONS.md
```

## Environment
- Reference: the dev container (`.devcontainer/`). CI builds the same image.
- Maintainer's Coder workspace (no Docker): `tools/setup-workspace.sh` installs the same pinned
  toolchain into `~/volume/.toolchain` (persistent) and links `/opt/devkitpro`, `/opt/tools`.
  Re-run it after a workspace restart, then `. ~/volume/.toolchain/env.sh`.
- Both environments: `/opt/devkitpro` (devkitARM, libctru, citro3d, portlibs), `/opt/tools/ruby`
  (host Ruby = runtime's Ruby), `/opt/tools/azahar`, `/opt/tools/bin` (makerom, bannertool).
- Gems: in the image `/opt/tools` is root-owned, so `GEM_HOME=/home/dev/.gem`; in the workspace
  gems go to `/opt/tools/ruby` (user-owned volume). Prefer `bundle config set path vendor/bundle`.
- Windows hosts: only via WSL2 (scripts need LF, `.gitattributes` enforces it).
- Changing a version: edit the `ARG` in `.devcontainer/Dockerfile` (single source of truth), update
  NOTES.md with the source, re-run `tools/setup-workspace.sh`.
- devkitPro's own servers (devkitpro.org, pkg/apt.devkitpro.org) answer 403 from cloud IPs: never
  call `dkp-pacman` in CI or scripts; everything comes from the pinned `devkitpro/devkitarm` image.
- Heavy commands in the Coder workspace go through `memguard -- <cmd>` (4 GiB limit); use
  `$MEMGUARD_CPUS` for `-j`.

## Build / test / run
| What | Command |
|---|---|
| Workspace toolchain | `tools/setup-workspace.sh && . ~/volume/.toolchain/env.sh` |
| Build hello-world | `cmake -S tools/hello -B build/hello -G Ninja -DCMAKE_TOOLCHAIN_FILE="$DEVKITPRO/cmake/3DS.cmake" && cmake --build build/hello` |
| Emulator smoke test | `tests/smoke/azahar-smoke.sh --3dsx build/hello/hello.3dsx --result rmxp3ds/test/hello.txt --expect '^RMXP3DS_TEST hello PASS' --screenshot build/hello-smoke.png` (`--sd-file SRC=DEST` / `--sd-dir SRC=DEST` put files or directories on the virtual SD) |
| CRuby for 3DS (fork) | `runtime/3ds/ruby/build.sh --jobs "$MEMGUARD_CPUS"` (via `memguard --`) → `runtime/build-3ds/ruby/` |
| SDL2 libraries for 3DS (fork) | `runtime/3ds/deps/build.sh --jobs "$MEMGUARD_CPUS"` (via `memguard --`) → `runtime/build-3ds/deps/prefix/` |
| Runtime (mkxp-z for 3DS, fork) | after the CRuby and deps builds: `cmake -S runtime/3ds -B runtime/build-3ds/mkxp -G Ninja -DCMAKE_TOOLCHAIN_FILE="$DEVKITPRO/cmake/3DS.cmake" && cmake --build runtime/build-3ds/mkxp` → `mkxp-z.3dsx` (see `runtime/3ds/README.md`) |
| Runtime engine check in Azahar | `tests/smoke/azahar-smoke.sh --3dsx runtime/build-3ds/mkxp/mkxp-z.3dsx --result rmxp3ds/test/mkxp.txt --expect '^RMXP3DS_TEST mkxp PASS' --sd-file tests/runtime/enginecheck/mkxp.json=rmxp3ds/game/mkxp.json --sd-file tests/runtime/enginecheck/enginecheck.rb=rmxp3ds/game/enginecheck.rb --timeout 300` |
| Runtime render check in Azahar | `ruby tests/runtime/rendercheck/make-transmap.rb --out build/trans-map.png`, then as the engine check with `tests/runtime/rendercheck/{mkxp.json,rendercheck.rb}` plus `--sd-file build/trans-map.png=rmxp3ds/game/trans-map.png`, `--result rmxp3ds/test/render.txt --expect '^RMXP3DS_TEST render PASS' --screenshot build/render.png` (Bitmap ops, blt, VRAM pressure, effects, transitions; final scene: quadrants red top left, green top right, blue bottom left, white bottom right) |
| Runtime title check in Azahar | `ruby tests/runtime/titlecheck/make-assets.rb --out-dir build/titlecheck`, then as the engine check with `tests/runtime/titlecheck/{mkxp.json,titlecheck.rb}` plus `--sd-file build/titlecheck/title.png=rmxp3ds/game/Graphics/Titles/title.png --sd-file build/titlecheck/windowskin.png=rmxp3ds/game/Graphics/Windowskins/windowskin.png`, `--result rmxp3ds/test/title.txt --expect '^RMXP3DS_TEST title PASS' --screenshot build/title.png` (synthetic title scene: title image, command window, cursor, fades) |
| Hardware run 3 (M3) | `tools/hw3/hw3.sh azahar` validates the kit in Azahar; `tools/hw3/hw3.sh kit --out build/hw3` writes the SD layout (engine, render, title checks, frame times, HOME/sleep window; results in `sdmc:/rmxp3ds/test/hw3.txt`) |
| Real game to its title screen (M3 exit, D16) | `tools/title/title.sh azahar --game DIR --height 384` (Essentials: 512×384) runs a local game copy in Azahar until the preload probe reports the title (`realtitle.txt`, step log `realtitle-log.txt`); `tools/title/title.sh kit --height 384 --out build/title-kit` writes a console kit without game files |
| SDL2 libraries test app | `cmake -S tools/sdlcheck -B build/sdlcheck -G Ninja -DCMAKE_TOOLCHAIN_FILE="$DEVKITPRO/cmake/3DS.cmake" && cmake --build build/sdlcheck`; in Azahar: `tests/smoke/azahar-smoke.sh --3dsx build/sdlcheck/sdlcheck.3dsx --result rmxp3ds/test/sdlcheck.txt --expect '^RMXP3DS_TEST sdlcheck PASS' --timeout 300` |
| Ruby test/bench app | `cmake -S tools/bench -B build/bench -G Ninja -DCMAKE_TOOLCHAIN_FILE="$DEVKITPRO/cmake/3DS.cmake" && cmake --build build/bench` |
| Ruby test in Azahar | `tests/smoke/azahar-smoke.sh --3dsx build/bench/bench.3dsx --result rmxp3ds/test/rubybench.txt --expect '^RMXP3DS_TEST rubybench PASS' --timeout 600` (add `--sd-file SRC=rmxp3ds/test/NAME` to run scripts/fixtures from SD) |
| Synthetic map fixture | `ruby tests/fixtures/make-rxdata.rb --out FILE` |
| Synthetic game (M2 pipeline) | `ruby tests/fixtures/make-game.rb --out build/m2/synthetic-game` |
| Headless game benchmark (M2) | `tools/m2/m2.sh host\|azahar --game DIR [--bench essentials\|synthetic] [--env K=V]`; `tools/m2/m2.sh kit --out DIR` for the console (see `--help`) |
| Lint scripts | `git ls-files '*.sh' \| xargs shellcheck` |
| Headless emulator | `azahar-headless <file.3dsx>`; screenshots via mcp-azahar |
| Console | `3dslink -a <3ds-ip> <file.3dsx>`; test output (stderr): `3dslink -s` |

CI (`.github/workflows/ci.yml`): shellcheck; dev container image build, hello-world build and
Azahar smoke test, CRuby 3DS build, Ruby test/bench in Azahar with scripts from SD, M2 pipeline
with a synthetic game (host and Azahar digests must match), SDL2 libraries build and
`tools/sdlcheck` in Azahar, the runtime (`mkxp-z.3dsx`) with the engine, render and title checks in Azahar, all inside
the image (`.3dsx` and screenshots uploaded as artifact `smoke-tests`). Fill in this table as milestones add targets.

## Conventions
- Conventional Commits; one reviewable topic per PR; docs (README, AGENTS, NOTES, docs/*) updated in
  the same commit as the change.
- Branch from the up-to-date default branch (`git fetch --prune` first): `main` here, `dev` in the fork.
  Squash-merge, delete branch, only when every check on the head commit is SUCCESS.
- SPDX header on every new source file (`GPL-3.0-or-later` here, `GPL-2.0-or-later` in the fork).
- Third-party code: check its license, record origin and license in `THIRD_PARTY.md` before copying.
- Scripts: usage/help block, `set -euo pipefail`, `-h/--help`.
- Pin every external version (image digest, release tag + checksum) and cite the source in NOTES.md.
  Never guess APIs, flags or formats: check source/docs/`--help`.

## Rules (short)
- **No game content** in the repo, PRs, CI logs or releases: no game data, graphics, audio, RTP,
  Essentials scripts, ROMs. CI uses synthetic fixtures generated by scripts here. Real games live in
  `/workspaces/games` (bind mount) or outside the repo, for local tests only.
- Emulator results prove correctness only; performance numbers count only from a real New 3DS.
- 3DS constraints: New 3DS only, limited app memory (see NOTES.md), PICA200 without programmable
  fragment shaders, textures ≤ 1024 px power-of-two, two usable cores.
- Ask the maintainer before: releases/tags, publishing CIAs/UniStore, deleting anything, PRs/issues on
  upstream or other repos, settings/secrets, disabling upstream workflows in the fork, and decisions
  that change docs/DECISIONS.md.
- M2 is a go/no-go gate decided by the maintainer.

## Self-reporting test mode
Test programs (hello now, the runtime later) write one line `RMXP3DS_TEST <name> PASS|FAIL ...` to
`sdmc:/rmxp3ds/test/<name>.txt`, show it on screen and, when started via `3dslink -s`, send it to
stderr (redirected to the PC; stdout stays on the screen console). If
`sdmc:/rmxp3ds/test/autoexit` exists they exit by themselves a few seconds after reporting.
`tests/smoke/azahar-smoke.sh` drives this in headless Azahar (fresh HOME, virtual SD and free X
display per run).

## Debugging on 3DS/Azahar
`tools/bench` appends progress markers to `sdmc:/rmxp3ds/test/rubybench-stage.txt` and, without
3dslink, redirects stderr (Ruby `[BUG]` reports, warnings) to `rubybench-stderr.txt`; run the
smoke script with `--keep-home` and read them from the kept virtual SD. Ruby scripts placed on
SD (`--sd-file`) override the romfs copies without rebuilding. If `sdmc:/rmxp3ds/test/main.rb` exists, `bench.3dsx` runs only
that script (after its native checks): the entry point for other Ruby test programs.

## Pitfalls
- Headless game scripts (`tools/m2/rgss_headless.rb`): stand-ins must not define
  `respond_to_missing?` (it makes `defined?` lie and games skip their own aliases), and the game
  clock (`System.uptime`) only advances with `Graphics.update`: a loop that polls the clock
  without drawing frames never ends.
- Azahar stays open after a homebrew app exits and aborts on SIGTERM: judge runs by the result
  file, never by the emulator's exit status. Don't `pkill -f azahar` from a shell whose command
  line contains "azahar" (it kills itself); stop emulators by PID or process group.
- A corrupt `.3dsx` can make Azahar allocate GiBs until the timeout: run it under `memguard` in the
  workspace.
- Files extracted from an AppImage keep mode 0700; `install-tools.sh` opens them for other users.
- CRuby on 3DS: Ruby `Thread`s work but are not preempted (no timer pipe: a busy thread runs
  until it blocks or passes); deep C recursion can overflow the stack without SystemStackError;
  GCC turns tail recursion into loops at -O2 (stack probes need a non-tail call). See `runtime/3ds/ruby/README.md`.
- `runtime/` uses an HTTPS URL; a local `url.git@github.com:.insteadOf` rewrite is fine.
- Stacked PRs: retarget the PR stacked on top (`gh pr edit N --base dev`) before merging the
  one below with `--delete-branch`. Deleting a PR's base branch closes it, and a closed PR's base
  can't be changed. After a squash merge, rebase the upper branch with
  `git rebase --onto origin/dev <old-lower-head>`.
- `/opt` in the Coder workspace is not persistent; only `/home/vscode/volume` is.
