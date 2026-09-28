# Windows native backend

The Windows implementation is split into an application-side media backend, a Software Device bootstrap and an Indirect Display Driver.

## Application backend

Responsibilities:

- DXGI / D3D11 capture
- Media Foundation hardware encode/decode
- D3D11 rendering
- Windows input injection
- telemetry

## DMP protocol foundation

`protocol/` contains the native C++ DMPv1 framing foundation for the Windows path. It currently validates the fixed 16-byte header, protocol/message IDs, per-message payload budgets, exact input/keyframe sizes, and per-connection sequence progression. It is deliberately transport-agnostic; the Windows network/media service still needs to be integrated.

Build and test:

```powershell
cmake -S platforms/windows/protocol -B build/windows-protocol
cmake --build build/windows-protocol --config Release
ctest --test-dir build/windows-protocol -C Release --output-on-failure
```

The input bridge also rejects reserved DMPv1 input flags instead of silently accepting undefined extensions.

## Software-device bootstrap

`bootstrap/` contains a small Windows SDK application that creates the DisplayMesh software device with `SwDeviceCreate`.

Build from a Developer Command Prompt:

```powershell
cmake -S platforms/windows/bootstrap -B build/windows-bootstrap
cmake --build build/windows-bootstrap --config Release
```

The bootstrap does **not** pretend to be the display driver. It enumerates the software device and expects a matching `DisplayMeshIdd` driver package to already be installed.

## Virtual display driver

The next native milestone is the DisplayMesh IddCx driver using the Windows Driver Kit.

Responsibilities:

- expose virtual monitor(s) to Windows
- publish supported modes
- manage monitor arrival/departure
- provide a stable control path to the DisplayMesh service
- process swap chains without unnecessary CPU copies

## Development signing

Initial driver builds should use Windows test signing on dedicated development machines. Production distribution requires Microsoft's production driver-signing flow and must not depend on test mode.

## Validation checklist

1. Install the test-signed DisplayMesh IddCx package.
2. Run the bootstrap and create the software device.
3. Verify a 1920×1080 @ 60 Hz virtual monitor appears.
4. Extend the Windows desktop onto it.
5. Close the bootstrap.
6. Verify the virtual monitor departs cleanly.
7. Uninstall the development driver without stale devices.
