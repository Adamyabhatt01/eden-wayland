#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Development build (RelWithDebInfo) with CMake + Ninja.
# Does not modify the source tree and does not install anything.

set -euo pipefail

REPO_ROOT=$(git -C "$(dirname "$0")/.." rev-parse --show-toplevel)
BUILD_DIR=${BUILD_DIR:-"$REPO_ROOT/build/dev"}
BUILD_TYPE=${BUILD_TYPE:-RelWithDebInfo}
JOBS=${JOBS:-"$(nproc)"}

for tool in cmake ninja; do
    command -v "$tool" >/dev/null || { echo "Missing tool: $tool" >&2; exit 1; }
done

if ! command -v qmake6 >/dev/null; then
    echo "Warning: qmake6 not found; is Qt 6 installed?" >&2
fi

echo "Configuring $BUILD_TYPE in $BUILD_DIR"
cmake -S "$REPO_ROOT" -B "$BUILD_DIR" -G Ninja \
    -DCMAKE_BUILD_TYPE="$BUILD_TYPE" \
    -DENABLE_QT=ON \
    -DENABLE_DEBUG_TOOLS="${ENABLE_DEBUG_TOOLS:-ON}"

echo "Building with $JOBS jobs"
cmake --build "$BUILD_DIR" -j"$JOBS"

echo
echo "Binary: $BUILD_DIR/bin/eden"
echo "Run isolated (portable user/ directory):"
echo "  tools/wayland/run-portable.sh $BUILD_DIR/bin/eden"
