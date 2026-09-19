# DisplayMesh Protocol v1 (DMPv1)

Status: **draft**

DMPv1 is the planned secure session protocol between DisplayMesh peers.

## Design goals

1. Low-latency interactive display transport.
2. Encryption by default.
3. Independent control, input and media channels.
4. Capability negotiation before a display is created.
5. Fast reconnect without silently trusting a new device identity.
6. Forward-compatible codec and input capability negotiation.

## Session outline

```text
Discovery
   ↓
Pairing / identity verification
   ↓
TLS 1.3 / QUIC session
   ↓
Capability negotiation
   ↓
Display negotiation
   ↓
Virtual display creation
   ↓
Video + cursor + input streams
   ↓
Telemetry / adaptation
```

## Logical channels

| Channel | Reliability | Purpose |
| --- | --- | --- |
| control | reliable | session setup, display modes, errors |
| video | ordered media stream | encoded frames |
| pointer | low-latency | cursor position / shape |
| input | low-latency + reliable fallback | mouse, touch, keyboard, stylus |
| telemetry | low-latency | RTT, loss, decode time, FPS, bitrate |

## Security

- TLS 1.3 is required for remote sessions.
- First pairing must require an explicit user confirmation.
- A paired peer gets a persistent local identity record.
- A device identity change invalidates silent reconnect.
- No unauthenticated remote input is accepted.

## Codec negotiation

Initial implementation:

1. H.264 hardware acceleration when available.
2. Raw fallback is development-only and must not be enabled in production.

Future:

- HEVC
- AV1
- HDR metadata
- 4:4:4 / high-quality text modes

## Interoperability

An optional compatibility layer may be implemented for publicly documented third-party display protocols. Compatibility code must remain separated from DMPv1 and from third-party source code.
