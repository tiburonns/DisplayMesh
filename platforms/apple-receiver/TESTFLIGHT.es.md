# DisplayMesh Receiver 0.2.2 — Preflight de TestFlight

El receiver de iPhone/iPad puede probarse mediante TestFlight antes de que todo DisplayMesh esté listo para producción. Esto **no** convierte el transporte TCP sin cifrar en una función segura de producción.

## Gates de código

- Proyecto generado 0.2.2 (build 3).
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
- Aceptar Local Network y verificar Bonjour.
- Emparejar con el media harness de macOS.
- Verificar decode, keyframe recovery, rotación, diagnósticos y touch/Pencil.
- Mantener 1080p60 al menos 15 minutos sin crecimiento persistente de cola.
- Repetir 1440p60 en hardware compatible.
- Probar background/foreground y recuperación del idle timer.

## Preflight local

Ejecuta `./platforms/apple-receiver/preflight-testflight.sh` desde la raíz. Valida recursos, regenera el proyecto, ejecuta unit tests y compila Release para Simulator e iPhoneOS tratando warnings como errores.

## Export compliance

El receiver usa CryptoKit de Apple para verificar firmas P-256 y no implementa un algoritmo de cifrado propio. El plist actual declara `ITSAppUsesNonExemptEncryption = NO` porque esta build sólo usa criptografía exenta provista por Apple. Hay que reevaluarlo si cambia el cifrado de transporte o se añade criptografía propia/de terceros.

## Archive

Genera el proyecto con XcodeGen 2.46.0, ábrelo en Xcode 26+, selecciona tu Team de pago, Archive, Validate App y súbelo a **Internal TestFlight**.

El receiver sigue siendo candidato interno/de desarrollo mientras DMP use TCP sin cifrar. La distribución de producción continúa bloqueada por `docs/QUALITY_GATES.md`.
