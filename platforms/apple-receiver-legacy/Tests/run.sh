#!/bin/sh
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/displaymesh-legacy-tests.XXXXXX")"
trap 'rm -rf "$BUILD_DIR"' EXIT INT TERM

xcrun --sdk macosx clang \
  -fobjc-arc \
  -fmodules \
  -framework Foundation \
  -I "$ROOT/Sources" \
  "$ROOT/Sources/DMLegacyFrameCodec.m" \
  "$ROOT/Tests/FrameCodecTests.m" \
  -o "$BUILD_DIR/frame-codec-tests"

"$BUILD_DIR/frame-codec-tests"
