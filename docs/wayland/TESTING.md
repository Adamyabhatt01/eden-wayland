# Testing Strategy

No result in this file may be recorded until it has actually been observed.
"Application opens" is not evidence of native Wayland or a working Vulkan
surface.

## 1. Environment verification (per session)

```sh
tools/wayland/diag.sh
```

Required facts before any test:

- `XDG_SESSION_TYPE=wayland`, `WAYLAND_DISPLAY` set, `HYPRLAND_INSTANCE_SIGNATURE` set.
- `libqwayland.so` present in the Qt platform plugin directory and all its
  dependencies resolve.
- `vulkaninfo --summary` lists both GPUs and their driver versions.
- `prime-run vulkaninfo --summary` shows the NVIDIA GPU as the selected
  device (when testing PRIME).

## 2. Runtime platform proof (not just env vars)

Setting `QT_QPA_PLATFORM=wayland` is **not** proof. Collect at least two
independent signals:

1. Eden's own diagnostics log (added in Phase 3) must print
   `QGuiApplication::platformName()` and the `WindowSystemType`.
2. Hyprland must report the client as native, not XWayland:
   ```sh
   hyprctl clients -j | jq -r '.[] | "\(.class) xwayland=\(.xwayland) title=\(.title)"'
   ```
   Expect `xwayland=false` for `eden`.
3. Optional protocol trace:
   ```sh
   WAYLAND_DEBUG=1 ./eden 2>&1 | grep -E "wl_surface|xdg_toplevel|wl_display" | head -50
   ```
   Expect the app to bind `wl_compositor`, create a `wl_surface`, obtain
   `xdg_toplevel`, and commit buffers. Do not capture full traces for long
   runs (large output).

### Qt native-resource probe (no Eden build required)

`tools/wayland/qt-wl-native-probe.cpp` reproduces Eden's handle extraction
for a top-level window and for a native child widget with the same attributes
as `RenderWidget`:

```sh
inc=$(pkg-config --variable=includedir Qt6Gui)
ver=$(qmake6 -query QT_VERSION)
c++ -std=c++20 -O2 -fPIC -I"$inc/QtGui/$ver/QtGui" \
  -o /tmp/qt-wl-native-probe tools/wayland/qt-wl-native-probe.cpp \
  $(pkg-config --cflags --libs Qt6Gui Qt6Widgets)
QT_QPA_PLATFORM=wayland /tmp/qt-wl-native-probe
QT_QPA_PLATFORM=xcb /tmp/qt-wl-native-probe
```

Observed on 2026-10-31 (Qt 6.12.0):

- Wayland: top-level and child both return non-null `display` and `surface`;
  `WAYLAND_DEBUG=client` shows `wl_subcompositor.get_subsurface`. Exit 0.
- XCB: `display` non-null, `surface` null (expected; Eden uses `winId()`).
  Exit 0.
- Hyprland tiled the window to 905x1020 despite a 400x300 request.
- After the event loop exits, the Wayland surface resource is null; query only
  while the window is live.

## 3. Vulkan proof

Eden logs the following (implemented by the A2 diagnostics patch and observed
in the runs below):

- `WindowSystemType::Wayland`;
- non-null `wl_display` and `wl_surface`;
- `VkSurfaceKHR` created via `vkCreateWaylandSurfaceKHR`;
- physical device name/type/vendor/driver and `vkGetPhysicalDeviceSurfaceSupportKHR == VK_TRUE`;
- swapchain format, present mode, image count, extent;
- successful `vkQueuePresentKHR` for rendered frames.

Cross-check the GPU actually in use:

```sh
nvidia-smi pmon            # NVIDIA process list
MANGOHUD=1 ./eden          # overlay shows GPU name
```

For Intel: launch without PRIME variables; the diagnostics must report the
Intel Iris Xe device (or the explicitly selected device).

### Standalone surface-support probe

`tools/wayland/vk-present-probe.c` creates a real `wl_surface` via
`wl_compositor`, calls `vkCreateWaylandSurfaceKHR`, and reports per-GPU
present family, formats and present modes. It is independent of Eden and of
Qt, so it can run before the Qt build exists:

```sh
cc -O2 -Wall -Wextra -Werror -o /tmp/vk-present-probe \
   tools/wayland/vk-present-probe.c $(pkg-config --cflags --libs wayland-client vulkan)
/tmp/vk-present-probe
prime-run /tmp/vk-present-probe
```

Observed on 2026-10-31:

