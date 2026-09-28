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

Las solicitudes de pairing y la espera del descriptor del panel usan timeouts acotados para evitar sesiones colgadas.

La especificación sigue siendo un contrato de desarrollo: transporte TLS/QUIC, identidad persistente y aceptación end-to-end permanecen sujetos a los gates del roadmap.
