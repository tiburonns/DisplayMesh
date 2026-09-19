# DisplayMesh Legacy Receiver

Receptor separado para dispositivos Apple de 32 bits con **iOS 9**, incluido el iPad 3.

## Alcance

- proyecto Objective-C/UIKit sin SwiftUI ni `Network.framework`;
- framing DMPv1 sobre TCP, puerto 49655;
- Bonjour `_displaymesh._tcp`;
- autorización explícita de cada conexión;
- descriptor de panel y eventos multitáctiles normalizados;
- video JPEG con descarte de cuadros atrasados mediante el perfil `legacy-ios9-jpeg`.

El perfil JPEG es un fallback heredado y no sustituye el objetivo H.264 del receptor moderno. El host debe negociar explícitamente `legacy-ios9-jpeg` y enviar cada imagen JPEG completa como payload de un frame DMP `video` (`0x10`).

## Seguridad

iOS 9 no ofrece las primitivas modernas previstas por DMPv1 para TLS 1.3. Esta edición exige confirmación visible por conexión, pero el flujo TCP no está cifrado. Úsala exclusivamente mediante un túnel USB/usbmux o una LAN aislada y de confianza. Nunca la expongas a Internet.

## Compilación para jailbreak (recomendada)

Con [Theos](https://theos.dev/) y el SDK parcheado `iPhoneOS9.3.sdk`:

```sh
export THEOS=/ruta/a/theos
make clean package FINALPACKAGE=1
```

El resultado aparece en `packages/` como un paquete `iphoneos-arm`. Instálalo en el dispositivo con `dpkg -i paquete.deb` y después ejecuta `uicache`. La aplicación se instala en `/Applications/DisplayMeshLegacy.app` y no necesita AppSync.

## Compilación con Xcode histórico

Se requiere Xcode 8.3.3 con el SDK y linker armv7. El proyecto compatible ya está incluido: abre `DisplayMeshLegacy.xcodeproj`, configura el equipo de firma y ejecuta el target sobre el dispositivo. No lo regeneres con una versión moderna de XcodeGen, ya que elevaría el formato. El Xcode actual puede validar el código en Simulator, pero ya no produce el binario armv7 instalable.
