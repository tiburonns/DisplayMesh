# DisplayMesh Security Policy

DisplayMesh creates or controls virtual displays, captures screen content, receives input, and is designed to establish encrypted peer-to-peer sessions. Security defects in these areas can expose sensitive screen contents or allow unintended input, so security is treated as a release-blocking concern.

## Supported code

Security work currently targets the `main` branch while DisplayMesh is in early development. Once packaged releases begin, this document will list supported release lines explicitly.

## Reporting a vulnerability

Do not open a public issue for a vulnerability that could expose display contents, pairing credentials, remote input, driver installation, privilege boundaries, or code execution.

Use GitHub private vulnerability reporting when it is enabled for this repository. If private reporting is not available, contact the repository owner privately before publishing technical details.

Include, when possible:

- affected commit or version
- macOS or Windows version
- reproduction steps
- expected and observed behavior
- whether physical/local network access is required
- logs with secrets, device identifiers, and screen contents removed
- proof-of-concept material only when necessary to reproduce safely

## Security invariants

A production DisplayMesh session must satisfy all of the following:

- Encryption is enabled by default for network sessions.
- First pairing requires explicit user confirmation.
- The current Apple/macOS development pairing path signs the receiver challenge with a persistent P-256 host key stored in macOS Keychain; accepted receiver-side host trust records are also persisted in Keychain.
- The receiver rejects a changed public key for a known peer ID until the user explicitly clears trust.
- The shared development capability model must report plaintext TCP as unencrypted and must not advertise QUIC/USB until those concrete end-to-end transports exist.
- A peer identity change invalidates silent reconnect.
- Remote input is rejected until the peer is authenticated and authorized.
- Session configuration is negotiated from capabilities; unsupported codec, transport, display mode, or security requirements must fail explicitly rather than silently downgrade.
- Raw/uncompressed development transports are never enabled in production builds.
- Driver/bootstrap installation never disables system security protections automatically.
- macOS private display compatibility code remains isolated from the shared application.
- Windows test-signed drivers remain limited to dedicated development systems and are not presented as production packages.

## Sensitive logging

Logs must not include pairing secrets, cryptographic keys, full screen frames, clipboard contents, typed keystrokes, or authentication material. Device names and network addresses should be minimized or redacted in diagnostics intended for sharing.

## Dependency and build integrity

Before the first packaged release, DisplayMesh should commit `Cargo.lock` for reproducible Rust dependency resolution and pin third-party CI actions by full commit SHA. Native driver/toolchain versions used for release builds should be recorded with release notes.

## Scope

DisplayMesh is intended for devices and networks the user controls or is authorized to use. The project must not add stealth installation, hidden remote control, credential interception, or mechanisms designed to bypass OS security prompts.


## Current development identity boundary

DisplayMesh 0.2.3 authenticates **both development peers** during pairing. The macOS host signs the receiver challenge with its persistent P-256 identity. The Apple receiver signs the pairing result with its own persistent P-256 identity while binding both the receiver challenge and an independent fresh host challenge.

Both sides persist accepted peer public keys using device-only Keychain storage and fail closed when a known peer ID presents a different key. This closes the asymmetric identity gap in the development handshake, but it does **not** make the current plaintext TCP media session production-secure: media/control transport is still unencrypted.


## Development protocol guardrails

The plaintext TCP development binding remains intentionally labeled **not production-secure**. While it is used for engineering validation, DMP applies defense-in-depth guardrails:

- message-specific payload budgets are rejected from the 16-byte frame header before buffering the body;
- input and keyframe-request payload sizes are exact, and reserved input flags are rejected;
- sequence gaps/replays close the transport session;
- the receiver accepts only messages permitted by the current authorization/session phase;
- pairing admission and user approval windows are bounded, and repeated malformed pairing attempts close the connection;
- pairing responses are bound to the active receiver challenge;
- an unsolicited second LAN peer cannot replace an active receiver connection;
- Bonjour uses a generic DisplayMesh service name rather than exposing the configured device name;
- host identity and accepted trust records use device-only Keychain accessibility.

These controls reduce attack surface during development. Mutual persistent P-256 peer authentication is now present, but it does **not** replace TLS 1.3 (or an equivalently reviewed encrypted transport) for production confidentiality and transport integrity.


## Production negotiation guard

Production negotiation must reject any configuration with encryption disabled, even if both peers incorrectly advertise the same plaintext capability. The explicit plaintext path is limited to the development scaffold and must never be reused as a production fallback.


## Secure-session primitive status

The Apple receiver and macOS media harness now share a mirrored secure-session primitive based on ephemeral P-256 key agreement, HKDF-SHA256 directional keys and ChaCha20-Poly1305 authenticated encryption. Authentication data binds DMP protocol version, message type, flags and sequence number.

The secure-session primitive is now wired into the macOS ↔ Apple DMP TCP framing path. Ephemeral P-256 key-agreement public keys are covered by the signed mutual pairing transcript, and every post-pairing frame is required to authenticate/decrypt successfully. The current binding is encrypted and authenticated at the DMP payload layer; a separately reviewed production transport remains a release gate.


## Protected frame codec staging

DisplayMesh now has a mirrored Apple/macOS protected-frame codec that enforces the intended wire boundary before socket integration:

- `hello` and `pairing` are the only plaintext handshake frame types;
- every post-pairing frame requires an installed secure session;
- plaintext post-pairing frames fail closed;
- ChaCha20-Poly1305 overhead is included in per-message wire-size validation, including exact-size input and keyframe-request messages;
- the encrypted flag, message type and sequence remain authenticated metadata.

The active TCP listener/connection now install the codec from pairing-bound ephemeral key-agreement material before capabilities or media are admitted. Production readiness still requires the remaining transport review, hardware acceptance, signing and packaging gates.
