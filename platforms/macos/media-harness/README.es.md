# DisplayMesh macOS Media Harness

**[English](README.md) · Español**

Este harness es la primera ruta end-to-end de media en macOS: conecta con el receiver iPhone/iPad, espera un challenge nuevo, firma el pairing de seis dígitos con una identidad P-256 persistida en Keychain, captura una pantalla con ScreenCaptureKit, codifica H.264 low-delay con VideoToolbox, empaqueta DMP y envía al receiver.

También implementa recuperación por keyframe y mapping de muestras de touch a pointer/drag/scroll.

```bash
swift build --package-path platforms/macos/media-harness
swift test --package-path platforms/macos/media-harness
```

La identidad firmada endurece el pairing, pero TCP sigue sin cifrado. Su propósito es validar la ruta real de media antes de integrarla como backend host productivo. No debe confundirse con una release terminada.
