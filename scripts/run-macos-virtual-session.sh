#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HARNESS_DIR="$ROOT_DIR/platforms/macos/harness"
MEDIA_DIR="$ROOT_DIR/platforms/macos/media-harness"
VIRTUAL_DISPLAY_BIN="$HARNESS_DIR/displaymesh-virtual-display"

HOST=""
WIDTH=""
HEIGHT=""
FPS=60
BITRATE=24
HIDPI=1
SECONDS=""
RECONNECT_ATTEMPTS=3
KEEP_VIRTUAL_DISPLAY=0

usage() {
  cat <<'EOF'
DisplayMesh macOS receiver-native virtual-display session

Usage:
  scripts/run-macos-virtual-session.sh --host <receiver-ip> [options]

Options:
  --width <pixels>      Override receiver-native virtual width
  --height <pixels>     Override receiver-native virtual height
  --fps <15-240>        Refresh/capture target (default: 60; capped by receiver)
  --bitrate <2-200>     H.264 bitrate in Mbps (default: 24)
  --hidpi <0|1>         Request HiDPI virtual mode (default: 1)
  --seconds <n>         Stop streaming automatically after n seconds
  --reconnect-attempts <0-10>
                        Retry transient sessions (default: 3)
  --keep-display        Leave the managed virtual display running on exit
  --help                Show this help

The host pairs first, negotiates the receiver panel, then creates the isolated
CGVirtualDisplay helper at receiver-native dimensions unless width/height are
explicitly overridden. Post-pairing DMP traffic uses the authenticated encrypted
session implemented by the macOS/Apple development binding.
EOF
}

die() {
  echo "DisplayMesh: $*" >&2
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --host)
      [[ $# -ge 2 ]] || die "--host requires a value"
      HOST="$2"
      shift 2
      ;;
    --width)
      [[ $# -ge 2 ]] || die "--width requires a value"
      WIDTH="$2"
      shift 2
      ;;
    --height)
      [[ $# -ge 2 ]] || die "--height requires a value"
      HEIGHT="$2"
      shift 2
      ;;
    --fps)
      [[ $# -ge 2 ]] || die "--fps requires a value"
      FPS="$2"
      shift 2
      ;;
    --bitrate)
      [[ $# -ge 2 ]] || die "--bitrate requires a value"
      BITRATE="$2"
      shift 2
      ;;
    --hidpi)
      [[ $# -ge 2 ]] || die "--hidpi requires a value"
      HIDPI="$2"
      shift 2
      ;;
    --seconds)
      [[ $# -ge 2 ]] || die "--seconds requires a value"
      SECONDS="$2"
      shift 2
      ;;
    --reconnect-attempts)
      [[ $# -ge 2 ]] || die "--reconnect-attempts requires a value"
      RECONNECT_ATTEMPTS="$2"
      shift 2
      ;;
    --keep-display)
      KEEP_VIRTUAL_DISPLAY=1
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      die "unknown argument: $1"
      ;;
  esac
done

[[ -n "$HOST" ]] || die "--host <receiver-ip> is required"
if [[ -n "$WIDTH" ]]; then
  [[ "$WIDTH" =~ ^[0-9]+$ ]] && (( WIDTH >= 640 )) || die "width must be >= 640"
fi
if [[ -n "$HEIGHT" ]]; then
  [[ "$HEIGHT" =~ ^[0-9]+$ ]] && (( HEIGHT >= 480 )) || die "height must be >= 480"
fi
[[ "$FPS" =~ ^[0-9]+$ ]] && (( FPS >= 15 && FPS <= 240 )) || die "fps must be 15...240"
[[ "$BITRATE" =~ ^[0-9]+$ ]] && (( BITRATE >= 2 && BITRATE <= 200 )) || die "bitrate must be 2...200"
[[ "$HIDPI" == "0" || "$HIDPI" == "1" ]] || die "hidpi must be 0 or 1"
[[ "$RECONNECT_ATTEMPTS" =~ ^[0-9]+$ ]] && (( RECONNECT_ATTEMPTS <= 10 )) || die "reconnect attempts must be 0...10"
if [[ -n "$SECONDS" ]]; then
  [[ "$SECONDS" =~ ^[0-9]+$ ]] && (( SECONDS > 0 )) || die "seconds must be > 0"
fi

echo "Building virtual-display helper…"
make -C "$HARNESS_DIR" >/dev/null

echo "Building macOS media harness…"
swift build --package-path "$MEDIA_DIR" >/dev/null

MEDIA_ARGS=(
  --host "$HOST"
  --virtual-display-helper "$VIRTUAL_DISPLAY_BIN"
  --fps "$FPS"
  --bitrate "$BITRATE"
  --hidpi "$HIDPI"
  --reconnect-attempts "$RECONNECT_ATTEMPTS"
)

if [[ -n "$WIDTH" ]]; then
  MEDIA_ARGS+=(--width "$WIDTH")
fi
if [[ -n "$HEIGHT" ]]; then
  MEDIA_ARGS+=(--height "$HEIGHT")
fi
if [[ -n "$SECONDS" ]]; then
  MEDIA_ARGS+=(--seconds "$SECONDS")
fi
if [[ "$KEEP_VIRTUAL_DISPLAY" -eq 1 ]]; then
  MEDIA_ARGS+=(--keep-virtual-display)
fi

swift run --package-path "$MEDIA_DIR" displaymesh-mac-media-harness -- "${MEDIA_ARGS[@]}"
