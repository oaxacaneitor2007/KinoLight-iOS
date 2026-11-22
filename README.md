# Kino TV — iOS (SwiftUI)

Port nativo de la app Android `com.arkiv.player.light` (Kino TV 0.9.64): reproductor que consume
addons de Stremio. Fuente de plugins: GitHub -> archive.org -> jsDelivr -> catalogo incluido
(`KinoTV/Resources/plugin-catalog-seed.json`), con cache de 6 h. No existe comprobacion ni aviso de
actualizacion de la app.

## Que es codigo generado y que requiere macOS
| Parte | Donde se hace |
|---|---|
| Codigo Swift/SwiftUI, `project.yml`, recursos, workflow | Ya generado en este zip (cualquier SO) |
| `xcodegen generate` -> `KinoTV.xcodeproj` | macOS (lo hace el workflow) |
| Compilar Swift, enlazar, `.app` | macOS + Xcode (runner `macos-14` de GitHub) |
| Empaquetar `.ipa` (carpeta `Payload/` + zip) | El workflow |
| Firma | NO incluida: el `.ipa` sale sin firmar |

## Estructura
```
KinoTV-iOS/
├── project.yml                      # XcodeGen (bundle id, iOS 16, Info.plist)
├── .gitignore
├── README.md
├── .github/workflows/build-ipa.yml  # CI: genera proyecto, compila, empaqueta IPA
└── KinoTV/
    ├── App/KinoTVApp.swift
    ├── Core/    Models, Http, PluginStore, Stremio, ContinueStore, Subtitles
    ├── Views/   RootView, HomeView, SearchView, DetailView, StreamsView, PlayerModel, PlayerScreen, PosterCard
    └── Resources/ plugin-catalog-seed.json, Assets.xcassets (AppIcon 1024)
```

## Cambiar bundle ID / nombre
En `project.yml`: `PRODUCT_BUNDLE_IDENTIFIER` (hoy `com.example.kinotv`) y `CFBundleDisplayName`.

## Instalar el .ipa sin firmar
Un IPA sin firmar no se instala directo. Firmalo al instalar con AltStore, Sideloadly o similar
(Apple ID gratis: caduca a los 7 dias), o firmalo con tu certificado de desarrollador.

## Lo que se elimino a proposito (no existe en iOS o no aplica)
Cast/DLNA, servicios en primer plano, instalacion de paquetes/APK, camara/QR, Sentry/telemetria,
notificaciones, descargas, UpdateWorker (actualizacion de la app), Room/WorkManager, perfiles.

## Limites conocidos
- Solo addons de Stremio. Los plugins `repo` de Kino (JavaScript en QuickJS) no se portan.
- Solo enlaces directos HTTP(S); sin torrents (`infoHash`).
- AVPlayer reproduce HLS/MP4/MOV/audio; MKV/AVI/WebM suelen fallar (van al final y hay cambio automatico de fuente).
- Addons marcados `adult` o que requieren configuracion se omiten.
- Subtitulos externos (SRT/VTT, espanol e ingles) se dibujan como capa propia.
- El codigo NO se compilo antes de entregarlo (no habia Xcode): el primer run del workflow puede
  arrojar errores de compilacion que hay que corregir con el log (`build-log` en Artifacts).
