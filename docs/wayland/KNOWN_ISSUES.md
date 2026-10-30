# Known Issues and Limitations

State: audit and native-Wayland prototype complete (A1/A2/B1 landed on
`linux-wayland` through `41ad87851a`). Items are marked **[upstream]** when
present in `943f1fc7`, **[fork]** when introduced here (none yet), and
**[environment]** when they are local constraints. Runtime evidence lives in
`docs/wayland/evidence/`; verification status in `TESTING.md`.

## 1. Upstream behaviour that affects Wayland

| ID | Issue | Evidence | Planned |
|---|---|---|---|
| K1 | **Fixed (A1).** Wayland was discouraged by a modal dialog that recommended X11 and could persist `gui_force_x11` | `src/yuzu/main_window.cpp:4430-4477` | Replaced with neutral diagnostics |
| K2 | **Fixed (A1).** `QT_QPA_PLATFORM=xcb` could be forced by a persisted setting that overrode an explicit user choice | `src/yuzu/main.cpp:159-160` | Explicit setting still wins; ambient values are respected otherwise |
| K3 | **Fixed (A1).** `DISPLAY=:0` was set when `DISPLAY` was empty, even on pure Wayland sessions | `src/yuzu/main.cpp:155-157` | No longer set on Wayland sessions |
| K4 | Unknown Qt platforms fall back to `WindowSystemType::Windows` | `src/qt_common/qt_common.cpp:81-82` | Better error (A2) |
| K5 | `is_outdated` is set but ignored by `NeedsRecreation()` | `vk_swapchain.h:46-48` | Fix (D2) |
| K6 | Zero-extent surface returns early after overwriting metadata, leaving a stale swapchain; acquire uses an infinite timeout and the recreate loop is unbounded | `vk_swapchain.cpp:148-150,163`, `vk_present_manager.cpp:437-439` | Fix (D1) |
| K7 | Surface loss is unrecoverable on Linux (surface recreated only on Android); `DiscardFrame` submits a wait with no matching signal | `vk_present_manager.cpp:380-424` | Fix (D2) |
| K8 | No fallback when the preferred (discrete) GPU cannot present on the surface; initialization throws | `vulkan_device.cpp:1544-1579`, `vulkan_wrapper.cpp:50-69` | Fix (C1) |
| K9 | Instance asks for Vulkan 1.3 while only requiring 1.1; `apiVersion` parameter is ignored | `vulkan_wrapper.cpp:456-473` | Evaluate; low risk with current drivers |
| K10 | **Fixed (B1).** `wayland-client` headers were required by the Vulkan platform header but not declared in CMake | `vulkan.h:18-21`, `src/video_core/CMakeLists.txt` | `pkg_check_modules(WAYLAND_CLIENT)` added behind the desktop-Unix guard |
| K11 | Synchronous FIFO presentation on the GPU thread by default (`async_presentation=false` on desktop) | `src/common/settings.h:643-649`, `vk_present_manager.cpp:196-200` | Measure, then decide (D3) |
| K12 | Frame pacing is timer-based; no compositor presentation feedback | `vk_swapchain.cpp:182-212`, no `presentation-time` use | Document; optional future work |
| K13 | X11 borderless `HideFullscreen` restores flags from the wrong window | `main_window.cpp:3349` | Verify and fix if reproducible (F1) |
| K14 | `qvulkaninstance` is not used; Eden creates its own instance. This is intentional and not a bug, but diagnostics must not assume Qt's instance | `bootmanager.cpp:108-112`, `renderer_vulkan.cpp:134-143` | Document |
| K15 | Wayland fractional scales feed `width * devicePixelRatio` through a `u32` truncation | `bootmanager.cpp:186-193` | Fix (E1) |
| K16 | No handling of a pure DPR change without a resize | `bootmanager.cpp:937-943` | Fix (E1) |
| K17 | Official AppImage ships `bin/wayland-is-broken.hook`, which forces `QT_QPA_PLATFORM=xcb`, `SDL_VIDEO_DRIVER=x11`, `GDK_BACKEND=x11` and unsets `WAYLAND_DISPLAY` on Wayland unless `I_WANT_A_BROKEN_WAYLAND_UI=1`; the bundled Qt 6.11.1 Wayland plugin is nevertheless functional when opted in (observed: `xwayland=false`) | AppImage `AppDir/bin/wayland-is-broken.hook`, extracted v0.2.1 | Fork packaging must not ship this hook; document opt-in for the official binary (J1) |
| K18 | SDL CLI crashes on any early-exit path, including `--help`: `SDL_AppInit` allocates state but never assigns `*appstate`, so `SDL_AppQuit` dereferences null. Observed exit 139 on unmodified upstream | `src/yuzu_cmd/yuzu.cpp:165-166,333-335` | Report upstream; CLI is not part of the Wayland frontend |
| K19 | 8 unit tests fail on unmodified upstream in this environment, all in `MemoryTracker`; the test rasterizer's `UpdatePagesCachedBatch` is a no-op so counted paths never run | `src/tests/video_core/memory_tracker.cpp:47-49`; baseline 63/71 passed | Record as baseline; do not mask or "fix" tests to fake a green suite |
| K20 | Validation layers report upstream renderer/device issues: `VK_KHR_shader_quad_control` enabled without `VK_KHR_shader_maximal_reconvergence`; `StencilExportEXT` SPIR-V without the device extension; `R5G6B5_UNORM_PACK16` images created with storage usage that NVIDIA reports unsupported (`VUID-VkImageViewCreateInfo-usage-02275`) | `docs/wayland/evidence/2026-10-31-native-wayland-validation.log`; no swapchain/surface/present VUIDs | Report upstream; not Wayland- or fork-specific. Recheck after upstream sync |

