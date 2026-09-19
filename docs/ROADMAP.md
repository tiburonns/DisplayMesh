# DisplayMesh Roadmap

## M0 — Foundation

- [x] Repository structure
- [x] Shared Rust domain model
- [x] Cross-platform control application
- [x] Session configuration validation
- [x] Deterministic peer capability intersection and session negotiation
- [x] Protocol draft
- [x] macOS / Windows backend boundaries
- [ ] CI green on macOS and Windows

## M1 — Native display creation

### macOS
- [x] Runtime-based virtual-display harness implemented
- [ ] Validate create/destroy cycle on supported Macs
- [ ] Enumerate modes
- [ ] HiDPI validation
- [ ] Extend/mirror selection

### Windows
- [x] Software-device bootstrap implemented
- [ ] Build DisplayMesh IddCx driver
- [ ] Add virtual monitor modes
- [ ] Install/uninstall development package
- [ ] Test-sign development driver

## M2 — Local video path

- [ ] macOS ScreenCaptureKit capture
- [ ] Windows DXGI capture
- [ ] macOS VideoToolbox H.264
- [ ] Windows Media Foundation H.264
- [ ] Metal receiver
- [ ] D3D11 receiver
- [ ] End-to-end local loopback test

## M3 — Network sessions

- [ ] mDNS discovery
- [ ] Pairing
- [ ] QUIC + TLS 1.3
- [ ] Capability negotiation
- [ ] Adaptive bitrate
- [ ] Reconnect

## M4 — Input

- [ ] Mouse
- [ ] Keyboard
- [ ] Scroll
- [ ] Touch
- [ ] Stylus
- [ ] Clipboard

## M5 — Product quality

- [ ] English
- [ ] Español
- [ ] System language
- [ ] First-run permissions
- [ ] Diagnostics
- [ ] Automatic updates
- [ ] macOS signing/notarization
- [ ] Windows app signing
- [ ] Windows driver production signing

## M6 — Advanced

- [ ] 120 Hz
- [ ] HEVC
- [ ] AV1
- [ ] HDR
- [ ] Audio
- [ ] Multi-display sessions
- [ ] Optional third-party protocol compatibility
