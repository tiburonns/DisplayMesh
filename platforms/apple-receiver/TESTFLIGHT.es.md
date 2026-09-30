# DisplayMesh Receiver 0.2.3 — Preflight de TestFlight

El receiver de iPhone/iPad puede probarse mediante TestFlight antes de que todo DisplayMesh esté listo para producción. Esto **no** convierte el transporte TCP sin cifrar en una función segura de producción.

## Gates de código

- Proyecto generado 0.2.3 (build 3).
- Paridad English/Español/Sistema.
- Privacy Manifest con required reason de UserDefaults.
- Builds Release para Simulator e iPhoneOS.
- Tests de protocolo/video/input.
- Decoder H.264 VideoToolbox + renderer Metal NV12.
- Pairing explícito antes de autorizar video/input.
- Challenge nuevo del receiver + identidad P-256 persistente y firmada del host macOS.
- El trust store en Keychain detecta reemplazo de identidad y permite borrar explícitamente equipos confiables.
- Verificar que un cambio de identidad del host se rechaza hasta borrar las computadoras confiables.

## Gates físicos

- Instalar en iPhone y iPad.
- Verificar que la explicación de primer uso aparezca antes del prompt de Red local.
- Aceptar Red local y verificar Bonjour.
- Relanzar y confirmar que la explicación no se repita después de aceptarla.
- Negar Red local una vez, comprobar que el fallo del listener sea recuperable, usar **Abrir Ajustes**, habilitar acceso, volver a DisplayMesh y verificar que **Reintentar** inicia el listener.
- Emparejar con el media harness de macOS.
- Verificar decode, keyframe recovery, rotación, diagnósticos y touch/Pencil.
- Mantener 1080p60 al menos 15 minutos sin crecimiento persistente de cola.
- Repetir 1440p60 en hardware compatible.
- Probar background/foreground y recuperación del idle timer.

## Preflight local

Ejecuta `./platforms/apple-receiver/preflight-testflight.sh` desde la raíz. Valida recursos, regenera el proyecto, ejecuta unit tests y compila Release para Simulator e iPhoneOS tratando warnings como errores.

## Export compliance

El receiver ahora contiene código CryptoKit para identidad P-256 persistente y una implementación de sesión segura en preparación basada en P-256 ECDH / HKDF-SHA256 / ChaCha20-Poly1305. No se debe fijar una exención de export compliance en el plist antes de la primera subida.

Para el primer TestFlight, deja `ITSAppUsesNonExemptEncryption` sin definir y responde el cuestionario de cifrado de App Store Connect según la build realmente enviada y las regiones de distribución. Después de que Apple determine si este uso es exento o requiere documentación, registra el resultado y sólo entonces añade la clave/código correspondiente para futuras releases.

## Archive

Genera el proyecto con XcodeGen 2.46.0, ábrelo en Xcode 26+, selecciona tu Team de pago, Archive, Validate App y súbelo a **Internal TestFlight**.

El receiver sigue siendo candidato interno/de desarrollo mientras DMP use TCP sin cifrar. La distribución de producción continúa bloqueada por `docs/QUALITY_GATES.md`.
