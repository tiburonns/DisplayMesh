# DisplayMesh

DisplayMesh es un proyecto de pantalla virtual multiplataforma para **hosts macOS y Windows**, con **iPhone y iPad como receptores**.

El objetivo es permitir que una computadora cree una pantalla extendida real y la transmita a otra computadora o dispositivo Apple mediante **USB o Wi-Fi**, manteniendo baja latencia, alta resolución e interacción táctil.

> **`main` actual: 0.1.2.** Estado: desarrollo inicial. La app de control ya separa USB/Wi-Fi de QUIC/TCP, valida configuraciones compatibles y ofrece interfaz Sistema/English/Español. La integración nativa de pantalla, el empaquetado del receptor Apple y el video end-to-end siguen siendo hitos activos.

## Requisitos del producto

- Pantalla extendida real o modo duplicado
- macOS ↔ Windows, macOS ↔ macOS y Windows ↔ Windows
- iPhone y iPad como pantallas táctiles externas
- USB y Wi-Fi como modos de conexión de primera clase
- Negociación de resolución nativa Retina
- H.264 por hardware como baseline de baja latencia
- HEVC / AV1 después cuando el hardware lo permita
- 1080p60 y 1440p60 primero; 4K60 y 120 Hz después
- Multitouch, scroll y metadatos de Apple Pencil
- Mouse y teclado cuando aplique
- Bitrate, FPS y raster de transmisión adaptativos
- Emparejamiento y sesiones cifradas
- Interfaz en inglés, español e idioma del sistema

## Enlaces de conexión

DisplayMesh separa la conexión física del protocolo:

| Conexión | Protocolo inicial |
| --- | --- |
| Wi-Fi / LAN | QUIC o TCP |
| Ethernet | QUIC o TCP |
| USB a iPhone/iPad | TCP mediante usbmux |

Esto permite que USB sea una ruta real de baja variación de latencia sin mezclarlo conceptualmente con QUIC/TCP.

## Arquitectura

```text
apps/control
    │
    ├── displaymesh-core
    │       ├── modelo de dispositivos/sesiones
    │       ├── negociación de capacidades
    │       ├── modelo de touch
    │       └── modelo de bindings de conexión
    │
    ├── backend host macOS
    │       ├── monitor virtual
    │       ├── ScreenCaptureKit
    │       └── VideoToolbox
    │
    ├── backend host Windows
    │       ├── driver virtual IddCx
    │       ├── DXGI / D3D11
    │       └── Media Foundation
    │
    └── receptor Apple
            ├── listener con Network.framework
            ├── decode con VideoToolbox / AVFoundation
            ├── presentación Metal
            └── touch / Pencil con UIKit
```

Consulta [ARCHITECTURE.md](docs/ARCHITECTURE.md), [ROADMAP.md](docs/ROADMAP.md), [DMPv1.md](protocol/DMPv1.md), las [notas del receptor Apple](platforms/apple-receiver/README.md) y el [plan de aceptación nativa](docs/TESTING.es.md).

## Compilar la aplicación de control

Instala Rust estable y ejecuta:

```bash
cargo run -p displaymesh-control
```

La aplicación de control compila tanto en macOS como en Windows. Los backends de monitor virtual están separados intencionalmente de la UI compartida para usar las APIs y el modelo de drivers adecuados en cada plataforma.

## Idiomas

- Español: este archivo
- English: [README.md](README.md)

## Política del repositorio

DisplayMesh es una implementación independiente. No se debe copiar branding, arte ni código fuente de OpenDisplay. La interoperabilidad debe basarse en documentación pública de protocolos/APIs y en implementaciones limpias e independientes.
