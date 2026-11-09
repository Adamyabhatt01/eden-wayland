# Fork Patch Inventory

All fork-specific modifications, grouped by subsystem. Keep this list in sync
with `git log upstream/master..linux-wayland`.

Base commit: `ae60f8e7f85915a2b79d98b49e3134bbdbeca471` (2026-11-08 upstream sync, staged).
Source patches committed: **A1, A2, B1, C1, D1, D2**. The hybrid Wayland-first delta
(`QtCommon::SetupApplication()`), C2, E1, F1 and J1 are implemented in the
working tree but **not committed** (AGENTS.md leaves commits to the user).
The remaining fork commits are
documentation, read-only diagnostics, or build/run scripts. Run
`git log --oneline upstream/master..linux-wayland` for the current list
(hashes are kept out of this file so it cannot go stale).

## Categorization rules

| Prefix | Scope |
|---|---|
| `build:` | CMake, dependencies, packaging inputs |
| `feat:` | New Wayland/platform behaviour |
| `fix:` | Correctness/reliability in presentation or integration |
| `perf:` | Measured performance changes only |
| `test:` | Automated tests, diagnostics, harnesses |
| `diagnostics:` | Runtime logging added for verification |
| `docs:` | Documentation only |
| `packaging:` | PKGBUILD, desktop integration |

## Implemented patches

| ID | Commit subject | Files | Notes |
|---|---|---|---|
| A1 | `fix: stop steering Wayland sessions toward XWayland` | `src/qt_common/qt_common.cpp` (`QtCommon::SetupApplication()`) | Fork delta after the 2026-11-09 upstream sync (upstream `9c3bdeffc0` deleted the modal, the `gui_force_x11` mechanism and `OnCheckGraphicsBackend`; its `SetupApplication()` defaults `QT_QPA_PLATFORM=xcb;wayland`): this fork defaults `QT_QPA_PLATFORM=wayland` when unset (an explicit value, e.g. `xcb` for XWayland, always wins) and synthesises `DISPLAY` only for non-Wayland selections. Verified: with a clean environment the default launch reports `Qt Platform Backend: wayland` with `xwayland=false`; `QT_QPA_PLATFORM=xcb` reports `xcb` with an Xlib surface. Evidence in `TESTING.md` |
| A2 | `diagnostics: log Vulkan window system, surface and swapchain state` | `renderer_vulkan.cpp`, `vk_swapchain.cpp`, `vulkan_surface.cpp` | Logs window system type, render surface handle/scale, WSI surface creation, swapchain extent/format/color space/present mode/image count, and surface capabilities. Avoids a public present-mode accessor by logging in `CreateSwapchain`. Verified with an hbmenu NRO on native Wayland (NVIDIA and Intel) and XWayland, including resize and fullscreen re-creations; validation layers reported no swapchain/surface/present VUIDs. The 2026-11-09 upstream sync removed the `OnCheckGraphicsBackend` diagnostic in `main_window.cpp`; upstream's own `Qt Platform Backend` log line now covers it |
| B1 | `build: require wayland-client headers for the Vulkan Wayland surface` | `src/video_core/CMakeLists.txt` | `VK_USE_PLATFORM_WAYLAND_KHR` pulls in `<wayland-client.h>`, but nothing declared it. `pkg_check_modules` now fails configuration with a clear message when the headers are absent. Only include directories are added because Eden passes native handles through without calling `wl_*` functions. Verified: configure finds `wayland-client 1.26.0` |
| C1 | `fix: choose a Vulkan GPU that can present on the window surface` | `renderer_vulkan.cpp` | Enumerates every GPU with its present support, falls back to the next present-capable device when the configured one cannot present, and treats an out-of-range index as a loud error with a GPU[0] fallback. Verified on Hyprland: index 99 falls back to GPU[0] (NVIDIA) and still presents; index 1 selects Intel and presents a 1280x720 Wayland swapchain. Evidence is recorded in `TESTING.md` |
| D1 | `fix: handle zero-extent and minimised Wayland surfaces` | `vk_swapchain.h`, `vk_swapchain.cpp`, `vk_present_manager.h`, `vk_present_manager.cpp` | `Swapchain::Create()` now returns a drawable status and keeps the previous swapchain (with `oldSwapchain` chaining) when the surface reports no valid extent; acquire/present is skipped while not drawable; recreate attempts are bounded and the frame is discarded safely. Verified: native Wayland resize recreations present without validation errors. Zero-extent was not observed (Hyprland keeps valid extents), so minimised-surface behaviour is still unverified |
| D2 | `fix: recover from out-of-date and lost Wayland surfaces` | `vk_swapchain.h`, `vk_present_manager.h`, `vk_present_manager.cpp` | `NeedsRecreation()` includes `is_outdated`; surface recreation now runs on all platforms from the stored `WindowSystemInfo` with the correct destruction order (`CreateSurface` → `swapchain.Reset()` → assign); `DiscardFrame` tracks whether `render_ready` was consumed and never waits on it twice. Verified: build passes, hbmenu resize/present path is clean. No `VK_ERROR_SURFACE_LOST_KHR` was triggered at runtime, so surface-loss recovery is not yet observed |

