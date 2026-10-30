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

## 3. Vulkan proof

Eden must log (Phase 3 diagnostics):

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

## 4. Test matrix

| ID | Scenario | Expected | Status |
|---|---|---|---|
| T01 | Launch GUI, no game, native Wayland | `platformName=wayland`, `xwayland=false`, no warning dialog | Not run |
| T02 | Launch with `QT_QPA_PLATFORM=xcb` | XWayland window, same functionality | Not run |
| T03 | Force X11 via setting, restart | `platformName=xcb` persisted | Not run |
| T04 | Render a frame (legal content or self-test) | Surface + swapchain created, frames presented | Not run |
| T05 | Intel iGPU only | Intel device selected, present works | Not run |
| T06 | NVIDIA dGPU via PRIME | NVIDIA device selected, present works | Not run |
| T07 | Explicit GPU selection in settings | Chosen present-capable GPU used; invalid choice explains and falls back | Not run |
| T08 | Window resize (many sizes, rapid) | Swapchain recreated, no validation errors, no crash | Not run |
| T09 | Minimise / restore | No hang, no stale frame, swapchain valid after restore | Not run |
| T10 | Fullscreen on/off | `showFullScreen()` works, state restored | Not run |
| T11 | Workspace switch / focus loss | Input released, frame loop continues or pauses correctly, focus restore works | Not run |
| T12 | Monitor/scale change (if permitted) | Extent and DPR updated, no mismatch | Not run |
| T13 | Fractional scale 1.25/1.5 (if permitted) | Rounded extents, aligned input, no validation errors | Not run |
| T14 | 120 Hz / VRR | Present pacing behaves; no forced 60 Hz; VRR subject to compositor | Not run |
| T15 | Gamepad hotplug | Controller detected/removed at runtime | Not run |
| T16 | Keyboard/mouse/touch | Input reaches emulation; focus loss releases keys | Not run |
| T17 | Suspend/resume via logind | Emulation pauses/resumes; renderer survives | Not run |
| T18 | Stop/start game repeatedly | Renderer/surface recreated cleanly; no leaks/validation errors | Not run |
| T19 | Close during emulation | Clean shutdown, no hang | Not run |
| T20 | XWayland fallback full session | Same as native matrix on `xcb` | Not run |
| T21 | Validation layers enabled | No errors; warnings triaged | Not run |
| T22 | Save data isolation | Portable `user/` used; existing data untouched | Not run |
| T23 | Upstream regression after sync | Matrix passes vs previous known-good | Not run |

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

## 6. Diagnostics tooling

| Tool | Purpose | Status |
|---|---|---|
| `tools/wayland/diag.sh` | Environment/session/GPU report | To add |
| `vulkaninfo --summary` | GPU/driver/extension inventory | Available |
| `vulkan-validation-layers` | API correctness | Missing (install) |
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

| Date | Build | Scenario | Result | Evidence |
|---|---|---|---|---|
| 2026-10-31 | Official v0.2.1 AppImage (extracted, isolated HOME) | Default launch on Hyprland | Observed: forced XWayland | `hyprctl`: class `eden`, `xwayland=true`; stderr "Wayland is disabled due to known issues" (hook sets `QT_QPA_PLATFORM=xcb`) |
| 2026-10-31 | Official v0.2.1 AppImage | Opt-in `I_WANT_A_BROKEN_WAYLAND_UI=1 QT_QPA_PLATFORM=wayland` | Observed: native Wayland GUI | `hyprctl`: class `dev.eden_emu.eden`, `xwayland=false` |
| 2026-10-31 | Official v0.2.1 AppImage | `WAYLAND_DEBUG=client` trace (opt-in) | Observed protocol set | binds `xdg_wm_base`, `zxdg_decoration_manager_v1`, `wp_fractional_scale_manager_v1`, `wp_viewporter`, `wp_presentation`, `zwp_linux_dmabuf_v1`, `wl_seat`, `wl_output` |
| 2026-10-31 | Official v0.2.1 AppImage | Vulkan surface + swapchain during title boot | Not run | No title/homebrew content available in the sandbox; not fabricated |

These rows describe the **official binary**, not the fork. They prove the
environment and Qt Wayland path; they do not prove emulator Vulkan
presentation. No result in this file may be recorded until it has actually been
observed.

Only real, observed results belong here, with the exact build commit,
environment and log excerpt (or a path to the saved log).
