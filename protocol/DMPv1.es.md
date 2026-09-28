# Protocolo DisplayMesh v1 (DMPv1)

**[English](DMPv1.md) · Español**

Estado: **borrador**.

DMPv1 es el protocolo de sesión de baja latencia entre hosts y receivers DisplayMesh.

## Objetivos

- Interacción de baja latencia.
- Cifrado por defecto.
- Canales de control/input/media separados donde el binding lo permita.
- Negociación de capacidades antes de crear la pantalla.
- Negociación del panel nativo del receiver.
- USB y Wi‑Fi sin confundir medio físico con protocolo.
- Reconexión rápida sin confiar silenciosamente en una identidad nueva.
- Negociación extensible de codecs e input.

## Bindings iniciales

| Medio | Protocolo | Descubrimiento |
| --- | --- | --- |
| Wi‑Fi/LAN | QUIC o TCP | Bonjour + IP |
| Ethernet | QUIC o TCP | Bonjour + IP |
| USB iPhone/iPad | TCP | túnel usbmux |

USB + QUIC no forma parte del binding inicial.

## Sesión

```text
Discovery → Pairing/identidad → Binding → Sesión segura DMP
→ Negociación de capacidades → Panel receiver → Pantalla virtual
→ Video + cursor + input → Telemetría/adaptación
```

El receiver debe anunciar identificador estable de instalación, píxeles físicos, escala, orientación, refresh máximo y capacidades de touch/Pencil antes de que el host cree la pantalla virtual.

### Secuencia por conexión

En TCP, cada dirección reinicia la secuencia DMP en **1** al establecer una conexión nueva y la incrementa por cada frame enviado. Como TCP ya es fiable y ordenado, una secuencia duplicada, repetida o con saltos se trata como error de protocolo y la conexión se cierra en lugar de resincronizarse silenciosamente.

El receiver autorizado devuelve al host, a cadencia limitada, telemetría de decode: FPS, bitrate recibido, tiempo medio de decode, frames descartados, estado de aceleración por hardware y última secuencia de video observada. Esta telemetría no contiene secretos de pairing, contenido de pantalla ni payloads de input.

La ruta de desarrollo macOS ya usa esos FPS/tiempos de decode/descartes para reducir o recuperar de forma acotada el bitrate de VideoToolbox. Un estrés severo también solicita un keyframe de recuperación. El cambio dinámico de raster sigue pendiente.

Las solicitudes de pairing y la espera del descriptor del panel usan timeouts acotados para evitar sesiones colgadas.

### Handshake de identidad de desarrollo

El binding Apple/macOS actual comienza con un challenge aleatorio de 32 bytes creado por el receiver. El host conserva UUID y clave P-256 en Keychain y firma un payload canónico con versión, peer ID/nombre, código de seis dígitos, challenge y clave pública. El receiver verifica firma/challenge antes de mostrar aprobación. Si un peer ID conocido llega con otra clave pública, se rechaza hasta borrar la confianza.

Esto autentica únicamente la **identidad del host de desarrollo**; no sustituye TLS 1.3 ni autentica todavía el receiver ante el host.

El scaffold compartido de capacidades de desarrollo anuncia deliberadamente sólo la ruta implementada de extremo a extremo: **H.264 sobre TCP sin cifrar por Wi‑Fi/LAN**. Reporta cifrado como no disponible. La configuración de producción `SessionConfig::default()` sigue exigiendo cifrado, por lo que debe fallar contra el scaffold de desarrollo en lugar de fingir una sesión segura.

La especificación sigue siendo un contrato de desarrollo: transporte TLS/QUIC, identidad persistente y aceptación end-to-end permanecen sujetos a los gates del roadmap.
