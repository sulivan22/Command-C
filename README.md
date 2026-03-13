<img width="566" height="289" alt="Captura de pantalla 2026-03-13 a las 9 55 35" src="https://github.com/user-attachments/assets/ae50f8a5-1f1f-48c1-9bd8-46d2793f0d2c" /> <img width="566" height="283" alt="Captura de pantalla 2026-03-13 a las 9 56 45" src="https://github.com/user-attachments/assets/1c64222a-1b27-4651-8cb0-c3a69a2df984" />


# Command-C

Aplicacion de barra de menu para macOS que guarda historial del portapapeles y permite reutilizar texto, codigo, imagenes, enlaces y rutas de archivos.

## Estado

- Plataforma: macOS (SwiftUI + AppKit)
- Minimo: macOS 13.5
- Build validado en local con `xcodebuild` (Debug)

## Caracteristicas

- Captura automatica del portapapeles (texto, codigo, URL, imagen, archivo)
- Interfaz de popover en la barra de menu
- Busqueda en historial
- Filtros por tipo de contenido
- Categorias personalizadas
- Fijar/desfijar elementos (`pin`)
- Copiar de nuevo cualquier item al portapapeles
- Arranque automatico opcional al iniciar sesion

## Estructura del proyecto

- `Command-C.xcodeproj`: proyecto Xcode principal
- `Porta papeles/`: vistas SwiftUI, AppDelegate, assets y entrypoint
- `ClipboardManager.swift`: modelo de datos, persistencia y monitor del portapapeles

## Requisitos

- Xcode 16 o superior
- macOS 13.5 o superior

## Como ejecutar

1. Clona el repositorio:

```bash
git clone https://github.com/TU_USUARIO/command-c.git
cd command-c
```

2. Abre el proyecto:

```bash
open Command-C.xcodeproj
```

3. En Xcode:
- Selecciona el target `Command-C`
- Configura tu `Team` en Signing
- Si vas a distribuir, cambia `PRODUCT_BUNDLE_IDENTIFIER` por uno propio
- Ejecuta (`Run`)

## Build por terminal

```bash
xcodebuild -project "Command-C.xcodeproj" \
  -scheme "Command-C" \
  -configuration Debug \
  -sdk macosx \
  -derivedDataPath /tmp/Command-C-Derived \
  CODE_SIGNING_ALLOWED=NO \
  build
```

## Persistencia de datos

- Metadatos del historial: `UserDefaults`
- Imagenes copiadas: carpeta `Application Support/<bundle-id>/Clips`

## Privacidad

- No usa backend remoto ni servicios de terceros
- Todo el historial se mantiene en local

## Licencia

Este proyecto usa licencia MIT. Consulta el archivo [LICENSE](LICENSE).

