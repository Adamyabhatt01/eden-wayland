# Eden Linux Windowing and Graphics Architecture Audit

Base commit: `943f1fc76087adcfc893fb1ca3aea507df15d004` (`upstream/master`,
2026-10-30). All paths are relative to the repository root. Line numbers refer
to that commit. Findings marked **[verified]** were read directly during the
audit; runtime behaviour is tracked separately in `TESTING.md`.

> Update (2026-11-09): C1 (present-support-aware GPU selection) has since
> landed on `linux-wayland`. The audit below remains the reference for the
> base commit and for the remaining reliability work.

## 1. Executive summary

Eden's desktop frontend is a Qt 6 Widgets application that renders through a
dedicated native child `QWidget` (`RenderWidget`) whose platform surface is
handed to the renderer as an opaque `WindowSystemInfo` structure. The Vulkan
renderer, not Qt, owns `VkInstance`/`VkSurfaceKHR`/`VkSwapchainKHR`.

Native Wayland support **already exists at both layers**:

1. Qt: `QtCommon::GetWindowSystemType()` maps the `wayland`/`wayland-egl` QPA
   plugins to `WindowSystemType::Wayland`, and `GetWindowSystemInfo()` obtains
   `wl_display*` and `wl_surface*` through
   `QPlatformNativeInterface::nativeResourceForWindow("display"/"surface")`.
2. Vulkan: `Vulkan::CreateSurface()` implements
   `vkCreateWaylandSurfaceKHR` and the instance requests
   `VK_KHR_wayland_surface`.

The fork therefore does **not** need a new windowing subsystem. The work is to
remove upstream's Wayland-hostile defaults, fix the presentation/recreation
edge cases that matter on Wayland/Hyprland, make GPU selection robust on
Optimus, add verification, and package `qt6-wayland` as a runtime dependency.

Architecture target, already mostly realised:

```
Eden emulation core (Core/Tegra/GPU thread)
    |
    v
EmuWindow + WindowSystemInfo{type, display_connection, render_surface, scale}
    |
    v
Qt desktop frontend (QWidget/QWindow)          CLI frontend (SDL3)
    |                                             |
    +---------------- QPlatformNativeInterface ---+
    |
    v
Vulkan::CreateSurface  ->  VkSurfaceKHR (Wayland / Xlib)
    |
    v
Vulkan renderer (instance, device, swapchain, present manager)
    |
    v
GPU driver (Mesa Intel / NVIDIA proprietary) -> compositor
```

## 2. Windowing subsystem (Qt)

### 2.1 Application startup and platform selection

| Concern | Location | Behaviour |
|---|---|---|
| Application object | `src/yuzu/main.cpp:182` | `QApplication app(argc, argv)` |
| Org/app id | `src/yuzu/main.cpp:111-112` | `eden` |
| `DISPLAY` fallback | `src/yuzu/main.cpp:155-157` | If `DISPLAY` unset, sets `DISPLAY=:0` unconditionally on Unix |
| Force X11 | `src/yuzu/main.cpp:159-160` | If `gui_force_x11` is set and `QT_QPA_PLATFORM` is empty, sets `QT_QPA_PLATFORM=xcb` |
| Wayland app id | `src/yuzu/main.cpp:162-164` | `setDesktopFileName("dev.eden_emu.eden")` |
| HiDPI policy | `src/yuzu/main.cpp:41-78`, applied `167-168` | Windows: per-screen rounding; all other OS: `PassThrough` |
| Backend warning | `src/yuzu/main_window.cpp:4430-4477`, called from ctor `:456` | Modal "Wayland Detected!" dialog recommending X11; "Use X11" persists `gui_force_x11=true` |

Platform detection: `src/qt_common/qt_common.cpp:62-83`.
`xcb -> X11`, `wayland`/`wayland-egl -> Wayland`, `windows/cocoa/android/haiku`
mapped. **Unknown platforms fall through to `WindowSystemType::Windows`**
(`:81-82`), which then fails surface creation; this is a diagnostic-quality
bug, not a Wayland blocker.

Settings persistence:
`gui_force_x11` and `gui_hide_backend_warning` live in
`src/qt_common/config/uisettings.h:151-155` and are stored in
`gui_config.ini` through `src/qt_common/gui_settings.cpp:12-24`.
The force-X11 checkbox is auto-generated in Configure > General
(`src/yuzu/configuration/configure_general.cpp:55-92`).

