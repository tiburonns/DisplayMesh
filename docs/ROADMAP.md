# DisplayMesh Roadmap

## M0 — Foundation

- [x] Repository structure
- [x] Shared Rust domain model
- [x] Cross-platform control application
- [x] Session configuration validation
- [x] Deterministic peer capability intersection and session negotiation
- [x] Production-safe session defaults separated from truthful plaintext development capabilities
- [x] Separate USB/Wi-Fi medium from QUIC/TCP protocol
- [x] Reject invalid USB + QUIC binding
- [x] Shared touch capability/event model
- [x] Shared DMP framing in Rust and Swift
- [x] Binary DMP video packet contract
- [x] Adaptive quality controller with stress/recovery tests
- [x] Protocol draft
- [x] macOS / Windows backend boundaries
- [x] Managed backend lifecycle with create/capture/stop/destroy rollback tests
- [x] Product quality gates documented
- [ ] CI green on all host/receiver jobs

## M1 — Native display creation

### macOS host
- [x] Runtime-based virtual-display harness implemented
- [ ] Validate create/destroy cycle on supported Macs
- [ ] Enumerate modes
- [ ] HiDPI validation
- [ ] Extend/mirror selection
- [x] Dynamic receiver-native panel mode in the developer orchestration path
- [x] Developer orchestration path from macOS virtual display into the media receiver

### Windows host
- [x] Software-device bootstrap implemented
- [x] DisplayMesh UMDF/IddCx source + INF/project package foundation
- [x] Static 1080p60/120, 1440p60/120 and 4K60 virtual monitor modes
- [x] D3D11 IddCx swap-chain consumer foundation without CPU readback
- [x] CI contract validation for bootstrap/INF/modes/hot-path invariants
- [ ] Compile driver with a real WDK toolchain (x64 + ARM64)
- [x] Receiver-native mode request/normalization contract (including odd mobile-panel dimensions)
- [ ] Apply receiver-native mode changes to a live IddCx monitor through controlled re-arrival/hot reconfiguration
- [ ] Install/uninstall development package on Windows hardware
- [ ] Test-sign development driver

### iPhone / iPad receiver
- [x] Panel descriptor scaffold
- [x] UIKit multitouch capture scaffold
- [x] Apple Pencil pressure/altitude/azimuth capture scaffold
- [x] Bonjour/TCP listener scaffold
- [x] XcodeGen application target
- [x] Full-screen receiver UI
- [x] System / English / Español localization
- [x] Rotation-driven panel descriptor refresh
- [x] Receiver-side six-digit pairing approval UI
- [x] Receiver protocol framing/video packet tests
- [x] VideoToolbox H.264 decoder implementation
- [x] NV12 Metal presentation implementation
- [x] Bounded decode work + keyframe recovery implementation
- [ ] Validate hardware H.264 decode on iPhone/iPad
- [ ] Signed device build / TestFlight validation

## M2 — End-to-end video path

- [x] macOS ScreenCaptureKit capture (development media harness)
- [x] Windows IddCx → D3D11 desktop-surface acquisition foundation
- [x] Windows GPU BGRA → NV12 Media Foundation capability harness
- [x] Hardware H.264 MFT discovery/configuration + DXGI sample wrapping harness
- [x] Windows bounded latest-frame encode scheduler foundation
- [x] Windows asynchronous Media Foundation pump state contract (NeedInput / HaveOutput / drain)
- [x] Windows Media Foundation encoded-sample → H.264 normalize → DMP payload pipeline
- [x] Shared GPU slot generation/geometry contract for safe texture recreation
- [x] Real three-slot D3D11 shared-texture pool with NT handles, keyed mutexes and WARP lifecycle validation
- [x] Shared D3D11 NT handle → timed Media Foundation DXGI input sample adapter with geometry/format validation
- [x] Latest-frame work item carries slot/generation/timing through stale-safe shared-surface → MF sample admission
- [x] Coordinate asynchronous MFT NeedInput/HaveOutput credits with the bounded latest-frame worker
- [x] Concrete IMFTransform ProcessInput/ProcessOutput adapter with H.264 normalization → DMP payload delivery
- [x] Asynchronous Media Foundation event pump routes NeedInput/HaveOutput/DrainComplete into the bounded coordinator
- [ ] Wire the live IddCx producer and GPU BGRA→NV12 surface path into the live encoder
- [x] Windows H.264 output normalizer (Annex-B + 4-byte AVC length prefixes)
- [x] Windows H.264 Annex-B → DMP video packetizer with SPS/PPS recovery cache
- [x] macOS VideoToolbox H.264 real-time encoder (development media harness)
- [x] Windows Media Foundation H.264 hardware encoder adapter/event-pump path
- [ ] Validate the Media Foundation H.264 path on target Windows GPUs
- [x] iPhone/iPad VideoToolbox H.264 receive implementation
- [x] iPhone/iPad Metal NV12 renderer implementation
- [x] Receiver bounded-latency policy
- [x] Receiver keyframe recovery
- [x] macOS host emits DMP H.264 packets with recovery keyframes
- [ ] End-to-end local loopback test
- [x] Scripted macOS virtual-display → ScreenCaptureKit → H.264 → Apple receiver path
- [ ] 1080p60 hardware acceptance
- [ ] 1440p60 hardware acceptance

