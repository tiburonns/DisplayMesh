# DisplayMesh Architecture

## Principle

DisplayMesh uses a shared product layer and native media/display layers.

Trying to implement the virtual monitor itself in a cross-platform UI framework would make the project less reliable. macOS and Windows expose fundamentally different display-extension mechanisms.

## Shared layer

The Rust workspace owns:

- session state
- device model
- capability negotiation
- settings
- protocol model
- product UI
- transport orchestration

It must not directly depend on private macOS declarations or Windows Driver Kit headers.

## macOS backend

Target pipeline:

```text
Virtual display
    ↓
ScreenCaptureKit
    ↓
CVPixelBuffer / IOSurface
    ↓
VideoToolbox encoder
    ↓
DMP transport

DMP transport
    ↓
VideoToolbox decoder
    ↓
Metal renderer
```

The virtual-display implementation is isolated because the practical mechanism may depend on APIs that are not App-Store-safe.

## Windows backend

Target pipeline:

```text
IddCx indirect display driver
    ↓
DXGI / D3D11 capture
    ↓
Media Foundation hardware encoder
    ↓
DMP transport

DMP transport
    ↓
Media Foundation hardware decoder
    ↓
D3D11 renderer
```

The IddCx driver is a separate package and has its own signing/deployment lifecycle.

## Boundaries

A native backend will expose a small interface to the shared application:

- enumerate physical displays
- create virtual display
- destroy virtual display
- start capture
- stop capture
- encode/decode capabilities
- inject pointer
- inject keyboard
- inject touch/stylus where supported
- report telemetry

## Performance targets

First usable target:

- 1080p60 on ordinary LAN
- 1440p60 on modern hardware
- interactive pointer latency
- zero unnecessary CPU-side frame copies in steady state

Later target:

- 1440p120
- 4K60
- multiple simultaneous virtual displays
- HDR
