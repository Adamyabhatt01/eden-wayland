#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Launch Eden from an isolated portable data directory.
#
# Usage:
#   tools/wayland/run-portable.sh [path/to/eden] [eden args...]
#
# Environment:
#   RUN_DIR        runtime directory (default: <repo>/build/wayland-run)
#   EDEN_DISPLAY   auto | wayland | x11   (default: auto)
#   EDEN_GPU       auto | intel | nvidia   (default: auto)
#   EDEN_LOG       if set, tee stdout/stderr to this file (default: <run>/eden.log)
#
# `auto` does not set QT_QPA_PLATFORM, so this script never overrides an
# explicit environment. Existing Eden data in ~/.config/eden and
# ~/.local/share/eden is not touched: a portable ./user directory is used.

set -euo pipefail

REPO_ROOT=$(git -C "$(dirname "$0")/../.." rev-parse --show-toplevel)
BIN=${1:-"$REPO_ROOT/build/dev/bin/eden"}
if (($#)); then shift; fi

if [[ ! -x "$BIN" ]]; then
    echo "Executable not found: $BIN" >&2
    echo "Build first: scripts/build-dev.sh" >&2
    exit 1
fi
BIN=$(realpath "$BIN")

RUN_DIR=${RUN_DIR:-"$REPO_ROOT/build/wayland-run"}
mkdir -p "$RUN_DIR/user"
cd "$RUN_DIR"

case "${EDEN_DISPLAY:-auto}" in
    wayland) export QT_QPA_PLATFORM=wayland ;;
    x11|xcb) export QT_QPA_PLATFORM=xcb ;;
    auto) : ;;
    *) echo "EDEN_DISPLAY must be auto|wayland|x11" >&2; exit 2 ;;
esac

case "${EDEN_GPU:-auto}" in
    nvidia)
        export __NV_PRIME_RENDER_OFFLOAD=1
        export __VK_LAYER_NV_optimus=NVIDIA_only
        unset VK_LOADER_DRIVERS_SELECT || true
        ;;
    intel)
        unset __NV_PRIME_RENDER_OFFLOAD || true
        unset __VK_LAYER_NV_optimus || true
        export VK_LOADER_DRIVERS_SELECT='*intel*'
        ;;
    auto) : ;;
    *) echo "EDEN_GPU must be auto|intel|nvidia" >&2; exit 2 ;;
esac

LOG=${EDEN_LOG:-"$RUN_DIR/eden.log"}

{
    echo "== $(date -Is) =="
    echo "binary: $BIN"
    echo "cwd:    $RUN_DIR"
    echo "QT_QPA_PLATFORM=${QT_QPA_PLATFORM-<unset>}"
    echo "EDEN_GPU=${EDEN_GPU:-auto}"
    echo "WAYLAND_DISPLAY=${WAYLAND_DISPLAY-<unset>}"
    echo "DISPLAY=${DISPLAY-<unset>}"
    env | grep -E '^(__NV_PRIME_RENDER_OFFLOAD|__VK_LAYER_NV_optimus|VK_LOADER_DRIVERS_SELECT|VK_ICD_FILENAMES|DRI_PRIME)=' || true
    echo "=========================="
} | tee -a "$LOG" >/dev/null

"$BIN" "$@" 2>&1 | tee -a "$LOG"
exit "${PIPESTATUS[0]}"
