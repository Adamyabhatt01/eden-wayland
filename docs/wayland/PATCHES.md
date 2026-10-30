# Fork Patch Inventory

All fork-specific modifications, grouped by subsystem. Keep this list in sync
with `git log upstream/master..linux-wayland`.

Base commit: `943f1fc76087adcfc893fb1ca3aea507df15d004`.
Source patches implemented: **A1, A2**. The remaining fork commits are
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
| A2 | `diagnostics: log Vulkan window system, surface and swapchain state` | `renderer_vulkan.cpp`, `vk_swapchain.cpp`, `vulkan_surface.cpp` | Logs window system type, render surface handle/scale, WSI surface creation, swapchain extent/format/color space/present mode/image count, and surface capabilities. Avoids a public present-mode accessor by logging in `CreateSwapchain` |

## Planned patches (not yet implemented)

| ID | Commit subject (planned) | Files | Phase | Notes |
|---|---|---|---|---|
| B1 | `build: declare wayland-client dependency` | `CMakeLists.txt`, `src/video_core/CMakeLists.txt` | 3 | Headers for `vulkan_wayland.h` |
| C1 | `fix: select a GPU that can present on the Wayland surface` | `renderer_vulkan.cpp`, `vulkan_device.cpp` | 4 | Fallback with loud diagnostics; respects explicit choice |
| C2 | `fix: report actionable Vulkan initialization failures` | `renderer_vulkan.cpp`, `bootmanager.cpp` | 4 | Device matrix in error path |
| D1 | `fix: handle zero-extent and minimised Wayland surfaces` | `vk_swapchain.*`, `vk_present_manager.cpp` | 4 | No stale swapchain, bounded retries |
| D2 | `fix: recover from out-of-date and lost Wayland surfaces` | `vk_swapchain.h`, `vk_present_manager.*`, `renderer_vulkan.*` | 4 | Linux surface recreation, safe frame discard |
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
