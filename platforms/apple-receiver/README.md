# DisplayMesh Apple Receiver (iPhone / iPad)

This target turns an iPhone or iPad into an interactive external display for a DisplayMesh host.

## Product requirements

The receiver is not a simple screen mirror. It must support:

- true extended desktop sessions
- USB and Wi-Fi connectivity
- native Retina panel resolution
- portrait and landscape orientation
- low-latency H.264 hardware decode
- multitouch input
- Apple Pencil pressure, altitude and azimuth when available
- scroll gestures
- automatic panel capability reporting
- challenge-bound signed pairing with persistent host identity
- automatic reconnect

## Connection model

The receiver listens on one DMP TCP endpoint.

### Wi-Fi

The receiver advertises `_displaymesh._tcp` through Bonjour. The host discovers it and connects over the LAN.

DMP may later prefer QUIC for Wi-Fi sessions, but TCP remains available for compatibility and debugging.

### USB

The iOS/iPadOS app still listens on the same TCP port. The macOS or Windows host reaches that port through Apple's usbmux device multiplexing path.

That gives DisplayMesh one application protocol while keeping USB and Wi-Fi as separate connection bindings.

Initial bindings:

| Medium | Wire protocol |
| --- | --- |
| Wi-Fi / LAN | QUIC or TCP |
| Ethernet | QUIC or TCP |
| USB to iPhone/iPad | TCP through usbmux |

The Windows host will need a bundled or independently implemented usbmux-compatible transport layer. The receiver does not depend on ExternalAccessory/MFi because the computer is the USB host and the iPhone/iPad application exposes a tunneled TCP endpoint.

## Display negotiation

The receiver reports:

- physical pixel width/height
- native scale
- current orientation
- maximum screen refresh rate
- touch capability
- Pencil capability

The host should prefer a virtual display matching the receiver panel rather than forcing a generic 1080p or 1440p mode.

For very high-resolution panels, DisplayMesh may negotiate a lower stream raster while preserving the virtual desktop's logical HiDPI geometry.

## Touch behavior

The receiver captures raw UIKit touch events in normalized display coordinates.

Windows target behavior:

- inject touch as real system touch input when permitted
- preserve multiple simultaneous contacts
- map Pencil to pen/stylus input where supported

macOS target behavior:

- first release: map one-finger touch to pointer/click/drag
- two-finger pan to scroll
- preserve higher-fidelity Pencil fields in DMP for future/native integrations

## Low-latency policy

- hardware decode only in normal operation
- discard stale frames rather than building latency
- request a keyframe immediately after decoder loss
- prioritize input/control packets over video backlog
- disable Nagle for TCP interactive sessions
- adapt bitrate before allowing large queues
- target 60 FPS first, then 120 FPS on supported iPad Pro hardware


## Current security boundary

The 0.2.2 development receiver verifies a P-256 signature from the macOS host against a fresh per-connection challenge and remembers accepted host public keys. This authenticates the host identity during pairing, but the current media/control transport remains plaintext TCP. Production still requires encrypted authenticated transport and receiver identity authentication.

## TestFlight preflight

See [TESTFLIGHT.md](TESTFLIGHT.md) for the internal receiver acceptance path.
