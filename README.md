# DisplayMesh

DisplayMesh is a cross-platform virtual-display project for **macOS and Windows hosts**, with **iPhone and iPad receivers**.

The goal is to let a computer create a real extended display and stream it to another computer or Apple mobile device over **USB or Wi-Fi**, while preserving low latency, high resolution and interactive touch input.

> **Current `main`: 0.2.1.** The Apple receiver includes the real low-latency H.264 receive path (DMP video packet → Annex-B parser → VideoToolbox → NV12 → Metal), bounded decoder work, keyframe recovery, live diagnostics and EN/ES/System UI. The current development path also enforces per-connection DMP sequencing, expires stalled pairing/panel waits, and returns bounded receiver decode telemetry to the macOS host. Host-side production integration, encrypted transport and end-to-end hardware validation remain release blockers.

## Product requirements

- True extended display or mirror mode
- macOS ↔ Windows, macOS ↔ macOS, Windows ↔ Windows
- iPhone and iPad as external touch displays
- USB and Wi-Fi as first-class connection modes
- Native Retina-aware panel negotiation
- Hardware-accelerated H.264 low-latency baseline
- HEVC / AV1 later where hardware support makes sense
- 1080p60 and 1440p60 first; 4K60 and 120 Hz only after hardware validation
- Multitouch, scroll and Apple Pencil metadata
- Mouse and keyboard input where applicable
- Adaptive bitrate and encoded raster without changing logical desktop geometry
- Pairing and encrypted sessions
- English, Spanish and system-language UI

## Latency strategy

DisplayMesh optimizes for interaction freshness instead of media-player behavior.

- no deliberate playback buffer
- bounded decoder work
- realtime VideoToolbox decode on Apple receivers
- Metal presentation from NV12 surfaces
- keyframe request after decode loss or backlog reset
- input/control priority over queued video
- adaptive controller reduces bitrate before reducing encoded raster
- persistent congestion may step stream raster from 100% → 85% → 75% → 67%
- recovery restores resolution before aggressively increasing bitrate

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
    │       ├── DMP framing + video packet contract
    │       ├── adaptive quality controller
    │       ├── touch model
    │       └── backend lifecycle
    │
    ├── macOS host backend
    │       ├── virtual display
    │       ├── ScreenCaptureKit
    │       └── VideoToolbox encoder
    │
    ├── Windows host backend
    │       ├── IddCx virtual display driver
    │       ├── DirectX / D3D11
    │       └── Media Foundation encoder
    │
    └── Apple receiver
            ├── Network.framework listener
            ├── VideoToolbox H.264 decoder
            ├── Metal NV12 renderer
            └── UIKit touch / Pencil capture
```

See [ARCHITECTURE.md](docs/ARCHITECTURE.md), [ROADMAP.md](docs/ROADMAP.md), [DMPv1.md](protocol/DMPv1.md), [QUALITY_GATES.md](docs/QUALITY_GATES.md), and the [native acceptance plan](docs/TESTING.md).

## Build the shared control app

Install the stable Rust toolchain and run:

```bash
cargo run -p displaymesh-control
```

## Generate the iPhone/iPad receiver project

Install XcodeGen, then run:

```bash
cd platforms/apple-receiver
xcodegen generate
open DisplayMeshReceiver.xcodeproj
```

## Languages

- English: this file
- Español: [README.es.md](README.es.md)

## Repository policy

DisplayMesh is an independent implementation. Do not copy OpenDisplay branding, artwork, or source code into this repository. Interoperability work should be based on public protocol/API documentation and clean implementation boundaries.


## macOS developer end-to-end path

A developer orchestration script now joins the virtual-display proof harness with the ScreenCaptureKit/VideoToolbox media harness:

```bash
scripts/run-macos-virtual-session.sh --host <iphone-or-ipad-ip>
```

It creates a temporary DisplayMesh virtual display, captures that exact display, encodes low-latency H.264, streams it to the Apple receiver, and tears the virtual display down on exit. This is a development integration path only: transport is still plaintext TCP and production host integration/TLS remain release blockers.