### 2.2 Render target creation

- `GRenderWindow : QWidget, EmuWindow` — `src/yuzu/bootmanager.h:61`.
- `RenderWidget : QWidget` — `src/yuzu/bootmanager.cpp:78-93`:
  `WA_NativeWindow`, `WA_PaintOnScreen`, and on Wayland
  `WA_DontCreateNativeAncestors`; `paintEngine()` returns `nullptr`.
- `VulkanRenderWidget` sets `QWindow::VulkanSurface` —
  `src/yuzu/bootmanager.cpp:108-112`.
- `GRenderWindow::InitRenderTarget()` — `bootmanager.cpp:736-781`:
  1. constructs a throw-away `RenderWidget` to let Qt lay out the container;
  2. constructs the real widget and calls `windowHandle()->create()` in
     `InitializeVulkan()` (`:866-874`);
  3. reads `QtCommon::GetWindowSystemInfo(child_widget->windowHandle())`;
  4. resizes and installs the widget in the layout.
- `GetWindowSystemInfo()` — `src/qt_common/qt_common.cpp:85-135`:
  - display: `nativeResourceForWindow("display", window)`;
  - Wayland surface: `nativeResourceForWindow("surface", window)`;
  - X11 surface: `window->winId()`;
  - `render_surface_scale = window->devicePixelRatio()`.
- `WindowSystemInfo` contract — `src/core/frontend/emu_window.h:60-74`.

Consequences for Wayland:

- The Vulkan surface is a `wl_surface` belonging to a **native child widget**
  (a `wl_subsurface` under Qt's Wayland QPA). This is a supported but less
  common WSI configuration; it must be validated on Hyprland with both Intel
  and NVIDIA.
- The renderer starts only after `windowHandle()->create()`, so the
  `wl_surface` exists when `vkCreateWaylandSurfaceKHR` is called.
- Qt's own `QVulkanInstance` is **not** used (`main_context` is a
  `DummyContext` for Vulkan), so there is no second Vulkan instance and no
  duplicated Wayland connection. The single `wl_display` comes from Qt.

### 2.3 Framebuffer size and HiDPI

- `OnFramebufferSizeChanged()` — `bootmanager.cpp:186-193`:
  `width = this->width() * devicePixelRatioF()` (truncated to `u32`).
- `windowPixelRatio()` — `:220-222`; touch scaling `:224-228`.
- `resizeEvent()` — `:717-720`; `showEvent()` connects
  `QWindow::screenChanged` to `OnFramebufferSizeChanged` — `:937-943`.
- With `PassThrough` rounding, Wayland fractional scales (1.25, 1.5, ...)
  reach the framebuffer layout as fractional products. Truncation can produce
  off-by-one swapchain extents and touch-coordinate drift.
- No handler exists for a per-screen DPR change that is not accompanied by a
  resize (`screenChanged` is the only hook).
- The desktop file declares no `X-GNOME-*` hints; Hyprland does not apply
  toolkit scaling overrides, so Qt's Wayland fractional-scale path is used.

### 2.4 Fullscreen and window state

- `MainWindow::ToggleFullscreen()` — `main_window.cpp:3271-3280`.
- `UsingExclusiveFullscreen()` — `:3294-3298`: true when the setting is
  `Exclusive` **or the platform is Wayland** (Wayland has no exclusive
  fullscreen; `showFullScreen()` is the correct primitive).
- `ShowFullscreen()` — `:3300-3326`: exclusive path calls
  `showFullScreen()`; borderless path (X11-only in practice) manually sizes a
  frameless window to `GuessCurrentScreen()->geometry()` with `height + 1`.
- `HideFullscreen()` — `:3328-3355`. The X11 borderless branch appears to
  restore `windowFlags()` from `MainWindow` rather than the render window
  (`:3349`); this is an upstream latent bug, not Wayland-specific.
- Multi-monitor selection: `GuessCurrentScreen()` — `:3283-3292` (maximum
  intersection). It is unused on Wayland because exclusive fullscreen is
  forced. `QWindow::setScreen` is never called.
- Geometry persistence: `UISettings::RestoreWindowState`
  (`src/qt_common/config/uisettings.cpp:118-150`), save on close
  (`main_window.cpp:4603-4605`), skipped while fullscreen (`:4371-4373`).
  Wayland compositors may ignore requested positions; geometry restore is
  best-effort only.
