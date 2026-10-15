# DisplayMesh Architecture

## Principle

DisplayMesh uses a shared product/protocol layer and native display/media layers.

The product has two primary roles:

1. **Host** — macOS or Windows creates a real virtual display, captures it and encodes it.
2. **Receiver** — macOS, Windows, iPhone or iPad decodes and presents the display and may send input back.

## Shared layer

The Rust workspace owns:

- session state
- device model
- capability negotiation
- settings
- protocol model
- touch/input model
- connection binding model
- product UI
- transport orchestration

It must not directly depend on private macOS declarations, UIKit or Windows Driver Kit headers.

## Connection model

Connection medium and wire protocol are separate concepts.

Initial valid bindings:

| Medium | Protocol |
| --- | --- |
| Wi-Fi / LAN | QUIC or TCP |
| Ethernet | QUIC or TCP |
| USB to iPhone/iPad | TCP through usbmux |

USB to Apple mobile devices uses the same application-level receiver endpoint as Wi-Fi. On USB, the host reaches that TCP port through the Apple device multiplexing path.

This allows one DMP session layer while preserving transport-specific discovery and latency behavior.

## macOS host backend

Target pipeline:

```text
Virtual display
    ↓
ScreenCaptureKit
    ↓
CVPixelBuffer / IOSurface
    ↓
VideoToolbox H.264 real-time encoder
    ↓
DMP transport
```

The virtual-display implementation is isolated because the practical mechanism may depend on APIs that are not App-Store-safe.

Input returned from an iPhone/iPad initially maps touch gestures to pointer/drag/scroll. DMP still preserves multitouch and Pencil metadata so richer mappings remain possible.

## Windows host backend

Target pipeline:

```text
IddCx indirect display driver
    ↓
DirectX swap chain / D3D11
    ↓
Media Foundation hardware encoder
    ↓
DMP transport
```

The IddCx driver is a separate package and has its own signing/deployment lifecycle.

For touch input, Windows is the preferred target for true multi-contact system injection when the required system capability/deployment model is available. Pointer fallback remains required.

## iPhone / iPad receiver

Target pipeline:

```text
Wi-Fi Bonjour or USB usbmux tunnel
    ↓
DMP session
    ↓
H.264 hardware decoder
    ↓
Metal / AVSampleBufferDisplayLayer presentation
    ↓
UIKit multitouch + Apple Pencil capture
    ↓
DMP input return channel
```

The receiver announces:

- physical pixel dimensions
- native scale
- orientation
- maximum refresh rate
- touch capabilities
- Pencil capabilities

The host should use this data to build a virtual display that matches the receiving panel instead of assuming a generic 1080p/1440p mode.

## Low-latency rules

DisplayMesh optimizes for interaction latency rather than perfect frame delivery:

- hardware encode/decode in steady state
- no avoidable CPU readback of GPU frames
- bounded video queue
- drop stale non-key frames before accumulating latency
- immediate keyframe request after decoder loss
- input/control priority over video backlog
- `TCP_NODELAY` for interactive TCP sessions
- bitrate reduction before queue growth
- receiver decode feedback can lower/recover the macOS development encoder bitrate with hysteresis
- adaptive stream raster when the network cannot sustain native panel pixels

## Resolution / refresh targets

Initial usable target:

- 1080p60
- 1440p60
- native Retina logical geometry
- interactive touch latency

Advanced target:

- 4K60
- 1440p120 / native 120 Hz receiver modes
- HDR
- multiple simultaneous receivers

High refresh rate is negotiated end-to-end: virtual display, capture, encoder, transport, decoder and receiving panel must all support the requested refresh rate.

## Native backend boundary

A host backend exposes:

- enumerate displays
- create/destroy virtual display
- start/stop capture
- encode capability reporting
- inject pointer/keyboard/touch/stylus where supported
- telemetry

The shared core wraps host backends in a managed lifecycle. Session startup is ordered as virtual-display creation followed by capture. If capture startup fails, the core immediately attempts to destroy the newly created display. Session shutdown stops capture before destroying the display and is idempotent when already idle. Cleanup failures remain visible as a failed lifecycle state rather than being reported as success.

The current TCP development path also treats transport connection lifetime as a protocol boundary: frame sequences restart at 1 in each direction, gaps/replays close the connection, pairing/panel waits are bounded, and receiver decode telemetry is returned to the host for future adaptation work. DMP header parsing applies per-message payload budgets before buffering a body, reserved input flags are rejected, and the Apple receiver disconnects frames that arrive in an invalid authorization phase. Malformed pairing is capped per connection instead of allowing an unbounded approval/challenge loop.

A receiver backend exposes:

- report panel capabilities
- accept video/control connection
- decode/present frames
- capture touch/stylus
- report decode/display telemetry


## Transport handoff policy

The shared core now owns a deterministic handoff policy, while platform code remains responsible for discovery and the actual socket/usbmux switch.

A candidate transport may replace the active one only when it is ready, authenticated, and proves the **same peer identity**. USB presence is never treated as trust. The initial USB binding remains TCP-only, and a healthy higher-preference transport is not replaced by a lower-preference path. Each accepted switch increments a transport generation so platform callbacks from the previous binding can be discarded as stale.

Current preference order is USB → Ethernet → Wi-Fi. A degraded/unhealthy active path may fail over to a lower-preference authenticated path. This policy does **not** claim that usbmux discovery or live handoff is already implemented.
