# Legacy iOS 9 receiver profile

`platforms/apple-receiver-legacy` is a compatibility receiver for 32-bit devices that cannot run the modern SwiftUI/Network.framework target.

## Negotiation

The receiver advertises a capabilities JSON payload with:

- `profile`: `legacy-ios9-jpeg`
- `videoCodecs`: `["jpeg"]`
- `connectionBindings`: `["tcp"]`
- `encryption`: `["none"]`
- `maximumFramesPerSecond`: `20`

The host must select this profile explicitly. It must not silently downgrade a normal DMPv1 session.

## Media payload

Each `video` (`0x10`) DMP frame contains one complete JPEG image. The receiver keeps at most one pending image and discards superseded images to bound latency. The profile is intended for compatibility, not high-frame-rate production streaming.

## Security boundary

The receiver asks the user to authorize every TCP peer. Transport is not encrypted because TLS 1.3 is unavailable on iOS 9. Use this profile only over an authenticated usbmux tunnel or an isolated trusted LAN. Internet exposure is unsupported.

## Toolchain

An armv7 artifact requires Xcode 8.3.3 and an iOS 9-compatible signing profile. Modern Xcode releases can syntax-check the Objective-C source on a simulator but cannot link the installable 32-bit device binary.
