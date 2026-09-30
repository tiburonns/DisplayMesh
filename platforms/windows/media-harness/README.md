# DisplayMesh Windows Media Harness

This harness validates the Windows GPU media path that will sit between the IddCx desktop swap-chain and DMP H.264 transport.

It intentionally stays outside the UMDF display driver while the media path is being validated.

## Implemented probe

At runtime it verifies that a Windows machine can:

1. create a hardware D3D11 device with video support,
2. create an `IMFDXGIDeviceManager`,
3. convert a GPU BGRA texture to NV12 using the D3D11 video processor,
4. enumerate a hardware H.264 encoder MFT,
5. require a D3D11-aware encoder,
6. configure H.264 output and NV12 input,
7. request low-latency operation,
8. wrap an NV12 `ID3D11Texture2D` in a Media Foundation DXGI buffer/sample without CPU readback,
9. reopen DisplayMesh NT shared D3D11 handles and validate geometry/format before wrapping them in timed `IMFSample` objects,
10. normalize hardware H.264 output from Annex-B or 4-byte AVC length-prefixed access units before DMP packetization.

This is the correct foundation for DisplayMesh's Windows sender. Hardware MFTs are asynchronous. The harness now includes a deterministic MFT pump state contract for NeedInput / HaveOutput / drain sequencing, alongside the bounded latest-frame worker, so the eventual hardware event pump cannot block the IddCx swap-chain thread or submit input after drain has started.

## Build

```powershell
cmake -S platforms/windows/media-harness -B build/windows-media-harness
cmake --build build/windows-media-harness --config Release
```

## Run

Default 1080p60 at 24 Mbps:

```powershell
.\build\windows-media-harness\Release\displaymesh-media-probe.exe
```

Custom mode:

```powershell
.\displaymesh-media-probe.exe 2560 1440 60 36
```

A successful result proves capability/configuration on that machine. It does **not** yet prove sustained encoding or DMP transmission.

## Next integration

The bounded worker, MFT event-pump state contract, encoded-output processor, shared D3D11 pool and shared-handle DXGI sample factory are now present. The factory reopens an NT shared texture, rejects geometry/format mismatches, keeps the sample GPU-backed, and assigns Media Foundation timestamps/durations without mapping pixels to CPU memory. The WARP contract test intentionally wraps the pool's BGRA surface to validate shared-handle ownership; **this is not a claim that BGRA is fed directly to the H.264 encoder**. The live sender still performs GPU BGRA → NV12 conversion before submitting NV12 to the encoder MFT. Media Foundation H.264 output is then normalized and packetized for DMP. The next runtime step is to bind the live IddCx producer, GPU conversion stage and actual asynchronous MFT events to this contract:

```text
IddCx BGRA texture
    ↓
GPU video processor
    ↓
NV12 texture
    ↓
Media Foundation hardware H.264 MFT
    ↓
Annex-B/DMP packetizer
    ↓
network / USB transport
```

No ordinary frame should be copied to CPU memory.