- Default enumeration: Intel GPU0, NVIDIA GPU1. `prime-run`: NVIDIA GPU0.
- Both GPUs: `swapchain extension: yes`, present family 0 with
  `surface=1 wayland=1 graphics=yes`.
- Intel present modes: `mailbox fifo immediate`; NVIDIA: `mailbox fifo
  immediate` plus a vendor mode. **`FIFO_RELAXED` is absent on both.**
- `currentExtent` is `4294967295x4294967295` (compositor-decided), so the
  swapchain must use the size passed by the app and handle zero extents.

This proves the environment and the Vulkan Wayland WSI path, not Eden's own
swapchain. `vk_swapchain.cpp:74-77` already falls back to `FIFO` when the
requested mode is unsupported.

## 4. Test matrix

T04 onward require bootable content. The commercial NSP files under
`~/Downloads` were never read, copied or bundled. Vulkan presentation was
exercised with **nx-hbmenu v3.6.1** (GPLv2, SHA-256
`6cf6d130515723ebe0041c2479420caf9726895087439ff7b2e528c2ed39c100`), fetched to
`/tmp/eden-homebrew/` and never committed. Started as a bare NRO it shows its
own `launchInit() failed` page; that is hbmenu's normal response to missing
boot arguments and still drives the full render/present path. No keys,
firmware or commercial content were added to the repository.

Observed device selection on this laptop: Eden sorts physical devices
(discrete first, then NVIDIA/AMD/Intel, `vulkan_wrapper.cpp:50-68`), so
`vulkan_device=0` selects the RTX 3050 even though `vulkaninfo` lists Intel as
GPU0. The Intel run below hides the NVIDIA ICD with
`VK_LOADER_DRIVERS_SELECT='*intel*'`, which is a test technique, not a fork
feature.


| ID | Scenario | Expected | Status |
|---|---|---|---|
| T01 | Launch GUI, no game, native Wayland | `platformName=wayland`, `xwayland=false`, no warning dialog | Pass (GUI only) |
| T02 | Launch with `QT_QPA_PLATFORM=xcb` | XWayland window, same functionality | Pass (GUI only) |
| T03 | Force X11 via setting, restart | `platformName=xcb` persisted | Pass (GUI only) |
| T04 | Render a frame (legal content or self-test) | Surface + swapchain created, frames presented | Pass (hbmenu NRO) |
| T05 | Intel iGPU only | Intel device selected, present works | Pass (loader-selected Intel) |
| T06 | NVIDIA dGPU via PRIME | NVIDIA device selected, present works | Pass (default device sort selects NVIDIA) |
| T07 | Explicit GPU selection in settings | Chosen present-capable GPU used; invalid choice explains and falls back | Pass (C1; index 99 falls back, index 1 selects Intel) |
| T08 | Window resize (many sizes, rapid) | Swapchain recreated, no validation errors, no crash | Pass (single compositor-driven resize) |
| T09 | Minimise / restore | No hang, no stale frame, swapchain valid after restore | Not run |
| T10 | Fullscreen on/off | `showFullScreen()` works, state restored | Partial (enter observed; toggle-off not exercised) |
| T11 | Workspace switch / focus loss | Input released, frame loop continues or pauses correctly, focus restore works | Not run |
| T12 | Monitor/scale change (if permitted) | Extent and DPR updated, no mismatch | Not run |
| T13 | Fractional scale 1.25/1.5 (if permitted) | Rounded extents, aligned input, no validation errors | Not run |
| T14 | 120 Hz / VRR | Present pacing behaves; no forced 60 Hz; VRR subject to compositor | Not run |
| T15 | Gamepad hotplug | Controller detected/removed at runtime | Not run |
| T16 | Keyboard/mouse/touch | Input reaches emulation; focus loss releases keys | Not run |
| T17 | Suspend/resume via logind | Emulation pauses/resumes; renderer survives | Not run |
| T18 | Stop/start game repeatedly | Renderer/surface recreated cleanly; no leaks/validation errors | Not run |
| T19 | Close during emulation | Clean shutdown, no hang | Pass |
| T20 | XWayland fallback full session | Same as native matrix on `xcb` | Pass (hbmenu NRO) |
| T21 | Validation layers enabled | No errors; warnings triaged | Pass with triaged upstream warnings (no WSI errors) |
| T22 | Save data isolation | Portable `user/` used; existing data untouched | Pass (portable profile; existing install not touched) |
| T23 | Upstream regression after sync | Matrix passes vs previous known-good | Not run |

### Pending runtime checks — agreed procedures

