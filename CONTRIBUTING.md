# Contribuir a Command-C

Gracias por querer contribuir.

## Flujo recomendado

1. Crea una rama desde `main`
2. Haz cambios pequenos y enfocados
3. Compila antes de abrir PR
4. Abre un Pull Request con contexto tecnico claro

## Convenciones

- Mantener compatibilidad con macOS 13.5+
- Evitar dependencias externas innecesarias
- Priorizar cambios pequenos, legibles y testeables
- Respetar el estilo Swift existente

## Comprobacion local minima

```bash
xcodebuild -project "Command-C.xcodeproj" \
  -scheme "Command-C" \
  -configuration Debug \
  -sdk macosx \
  -derivedDataPath /tmp/Command-C-Derived \
  CODE_SIGNING_ALLOWED=NO \
  build
```

## Reporte de issues

Incluye:

- Version de macOS
- Version de Xcode
- Pasos para reproducir
- Resultado esperado vs actual
- Capturas o logs si aplica

