# xp3ds — RPG Maker XP / Pokémon Essentials runtime for the New Nintendo 3DS

Working title. A homebrew runtime that plays RPG Maker XP games (primarily Pokémon Essentials fan games such as Insurgence and Reborn) on the New 3DS, plus a PC-side converter that prepares each game for the hardware. Optional per-layer stereoscopic 3D, inspired by gpSP 3D.

## 1. Goals and non-goals

**Goals**
- Run lightweight Essentials games at a playable frame rate on a New 3DS (target: 30 fps on the overworld, no hard stalls > 1 s outside loading screens).
- A converter that turns a user's own game folder into a ready-to-copy SD package.
- Per-layer stereoscopic 3D on the overworld.
- Fully open source (GPL, see §9).

**Non-goals (for now)**
- Old 3DS support (target New 3DS only; revisit after M4).
- RGSS2/RGSS3 (VX / VX Ace) games.
- Online features (Reborn online play, GTS, etc.).
- Shipping or linking any game content. Users convert games they obtained themselves.

## 2. Hardware budget (New 3DS)

| Resource | Budget | Consequence |
|---|---|---|
| CPU | ARM11 MPCore @ 804 MHz, 2 MB L2; app gets the main core plus a second core (verify exact availability and time limits via APT) | Ruby on main core, renderer on second core (gpSP 3D pattern) |
| RAM | Roughly 124–178 MB for the app depending on memory mode (verify) | Downscaled assets, lazy loading, Ruby heap tuning |
| VRAM | 6 MB | Texture atlas management, eviction |
| GPU | PICA200, no programmable fragment shaders, textures ≤ 1024×1024, power-of-two | Tone/blend via TEV combiners; tilesets split at convert time |
| Display | Top 400×240 (per eye), bottom 320×240 touch | Render at 400×240; menus/debug on bottom screen |

## 3. Architecture

```
┌──────────────── PC ─────────────────┐     ┌─────────────── New 3DS ───────────────┐
│ xp3ds-convert (Ruby)                │     │ xp3ds runtime (C++, fork of mkxp-z)    │
│  ├─ read Game.ini, Data/*.rxdata    │     │  Core 0: CRuby VM + RGSS bindings      │
│  ├─ assets: scale, split, tex3ds    │ SD  │     └─ records frame snapshot          │
│  ├─ audio: ffmpeg → ogg/wav         │ ──▶ │  Core 1: citro3d renderer              │
│  ├─ scripts: apply patch set        │     │     ├─ native Tilemap/Sprite/Window    │
│  ├─ precompile Ruby → ISeq binary   │     │     ├─ tone/blend via TEV              │
│  ├─ depth profile (3D)              │     │     └─ stereo: per-eye layer shift     │
│  └─ forwarder CIA + icon            │     │  Audio: ndsp, streamed                 │
└─────────────────────────────────────┘     └────────────────────────────────────────┘
```