- Window close / game stop: `GRenderWindow::closeEvent` emits `Closed`
  (`bootmanager.cpp:230-233`) handled by `MainWindow::OnStopGame`
  (`main_window.cpp:2046`).

### 2.5 Event flow

- Key press/release mapping: `bootmanager.cpp:251-459`.
- Mouse press/move/release/wheel: `:480-539`, `:563-567`; capture/constrain
  timer `:140-145`, `:541-557`; hover forwarding `:945-955`.
- Touch: `:569-591`; focus loss releases keyboard, touch and mouse buttons
  (`:710-715`). There is no `focusInEvent`.
- Event interception for the software keyboard: `:695-708`.
- No `paintEvent`: presentation is owned by the renderer.
- Timers: mouse constrain 10 ms, mouse update 5 ms, camera 50 ms
  (`:75-76`, `:140-145`, `:637-640`); MainWindow status 500 ms and
  1 ms input polling (`main_window.cpp:316-317`, `:474-480`).

## 3. Vulkan presentation pipeline

### 3.1 Initialisation order

`RendererVulkan` constructor — `src/video_core/renderer_vulkan/renderer_vulkan.cpp:127-165`:

1. `CreateInstance(..., VK_API_VERSION_1_1, GetWindowInfo().type,
   renderer_debug)` — `:134-138`.
2. Optional debug messenger — `:140-141`.
3. `Vulkan::CreateSurface(instance, GetWindowInfo())` — `:143`.
4. `CreateDevice(instance, dld, *surface)` — `:144`.
5. `Swapchain(surface, device, scheduler, framebuffer_width, height)` — `:148-152`.
6. `PresentManager(...)` — `:153-159`.
7. `VKSurfaceKHR` is owned by `RendererVulkan::surface`
   (`renderer_vulkan.h:92`, RAII `vk::SurfaceKHR`); destruction order preserves
   device/swapchain destruction before surface destruction.

### 3.2 Instance and surface

- Extension selection — `src/video_core/vulkan_common/vulkan_instance.cpp:38-86`:
  - Wayland -> `VK_KHR_wayland_surface` (`:66-68`);
  - X11 -> `VK_KHR_xlib_surface` (`:63-65`);
  - `VK_KHR_surface` always added for windowed rendering (`:74-76`).
- Validation: hardcoded `VK_LAYER_KHRONOS_validation`, enabled only when
  `renderer_debug` is on; filtered against enumerated layers
  (`:88-113`). No `VK_INSTANCE_LAYERS` override.
- API-version mismatch: `renderer_vulkan.cpp:134-138` passes 1.1, but
  `VkApplicationInfo.apiVersion` is hardcoded to `VK_API_VERSION_1_3`
  (`vulkan_wrapper.cpp:456-473`) and the passed version is ignored.
- Wayland surface creation — `vulkan_surface.cpp:93-106`:
  `VkWaylandSurfaceCreateInfoKHR{display, surface}` with
  `wl_display*`/`wl_surface*` from Qt. Xlib path `:80-91`.
- Build definitions: `VK_USE_PLATFORM_XLIB_KHR` and
  `VK_USE_PLATFORM_WAYLAND_KHR` are hardcoded in
  `src/video_core/vulkan_common/vulkan.h:18-21`. The `wayland-client` headers
  are required but not declared as a CMake dependency; no libwayland symbols
  are linked (handles are opaque), so the build succeeds on any distro with
  Vulkan headers plus wayland headers.

### 3.3 Physical device and queue families

- Enumeration/selection — `renderer_vulkan.cpp:112-121`: the user setting
  `vulkan_device` is a direct index into the sorted device list
  (`src/common/settings.h:345`, default 0).
- Sort order — `vulkan_wrapper.cpp:50-69`: name descending, discrete before
  integrated, then vendor order **NVIDIA (0x10DE) > AMD > Intel**, Dozen last.
  On this laptop this puts the RTX 3050 first.
- Device suitability — `vulkan_device.cpp:999-1308` is computed but only
  logged ("Unsuitable driver - continuing anyways", `:473-474`); it never
  rejects a device.
- Present queue validation — `Device::SetupFamilies`
  (`vulkan_device.cpp:1544-1579`): searches for a graphics family and a
  present-capable family, throws if none. **There is no fallback to another
  physical device**; if the preferred dGPU cannot present to the compositor
  surface, initialization fails.
