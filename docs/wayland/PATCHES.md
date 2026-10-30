# Fork Patch Inventory

All fork-specific modifications, grouped by subsystem. Keep this list in sync
with `git log upstream/master..linux-wayland`.

Base commit: `943f1fc76087adcfc893fb1ca3aea507df15d004`.
Source patches implemented: **none**. Fork commits currently present:

| Commit | Subject |
|---|---|
| `d9d8f4dd4a` | `docs: add Wayland architecture audit and implementation plan` |
| `405e31b065` | `test: add upstream sync audit and Wayland diagnostics tooling` |
| `c073794101` | `build: add development, release and portable run scripts` |
| `f4d76ccd44` | `docs: record official AppImage native Wayland and XWayland evidence` |

None of these change emulator behaviour. They are documentation, scripts, and
read-only diagnostics.

## Categorization rules

| Prefix | Scope |
|---|---|
| `build:` | CMake, dependencies, packaging inputs |
| `feat:` | New Wayland/platform behaviour |
| `fix:` | Correctness/reliability in presentation or integration |
| `perf:` | Measured performance changes only |
| `test:` | Automated tests, diagnostics, harnesses |
| `docs:` | Documentation only |
| `packaging:` | PKGBUILD, desktop integration |

## Planned patches (not yet implemented)

| ID | Commit subject (planned) | Files | Phase | Notes |
|---|---|---|---|---|
| A1 | `feat: prefer native Wayland on Wayland sessions` | `src/yuzu/main.cpp`, `src/yuzu/main_window.cpp`, UI settings | 3 | Removes forced X11 and blocking warning; keeps opt-in fallback. Runtime evidence: default official AppImage runs `xwayland=true`; opt-in runs native. Fork packaging must also omit `wayland-is-broken.hook` (K17) |
| A2 | `feat: add Wayland/Vulkan runtime diagnostics` | `qt_common/qt_common.cpp`, `renderer_vulkan.cpp`, `vk_swapchain.cpp` | 3 | Proves platform, surface, GPU, present mode |
| B1 | `build: declare wayland-client dependency` | `CMakeLists.txt`, `src/video_core/CMakeLists.txt` | 3 | Headers for `vulkan_wayland.h` |
| C1 | `fix: select a GPU that can present on the Wayland surface` | `renderer_vulkan.cpp`, `vulkan_device.cpp` | 4 | Fallback with loud diagnostics; respects explicit choice |
| C2 | `fix: report actionable Vulkan initialization failures` | `renderer_vulkan.cpp`, `bootmanager.cpp` | 4 | Device matrix in error path |
| D1 | `fix: handle zero-extent and minimised Wayland surfaces` | `vk_swapchain.*`, `vk_present_manager.cpp` | 4 | No stale swapchain, bounded retries |
| D2 | `fix: recover from out-of-date and lost Wayland surfaces` | `vk_swapchain.h`, `vk_present_manager.*`, `renderer_vulkan.*` | 4 | Linux surface recreation, safe frame discard |
| E1 | `fix: use rounded framebuffer extents for fractional scaling` | `bootmanager.cpp` | 4 | Handles DPR changes |
| F1 | `fix: correct fullscreen window flag restoration` | `main_window.cpp` | 4 | Verify before changing; may be upstream-only bug |
| J1 | `packaging: add Arch Linux PKGBUILD` | `packaging/arch/PKGBUILD` | 6 | Runtime dep on `qt6-wayland` |
| H1 | `test: add native Wayland diagnostic harness` | `tools/wayland/`, `tests/` | 3–6 | Proves surface/swapchain without commercial content |

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
