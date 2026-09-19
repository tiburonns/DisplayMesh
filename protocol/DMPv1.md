# DisplayMesh Protocol v1 (DMPv1)

Status: **draft**

DMPv1 is the secure low-latency session protocol between DisplayMesh hosts and receivers.

## Design goals

1. Low-latency interactive display transport.
2. Encryption by default.
3. Independent control, input and media channels where the binding permits it.
4. Capability negotiation before a display is created.
5. Native receiver-panel negotiation.
6. USB and Wi-Fi support without mixing the physical medium with the wire protocol.
7. Fast reconnect without silently trusting a new device identity.
8. Forward-compatible codec and input capability negotiation.

## Connection bindings

A connection **medium** and a wire **protocol** are negotiated separately.

Initial bindings:

| Medium | Protocol | Discovery / reachability |
| --- | --- | --- |
| Wi-Fi / LAN | QUIC | Bonjour + IP |
| Wi-Fi / LAN | TCP | Bonjour + IP |
| Ethernet | QUIC | Bonjour + IP |
| Ethernet | TCP | Bonjour + IP |
| USB iPhone/iPad | TCP | usbmux device tunnel |

USB + QUIC is intentionally not an initial DMPv1 binding.

The iPhone/iPad receiver listens on the same logical DMP TCP port for Wi-Fi and USB. On USB, the host asks the Apple device multiplexing layer to connect to that receiver port and then treats the resulting byte stream as DMP-over-TCP.

## Session outline

```text
Discovery
   ↓
Pairing / identity verification
   ↓
Connection binding establishment
   ↓
Secure DMP session
   ↓
Capability negotiation
   ↓
Receiver panel negotiation
   ↓
Virtual display creation
   ↓
Video + cursor + input
   ↓
Telemetry / adaptation
```

## Receiver hello

A receiver must describe the panel before the host creates the virtual display.

Required fields:

- stable device/install identifier
- physical pixel width
- physical pixel height
- native scale
- orientation
- maximum refresh rate
- supported codecs
- supported connection bindings
- maximum touch contacts
- touch support
- stylus/Pencil support
- stylus hover support when available

A host may negotiate a smaller encoded stream raster than the panel's physical pixels to preserve latency/bandwidth, but the receiver's logical display geometry should remain stable unless a display reconfiguration is explicitly negotiated.

## Logical channels

| Channel | Reliability | Purpose |
| --- | --- | --- |
| control | reliable | session setup, display modes, errors |
| video | ordered media stream | encoded frames |
| pointer | low-latency | cursor position / shape |
| input | low-latency + reliable fallback | mouse, touch, keyboard, stylus |
| telemetry | low-latency | RTT, loss, queue depth, decode time, FPS, bitrate |

For a TCP binding, channels are multiplexed with explicit message type and length framing. Interactive implementations must disable Nagle and must never let video backlog block input indefinitely.

## Touch input

Touch coordinates are normalized against the receiver presentation surface:

- x: 0.0 ... 1.0
- y: 0.0 ... 1.0
- independent contact ID
- phase: began / moved / ended / cancelled
- timestamp

Optional stylus fields:

- normalized pressure
- altitude
- azimuth
- barrel roll where available
- hover/proximity where available

Receivers should forward coalesced high-frequency samples when useful, but senders may downsample if necessary to protect overall latency.

## Low-latency behavior

DMPv1 prefers freshness over perfect delivery.

- stale non-key video frames may be dropped
- video queues must be bounded
- receiver may request an immediate IDR/keyframe
- bitrate should be reduced before allowing persistent queue growth
- input/control must be prioritized ahead of queued video
- decode/render telemetry feeds adaptation

## Security

- TLS 1.3 is required for normal remote sessions.
- First pairing requires explicit user confirmation.
- A paired peer gets a persistent local identity record.
- A device identity change invalidates silent reconnect.
- No unauthenticated remote input is accepted.
- USB does not disable authentication merely because a cable is present.

## Capability negotiation

Each peer advertises the codecs, connection bindings, display presets/panel modes, input features and security features it actually supports.

The effective capability set is the intersection of both peers. DMPv1 does **not** silently replace an unsupported codec, connection binding, display mode or encryption requirement. Setup fails explicitly before creating a virtual display or media stream.

## Codec negotiation

Initial implementation:

1. H.264 hardware acceleration in low-latency / real-time mode.
2. Software/raw fallback is development-only and must not be enabled in production.

Future:

- HEVC
- AV1
- HDR metadata
- 4:4:4 / text-quality modes

## Interoperability

An optional compatibility layer may be implemented for publicly documented third-party display protocols. Compatibility code must remain separated from DMPv1 and from third-party source code.
