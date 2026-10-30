# Native Wayland Implementation Plan

Base: `upstream/master` @ `943f1fc76087adcfc893fb1ca3aea507df15d004`
(2026-10-30). Companion documents: `ARCHITECTURE.md`, `TESTING.md`,
`UPSTREAM_SYNC.md`, `PATCHES.md`.

## 1. Current architecture (short)

- Qt 6 Widgets frontend creates a native child `QWidget` (`RenderWidget`) with
  a `QWindow`; Qt's Wayland QPA creates the `wl_surface`.
- `QtCommon::GetWindowSystemInfo()` extracts `wl_display*`/`wl_surface*`
  through `QPlatformNativeInterface` and passes an opaque
  `WindowSystemInfo` to the renderer.
- `Vulkan::CreateSurface()` already creates `VkSurfaceKHR` with
  `vkCreateWaylandSurfaceKHR`; the instance requests
  `VK_KHR_wayland_surface`.
- The Vulkan renderer owns instance/device/swapchain and presents with
  `vkQueuePresentKHR`. Qt's `QVulkanInstance` is unused, so there is only one
  Wayland connection and one Vulkan instance.
- XWayland remains available through Qt's `xcb` QPA plugin, selectable with
  `QT_QPA_PLATFORM=xcb` or the persisted `gui_force_x11` setting.

## 2. Existing Wayland support

| Area | State |
|---|---|
| Qt QPA Wayland | Supported by Qt 6.12 (plugin in `qt6-base`, `qt6-wayland` libs) |
| Window creation | Native child surface via `WA_NativeWindow` + `WA_DontCreateNativeAncestors` |
| `wl_display`/`wl_surface` extraction | Implemented |
| `VK_KHR_wayland_surface` | Implemented |
| App id (`xdg_toplevel.app_id`) | Implemented (`dev.eden_emu.eden`) |
| Wayland-first defaults | **No** — app may force X11 and warns users away from Wayland |
| Surface-loss recovery | **No** on Linux |
| Minimise/zero-extent robustness | **Weak** |
| GPU fallback on present failure | **No** |
| Fractional-scale correctness | **Unverified**, truncation risk |
| Pointer constraints | **No** (Qt limitation) |
| Runtime platform/surface proof | **No** dedicated diagnostics |

## 3. Design principles for the fork

1. Reuse Qt's Wayland support. Do not add a second `wl_display`, custom
   protocol code, or an SDL window in the Qt frontend.
2. Keep the `EmuWindow`/`WindowSystemInfo` contract. It is the platform
   abstraction; the emulation core must not learn about Wayland.
3. Keep Vulkan rendering backend-agnostic. Only surface creation and
   recreation are platform-specific.
4. Make every change independently reviewable and upstream-mergeable.
5. Measure before changing performance defaults.
6. Preserve XWayland as an explicit fallback at all times.

## 4. Workstreams and tasks

Complexity: S = < 1 day, M = 1–3 days, L = > 3 days / design work.
Priority: P0 = required for native Wayland; P1 = reliability; P2 = polish.

### A. Wayland-first policy and diagnostics (P0)

#### A1. Make Wayland the default on Wayland sessions
- Files: `src/yuzu/main.cpp` (Unix block `:152-164`),
  `src/yuzu/main_window.cpp` (`OnCheckGraphicsBackend`, `:4430-4477`),
  `src/qt_common/config/uisettings.h:151-155`,
  `src/qt_common/config/shared_translation.cpp:349-350`.
- Changes:
  - Stop forcing `QT_QPA_PLATFORM=xcb` by default. Keep `gui_force_x11` as an
    explicit opt-in and as an environment override.
  - Remove the blocking "Wayland is known to have significant performance
    issues" dialog from the fork, or replace it with a non-blocking,
    once-per-profile informational log line. Do not persist force-X11 without
    an explicit user action.
  - Stop setting `DISPLAY=:0` when `DISPLAY` is empty. Only set it when an X11
    session is actually detected, or drop the fallback (it primarily exists
    for AppImage/browser launching; use `QDesktopServices` semantics).
  - Detect `XDG_SESSION_TYPE=wayland`/`WAYLAND_DISPLAY` only for logging and
    for choosing a sensible default; never override an explicit
    `QT_QPA_PLATFORM` or `-platform` argument.
