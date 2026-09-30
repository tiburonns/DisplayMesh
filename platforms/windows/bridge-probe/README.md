# DisplayMesh Windows Companion Bridge

DisplayMesh keeps the IddCx driver and the product/session process separate.

The public control contract lives in `bridge/DisplayMeshBridgeProtocol.h`. The driver exposes a device interface and uses IddCx's companion-app IOCTL callback for small control messages.

Current control operations:

- query driver/monitor readiness,
- read the current receiver-native requested mode,
- set an even-pixel receiver mode from 640×480 through 8192×8192 at 30–240 Hz.

The requested receiver mode is added to the monitor/target mode list on the next Windows mode query. Automatic monitor re-arrival is intentionally deferred until WDK/hardware validation so an IOCTL cannot unexpectedly tear down an active desktop.

## Frame backpressure contract

`bridge/LatestFrameMailbox.h` defines the scheduling rule used at the GPU-frame boundary.

- exactly three reusable frame slots,
- sequence-numbered publication,
- explicit nonzero GPU surface generation on every frame announcement,
- generation/geometry matching so a stale announcement cannot target a recreated slot after resize,
- single-producer/single-consumer operation,
- no FIFO backlog,
- consumer always takes the newest complete frame,
- sequence gaps report how many stale frames were intentionally skipped,
- metadata publication uses lock-free atomics on the supported x64/ARM64 Windows targets.

The mailbox does not carry pixels. `SharedD3D11TexturePool` now owns exactly three real D3D11 textures created with NT shared handles + keyed mutex support, while `SharedGpuSlotContract.h` binds slot index + monotonically increasing generation + geometry. Pool recreation is atomic: a new generation replaces the old slots only after all three textures/handles are created successfully, so resize failure cannot leave a partially updated pool and stale announcements cannot target recreated textures.

This gives DisplayMesh deterministic **latest-frame-wins** behavior: congestion can reduce visual frame count, but it cannot turn into seconds of accumulated interaction latency.

The bridge-probe test suite creates the shared texture pool on the Windows WARP D3D11 device, reopens every NT handle through `ID3D11Device1::OpenSharedResource1`, verifies keyed-mutex/share flags, then recreates the pool at a new raster and confirms the previous generation is rejected. WARP validates ownership/lifecycle without claiming physical-GPU performance.

## Build and test

```powershell
cmake -S platforms/windows/bridge-probe -B build/windows-bridge-probe
cmake --build build/windows-bridge-probe --config Release
ctest --test-dir build/windows-bridge-probe -C Release --output-on-failure
```

Query status:

```powershell
.\build\windows-bridge-probe\Release\displaymesh-bridge-probe.exe
```

Request a receiver-native mode:

```powershell
.\displaymesh-bridge-probe.exe --mode 2732 2048 120
```

Video frames do not travel through control IOCTLs. The pixel path remains GPU-based.
