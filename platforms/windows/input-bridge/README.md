# DisplayMesh Windows Input Bridge

This component turns DisplayMesh's fixed-width binary touch samples into real Windows touch input.

## Why this exists

High-rate iPhone/iPad touch and Apple Pencil samples should not travel through JSON in the interactive path. DMP input samples use a fixed 40-byte binary representation so Windows can validate and map them with predictable work.

The bridge tracks active contacts and calls the Win32 touch injection APIs. The target rectangle is the desktop rectangle occupied by the DisplayMesh virtual monitor.

## Build

```powershell
cmake -S platforms/windows/input-bridge -B build/input-bridge
cmake --build build/input-bridge --config Release
ctest --test-dir build/input-bridge -C Release --output-on-failure
```

## Runtime integration

The production Windows host will:

1. receive authenticated DMP `input` frames,
2. decode a 40-byte `DmpInputSample`,
3. resolve the current desktop rectangle of the DisplayMesh IddCx monitor,
4. pass the sample to `TouchInjector`,
5. cancel all active contacts if the virtual display is removed or its geometry changes.

The standalone CLI exists only for development decoding/injection tests.

## Important behavior

- A touch sequence must begin before update/end events are accepted.
- All active contacts are included in each injected touch frame.
- A changed final coordinate is injected as an update before the UP frame, because Windows requires the UP location to match the preceding update.
- Cancellation uses `POINTER_FLAG_CANCELED | POINTER_FLAG_UP`.
- Pressure is normalized to the Windows 0–1024 touch range.
- Pencil samples currently use the touch injector path. A dedicated synthetic pen path remains a later milestone.
