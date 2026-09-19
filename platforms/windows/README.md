# Windows native backend

The Windows implementation is split into an application-side media backend and an Indirect Display Driver.

## Application backend

Responsibilities:

- DXGI / D3D11 capture
- Media Foundation hardware encode/decode
- D3D11 rendering
- Windows input injection
- telemetry

## Virtual display driver

Use Microsoft's IddCx model through the Windows Driver Kit.

Responsibilities:

- expose virtual monitor(s) to Windows
- publish supported modes
- manage monitor arrival/departure
- provide a stable control path to the user-mode DisplayMesh service

## Development signing

The first driver builds should use Windows test signing on dedicated development machines. Production distribution requires the appropriate Microsoft driver signing flow and must not rely on test mode.

## First implementation milestone

1. Install a development driver package.
2. Add one 1920×1080 @ 60 Hz virtual monitor.
3. Verify Windows can extend the desktop onto it.
4. Remove the monitor.
5. Uninstall the driver without leaving stale devices.