## In working tree (implemented, pending commit)
|---|---|---|---|---|
| C2 | `fix: report actionable Vulkan initialization failures` | `renderer_vulkan.cpp` | The constructor catch block now names the window system and adds prime-run/`QT_QPA_PLATFORM` guidance (Linux-guarded) to the error that reaches `VideoCore::CreateGPU`; the device matrix is already logged by `CreateDevice`. Verified: a forced init failure (`VK_LOADER_DRIVERS_SELECT` with no devices) logs `Vulkan initialization failed on window system Wayland ...` + the hint + `Failed to initialize GPU: Vulkan initialization error ... (window system: Wayland)`. Evidence: `2026-11-09-c2-enriched-error-eden.log` |
| E1 | `fix: use rounded framebuffer extents for fractional scaling` | `src/yuzu/bootmanager.cpp`, `src/yuzu/bootmanager.h` | `OnFramebufferSizeChanged` now rounds (no `u32` truncation); a `QScreen::logicalDotsPerInchChanged` connection (re-connected on `screenChanged`) refreshes the framebuffer on a pure DPR change without a resize. Code-verified: Qt 6.12 QWindow headers confirm `screenChanged` + QScreen DPI notifier (no QWindow DPI signal exists); a first attempt crashed on a null `windowHandle()` (coredump) and was fixed with a null guard. Fractional-scale runtime behaviour was not exercised (single 1920x1080@120 monitor at scale 1) |
| F1 | `fix: correct fullscreen window flag restoration` | `src/yuzu/main_window.cpp` | `HideFullscreen` (two-window mode) now modifies `render_window->windowFlags()` instead of `MainWindow`'s flags. Code-verified: a one-line wrong-window bug confirmed by reading; F11 toggle runtime verification not yet run |
| J1 | `packaging: add Arch Linux PKGBUILD` | `packaging/arch/PKGBUILD` | Runtime dep on `qt6-wayland`; makepkg --printsrcinfo validation passed; full makepkg build not yet run (no origin remote) |

## Planned patches (not yet implemented)

| ID | Commit subject (planned) | Files | Phase | Notes |
|---|---|---|---|---|
| H1 | `test: add native Wayland diagnostic harness` | `tools/wayland/`, `tests/` | 3–6 | Partially implemented: `diag.sh` and `vk-present-probe.c` (environment-level surface support); `tools/wayland/benchmark.sh` added for Phase 5 benchmarks. Emulator-internal self-test still pending |

Planned patches will be re-evaluated after the baseline build; some may be
unnecessary once runtime behaviour is observed. No patch is claimed as
implemented until it is committed and tested.

## Interaction with upstream

**Portability rule (hard constraint for every fork patch):** this fork must
stay easy to keep in sync with upstream. Every patch must satisfy all of the
following:

1. Keep the diff small and localized to the subsystem it touches.
2. Do not rename/move upstream code or restructure upstream files; prefer a
   small helper or a guarded branch (platform- or feature-guarded) over
   rewriting upstream logic.
3. Do not change behaviour on platforms/paths other than the one the patch
   targets (e.g. a Wayland fix must not alter Windows/Android/X11 behaviour),
   so an upstream port of the same area keeps working.
4. Put fork-only files under `docs/wayland/`, `tools/wayland/`,
   `tools/upstream-sync/`, and `packaging/` where possible.
5. Record every patch in this inventory with the upstream base commit it was
   written against, so a later import can be reapplied or dropped cleanly.

If a patch would violate any of these, stop and discuss it before writing code.

## Dropped / superseded patches

None.
