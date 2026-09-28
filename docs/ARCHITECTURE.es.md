# Arquitectura de DisplayMesh

**[English](ARCHITECTURE.md) · Español**

DisplayMesh usa una capa compartida de producto/protocolo y backends nativos de display/media.

## Roles

1. **Host** — macOS o Windows crea una pantalla virtual real, la captura y codifica.
2. **Receiver** — macOS, Windows, iPhone o iPad decodifica/presenta la imagen y puede devolver input.

## Capa compartida

El workspace Rust define estado de sesión, modelo de dispositivos, negociación de capacidades, protocolo, touch/input, bindings de conexión y ciclo de vida de backend.

## Conexiones

Medio y protocolo se negocian por separado:

| Medio | Protocolo |
| --- | --- |
| Wi‑Fi/LAN | QUIC o TCP |
| Ethernet | QUIC o TCP |
| USB iPhone/iPad | TCP mediante usbmux |

USB reutiliza el mismo endpoint lógico DMP del receiver.

## macOS host

Pipeline objetivo:

```text
Pantalla virtual → ScreenCaptureKit → CVPixelBuffer/IOSurface
→ VideoToolbox H.264 → transporte DMP
```

La capa de pantalla virtual se mantiene aislada porque puede depender de interfaces no públicas y debe revalidarse por versión de macOS.

## Windows host

Pipeline objetivo:

```text
IddCx indirect display → D3D11 → Media Foundation H.264 → DMP
```

El driver IddCx tiene un ciclo separado de firma/despliegue.

## iPhone/iPad receiver

```text
Bonjour o usbmux → DMP → VideoToolbox H.264 decode
→ Metal/AVSampleBufferDisplayLayer → multitouch/Pencil → DMP input
```

El receiver anuncia píxeles físicos, escala, orientación, refresh máximo y capacidades de input para que el host cree el modo virtual adecuado.

## Reglas de baja latencia

Hardware encode/decode, colas acotadas, descarte de frames viejos, prioridad para input/control, `TCP_NODELAY`, reducción de bitrate antes de acumular cola y raster adaptativo sin cambiar la geometría lógica.

## Robustez de sesión

La conexión TCP de desarrollo actúa como frontera de sesión: cada dirección reinicia su secuencia DMP en 1, un gap/replay invalida la conexión, pairing y descriptor de panel usan timeouts acotados, y el receiver devuelve telemetría de decode al host para la futura adaptación end-to-end.

## Estado

La arquitectura describe tanto componentes implementados como objetivos. Consulta `ROADMAP.es.md` para distinguir claramente lo disponible de lo pendiente.
