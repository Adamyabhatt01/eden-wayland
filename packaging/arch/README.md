# Eden-Wayland packaging

Maintainer-local packaging for the native-Wayland fork
(branch `linux-wayland`).

`PKGBUILD` builds from the local checkout via `git+file://` because the
fork has no published origin remote yet. It is not usable on other
machines until `_source` is pointed at a real remote (or the file://
path is adjusted for the local tree).

Runtime note for the first real install: `qt6-wayland` (already in
`depends`) provides the native Wayland Qt platform plugin;
`QT_QPA_PLATFORM=xcb` selects the XWayland fallback.
