# DisplayMesh macOS Media Harness

**[English](README.md) · Español**

Este harness es la primera ruta end-to-end de media en macOS: conecta con el receiver iPhone/iPad, espera un challenge nuevo, firma el pairing de seis dígitos con una identidad P-256 persistida en Keychain, captura una pantalla con ScreenCaptureKit, codifica H.264 low-delay con VideoToolbox, empaqueta DMP y envía al receiver.

También implementa recuperación por keyframe, mapping de muestras de touch a pointer/drag/scroll y reconexión limitada con backoff para fallos transitorios. Cada reconexión reinicia challenge, secuencias y estado de protocolo para no reutilizar una sesión obsoleta.

```bash
swift build --package-path platforms/macos/media-harness
swift test --package-path platforms/macos/media-harness
```

La identidad firmada endurece el pairing, pero TCP sigue sin cifrado. Su propósito es validar la ruta real de media antes de integrarla como backend host productivo. No debe confundirse con una release terminada.


## Raster adaptativo

La telemetría del receiver puede mover el pipeline de desarrollo entre 100%, 85%, 75% y 67% del raster codificado. La reconfiguración actualiza primero ScreenCaptureKit, recrea el encoder VideoToolbox con el nuevo raster, descarta frames durante la transición y fuerza recuperación con un keyframe nuevo. La geometría lógica del panel del receiver no cambia. Si una reconfiguración no puede reconstruir el encoder, la sesión de desarrollo se desmonta en lugar de continuar con estados de captura/codificación incompatibles.
