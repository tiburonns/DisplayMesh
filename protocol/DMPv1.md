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

### Framing admission limits

Receivers and hosts reject an invalid payload length from the **16-byte DMP header before waiting for the body**. The global frame ceiling remains 16 MiB for video, but control traffic has substantially smaller budgets:

| Message | Payload budget |
| --- | ---: |
| hello | 4 KiB |
| capabilities | 64 KiB |
| panel descriptor | 16 KiB |
| pairing | 16 KiB |
| video | 16 MiB |
| input | exactly 40 bytes |
| telemetry | 16 KiB |
| keyframe request | exactly 0 bytes |
| error | 8 KiB |

These are protocol safety limits, not targets. Implementations should normally send much smaller control payloads.

Before receiver authorization, the current host-to-Apple-receiver development direction permits only a signed `pairing` request. The current Apple receiver then advertises its implemented capabilities to the macOS development host, followed by its panel descriptor. Only after those phases complete does streaming admit input/telemetry/keyframe traffic in the receiver→host direction and video in the host→receiver direction. This is **receiver capability admission**, not yet full bilateral capability negotiation. Frames in the wrong direction or phase are treated as protocol violations rather than silently ignored.

DMP frame sequence numbers are scoped to one transport connection. Each direction starts at sequence **1**, increments by one for every transmitted DMP frame, and wraps as an unsigned 32-bit counter. Because TCP is reliable and ordered, a duplicate, replayed or skipped sequence is a protocol error and the connection is closed rather than silently resynchronized.

## Video payload

A DMP frame with message type `video` carries a binary DMP video packet.

The fixed header is 16 bytes:

| Offset | Size | Field |
| ---: | ---: | --- |
| 0 | 1 | codec: 1 H.264, 2 HEVC, 3 AV1 |
| 1 | 1 | flags; bit 0 means keyframe |
| 2 | 2 | reserved, currently zero |
| 4 | 8 | presentation timestamp in microseconds, big endian |
| 12 | 4 | frame duration in microseconds, big endian |
| 16 | variable | encoded access unit |

H.264 access units use Annex-B NAL framing. A keyframe access unit should carry current SPS/PPS parameter sets together with the IDR so a receiver can join or recover without waiting for unrelated configuration messages.

The receiver converts Annex-B NAL units to the native decoder representation internally. This keeps DMP portable across VideoToolbox, Media Foundation and other decoder APIs.

### H.264 low-delay requirements

The production H.264 encoder should:

- use hardware acceleration when available,
- run in realtime mode,
- avoid B-frame reordering,
- minimize encoder frame delay,
- emit IDR frames on receiver request,
- repeat SPS/PPS on recovery keyframes,
- favor a bounded latency budget over perfect delivery.

## Touch input

DMP input frames use a fixed 40-byte binary sample instead of JSON in the interactive path.

| Offset | Size | Field |
| ---: | ---: | --- |
| 0 | 1 | input version, currently 1 |
| 1 | 1 | kind: 1 touch, 2 pencil |
| 2 | 1 | phase: 1 began, 2 moved, 3 ended, 4 cancelled, 5 hover |
| 3 | 1 | flags, reserved for compatible extensions |
| 4 | 4 | contact ID, big endian |
| 8 | 4 | normalized X, IEEE-754 float32, big endian |
| 12 | 4 | normalized Y, IEEE-754 float32, big endian |
| 16 | 4 | normalized pressure, float32 |
| 20 | 4 | altitude, radians, float32 |
| 24 | 4 | azimuth, radians, float32 |
| 28 | 4 | barrel roll, radians, float32; zero when unavailable |
| 32 | 8 | receiver input timestamp in microseconds, big endian |

Coordinates and pressure are validated before transmission and again before injection. The input flags byte is reserved in DMPv1 and must be zero; nonzero values are rejected until a later protocol revision defines them.

The fixed layout keeps the high-rate path predictable for coalesced touch and Pencil input and lets native host backends decode a sample without a JSON parser or heap-heavy object model.

Windows keeps all active contacts in each injected frame. A final location change is emitted as an UPDATE before UP because the Win32 touch injection API requires the UP coordinate to match the preceding update. Pencil currently falls back to the touch path until the dedicated pen injector is integrated.

Receivers should forward coalesced high-frequency samples when useful, but may downsample when the input rate would otherwise compete with control/video latency.

## Low-latency behavior

DMPv1 prefers freshness over perfect delivery.

- receiver decode queues must be bounded
- a receiver that loses decode synchronization requests an immediate IDR/keyframe
- bitrate is reduced before persistent queue growth is allowed
- stream raster may step down while logical desktop geometry stays stable
- input/control is prioritized ahead of queued video
- stale media work is discarded rather than adding interaction latency
- decode/render telemetry feeds adaptation
- an authorized receiver reports decode FPS, bitrate, decode time, dropped-frame count, hardware-decoder state and the last observed video sequence to the host at a bounded cadence

DisplayMesh's adaptive controller treats bitrate as the first quality lever. Persistent congestion may then step the encoded stream raster through 100%, 85%, 75% and 67%. Resolution recovery happens before aggressive bitrate upshifts and requires a recovery keyframe.

## Development identity handshake

The current Apple/macOS development binding starts with a receiver-generated 32-byte random challenge. The host keeps a stable UUID and P-256 signing key in Keychain and signs a canonical pairing payload containing the protocol version, peer ID/name, six-digit verification code, challenge and public key. The receiver verifies the signature and challenge before showing the approval UI. A known peer ID arriving with a different public key is rejected until trust is explicitly cleared.

The receiver pairing response echoes the active receiver challenge, and the host rejects stale or out-of-phase responses. This authenticates the development **host identity only** and binds the transaction against accidental/stale replay. It does not replace the TLS 1.3 requirement or authenticate the receiver to the host.

## Security

- TLS 1.3 is required for normal remote sessions.
- A connected development peer must present a valid signed pairing request within 10 seconds or the receiver closes the connection.
- First pairing requires explicit user confirmation; once a valid request is shown, the approval window expires after 30 seconds instead of remaining pending indefinitely.
- Pairing rejection/expiry closes that transport connection so a retry starts with a fresh challenge and sequence space.
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
