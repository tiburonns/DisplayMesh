#!/bin/sh
set -eu

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

xcodebuild \
  -project DisplayMeshLegacy.xcodeproj \
  -scheme DisplayMeshLegacy \
  -configuration Release \
  -sdk iphoneos \
  -arch armv7 \
  IPHONEOS_DEPLOYMENT_TARGET=9.0 \
  build
