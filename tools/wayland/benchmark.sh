#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Benchmark Eden on native Wayland vs XWayland.
#
# Usage:
#   tools/wayland/benchmark.sh <game-file> [seconds]
#
# Logs MangoHud CSV (if available) and Eden logs into
# docs/wayland/evidence/benchmark-YYYYMMDD-HHMMSS/.
#
# Requires: legal dumped game + Eden keys in the portable profile
# (build/wayland-run/user/keys). User-launched; this harness only drives
# the binary, it never reads the game file contents.

set -euo pipefail

REPO_ROOT=$(git -C "$(dirname "$0")/../.." rev-parse --show-toplevel)
GAME=${1:?usage: benchmark.sh <game-file> [seconds]}
SECONDS_RUN=${2:-60}
BIN=${BIN:-"$REPO_ROOT/build/bench/bin/eden"}
export LD_LIBRARY_PATH=/tmp/qt6-charts-root/usr/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}

STAMP=$(date +%Y%m%d-%H%M%S)
OUT="$REPO_ROOT/docs/wayland/evidence/benchmark-$STAMP"
mkdir -p "$OUT"

run_one() {
    local label=$1 qpa=$2
    echo "=== $label (QT_QPA_PLATFORM=$qpa, ${SECONDS_RUN}s) ==="
    ( export QT_QPA_PLATFORM="$qpa";
      export EDEN_LOG="$OUT/eden-$label.log";
      timeout --signal=TERM "$SECONDS_RUN" \
          tools/wayland/run-portable.sh "$BIN" "$GAME" \
          > "$OUT/console-$label.log" 2>&1 ) || true
    echo "log: $OUT/eden-$label.log"
}

run_one wayland wayland
run_one xwayland xcb

echo
echo "Done. Logs land in $OUT."
if command -v mangohud >/dev/null; then
    echo "Tip: enable CSV logging first — set 'logging=true' in"
    echo "~/.config/MangoHud/MangoHud.conf (MANGOHUD=1 alone only shows the overlay;"
    echo "F12 is the screenshot key, not a logging toggle). CSVs land in"
    echo "~/.local/share/MangoHud/."
fi
