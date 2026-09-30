# DisplayMesh macOS Media Harness

This harness is the first end-to-end macOS host media path for DisplayMesh.

It connects to the iPhone/iPad receiver, waits for a fresh receiver challenge, signs the six-digit pairing request with a persistent P-256 identity stored in macOS Keychain, captures a selected macOS display with ScreenCaptureKit, encodes it as low-delay H.264 using VideoToolbox, wraps each access unit in the DMP video packet format, and sends it to the receiver.

It is intentionally separate from the production host backend while the media path is validated on real hardware.

## What it proves

- ScreenCaptureKit can provide the host frames used by DisplayMesh.
- The capture path can output NV12 directly.
- VideoToolbox can consume those frames without a required CPU color conversion.
- H.264 output is converted from AVCC to DMP Annex-B.
- SPS/PPS are repeated with keyframes so the receiver can join/recover.
- Receiver keyframe requests force the next host frame to be an IDR.
- The host identity persists in Keychain and every pairing request is challenge-bound and signed.
- Capture input is dropped before encoding while the TCP video send is busy instead of building an unbounded media queue.
- Binary DMP touch samples map one finger to pointer/click/drag and two fingers to scrolling.
- The gesture state machine releases an active mouse button before entering two-finger scroll and never turns the remaining finger into an accidental click.

## Build

```bash
swift build --package-path platforms/macos/media-harness
swift test --package-path platforms/macos/media-harness
```

## Run

First start the DisplayMesh receiver on the iPhone/iPad.

List capturable displays:

```bash
swift run --package-path platforms/macos/media-harness \
  displaymesh-mac-media-harness --list
```

Stream the first display:

```bash
swift run --package-path platforms/macos/media-harness \
  displaymesh-mac-media-harness \
  --host 192.168.1.25 \
  --fps 60 \
  --bitrate 24
```

macOS must grant Screen Recording permission to the harness/Terminal process.

Touch control additionally requires Accessibility permission. The harness requests the system prompt when needed. Apple documents that this prompt is asynchronous, so grant the permission in System Settings if the first check still reports that access is unavailable.

## Current limitations

- Captures an existing display; integration with the DisplayMesh virtual-display backend is still pending.
- Development transport is plaintext TCP. Production TLS 1.3 remains mandatory before release.
- macOS maps touch to pointer/drag/scroll because the first public integration path is synthetic mouse/scroll input rather than Windows-style injected multitouch.
- Apple Pencil currently follows the same pointer path; higher-fidelity stylus mapping remains a later milestone.
- USB/usbmux is not connected to this harness yet.
- Hardware performance claims require physical-device testing.


## Adaptive raster

Receiver telemetry can now move the development pipeline through 100%, 85%, 75%, and 67% encoded raster steps. Reconfiguration updates ScreenCaptureKit first, recreates the VideoToolbox encoder at the negotiated raster, drops frames during the transition, and forces recovery with a fresh keyframe. The receiver panel geometry remains unchanged. If a live raster reconfiguration cannot rebuild the encoder, the development session tears down instead of continuing with mismatched capture/encode state.