- Dependencies: none.
- Risks: users on broken Wayland drivers lose the automatic X11 escape hatch;
  mitigate by keeping the Force X11 setting and documenting
  `QT_QPA_PLATFORM=xcb`.
- Tests: fresh profile in Hyprland; verify `QGuiApplication::platformName()`
  is `wayland`; verify `QT_QPA_PLATFORM=xcb` and the setting still force X11;
  verify XWayland run still works.
- Acceptance: no environment variables required for native Wayland; X11 path
  unchanged when explicitly requested; no modal warning.
- Complexity: S.

#### A2. Runtime diagnostics
- Files: `src/qt_common/qt_common.cpp` (GetWindowSystemInfo),
  `src/video_core/renderer_vulkan/renderer_vulkan.cpp`,
  `src/video_core/renderer_vulkan/vk_swapchain.cpp`, `src/yuzu/main.cpp`.
- Changes: log (INFO, no debug UI required):
  - Qt platform name, session type, presence of `wl_display`/`wl_surface`,
    `devicePixelRatio`, logical size, framebuffer size;
  - `WindowSystemType`, chosen physical device name/type/vendor/driver/API,
    UUID, queue families, present support result;
  - surface format, present mode, image count, extent, composite alpha,
    transform, swapchain recreation reasons.
  - Optional `EDEN_VK_DIAG=1` to raise verbosity and print a compact report at
    startup and at first present.
- Risks: log noise; gate verbose output behind an env var.
- Tests: run and compare logs on Wayland and XWayland, Intel and NVIDIA.
- Acceptance: a single log block proves platform, surface type, GPU and
  present mode; usable in bug reports.
- Complexity: S.

### B. Build and dependency correctness (P0)

#### B1. Declare Wayland client headers
- Files: `src/video_core/CMakeLists.txt`, top-level `CMakeLists.txt`.
- Changes: on Linux, locate `wayland-client` via
  `pkg_check_modules(WAYLAND_CLIENT REQUIRED IMPORTED_TARGET wayland-client)`
  and link/include it for `video_core` (no functional symbol use; the
  platform header includes `wayland-client.h`). Keep the code portable by
  gating on `LINUX`.
- Risks: none functional; improves reproducibility.
- Tests: clean configure on a container/VM without X11 headers.
- Acceptance: configure fails early with a clear message if Wayland headers
  are missing, rather than a deep compile error.
- Complexity: S.

#### B2. Packaging dependencies
- Files: `packaging/arch/PKGBUILD` (new), docs.
- Runtime dependency must include `qt6-wayland` (Qt platform plugin) in
  addition to `qt6-base`, `sdl3`, `ffmpeg`, `vulkan-icd-loader`, `cubeb`,
  `libusb`, `gamemode` (optional), `libxkbcommon`, `wayland`.
- Tests: `makepkg` in a clean chroot, install, run native Wayland.
- Acceptance: package runs native Wayland without manual plugin install.
- Complexity: S–M.

### C. GPU selection and Optimus robustness (P0/P1)

#### C1. Present-support-aware device selection with fallback
- Files: `src/video_core/renderer_vulkan/renderer_vulkan.cpp`
  (`CreateDevice`, `:112-121`),
  `src/video_core/vulkan_common/vulkan_device.cpp`
  (`SetupFamilies`, `:1544-1579`; possibly a new helper),
  `src/video_core/vulkan_common/vulkan_wrapper.cpp` (keep sort, expose
  diagnostic info).
