# Roadmap de DisplayMesh

**[English](ROADMAP.md) · Español**

## M0 — Base

- [x] Estructura del repositorio y dominio Rust compartido.
- [x] Validación/negociación de sesión y capacidades.
- [x] Separación medio USB/Wi‑Fi de protocolo QUIC/TCP.
- [x] Framing DMP, modelo de touch, controlador adaptativo y lifecycle de backends.
- [x] Gates de calidad documentados.
- [ ] CI verde en todos los jobs host/receiver.

## M1 — Pantalla nativa

### macOS
- [x] Harness de pantalla virtual por runtime.
- [x] Ruta de desarrollo desde pantalla virtual hacia media receiver.
- [ ] Validación física create/destroy, modos, HiDPI, extend/mirror y panel dinámico.

### Windows
- [x] Bootstrap de Software Device.
- [ ] Driver IddCx, modos, instalación/desinstalación y firma de desarrollo.

### iPhone/iPad receiver
- [x] Descriptor de panel, multitouch/Pencil, Bonjour/TCP, UI, EN/ES/Sistema, pairing, H.264 decode y Metal NV12.
- [ ] Validación física de decode y build firmado/TestFlight.

## M2 — Video end-to-end

- [x] Receiver H.264/Metal y harness de media macOS.
- [ ] Backends productivos completos de captura/encode macOS/Windows.
- [ ] Loopback end-to-end y aceptación 1080p60/1440p60.

## M3 — USB + red

- [ ] Discovery productivo, QUIC/TLS, TCP/TLS, usbmux macOS/Windows, pairing host, handoff Wi‑Fi↔USB.
- [x] Motor de bitrate/raster adaptativo; falta conectarlo a telemetría/encoders reales.

## M4 — Input

- [x] Modelo multitouch y captura iOS.
- [ ] Mapping productivo macOS, touch Windows final, Pencil, teclado y clipboard.

## M5 — Calidad de producto

- [x] EN/ES/Sistema, pairing explícito, estado de seguridad visible y proyecto reproducible del receiver.
- [x] Guard de secuencia/replay por conexión DMP.
- [x] Timeouts de pairing y descriptor de panel en la ruta de desarrollo macOS.
- [x] Telemetría de decode del receiver enviada al host de desarrollo macOS.
- [x] Identidad P-256 persistente del host macOS y verificación del pairing en receiver.
- [ ] Primer uso/permisos, TLS 1.3, identidad mutua de producción, telemetría E2E, updates y firma/notarización.

## M6 — Avanzado

120 Hz, 4K60, HEVC, AV1, HDR, audio y multi-display permanecen planificados.


## Robustez DMP añadida

- [x] Presupuestos de payload DMP por tipo validados desde el header
- [x] Gate de fase/autorización en el receiver
- [x] Intentos de pairing malformado acotados por conexión
- [x] Flags reservados de input rechazados


### Feedback adaptativo de desarrollo

- [x] Telemetría de decode del receiver alimenta el bitrate adaptativo del harness macOS
- [x] VideoToolbox puede ajustar bitrate durante la sesión con histéresis
- [ ] Integrar RTT / cola de envío / pérdida con el controlador adaptativo compartido
- [ ] Aplicar cambios adaptativos de raster sin cambiar la geometría lógica


## Base Windows reforzada

- [x] framing DMP C++ con secuencia y límites de payload
- [x] decoder Windows de input rechaza flags reservados
- [ ] integrar framing DMP al servicio Windows de red/media
- [ ] implementar driver IddCx real y pipeline Media Foundation
