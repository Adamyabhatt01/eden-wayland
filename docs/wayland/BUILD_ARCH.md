# Arch Linux Build and Packaging

Target: Arch Linux, CMake + Ninja, system Qt 6, Vulkan, Hyprland/Wayland.

## 1. Dependencies

### Build (pacman)

```sh
sudo pacman -S --needed base-devel cmake ninja git boost fmt sdl3 enet \
  qt6-base qt6-charts qt6-multimedia qt6-wayland qt6-svg qt6-declarative \
  vulkan-headers vulkan-utility-libraries vulkan-icd-loader vulkan-validation-layers \
  spirv-tools spirv-headers glslang libusb ffmpeg libzip lz4 zlib zstd \
  nlohmann-json openssl opus gamemode catch2 wayland wayland-protocols \
  wayland-utils pkgconf
```

Notes:

- `qt6-charts` is mandatory: `find_package(Qt6 REQUIRED COMPONENTS Charts)`.
- On Arch `qt6-base` 6.12, the Qt Wayland platform plugin
  (`libqwayland.so`) and `libQt6WaylandClient` ship in `qt6-base`; the
  `qt6-wayland` package remains listed for portability and for QML/compositor
  APIs.
- `enet`, `gamemode`, `catch2` can be fetched by CPM, but system packages are
  preferred for reproducible distro builds.
- `vulkan-headers` and `vulkan-utility-libraries` are configured as one
  dependent group. If only one is installed system-wide, CMake aborts with
  "Partial dependency installation detected"; either install both or configure
  with `-DVulkanHeaders_FORCE_BUNDLED=ON` to bundle both.
- `vulkan-validation-layers` is not required to build; it is required for the
  validation test matrix.
- Missing packages on this machine at the time of writing: `qt6-charts`
  (blocking), `vulkan-utility-libraries` (workaround above),
  `vulkan-validation-layers`, `wayland-utils`, plus optional
  `enet`/`gamemode`/`catch2`.

### Runtime

`qt6-base`, `qt6-charts`, `qt6-wayland` (or equivalent providing the Wayland
QPA plugin), `sdl3`, `ffmpeg`, `libusb`, `cubeb`/PipeWire or PulseAudio,
`vulkan-icd-loader`, one or more Vulkan ICDs (`vulkan-intel`,
`nvidia-utils`, ...), `libxkbcommon`, `wayland`, `gamemode` (optional),
`qt6-multimedia` (only if built with `YUZU_USE_QT_MULTIMEDIA`).

Do **not** bundle system Qt libraries into the Arch package.

## 2. Configure and build

Development (Release with debug info, matches common Arch practice):

```sh
cmake -B build/rel -G Ninja \
  -DCMAKE_BUILD_TYPE=RelWithDebInfo \
  -DENABLE_QT=ON \
  -DYUZU_CMD=ON
cmake --build build/rel -j"$(nproc)"
```

Release:

```sh
cmake -B build/release -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DENABLE_QT=ON \
  -DENABLE_WERROR=ON
cmake --build build/release -j"$(nproc)"
```

Debug with validation layers:

```sh
cmake -B build/debug -G Ninja \
  -DCMAKE_BUILD_TYPE=Debug \
  -DENABLE_QT=ON \
  -DENABLE_DEBUG_TOOLS=ON
cmake --build build/debug -j"$(nproc)"
```

Sanitizers (optional; not for performance runs):

```sh
cmake -B build/asan -G Ninja \
  -DCMAKE_BUILD_TYPE=RelWithDebInfo \
  -DCMAKE_CXX_FLAGS="-fsanitize=address,undefined -fno-omit-frame-pointer" \
  -DCMAKE_EXE_LINKER_FLAGS="-fsanitize=address,undefined"
cmake --build build/asan -j"$(nproc)"
```

The project uses CPM for missing dependencies. Its cache lives in
`.cache/cpm`. Offline builds require all dependencies to be present in that
cache or installed on the system.

## 3. Isolated runtime and portable mode

Eden treats an existing `./user` directory as portable data
(`src/common/fs/path_util.cpp:108-150`). Development runs must use this to
avoid touching `~/.config/eden` and `~/.local/share/eden`.

```sh
mkdir -p build/wayland-run/user
cd build/wayland-run
../rel/bin/eden
```

To reuse existing keys/firmware **without modifying them**, symlink read-only
subdirectories into the portable `user/` tree only if the user explicitly
authorizes it; never copy commercial content into the repository.

## 4. Installation and removal (from a build tree)

```sh
sudo cmake --install build/release --prefix /usr
# or a staged install:
DESTDIR="$PWD/pkg" cmake --install build/release --prefix /usr
```

Installed by upstream rules: the `eden` binary, desktop file, icon,
appstream metainfo, MIME XML, and optionally udev rules
(`CMakeLists.txt:731-742`). Removal is manual unless installed via a package
manager; prefer `pacman -R eden-wayland`.

## 5. Arch package (Phase 6)

Planned `packaging/arch/PKGBUILD`:

- `pkgname=eden-wayland`
- `source=("git+https://git.eden-emu.dev/eden-emu/eden.git#tag=<pinned>"
  or a release tarball pinned by commit)`
- `depends=(qt6-base qt6-charts qt6-wayland sdl3 ffmpeg vulkan-icd-loader
  libusb cubeb gamemode libxkbcommon wayland)`
- `makedepends=(cmake ninja git boost fmt enet ...)`
- `options=(!strip)` only if crash symbols are desired; otherwise standard.
- Build with `-DCMAKE_BUILD_TYPE=Release -DENABLE_QT=ON`.
- Install with `cmake --install`.
- Optional: udev rules for controllers/gyro (`YUZU_INSTALL_UDEV_RULES=ON`).
- Do not vendor keys, firmware, games, or Qt.

Validation: `makepkg -s` in a clean chroot, install, run native Wayland and
XWayland, verify the package does not shadow system Qt.

AppImage feasibility: technically possible with linuxdeploy/Qt deployment,
but it necessarily bundles Qt and duplicates system graphics libraries, which
conflicts with this project's "no unnecessary Qt bundling" rule. It is
therefore optional and non-default; document any recipe as unverified until
tested.

## 6. Runtime diagnostics

```sh
tools/wayland/diag.sh                 # human-readable report
tools/wayland/diag.sh > diag.txt      # save for bug reports
```

The script is read-only. It reports session type, compositor version, monitor
layout/scale/refresh, Qt version and platform plugin availability, Vulkan
loader and GPUs, active ICDs, relevant environment variables, and package
versions. It does not launch Eden.

## 7. Reproducibility notes

- Pin the upstream commit in packaging and in release notes.
- Record: compiler, CMake, Ninja, Qt, Vulkan loader, and GPU driver versions.
- Builds that mix system and CPM dependencies are reproducible only if the
  CPM cache is pinned; prefer system packages for release builds.
- Do not enable LTO selectively without measuring; the project's
  `DefaultConfig`/`UseLTO` defaults apply.
