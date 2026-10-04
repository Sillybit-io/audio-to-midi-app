#!/bin/zsh
# Xcode post-build phase: copies sillymidi-engine (and any Metal libraries) into the
# app's Contents/MacOS and ad-hoc signs the helper so it inherits the app sandbox.
set -euo pipefail

root="${SRCROOT:-${0:A:h:h}}"
arch="${NATIVE_ARCH_ACTUAL:-$(uname -m)}"
build="$root/Engine/build-$arch"
dest="$TARGET_BUILD_DIR/$EXECUTABLE_FOLDER_PATH"

if [[ ! -x "$build/sillymidi-engine" ]]; then
  echo "error: $build/sillymidi-engine is missing; run scripts/build-engine.sh" >&2
  exit 1
fi

mkdir -p "$dest"
cp -f "$build/sillymidi-engine" "$dest/sillymidi-engine"
for lib in "$build"/*.metallib(N); do
  cp -f "$lib" "$dest/"
  codesign --force --sign - "$dest/${lib:t}"
done

codesign --force --sign - --entitlements "$root/Config/Engine.entitlements" "$dest/sillymidi-engine"
