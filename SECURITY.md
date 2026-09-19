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