## M3 — USB + network sessions

- [x] macOS host Bonjour discovery for the Apple receiver with explicit multi-receiver ambiguity failure
- [ ] Product-wide Bonjour discovery over Wi-Fi/LAN (Windows host still pending)
- [ ] QUIC + TLS 1.3 for Wi-Fi/LAN
- [x] Post-pairing frame protection policy/codec
- [x] Authenticated encrypted DMP-over-TCP binding for Apple↔macOS (ECDH/HKDF/ChaChaPoly)
- [ ] TCP + TLS binding (optional/alternative reviewed binding)
- [ ] macOS usbmux host transport
- [ ] Windows usbmux-compatible host transport
- [ ] USB device discovery
- [x] Signed macOS development host pairing request + Keychain identity persistence
- [x] Apple receiver ↔ macOS development pairing handshake
- [x] Adaptive bitrate/raster decision engine with 100/85/75/67% hysteresis
- [x] Wire receiver decode/drop telemetry into the macOS development adaptive controller
- [x] Apply adaptive bitrate to the macOS VideoToolbox development encoder
- [x] Apply adaptive stream raster to ScreenCaptureKit + VideoToolbox on the macOS development path
- [ ] Reconnect / seamless Wi-Fi ↔ USB handoff
- [x] Windows receiver-driven adaptive bitrate/raster controller with the same 100/85/75/67% hysteresis policy as macOS
- [ ] Wire authenticated Windows receiver telemetry into the adaptive controller and live MFT/raster pipeline

## M4 — Touch and input

- [x] Normalized multitouch data model
- [x] iOS/iPadOS coalesced touch capture
- [x] One-finger pointer/click/drag on macOS development path
- [x] Two-finger scroll on macOS development path
- [x] Windows native multi-contact touch injection bridge
- [x] Windows host DMP phase/admission gate for authenticated-session routing
- [x] Windows session-gated DMP input decode/router contract
- [ ] Wire validated Windows pairing/network transport into the live touch injector
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
- [x] Apple receiver English / Español / System
- [x] Apple receiver localization parity validation
- [x] Explicit receiver-side pairing confirmation
- [x] Development security state shown truthfully in UI
- [x] Apple receiver reproducible project generation
- [x] Receiver FPS / bitrate / decode / dropped-frame diagnostics
- [x] Receiver decode telemetry returned to the macOS development host
- [x] Per-connection DMP sequence/replay guard
- [x] Pairing and panel negotiation timeouts in the macOS development path
- [x] Bounded macOS transport connect deadline + fail-closed malformed control frames
- [x] Per-message DMP payload budgets and exact-size interactive frames
- [x] Receiver authorization-phase admission gate
- [x] Bounded malformed pairing attempts + challenge-bound response
- [x] Generic Bonjour receiver identity (no configured device-name leak)
- [x] Windows native DMP framing/sequence contract
- [ ] Apple receiver CI build confirmed green
- [x] First-run Local Network permission education before Bonjour/listener startup
- [ ] Production transport security review / TLS 1.3 or equivalent binding
- [x] Fail-closed encrypted DMP frame codec and encrypted-wire payload validation
- [x] Signed ephemeral P-256 key exchange wired into macOS ↔ Apple sessions
- [x] Mutual persistent peer identity for the Apple↔macOS binding
- [x] End-to-end encrypted RTT probes + receiver decode/presentation queue-depth telemetry
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