These are the exact steps for the checks still open; record results in §8
only after observing them.

- **T10 (F1/F11 toggle-off):** toggle fullscreen via Eden's
  View → Fullscreen menu (`action_Fullscreen`), not a synthetic F11 —
  the default F11 hotkey is a `Qt::WindowShortcut` on `MainWindow`
  (`qt_common/config/uisettings.cpp`) and does not fire while the render
  window holds focus. Expected: swapchain recreation lines
  `1920x1017` ↔ `1280x720` in `eden_log.txt` on each toggle, no stuck
  fullscreen, frameless flag restored on exit.
- **T09/T11 (unmap + focus loss):** `hyprctl dispatch minimize` mid-game.
  Moving the window to another workspace does NOT unmap the surface, so
  it cannot exercise the not-drawable path. On minimise expect
  `Surface is not drawable` (`vk_swapchain.cpp`) and no hang; on restore
  expect `Recreated presentation surface after surface loss`
  (`vk_present_manager.cpp`) and a valid swapchain. Same run covers the
  T11 remainder (input released on focus loss, loop continues).
- **T13/E1 (fractional scale):** `hyprctl keyword monitor eDP-1,1920x1080@120,0x0,1.5`
  then resize/reconfigure. Swapchain extents are physical pixels
  (~logical × 1.5), so do not predict a literal size — assert the extent
  equals `round(window_size × scale)` (the `std::round` path in
  `GRenderWindow::OnFramebufferSizeChanged`), with no truncation and no
  restart. Revert the monitor scale to `1.0` afterwards.

## 5. Validation layers

Build/run with renderer debug enabled (`debug` renderer setting) so Eden adds
`VK_LAYER_KHRONOS_validation`
(`src/video_core/vulkan_common/vulkan_instance.cpp:88-113`).

Procedure:

1. Install `vulkan-validation-layers`.
2. Enable "Renderer debug" in Eden (Configuration > Graphics > Advanced) or
   the equivalent setting key.
3. Run scenarios T01–T20.
4. Capture `~/.local/share/eden/log/eden_log.txt` (portable:
   `build/wayland-run/user/log/eden_log.txt`) and search for
   `VUID-`, `Validation Error`, `ERROR`.
5. Record each unique message and whether it is upstream or fork-introduced.

`VK_INSTANCE_LAYERS` cannot override Eden's hardcoded layer list; use Eden's
debug setting.

Observed on 2026-10-31 (NVIDIA, native Wayland, hbmenu, validation 1.4.363
extracted from the Arch package to `/tmp/vk-validation-root`; layer confirmed
loaded):

- **No swapchain, surface or present VUIDs.** The whole WSI path (Wayland
  surface creation, swapchain create/recreate, acquire, present) produced no
  validation messages.
- `vkCreateDevice`: `VK_KHR_shader_quad_control` is enabled without its
  required dependency `VK_KHR_shader_maximal_reconvergence`.
- `vkCreateShaderModule`: SPIR-V declares `StencilExportEXT` /
  `SPV_EXT_shader_stencil_export` without `VK_EXT_shader_stencil_export`
  enabled.
- `vkCreateImage` / `vkCreateImageView` on `VK_FORMAT_R5G6B5_UNORM_PACK16`
  with `VK_IMAGE_USAGE_STORAGE_BIT`: the driver reports the combination as
  unsupported and the view inherits storage usage
  (`VUID-VkImageViewCreateInfo-usage-02275`). The layer stops repeating this
  VUID after its 10-message duplicate limit.
- All of the above originate in the upstream renderer/device setup, not in
  the fork's Wayland or diagnostics patches; they also affect XWayland. They
  are recorded as K20 in `KNOWN_ISSUES.md` and are not blockers for the
  Wayland prototype.

## 6. Diagnostics tooling

| Tool | Purpose | Status |
|---|---|---|
| `tools/wayland/diag.sh` | Environment/session/GPU report | Available |
| `vulkaninfo --summary` | GPU/driver/extension inventory | Available |
| `vulkan-validation-layers` | API correctness | Available locally (extracted Arch 1.4.363 to `/tmp/vk-validation-root`) |
| MangoHud (`MANGOHUD=1`) | FPS/frame time/GPU metrics | Available |
| `WAYLAND_DEBUG=1` | Protocol trace (short captures) | Available |
| `hyprctl clients -j` | XWayland vs native proof | Available |
| `journalctl` | logind/suspend, driver errors | Available |
| Qt logging (`QT_LOGGING_RULES`) | QPA/plugin diagnostics | Available |
| RenderDoc / apitrace | Frame capture | Not installed |
| `wayland-info` | Advertised protocols | Missing (`wayland-utils`) |

