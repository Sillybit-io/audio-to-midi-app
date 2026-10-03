#!/bin/zsh
# Builds sillymidi-engine for the host architecture into Engine/build-<arch>.
set -euo pipefail

root="${0:A:h:h}"
arch="$(uname -m)"
build="$root/Engine/build-$arch"

precompiled=OFF
if xcrun -sdk macosx metal --version >/dev/null 2>&1; then
  precompiled=ON
fi

cmake -S "$root/Engine" -B "$build" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_OSX_ARCHITECTURES="$arch" \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=26.0 \
  -DMUSCRIPTOR_METAL_PRECOMPILED="$precompiled"
cmake --build "$build" --target sillymidi-engine
echo "built $build/sillymidi-engine"
