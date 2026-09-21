#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HARNESS_DIR="$ROOT_DIR/platforms/macos/harness"
MEDIA_DIR="$ROOT_DIR/platforms/macos/media-harness"
VIRTUAL_DISPLAY_BIN="$HARNESS_DIR/displaymesh-virtual-display"

HOST=""
WIDTH=1920
HEIGHT=1080
FPS=60
BITRATE=24
HIDPI=1
SECONDS=""
KEEP_VIRTUAL_DISPLAY=0

usage() {
  cat <<'EOF'
DisplayMesh macOS virtual-display session

Usage:
  scripts/run-macos-virtual-session.sh --host <receiver-ip> [options]

Options:
  --width <pixels>      Virtual/encoded width (default: 1920)
  --height <pixels>     Virtual/encoded height (default: 1080)
  --fps <15-240>        Refresh/capture target (default: 60)
  --bitrate <2-200>     H.264 bitrate in Mbps (default: 24)
  --hidpi <0|1>         Request HiDPI virtual mode (default: 1)
  --seconds <n>         Stop streaming automatically after n seconds
  --keep-display        Leave virtual display running when media exits
  --help                Show this help

This is a developer integration path. Transport remains plaintext TCP and is
not a production release path.
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
[[ "$WIDTH" =~ ^[0-9]+$ ]] && (( WIDTH >= 640 )) || die "width must be >= 640"
[[ "$HEIGHT" =~ ^[0-9]+$ ]] && (( HEIGHT >= 480 )) || die "height must be >= 480"
[[ "$FPS" =~ ^[0-9]+$ ]] && (( FPS >= 15 && FPS <= 240 )) || die "fps must be 15...240"
[[ "$BITRATE" =~ ^[0-9]+$ ]] && (( BITRATE >= 2 && BITRATE <= 200 )) || die "bitrate must be 2...200"
[[ "$HIDPI" == "0" || "$HIDPI" == "1" ]] || die "hidpi must be 0 or 1"
if [[ -n "$SECONDS" ]]; then
  [[ "$SECONDS" =~ ^[0-9]+$ ]] && (( SECONDS > 0 )) || die "seconds must be > 0"
fi

LOG_DIR="$(mktemp -d /tmp/displaymesh-session.XXXXXX)"
DISPLAY_LOG="$LOG_DIR/virtual-display.log"
DISPLAY_PID=""

cleanup() {
  local exit_code=$?
  if [[ -n "$DISPLAY_PID" && "$KEEP_VIRTUAL_DISPLAY" -eq 0 ]]; then
    kill -TERM "$DISPLAY_PID" 2>/dev/null || true
    wait "$DISPLAY_PID" 2>/dev/null || true
  fi
  rm -rf "$LOG_DIR"
  exit "$exit_code"
}
trap cleanup EXIT INT TERM

echo "Building virtual-display harness…"
make -C "$HARNESS_DIR" >/dev/null

echo "Building macOS media harness…"
swift build --package-path "$MEDIA_DIR" >/dev/null

echo "Creating DisplayMesh virtual display ${WIDTH}x${HEIGHT}@${FPS}, HiDPI=${HIDPI}…"
"$VIRTUAL_DISPLAY_BIN" "$WIDTH" "$HEIGHT" "$FPS" "$HIDPI" >"$DISPLAY_LOG" 2>&1 &
DISPLAY_PID=$!

DISPLAY_ID=""
for _ in {1..50}; do
  if ! kill -0 "$DISPLAY_PID" 2>/dev/null; then
    cat "$DISPLAY_LOG" >&2
    die "virtual-display harness exited before a display was created"
  fi

  DISPLAY_ID="$(sed -n 's/.*id=\([0-9][0-9]*\).*/\1/p' "$DISPLAY_LOG" | head -n 1)"
  if [[ -n "$DISPLAY_ID" ]]; then
    break
  fi
  sleep 0.1
done

if [[ -z "$DISPLAY_ID" ]]; then
  cat "$DISPLAY_LOG" >&2
  die "timed out waiting for the virtual display ID"
fi

echo "Virtual display ready: id=$DISPLAY_ID"
echo "Connecting media path to receiver at $HOST…"

MEDIA_ARGS=(
  --host "$HOST"
  --display "$DISPLAY_ID"
  --fps "$FPS"
  --bitrate "$BITRATE"
  --width "$WIDTH"
  --height "$HEIGHT"
)

if [[ -n "$SECONDS" ]]; then
  MEDIA_ARGS+=(--seconds "$SECONDS")
fi

swift run --package-path "$MEDIA_DIR" displaymesh-mac-media-harness -- "${MEDIA_ARGS[@]}"