- Queue creation — `:1679-1699`: one queue per unique family.
- PRIME awareness: none. `DRI_PRIME`, `__NV_PRIME_RENDER_OFFLOAD` and
  `VK_ICD_FILENAMES` are honoured only by the loader/driver, not by Eden.
  `LIBVULKAN_PATH` is the only Vulkan env var Eden reads
  (`vulkan_library.cpp:29`).
- The GPU picker UI is `src/qt_common/util/vk.cpp:31-65` (it creates a
  temporary `QWindow` with `VulkanSurface` and enumerates devices) and
  `src/yuzu/configuration/configure_graphics.cpp:55-63`. Users see list
  indices and names, not vendor/type diagnostics.

### 3.4 Swapchain

`src/video_core/renderer_vulkan/vk_swapchain.cpp`:

| Property | Behaviour |
|---|---|
| Format | Prefer `B8G8R8A8_UNORM` + `SRGB_NONLINEAR` (`:30-42`) |
| Present mode | `vsync_mode` 1:1 (`:79-90`); frame-gen forces FIFO/FIFO_RELAXED (`:51-53`); unlocked speed setting can upgrade FIFO to MAILBOX/IMMEDIATE (`:54-70`); fallback FIFO (`:71-77`) |
| Image count | `minImageCount + 1`, minimum 3, clamped (`:268-279`) |
| Composite alpha | OPAQUE -> INHERIT -> OPAQUE (`:106-116`) |
| Transform | Surface `currentTransform` (`:294-299`) |
| Usage | `COLOR_ATTACHMENT | TRANSFER_DST` (`:290`), `clipped = VK_FALSE` (`:302`) |
| Sharing | Concurrent when graphics/present families differ (`:305-312`) |
| `oldSwapchain` | Always null (`:303`); the old chain is destroyed before create (`:152`, `:361-366`) |
| Zero extent | If `maxImageExtent` is 0x0, `Create()` returns early **after** overwriting width/height with the new size (`:148-150`), leaving the previous swapchain alive with mismatched metadata |
| Acquire | `vkAcquireNextImageKHR` with `UINT64_MAX` timeout (`:163`); out-of-date/suboptimal only set flags and continue (`:167-180`) |
| Present | `vkQueuePresentKHR` (`:230`); out-of-date sets `is_outdated`; surface-lost throws; other errors are logged as critical and execution continues (`:230-249`) |
| Recreation predicate | `NeedsRecreation()` returns `is_suboptimal || present_mode_changed`; **`is_outdated` is ignored** (`vk_swapchain.h:46-48`) |

Frame pacing is applied inside `AcquireNextImage` via
`scheduler.Wait(resource_ticks[image_index], target_fps)`
(`vk_swapchain.cpp:182-212`, `vk_scheduler.h:132-163`). Generated frames are
paced by `Present/Framegen::FrameGenPacer::Plan`
(`present/frame_gen_pacer.cpp:49-141`, wired at
`renderer_vulkan.cpp:224-238`).

### 3.5 Present manager and frame copies

`src/video_core/renderer_vulkan/vk_present_manager.cpp`:

- Optional worker thread `PresentThread` (`:330-356`) enabled by
  `async_presentation`, whose desktop default is **false**
  (`src/common/settings.h:643-649`). With the default, presentation runs
  inline on the GPU thread.
- Submit waits on `{present_semaphore, frame->render_ready}`, signals
  `render_semaphore`, fence `present_done` (`:547-572`); fences waited
  `:156-184`; `vkQueuePresentKHR` at `:585`.
- Guest layers are composed into an intermediate `Frame::image`
  (`vk_blit_screen.cpp:95-163`) and copied/blitted into the swapchain image
  (`vk_present_manager.cpp:531-540`).
- Recreation loop (`:426-439`): recreates when suboptimal or size changed,
  then `while (AcquireNextImage()) RecreateSwapchain(...)` with no iteration
  bound.
- Surface loss (`:399-424`): retries up to `MAX_PRESENT_ATTEMPTS` (3, `:26`);
  recreates `VkSurfaceKHR` **only on Android** (`:406-408`); otherwise the
  frame is discarded by submitting a wait on `render_ready` with no signal
  (`:380-397`).
