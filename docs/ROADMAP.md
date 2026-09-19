# DisplayMesh Roadmap

## M0 — Foundation

- [x] Repository structure
- [x] Shared Rust domain model
- [x] Cross-platform control application
- [x] Session configuration validation
- [x] Deterministic peer capability intersection and session negotiation
- [x] Separate USB/Wi-Fi medium from QUIC/TCP protocol
- [x] Reject invalid USB + QUIC binding
- [x] Shared touch capability/event model
- [x] Protocol draft
- [x] macOS / Windows backend boundaries
- [x] Apple receiver source scaffold
- [ ] CI green on macOS and Windows after current transport refactor

## M1 — Native display creation

### macOS host
- [x] Runtime-based virtual-display harness implemented
- [ ] Validate create/destroy cycle on supported Macs
- [ ] Enumerate modes
- [ ] HiDPI validation
- [ ] Extend/mirror selection
- [ ] Dynamic receiver-native panel mode

### Windows host
- [x] Software-device bootstrap implemented
- [ ] Build DisplayMesh IddCx driver
- [ ] Add virtual monitor modes
- [ ] Dynamic receiver-native panel mode
- [ ] Install/uninstall development package
- [ ] Test-sign development driver

### iPhone / iPad receiver
- [x] Panel descriptor scaffold
- [x] UIKit multitouch capture scaffold
- [x] Apple Pencil pressure/altitude/azimuth capture scaffold
- [x] Bonjour/TCP listener scaffold
- [ ] Xcode application target
- [ ] Full-screen receiver UI
- [ ] Rotation-driven panel renegotiation

## M2 — Video path

- [ ] macOS ScreenCaptureKit capture
- [ ] Windows DirectX / IddCx frame path
- [ ] macOS VideoToolbox H.264 real-time encoder
- [ ] Windows Media Foundation H.264 hardware encoder
- [ ] iPhone/iPad hardware H.264 decode
- [ ] Metal / AVSampleBufferDisplayLayer receiver presentation
- [ ] Frame dropping / bounded latency queue
- [ ] Keyframe recovery
- [ ] End-to-end local loopback test

## M3 — USB + network sessions

- [ ] Bonjour discovery over Wi-Fi/LAN
- [ ] QUIC + TLS 1.3 for Wi-Fi/LAN
- [ ] TCP + TLS binding
- [ ] macOS usbmux host transport
- [ ] Windows usbmux-compatible host transport
- [ ] USB device discovery
- [ ] Pairing
- [ ] Adaptive bitrate
- [ ] Adaptive stream raster
- [ ] Reconnect / seamless Wi-Fi ↔ USB handoff

## M4 — Touch and input

- [x] Normalized multitouch data model
- [ ] iOS/iPadOS coalesced touch transport
- [ ] One-finger pointer/click/drag on macOS
- [ ] Two-finger scroll on macOS
- [ ] Windows real touch injection where deployment permits
- [ ] Windows pointer fallback
- [ ] Apple Pencil pen mapping
- [ ] Pencil hover
- [ ] Keyboard input
- [ ] Clipboard

## M5 — Product quality

- [x] Control UI in English
- [x] Control UI in Español
- [x] Control UI follows system language
- [x] Persist explicit language preference
- [ ] Apple receiver English/Español/System
- [ ] First-run permissions
- [ ] Diagnostics
- [ ] Latency/FPS/bitrate overlay
- [ ] Automatic updates
- [ ] macOS signing/notarization
- [ ] Windows app signing
- [ ] Windows driver production signing
- [ ] iOS/iPadOS signing and TestFlight build

## M6 — Advanced

- [ ] 120 Hz end-to-end
- [ ] 4K60
- [ ] HEVC
- [ ] AV1
- [ ] HDR
- [ ] Audio
- [ ] Multi-display sessions
- [ ] Optional third-party protocol compatibility
