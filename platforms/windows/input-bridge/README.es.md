# DisplayMesh Windows Input Bridge

**[English](README.md) · Español**

Este componente convierte muestras touch binarias DMP de 40 bytes en input real de Windows mediante APIs Win32.

```powershell
cmake -S platforms/windows/input-bridge -B build/input-bridge
cmake --build build/input-bridge --config Release
ctest --test-dir build/input-bridge -C Release --output-on-failure
```

La integración productiva deberá recibir frames autenticados, decodificar la muestra, resolver el rectángulo del monitor virtual IddCx e inyectar contactos. El CLI actual existe para pruebas de desarrollo.

Pencil todavía reutiliza la ruta touch; synthetic pen dedicado sigue como milestone futuro.
