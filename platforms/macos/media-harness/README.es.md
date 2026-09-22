# DisplayMesh macOS Media Harness

**[English](README.md) · Español**

Este harness es la primera ruta end-to-end de media en macOS: conecta con el receiver iPhone/iPad, usa el pairing de desarrollo, captura una pantalla con ScreenCaptureKit, codifica H.264 low-delay con VideoToolbox, empaqueta DMP y envía al receiver.

También implementa recuperación por keyframe y mapping de muestras de touch a pointer/drag/scroll.

```bash
swift build --package-path platforms/macos/media-harness
swift test --package-path platforms/macos/media-harness
```

Su propósito es validar la ruta real de media antes de integrarla como backend host productivo. No debe confundirse con una release terminada.
