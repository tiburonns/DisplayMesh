# DisplayMesh

DisplayMesh is a cross-platform virtual-display project for **macOS and Windows hosts**, with **iPhone and iPad receivers**.

The goal is to let a computer create a real extended display and stream it to another computer or Apple mobile device over **USB or Wi-Fi**, while preserving low latency, high resolution and interactive touch input.

> **Current `main`: 0.1.3.** Status: early development. The shared control app models USB/Wi-Fi separately from QUIC/TCP, validates capability-compatible configurations, and supports System/English/Español UI. Native display integration, Apple receiver packaging and end-to-end video transport remain active milestones.

## Product requirements

- True extended display or mirror mode
- macOS ↔ Windows, macOS ↔ macOS, Windows ↔ Windows
- iPhone and iPad as external touch displays
- USB and Wi-Fi as first-class connection modes
- Native Retina-aware panel negotiation
- Hardware-accelerated H.264 low-latency baseline
- HEVC / AV1 later where hardware support makes sense
- 1080p60 and 1440p60 first; 4K60 and 120 Hz targets later
- Multitouch, scroll and Apple Pencil metadata
- Mouse and keyboard input where applicable
- Adaptive bitrate, frame rate and stream raster
- Pairing and encrypted sessions
- English, Spanish and system-language UI

## Connection bindings

DisplayMesh keeps the physical connection separate from the wire protocol:

| Connection | Initial wire protocol |
| --- | --- |
| Wi-Fi / LAN | QUIC or TCP |
| Ethernet | QUIC or TCP |
| USB to iPhone/iPad | TCP through usbmux |

This lets the product use USB as a true low-jitter path without pretending that USB and QUIC/TCP are the same layer.

## Architecture

```text
apps/control
    │
    ├── displaymesh-core
    │       ├── device/session model
    │       ├── capability negotiation
    │       ├── touch model
    │       └── connection binding model
    │
    ├── macOS host backend
    │       ├── virtual display
    │       ├── ScreenCaptureKit
    │       └── VideoToolbox
    │
    ├── Windows host backend
    │       ├── IddCx virtual display driver
    │       ├── DXGI / D3D11
    │       └── Media Foundation
    │
    └── Apple receiver
            ├── Network.framework listener
            ├── VideoToolbox / AVFoundation decode
            ├── Metal presentation
            └── UIKit touch / Pencil capture
```

See [ARCHITECTURE.md](docs/ARCHITECTURE.md), [ROADMAP.md](docs/ROADMAP.md), [DMPv1.md](protocol/DMPv1.md), the [Apple receiver notes](platforms/apple-receiver/README.md), and the [native acceptance plan](docs/TESTING.md).

For 32-bit devices that stop at iOS 9, the repository also contains a separate Objective-C/UIKit compatibility receiver in [`platforms/apple-receiver-legacy`](platforms/apple-receiver-legacy/README.md). Its explicitly negotiated `legacy-ios9-jpeg` profile is documented in [`docs/LEGACY_IOS9.md`](docs/LEGACY_IOS9.md); it is an unencrypted trusted-USB/LAN fallback, not a silent downgrade of normal DMPv1.

## Build the shared control app

Install the stable Rust toolchain and run:

```bash
cargo run -p displaymesh-control
```

The control application builds on both macOS and Windows. Native virtual-display backends are intentionally isolated from the shared UI so each platform can use the correct system APIs and driver model.

## Languages

- English: this file
- Español: [README.es.md](README.es.md)

## Repository policy

DisplayMesh is an independent implementation. Do not copy OpenDisplay branding, artwork, or source code into this repository. Interoperability work should be based on public protocol/API documentation and clean implementation boundaries.
