# DisplayMesh

DisplayMesh es un proyecto de pantalla virtual multiplataforma para **hosts macOS y Windows**, con **iPhone y iPad como receptores**.

El objetivo es permitir que una computadora cree una pantalla extendida real y la transmita a otra computadora o dispositivo Apple mediante **USB o Wi-Fi**, manteniendo baja latencia, alta resolución e interacción táctil.

> **`main` actual: 0.2.3.** El receptor Apple incluye la ruta real H.264 de baja latencia (paquete DMP → Annex-B → VideoToolbox → NV12 → Metal), decode acotado, recuperación por keyframe, diagnósticos e interfaz Sistema/English/Español. La ruta Apple↔macOS ya usa identidades P-256 persistentes mutuas, ECDH P-256 efímero firmado, HKDF-SHA256 y ChaCha20-Poly1305 para proteger todos los frames DMP posteriores al pairing; el tráfico plaintext posterior al pairing falla cerrado. La telemetría de colas/decode, bitrate/raster adaptativos y las sondas RTT cifradas están conectadas al harness macOS. Windows ya incluye la base IddCx/D3D11 y un adaptador/coordinador asíncrono concreto de Media Foundation. Siguen pendientes validación WDK real, cablear IddCx→NV12→MFT en vivo, USB, revisión independiente de seguridad y aceptación end-to-end en hardware.

## Estado de capacidades

Las listas siguientes separan el código que existe en `main` de los objetivos del producto. Una capacidad no se considera lista para release hasta pasar su gate de aceptación en hardware de [docs/TESTING.es.md](docs/TESTING.es.md).

### Implementado en `main`

- Receptor para iPhone/iPad con decode H.264 de baja latencia mediante VideoToolbox, presentación NV12 con Metal, reporte de capacidades del panel, captura de muestras touch/Pencil, diagnósticos e interfaz English/Español/Sistema.
- Ruta de desarrollo macOS que crea un monitor virtual temporal real, lo captura con ScreenCaptureKit, codifica H.264 con VideoToolbox y lo transmite al receptor Apple mediante la ruta DMP LAN/TCP actual.
- Identidades P-256 persistentes, ECDH P-256 efímero firmado, HKDF-SHA256 y ChaCha20-Poly1305 para proteger el tráfico DMP posterior al pairing entre Apple y macOS.
- Trabajo de decode/presentación acotado, descarte de frames obsoletos, recuperación por keyframe, telemetría del receptor, sondas RTT cifradas y control adaptativo de bitrate/raster.

### Base implementada; validación de release pendiente

- Base de monitor virtual IddCx/D3D11 para Windows y adaptador/coordinador asíncrono de Media Foundation.
- 1080p60 y 1440p60 son objetivos actuales de aceptación, no afirmaciones universales de rendimiento; aún requieren mediciones end-to-end en hardware representativo.
- El comportamiento real de Windows, despliegue/firma WDK y la integración IddCx → NV12 → Media Foundation en vivo siguen siendo gates de release.

### Objetivos del producto / todavía no listos para producción

- USB a iPhone/iPad mediante usbmux.
- Rutas completas macOS ↔ Windows, macOS ↔ macOS y Windows ↔ Windows.
- Modo duplicado listo para producción y mapeos completos de mouse/teclado/touch a nivel de sistema en cada host soportado.
- HEVC / AV1 donde el hardware lo permita.
- 4K60 y 120 Hz después de validar la ruta completa de monitor virtual, captura, codec, transporte, decoder, renderer y panel.

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

| Conexión | Modelo de protocolo | Estado actual |
| --- | --- | --- |
| Wi-Fi / LAN | TCP actualmente; QUIC permanece como opción arquitectónica | La ruta de desarrollo receptor Apple ↔ macOS está conectada |
| Ethernet | TCP / QUIC futuro | Usa el mismo modelo LAN; la aceptación end-to-end del producto sigue pendiente |
| USB a iPhone/iPad | TCP mediante usbmux | Arquitectura objetivo; todavía no está conectado como ruta de producción |

La tabla describe el modelo de transporte, no afirma que todos los enlaces estén listos para release. USB sigue siendo un blocker de release en `main`.

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


## Ruta end-to-end de desarrollo en macOS

Ahora existe un script de orquestación que une el harness de pantalla virtual con el harness de ScreenCaptureKit/VideoToolbox:

```bash
scripts/run-macos-virtual-session.sh --host <ip-del-iphone-o-ipad>
```

Crea una pantalla virtual temporal de DisplayMesh, captura exactamente esa pantalla, codifica H.264 de baja latencia, la transmite al receptor Apple y elimina la pantalla virtual al salir. El binding TCP queda protegido después del pairing mediante la sesión segura autenticada de DMP. Sigue siendo una ruta de desarrollo hasta completar revisión independiente de seguridad, integración de host/USB y aceptación en hardware.

## Contacto, soporte y feedback

¿Tienes una **duda**, **sugerencia**, encontraste un **error** o quieres compartir **feedback** sobre DisplayMesh? Usa el formulario de GitHub Issues del proyecto:

**[Abrir formulario de contacto y feedback](https://github.com/tiburonns/DisplayMesh/issues/new?template=feedback.yml)**

Selecciona la categoría que mejor corresponda: **Duda, Sugerencia, Error, Feedback, Compatibilidad u Otro**. Incluye la versión de la app, dispositivo/sistema y pasos para reproducir el problema cuando aplique.

No publiques contraseñas, tokens, claves, direcciones privadas ni otra información personal sensible. Para vulnerabilidades de seguridad, utiliza el proceso indicado en `SECURITY.md` cuando esté disponible.

