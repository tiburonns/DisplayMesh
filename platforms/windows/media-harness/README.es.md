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


## Coordinación de encode en vivo

La ruta multimedia de Windows ahora incluye `LiveEncodeCoordinator`, que une el modelo asíncrono de créditos `NeedInput` / `HaveOutput` de Media Foundation con el worker acotado de último frame.

El coordinador:

- conserva sólo el frame más reciente mientras no exista crédito de entrada;
- reserva exactamente un crédito MFT por frame programado;
- impide que una ráfaga de frames reutilice un solo evento `NeedInput`;
- falla de forma cerrada si falla el handler de entrada o salida;
- descarta trabajo pendiente no programado al comenzar drain;
- expone estadísticas separadas del coordinador, worker y pump.

Esta es la capa determinista de orquestación. El siguiente paso en Windows es integrar las llamadas reales `IMFTransform::ProcessInput` / `ProcessOutput` y después conectar el productor vivo de superficies IddCx.


## Ruta MFT asíncrona concreta

El harness multimedia ya tiene las piezas concretas entre un frame GPU admitido y un payload de vídeo DMP:

`EncodeWorkItem → InputSampleFactory/SharedSurfaceEncodeInput → IMFTransform::ProcessInput → eventos MFT asíncronos → IMFTransform::ProcessOutput → normalizador H264 → packetizer DMP → handler de paquetes`.

`MftLiveEncodeAdapter` usa el adaptador real de superficies compartidas en producción, pero permite inyectar la fábrica de samples para probar de forma determinista fallos de Media Foundation y la salida H.264 sin requerir GPU física.

`MftAsyncEventPump` consume los eventos asíncronos del transform y dirige `METransformNeedInput`, `METransformHaveOutput` y `METransformDrainComplete` a `LiveEncodeCoordinator`. Los errores del transform/eventos fallan de forma cerrada y detienen el pump.

El gate multimedia Windows restante es conectar el productor IddCx vivo y la publicación BGRA→NV12 a esta ruta, seguido del binding de sesión/red DMP de Windows.
