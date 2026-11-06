# iOS-Port von Boorusphere

Dieser Fork baut eine **unsignierte IPA** über GitHub Actions (kein Mac nötig).

## Bauen

1. Fork auf GitHub pushen (öffentliches Repo = kostenlose macOS-Runner).
2. Actions → **Build iOS (unsigned IPA)** → *Run workflow* (oder Push auf den Branch `ios-port`).
3. Artefakt `boorusphere-unsigned-ipa` herunterladen und entpacken → `boorusphere-unsigned.ipa`.

Der Workflow ruft `tool/ios_setup.sh` auf. Das Skript erzeugt `ios/` mit `flutter create`
und patcht danach AppDelegate (flutter_downloader), Info.plist, Podfile und das App-Icon.
`ios/` wird deshalb nicht eingecheckt.

## Installieren (ohne Mac)

- **AltStore PAL (EU)** installieren → darüber **AltStore Classic** installieren → in Classic die `.ipa`
  öffnen. Signiert wird mit der eigenen Apple-ID (Free-Account: 7 Tage Laufzeit, 3 Apps), Classic
  erneuert die Signatur im Hintergrund.
- Alternativ SideStore, oder Sideloadly unter Windows.

## Was auf iOS anders ist

| Bereich | Android | iOS |
| --- | --- | --- |
| Version / `sdkVersion` | Pigeon `AppEnv` (Kotlin) | `package_info_plus`, `sdkVersion = 99` |
| Download-Ordner | öffentlicher Downloads-Ordner (Pigeon `StorageUtil`) | App-Ordner `Documents/Boorusphere`, sichtbar in der Dateien-App |
| Datei öffnen | Intent (Pigeon `StorageUtil`) | `open_filex` |
| Medien-Scan, „Medien verstecken" | `media_scanner`, `.nomedia` | entfällt (Einstellung ausgeblendet) |
| Benachrichtigungs-Berechtigung für Downloads | wird abgefragt | wird nicht abgefragt |
| In-App-Updater (APK) | aktiv | ausgeblendet |
| Neustart nach Backup-Wiederherstellung | automatisch (`restart_app`) | App manuell neu öffnen |
| Video | media_kit (libmpv) | media_kit (libmpv), spielt auch WebM/VP9 |

Hinweis: Video läuft jetzt auf **allen** Plattformen über `media_kit` statt `video_player`
(AVPlayer kann auf iOS kein WebM).

## Nicht getestet

Der Port wurde ohne Flutter-SDK und ohne Gerät geschrieben. Erwartbare Stellen für Nacharbeit, falls der
erste Build oder Start scheitert: Paketversionen in `pubspec.yaml` (`flutter pub get`),
`tool/ios_setup.sh` (andere Flutter-Version = anderes `AppDelegate`-Template) und das Verhalten von
`flutter_downloader` im Hintergrund.

## An Monbooru senden

Im Post-Viewer gibt es neben Download einen Wolken-Knopf. Er schickt die Post-Seite über die monloader-API (`POST /api/v1/queue`) an monloader, der sie per gallery-dl lädt und in Monbooru ablegt. Adresse und Token (Schreibrecht) werden unter Einstellungen → „Monbooru (monloader)" eingetragen; sie liegen nur lokal auf dem Gerät und sind nicht Teil des Backups. Das iPhone muss die Adresse erreichen können.
