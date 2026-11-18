<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
# NOTES — status, findings, measurements, sources

Newest first within each section. Dates are absolute. Replaces `docs/STATUS.md` from PLAN §10.

## Status
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

## Carried over to later milestones
- **M3 (runtime integration):** set `rb3ds_main_stack_size` (fork `3ds/ruby/shim/include/rb3ds.h`) to the
  rgss thread's stack size before `RUBY_INIT_STACK` (mkxp-z `binding/binding-mri.cpp:1194`), and create
  that thread with a large stack (SDL2 n3ds default: 80 KiB).
- **Later:** Ruby thread preemption (timer without pipes); guard page + exception handler for deep C
  recursion.

## Measurements
Console numbers only, with date, commits of both repos and settings.

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