- Changes:
  - Before constructing `Device`, test whether at least one queue family of
    the candidate reports `vkGetPhysicalDeviceSurfaceSupportKHR == VK_TRUE`
    for the actual `VkSurfaceKHR`.
  - Iterate candidates: first the user-configured `vulkan_device` index, then
    the remaining sorted devices. Use the first device that supports
    graphics + present. If the configured device is unsupported, log a
    prominent warning and explain the fallback; do not silently switch.
  - If no device supports present, throw with a report listing every device,
    vendor, type, driver and present support. Surface that report in the
    frontend error dialog.
  - Keep NVIDIA-specific workarounds confined to existing
    `vulkan_device.cpp` vendor code; do not hardcode NVIDIA in the selection
    path.
- Risks: changing selection order can surprise users on multi-GPU systems;
  mitigate with logs and by respecting an explicit supported choice.
- Tests: see `TESTING.md` §GPU matrix (Intel-only, NVIDIA-only, prime-run,
  invalid `vulkan_device` index, unsupported device simulation).
- Acceptance: on this laptop, default startup works with both GPUs; explicit
  selection is honoured when present-capable; unsupported selection produces
  a clear error and a documented fallback.
- Complexity: M.

#### C2. Actionable Vulkan failure diagnostics
- Files: `renderer_vulkan.cpp`, `src/yuzu/bootmanager.cpp` (renderer init
  failure path), `src/qt_common/util/vk.cpp` (device list metadata).
- Changes: show device name/type/driver and surface support in the error
  dialog; add a log line with `prime-run`/`QT_QPA_PLATFORM` guidance.
- Complexity: S.

### D. Presentation reliability on Wayland (P0/P1)

#### D1. Zero-extent / minimised handling
- Files: `src/video_core/renderer_vulkan/vk_swapchain.cpp/.h`,
  `vk_present_manager.cpp`.
- Changes:
  - Treat a 0x0 `maxImageExtent` as "surface not drawable": do not publish
    new width/height, do not acquire/present, and retry recreation on the
    next frame. Never spin in the unbounded
    `while (AcquireNextImage()) RecreateSwapchain(...)` loop; bound attempts
    and skip the frame.
  - Preserve the previous swapchain until a valid extent is available; use
    `oldSwapchain` when creating the replacement to avoid a window of
    undefined content.
- Risks: touching the shared Vulkan path affects Windows/Android; keep the
  logic platform-neutral and test all backends compile.
- Tests: minimise/restore, hide/show, resize to minimum, restore from
  fullscreen; validation layers must stay clean.
- Acceptance: no hang, no validation error, no stale frame after restore.
- Complexity: M.

#### D2. Out-of-date and surface-loss recovery
- Files: `vk_swapchain.h` (`NeedsRecreation`), `vk_swapchain.cpp`,
  `vk_present_manager.cpp/.h`, `renderer_vulkan.cpp/.h`.
- Changes:
  - Include `is_outdated` in `NeedsRecreation()`.
  - On `VK_ERROR_SURFACE_LOST_KHR`, recreate `VkSurfaceKHR` from the stored
    `WindowSystemInfo` on Linux, then recreate the swapchain and semaphores.
    Ownership stays with `RendererVulkan::surface`; provide a narrow
    recreation hook rather than duplicating surface ownership.
  - Replace `DiscardFrame`'s unpaired semaphore wait with a safe path that
    always retires the frame.
  - Keep behaviour on other platforms unchanged.
- Risks: surface recreation during teardown can race the Qt widget
  destruction; serialise with renderer lifecycle (`ReleaseRenderTarget`).
- Tests: stop/start game repeatedly; resize during load; (if feasible) force
  a surface-lost fault via a test hook; compositor restart is destructive and
  will be documented rather than automated.
- Acceptance: no crash/hang on repeated renderer init/teardown; surface loss
  recovers when the window still exists.
- Complexity: M.

