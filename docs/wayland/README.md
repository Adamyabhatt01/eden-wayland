# Eden-Wayland

A Linux-native, Wayland-first fork/workspace of the Eden Nintendo Switch
emulator, targeting Arch Linux, Hyprland and Vulkan (Intel iGPU + NVIDIA RTX
3050 via PRIME), while keeping XWayland as an explicit fallback.

This is **not** a rewrite. Upstream Eden already contains a Qt Wayland path and
`VK_KHR_wayland_surface` support. This project verifies that path, removes
upstream's X11 bias, hardens presentation and GPU selection, and packages it
reproducibly.

## Status

| Phase | Status |
|---|---|
| 0 — Repository verification | Complete (`REPOSITORY_ACQUISITION.md`) |
| 1 — Architecture audit | Complete (`ARCHITECTURE.md`) |
| 2 — Implementation plan | Complete (`WAYLAND_IMPLEMENTATION_PLAN.md`) |
| 3 — Baseline + native Wayland prototype | Complete: native Wayland Vulkan presentation verified on NVIDIA and Intel, plus XWayland; see `TESTING.md` and `evidence/` |
| 4 — Reliability | In progress: C1, D1 and D2 landed (D1/D2 recovery paths code-verified, runtime surface-loss/minimise not yet observed); C2, E1 and F1/F2 pending |
| 5 — Optimization | Not started |
| 6 — Packaging | Not started |
| 7 — Final audit | Not started |

Runtime claims are limited to what `TESTING.md` records with logs and
screenshots in `evidence/`. Performance comparisons remain unmeasured.

## Quick start (development)

```sh
# Build dependencies (Arch; run as your user, not via this repo)
sudo pacman -S --needed base-devel cmake ninja git boost fmt sdl3 enet \
  qt6-base qt6-charts qt6-multimedia qt6-wayland qt6-svg qt6-declarative \
  vulkan-headers vulkan-icd-loader vulkan-validation-layers \
  spirv-tools spirv-headers glslang libusb ffmpeg libzip lz4 zlib zstd \
  nlohmann-json openssl opus gamemode catch2 wayland wayland-protocols \
  wayland-utils pkgconf

cmake -B build/rel -G Ninja -DCMAKE_BUILD_TYPE=Release
cmake --build build/rel -j"$(nproc)"
```

Run isolated from an existing Eden installation (portable mode: a `user/`
directory in the working directory takes priority over XDG paths):

```sh
mkdir -p build/wayland-run/user
cd build/wayland-run
../rel/bin/eden            # native Wayland by default after Phase 3 patches
QT_QPA_PLATFORM=xcb ../rel/bin/eden   # XWayland fallback
```

Do not point development runs at `~/.config/eden` or `~/.local/share/eden`.

## Branch model

- `upstream/master` — read-only upstream tracking.
- `linux-wayland` — integration branch (main development).
- `feature/native-wayland` — platform selection, WSI, diagnostics.
- `feature/vulkan-presentation` — swapchain/present/reliability.
- `feature/linux-optimizations` — measured Linux performance work.
- `packaging/arch` — PKGBUILD and packaging.
- `stable` — tested integration states.

All work is local. No remote named `origin` exists and nothing is pushed.
See `UPSTREAM_SYNC.md` for synchronization rules and
`tools/upstream-sync/audit-upstream.sh` for the automated audit.

## Documentation

| File | Content |
|---|---|
| `REPOSITORY_ACQUISITION.md` | Phase 0 report: upstream identity, license, versions, environment |
| `ARCHITECTURE.md` | Windowing, Vulkan, input, Linux integration audit with source map |
| `WAYLAND_IMPLEMENTATION_PLAN.md` | Tasks, files, risks, tests, acceptance criteria |
| `BUILD_ARCH.md` | Reproducible Arch builds, packaging, diagnostics |
| `TESTING.md` | Test matrix, tools, validation procedure, results log |
| `BENCHMARKS.md` | Benchmark methodology and (only real) results |
| `KNOWN_ISSUES.md` | Current defects, limitations and upstream quirks |
| `UPSTREAM_SYNC.md` | Sync policy, state, conflict handling |
| `PATCHES.md` | Categorized fork patch list |
| `evidence/` | Raw logs and screenshots from executed tests |

## Legal

GPL-3.0-or-later, matching upstream. No firmware, keys, or game files are
included, copied, or required for building. Testing requires content the user
is legally entitled to use.
