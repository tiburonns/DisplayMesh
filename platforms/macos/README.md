# macOS native backend

This directory contains the native macOS display/capture/encode/render work.

## Responsibilities

- virtual display lifecycle
- display mode / HiDPI configuration
- ScreenCaptureKit capture
- VideoToolbox encode/decode
- Metal rendering
- macOS input injection
- permission/status reporting

## Virtual-display harness

A standalone runtime-based proof harness lives in `harness/`. It intentionally resolves the virtual-display classes at runtime instead of statically linking private declarations into the shared Rust app.

Build:

```bash
make -C platforms/macos/harness
```

Run with the default 1920×1080 @ 60 Hz mode:

```bash
./platforms/macos/harness/displaymesh-virtual-display
```

Or request a mode explicitly:

```bash
./platforms/macos/harness/displaymesh-virtual-display 2560 1440 60 0
```

The last argument controls HiDPI (0/1).

The harness verifies that the required runtime classes/selectors exist before creating anything. Press Ctrl+C to release the display.

## Important constraint

The virtual-display mechanism relies on a non-public macOS display interface. It must be treated as an isolated compatibility layer and validated on every macOS release we support. This also means the shipping plan should assume direct signed/notarized distribution rather than Mac App Store acceptance.

## Validation checklist

1. Build the harness.
2. Create one 1920×1080 @ 60 Hz display.
3. Confirm it appears in System Settings → Displays.
4. Move a window onto it.
5. Press Ctrl+C.
6. Confirm the display disappears cleanly.
7. Repeat the cycle several times without rebooting.