#### D3. Present mode and frame pacing policy (measurement-gated)
- Files: `vk_swapchain.cpp` (`ChooseSwapPresentMode`),
  `src/common/settings.h` (defaults), `vk_present_manager.cpp`.
- Changes: only after benchmarks:
  - determine which present modes the Wayland WSI exposes on Mesa Intel and
    NVIDIA 615;
  - compare FIFO, MAILBOX, IMMEDIATE and `async_presentation` on/off;
  - consider enabling `async_presentation` by default on Wayland or
    auto-selecting MAILBOX when the compositor reports it, if measurements
    show lower frame-time variance without corruption;
  - do not force FIFO for frame-gen unless measured necessary on Wayland.
- Risks: async present can increase latency; MAILBOX can tear under some
  compositors; never enable without data.
- Tests: `BENCHMARKS.md` scenarios.
- Acceptance: any default change is backed by measured data and documented.
- Complexity: M.

### E. HiDPI and fractional scaling (P1)

#### E1. Correct pixel math and DPR-change handling
- Files: `src/yuzu/bootmanager.cpp` (`OnFramebufferSizeChanged`, `:186-193`;
  `windowPixelRatio`, `:220-222`; `showEvent`, `:937-943`),
  `src/yuzu/main.cpp` (`GetHighDpiRoundingPolicy`).
- Changes:
  - Compute framebuffer size with rounding
    (`std::lround(width * dpr)`) instead of truncation, and keep the layout
    consistent with QWindow logical size.
  - React to `QEvent::DevicePixelRatioChange` (or the QWindow/QScreen signal
    available in Qt 6.12) by updating the framebuffer layout, not only on
    resize/screen change.
  - Keep `PassThrough` rounding on Wayland so fractional scales are not
    silently rounded to integers.
- Tests: scale 1.0, 1.25, 1.5, 2.0 (via temporary Hyprland monitor scale
  override with explicit user permission); verify extent, touch mapping,
  swapchain recreation and no validation errors.
- Acceptance: correct extents at all tested scales; no off-by-one swapchain
  churn; input coordinates match.
- Complexity: S–M.

### F. Fullscreen, focus and session lifecycle (P1)

#### F1. Verify and fix fullscreen paths
- Files: `src/yuzu/main_window.cpp` (`ShowFullscreen`, `HideFullscreen`,
  `UsingExclusiveFullscreen`, `:3271-3355`), `bootmanager.cpp`.
- Changes: verify `showFullScreen()` on Hyprland; ensure borderless/exclusive
  semantics do not double-handle geometry; fix the `HideFullscreen`
  `windowFlags()` source bug (`:3349`) as a separate, upstreamable commit if
  it reproduces. Add diagnostics for fullscreen state.
- Tests: fullscreen on/off, workspace switch, focus loss/restore, monitor
  change, 120 Hz; see `TESTING.md`.
- Acceptance: no stuck fullscreen, no lost input after focus changes, correct
  restore geometry where the compositor permits.
- Complexity: S–M.

#### F2. Suspend/resume and shutdown
- Files: `main_window.cpp` (`PrepareForSleep` `:1738-1779`; shutdown
  `:2136-2138`), `bootmanager.cpp` (close path).
- Changes: verify pause/resume and clean renderer teardown; add logs; no
  architectural change expected.
- Tests: suspend/resume via logind; close during emulation; reopen.
- Complexity: S.

### G. Input (P2)

- Verify Qt keyboard/mouse/touch and SDL3 gamepad/hotplug under Wayland.
- Document that cursor warping/pointer lock is unavailable through Qt; mouse
  aiming modes that rely on `QCursor::setPos()` do not work. A future
  implementation would need `zwp_pointer_constraints_v1`/relative-pointer,
  which Qt does not expose publicly; do not add custom protocol code without
  a design review.
- No changes planned in Phase 1.

### H. Testing and tooling (P0)

