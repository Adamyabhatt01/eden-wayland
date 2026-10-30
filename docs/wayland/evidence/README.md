# Runtime evidence (2026-10-31)

These files are raw observations from the fork at commit `41ad87851a`
(`linux-wayland`, A1 + A2 + B1). The binary reports `e287b515ab-linux-wayland`
in its title because CMake was configured before the B1 commit; the source
tree built is `41ad87851a`.

No content is bundled. nx-hbmenu v3.6.1 (GPLv2, SHA-256
`6cf6d130515723ebe0041c2479420caf9726895087439ff7b2e528c2ed39c100`) was
fetched to `/tmp/eden-homebrew/hbmenu.nro`. Started as a bare NRO it displays
its own `launchInit() failed` page, which still exercises the renderer,
swapchain and presentation loop. It is redistributable homebrew and requires
no prod.keys; the NRO itself is not committed here.

## Environment

- Arch Linux, kernel 7.2.11, Hyprland 0.56.2, Wayland session `wayland-1`
- Qt 6.12.0 (`libqwayland.so`), build `RelWithDebInfo`, `ENABLE_QT=ON`
- NVIDIA GeForce RTX 3050 Laptop GPU, driver 615.78.08 (Vulkan 1.4.351)
- Intel Iris Xe (ADL GT2), Mesa 26.2.5 (Vulkan 1.4.354)
- Vulkan validation layers 1.4.363 extracted from the Arch package to
  `/tmp/vk-validation-root` (not installed system-wide)

## Launch commands

All runs used the portable profile (`build/wayland-run/user/`):

```sh
cd build/wayland-run
QT_QPA_PLATFORM=wayland WAYLAND_DISPLAY=wayland-1 DISPLAY=:1 \
  XDG_SESSION_TYPE=wayland ../baseline-qt/bin/eden \
  /tmp/eden-homebrew/hbmenu.nro
```

- Intel run adds `VK_LOADER_DRIVERS_SELECT='*intel*'`.
- XWayland run uses `QT_QPA_PLATFORM=xcb` (same display variables).
- Validation run adds `VK_LAYER_PATH=/tmp/vk-validation-root/usr/share/vulkan/explicit_layer.d`
  and `LD_LIBRARY_PATH=/tmp/vk-validation-root/usr/lib`, with
  `Renderer.debug=true` in the portable config.

`vulkan_device=0` selects the RTX 3050 because Eden sorts discrete GPUs first;
`vulkaninfo` lists Intel first. See `TESTING.md` §4.

## Files

| File | sha256 | Content |
|---|---|---|
| `2026-10-31-native-wayland-nvidia.log` | `bd690e42…c60c1c3` | Native Wayland, NVIDIA, windowed → resize → fullscreen → close |
| `2026-10-31-native-wayland-intel.log` | `e3c53d9e…711b2074` | Native Wayland, Intel via loader selection |
| `2026-10-31-xwayland.log` | `43d92a66…d04049056` | XWayland (`xcb`), Xlib surface, resize, close |
| `2026-10-31-native-wayland-validation.log` | `41e5e5be…efdd322a` | Validation layers enabled (`Renderer.debug=true`) |
| `2026-10-31-native-wayland-nvidia-windowed.png` | | hbmenu page, windowed, 60 FPS |
| `2026-10-31-native-wayland-nvidia-resized.png` | | Same run after compositor resize |
| `2026-10-31-native-wayland-nvidia-fullscreen.png` | | Fullscreen, 1920x1017 swapchain |
| `2026-10-31-native-wayland-intel-windowed.png` | | Intel device, 60 FPS |
| `2026-10-31-xwayland-windowed.png` | | XWayland window, 60 FPS, cropped |
| `2026-10-31-validation-run.png` | | Validation-enabled run |

Full hashes:

```
bd690e42002c7d9b9eb2775830ccc28b569e8975095a8df647cf2cab2c60c1c3  native-wayland-nvidia
e3c53d9eba06a97d7ac5b3a097c174dd20bb5f0f9a643d3ef1e7781d711b2074  native-wayland-intel
43d92a669faca8bb7de68c8feaec06fd6bdf50116977ca89ba446d5d04049056  xwayland
41e5e5be380b51175b0b30b8f8f433bf347ee2a91c8bc7a7835adbbeefdd322a  native-wayland-validation
```

Log paths inside the files show `/home/user/projects/...`; this is the
sandbox's path alias for `/home/adamya/projects/...` (same inode).
