# DisplayMesh Windows Companion Bridge

DisplayMesh keeps the IddCx driver and the product/session process separate.

The public bridge contract lives in `bridge/DisplayMeshBridgeProtocol.h`. The driver exposes a device interface and uses IddCx's companion-app IOCTL callback for small control messages.

Current bridge operations:

- query driver/monitor readiness,
- read the current receiver-native requested mode,
- set an even-pixel receiver mode from 640×480 through 8192×8192 at 30–240 Hz.

The requested receiver mode is added to the monitor/target mode list on the next Windows mode query. Automatic monitor re-arrival is intentionally deferred until WDK/hardware validation so an IOCTL cannot unexpectedly tear down an active desktop.

Build the probe:

```powershell
cmake -S platforms/windows/bridge-probe -B build/windows-bridge-probe
cmake --build build/windows-bridge-probe --config Release
```

Query status:

```powershell
.\build\windows-bridge-probe\Release\displaymesh-bridge-probe.exe
```

Request a receiver-native mode:

```powershell
.\displaymesh-bridge-probe.exe --mode 2732 2048 120
```

Video frames do not travel through these IOCTLs. The frame bridge remains GPU-based.