- Device loss: submit path reports loss with a 15 s sleep then throws
  (`vulkan_device.cpp:897-902`); acquire default branch logs; present logs
  critical and continues.

### 3.6 Synchronisation summary

- One acquire semaphore per swapchain image; one render semaphore per frame.
- Presentation serialised by `scheduler.submit_mutex`.
- No `VK_KHR_surface_maintenance1`, `VK_EXT_surface_maintenance1` or
  `present_wait`/`present_id` usage; no `wp_presentation` feedback from the
  compositor. Frame pacing is time-based, not compositor-time-based.
- Wayland implicit synchronisation is handled by the NVIDIA/Mesa WSI; Eden
  does not import/export dma-buf explicitly.

## 4. Input subsystem

- `InputSubsystem` is constructed and initialised by `GRenderWindow`
  (`bootmanager.cpp:118-129`), before any render target exists.
  Drivers registered in `src/input_common/main.cpp:75-102`: keyboard, mouse,
  touch, SDL3, joycon, UDP, TAS.
- Keyboard/mouse/touch in the Qt frontend are driven by Qt events
  (`bootmanager.cpp` as above) and are display-backend independent.
- SDL3 is initialised for joystick/gamepad only
  (`src/input_common/drivers/sdl_driver.cpp:643-709`), with
  `SDL_HINT_ALLOW_BACKGROUND_EVENTS` (`:665`), event watch registration
  (`:697`) and hotplug events (`:627-634`). It does not set
  `SDL_VIDEODRIVER`.
- The Qt frontend inits `SDL_INIT_VIDEO` only for screensaver/DBus handling
  (`src/yuzu/main_window.cpp:500-514`).
- Wayland limitation: Qt does not expose pointer constraints / relative
  pointer to applications, and `QCursor::setPos()` is a no-op under Wayland.
  Eden's mouse constrain/recentre logic (`bootmanager.cpp:541-557`) cannot
  warp the compositor cursor. Gamepad input (SDL3) and absolute touch/mouse
  input are unaffected. Keyboard capture works because the window has focus.

## 5. Linux desktop integration

| Area | Location | Notes |
|---|---|---|
| Suspend/resume | `main_window.cpp:1738-1779` | logind/ConsoleKit `PrepareForSleep` via DBus; pauses/resumes emulation |
| Screensaver inhibition | `main_window.cpp:1829-1843`, init `:500-514` | SDL3 video subsystem |
| GameMode | `src/qt_common/gamemode.cpp:19-50`; calls `main_window.cpp:3078,3099,4821-4828` | `gamemode_request_start/end`, Linux-only |
| File dialogs | `src/qt_common/abstract/frontend.cpp:10-24` and `QFileDialog` call sites | No `DontUseNativeDialog`; Qt uses the XDG desktop portal under Wayland when available |
| Clipboard | `main_window.cpp:2699-2702` | `QClipboard` |
| Drag and drop | `main_window.cpp:4664-4674` | Qt drop events |
| Audio | `src/audio_core/sink/sink_details.cpp:44-107`, `audio_core.cpp:26-31` | Cubeb preferred (PipeWire/PulseAudio/ALSA), SDL3 fallback, null |
| App identity | `main.cpp:164`, `dist/dev.eden_emu.eden.desktop` | `dev.eden_emu.eden`, `StartupWMClass=eden` |
| Notifications | none | only in-window multiplayer notifications |
| RenderDoc | `src/core/tools/renderdoc.cpp:35-42` | `dlopen("librenderdoc.so")` |
| MangoHud | no code | external Vulkan layer |
| TurboMode | `vk_turbo_mode.cpp:22-26` | opens a second `VkDevice` for GPU boost |

## 6. Build and dependency map

- Top level: `CMakeLists.txt` requires CMake >= 3.31, C++20
  (`:4`, `:371`).
- Qt frontend: `ENABLE_QT` (`:74`), Qt components
  `Core Widgets Charts Concurrent Gui [+DBus]` (`:620-640`);
  `src/yuzu/CMakeLists.txt` links `Qt6::Widgets Charts Concurrent` (`:406`)
  and DBus (`:412-414`).
- Vulkan renderer: `src/video_core/CMakeLists.txt:203-220` compiles
  `vulkan_common`; `:429` links `Vulkan::Headers`, VMA and
  Vulkan-Utility-Libraries. No `wayland-client` target.
