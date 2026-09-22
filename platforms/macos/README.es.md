# Backend nativo de macOS

**[English](README.md) · Español**

Responsabilidades objetivo: ciclo de vida de pantalla virtual, modos/HiDPI, ScreenCaptureKit, VideoToolbox, Metal, input y permisos/diagnóstico.

`harness/` contiene una prueba independiente que resuelve clases de pantalla virtual en runtime. No enlaza esas declaraciones privadas con la app Rust compartida.

```bash
make -C platforms/macos/harness
./platforms/macos/harness/displaymesh-virtual-display
```

La interfaz usada para pantalla virtual no es pública y debe revalidarse en cada macOS soportado. La distribución final debe asumir firma/notarización directa, no aceptación garantizada en Mac App Store.

El harness es evidencia de desarrollo, no el backend productivo completo.
