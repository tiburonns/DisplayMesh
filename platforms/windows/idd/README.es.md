# Driver IddCx de DisplayMesh

Este directorio contiene la base del driver de pantalla virtual UMDF/IddCx para Windows.

Implementado:

- un monitor virtual DisplayMesh
- identidad estable del monitor
- lifecycle de llegada/salida
- 1080p60/120, 1440p60/120 y 4K60
- dispositivo D3D11 usando el adaptador elegido por Windows
- asignación y consumo real del swap-chain IddCx
- hilo acotado para procesar frames
- sin readback de CPU en la ruta normal

El consumidor actual demuestra la recepción real de superficies de escritorio por IddCx y las libera de forma segura. El siguiente paso M2 conecta la textura D3D11 con Media Foundation H.264.

Para compilar se requiere Visual Studio 2022, Windows SDK y WDK.

No está validado todavía en hardware Windows: instalación, Driver Verifier/HLK, carga sostenida 60/120 Hz, encode Media Foundation, modos dinámicos ni firma de producción.