- Dependency acquisition: CPM + `cpmfile.json` (`CMakeLists.txt:13,25,404-489`;
  `CMakeModules/CPMUtil.cmake`). System packages are preferred when found.
- Packaging assets: desktop file, icon, metainfo, MIME XML, udev rules in
  `dist/`; install rules at `CMakeLists.txt:731-742`. No PKGBUILD, AppImage
  recipe or Flatpak manifest exists upstream. CI (`.forgejo/workflows/`) does
  not build a Linux desktop binary.

## 7. Existing Wayland support assessment

| Capability | Status | Evidence |
|---|---|---|
| Qt Wayland platform plugin detection | Present | `qt_common.cpp:66-73` |
| Wayland app id (`xdg_toplevel.app_id`) | Present | `main.cpp:162-164` |
| `wl_display`/`wl_surface` extraction from Qt | Present | `qt_common.cpp:125-130` |
| `VK_KHR_wayland_surface` instance extension | Present | `vulkan_instance.cpp:66-68` |
| `vkCreateWaylandSurfaceKHR` | Present | `vulkan_surface.cpp:93-106` |
| Native child surface (`wl_subsurface`) | Verified by standalone Qt 6.12 probe; Eden path pending boot | `bootmanager.cpp:78-112`, `866-874`; `tools/wayland/qt-wl-native-probe.cpp` |
| Wayland-first default policy | **Absent** | `main.cpp:155-160`, `main_window.cpp:4430-4477` |
| XWayland fallback | Present (`gui_force_x11` / env override) | `main.cpp:159-160`, `gui_settings.cpp:12-24` |
| Present-mode selection for Wayland | Generic only; no Wayland-specific handling | `vk_swapchain.cpp:44-91` |
| Surface-lost recovery | **Absent on Linux** | `vk_present_manager.cpp:399-424` |
| Minimised/zero-extent handling | **Fragile** | `vk_swapchain.cpp:148-150`, `vk_present_manager.cpp:437-439` |
| Out-of-date recreation | **Incomplete** (`is_outdated` ignored) | `vk_swapchain.h:46-48` |
| GPU fallback when preferred GPU cannot present | **Absent** | `vulkan_device.cpp:1544-1579` |
| Fractional scaling correctness | **Unverified**; truncation risk | `bootmanager.cpp:186-193` |
| Pointer constraints / relative mouse | **Absent** | Qt limitation; no protocol use |
| `presentation-time` / `frame-callback` pacing | **Absent** | no protocol use |
| Runtime diagnostics (platform, GPU, surface, present mode) | Partial | device log only |

Protocols actually needed on Hyprland:

- `xdg-shell`: provided by Qt Wayland, used for the top-level window.
- `wl_subsurface`: implicitly used by Qt for the native child render window.
- `xdg-decoration`: provided by Qt when available; Hyprland supports/ignores
  server-side decoration negotiation depending on config. Qt falls back
  client-side.
- `fractional-scale-v1` + `viewporter`: Qt Wayland handles them; Eden only
  needs correct pixel extents.
- `presentation-time`: optional, would enable real presentation feedback;
  not required for correctness.
- `linux-dmabuf`: used internally by the Vulkan WSI/driver; Eden does not
  need to speak it directly.
- `zwp_pointer_constraints_v1` / `relative-pointer`: not exposed by Qt;
  needed only for cursor-warping mouse modes.

Runtime observation (official v0.2.1 AppImage, isolated run, 2026-10-31):

- Default launch is forced to XWayland (`hyprctl`: class `eden`,
  `xwayland=true`) by `bin/wayland-is-broken.hook`.
- With `I_WANT_A_BROKEN_WAYLAND_UI=1` and `QT_QPA_PLATFORM=wayland` the same
  binary is native (`app_id=dev.eden_emu.eden`, `xwayland=false`).
- `WAYLAND_DEBUG=client` shows the Qt client binding `xdg-shell`,
  `xdg-decoration`, `fractional-scale-v1`, `viewporter`, `presentation-time`,
  `linux-dmabuf`, `wl_seat`, `wl_output`, pointer and keyboard.
- This validates the GUI/windowing path on Hyprland but **not** the emulator
  Vulkan surface: no title was booted, so `VkSurfaceKHR` and swapchain
  presentation remain unverified (T04+).

Qt native-resource probe (Qt 6.12, 2026-10-31):

