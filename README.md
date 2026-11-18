# rmxp3ds

Runtime and converter to play RPG Maker XP games (primarily Pokémon Essentials fan games) on the
New Nintendo 3DS, with optional per-layer stereoscopic 3D.

**Status:** early development. M0 (toolchain, CI) and M1 (CRuby 3.1.3 on the 3DS) run on the
console. M2 (go/no-go benchmark): a real game's scripts run headlessly on the emulated 3DS
(`tools/m2`); console measurements pending. Nothing playable yet. See
[NOTES.md](NOTES.md) for the current state and [docs/PLAN.md](docs/PLAN.md) for the roadmap.

## Repositories
- this repo: plan, converter, per-game patch sets and depth profiles, tools, CI (GPL-3.0)
- [`runtime/`](https://github.com/michvllni/mkxp-z-3ds): the runtime, a fork of
  [mkxp-z](https://github.com/mkxp-z/mkxp-z) (GPL-2.0-or-later), as a git submodule

## Setup
```sh
git clone --recurse-submodules https://github.com/michvllni/rmxp3ds
```
Open the folder in the dev container (`.devcontainer/`, VS Code or devcontainer CLI). It provides
devkitARM/libctru/citro3d, host Ruby, packaging tools and a headless Azahar emulator.
- Default config: portable (Linux, macOS, Windows via WSL2), software rendering.
- `.devcontainer/linux-host/`: Linux hosts with an iGPU (`/dev/dri`) and host networking for
  `3dslink -s`.
- Without Docker (Debian trixie host): `tools/setup-workspace.sh` installs the same pinned
  toolchain; then `. ~/volume/.toolchain/env.sh`.

## Games
No game content is part of this project. You convert games you own; real games stay outside the
repository. See [AGENTS.md](AGENTS.md) for contributor rules.

## License
GPL-3.0, see [LICENSE](LICENSE). The runtime submodule is GPL-2.0-or-later.
