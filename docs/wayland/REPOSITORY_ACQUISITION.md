# Repository Acquisition Report (Phase 0)

Date: 2026-10-31
Workspace: `/home/adamya/projects/eden-wayland`

## 1. Upstream identity

| Item | Value |
|---|---|
| Canonical repository | https://git.eden-emu.dev/eden-emu/eden |
| Hosting | Self-hosted Forgejo (`git.eden-emu.dev`) |
| Mirrors | https://codeberg.org/eden-emu/eden ; issue tracker https://github.com/eden-emulator/Issue-Reports |
| Project | Eden, a Nintendo Switch 1 emulator derived from Yuzu |
| Default branch | `master` |
| Latest stable tag | `v0.2.1` (published 2026-06-01) |
| Default-branch HEAD at clone | `943f1fc76087adcfc893fb1ca3aea507df15d004` |
| HEAD commit date | 2026-10-30 19:55:35 +0100 |
| HEAD subject | `[gpu_thread] drop affinity pinning, fix BOTW perf regression (#4603)` |
| Distance from v0.2.1 | 411 commits on `master` |
| Repository size | ~235 MiB working tree |
| Open issues (API) | 66 |
| Forks (API) | 61 |
| Archived | No |
| Last API update | 2026-10-30T19:55:42+01:00 |

Verification method: Forgejo REST API (`/api/v1/repos/eden-emu/eden`,
`/branches`, `/releases`, `/tags`) plus web search for identity confirmation on
2026-10-31. `https://github.com/eden-emu/eden` returns HTTP 404; GitHub is not
the canonical source.

## 2. License and contribution requirements

- License: **GPL-3.0-or-later** (`LICENSE.txt`, GNU GPL v3 text; every source
  file carries `SPDX-License-Identifier: GPL-3.0-or-later`).
- Contributions: `CONTRIBUTING.md`.
  - PRs accepted via the Forgejo instance, the Codeberg mirror, or
    `git format-patch` mail to `patch@eden-emu.dev`.
  - AI usage must be disclosed in the PR description (`Assisted-by: ...`).
  - New code must match surrounding style; maintainers may rework patches.
- `AGENTS.md` requires reading `docs/policies/AI.md` (not present in this
  checkout) and `docs/policies/Coding.md` (present). It also forbids
  submitting PRs or pushing commits on behalf of the user. This project obeys
  that: **no remote push has been or will be performed without explicit
  authorization.**
- Coding policy highlights relevant to this fork: prefer simple, efficient,
  readable code; avoid unnecessary abstractions/dependencies; no `typeid`/
  `dynamic_cast`; copy-on-value for small objects; keep comments reasonable.

## 3. Dependencies and repository structure

- Git submodules: **none** (`git submodule status` is empty).
- Third-party dependencies are fetched by **CPM** from `cpmfile.json` at
  configure time into `.cache/cpm`, or resolved from the system
  (`find_package`). Pinned versions of note:
  - Boost 1.92.0, fmt 12.1.0, SDL3 release-3.4.8, FFmpeg `c7b5f1537d`
    (system FFmpeg is used by default on Linux), Vulkan headers v1.4.345,
    VMA v3.3.0, Vulkan-Utility-Libraries v1.4.345, sirit v1.0.5,
    enet v1.3.18, cubeb `fa02160712`, gamemode `ce6fe122f3`,
    Catch2 v3.13.0, quazip `2e95c9001b`.
- Build system: CMake >= 3.31, C++20, Ninja. `ENABLE_QT=ON` by default.
- Qt: system Qt 6 is preferred on Linux; the bundled fallback is a
  prebuilt Eden-CI Qt 6.11.1 (`CMakeLists.txt:586-595`).
- Required Qt components: `Core Widgets Charts Concurrent Gui`, plus `DBus`
  on Linux, optional `GuiPrivate` (`CMakeLists.txt:620-640`).
- `qt6-wayland` is documented as a runtime requirement (`docs/Deps.md`) but is
  **not** a CMake dependency and is not linked or installed by the build.

## 4. Clone procedure and workspace state

```sh
git clone --recursive https://git.eden-emu.dev/eden-emu/eden.git eden-wayland
cd eden-wayland
git remote rename origin upstream
git checkout -b linux-wayland
```

- Remote `upstream` = `https://git.eden-emu.dev/eden-emu/eden.git`.
- No `origin` exists: no personal fork destination was provided, and no
  remote URL was invented.
