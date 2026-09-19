# macOS native backend

This directory is reserved for the native macOS display/capture/encode/render implementation.

## Responsibilities

- virtual display lifecycle
- display mode / HiDPI configuration
- ScreenCaptureKit capture
- VideoToolbox encode/decode
- Metal rendering
- macOS input injection
- permission/status reporting

## Distribution constraint

The virtual-display mechanism must be reviewed independently from the shared application because practical implementations can involve non-public display APIs. The shipping strategy is therefore expected to use a signed and notarized direct-download application rather than assuming Mac App Store compatibility.

## First implementation milestone

A minimal native harness must:

1. Create one 1920×1080 @ 60 Hz virtual display.
2. Confirm it appears in macOS display settings.
3. Destroy it cleanly.
4. Repeat the cycle without requiring a reboot.
