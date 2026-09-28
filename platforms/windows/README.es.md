# Backend nativo de Windows

**[English](README.md) · Español**

La implementación se divide en backend de aplicación, bootstrap de Software Device y un futuro Indirect Display Driver (IddCx).

## Base de protocolo DMP

`protocol/` contiene la base C++ nativa de framing DMPv1 para Windows. Valida header fijo de 16 bytes, IDs de protocolo/mensaje, límites de payload por tipo, tamaños exactos de input/keyframe y secuencia por conexión. Sigue siendo independiente del transporte; aún falta integrarla al servicio Windows de red/media.

```powershell
cmake -S platforms/windows/protocol -B build/windows-protocol
cmake --build build/windows-protocol --config Release
ctest --test-dir build/windows-protocol -C Release --output-on-failure
```

El input bridge también rechaza flags reservados de DMPv1.

## Bootstrap de Software Device

El bootstrap existente crea el software device mediante `SwDeviceCreate`, pero **no** sustituye al display driver.

```powershell
cmake -S platforms/windows/bootstrap -B build/windows-bootstrap
cmake --build build/windows-bootstrap --config Release
```

El siguiente milestone nativo sigue siendo implementar/firmar el driver IddCx que exponga el monitor virtual y sus modos. Los builds de desarrollo pueden usar test signing en máquinas dedicadas; distribución de producción requiere el flujo de firma de Microsoft.
