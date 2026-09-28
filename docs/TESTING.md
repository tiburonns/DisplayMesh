# DisplayMesh 0.2.1 — Native Acceptance Plan

[Español](TESTING.es.md) · **English**

DisplayMesh is not release-ready until both native display backends and an end-to-end media path pass on real hardware. CI can compile shared Rust code and proof harnesses, but it cannot prove private macOS display behavior, Windows driver installation, GPU encode/decode, or interactive latency.

## macOS virtual-display gate

On every supported macOS release:

1. Build `platforms/macos/harness`.
2. Create 1920×1080@60 and 2560×1440@60 virtual displays.
3. Confirm each display appears in System Settings and can be used as an extended desktop.
4. Move windows onto the display and verify stable rendering.
5. Remove the virtual display and confirm it disappears without logout/reboot.
6. Repeat create/remove at least five times.
7. Test HiDPI where supported.

Any macOS update that removes or changes the private runtime classes/selectors blocks release until compatibility is revalidated.

## Windows virtual-display gate

On a dedicated Windows test machine:

1. Install the test-signed DisplayMesh IddCx development driver.
2. Run the software-device bootstrap.
3. Confirm the adapter and virtual monitor appear without Device Manager errors.
4. Validate 1920×1080@60 and the additional modes advertised by the driver.
5. Extend the desktop onto the virtual monitor.
6. Close the bootstrap and confirm clean monitor departure.
7. Uninstall the driver and confirm no stale devices remain.

Production packages must not require Windows test-signing mode.

## Media path gate

For macOS and Windows sender/receiver combinations:

- capture the intended virtual display only
- H.264 hardware encode when available
- decode and render without unnecessary CPU frame copies in steady state
- preserve aspect ratio and color correctly
- recover cleanly from receiver disconnect/reconnect
- expose measured FPS, bitrate, RTT and dropped frames

Minimum first-usable target: stable 1080p60 over an ordinary local network.

## Session/security gate

- First pairing requires explicit confirmation and expires if it is left unanswered.
- Pairing and receiver-panel waits fail with bounded timeouts instead of hanging indefinitely.
- Every TCP connection restarts DMP sequence numbers at 1; duplicate, replayed or skipped frames are rejected.
- Receiver decode telemetry reaches the host without including pairing secrets, screen contents or input payloads.
- A changed peer identity invalidates silent reconnect.
- Unsupported codec/transport/mode fails explicitly; no silent downgrade.
- Network sessions use encrypted transport.
- Remote input is ignored before authentication/authorization.
- Pairing secrets, frames, clipboard data and keystrokes are absent from shareable logs.

## Input gate

Mouse movement, buttons, scroll and keyboard must be tested in both macOS→Windows and Windows→macOS directions before being marked complete. Touch/stylus require hardware capable of generating and receiving those events.

## Acceptance result

A DisplayMesh build can be called a usable preview only after virtual display creation, video transport and clean teardown work on at least one supported Mac and one supported Windows PC. A production release additionally requires signing/notarization/driver-signing paths appropriate to each OS.
