# rmxp3ds

Runtime and converter to play RPG Maker XP games (primarily Pokémon Essentials fan games) on the
New Nintendo 3DS, with optional per-layer stereoscopic 3D.

**Status:** early development. M0 (toolchain, CI) and M1 (CRuby 3.1.3 on the 3DS: scripts from
SD, Marshal load of RMXP data, threads, micro-benchmarks) run in the emulator and on the New 3DS.
M2 (go/no-go benchmark): a real game's scripts run headlessly on the New 3DS (`tools/m2`);
decision: continue (docs/DECISIONS.md D13). M3: mkxp-z runs on the 3DS with a citro3d renderer;
Pokémon Essentials v21.1 reaches its title screen on the New 3DS. M4: a native map renderer;
the player walks Essentials maps at 31–40 FPS on the New 3DS. Next: M5, the converter. Nothing
is playable end to end yet. See
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

Converting a game (host Ruby 3.1, no gems):
```sh
convert/rmxp3ds-convert --game ~/games/MyGame --out build/sd \
  --runtime runtime/build-3ds/mkxp/mkxp-z.3dsx
```
Copy the contents of `build/sd` to the root of the SD card. The app (`sdmc:/3ds/rmxp3ds/`)
lists every game in `sdmc:/rmxp3ds/games/`. Each package has a report
(`rmxp3ds/convert-report.txt`) with the detected profile, the files left out (Windows
programs and DLLs), missing graphics or audio, and script calls that cannot work on the 3DS.
`--help` lists all options.

## License
GPL-3.0, see [LICENSE](LICENSE). The runtime submodule is GPL-2.0-or-later.