## 2. Wayland-specific functional limitations

| ID | Limitation | Impact |
|---|---|---|
| L1 | Qt does not expose `zwp_pointer_constraints_v1`/relative-pointer; `QCursor::setPos()` is ineffective | Mouse-capture modes that warp the cursor do not work; absolute touch/mouse still work |
| L2 | Wayland has no exclusive fullscreen; `showFullScreen()` is used | Expected; monitor mode switching is compositor-controlled |
| L3 | Window position restore is compositor-controlled | Geometry may differ from the saved X11 position |
| L4 | `xdg-decoration` negotiation depends on the compositor | Hyprland may draw no server-side decorations; Qt falls back client-side |
| L5 | Presentation feedback (`wp_presentation`) is not used | No true latency measurement; pacing is approximate |
| L6 | Surface-lost/output-removal scenarios are hard to trigger non-destructively | Recovery is validated by code review and fault injection where possible |

## 3. NVIDIA / Optimus

| ID | Issue | Impact |
|---|---|---|
| N1 | **Confirmed.** Device sort prefers the discrete GPU unconditionally; `vulkan_device=0` selects the RTX 3050 on this laptop even without PRIME environment (`vulkaninfo` lists Intel as GPU0) | May initialise NVIDIA when the user expected Intel; no fallback yet if presentation fails (C1) |
| N2 | `prime-run` sets `__NV_PRIME_RENDER_OFFLOAD=1` and `__VK_LAYER_NV_optimus=NVIDIA_only`; without it, loader ICD order applies | Results must state the exact launch environment |
| N3 | 4 GiB VRAM is a hard limit for heavy titles at high scaling | Benchmark workload must fit; monitor VRAM |
| N4 | NVIDIA Wayland presentation support depends on driver/compositor cooperation | Must be verified on Hyprland, not assumed |
| N5 | TurboMode opens a second `VkDevice` | Extra resource use; only when enabled |

## 4. Environment constraints

| ID | Constraint |
|---|---|
| E1 | No keys or firmware; commercial NSP files in `~/Downloads` are not used. Presentation was verified with nx-hbmenu v3.6.1 (GPLv2) from `/tmp`, not committed |
| E2 | Single monitor, 1920x1080@120.21, scale 1; multi-monitor, fractional scaling and VRR require temporary config changes or hardware |
| E3 | `qt6-charts` still missing system-wide (build uses an extracted local copy); validation layers available only as an extracted package in `/tmp`; `wayland-info` not installed |
| E4 | `sudo` requires a password; dependency installation is performed by the user |
| E5 | Hyprland 0.56.2 and NVIDIA 615.78.08 are a specific combination; results are not generalizable without broader testing |

## 5. Reporting

When filing an issue, include:

- upstream/fork commit, build type;
- `tools/wayland/diag.sh` output;
- `hyprctl clients -j` entry for the window (proves native vs XWayland);
- Eden log with diagnostics (platform, surface, GPU, present mode);
- validation-layer messages if enabled;
- exact launch command and environment variables.
