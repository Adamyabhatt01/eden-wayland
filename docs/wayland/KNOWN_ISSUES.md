# Known Issues and Limitations

State: audit + plan complete; no fork code changes yet. Items are marked
**[upstream]** when present in `943f1fc7`, **[fork]** when introduced here
(none yet), **[environment]** when they are local constraints.

## 1. Upstream behaviour that affects Wayland

| ID | Issue | Evidence | Planned |
|---|---|---|---|
| K1 | Wayland is discouraged by a modal dialog that recommends X11 and can persist `gui_force_x11` | `src/yuzu/main_window.cpp:4430-4477` | Remove/neutralize in fork (A1) |
| K2 | `QT_QPA_PLATFORM=xcb` can be forced from a persisted setting | `src/yuzu/main.cpp:159-160` | Keep as explicit opt-in only (A1) |
| K3 | `DISPLAY=:0` is set when `DISPLAY` is empty, even on pure Wayland sessions | `src/yuzu/main.cpp:155-157` | Remove/restrict (A1) |
| K4 | Unknown Qt platforms fall back to `WindowSystemType::Windows` | `src/qt_common/qt_common.cpp:81-82` | Better error (A2) |
| K5 | `is_outdated` is set but ignored by `NeedsRecreation()` | `vk_swapchain.h:46-48` | Fix (D2) |
| K6 | Zero-extent surface returns early after overwriting metadata, leaving a stale swapchain; acquire uses an infinite timeout and the recreate loop is unbounded | `vk_swapchain.cpp:148-150,163`, `vk_present_manager.cpp:437-439` | Fix (D1) |
| K7 | Surface loss is unrecoverable on Linux (surface recreated only on Android); `DiscardFrame` submits a wait with no matching signal | `vk_present_manager.cpp:380-424` | Fix (D2) |
| K8 | No fallback when the preferred (discrete) GPU cannot present on the surface; initialization throws | `vulkan_device.cpp:1544-1579`, `vulkan_wrapper.cpp:50-69` | Fix (C1) |
| K9 | Instance asks for Vulkan 1.3 while only requiring 1.1; `apiVersion` parameter is ignored | `vulkan_wrapper.cpp:456-473` | Evaluate; low risk with current drivers |
| K10 | `wayland-client` headers are required by the Vulkan platform header but not declared in CMake | `vulkan.h:18-21`, `src/video_core/CMakeLists.txt` | Fix (B1) |
| K11 | Synchronous FIFO presentation on the GPU thread by default (`async_presentation=false` on desktop) | `src/common/settings.h:643-649`, `vk_present_manager.cpp:196-200` | Measure, then decide (D3) |
| K12 | Frame pacing is timer-based; no compositor presentation feedback | `vk_swapchain.cpp:182-212`, no `presentation-time` use | Document; optional future work |
| K13 | X11 borderless `HideFullscreen` restores flags from the wrong window | `main_window.cpp:3349` | Verify and fix if reproducible (F1) |
| K14 | `qvulkaninstance` is not used; Eden creates its own instance. This is intentional and not a bug, but diagnostics must not assume Qt's instance | `bootmanager.cpp:108-112`, `renderer_vulkan.cpp:134-143` | Document |
| K15 | Wayland fractional scales feed `width * devicePixelRatio` through a `u32` truncation | `bootmanager.cpp:186-193` | Fix (E1) |
| K16 | No handling of a pure DPR change without a resize | `bootmanager.cpp:937-943` | Fix (E1) |

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
| N1 | Device sort prefers the discrete GPU unconditionally; `vulkan_device=0` therefore selects the RTX 3050 on this laptop even without PRIME environment | May initialise NVIDIA when the user expected Intel; currently no fallback if presentation fails |
| N2 | `prime-run` sets `__NV_PRIME_RENDER_OFFLOAD=1` and `__VK_LAYER_NV_optimus=NVIDIA_only`; without it, loader ICD order applies | Results must state the exact launch environment |
| N3 | 4 GiB VRAM is a hard limit for heavy titles at high scaling | Benchmark workload must fit; monitor VRAM |
| N4 | NVIDIA Wayland presentation support depends on driver/compositor cooperation | Must be verified on Hyprland, not assumed |
| N5 | TurboMode opens a second `VkDevice` | Extra resource use; only when enabled |

## 4. Environment constraints

| ID | Constraint |
|---|---|
| E1 | No keys (`~/.local/share/eden/keys` is empty) and no homebrew content; commercial NSP files in `~/Downloads` will not be used |
| E2 | Single monitor, 1920x1080@120.21, scale 1; multi-monitor, fractional scaling and VRR require temporary config changes or hardware |
| E3 | `qt6-charts` missing at audit time (build blocker); validation layers and `wayland-info` not installed |
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