### 3.1 Runtime
- **Base:** fork of mkxp-z (GPLv2). Keep the RGSS1 Ruby API surface; replace platform layers.
- **Ruby:** CRuby cross-compiled for `arm-none-eabi` with newlib/libctru (same version mkxp-z targets — verify; currently pinned via `RUBY_VERSION` in the dev container). Stub threads/signals/mmap as needed. Fallback plan if CRuby proves infeasible: evaluate mruby with a compatibility layer (high risk, large scope).
- **Rendering:** remove OpenGL; new citro3d backend. Native implementations of `Tilemap` (incl. autotile animation and tone — the two things Reborn's Performance Mode loses), `Sprite`, `Plane`, `Window`, `Viewport`.
- **Threading model (from gpSP 3D):** core 0 runs Ruby and produces an immutable frame snapshot (draw list + dirty Bitmap list). Core 1 consumes it, uploads only dirty textures, renders both eyes. Ruby never waits on the GPU.
- **Bitmap dirty tracking:** `blt`, `fill_rect`, `draw_text`, `set_pixel`, etc. mark regions; only changed regions are re-uploaded.
- **Audio:** ndsp; BGM streamed from SD, SE cached. Requires `sdmc:/3ds/dspfirm.cdc`.
- **Input:** RGSS `Input` mapped to buttons; touch screen for menus and an optional virtual keyboard (naming screens).
- **Safety:** crash-safe settings (if GPU init hangs, next launch falls back — gpSP 3D pattern); error screen with Ruby backtrace on bottom screen.

### 3.2 Converter (`xp3ds-convert`)
- Written in Ruby (native `Marshal` access to `.rxdata`, minimal RGSS class stubs for loading).
- **Assets:** downscale by game profile (default 512×384 → 400×240, letterboxed/cropped per profile), split tall tilesets into ≤1024 px chunks with a remap table, encode with `tex3ds` (ETC1/RGBA4/RGBA8 per asset).
- **Audio:** ffmpeg → Ogg Vorbis (BGM) / PCM WAV (SE), resampled for ndsp.
- **Scripts:** apply an ordered patch set per game (`patches/<game-id>/*.rb`): disable or simplify heavy effects, swap `CustomTilemap` → native `Tilemap`, cap animation counts, etc.
- **Precompile:** `RubyVM::InstructionSequence#to_binary` for all scripts using the *same Ruby version* as the runtime, so the 3DS skips parsing.
- **Data:** optionally re-pack large `.rxdata`/`.dat` files to reduce load time (measure first).
- **3D depth profile:** default z→depth mapping + per-game overrides (`profiles/<game-id>.toml`), including grouping rules (events used as tiles stay at tile depth).
- **Output:** `sdmc:/3ds/xp3ds/games/<game-id>/` plus optional forwarder CIA with game icon.
- **Validation:** report unsupported Win32API calls, DLL usage, missing assets, estimated RAM.

## 4. Milestones

Each milestone has an exit criterion measured **on real hardware**.

| # | Milestone | Exit criterion |
|---|---|---|
| M0 | Dev environment & CI | Dev container builds a hello-world `.3dsx`; it runs in headless Azahar inside the container (screenshot taken via mcp-azahar) and on the console via 3dslink; CI builds on every push |
| M1 | CRuby on 3DS | `ruby -e`-equivalent runs a script from SD; Marshal load of an `.rxdata`; Ruby micro-benchmark numbers recorded |
| M2 | Go/no-go benchmark | Run Essentials' battle damage calc + event interpreter loop headless on 3DS; extrapolate frame cost. **Decide whether to continue.** |
| M3 | Minimal renderer | Sprite, Bitmap, Viewport, Window via citro3d; RMXP default title screen of a blank project |
| M4 | Native Tilemap + dual-core | Vanilla Essentials demo walks around a map at ≥ 30 fps |
| M5 | Converter v1 | Converts the Essentials demo end-to-end; package boots from SD |
| M6 | Battles & audio | Wild battle in Essentials demo completes; BGM/SE play |
| M7 | First real game | A small fan game fully playable; then Insurgence (patch set) |
| M8 | Stereoscopic 3D | Per-layer depth on overworld, presets + per-game profiles, UI at screen plane |
| M9 | Reborn attempt | Reborn boots and is playable through the first gym; documented performance |
| M10 | Polish & release | Forwarders, UniStore, docs, compatibility list |

## 5. Performance strategy
- Measure before optimizing: built-in profiler overlay on the bottom screen (Ruby time, render time, upload bytes, heap).
- Move per-frame work from Ruby to native in this order, guided by profiles: Tilemap → Sprite/Window updates → message window text → weather/fog → selected Essentials hot paths (via patch set replacing Ruby methods with native ones).
- Ruby GC tuning (heap growth, malloc limits) for the fixed memory budget.
- 3D renders both eyes on core 1 only; Ruby cost is unchanged. Accept ~30 fps in 3D.

## 6. Testing
- **Azahar, headless in the dev container** for fast iteration: New 3DS model, CPU clock calibrated (see §6.1), driven by Claude Code through mcp-azahar (see §6.2). Good for correctness, not for performance.
- **Real New 3DS** via 3dslink and Luma3DS GDB stub for performance and final verification. Performance numbers only count from real hardware.
- **Golden images:** render reference scenes (title, map, battle) and compare screenshots between mkxp-z desktop and xp3ds.
- **Converter tests:** run on the Essentials demo in CI.

### 6.1 Emulator calibration
Azahar's JIT does not model cache misses or memory latency the way real hardware does, so code usually runs faster there than on a real console, and GPU work runs on the host GPU. Calibrate:
1. Build `tools/bench` (Ruby interpreter loop, Marshal load, tilemap redraw).
2. Run on real New 3DS and on Azahar at 100 % CPU clock; record times.
3. Set Azahar's CPU clock percentage to roughly `real_speed / emulated_speed × 100` (rounded to the available steps).
4. Re-check after major runtime changes. Treat it as a smoke test, never as the performance gate.

Calibrate with GPU acceleration (`/dev/dri`); with software rendering the emulator's frame rate is even less representative.

### 6.2 Agent test loop (headless Azahar + mcp-azahar)
Everything runs inside the dev container, so the loop is identical on the Fedora laptop, the NixOS tower and CI.

- **Emulator:** Azahar AppImage (extracted) started via `azahar-headless`, which runs it on an Xvfb display (`$AZAHAR_DISPLAY`, default `:99`). Uses the host iGPU through `/dev/dri` if available, otherwise Mesa software rendering. Audio off.
- **Settings:** a committed `qt-config.ini` (`.devcontainer/azahar/`) is seeded on container creation, so every run uses the same model, CPU clock and renderer.
- **Control:** mcp-azahar launches `azahar-headless`, sends input, takes screenshots (from the Xvfb display) and changes settings. Claude Code uses it for interactive debugging: launch build → press buttons → inspect screenshot → fix.
- **Self-reporting runtime test mode:** a test script on the (virtual) SD card drives the runtime; it writes logs, timings and framebuffer dumps to the SD card and exits. The same tests run unchanged on the real console (3dslink, `3dslink -s` for stdout/stderr, ftpd for files).
- **Parallel runs (tower):** one instance per display and HOME directory (e.g. `AZAHAR_DISPLAY=:100 HOME=/tmp/az1`), so configs and virtual SD cards don't collide.
- **Split of responsibilities:** mcp-azahar for interactive exploration and emulator control; runtime test mode for repeatable tests, CI and real-hardware runs. Performance numbers only from the console.

## 7. Risks

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| CRuby too slow on ARM11 | High | Fatal for big games | M2 go/no-go; native hot paths; scope down to light games |
| Out of memory (Reborn) | High | Fatal for that game | Asset downscaling, lazy loading, GC tuning; accept per-game unsupported |
| CRuby porting issues (newlib, threads) | Medium | Delays | Start with minimal config; disable extensions not needed by RGSS |
| Shader effects not reproducible with TEV | Medium | Visual differences | CPU fallback for rare effects; patch set disables them |
| Game scripts rely on Win32API / DLLs | Medium | Per-game breakage | Converter reports them; patch set stubs them |
| License mix-ups | Low | Distribution problems | §9 checklist, SPDX headers |

## 8. Repository layout

```
xp3ds/
├─ .devcontainer/         # Dockerfile, devcontainer.json, azahar-headless.sh, azahar/qt-config.ini
├─ runtime/               # fork of mkxp-z (submodule or vendored)
│  ├─ src/platform/3ds/   # libctru glue, input, audio
│  └─ src/render/citro3d/ # renderer, tilemap, stereo
├─ ruby/                  # CRuby cross-build scripts + patches
├─ convert/               # xp3ds-convert (Ruby gem)
│  ├─ patches/<game-id>/
│  └─ profiles/<game-id>.toml
├─ tools/bench/           # calibration + benchmarks
├─ tests/golden/
└─ docs/
```

## 9. Licensing
- mkxp-z: GPLv2 → runtime is GPL.
- Anything taken from gpSP 3D: GPL-2.0-or-later; its mGBA GPU helpers are MPL-2.0; its RetroArch `ctr_svchax.c` is GPL-3.0 (avoid unless needed, it would make the binary GPL-3.0).
- Converter: GPL as well for simplicity.
- No game assets, ROMs, or Essentials scripts in the repo or releases. Per-game patch sets contain only our own code/diffs; check each game's terms before publishing patches for it.

## 10. Working with an AI coding agent
- Small, verifiable tasks with exit criteria (one milestone sub-step per session).
- Agent builds, runs unit tests and drives headless Azahar via mcp-azahar inside the dev container (§6.2); a human puts the console into netloader mode for real-hardware runs, which the agent then deploys and reads back via 3dslink/ftpd.
- Keep `docs/STATUS.md` updated after each session so a fresh session can resume.

## 11. Open questions
- Exact app memory available in the memory mode we choose, and whether core 2 is usable.
- Which Ruby version mkxp-z currently targets, and whether ISeq binaries are portable from x86-64 host to ARM.
- Default screen mapping: downscale 512×384 → 400×240 (blurry) vs. crop with camera follow vs. require 400×240-patched games.
- Save compatibility with PC versions (Marshal format should allow it — verify).
