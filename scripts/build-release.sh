#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Release build with CMake + Ninja. No installation, no stripping.

set -euo pipefail

REPO_ROOT=$(git -C "$(dirname "$0")/.." rev-parse --show-toplevel)
BUILD_DIR=${BUILD_DIR:-"$REPO_ROOT/build/release"}
JOBS=${JOBS:-"$(nproc)"}

for tool in cmake ninja; do
    command -v "$tool" >/dev/null || { echo "Missing tool: $tool" >&2; exit 1; }
done

echo "Configuring Release in $BUILD_DIR"
cmake -S "$REPO_ROOT" -B "$BUILD_DIR" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DENABLE_QT=ON \
    -DENABLE_WERROR=ON

echo "Building with $JOBS jobs"
cmake --build "$BUILD_DIR" -j"$JOBS"

echo
echo "Binary: $BUILD_DIR/bin/eden"
echo "Stage install: DESTDIR=\"$PWD/pkg\" cmake --install \"$BUILD_DIR\" --prefix /usr"
