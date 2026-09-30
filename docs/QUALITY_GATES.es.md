# Gates de calidad de DisplayMesh

**[English](QUALITY_GATES.md) · Español**

Una capacidad no se considera completa sólo porque exista un control de UI. Para describirla como **disponible** deben cumplirse todos estos puntos:

1. backend real de plataforma;
2. UI conectada al backend;
3. estados de fallo visibles/recuperables;
4. pruebas automatizadas del comportamiento determinista;
5. prueba manual de hardware para comportamiento específico;
6. strings de usuario completos en inglés y español;
7. accesibilidad para controles no textuales;
8. diagnósticos capaces de identificar la capa que falla sin exponer secretos.

Si falla cualquiera de estos gates, la capacidad debe etiquetarse como desarrollo/planificada.

## Receiver

Debe ocupar la superficie completa, adaptarse a orientación, soportar Sistema/English/Español, reportar capacidades de panel, exigir autorización de peers nuevos, rechazar tráfico útil antes de autorización, mantener la pantalla despierta sólo durante una sesión conectada y autorizada, mostrar fallos de conexión/protocolo y usar presentación **latest-frame-wins** para que un bloqueo temporal de UI no acumule una cola de video obsoleta.

## Host

Debe crear/destruir la pantalla virtual de forma limpia, capturar sólo la pantalla prevista, cerrar recursos en orden, propagar fallos y no presentar harnesses de desarrollo como backends de producción.

## Release

El receiver Apple debe compilar en **Release** para iOS Simulator e iPhoneOS tratando warnings como errores, además de pasar sus tests de protocolo/video/input y validación de recursos.

No se considera release-ready el producto completo mientras falten validaciones de hardware del backend nativo, transporte seguro, firma/entitlements y pruebas de latencia/resolución anunciadas. El receiver puede usarse como candidato de **Internal TestFlight** bajo las limitaciones documentadas.
