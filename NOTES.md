<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
# NOTES — status, findings, measurements, sources

Newest first within each section. Dates are absolute. Replaces `docs/STATUS.md` from PLAN §10.

## Status
- **2026-11-19:** M3 exit reached (D16): Pokémon Essentials v21.1 (local copy) reaches its title
  screen on the New 3DS. The title opens 19.9 s after start and runs at 40.0 FPS; the snapshot
  matches Azahar's (Measurements, Essentials title run attempt 5). The runtime is fork `dev`
  `29930935`. M4 started: map baseline tool, Ruby compiler crash fixed (fork Ruby patch 0006), native map
  renderer drawing Essentials maps (D17; M4 findings). Console map run 2: 31.3 FPS on Route 5,
  39.9 FPS on Route 3, so the M4 frame rate is met (Measurements). Scroll seams fixed and confirmed on
  the console (run 3), texture leak fixed. Open: merges.
- **2026-11-18:** M3 in progress: SDL2 utility libraries for the 3DS (fork `3ds/deps`, test app
  `tools/sdlcheck`); mkxp-z runs on the 3DS with the citro3d renderer (D14, D15): engine, render
  (27 checks) and synthetic title screen checks pass in Azahar and on the New 3DS (hardware run
  3: title scene at 40 FPS, frame work under 8.3 ms, HOME and sleep survive). Pokémon Essentials
  v21.1 reaches its title screen in Azahar. Open for the M3 exit (D16): the Essentials title on
  the console.
- **2026-11-18:** M2 done: Essentials v21.1 runs headlessly on the New 3DS (`tools/m2`, hardware
  run 2). Go/no-go: **go, full scope** (docs/DECISIONS.md D13). Next: M3.
