# DisplayMesh Receiver 0.2.2 — TestFlight preflight

The iPhone/iPad receiver can be tested through TestFlight before the full DisplayMesh host product is production-ready. This does **not** make plaintext developer transport a production security claim.

## Source gates

- Generated project version: 0.2.2 (build 3).
- EN/ES/System localization parity.
- Privacy Manifest with UserDefaults required-reason declaration.
- Release builds for iOS Simulator and iPhoneOS.
- Protocol/video/input unit tests.
- H.264 VideoToolbox decoder + Metal NV12 renderer.
- Explicit receiver-side pairing before video/input authorization.
- Fresh receiver challenge + P-256 signed persistent macOS host identity.
- Receiver trust store detects host identity replacement; trusted peers can be cleared explicitly.

## Physical gates

- Install on iPhone and iPad.
- Accept Local Network permission and verify Bonjour advertisement.
- Pair with the macOS developer media harness.
- Verify H.264 decode, keyframe recovery, rotation, FPS/bitrate diagnostics and touch/Pencil samples.
- Run 1080p60 for at least 15 minutes and verify bounded queue behavior.
- Repeat on 1440p60-capable hardware where available.
- Verify background/foreground reconnect and idle-timer restoration.

## Local preflight

Run `./platforms/apple-receiver/preflight-testflight.sh` from the repository root. It validates resources, regenerates the project, runs unit tests, and performs warning-free Release builds for Simulator and iPhoneOS.

## Export compliance

The receiver uses Apple's CryptoKit for P-256 signing verification and does not implement its own encryption algorithm. The current plist declares `ITSAppUsesNonExemptEncryption = NO` because this build uses only exempt, Apple-provided cryptographic functionality. Re-evaluate this declaration if transport encryption or third-party/custom cryptography changes.

## Archive

Generate the project with XcodeGen 2.46.0, open it in Xcode 26+, choose your paid team, Archive, Validate App and upload for **Internal TestFlight**.

The receiver is an internal/development TestFlight candidate while DMP transport is plaintext TCP. Production distribution remains blocked by the security gates in `docs/QUALITY_GATES.md`.
