# Backend nativo de Windows

**[English](README.md) · Español**

La implementación se divide en backend de aplicación, bootstrap de Software Device y un futuro Indirect Display Driver (IddCx).

El bootstrap existente crea el software device mediante `SwDeviceCreate`, pero **no** sustituye al display driver.

```powershell
cmake -S platforms/windows/bootstrap -B build/windows-bootstrap
cmake --build build/windows-bootstrap --config Release
```

El siguiente milestone nativo sigue siendo implementar/firmar el driver IddCx que exponga el monitor virtual y sus modos. Los builds de desarrollo pueden usar test signing en máquinas dedicadas; distribución de producción requiere el flujo de firma de Microsoft.
