# DisplayMesh

DisplayMesh es un proyecto de pantalla virtual multiplataforma para **macOS y Windows**.

El objetivo es permitir que una computadora funcione como un monitor secundario real para otra computadora a través de la red local, manteniendo una interfaz y modelo de sesión compartidos y usando backends nativos para cada sistema operativo.

> **`main` actual: 0.1.2.** Estado: desarrollo inicial. La app de control ahora valida únicamente configuraciones de desarrollo compatibles con las capacidades actuales y ofrece interfaz Sistema/English/Español. La integración real del monitor virtual y el transporte de video siguen siendo hitos activos.

## Capacidades previstas

- Extender o duplicar el escritorio
- macOS ↔ Windows, macOS ↔ macOS y Windows ↔ Windows
- H.264 acelerado por hardware inicialmente; HEVC/AV1 después
- LAN/Wi-Fi y conexiones cableadas
- Resoluciones compatibles con HiDPI / Retina
- Mouse, teclado, scroll y touch
- Bitrate, FPS y resolución adaptativos
- Emparejamiento y sesiones cifradas
- Interfaz en inglés, español e idioma del sistema

## Arquitectura

```text
apps/control
    │
    ├── displaymesh-core
    │       ├── modelo de dispositivos y sesiones
    │       ├── negociación de capacidades
    │       └── abstracción del backend
    │
    ├── backend nativo de macOS
    │       ├── monitor virtual
    │       ├── ScreenCaptureKit
    │       ├── VideoToolbox
    │       └── Metal
    │
    └── backend nativo de Windows
            ├── driver virtual IddCx
            ├── DXGI / D3D11
            ├── Media Foundation
            └── DirectComposition / D3D11
```

Consulta [ARCHITECTURE.md](docs/ARCHITECTURE.md), [ROADMAP.md](docs/ROADMAP.md), [DMPv1.md](protocol/DMPv1.md) y el [plan de aceptación nativa](docs/TESTING.es.md).

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
