# Windows native backend

The Windows implementation is split into the product/service layer, a Software Device bootstrap, the UMDF/IddCx virtual display driver, the input bridge and the future Media Foundation encoder.

## Current state

Implemented in source:

- Software Device bootstrap with `SwDeviceCreate`
- DisplayMesh UMDF/IddCx driver package under `idd/`
- one virtual DisplayMesh monitor
- 1920×1080 at 60/120 Hz
- 2560×1440 at 60/120 Hz
- 3840×2160 at 60 Hz
- D3D11 render-device creation on the adapter selected by Windows
- real IddCx swap-chain acquisition/release lifecycle
- Windows multi-contact touch injection bridge
- CI contract checks for hardware ID, driver package, modes and no-CPU-readback invariant
- reusable three-slot D3D11 shared-texture pool with NT handles, keyed mutexes and generation-safe resize/recreation

Still pending:

- compile the driver with a real WDK toolchain
- install/test-sign it on Windows hardware or a suitable VM
- connect the IddCx desktop texture producer to the shared D3D11 pool and Media Foundation H.264 worker
- dynamic receiver-native monitor modes
- integrate authenticated DMP input with the touch injector
- production driver signing

## Bootstrap

`bootstrap/` enumerates the `DisplayMeshIdd` software device. It is not the display driver.

Build:

```powershell
cmake -S platforms/windows/bootstrap -B build/windows-bootstrap
cmake --build build/windows-bootstrap --config Release
```

## IddCx driver

`idd/` contains the actual virtual-display driver source, INF and Visual Studio driver project.

With Visual Studio 2022 + Windows SDK + WDK:

```powershell
msbuild platforms\windows\idd\DisplayMeshIdd.vcxproj /p:Configuration=Debug /p:Platform=x64
```

The driver keeps the desktop frame as a D3D11 GPU surface. The normal path intentionally does not map frames back to CPU memory; the next media milestone feeds that texture directly into the Windows hardware H.264 encoder.

## Development signing

Use test signing only on a dedicated development PC/VM. Production distribution requires Microsoft's production driver-signing submission flow.

## Hardware acceptance

1. Compile x64 and ARM64 with the WDK.
2. Test-sign/install the package.
3. Start the DisplayMesh bootstrap.
4. Confirm **DisplayMesh Virtual Display Adapter** enumerates.
5. Confirm Windows offers the advertised modes.
6. Extend the desktop onto the virtual display.
7. Exercise 60/120 Hz swap-chain delivery.
8. Close/remove the software device and confirm clean monitor departure.
9. Run Driver Verifier/IDD diagnostics before calling the driver production-ready.


## Bounded encode scheduling

`media-harness/BoundedEncodeWorker` provides the low-latency queue policy for the Windows encoder path. At most one frame may wait while another is being processed; newer submissions replace an older pending frame, stale sequence numbers are rejected, shutdown discards pending work, and handler failures cannot kill the worker thread.

This is intentionally a scheduling foundation, not a claim that the IddCx texture is already flowing into Media Foundation. The remaining integration must carry the shared D3D11 surface/handle into this worker without CPU readback and then packetize the encoded H.264 output into DMP.


## H.264 Annex-B packetizer

`media-harness/H264AnnexBPacketizer` validates Annex-B access units and produces the same 16-byte DMP video payload header consumed by the Apple receiver. It caches SPS/PPS, repairs an IDR that omits them when valid cached parameter sets exist, normalizes NAL start codes, preserves the DMP payload budget, and fails instead of emitting a non-recoverable keyframe when parameter sets are unavailable.

This component is deterministic and hardware-independent. The remaining Windows M2 work is to feed real Media Foundation encoder output into it and then wrap the resulting video payload in the authenticated DMP transport.


## Host session admission

`protocol/DmpHostSessionGate` mirrors the host-side DMP phase rules used by the macOS development path. Input routing and video transmission stay closed until the host has accepted receiver hello, sent pairing, accepted the pairing response, validated receiver capabilities and accepted a panel descriptor. Unexpected message types fail closed for the current phase; reset immediately closes the input/video gates.

This is an admission/state-machine boundary, **not** the Windows pairing/crypto implementation itself. The Windows network service must validate identity/pairing before advancing this gate and only then forward validated input payloads to the native injector.


## Session-gated input routing

`input-bridge/DmpInputRouter` joins the protocol admission gate and the 40-byte input decoder. Even a structurally valid touch sample is rejected unless the host session is already in `streaming`; non-input frames and reserved DMP input-payload flags are rejected before injection.

The remaining integration is the actual Windows network/pairing service: it must advance `DmpHostSessionGate` only after identity/pairing/capability validation, decode frames through the native DMP library, then pass authorized input frames through this router into `TouchInjector`.

## Reconnect policy

`protocol/DmpHostReconnectPolicy` mirrors the bounded reconnect behavior used by the macOS development host. Only transport closure and bounded machine-phase timeouts are retryable. Pairing timeout/rejection, identity change, protocol violations, incompatible capabilities and replay/sequence failures stop instead of looping. Reconnect uses 500 ms → 1 s → 2 s → 4 s capped backoff and resets `DmpHostSessionGate` to `AwaitingHello` before any retry, closing video and input gates immediately.

This is deliberately transport-independent. It does not claim that the Windows Wi-Fi/USB network service is already implemented.


## Receiver-native mode normalization

The driver-side mode request now uses a shared `ReceiverModePolicy` before touching IddCx state. It accepts negotiated mobile-panel dimensions within the product safety bounds and normalizes odd pixel axes down by at most one pixel so the resulting mode stays compatible with the NV12/H.264 GPU pipeline. Invalid protocol versions, extreme dimensions and unsupported refresh rates fail before driver state changes.

This removes an avoidable incompatibility with real mobile panels that report an odd native width or height while preserving deterministic, bounded virtual-display geometry.
