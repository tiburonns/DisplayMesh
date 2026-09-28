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

DisplayMesh 0.2.2 authenticates the **macOS development host identity** during pairing with P-256 signatures and a fresh receiver challenge. This prevents silent host-key substitution after trust has been recorded, but it does **not** make the current plaintext TCP media session production-secure: the receiver does not yet present a cryptographically authenticated identity to the host and media/control transport is not yet encrypted.


## Development protocol guardrails

The plaintext development binding is **not** a secure production transport. While it remains in use for engineering validation, DMP now applies defense-in-depth guardrails:

- message-specific payload budgets are rejected from the frame header before buffering the body;
- input/keyframe payload sizes are exact and reserved input flags are rejected;
- sequence gaps/replays close the transport session;
- a receiver connection has a bounded admission window and malformed pairing attempts are bounded;
- frames outside the current authorization/session phase are rejected;
- stale pairing responses are bound to and rejected against the active receiver challenge;
- a second LAN peer cannot replace an already active receiver connection;
- Bonjour advertises a generic DisplayMesh service name instead of the user-configured device name;
- host identity and receiver trust records use device-only Keychain accessibility.

These controls reduce attack surface during development but do **not** satisfy the production TLS 1.3 requirement.
