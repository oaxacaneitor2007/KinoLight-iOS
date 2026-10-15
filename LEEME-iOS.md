# Kino Tv (demo) — port a iOS

Port a SwiftUI de [kino-light](https://github.com/kinotvapp/kino-light) (Android, Kotlin + Compose).
Licencia del código: Apache-2.0 (ver `LICENSE`). **El nombre "Kino" y su logo no están licenciados** (ver `NOTICE`).

## Qué se portó

| Android | iOS |
|---|---|
| Jetpack Compose | SwiftUI (iOS 16+) |
| media3 ExoPlayer + controles propios | AVPlayer + controles propios (progreso con búfer, ±10 s, auto-ocultar, reintentar, rotar) |
| Coil | `AsyncImage` + pósters locales del bundle |
| Drawer / NavigationRail | `TabView` (Inicio, Categorías, Acerca de) |
| `home.json`, `assets/posters` | los mismos archivos en `Resources/` |
| Logo (Path de Compose) | `Canvas` con las mismas coordenadas |

## Qué NO se portó (a propósito)

- **UI de Android TV** (`ui/tv/*`, `TvApp`, D-pad): no aplica en iPhone/iPad.
- **Actualización OTA por APK** (`com.arkiv.player.data.update`, WorkManager, FileProvider, permiso de instalar paquetes): iOS no permite instalar binarios fuera de la App Store, y Apple lo prohíbe.
- Pantallas "de adorno" que ya eran de muestra en Android.
- La animación de inicio es una versión simplificada (el logo aparece y hace zoom/fundido; no hay la transición anillo → "o").
- Se quitó la línea de "Códigos de Downloader" de Acerca de (es de Android TV).

## Compilar con Mac

```bash
brew install xcodegen
xcodegen generate
open KinoLight.xcodeproj
```
En Xcode: target **KinoLight → Signing & Capabilities**, elige tu Team y cambia el Bundle Identifier. Run en tu iPhone.

## Compilar sin Mac (GitHub Actions)

1. Sube esta carpeta a un repositorio de GitHub.
2. Pestaña **Actions → Build IPA (sin firmar) → Run workflow**.
3. Descarga el artefacto `KinoLight-unsigned-ipa`.

Ese `.ipa` **no está firmado**: no se instala tal cual. Para instalarlo en tu iPhone, fírmalo con tu Apple ID usando
Sideloadly o AltStore (con cuenta gratuita caduca a los 7 días; con Apple Developer, 99 USD/año, puedes usar TestFlight).

## Nota sobre pruebas

Este port se escribió sin poder compilarlo en Xcode (el entorno no es macOS). Si el primer build marca algún error de
sintaxis o de API, pásame el mensaje y lo corrijo.
