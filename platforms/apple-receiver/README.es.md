# DisplayMesh Apple Receiver (iPhone / iPad)

**[English](README.md) · Español**

Este target convierte un iPhone o iPad en receiver interactivo para un host DisplayMesh.

Objetivos: escritorio extendido real, USB/Wi‑Fi, resolución Retina, portrait/landscape, decode H.264 de baja latencia, multitouch, Apple Pencil, scroll, reporte de capacidades, pairing cifrado y reconexión.

El receiver escucha un endpoint TCP DMP. En Wi‑Fi se anuncia por Bonjour; en USB el host alcanza el mismo puerto mediante usbmux. El receptor no requiere ExternalAccessory/MFi para este diseño.

Actualmente existen UI de receiver, captura touch/Pencil, framing, pairing de desarrollo, decode VideoToolbox H.264, render Metal NV12 y tests de protocolo. La validación física firmada y la integración host productiva completa siguen siendo gates separados.


## Preflight de TestFlight

Consulta [TESTFLIGHT.es.md](TESTFLIGHT.es.md) para la ruta de aceptación interna del receiver.