- `tools/wayland/qt-wl-native-probe.cpp` creates a top-level widget and a
  native child widget (same attributes as `RenderWidget`). On `wayland`,
  both return non-null `nativeResourceForWindow("display")` and
  `("surface")`; `WAYLAND_DEBUG=client` shows
  `wl_subcompositor.get_subsurface`.
- On `xcb`, `"display"` is non-null and `"surface"` is null, which matches
  Eden's design: non-Wayland paths use `winId()` as the render surface.
- Hyprland tiled the probe's top-level to 905x1020 despite a requested
  400x300 geometry, confirming that window geometry is compositor-controlled.
- Handles are valid only while the window is shown; after the event loop
  exits the surface resource becomes null. Eden extracts WSI while the render
  target is live, so this is expected, but diagnostics must not query after
  teardown.

## 8. Technical risks

| # | Risk | Severity | Affected area |
|---|---|---|---|
| R1 | Default FIFO + synchronous present (`async_presentation=false`) can couple emulation speed to compositor frame callbacks | High | `vk_present_manager`, GPU thread |
| R2 | Surface loss is unrecoverable on Linux; `DiscardFrame` can stall on semaphore semantics | High | `vk_present_manager.cpp:380-424` |
| R3 | Zero-extent (minimised/output removal) leaves stale swapchain metadata and can spin in the recreate loop | High | `vk_swapchain.cpp:148-150`, `vk_present_manager.cpp:437-439` |
| R4 | dGPU preferred unconditionally; no fallback when present support is missing | High (Optimus) | `vulkan_wrapper.cpp:50-69`, `vulkan_device.cpp:1544-1579` |
| R5 | `DISPLAY=:0` fallback and X11-forcing defaults undermine Wayland-first policy | Medium | `main.cpp:155-160` |
| R6 | Wayland warning dialog + force-X11 persistence is hostile UX and hides native mode | Medium | `main_window.cpp:4430-4477` |
| R7 | Fractional-scale framebuffer truncation / no DPR-change handler | Medium | `bootmanager.cpp:186-193`, `937-943` |
| R8 | No runtime proof of surface type/GPU; success can be claimed falsely | Medium | diagnostics gap |
| R9 | Instance requests API 1.3 while validating 1.1 | Low | `vulkan_wrapper.cpp:456-473` |
| R10 | `wayland-client` not declared in CMake | Low (build portability) | `src/video_core/CMakeLists.txt`, `vulkan.h:18-21` |
| R11 | Mouse warp/constrain ineffective on Wayland | Low (feature loss) | Qt input |
| R12 | Upstream churn in `video_core`/Qt while fork patches touch the same files | Medium (maintenance) | sync workflow |

## 9. Source file index (primary)

Windowing / Qt:
`src/yuzu/main.cpp`, `src/yuzu/main_window.cpp`, `src/yuzu/bootmanager.cpp/.h`,
`src/qt_common/qt_common.cpp/.h`, `src/qt_common/gui_settings.cpp/.h`,
`src/qt_common/config/uisettings.h`, `src/qt_common/util/vk.cpp/.h`,
`src/core/frontend/emu_window.h`.

Vulkan:
`src/video_core/renderer_vulkan/renderer_vulkan.cpp/.h`,
`src/video_core/vulkan_common/vulkan_instance.cpp`,
`vulkan_surface.cpp`, `vulkan_device.cpp`, `vulkan_wrapper.cpp`, `vulkan.h`,
`src/video_core/renderer_vulkan/vk_swapchain.cpp/.h`,
`vk_present_manager.cpp/.h`,
`vk_blit_screen.cpp`,
`src/video_core/renderer_vulkan/present/frame_gen_pacer.cpp`,
`vk_scheduler.h`.

Input:
`src/input_common/main.cpp`,
`src/input_common/drivers/{keyboard,mouse,touch_screen,sdl_driver}.cpp`.

Linux integration:
`src/qt_common/gamemode.cpp/.h`,
`src/audio_core/sink/sink_details.cpp`,
`src/audio_core/audio_core.cpp`,
`src/core/tools/renderdoc.cpp`.

Build:
`CMakeLists.txt`, `CMakeModules/CPMUtil.cmake`, `cpmfile.json`,
`src/yuzu/CMakeLists.txt`, `src/video_core/CMakeLists.txt`,
`src/qt_common/CMakeLists.txt`, `dist/`.
