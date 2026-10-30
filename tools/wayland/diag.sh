#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Read-only Wayland/Vulkan environment report for Eden-Wayland.
# Prints to stdout; redirect to a file for bug reports.
#
# This script does not launch Eden and does not modify system state.

set -uo pipefail

have() { command -v "$1" >/dev/null 2>&1; }
section() { printf '\n=== %s ===\n' "$1"; }

section "Date and host"
date -Is
uname -a
[[ -r /etc/os-release ]] && grep -E '^(PRETTY_NAME|BUILD_ID)=' /etc/os-release

section "Session"
for v in XDG_SESSION_TYPE XDG_CURRENT_DESKTOP XDG_SESSION_DESKTOP \
         WAYLAND_DISPLAY DISPLAY HYPRLAND_INSTANCE_SIGNATURE XDG_RUNTIME_DIR; do
    printf '%s=%s\n' "$v" "${!v-<unset>}"
done
if [[ -n "${WAYLAND_DISPLAY:-}" && -n "${XDG_RUNTIME_DIR:-}" ]]; then
    ls -l "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY" 2>/dev/null || echo "Wayland socket not found"
fi

section "Compositor"
if have hyprctl; then
    hyprctl version 2>/dev/null | head -4
    echo
    hyprctl monitors 2>/dev/null | grep -E '^(Monitor|\s+[0-9]+x[0-9]+@|\s+scale:|\s+availableModes:)' || true
    if have jq; then
        echo
        echo "Native clients (class, xwayland):"
        hyprctl clients -j 2>/dev/null | jq -r '.[] | "\(.class)\txwayland=\(.xwayland)\t\(.title)"' | head -20 || true
    fi
else
    echo "hyprctl not found"
fi

section "Qt"
if have qmake6; then
    qmake6 -query QT_VERSION
    qmake6 -query QT_INSTALL_PLUGINS
    echo "Platform plugins:"
    ls "${QT_PLUGIN_PATH:-$(qmake6 -query QT_INSTALL_PLUGINS)/platforms}" 2>/dev/null || true
    echo "Wayland shell integrations:"
    ls "${QT_PLUGIN_PATH:-$(qmake6 -query QT_INSTALL_PLUGINS)/wayland-shell-integration}" 2>/dev/null || true
    qplugin=$(qmake6 -query QT_INSTALL_PLUGINS)/platforms/libqwayland.so
    if [[ -f "$qplugin" ]]; then
        missing=$(ldd "$qplugin" 2>/dev/null | grep -c 'not found' || true)
        echo "libqwayland.so dependencies not found: $missing"
    else
        echo "libqwayland.so NOT FOUND"
    fi
else
    echo "qmake6 not found"
fi

section "Qt/environment variables"
for v in QT_QPA_PLATFORM QT_QPA_PLATFORMTHEME QT_WAYLAND_DISABLE_WINDOWDECORATION \
         QT_WAYLAND_FORCE_DPI QT_SCALE_FACTOR QT_SCALE_FACTOR_ROUNDING_POLICY \
         QT_AUTO_SCREEN_SCALE_FACTOR QT_LOGGING_RULES; do
    printf '%s=%s\n' "$v" "${!v-<unset>}"
done

section "Vulkan loader and devices"
if have vulkaninfo; then
    vulkaninfo --summary 2>/dev/null | sed -n '/^Vulkan Instance Version/p;/^Devices:/,$p'
else
    echo "vulkaninfo not found"
fi
echo
echo "ICD manifests:"
ls /usr/share/vulkan/icd.d/*.json 2>/dev/null || echo "none"
if have jq; then
    for f in /usr/share/vulkan/icd.d/*.json; do
        [[ -e "$f" ]] || continue
        printf '%s: ' "$f"
        jq -r '.ICD.library_path // .ICD.library_arch_path // "?"' "$f" 2>/dev/null
    done
fi
echo
echo "Explicit layers selected by the loader:"
vulkaninfo --summary 2>/dev/null | sed -n '/^Instance Layers:/,/^$/p' | head -20

section "PRIME / NVIDIA"
for v in __NV_PRIME_RENDER_OFFLOAD __VK_LAYER_NV_optimus DRI_PRIME \
         VK_ICD_FILENAMES VK_DRIVER_FILES VK_LOADER_DEBUG VK_INSTANCE_LAYERS; do
    printf '%s=%s\n' "$v" "${!v-<unset>}"
done
if have prime-run; then
    echo "prime-run present: $(command -v prime-run)"
    prime-run vulkaninfo --summary 2>/dev/null | sed -n '/^GPU[0-9]:/,/^$/p' | grep -E 'GPU[0-9]:|deviceName|driverInfo|driverID|apiVersion' || echo "prime-run vulkaninfo failed"
else
    echo "prime-run not present"
fi

section "Graphics tooling"
for t in vulkaninfo mangoapp mangohud hyprctl wayland-info weston-info \
         renderdoccmd apitrace jq sensors nvidia-smi; do
    if have "$t"; then printf '%-14s %s\n' "$t" "$(command -v "$t")"; else printf '%-14s MISSING\n' "$t"; fi
done

section "Packages"
if have pacman; then
    for p in qt6-base qt6-wayland qt6-charts qt6-multimedia sdl3 vulkan-icd-loader \
             vulkan-intel vulkan-validation-layers nvidia-utils wayland wayland-utils \
             libxkbcommon mesa mangohud gamemode; do
        if q=$(pacman -Q "$p" 2>/dev/null); then echo "$q"; else echo "$p MISSING"; fi
    done
else
    echo "pacman not found (non-Arch system)"
fi

section "Eden-Wayland repository"
if git -C "$(dirname "$0")/../.." rev-parse --git-dir >/dev/null 2>&1; then
    repo=$(git -C "$(dirname "$0")/../.." rev-parse --show-toplevel)
    echo "repo: $repo"
    git -C "$repo" log -1 --format='HEAD %H %ad %s' --date=iso
    git -C "$repo" status --short | head -20
fi

echo
echo "End of report."
