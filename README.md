# DisplayMesh

DisplayMesh is a cross-platform virtual-display project for **macOS and Windows**.

The goal is to let one computer act as a real secondary display for another computer over a local network, while keeping the UI and session model shared and the display backends native to each operating system.

> **Current `main`: 0.1.1.** Status: early development. The shared control app, capability negotiation, protocol draft, and native proof harnesses are in place. Native virtual-display integration and video transport remain active implementation milestones.

## Planned capabilities

- Extend or mirror a desktop
- macOS ↔ Windows, macOS ↔ macOS, Windows ↔ Windows
- Hardware-accelerated H.264 first; HEVC/AV1 later
- LAN/Wi-Fi and wired transports
- HiDPI / Retina-aware resolutions
- Mouse, keyboard, scroll and touch input
- Adaptive bitrate, frame rate and resolution
- Pairing and encrypted sessions
- English, Spanish and system-language UI

## Architecture

```text
apps/control
    │
    ├── displaymesh-core
    │       ├── device/session model
    │       ├── capability negotiation
    │       └── backend abstraction
    │
    ├── macOS native backend
    │       ├── virtual display
    │       ├── ScreenCaptureKit
    │       ├── VideoToolbox
    │       └── Metal
    │
    └── Windows native backend
            ├── IddCx virtual display driver
            ├── DXGI / D3D11
            ├── Media Foundation
            └── DirectComposition / D3D11
```

See [ARCHITECTURE.md](docs/ARCHITECTURE.md), [ROADMAP.md](docs/ROADMAP.md), [DMPv1.md](protocol/DMPv1.md), and the [native acceptance plan](docs/TESTING.md).

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