- `tools/wayland/diag.sh`: read-only environment report.
- `tools/upstream-sync/audit-upstream.sh`: upstream change/conflict audit.
- `TESTING.md`: manual + automated matrix, validation-layer procedure.
- A dedicated render self-test is **required** to verify the Vulkan Wayland
  path without commercial content. Options, in order of preference:
  1. Run a legal homebrew NRO (no keys required) supplied by the user;
  2. add a small `eden-vk-probe` test executable that reuses
     `vulkan_common` instance/surface helpers and a minimal Qt window to
     create a surface, swapchain and present N clear frames, reporting
     device/present mode/extent. It must not touch the emulation core.
- Acceptance: at least one automated run proves Qt/Wayland + Vulkan surface +
  present on both GPUs, with validation layers enabled, before claiming
  native Wayland works.

### I. Upstream synchronization (P0)

- Implemented now: `tools/upstream-sync/audit-upstream.sh`, `UPSTREAM_SYNC.md`,
  `PATCHES.md`, branch layout.
- Policy: merge complete `upstream/master` into `linux-wayland`; do not
  cherry-pick unless a commit cannot wait. Re-run the audit before each
  merge, resolve conflicts preserving both sides, rerun the full test matrix.

### J. Packaging and release (P1)

- `packaging/arch/PKGBUILD` for a source build of a pinned commit/tag.
- Release build script with `-DCMAKE_BUILD_TYPE=Release`, LTO per project
  defaults, Ninja; optional debug/sanitizer builds.
- AppImage: feasible but conflicts with the "do not bundle system Qt"
  requirement. Provide an optional recipe only if it can use a pinned
  toolchain Qt and be clearly labelled non-default; otherwise document why
  it is not shipped.
- Installation/uninstallation documented; no bundled keys/firmware/games.

## 5. Phased execution

| Phase | Deliverable | Gate |
|---|---|---|
| 0 | Repository report | Upstream verified, workspace created (done) |
| 1 | Architecture audit | Source map verified against code (done) |
| 2 | This plan | Approved roadmap (done) |
| 3 | Baseline + native Wayland prototype | Upstream and fork run under Wayland; platform, surface, GPU and frames verified |
| 4 | Reliability | D1, D2, E1, F1/F2 validated on Hyprland |
| 5 | Optimization | D3 with benchmark evidence only |
| 6 | Packaging | PKGBUILD builds and installs; runtime diagnostics script |
| 7 | Final audit | Regression matrix vs upstream; known issues documented |

## 6. Performance strategy

1. Establish baselines before any presentation change:
   upstream XWayland, fork XWayland, fork native Wayland, Intel and NVIDIA.
2. Metrics: average FPS, 1% lows, frame-time p50/p95/p99, CPU/GPU utilisation,
   VRAM/RSS, present mode, swapchain recreations, shader-compile stutter.
3. Tools: MangoHud (CSV logging), `vulkaninfo`, validation layers,
   `WAYLAND_DEBUG` (protocol trace, short captures), `journalctl`,
   `/proc` sampling; RenderDoc/apitrace only if installed.
4. Only keep changes that show a repeatable improvement outside noise; no
   "Wayland is faster" claims without measurements.
5. Suspected bottlenecks to investigate first: synchronous FIFO present on
   the GPU thread, double copy (blit to intermediate then swapchain), frame
   pacing timers, and swapchain recreation cost.

## 7. Known limitations of this plan

- Requires legal test content or a self-test binary; no keys/games exist in
  the environment and commercial NSP files will not be used.
- Only one monitor (1920x1080@120, scale 1) is currently connected;
  multi-monitor and fractional-scale tests need temporary configuration
  changes or additional hardware (user approval required).
- Wayland surface-lost and output-removal scenarios are difficult to trigger
  non-destructively; some validation will be code-level plus fault injection.
- Pointer constraints cannot be implemented through public Qt APIs.
- Upstream may change the same files; all patches must stay small and
  isolated (see `UPSTREAM_SYNC.md`).
