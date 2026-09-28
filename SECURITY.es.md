# Política de seguridad de DisplayMesh

**Español · [English](SECURITY.md)**

DisplayMesh crea o controla pantallas virtuales, captura contenido de pantalla, recibe entrada y está diseñado para establecer sesiones peer-to-peer cifradas. Por ello, los defectos de seguridad en estas áreas se consideran bloqueadores de release.

## Código soportado

Mientras el proyecto está en desarrollo temprano, el trabajo de seguridad se concentra en `main`. Cuando existan releases empaquetadas, este documento deberá indicar explícitamente qué líneas reciben correcciones.

## Reportar una vulnerabilidad

No abras un issue público si el problema puede exponer contenido de pantalla, credenciales de pairing, entrada remota, instalación de drivers, límites de privilegio o ejecución de código. Usa el reporte privado de vulnerabilidades de GitHub cuando esté disponible.

Incluye versión/commit, plataforma, pasos de reproducción, impacto esperado/observado, requisitos de acceso físico/red y logs redactados.

## Invariantes de seguridad

Una sesión de producción debe:

- usar cifrado por defecto en red;
- exigir confirmación explícita en el primer pairing;
- firmar el challenge nuevo del receiver con la identidad P-256 persistente del host macOS guardada en Keychain y conservar en Keychain las decisiones de confianza del receiver;
- rechazar una clave pública distinta para un peer ID conocido hasta que el usuario borre la confianza;
- invalidar reconexión silenciosa si cambia la identidad del peer;
- rechazar entrada remota hasta autenticar/autorizar al peer;
- fallar explícitamente ante codec/transporte/modo/requisito de seguridad no soportado;
- mantener transportes raw de desarrollo fuera de builds de producción;
- no desactivar protecciones del sistema para instalar drivers;
- aislar compatibilidad privada de macOS del núcleo compartido;
- limitar drivers test-signed de Windows a entornos de desarrollo.

Los logs no deben contener secretos, claves, frames completos, clipboard, teclas o material de autenticación.


## Límite actual de identidad de desarrollo

DisplayMesh 0.2.2 autentica la **identidad del host macOS de desarrollo** durante el pairing mediante P-256 y un challenge nuevo del receiver. Esto evita sustituir silenciosamente la clave de un host ya confiable, pero **no** vuelve seguro para producción el transporte TCP actual: el receiver todavía no presenta una identidad criptográfica autenticada al host y media/control siguen sin cifrado.
