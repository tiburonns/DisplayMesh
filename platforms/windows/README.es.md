# Backend nativo de Windows

**[English](README.md) · Español**

La implementación de Windows se divide en la capa de producto/servicio, bootstrap de Software Device, driver virtual UMDF/IddCx, puente de entrada y el futuro encoder Media Foundation.

## Estado actual

Implementado en código:
- biblioteca nativa de framing/secuencia DMP con presupuestos por tipo
- mailbox latest-frame-wins para mantener latencia acotada

- bootstrap con `SwDeviceCreate`
- paquete de driver UMDF/IddCx en `idd/`
- un monitor virtual DisplayMesh
- 1920×1080 a 60/120 Hz
- 2560×1440 a 60/120 Hz
- 3840×2160 a 60 Hz
- creación D3D11 en el adaptador elegido por Windows
- lifecycle real de adquisición/liberación del swap-chain IddCx
- puente de touch multi-contacto para Windows
- validación CI del hardware ID, paquete, modos y regla de no hacer readback a CPU

Pendiente:
- conectar el bridge driver/GPU con el worker Media Foundation sin readback a CPU

- compilar el driver con un toolchain WDK real
- instalarlo/test-firmarlo en hardware Windows o VM adecuada
- conectar las texturas D3D11 con H.264 de Media Foundation
- modos dinámicos según el receiver
- integrar la sesión DMP autenticada con el inyector táctil
- firma de producción del driver

## Bootstrap

`bootstrap/` enumera el software device `DisplayMeshIdd`; no sustituye al driver.

```powershell
cmake -S platforms/windows/bootstrap -B build/windows-bootstrap
cmake --build build/windows-bootstrap --config Release
```

## Driver IddCx

`idd/` contiene el código fuente real del display driver, INF y proyecto de Visual Studio.

Con Visual Studio 2022 + Windows SDK + WDK:

```powershell
msbuild platforms\windows\idd\DisplayMeshIdd.vcxproj /p:Configuration=Debug /p:Platform=x64
```

El driver mantiene cada frame del escritorio como superficie D3D11 en GPU. La ruta normal evita mapear el frame a memoria de CPU; el siguiente milestone conectará esa textura directamente con el encoder H.264 de Windows.

## Firma de desarrollo

Usa test signing sólo en una PC/VM dedicada de desarrollo. La distribución final requiere el flujo de firma de drivers de producción de Microsoft.
