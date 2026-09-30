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


## Scheduler bounded de encode

`media-harness/BoundedEncodeWorker` define la política de baja latencia del futuro encoder Windows. Sólo puede existir un frame pendiente mientras otro se procesa; un frame nuevo reemplaza al pendiente anterior, se rechazan secuencias obsoletas, el shutdown descarta trabajo pendiente y una excepción del handler no mata el worker.

Es una base de scheduling, no una afirmación de que la textura IddCx ya llegue a Media Foundation. Falta transportar la superficie/handle D3D11 compartida sin readback a CPU y packetizar la salida H.264 en DMP.


## Packetizer H.264 Annex-B

`media-harness/H264AnnexBPacketizer` valida access units Annex-B y genera el mismo header DMP de video de 16 bytes que consume el receiver Apple. Mantiene cache SPS/PPS, repara un IDR que no los incluya cuando existe estado válido, normaliza start codes, respeta el presupuesto DMP y falla antes de emitir un keyframe no recuperable si faltan parameter sets.

Es una pieza determinista e independiente del hardware. Falta alimentar este packetizer con la salida real del encoder Media Foundation y envolver el payload resultante en la sesión DMP autenticada.


## Admisión de sesión host

`protocol/DmpHostSessionGate` replica las reglas de fase DMP del host usadas por la ruta de desarrollo macOS. Input y video permanecen cerrados hasta aceptar hello, enviar pairing, aceptar su respuesta, validar capabilities y aceptar el descriptor de panel. Los tipos inesperados fallan en cerrado y un reset vuelve a bloquear input/video inmediatamente.

Es una frontera de admisión/estado, **no** la implementación criptográfica de pairing Windows. El futuro servicio de red Windows debe validar identidad/pairing antes de avanzar este gate y sólo entonces entregar payloads de input validados al inyector nativo.


## Routing de input condicionado por sesión

`input-bridge/DmpInputRouter` une el gate de admisión del protocolo con el decoder de input de 40 bytes. Incluso un sample touch estructuralmente válido se rechaza mientras la sesión host no esté en `streaming`; frames que no sean input y los flags reservados del payload DMP Input también se rechazan antes de la inyección.

La integración pendiente es el servicio real de red/pairing Windows: deberá avanzar `DmpHostSessionGate` sólo después de validar identidad/pairing/capabilities, decodificar frames con la biblioteca DMP nativa y entregar únicamente input autorizado a `TouchInjector`.
