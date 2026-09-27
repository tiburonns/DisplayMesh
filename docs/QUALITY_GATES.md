# DisplayMesh Quality Gates

DisplayMesh is treated as a product, not a demo. A capability is not considered complete because a control exists in the UI; it is complete only when its end-to-end path is implemented, tested and documented.

## Product gates

A feature may be described as **available** only when:

1. the real platform backend exists,
2. the UI reaches that backend,
3. failure states are visible and recoverable,
4. automated tests cover deterministic protocol/domain behavior,
5. a manual hardware acceptance test exists for platform-specific behavior,
6. English and Spanish user-facing strings are complete,
7. accessibility labels exist for non-text controls,
8. diagnostics can identify the failing layer without exposing secrets.

Features that fail any gate must be labeled development/planned rather than presented as secure or complete.

## Receiver quality baseline

The iPhone/iPad receiver must:

- occupy the full display surface in portrait and landscape,
- preserve safe interactive controls without shrinking the remote surface,
- support System / English / Español,
- advertise native panel pixels, scale, orientation and maximum refresh rate,
- require explicit approval for a new peer,
- reject useful session traffic before authorization,
- keep the screen awake only while actively receiving,
- expose connection and protocol failures,
- never claim encrypted transport while running plaintext TCP,
- preserve touch and Pencil samples independently from video rendering.

## Security release blockers

Production distribution is blocked until all of the following are true:

- TLS 1.3 or an equivalently reviewed authenticated transport is enabled,
- peer identity is persisted securely,
- changed peer identity invalidates silent reconnect,
- pairing codes are short-lived and bound to the active connection,
- unauthenticated input/video/control traffic is rejected,
- secrets and identifiers are excluded from diagnostics.

USB is not implicitly trusted merely because a cable is attached.

## Performance release gates

Performance must be measured on real hardware.

Initial acceptance:

- 1080p60 without persistent frame queue growth,
- 1440p60 on supported hardware,
- bounded decode/render queue,
- stale video frames are dropped instead of increasing interaction latency,
- input has priority over queued video,
- reconnect does not leak old session state.
- capture-start failure tears down any virtual display created for that attempt,
- stopping a session tears down capture before the virtual display and is safe to retry.

Advanced acceptance:

- 4K60 where the complete hardware path supports it,
- 120 Hz only when virtual display, capture, codec, transport, decoder and panel all sustain it.

## Build/release gates

Before a release candidate:

- Rust workspace format, check, clippy and tests pass,
- macOS native harness builds,
- Windows bootstrap/driver checks pass,
- Apple receiver project generates reproducibly,
- Apple receiver Release builds pass for iOS Simulator and iPhoneOS with warnings treated as errors,
- protocol framing tests pass on both implementations,
- app version and protocol version are documented,
- release notes distinguish implemented features from roadmap items.
