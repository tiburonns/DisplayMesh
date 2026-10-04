# DisplayMesh 0.2.3 — Plan de aceptación nativa

**Español** · [English](TESTING.md)

DisplayMesh no está listo para release hasta que ambos backends nativos y una ruta de video de extremo a extremo funcionen en hardware real. El CI puede compilar Rust y los harnesses de prueba, pero no puede demostrar el comportamiento privado de pantalla en macOS, la instalación del driver de Windows, encode/decode por GPU ni la latencia interactiva.

## Puerta de monitor virtual en macOS

En cada versión de macOS soportada:

1. Compila `platforms/macos/harness`.
2. Crea monitores virtuales 1920×1080@60 y 2560×1440@60.
3. Confirma que aparezcan en Ajustes del Sistema y puedan usarse como escritorio extendido.
4. Mueve ventanas al monitor y verifica render estable.
5. Elimina el monitor y confirma que desaparezca sin cerrar sesión ni reiniciar.
6. Repite crear/eliminar al menos cinco veces.
7. Prueba HiDPI donde sea compatible.

Cualquier actualización de macOS que cambie o elimine las clases/selectores privados bloquea release hasta revalidar compatibilidad.

## Puerta de monitor virtual en Windows

En un equipo de prueba dedicado:

1. Instala el driver de desarrollo IddCx de DisplayMesh con firma de prueba.
2. Ejecuta el bootstrap de software device.
3. Confirma adaptador y monitor virtual sin errores en Administrador de dispositivos.
4. Valida 1920×1080@60 y los modos adicionales publicados por el driver.
5. Extiende el escritorio al monitor virtual.
6. Cierra el bootstrap y confirma salida limpia del monitor.
7. Desinstala el driver y confirma que no queden dispositivos obsoletos.

Los paquetes de producción no deben requerir el modo de test-signing de Windows.

## Puerta de video

Para combinaciones macOS/Windows como emisor y receptor:

- capturar sólo el monitor virtual previsto
- H.264 por hardware cuando esté disponible
- decodificar/renderizar sin copias CPU innecesarias en estado estable
- mantener relación de aspecto y color
- recuperarse de desconexión/reconexión
- mostrar FPS, bitrate, RTT y frames perdidos medidos

Objetivo mínimo inicial: 1080p60 estable en una red local ordinaria.

## Puerta de sesión/seguridad

- El primer emparejamiento requiere confirmación explícita y expira si queda sin responder.
- La espera de pairing y descriptor de panel termina con timeout en vez de quedar colgada indefinidamente.
- Cada conexión TCP reinicia la secuencia DMP en 1; frames duplicados, repetidos o con saltos se rechazan.
- La telemetría de decode llega al host sin incluir secretos, frames de pantalla ni payloads de input.
- El host macOS de desarrollo conserva su identidad P-256 en Keychain.
- El receiver Apple conserva en Keychain las identidades aceptadas; un fallo de persistencia debe impedir la autorización.
- La firma de pairing queda ligada al challenge nuevo del receiver y al código de seis dígitos mostrado.
- Una clave pública distinta para un peer ID ya conocido se rechaza hasta borrar explícitamente la confianza.
- Un cambio de identidad invalida la reconexión silenciosa.
- Codec/transporte/modo incompatible falla explícitamente; sin downgrade silencioso.
- Las sesiones de red usan transporte cifrado.
- El input remoto se ignora antes de autenticar/autorizar.
- Logs compartibles no incluyen secretos, frames, portapapeles ni teclas.

## Puerta de input

Mouse, botones, scroll y teclado deben probarse en macOS→Windows y Windows→macOS antes de marcarse completos. Touch/stylus requieren hardware compatible.

## Resultado

Una build puede llamarse preview utilizable sólo cuando creación del monitor virtual, transporte de video y cierre limpio funcionen en al menos una Mac y una PC Windows soportadas. Una release de producción requiere además firma/notarización/firma de driver adecuadas para cada sistema.


## Aceptación de guardrails de protocolo/sesión

Antes de aprobar rendimiento en hardware, verifica que las pruebas deterministas cubran:

- presupuestos de payload por tipo y tamaños exactos de input (40 bytes) / keyframe request (vacío);
- rechazo coherente de flags DMP reservados en Rust, Swift y Windows;
- rechazo de gaps/replays de secuencia por conexión;
- admisión del receiver según fase y pairing malformado acotado;
- validación de capabilities y descriptor de panel antes de video;
- Bonjour genérico y rechazo de reemplazo de una sesión activa;
- golden frame y tracker de secuencia del framing DMP Windows.

Estos checks endurecen la ruta plaintext de desarrollo, pero no sustituyen el gate TLS de producción.


## Gate de agotamiento de secuencia

- Cada conexión inicia en secuencia 1.
- Gaps y replays deben rechazarse.
- Tras aceptar o emitir `0xFFFFFFFF`, la conexión debe cerrarse antes de enviar otro frame; nunca se permite wrap a 0 dentro de la misma sesión autenticada.