## 7. Automated tests

Current state: none (no tests executed). Planned:

1. **Static checks**
   - `git diff --check`
   - build with `-DENABLE_WERROR=ON`
   - CMake configure on a clean build directory
2. **Startup test** (script):
   - launch in portable mode with native Wayland for N seconds;
   - require diagnostic log lines: `platform=wayland`, surface type,
     GPU name, present mode;
   - require `hyprctl clients -j` to report `xwayland=false`;
   - terminate and require clean exit.
3. **XWayland test**: same with `QT_QPA_PLATFORM=xcb`, require `xwayland=true`.
4. **GPU test**: repeat startup with Intel-only and NVIDIA-only environment;
   require the matching device name in logs.
5. **Render test**: requires legal content or a self-contained
   `eden-vk-probe`; must present at least N frames and survive resize and
   minimisation.
6. **Upstream sync audit**: `tools/upstream-sync/audit-upstream.sh` produces a
   report; a merge is not accepted unless the report is reviewed.

Tests must be runnable without touching `~/.config/eden` or
`~/.local/share/eden`.

## 8. Results log

Methodology note: Eden's file logger buffers until a graceful shutdown. While
the process runs, `eden_log.txt` can omit recent swapchain re-creations; read
the log only after closing Eden through the window/confirmation dialog (SIGINT
kills without flushing, SIGTERM may hang). The XWayland row below shows the
effect: `100x30` was the only entry during the run, while the flushed log also
contains `908x975` and `1016x975`.

