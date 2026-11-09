# Fork Patch Inventory

All fork-specific modifications, grouped by subsystem. Keep this list in sync
with `git log upstream/master..linux-wayland`.

Base commit: `943f1fc76087adcfc893fb1ca3aea507df15d004`.
Source patches implemented: **A1, A2, B1, C1, D1, D2**. The remaining fork commits are
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
| A1 | `fix: stop steering Wayland sessions toward XWayland` | `src/yuzu/main.cpp`, `src/yuzu/main_window.cpp` | Removes the blocking "Wayland is known to have significant performance issues" modal. `DISPLAY` is only synthesized for non-Wayland sessions, and an explicit Force X11 setting now overrides an ambient `QT_QPA_PLATFORM`. Native-Wayland detection uses `QGuiApplication::platformName()`, never the environment variable. Verified: patched binary reports `Qt platform: wayland`; XWayland reports `xcb`; Force X11 with `QT_QPA_PLATFORM=wayland` produces an XWayland window per `hyprctl clients` |
| A2 | `diagnostics: log Vulkan window system, surface and swapchain state` | `renderer_vulkan.cpp`, `vk_swapchain.cpp`, `vulkan_surface.cpp` | Logs window system type, render surface handle/scale, WSI surface creation, swapchain extent/format/color space/present mode/image count, and surface capabilities. Avoids a public present-mode accessor by logging in `CreateSwapchain`. Verified with an hbmenu NRO on native Wayland (NVIDIA and Intel) and XWayland, including resize and fullscreen re-creations; validation layers reported no swapchain/surface/present VUIDs |
| B1 | `build: require wayland-client headers for the Vulkan Wayland surface` | `src/video_core/CMakeLists.txt` | `VK_USE_PLATFORM_WAYLAND_KHR` pulls in `<wayland-client.h>`, but nothing declared it. `pkg_check_modules` now fails configuration with a clear message when the headers are absent. Only include directories are added because Eden passes native handles through without calling `wl_*` functions. Verified: configure finds `wayland-client 1.26.0` |
| C1 | `fix: choose a Vulkan GPU that can present on the window surface` | `renderer_vulkan.cpp` | Enumerates every GPU with its present support, falls back to the next present-capable device when the configured one cannot present, and treats an out-of-range index as a loud error with a GPU[0] fallback. Verified on Hyprland: index 99 falls back to GPU[0] (NVIDIA) and still presents; index 1 selects Intel and presents a 1280x720 Wayland swapchain. Evidence is recorded in `TESTING.md` |
| D1 | `fix: handle zero-extent and minimised Wayland surfaces` | `vk_swapchain.h`, `vk_swapchain.cpp`, `vk_present_manager.h`, `vk_present_manager.cpp` | `Swapchain::Create()` now returns a drawable status and keeps the previous swapchain (with `oldSwapchain` chaining) when the surface reports no valid extent; acquire/present is skipped while not drawable; recreate attempts are bounded and the frame is discarded safely. Verified: native Wayland resize recreations present without validation errors. Zero-extent was not observed (Hyprland keeps valid extents), so minimised-surface behaviour is still unverified |
| D2 | `fix: recover from out-of-date and lost Wayland surfaces` | `vk_swapchain.h`, `vk_present_manager.h`, `vk_present_manager.cpp` | `NeedsRecreation()` includes `is_outdated`; surface recreation now runs on all platforms from the stored `WindowSystemInfo` with the correct destruction order (`CreateSurface` → `swapchain.Reset()` → assign); `DiscardFrame` tracks whether `render_ready` was consumed and never waits on it twice. Verified: build passes, hbmenu resize/present path is clean. No `VK_ERROR_SURFACE_LOST_KHR` was triggered at runtime, so surface-loss recovery is not yet observed |

## Planned patches (not yet implemented)

| ID | Commit subject (planned) | Files | Phase | Notes |
|---|---|---|---|---|
| C2 | `fix: report actionable Vulkan initialization failures` | `renderer_vulkan.cpp`, `bootmanager.cpp` | 4 | Device matrix in error path |
| E1 | `fix: use rounded framebuffer extents for fractional scaling` | `bootmanager.cpp` | 4 | Handles DPR changes |
| F1 | `fix: correct fullscreen window flag restoration` | `main_window.cpp` | 4 | Verify before changing; may be upstream-only bug |
| J1 | `packaging: add Arch Linux PKGBUILD` | `packaging/arch/PKGBUILD` | 6 | Runtime dep on `qt6-wayland` |
| H1 | `test: add native Wayland diagnostic harness` | `tools/wayland/`, `tests/` | 3–6 | Partially implemented: `diag.sh` and `vk-present-probe.c` (environment-level surface support). Emulator-internal self-test still pending |

Planned patches will be re-evaluated after the baseline build; some may be
unnecessary once runtime behaviour is observed. No patch is claimed as
implemented until it is committed and tested.

## Interaction with upstream

- Prefer changes that upstream would accept (small, platform-neutral where
  possible).
- If upstream later implements the same behaviour, remove the fork patch and
  record it here.
- Never modify `upstream/master`.

## Dropped / superseded patches

None.