- Branches created at the same base commit:
  `linux-wayland` (integration), `feature/native-wayland`,
  `feature/vulkan-presentation`, `feature/linux-optimizations`,
  `packaging/arch`, `stable`.
- `upstream/master` is treated as read-only and is never modified.

## 5. Recorded environment

| Component | Version |
|---|---|
| OS | Arch Linux (rolling), kernel 7.2.11-arch1-1 x86_64 |
| Session | Wayland, Hyprland 0.56.2, `WAYLAND_DISPLAY=wayland-1` |
| Display | eDP-1, 1920x1080 @ 120.21 Hz, scale 1, single monitor |
| CPU | Intel Core i5-12500H (16 threads) |
| GPU 0 | Intel Iris Xe Graphics (ADL GT2), Mesa 26.2.5, Vulkan 1.4.354 |
| GPU 1 | NVIDIA GeForce RTX 3050 Laptop GPU, driver 615.78.08, Vulkan 1.4.351, 4 GiB |
| Vulkan loader | 1.4.363 (`vulkan-icd-loader 1.4.363.0-1`) |
| Qt | 6.12.0 (`qt6-base 6.12.0-3`); Wayland platform plugin `libqwayland.so` owned by qt6-base |
| Compiler | GCC 16.2.1, Clang 23.1.4 |
| CMake / Ninja | 4.4.4 / 1.13.2 |
| RAM | 15 GiB usable |
| Disk free | ~250 GiB on `/home` |

Prime offload helper present: `/usr/bin/prime-run` sets
`__NV_PRIME_RENDER_OFFLOAD=1`, `__VK_LAYER_NV_optimus=NVIDIA_only`,
`__GLX_VENDOR_LIBRARY_NAME=nvidia`.

## 6. Missing system packages at audit time

Build-blocking: `qt6-charts` (required by `find_package(Qt6 ... Charts ...)`).

Recommended for validation: `vulkan-validation-layers`, `wayland-utils`
(provides `wayland-info`), and optionally `catch2`, `enet`, `gamemode`
(missing packages are otherwise fetched by CPM, but system packages give
reproducible, distro-tracked builds).

## 7. Existing user data (must be preserved)

- `~/.config/eden/qt-config.ini`
- `~/.local/share/eden/{nand,keys,sdmc,shader,...}` (keys directory is empty)
- Eden supports a portable data directory: if `./user` exists next to the
  working directory it takes priority over XDG paths
  (`src/common/fs/path_util.cpp:108-150`). All development runs will use
  `build/wayland-run/user` or an equivalent isolated directory.
- The existing installation and its data will not be modified.
- Two commercial NSP files exist under `~/Downloads`; they are out of scope,
  will not be copied, bundled, or read, and cannot boot without keys.

## 8. Stable releases and development branch

Releases: v0.2.1, v0.2.0, v0.2.0-rc2, v0.2.0-rc1, v0.1.1, v0.1.0,
v0.0.4 ... The project is actively developed on `master` (HEAD one day before
this audit). Release tags are not necessarily ancestors of `master`
(`git describe` reports `v0.2.0-411-g943f1fc760`); synchronization therefore
tracks `master`, not release tags.

## 9. Preliminary finding

Eden is **not** an X11-only application:

- The Vulkan layer already implements `VK_KHR_wayland_surface`
  (`src/video_core/vulkan_common/vulkan_surface.cpp:93-106`,
  `vmulkan_instance.cpp`).
- Qt WSI extraction already supports Wayland via
  `QPlatformNativeInterface("display"/"surface")`
  (`src/qt_common/qt_common.cpp:85-135`).
- The CLI frontend (SDL3) already selects Wayland automatically.

However, the Qt desktop frontend actively discourages Wayland: it can force
`QT_QPA_PLATFORM=xcb` (`src/yuzu/main.cpp:159-160`), shows a warning dialog
recommending X11 (`src/yuzu/main_window.cpp:4430-4477`), and sets `DISPLAY=:0`
when `DISPLAY` is unset (`main.cpp:155-157`). Native Wayland is therefore a
**harden-and-verify** effort, not a greenfield port.

## 10. Sources

- https://git.eden-emu.dev/eden-emu/eden
- https://git.eden-emu.dev/
- https://codeberg.org/eden-emu/eden
- https://github.com/eden-emulator/Issue-Reports
- https://eden-emu.dev
- https://www.gnu.org/licenses/gpl-3.0.en.html