| Date | Build | Scenario | Result | Evidence |
|---|---|---|---|---|
| 2026-10-31 | Official v0.2.1 AppImage (extracted, isolated HOME) | Default launch on Hyprland | Observed: forced XWayland | `hyprctl`: class `eden`, `xwayland=true`; stderr "Wayland is disabled due to known issues" (hook sets `QT_QPA_PLATFORM=xcb`) |
| 2026-10-31 | Official v0.2.1 AppImage | Opt-in `I_WANT_A_BROKEN_WAYLAND_UI=1 QT_QPA_PLATFORM=wayland` | Observed: native Wayland GUI | `hyprctl`: class `dev.eden_emu.eden`, `xwayland=false` |
| 2026-10-31 | Official v0.2.1 AppImage | `WAYLAND_DEBUG=client` trace (opt-in) | Observed protocol set | binds `xdg_wm_base`, `zxdg_decoration_manager_v1`, `wp_fractional_scale_manager_v1`, `wp_viewporter`, `wp_presentation`, `zwp_linux_dmabuf_v1`, `wl_seat`, `wl_output` |
| 2026-10-31 | Official v0.2.1 AppImage | Vulkan surface + swapchain during title boot | Not run | No title/homebrew content available in the sandbox; not fabricated |
| 2026-10-31 | Unmodified upstream `943f1fc760`, `ENABLE_QT=OFF`, RelWithDebInfo | Build `eden-cli`, `tests`, `eden-room` | Pass (build) | 1529/1529 targets, exit 0, no compiler errors; built with bundled Vulkan headers; see BUILD_ARCH §2 |
| 2026-10-31 | Same baseline | `bin/tests --durations yes` | 63/71 passed, 8 failed | 3,773,593 assertions, 8 failures, all `MemoryTracker`; upstream test/implementation mismatch, not Wayland-related |
| 2026-10-31 | Same baseline | `bin/eden-cli --help` | Fail (exit 139) | Upstream CLI bug: `SDL_AppInit` never sets `*appstate`, `SDL_AppQuit` dereferences null; Qt frontend unaffected |
| 2026-10-31 | Same source, `ENABLE_QT=ON`, Charts from extracted Arch package | Configure/build `bin/eden` | Pass (build) | 1683/1683 targets, exit 0; local `/tmp` Charts workaround (install `qt6-charts` for normal use) |
| 2026-10-31 | `tools/wayland/vk-present-probe.c` (standalone) | Default and `prime-run` enumeration | Pass (environment) | Both GPUs present on a real Wayland surface; `currentExtent` undefined; `FIFO_RELAXED` absent; PRIME changes GPU0 to NVIDIA |
| 2026-10-31 | `tools/wayland/qt-wl-native-probe.cpp` (Qt 6.12) | Wayland and XCB native resources | Pass | Wayland: top-level + child `display`/`surface` non-null, `wl_subsurface` bound; XCB: `surface` null as expected |
| 2026-10-31 | Unmodified upstream Qt baseline `e90121aeec` (source = `943f1fc760`), `ENABLE_QT=ON` | GUI launch, native Wayland, isolated `user/` | Pass (GUI only) | `hyprctl`: class `dev.eden_emu.eden`, `xwayland=false`; no renderer (empty profile, no title) |
| 2026-10-31 | Same Qt baseline | GUI launch, `EDEN_DISPLAY=x11` | Pass (GUI only) | `hyprctl`: class `eden`, `xwayland=true`; XWayland fallback works |
| 2026-10-31 | Fork with A1+A2 (`e6cca3f89f`, `de2d61cdfa`), RelWithDebInfo; binary version string is stale (`e90121aeec`) because CMake was configured earlier | T01: GUI launch, native Wayland, isolated `user/` | Pass (GUI only) | Log: `Qt platform: wayland \| session: wayland \| WAYLAND_DISPLAY: wayland-1 \| DISPLAY: :1 \| force_x11: false` and `Using native Wayland. XWayland remains available...`; `hyprctl`: class `dev.eden_emu.eden`, `xwayland=false`; warning dialog absent |
| 2026-10-31 | Same fork build | T02: GUI launch, `EDEN_DISPLAY=x11` (`QT_QPA_PLATFORM=xcb`) | Pass (GUI only) | Log: `Qt platform: xcb \| session: wayland \| ... \| force_x11: false`; `hyprctl`: class `eden`, `xwayland=true` |
| 2026-10-31 | Same fork build | T03: `gui_force_x11=true` with ambient `QT_QPA_PLATFORM=wayland` | Pass (GUI only) | `hyprctl`: class `eden`, `xwayland=true`; the explicit setting overrode the ambient Qt platform. Test config removed afterwards |
| 2026-10-31 | Same fork build | A2 Vulkan diagnostics (surface/swapchain logs) | Pass | Diagnostics appear once a renderer exists; see the hbmenu rows below |
| 2026-10-31 | Fork `41ad87851a` (A1+A2+B1), RelWithDebInfo | T04/T06: native Wayland, hbmenu NRO, default device sort | Pass | `Qt platform: wayland`, `Created Wayland surface`, `Window system: Wayland`, `Driver: NVIDIA 615.78.8.0`, `Device: NVIDIA GeForce RTX 3050 Laptop GPU`, swapchain `1280x720 B8G8R8A8_UNORM FIFO 3 images`, "extent 1x1..16384x16384 (current compositor-defined)", 60 FPS; `hyprctl`: `xwayland=false`. Evidence: `docs/wayland/evidence/2026-10-31-native-wayland-nvidia.log` |
| 2026-10-31 | Same build | T05: Intel only, `VK_LOADER_DRIVERS_SELECT='*intel*'` | Pass | `Driver: Intel open-source Mesa driver 26.2.5`, `Device: Intel(R) Iris(R) Xe Graphics (ADL GT2)`, swapchain `1280x720`, 4 images, 60 FPS. Evidence: `...native-wayland-intel.log` |
| 2026-10-31 | Same build | T08: compositor resize, native Wayland, hbmenu | Pass | Swapchain recreated `1280x720` → `908x975` → `640x975`; presentation continued; screenshots `...-nvidia-resized.png` |
| 2026-10-31 | Same build | T10: fullscreen, native Wayland, hbmenu | Partial | Fullscreen swapchain recreated at `1920x1017`, 60 FPS, status bar `DOCKED`; returning to windowed was not exercised. Evidence: `...-nvidia-fullscreen.png` |
| 2026-10-31 | Same build | T19: close during emulation | Pass | Confirmation dialog appeared, Return accepted; log ends with `ForceStop: Force stopping EmuThread`, config written; `gamemode` `dlopen` warning expected (library not installed); no crash dump |
| 2026-10-31 | Same build | T20: XWayland full session, hbmenu | Pass | `Qt platform: xcb`, `Created Xlib surface`, `Window system: X11`, swapchain `100x30` → `908x975` → `1016x975` (after compositor resize), 60 FPS; `hyprctl`: class `eden`, `xwayland=true`. Evidence: `docs/wayland/evidence/2026-10-31-xwayland.log` |
| 2026-10-31 | Fork `e479fef767`, RelWithDebInfo | T07: C1 GPU selection on native Wayland | Pass | `vulkan_device=99` logs an out-of-range error and falls back to GPU[0] (NVIDIA) which presents; `vulkan_device=1` selects Intel and presents a 1280x720 Wayland swapchain. Evidence: commit message only; no runtime log archived |
| 2026-10-31 | Same build, validation layers 1.4.363 (`Renderer.debug=true`) | T21: validation during hbmenu boot and presentation | Pass with triaged warnings | Zero swapchain/surface/present VUIDs. Warnings are upstream renderer/device issues (quad-control dependency, stencil-export SPIR-V, R5G6B5 storage usage); classified in §5. Evidence: `...native-wayland-validation.log` |
| 2026-10-31 | Same build | T22: portable profile isolation | Pass | All logs/config/saves stayed under `build/wayland-run/user/`; `~/.config/eden` and `~/.local/share/eden` untouched; `renderer_debug` reverted to `false` after the validation run |
| 2026-11-09 | Fork D1/D2 (`vk_swapchain`, `vk_present_manager`), RelWithDebInfo | T04/T08/D1+D2 smoke: native Wayland, hbmenu NRO, NVIDIA | Pass | `Qt platform: wayland`, `Created Wayland surface`, swapchain `1280x720`, then resize recreations `1808x955` → `1920x1017` → `1808x955` with presentation continuing; 0 `VUID-`/`Validation Error` lines; no hang or crash over 3 min. Not exercised: zero-extent/minimised surfaces and `VK_ERROR_SURFACE_LOST_KHR` recovery (Hyprland keeps valid extents; no surface loss occurred), so D1/D2 recovery paths remain code-verified only. Evidence: `docs/wayland/evidence/2026-11-09-d1d2-native-wayland-eden.log` |
| 2026-11-09 | Same D1/D2 build, RelWithDebInfo | T04/T08/T10: native Wayland, user-installed legal game, NVIDIA | Pass | `Qt platform: wayland`, `Created Wayland surface`, swapchain `1280x720`; resize/fullscreen recreations `1920x1017` ↔ `908x975` with presentation continuing and a clean shutdown (config written on exit). 0 `VUID-`/`Validation Error` lines; only upstream debug asserts (`texture format=0` lookup, `SwkbdConfig revision`) and the usual missing-save-dir error. Not observed: zero-extent/minimise and surface-loss recovery (no minimise or surface loss occurred). Evidence: `docs/wayland/evidence/2026-11-09-d1d2-realgamesession-eden.log` |
| 2026-11-09 | Post-merge build (37 upstream commits + fork Wayland-first hybrid) | T01/T02: default launch with clean environment; XWayland override | Pass | Default (no `QT_QPA_PLATFORM`): `Qt Platform Backend: wayland`, `Created Wayland surface`, swapchain `1280x720`, `xwayland=false`. `QT_QPA_PLATFORM=xcb`: `Qt Platform Backend: xcb`, `Created Xlib surface`, `xwayland=true`. 0 `VUID-`/`Validation Error` lines in both runs. Evidence: `...2026-11-09-merge-default-wayland-eden.log`, `...2026-11-09-merge-xwayland-eden.log` |
| 2026-11-09 | Post-merge build | C2: forced Vulkan init failure (`VK_LOADER_DRIVERS_SELECT` with no devices) | Pass | Log shows `Vulkan initialization failed on window system Wayland with error: ...` + the prime-run/`QT_QPA_PLATFORM` hint + `Failed to initialize GPU: Vulkan initialization error ... (window system: Wayland)`. Evidence: `...2026-11-09-c2-enriched-error-eden.log` |
| 2026-11-09 | Same build (portable profile) | T11-partial: user controller via Eden Configure Controllers | Pass (user-reported) | Dongle: `2563:0526 SHANWAN Android Gamepad` streams `js_event` bytes on `/dev/input/js0` (verified live); Eden's bundled SDL enumerates it (`joysticks: 1 ... SHANWAN Android Gamepad | /dev/input/event23`, `gamepads: 1`). User reports the pad is now recognised by Eden after connecting Player 1 in the UI. Caveat: profile snapshots still show `player_1_connected=false` with keyboard bindings, so the saving state in the killed session differs from the ini; not verified from a saved config |

Rows identify the build under test. Official-binary rows prove the environment
and Qt Wayland path only; fork rows with an hbmenu entry also prove the fork's
Vulkan presentation path. No result in this file may be recorded until it has
actually been observed.

Only real, observed results belong here, with the exact build commit,
environment and log excerpt (or a path to the saved log).
