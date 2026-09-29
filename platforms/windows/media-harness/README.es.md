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
8. creación de un sample Media Foundation directamente desde la textura NV12 sin readback a CPU.

Compila con:

```powershell
cmake -S platforms/windows/media-harness -B build/windows-media-harness
cmake --build build/windows-media-harness --config Release
```

El siguiente paso es conectar un worker asíncrono y acotado entre IddCx y el MFT. Los encoders por hardware de Media Foundation son asíncronos, así que el hilo del display driver no debe esperar al encoder.
