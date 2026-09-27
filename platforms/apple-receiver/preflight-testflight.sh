#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
RECEIVER_DIR="$ROOT_DIR/platforms/apple-receiver"
cd "$ROOT_DIR"

echo "== DisplayMesh Receiver TestFlight preflight =="
python3 scripts/validate-apple-receiver.py

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "xcodegen 2.46.0 is required. Install the pinned version used by CI." >&2
  exit 1
fi

cd "$RECEIVER_DIR"
xcodegen generate

xcodebuild \
  -project DisplayMeshReceiver.xcodeproj \
  -scheme DisplayMeshReceiver \
  -configuration Release \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  SWIFT_TREAT_WARNINGS_AS_ERRORS=YES \
  build

xcodebuild \
  -project DisplayMeshReceiver.xcodeproj \
  -scheme DisplayMeshReceiver \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO \
  SWIFT_TREAT_WARNINGS_AS_ERRORS=YES \
  build

DEVICE_ID=$(xcrun simctl list devices available -j | python3 -c 'import json,sys; data=json.load(sys.stdin)["devices"]; print(next(device["udid"] for devices in data.values() for device in devices if device.get("isAvailable")))')
xcodebuild \
  -project DisplayMeshReceiver.xcodeproj \
  -scheme DisplayMeshReceiver \
  -destination "platform=iOS Simulator,id=$DEVICE_ID" \
  CODE_SIGNING_ALLOWED=NO \
  test

echo "PASS: DisplayMesh Receiver source gate is ready for signed Archive/Validate App."
echo "Remaining gates: paid-team signing, Local Network permission, real host pairing, latency and long-session hardware acceptance."
