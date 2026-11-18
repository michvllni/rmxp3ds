<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
# Decisions

Decisions that shape the project. Changing one needs the maintainer's approval; record the
answer here with the date. Background and details: [PLAN.md](PLAN.md).

| # | Date | Decision | Why / notes |
|---|---|---|---|
| D1 | 2026-11-18 | **Two repositories.** `rmxp3ds` (this repo: plan, converter, patch sets, depth profiles, tools, CI) and `mkxp-z-3ds` (fork of mkxp-z, the runtime), included here as the git submodule `runtime/`. Runtime changes go through a PR on the fork first, then a separate PR here bumps the submodule pointer. | Keeps the fork rebaseable on upstream mkxp-z and its license separate. PLAN §8. |
| D2 | 2026-11-18 | **Licenses.** `rmxp3ds`: GPL-3.0. `mkxp-z-3ds`: GPL-2.0-or-later (inherited from mkxp-z). Every new source file carries an SPDX header. Third-party code is recorded in `THIRD_PARTY.md` before it is copied. Avoid GPL-3.0-only code in the runtime (e.g. RetroArch `ctr_svchax.c`) unless the maintainer agrees. | PLAN §9. |
| D3 | 2026-11-18 | **New Nintendo 3DS only.** Old 3DS is out of scope until after M4. | CPU, RAM and second core budget. PLAN §1, §2. |
| D4 | 2026-11-18 | **RGSS1 only** (RPG Maker XP, Pokémon Essentials). No RGSS2/RGSS3. | PLAN §1. |
| D5 | 2026-11-18 | **CRuby via mkxp-z**, cross-compiled for `arm-none-eabi` (newlib/libctru), same Ruby version as mkxp-z embeds. mruby only as a fallback if CRuby proves infeasible. | Compatibility with Essentials scripts; ISeq precompile needs the identical version. PLAN §3.1. |
| D6 | 2026-11-18 | **citro3d renderer** replaces OpenGL; native `Tilemap`, `Sprite`, `Plane`, `Window`, `Viewport`; tone/blend via TEV combiners. | PICA200 has no programmable fragment shaders, textures ≤ 1024 px, power-of-two. PLAN §3.1. |
| D7 | 2026-11-18 | **Dual-core snapshot rendering.** Core 0 runs Ruby and produces an immutable frame snapshot; core 1 uploads dirty textures and renders both eyes. Ruby never waits on the GPU. | gpSP 3D pattern. PLAN §3.1. |
| D8 | 2026-11-18 | **Converter in Ruby** (`convert/`), with native `Marshal` access to `.rxdata` and minimal RGSS class stubs. | PLAN §3.2. |
| D9 | 2026-11-18 | **Agent testing with headless Azahar + mcp-azahar** inside the dev container; the runtime's self-reporting test mode for repeatable tests on emulator and console. Emulator results prove correctness only; performance numbers count only from a real New 3DS. | PLAN §6. |
| D10 | 2026-11-18 | **Development environment.** The dev container (`.devcontainer/`) is the reference environment: CI builds and uses its image, and it works with local Docker (devcontainer CLI / VS Code). The maintainer's Coder workspace (Kubernetes pod, no Docker, no `/dev/dri`) does not run the container; the toolchain is installed directly in the workspace following the Dockerfile, with the same pinned versions (`tools/setup-workspace.sh`). The default `devcontainer.json` stays portable; GPU access and host networking are an opt-in variant in `.devcontainer/gpu/`. | Maintainer's choice (2026-11-18) over an envbuilder template or Docker-in-workspace. Risk: drift between workspace and image; mitigated by one script and the pinned versions shared with the Dockerfile, and by CI as the gate. |
| D11 | 2026-11-18 | **M2 is a go/no-go gate.** The maintainer decides on continue / scope down / alternative based on console measurements. | PLAN §4. |