- **2026-11-18:** M1 done: CRuby 3.1.3 cross-built in the fork (`runtime/3ds/ruby`, merged into
  `dev` as `a807e577`, mkxp-z-3ds PR #1), `tools/bench` passes in Azahar and on the New 3DS
  (hardware run 1, with M0's hello). `runtime/` points at `a807e577`.
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
| 3DS portlibs (in image via `3ds-portlibs`) | 3ds-zlib 1.3.1, 3ds-libpng 1.6.53, 3ds-freetype 2.14.1, 3ds-libjpeg-turbo (libjpeg API 62), 3ds-libogg 1.3.6, 3ds-libvorbisidec 1.2.1 (Tremor; no full libvorbis), 3ds-bzip2 1.0.8, 3ds-physfs 3.2.0, 3ds-libiconv 1.17, 3ds-pkg-config 0.28 | pacman local db in image |

| SDL2 / SDL2_image / SDL2_ttf (3DS, fork `3ds/deps`) | 2.32.10 / 2.8.12 / 2.24.0, release `.tar.gz` sha256 `5f5993c5…ca5165` / `393f5efb…785381` / `0b2bf1e7…bfd`; SDL2 and SDL2_image match GitHub's asset digests, SDL2_ttf verified with the SDL release key `1528635D8053A57F77D1E08630A59377A7763BE6` | GitHub releases API (`assets[].digest`), `.sig` files, keyserver.ubuntu.com |
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

## M1 findings (2026-11-18, emulator; fork `feat/3ds-ruby` @ 81cf0755)
- **Build:** `runtime/3ds/ruby/build.sh` about 1 min (-j3, workspace), peak about 1.9 GiB.
  `libruby-static.a` 5.3 MB, `bench.3dsx` 5.9 MB.
- **Problems found and fixed** (fork patches/shim, details in `runtime/3ds/ruby/README.md`):
  - GCC 16 defaults to C23 → `-std=gnu17`.
  - `addr2line.c` needs dl → `rb_cv_binary_elf=no`.
  - Missing POSIX symbols → shim.
  - libctru `fcntl()` only handles sockets → `rb_bug` on the first File.open → close-on-exec macros
    removed.
  - `.S` files assembled without the arch flags (`ASFLAGS` only) → `ASFLAGS` with `-mfpu=vfp`.
  - arm32 coroutine doesn't save d8–d15. Register-level test: fails without the patch, passes with it.
  - Main-stack size unknown → no stack-overflow detection → derived from `__stacksize__`. Now
    fires at about 951 KiB of 1 MiB.
  - Transient heap 32 MB → 4 MB: malloc arena after the bench 37 MB → 8.3 MB.
  - `File.expand_path('sdmc:/x')` was relative → `file.c` patch.
- **Works (Azahar):** VM init 0.8 s; scripts from `sdmc:/` and `romfs:/`; Marshal of the
  synthetic map (75 KB, digest verified); Zlib; Fiber; `Enumerator#next`; Shift_JIS; `sleep`;
  `Time`; `Dir.glob`; `Random`.
- **Threads (fixed):** four causes were stacked on top of each other:
  1. Ruby raised NotImplementedError in every new native thread (no `STACKADDR_AVAILABLE`).
  2. Thread stacks were 32 KiB (newlib has no `PTHREAD_STACK_MIN`).
  3. libctru creates pthreads at priority 0x3F (libctru 2.7.0 `source/system/syscalls.c:194-209`),
     and the 3DS never runs lower priorities while a higher one is runnable.
  4. newlib's `sched_yield` is an ENOSYS stub.

  Native `pthread_cond_timedwait` with `CLOCK_MONOTONIC` works. Now `Thread#value`,
  `Thread.pass`, Queue and ConditionVariable work; there is no preemption (timer pipe).
- **Thread memory leak (fixed):** libsysbase ignores `PTHREAD_CREATE_DETACHED`, so every finished
  thread kept its ~1 MiB stack. Measured with 30 threads: +30 MB, after the fix +23 KB. The shim
  now detaches threads in libctru; the bench check `thread_memory` guards it.
- **Fiber pool:** starts with 2 stacks (Ruby needs at least 2: `fiber_pool_allocate_memory` only
  allocates while count > 1; 1 hung `ruby_init`).
- **`File.dirname` of device paths** was missing the device ("/a"); fixed, bench check `device_paths`.
- **Open:**
  - Deep C recursion (nested `inspect` ~2000 levels) crashes instead of raising.
  - The initial cwd in Azahar is `/` (hbmenu on hardware: unverified).
- **Emulator timings are not performance numbers.** For the record (Azahar 2126.2, 100 % clock,
  JIT): while_loop_1M 670 ms, method_call_300k 1028 ms, object_alloc_200k 1637 ms,
  marshal_load_fixture 90 ms.

## M4 findings (2026-11-19, in progress)
- **Baseline tool:** `tools/title/title.sh --scene map` with `tools/title/map_probe.rb`.
  - The probe replaces Essentials' `Scene_Intro#main` (hooked through a `TracePoint(:end)`) with
    `Game.start_new`.
  - It walks a square on Route 5 (map 41, 96 events) and Route 3 (map 31, 30 events), using
    Essentials' debug walk with scripted input.
  - Per map, it measures 600 frames of frame interval and `Scene_Map#update` time, then saves a
    snapshot.
  - Azahar (emulator, not a performance number): 11.8 and 12.2 FPS. The frame time is almost all
    in `Scene_Map#update`: Ruby logic, plus Essentials' sprite and tilemap updates with their
    bitmap drawing.
- **Native map renderer (D17, fork https://github.com/michvllni/mkxp-z-3ds/pull/10):**
  - **Why:** Essentials' Ruby `TilemapRenderer` draws through bitmaps taller than 1024 px (log:
    1024×4096, 256×1536, 160×1536). gl3ds could not use those, so only the player was drawn, on
    black. The `Outside` tileset is 256×16064 (15.7 MiB as RGBA).
  - **What replaces it:**
    - The fork's `RMXP3DSTileRenderer`.
    - The patch `patches/essentials-v21/tilemap_renderer.rb`: a preload script that redirects
      `TilemapRenderer.new` and keeps Essentials' interface.
    - A behavioural spec of Essentials' renderer, written in our own words, kept local.
  - **Memory, first attempt:** uploading every tileset tile and autotile frame up front ran
    out of linear memory ("out of linear memory for textures"), and Route 3 was half black.
  - **Memory, second attempt:** keeping a CPU copy of each source failed on the second
    `Outside`. The heap was about 75–83 MB with about 66 MB in use (`mallinfo`), so the extra
    15.7 MB raised `bad_alloc`, and the app ended without a message.
  - **Memory, now:** atlas slots are filled on first use. Tall tilesets are loaded uncached
    (`Bitmap.new`) and read in place from the mega surface, kept alive until removed; small
    images are copied.
  - **gl3ds now reports `GL_MAX_TEXTURE_SIZE` 1024.** mkxp-z's RGSS Tilemap therefore refuses
    tilesets taller than about 1300 px; the engine check tests that a 1024 px tileset is
    accepted and a 4096 px one refused.
  - **Azahar (emulator, not performance numbers):** with the patch, Route 5 and Route 3 draw
    completely (snapshots checked by eye).
    - Route 5: 21.2 FPS (11.8 before), `Scene_Map#update` 32 ms (81 before).
    - Route 3: 28.1 FPS, update 23 ms.
  - **Tile check** (`tests/runtime/tilecheck`, synthetic): 26 checks after two reviews.
  - **Frame profile and vertex optimization (fork https://github.com/michvllni/mkxp-z-3ds/pull/11):**
    - `RMXP3DSProfile.read` returns per-frame averages; the map probe logs them per map,
      together with Essentials' `updateMaps`, `updateSpritesets` and the native tilemap update.
    - **Azahar, Route 5, before the change:**
      - `updateMaps` 5.4 ms, `updateSpritesets` 25.0 ms, of which the native tilemap is 1.0 ms
        and the rest is Essentials' Ruby sprite updates.
      - `composite` 14.6 ms, of which the gl3ds vertex transform was 13.4 ms, over about 13 draws
        per frame. The scene traversal itself is negligible.
      - Limiter, blit and present: under 1 ms.
    - **Cause:** gl3ds looked up uniforms by name and attribute buffers in a map for every vertex,
      and transformed shared quad vertices twice.
    - **Fix:** resolved once per draw, and each distinct vertex transformed once. Vertex
      transform 13.4 → 1.35 ms, `composite` 14.6 → 2.6 ms; Route 5 21.1 → 28.3 FPS, Route 3
      26 → 38.1 FPS (emulator).
    - **Consequence:** the render path is now about 3 ms, so a second core can save little.
      Ruby's sprite updates (about 24 ms on Route 5) are the next target (PLAN §5).
  - **Console map run 1, prepared on 2026-11-19:** kit from rmxp3ds `e20f3f0` and fork `510a9c66`
    (`feat/3ds-tilemap-renderer`, on top of fork PR 9). Kit SHA-256 `1b959ffa…`, built with
    `title.sh kit --scene map --patch patches/essentials-v21/tilemap_renderer.rb`. The ELF is kept
    in `build/map-kit/` for symbolizing crash dumps.
- **Ruby compiler crash on the 3DS (fixed, fork https://github.com/michvllni/mkxp-z-3ds/pull/9):**
  - **Symptom:** a data abort or "Undefined Instruction" in `iseq_peephole_optimize` →
    `optimize_checktype` (a NULL `INSN`) while Essentials' scripts load. It is the same crash as
    Essentials title run attempt 4 on the console (`3ds-results/title-attempt4/`).
  - **When it happened:** seemingly at random. The preload code, debug checks, a GDB breakpoint or
    simply relinking made it appear or disappear.
  - **Cause:**
    - devkitARM uses short enums, so `INSN.insn_id` in Ruby's `compile.c` is one byte at offset
      12.
    - `get_next_insn()` and `get_destination_insn()` can return ADJUST elements. `IS_INSN_ID` on
      an ADJUST read the low byte of its label pointer, a heap address.
    - When that byte is 60 (`BIN(jump)`), the ADJUST is taken for a `jump` and its bogus operand
      is followed.
    - The register dumps match: `r9 = 0x3c = BIN(jump)`, `r0 = 0x23 = BIN(dup)`.
    - A debug CRuby build (`RB3DS_EXTRA_CFLAGS=-g`, instrumented `compile.c`) showed the case: a
      `next` inside a `while` loop (`putnil, ADJUST(redo label), jump`), in `087:DrawText` line
      165.
    - M1 had already listed the risk ("devkitARM short enums break `compile.c` `IS_INSN_ID`", from
      a PS Vita Ruby port by Asukate), but no patch had been added.
  - **Fix:** fork Ruby patch 0006. `IS_INSN_ID`, the raw `insn_id` compare in branch jump
    threading, and `optimize_checktype` now check that the element is an instruction (review
    findings included).
  - **Regression check:** engine check `compile_next_loops` compiles a method with 120
    `while`/`next` loops 60 times, interleaved with allocations. Built with the old `compile.o`,
    the runtime timed out (crashed) on it; with the patch it passes (`checks=18`).
  - **Ruled out on the way:**
    - stack size (4 MiB);
    - the transient heap (`-DUSE_TRANSIENT_HEAP=0`);
    - `-fno-strict-aliasing`;
    - upstream e031eff343 (missing write barrier, https://bugs.ruby-lang.org/issues/19880);
    - the GC freeing an iseq while it compiles (`GC.stress` test);
    - heap layout alone.
  - **Tools added for this:** `tests/smoke/azahar-smoke.sh --gdb PORT` (Azahar's GDB stub) and
    the fork's `RB3DS_EXTRA_CFLAGS`.

## M3 findings (2026-11-18)
- **Renderer architecture (D14):**
  - The desk analysis proposed rewriting the drawing of each display class, because mkxp-z picks
    among 31 GLSL programs and the PICA200 has no programmable fragment stage.
  - A closer count shows the display classes use mkxp-z's own wrapper layer about 400 times and
    call GL directly only about 19 times. The wrapper layer is TEX/FBO, Quad, ShaderSet and
    GLState.
  - So the 3DS build implements that wrapper layer on citro3d instead: each "shader" class becomes
    a TEV preset. The display classes stay upstream's.
  - Rewriting the display classes is the fallback if performance problems show up.
- **Kept from upstream as-is:** the scene graph, the Ruby bindings, `etc/`, config, filesystem and
  Input.
- **SDL2 as a utility library** (fork `3ds/deps`):
  - mkxp-z's Bitmap, Font and file code use SDL surfaces, SDL2_image, SDL2_ttf and RWops (about
    150 references), so these stay. Video, audio and joystick are off.
  - Version 2.32.10, not the meson wrap's 2.28.1, because 2.28.1 caps 3DS thread stacks at 16 KiB
    (`src/thread/n3ds/SDL_systhread.c:30-31`). The Ruby thread needs about 1 MiB.
  - SDL2_image uses libpng and libjpeg, not stb_image, which peaks at about twice the memory.
  - `tools/sdlcheck` passes in Azahar:
    - PNG pixel-exact;
    - alpha blit with difference 0;
    - text with the bundled Liberation Sans, 158×25 px at 22 pt;
    - a 1 MiB thread (heap +1027 KiB) recursing 768 KiB deep;
    - RWops on `sdmc:/`.
- **Runtime builds and runs (fork `3ds/CMakeLists.txt`, `3ds/platform`):**
  - mkxp-z's own sources and the 3DS replacements for main, event loop, filesystem and system
    helpers, audio (silent) and HTTP make up `mkxp-z.3dsx` (7.6 MB).
  - The GL function table is bookkeeping only, so nothing is drawn yet.
  - The engine check (`tests/runtime/enginecheck`) passes in Azahar, 15 checks:
    - Zlib, Table, Color/Tone/Rect, Marshal;
    - Bitmap, text size;
    - Sprite, Viewport, Window;
    - 30 frames in 0.72 s at RGSS1's 40 FPS;
    - Input, the RPG module and `System.platform`;
    - a 256×4096 tileset in Tilemap, `play_movie` (skipped), controller name, `data_directory`.
  - Pitfalls found: libruby's empty `Init_ext` must not shadow `extinit.a` (Zlib); SDL renames
    `main`; PhysFS needs a path as argv[0]; meson `-Dc_args` drops the cross file's hard-float
    flags.
- **Renderer (fork `3ds/display/gl3ds.cpp`, citro3d):** first picture in Azahar. The render check
  (`tests/runtime/rendercheck`) passes: fill, clear, `blt` (approximated: alpha blending instead of
  mkxp-z's compositing shader), `draw_text`, read-back with `get_pixel`, and a scaled sprite in the
  right orientation at 41 FPS (RGSS1 targets 40).
  - **PICA facts found on the way:**
    - Clip z must lie in [-w, 0].
    - Render targets must be in VRAM (6 MB). Textures move there when first rendered into.
    - The CPU cannot access VRAM on the console (permission fault; citro3d `texture.c`: "CPU
      can't write to VRAM"), but Azahar allows it: copies to and from VRAM go through GX
      (`C3D_SyncTextureCopy`), never `memcpy`.
    - Azahar does not fault on reads near address 0 either: null-pointer bugs in citro3d calls
      (e.g. `C3D_TexBind(1, NULL)`) only show on the console.
    - citro3d's GX queue holds 32 entries per frame (`gxQueue.maxEntries`); every
      `C3D_SyncTextureCopy` inside a frame takes two. `gspWaitForPPF` after a copy outside a frame
      can return early (the event stays latched): wait for the queue instead.
    - Texture memory starts with the top row (t = 1).
    - `C3D_SetViewport` resets the scissor.
    - `DVLB_ParseFile` needs 4-byte-aligned data.
    - The top screen's framebuffer is rotated: window y runs along framebuffer x, window x against
      framebuffer y.
  - `glClear` ignores the viewport (mkxp-z's `fill_rect` is scissor + clear).
- **Resolution (D15):** the game screen is rendered at 3DS height (640×480 at 320×240,
  pillarboxed), using mkxp-z's Hires screen scaling. Bitmaps keep full size.
- **Renderer review fixes (fork https://github.com/michvllni/mkxp-z-3ds/pull/4, two independent
  reviews):**
  - **GPU sync:** citro3d queues a frame and runs it at `C3D_FrameEnd`
    (`renderqueue.c` v1.7.1: `C3D_FrameBegin` without `C3D_FRAME_NONBLOCK` waits for the GX queue;
    `C3D_RenderTargetDelete` panics inside a frame; `C3D_FrameEnd` copies every linked target
    with `used` to the display). Textures carry the serial of the last frame that used them;
    CPU access waits only for that frame, busy linear textures get new memory instead, deleted
    objects are freed after a GPU wait.
  - **Command buffer:** libctru's `GPUCMD_Add` breaks into the debugger on overflow; 512 KB
    buffer, frame submitted early when less than 1024 words are left (`gpuCmdBufOffset`, words).
  - **VRAM:** creating and filling bitmaps no longer moves them to VRAM (CPU clears); least
    recently used VRAM textures move back to linear memory when VRAM is full; mkxp-z's pool of
    disposed bitmaps is 4 MB on the 3DS.
  - **`Bitmap#blt`:** exact for transparent and opaque destination pixels on the TEV with the
    destination copy on unit 1 (combiner buffer: a stage's output reaches the buffer input two
    stages later; stage 0 reads the buffer as 0, the initial buffer color only from stage 1).
- **Renderer stage B (fork https://github.com/michvllni/mkxp-z-3ds/pull/6):** one TEV effect chain for sprites,
  planes, tilemap layers and gray (luma via per-channel multiply-add; color/flash mixed before
  the tone, scaled by what the mixes leave, so the per-stage clamps give GLSL's result); sprite bush as a CPU
  geometry split; viewport and screen effects; `Graphics.transition` plain and with a
  transition image (texture units 1-3 → PICA 0-2, third texture coordinate).
- **Upstream mkxp-z assumes Hires factors >= 1.** Found with factor 0.5, fixed with 3DS hooks:
  scissor cache (`GLProperty::set` skips unchanged boxes that apply() scales), screen scene
  geometry used for both buffer pixels and game coordinates (culled everything beyond 320×240),
  shader blits projected with the Hires matrix, the gray shader's quad, the transition quad and
  `resize_screen`'s scissor box in buffer pixels, `snap_to_bitmap` without bitmap twins. Plane's tiled path (no `npot_repeat`) ignored the viewport position. Upstream
  reports are on hold (Carried over: backlog).
- **Large textures:** mkxp-z keeps bitmaps above `GL_MAX_TEXTURE_SIZE` as CPU "mega surfaces"; only
  its tileset atlas needs more than 1024 px (tilesets above about 1300 px at 1024). Per PLAN §3.2
  and M4 the converter splits tall tilesets and the Tilemap becomes native, so >1024 px textures
  move to M4; gl3ds reports 4096 until then.
- **Pokémon Essentials v21.1 title screen (M3 exit, D16; local copy, `tools/title`):**
  - First run: Essentials stopped in its first script section, `Encoding::UTF_8` was a NameError.
    The runtime linked `enc/encinit.a` after `libruby-static.a`, whose `dmyenc.o` has an empty
    `Init_enc`: only the built-in encodings, without constants. Fixed in the fork (link order,
    https://github.com/michvllni/mkxp-z-3ds/pull/7); the engine check gained an `encodings` check.
  - The probe first wrapped `Graphics.update`; Essentials aliases it in its singleton class, and
    the alias of a prepended wrapper recursed (SystemStackError). It now hooks the title scene
    through a `TracePoint(:end)` on class definitions.
  - Azahar (emulator, timings don't count): scripts loaded and `IntroEventScene` defined after
    8.8 s, two splash screens, title screen after 24.2 s, then 39.9 FPS on the title; 512×384
    at factor 0.625 = 320×240.
  - Console attempt 1 (2026-11-19, rmxp3ds 10124ea, fork eba09cbc, kit SHA-256 d9611c41): the
    system crashed at start, before any probe line (Luma3DS dump: data abort, `far=0xffffffff`,
    in libiconv `iconv` ← `Encoding::convertString` ← `readConfFile` ← `Config::read`). The SD
    card still had Essentials' own `mkxp.json` (ASCII plus "Pokémon" in UTF-8) instead of the
    kit's. uchardet 0.0.8 guesses that text as `MAC-CENTRALEUROPE` (reproduced with a host build
    of the same tarball); the devkitPro 3DS libiconv only has `MACCENTRALEUROPE` (`strings
    libiconv.a`), so `iconv_open` returned `(iconv_t)-1` and `iconv()` wrote through it. Fix in the
    fork (https://github.com/michvllni/mkxp-z-3ds/pull/8): on the 3DS, well-formed UTF-8 is
    taken as is, and an unknown charset throws instead of crashing. The engine check's
    `mkxp.json` now carries a UTF-8 title that uchardet misdetects the same way. The old runtime
    times out with it in Azahar; the fixed one passes. Kit build 2 (SHA-256 db341025) tells the
    user to replace the game's `mkxp.json` and to check its first line.
  - Console attempt 2 (2026-11-19, kit 2, fork b29526e9): no crash, and the probe reported the
    title: probe loaded, `IntroEventScene` hooked at 6.8 s, splashes at 13.6 s and 16.5 s, title
    opened at 20.0 s, then 40.0 FPS over 240 frames. But the screen stayed **black** (maintainer).
    Once the title closed (on input), Essentials stopped with a NoMethodError in `AnimatedBitmap`:
    its first window got an empty path because Ruby's `FileTest` found no windowskin. In Azahar
    every lookup works (`./` paths, spaces, `Dir.pwd` = `sdmc:/rmxp3ds/game`), and the snapshot
    shows the title. Two open explanations: game files missing from the SD copy, or a console-only
    drawing problem. Kit 3 tells them apart: the probe saves `Graphics.snap_to_bitmap`
    (`realtitle-snap.png`, kept local) and logs `Dir.pwd`, how many entries each `Graphics/`
    directory has, and `FileTest` on the windowskin. Both run after the measurement, because they
    take seconds.
  - Console attempt 3 (2026-11-19, kit 3 SHA-256 2314007f, rmxp3ds e4247d8, fork 43e7ae75):
    the title was reported again (20.0 s, 40.0 FPS), and the snapshot was black. Cause: an
    incomplete copy on the SD card. `Graphics/` held only Animations through Items, and Items had
    310 of 449 files; Titles, Windowskins and the other later folders were missing. Essentials
    skips images it can't find, which gives a black title and then the empty windowskin path.
    Not a runtime bug. The full folder is 102 MB in 7606 files (6456 in `Graphics/`).
  - Console attempt 4 (2026-11-19, kit 3, full fresh copy): the top screen stayed black and the
    bottom screen showed only `game: sdmc:/rmxp3ds/game`. The system became very slow, and the
    app was hard to close. After a long wait it crashed: a data abort in Ruby's compiler
    (`iseq_peephole_optimize` ← `rb_iseq_compile_node` ← `yycompile0`, with `exec_hooks_protected`
    from the probe's TracePoint on the stack; `far=0x2d5dac0d`, an invalid pointer). No probe log
    was written. In Azahar the same full copy takes about 5 minutes of wall time before the scripts
    start, nearly all in "Loading path cache": mkxp-z's `createPathCache` enumerates and stats
    every file through PhysFS. With `"pathCache": false`, the run from start to title takes 38 s
    and gives the same result (title after 24.3 s, 39.9 FPS). The SD card is FAT, so it matches
    names without case anyway. `tools/title` now writes `"pathCache": false` (kit 4, SHA-256
    02caae71). The compiler crash is still unexplained; candidates are heap exhaustion or
    corruption after the long scan. Earlier Azahar "hangs" were timeouts that were too short
    (100–200 s).
- **Synthetic title screen (`tests/runtime/titlecheck`):** title image, command window with an
  RGSS1-layout windowskin, entries and cursor, fades; all generated by `make-assets.rb`, built
  from the RGSS API only (no RTP or game scripts). Passes in Azahar (7 checks).

## M2 findings (2026-11-18; console numbers: Measurements, hardware run 2)
- **Approach (`tools/m2`):** a real game's scripts run headlessly. The game's `Data/Scripts.rxdata` is
  loaded section by section (all except "Main") into `rgss_headless.rb`. That file provides real data
  classes (Table, Color, Tone and Rect with RGSS Marshal formats) and quiet stand-ins for graphics,
  input and audio, plus mkxp-z's RGSS1 `RPG` module (decoded from the runtime's
  `binding/module_rpg1.rb.xxd`, not stored here). A benchmark script then drives the game's own
  classes. The game is Pokémon Essentials v21.1 (its demo game, local only, never in the repo).
  CI runs the same pipeline with a synthetic game (`tests/fixtures/make-game.rb`), and host and
  Azahar must compute the same digest.
- **Headless pitfalls found:**
  - Essentials v21 is time-based (`System.uptime`), so the stand-in clock advances one frame per
    `Graphics.update` (`SIM_FPS`, default 30). With a wall clock, results would depend on machine
    speed.
  - A catch-all `respond_to_missing?` makes `defined?(x.y)` true, so Essentials skipped its own
    `Graphics.update` alias and never counted frames. Stand-ins answer only `method_missing`.
  - `Battle::DebugSceneNoVisuals#pbUpdate` is empty, but `pbShowAbilitySplash` waits one second of
    `System.uptime` in a loop: the benchmark makes it pass a frame, like the real scene's `pbUpdate`.
- **Port bug found:** `Kernel#load` failed with `ENOTSOCK` because it clears `O_NONBLOCK` via
  `fcntl(F_SETFL)` and libctru's `fcntl` only handles sockets. Fork: `ac_cv_func_fcntl=no`.
- **Workload** (`essentials_bench.rb`):
  - A: overworld logic per frame on Route 5 (map 41, 96 events) and Route 3 (map 31, 30 events),
    with the player debug-walking in a square and all events updating.
  - B: A plus Essentials' Ruby sprite updates (spritesets, including its Ruby tilemap renderer,
    with the drawing itself stubbed).
  - C: five 3-vs-3 AI trainer battles at level 50 without visuals.
- **Emulator results** (Azahar 2126.2, not performance numbers; M1 measured Azahar 1.4–2.2× slower
  than the console):

| Phase | Host x86 Ruby 3.1.3 | Azahar | Azahar / host |
|---|---|---|---|
| load 402 script sections (401 evaluated, "Main" skipped) | 0.33 s | 11.2 s | 34× |
| new game (data loading) | 0.12 s | 11.3 s | ~95× |
| A Route 5 logic | 0.14 ms/frame | 6.8 ms (p95 8.8) | 49× |
| B Route 5 + Ruby spritesets | 0.72 ms/frame | 32.8 ms (p95 36.3) | 46× |
| A Route 3 logic | 0.07 ms/frame | 3.1 ms (p95 4.1) | 44× |
| B Route 3 + Ruby spritesets | 0.66 ms/frame | 28.4 ms (p95 31.9) | 43× |
| C battle | 3.6 ms/turn | 120 ms/turn | 33× |
| C damage calc | 0.11 ms | 3.6 ms | 33× |

  Memory in Azahar: 38.7 MB malloc in use after everything (8.3 MB for M1's bench alone).

## Carried over to later milestones
- **M3 (runtime integration):** set `rb3ds_main_stack_size` (fork `3ds/ruby/shim/include/rb3ds.h`) to the
  rgss thread's stack size before `RUBY_INIT_STACK` (mkxp-z `binding/binding-mri.cpp:1194`), and create
  that thread with a large stack (SDL2 n3ds default: 80 KiB).
- **Later:** Ruby thread preemption (timer without pipes); guard page + exception handler for deep C
  recursion.
- **Backlog, upstream mkxp-z (on hold, maintainer decision 2026-11-18: no upstream traction for now):**
  Hires scissor bug. `GLProperty::set` (`src/display/gl/glstate.h`) skips unchanged values, but
  `GLScissorBox::apply` (`glstate.cpp`) scales the box when the ping-pong framebuffer is bound. A
  bitmap `fill_rect` with the same logical box then keeps the scaled scissor (at factor 0.5 it
  fills a quarter). The fork has a 3DS-only hook (fork PR https://github.com/michvllni/mkxp-z-3ds/pull/4).
  Before reporting, confirm on a desktop build. mkxp-z has no written AI contribution policy
  (checked the repo, wiki, org profile and issues; the community is on Discord): disclose AI
  assistance if it is ever filed.
  Bitmap texture leak: `Bitmap::releaseResources` (`src/display/bitmap.cpp`) releases the texture
  only when no CPU copy (`p->surface`, made by `get_pixel`/`set_pixel`) exists, so every bitmap
  read with `get_pixel` leaks its texture. The fork has a 3DS-only hook (fork PR
  https://github.com/michvllni/mkxp-z-3ds/pull/12).
  Charset guessing: `Encoding::convertString` (`src/util/encoding.h`) calls `iconv()` without
  checking `iconv_open`, and uchardet guesses mostly ASCII UTF-8 text wrongly (names libiconv may
  not know, or mojibake). The fork has a 3DS-only hook (fork PR
  https://github.com/michvllni/mkxp-z-3ds/pull/8). Confirm on desktop before reporting.

## Measurements
Console numbers only, with date, commits of both repos and settings.

- **Commit note (2026-11-19):** fork https://github.com/michvllni/mkxp-z-3ds/pull/7, /8 and /6 were
  squash-merged into `dev` (`2cb116f8`, `1265dcc7`, `29930935`). `29930935` has the same tree as
  `43e7ae75`, the runtime in the Essentials title runs 2–5.
- **Commit note:** after fork https://github.com/michvllni/mkxp-z-3ds/pull/5 was merged, the renderer
  branches were rebased onto `dev`: `3855a84d` → `952f37f9`, `9c9e785e` → `46949580`,
  `306dd26a` → `f81aa12a` (same changes).

### 2026-11-18 · Hardware run 3, attempt 1 · New 3DS · M3 checks (`tools/hw3`)
- **Commits:** rmxp3ds `9a7d5c6`, mkxp-z-3ds `3855a84d` (`feat/3ds-gl-effects`); settings: kit
  defaults (Hires factor 0.5, RGSS1, frame rate 40).
- **Result:** crash before any result file. Luma3DS exception dump: data abort (type 3) in
  `3dsx_app`, DFSR 0x80d (permission fault on a write), FAR 0x1f300008 (VRAM bank B), PC in
  `memcpy` called from the VRAM migration in gl3ds `currentTarget` while a Window was drawn
  (symbolized against a rebuild of the kit's source).
- **Cause:** the CPU cannot write VRAM on the console; Azahar allows it, so the emulator checks
  could not catch it. Fixed in mkxp-z-3ds `9c9e785e` (GX texture copies, render targets move
  back to linear memory before CPU access). Attempt 2 follows with the fixed kit.

### 2026-11-18 · Hardware run 3, attempt 2 · New 3DS · M3 checks (`tools/hw3`)
- **Commits:** rmxp3ds `5cc7d8f`, mkxp-z-3ds `9c9e785e`; kit defaults.
- **Result:** crash before any result file, again while a Window was drawn. Luma3DS dump: data
  abort, DFSR 0x5 (translation fault, read), FAR 0xc, PC in citro3d `C3D_TexBind` called from
  gl3ds `emit` (binary identical to the kit, symbolized). The VRAM fix of attempt 1 got past
  its crash site.
- **Cause:** `C3D_TexBind(unit, NULL)` for units 1 and 2: citro3d 1.7.1 reads the texture's
  type there (`texture.c` `C3D_TexBind` → `C3D_TexGetType`); NULL is only valid for unit 0.
  Azahar reads 0 at address 0xc instead of faulting. Fixed in mkxp-z-3ds `5fa7b754` (a dummy
  texture on unused units). An audit for further console-only faults then found a GX queue
  overflow (more than 15 moves to VRAM in one frame panic in libctru `gxqueue.c`), eviction
  copies not waited for, and empty scissor boxes covering the whole target; fixed in
  `5f8fabe6`. Attempt 3 follows.

### 2026-11-19 · Essentials map run 3 · New 3DS · seam check (kit 3)
- **Commits:** kit 3 (SHA-256 `f189ea99…`) from a local merge of mkxp-z-3ds `8d2d81cc` (fork
  PR 11) and `fa2a44d4` (fork PR 12, the get_pixel texture leak fix); rmxp3ds `6c44188`.
- **Result:**
  - The maintainer confirmed that the black vertical lines while walking sideways are gone
    (half-texel inset, fork PR 10).
  - The first set of result files sent was run 2's again (byte-identical); the correct files
    followed.

  | Map | FPS | Frame avg / p50 / p95 / max | `Scene_Map#update` | Ruby split (ms/frame) | Present path (ms/frame) |
  |---|---|---|---|---|---|
  | Route 5 (96 events) | **31.4** | 31.8 / 30.8 / 32.8 / 283 ms | 28.6 ms | updateMaps 4.3, updateSpritesets 21.6 (native tilemap 0.8) | composite 2.7 (vertex transform 1.3, 14.2 draws), present 0.15 |
  | Route 3 (30 events) | **39.2** | 25.5 / 25.0 / 28.8 / 41 ms | 22.5 ms | updateMaps 1.6, updateSpritesets 19.1 (native tilemap 0.8) | composite 2.2, limiter 0.4 |

  - The same as run 2 within noise. The M4 frame rate holds with the seam and leak fixes.
  - Snapshots and logs: `3ds-results/map-run3/` (not in the repo).

### 2026-11-19 · Essentials map run 2 · New 3DS · M4 (native map renderer, faster gl3ds vertex path)
- **Commits:** kit 2 from rmxp3ds `f32d273`, mkxp-z-3ds `eb546543` (`feat/3ds-frame-profile` on top
  of fork PRs 10 and 9; same tree as `8f74b4b1` after the rebase onto `dev`), SHA-256 `d9625d7e…`.
  Settings as in run 1.
- **Results:**

  | Map | FPS | Frame avg / p50 / p95 / max | `Scene_Map#update` | Ruby split (ms/frame) | Present path (ms/frame) |
  |---|---|---|---|---|---|
  | Route 5 (96 events) | **31.3** | 31.9 / 30.8 / 33.3 / 295 ms | 28.8 ms | updateMaps 4.3, updateSpritesets 21.7 (native tilemap 0.8) | composite 2.7 (vertex transform 1.3, 13.8 draws), blit 0.06, present 0.15 |
  | Route 3 (30 events) | **39.9** (the game's 40 FPS cap) | 25.1 / 25.0 / 25.6 / 49 ms | 21.8 ms | updateMaps 1.6, updateSpritesets 18.5 (native tilemap 0.8) | composite 2.1, limiter 0.7 |

- **Reading:**
  - The M4 frame rate (≥ 30 FPS) is met on both maps.
  - What's left is Ruby: Essentials' sprite updates take about 18–21 ms per frame, game logic
    1.6–4.3 ms, drawing about 3 ms.
  - Single frames of about 300 ms remain on Route 5 (map setup and GC runs).
- **Seams:**
  - **Seen:** the maintainer saw thin black vertical lines at tile edges while the player walked
    sideways (video and snapshots in `3ds-results/map-run2/`).
  - **Cause:** at factor 0.625, tile edges fall between screen pixels, and edge samples reached
    the neighbouring atlas slot.
  - **Fix:** half-texel inset (fork https://github.com/michvllni/mkxp-z-3ds/pull/10). The tile
    check `scroll_no_seams` reproduced the seam in Azahar and passes with the fix.
- **Texture leak found on the way:**
  - The memory figures added to the frame profile showed one texture kept alive per snapshot
    read with `get_pixel`.
  - **Cause:** upstream `Bitmap::releaseResources` freed the CPU copy instead of the texture.
    Each `get_pixel` snapshot cost 2 MB of linear memory, so about 15 of them exhausted it.
  - **Fix:** fork https://github.com/michvllni/mkxp-z-3ds/pull/12. Engine check
    `get_pixel_no_texture_leak`: fails on `dev`, passes with the fix.
- Local logs: `3ds-results/map-run2/` (not in the repo).

### 2026-11-19 · Essentials map run 1 · New 3DS · M4 (`tools/title --scene map`, native map renderer)
- **Commits:** kit from rmxp3ds `d8d1e5a` and mkxp-z-3ds `510a9c66` (`feat/3ds-tilemap-renderer`
  on top of fork PR 9), kit SHA-256 `1b959ffa…`; game: the Pokémon Essentials v21.1 demo, a
  local copy. Settings: RGSS1, Hires factor 0.625, `pathCache` false, frame rate 40 (the game's
  default), preload scripts `patches/essentials-v21/tilemap_renderer.rb` then the map probe.
  Debug walk in a square, 60 frames to settle, then 600 measured frames per map.
- **Results:**

  | Map | FPS | Frame avg / p50 / p95 / max | `Scene_Map#update` avg / p95 | GC runs |
  |---|---|---|---|---|
  | Route 5 (map 41, 96 events) | 26.7 | 37.5 / 36.6 / 38.4 / 308 ms | 28.9 / 30.0 ms | 8 |
  | Route 3 (map 31, 30 events) | 32.9 | 30.4 / 29.2 / 33.4 / 269 ms | 23.3 / 26.5 ms | 6 |

  - The snapshots show both maps fully drawn, with the day/night tint, the same as Azahar.
  - The game reached the map 13.4 s after start, with scripts and the new game loaded.
- **Reading:**
  - The frame is Ruby (`Scene_Map#update`: game logic plus Essentials' sprite updates) followed
    by drawing and presenting (about 7–8.5 ms), on one core.
  - The single frames of 270–310 ms coincide with the map setup and GC runs (to be confirmed).
  - The M4 exit (≥ 30 FPS) is met on Route 3 and is 11% short on Route 5.
  - Next: render on the second core (PLAN §2 threading model), so that Ruby and drawing
    overlap, then profile the Ruby side.
- Local logs and snapshots: `3ds-results/map-run1/` (not in the repo).

### 2026-11-19 · Essentials title run, attempt 5 · New 3DS · M3 exit (`tools/title`) · PASS
- **Commits:** rmxp3ds `75503ef` (kit 4, SHA-256 02caae71), mkxp-z-3ds `43e7ae75`
  (`feat/3ds-gl-effects`, which includes fork PRs #7 and #8); game: Pokémon Essentials v21.1, a
  full local copy on the SD card (never in the repo). Settings (`tools/title` mkxp.json): RGSS1,
  Hires factor 0.625 (512×384 → 320×240), texture factor 1.0, `pathCache` false, title probe as
  the preload script.
- **Result:** `RMXP3DS_TEST realtitle PASS title_after=19.9s title_fps=40.0 frames=240`. Probe
  log: `IntroEventScene` hooked at 6.75 s, splashes at 13.6 s and 16.5 s, title at 19.92 s. The
  snapshot (`Graphics.snap_to_bitmap`, 512×384) shows the full title screen and matches the one
  from Azahar. Ruby sees all 6456 files in `Graphics/`.
- **Earlier attempts** (M3 findings, Essentials title screen): 1 crashed reading the game's own
  `mkxp.json` (fork #8); 2 and 3 had an incomplete copy on the SD card; 4 took minutes in the path
  cache and then crashed in Ruby's compiler (`3ds-results/title-attempt4/`, not reproduced since
  the path cache is off).
- Local logs: `3ds-results/kit-4/` (not in the repo).

### 2026-11-18 · Hardware run 3, attempt 4 · New 3DS · M3 checks (`tools/hw3`) · PASS
- **Commits:** rmxp3ds `4eafc0a`, mkxp-z-3ds `0c370c89` (`feat/3ds-gl-effects`, code of
  `205732bc`); settings: kit defaults (RGSS1, Hires factor 0.5 → 320×240 pillarboxed, frame rate 40).
- **Checks:** engine 15/15, render 27/27, title 7/7 (synthetic title screen), in one app start;
  engine 1.2 s, render 9.9 s, title 8.2 s.
- **Frame times, synthetic title scene** (title sprite 640×480, window with three entries and a
  blinking cursor), 400 frames each:
  - at 40 FPS: avg 24.98 ms (40.0 fps), median 24.97, p95 25.02, max 25.21 ms;
  - uncapped target 120 FPS: avg 8.28 ms (120.7 fps), median 8.31, p95 8.34, max 8.37 ms, so
    the scene's frame work fits in 8.3 ms (limited by the frame limiter, not the work).
- **HOME and sleep:** 60 s window, 2037 frames; pauses of 8.2 s (HOME) and 0.9 s (lid), the app
  continued and finished normally: the GPU lock (`205732bc`) holds.
- Local logs: `3ds-results/hw3-attempt4/` (not in the repo).

### 2026-11-18 · Hardware run 3, attempt 3 · New 3DS · M3 checks (`tools/hw3`)
- **Commits:** rmxp3ds `9c73814`, mkxp-z-3ds `5f8fabe6`; kit defaults.
- **Result:** the whole console froze (no input, HOME included), no Luma3DS dump, and no log:
  the checks wrote their results only at the end of each check.
- **Analysis:**
  - Not the 3DSync freeze (https://github.com/vllni/3DSync/pull/81: `ptm:u`/`gsp::Lcd` held open
    for the app's lifetime blocked the system). The runtime opens neither; `cfgu` is closed right
    after use; `soc:U` is opened only when started via 3dslink.
  - Likely cause: citro3d's APT hook (`base.c` `C3Di_AptEventHook`) runs on the main thread in
    `aptMainLoop` and waits for/clears the GX queue on suspend, while the RGSS thread has a frame
    open (the queue is stopped during a frame, libctru `gxCmdQueueWait` returns at once) and keeps
    submitting GPU work after the app gave up the GPU. Not confirmed (no log of the stage).
  - Fixed in mkxp-z-3ds `205732bc` (GPU lock: rendering pauses at a frame boundary for HOME and
    sleep). Logging changed: every check and `tools/hw3` append each line at once
    (`<name>-results.txt`, `hw3-log.txt`), so a crash or freeze keeps the log.

### 2026-11-18 · Hardware run 2 · New 3DS · M2 go/no-go benchmark
- **Setup:**
  - Kit v3: rmxp3ds `1dbffc0` (bench app, branch `feat/m1-ruby-bench`) with the `tools/m2`
    harness (as committed in `86460a7`), mkxp-z-3ds `40375ce6` (branch `feat/3ds-ruby`).
  - Game: Pokémon Essentials v21.1 demo (`Data/` on SD, local copy).
  - Started from the Homebrew Launcher, `osSetSpeedupEnable(true)`, simulated game clock at
    30 FPS, default workload (Route 5 and Route 3, 600 frames each; 5 battles).
- **Result:** PASS. VM init 281 ms, whole run 78 s. malloc 38.7 MB in use (arena 44.8 MB) of a
  88.5 MB heap.

| Phase | New 3DS | Azahar | Host x86 | 3DS / host |
|---|---|---|---|---|
| load 402 script sections (parse + eval) | 8.65 s | 11.2 s | 0.33 s | 26× |
| new game (Marshal load of game data from SD) | 19.9 s | 11.3 s | 0.12 s | ~165× |
| A Route 5 logic (96 events) | 5.18 ms/frame (p95 6.37, max 11.5) | 6.8 ms | 0.14 ms | 37× |
| B Route 5 + Ruby spritesets | 25.1 ms/frame (p95 28.1, max 34.4) | 32.8 ms | 0.72 ms | 35× |
| A Route 3 logic (30 events) | 2.49 ms/frame (p95 3.40) | 3.1 ms | 0.07 ms | 36× |
| B Route 3 + Ruby spritesets | 22.2 ms/frame (p95 25.0) | 28.4 ms | 0.66 ms | 34× |
| C battle (3 vs 3, no visuals) | 115 ms/turn | 120 ms | 3.6 ms | 32× |
| C damage calc | 3.5 ms | 3.6 ms | 0.11 ms | 32× |

- **Reading:**
  - Game logic uses 8–16 % of a 30 FPS frame (33.3 ms).
  - With Essentials' Ruby sprite updates (drawing stubbed), a busy map uses about 75 %.
  - Host profile of B on Route 5 (660 frames): `TilemapRenderer#update` 0.31 ms/frame,
    `Sprite_Character#update` 0.19 ms, `Spriteset_Map#update` 0.17 ms. The tilemap is about half
    of the Ruby spriteset cost.
  - A battle turn costs ~0.1 s of Ruby: one hitch per turn, between animations.
  - Startup is slow: ~29 s to a new game. Data loading is slower on the console than in Azahar
    (SD I/O).
  - Azahar is only 1.0–1.3× slower than the console for this workload, and faster for SD I/O.

### 2026-11-18 · Hardware run 1 · New 3DS
- **Setup:**
  - Kit v2: rmxp3ds `62707b9` (branch `feat/m1-ruby-bench`), mkxp-z-3ds `88d0581d` (branch
    `feat/3ds-ruby`), devkitARM r68, libctru 2.7.0.
  - Started from the Homebrew Launcher (no 3dslink), `osSetSpeedupEnable(true)`, 1 MiB main stack.
  - Results from `sdmc:/rmxp3ds/test/`.
- **hello (M0):** `RMXP3DS_TEST hello PASS frames=60 new3ds=1`. M0's console criterion is met:
  the binary runs on the console. Deployment via 3dslink is not exercised yet.
- **rubybench (M1):** PASS. All checks pass on hardware: native pthread, stack limit (~951 KiB of
  1024), Fiber VFP, threads, Queue, ConditionVariable, Zlib, Marshal fixture + round trip, encodings.
  - VM init 284 ms; whole run 6.5 s.
  - heap 88.5 MB, malloc arena 8.3 MB (7.3 MB in use).
  - GC: 107 runs, 34 heap pages.
  - Timer pipe warning as expected.

| Benchmark | New 3DS | Azahar 2126.2 | Host Ruby 3.1.3 x86 (EPYC 9V74, median of 3) | 3DS / host |
|---|---|---|---|---|
| marshal_load_fixture (75 KB map) | 62 ms | 90 ms | 1.7 ms | ~37× |
| while_loop_1M | 301 ms | 670 ms | 12.8 ms | ~24× |
| method_call_300k | 530 ms | 1028 ms | 10.5 ms | ~50× |
| block_yield_300k | 660 ms | 1099 ms | 9.3 ms | ~71× |
| ivar_attr_200k | 372 ms | 632 ms | 10.0 ms | ~37× |
| array_push_each_200k | 700 ms | 1177 ms | 13.6 ms | ~52× |
| hash_set_get_100k | 442 ms | 637 ms | 14.5 ms | ~30× |
| string_build_50k | 373 ms | 538 ms | 8.4 ms | ~44× |
| object_alloc_200k | 1107 ms | 1637 ms | 32.7 ms | ~34× |
| table_rw_40x30x3_x10 | 304 ms | 491 ms | 9.2 ms | ~33× |
| marshal_load_fixture_x10 | 633 ms | 994 ms | 15.8 ms | ~40× |

- **Reading:**
  - CRuby on the New 3DS is roughly 25–70× slower than a current desktop core (median ~37×).
  - Azahar at 100 % clock is 1.4–2.2× *slower* than the console, the opposite of PLAN §6.1's
    assumption. CPU clock calibration therefore goes up, not down. Recheck with GPU
    acceleration; this workspace uses llvmpipe.
  - Marshal load of a 75 KB map takes 62 ms, so loading a map is acceptable.
  - Per-frame Ruby cost is the open question for M2.
