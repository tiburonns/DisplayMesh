# Harness multimedia de Windows para DisplayMesh

Este harness valida la ruta GPU que conectará el swap-chain de escritorio IddCx con el transporte H.264 de DMP.

La prueba verifica en hardware Windows:

1. dispositivo D3D11 con soporte de video,
2. `IMFDXGIDeviceManager`,
3. conversión GPU BGRA → NV12,
4. descubrimiento de un encoder H.264 por hardware,
5. compatibilidad D3D11 del encoder,
6. configuración de entrada NV12 y salida H.264,
7. modo de baja latencia,
8. creación de un sample Media Foundation directamente desde una textura NV12 sin readback a CPU,
9. reapertura de NT handles D3D11 compartidos de DisplayMesh, validación de geometría/formato y creación de `IMFSample` con timing sin mapear píxeles a CPU.

Compila con:

```powershell
cmake -S platforms/windows/media-harness -B build/windows-media-harness
cmake --build build/windows-media-harness --config Release
```

El siguiente paso es conectar un worker asíncrono y acotado entre IddCx y el MFT. Los encoders por hardware de Media Foundation son asíncronos, así que el hilo del display driver no debe esperar al encoder.


## Entrada DXGI compartida

El harness incorpora una fábrica de samples que abre los NT handles del pool D3D11 compartido mediante `ID3D11Device1::OpenSharedResource1`, valida tamaño/formato, exige la superficie compartida con keyed mutex y la envuelve con `MFCreateDXGISurfaceBuffer`. El test WARP envuelve intencionalmente la superficie BGRA para validar ownership y timing; **no significa que BGRA se envíe directamente al encoder H.264**. La ruta real conserva la conversión GPU BGRA → NV12 antes de entregar NV12 al MFT. WARP valida lifecycle sin convertir esa prueba en una afirmación de rendimiento de GPU física.


## Identidad de frame hasta el encoder

`EncodeWorkItem` conserva secuencia, timestamp, duración, generación de superficie, slot y geometría desde el mailbox latest-frame-wins. `SharedSurfaceEncodeInput` exige que esa identidad todavía coincida con el pool D3D11 actual antes de crear un `IMFSample`. Por tanto, un frame anunciado antes de un resize se rechaza antes de llegar al MFT.
