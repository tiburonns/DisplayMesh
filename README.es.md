# DisplayMesh

DisplayMesh es un proyecto de pantalla virtual multiplataforma para **hosts macOS y Windows**, con **iPhone y iPad como receptores**.

El objetivo es permitir que una computadora cree una pantalla extendida real y la transmita a otra computadora o dispositivo Apple mediante **USB o Wi-Fi**, manteniendo baja latencia, alta resolución e interacción táctil.

> **`main` actual: 0.2.0-development.** El receptor Apple ya incluye la ruta real de recepción H.264 de baja latencia (paquete DMP → parser Annex-B → VideoToolbox → NV12 → Metal), trabajo de decoder acotado, recuperación por keyframe, diagnósticos en vivo de FPS/bitrate/decode e interfaz Sistema/English/Español. La captura/encode del host y la validación end-to-end en hardware siguen siendo los bloqueadores antes de llamarlo un monitor externo utilizable.

## Requisitos del producto

- Pantalla extendida real o modo duplicado
- macOS ↔ Windows, macOS ↔ macOS y Windows ↔ Windows
- iPhone y iPad como pantallas táctiles externas
- USB y Wi-Fi como modos de conexión de primera clase
- Negociación de resolución nativa Retina
- H.264 por hardware como baseline de baja latencia
- HEVC / AV1 después cuando el hardware lo permita
- 1080p60 y 1440p60 primero; 4K60 y 120 Hz sólo después de validación en hardware
- Multitouch, scroll y metadatos de Apple Pencil
- Mouse y teclado cuando aplique
- Bitrate y raster codificado adaptativos sin cambiar la geometría lógica del escritorio
- Emparejamiento y sesiones cifradas
- Interfaz en inglés, español e idioma del sistema

## Estrategia de latencia

DisplayMesh prioriza interacción fresca en lugar de comportamiento de reproductor multimedia.

- sin buffer deliberado de reproducción
- trabajo del decoder acotado
- decode VideoToolbox en tiempo real en receptores Apple
- presentación Metal desde superficies NV12
- solicitud de keyframe después de pérdida de sincronía o reset por backlog
- prioridad de input/control sobre video en cola
- el controlador adaptativo reduce bitrate antes de reducir el raster codificado
- congestión persistente puede bajar 100% → 85% → 75% → 67%
- la recuperación restaura resolución antes de subir agresivamente el bitrate

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
    │       ├── framing DMP + contrato de video
    │       ├── controlador adaptativo de calidad
    │       ├── modelo de touch
    │       └── ciclo de vida del backend
    │
    ├── backend host macOS
    │       ├── monitor virtual
    │       ├── ScreenCaptureKit
    │       └── encoder VideoToolbox
    │
    ├── backend host Windows
    │       ├── driver virtual IddCx
    │       ├── DirectX / D3D11
    │       └── encoder Media Foundation
    │
    └── receptor Apple
            ├── listener con Network.framework
            ├── decoder H.264 con VideoToolbox
            ├── renderer NV12 con Metal
            └── touch / Pencil con UIKit
```

Consulta [ARCHITECTURE.md](docs/ARCHITECTURE.md), [ROADMAP.md](docs/ROADMAP.md), [DMPv1.md](protocol/DMPv1.md), [QUALITY_GATES.md](docs/QUALITY_GATES.md) y el [plan de aceptación nativa](docs/TESTING.es.md).

## Compilar la aplicación de control

Instala Rust estable y ejecuta:

```bash
cargo run -p displaymesh-control
```

## Generar el proyecto para iPhone/iPad

Instala XcodeGen y ejecuta:

```bash
cd platforms/apple-receiver
xcodegen generate
open DisplayMeshReceiver.xcodeproj
```

## Idiomas

- Español: este archivo
- English: [README.md](README.md)

## Política del repositorio

DisplayMesh es una implementación independiente. No se debe copiar branding, arte ni código fuente de OpenDisplay. La interoperabilidad debe basarse en documentación pública de protocolos/APIs y en implementaciones limpias e independientes.
