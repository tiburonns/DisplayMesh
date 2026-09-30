# DisplayMesh Receiver 0.2.3 — TestFlight preflight

The iPhone/iPad receiver can be tested through TestFlight before the full DisplayMesh host product is production-ready. The current macOS ↔ Apple development binding now protects all post-pairing DMP frames with an authenticated ephemeral P-256 / HKDF-SHA256 / ChaCha20-Poly1305 session. This is **not** a claim that the final production transport has completed its independent security review.

## Source gates

- Generated project version: 0.2.3 (build 3).
- EN/ES/System localization parity.
- Privacy Manifest with UserDefaults required-reason declaration.
- Release builds for iOS Simulator and iPhoneOS.
- Protocol/video/input unit tests.
- H.264 VideoToolbox decoder + Metal NV12 renderer.
- Explicit receiver-side pairing before video/input authorization.
- Fresh receiver challenge + P-256 signed persistent macOS host identity.
- Receiver Keychain trust store detects host identity replacement; trusted peers can be cleared explicitly.
- Verify a simulated/real host identity replacement is rejected until trusted computers are cleared.

## Physical gates

- Install on iPhone and iPad.
- Verify the first-run education appears before the system Local Network prompt.
- Accept Local Network permission and verify Bonjour advertisement.
- Relaunch and confirm the education does not repeat after acknowledgement.
- Deny Local Network once, confirm the listener failure remains recoverable, use **Open Settings**, enable access, return to DisplayMesh, and verify **Try Again** can start listening.
- Pair with the macOS developer media harness.
- Verify H.264 decode, keyframe recovery, rotation, FPS/bitrate diagnostics and touch/Pencil samples.
- Run 1080p60 for at least 15 minutes and verify bounded queue behavior.
- Repeat on 1440p60-capable hardware where available.
- Verify background/foreground reconnect and idle-timer restoration.

## Local preflight

Run `./platforms/apple-receiver/preflight-testflight.sh` from the repository root. It validates resources, regenerates the project, runs unit tests, and performs warning-free Release builds for Simulator and iPhoneOS.

## Export compliance

The receiver uses CryptoKit for persistent P-256 identity and for the active P-256 ECDH / HKDF-SHA256 / ChaCha20-Poly1305 post-pairing DMP session. Do **not** hard-code an export-compliance exemption in the plist before the first upload.

For the first TestFlight upload, leave `ITSAppUsesNonExemptEncryption` unset and answer App Store Connect's encryption questionnaire based on the actual submitted build and distribution regions. After Apple determines whether this use is exempt or requires documentation, record that result and only then add the appropriate plist/export-compliance code for subsequent releases.

## Archive

Generate the project with XcodeGen 2.46.0, open it in Xcode 26+, choose your paid team, Archive, Validate App and upload for **Internal TestFlight**.

The receiver is an internal/development TestFlight candidate with authenticated encrypted DMP payloads over the current TCP binding. Production distribution still requires the remaining security, signing and hardware gates in `docs/QUALITY_GATES.md`.
