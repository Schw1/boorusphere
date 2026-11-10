# Boorusphere iOS port

This fork builds an **unsigned IPA** and **signed Android APKs** with GitHub Actions, so no Mac is needed. A release always ships both.

## Building

- Every push to `main` runs **Build iOS (unsigned IPA)** and uploads the artifact `boorusphere-unsigned-ipa`.
- To publish a release: Actions → **Build iOS (unsigned IPA)** → *Run workflow*, and enter a tag such as `v1.5.4-ios.2`. The workflow builds the app, creates the tag and attaches `boorusphere-unsigned.ipa` and the APKs to the release, using `RELEASE_NOTES_IOS.md` as the release text. Runs on other branches than `main` create a pre-release (test build).
- The tag is passed to both apps (`--dart-define=APP_RELEASE=…`); it is the version shown in the app and the one the update check compares (`1.5.4-ios.12` is newer than `1.5.4-ios.11`).

The workflow runs on `macos-15-intel`. That only affects the build machine; the app itself is built for iPhone (arm64). The arm64 macOS runner pool frequently cancels jobs for lack of capacity.

The workflow calls `tool/ios_setup.sh`. The script generates `ios/` with `flutter create` and then patches AppDelegate (flutter_downloader), Info.plist, the Podfile and the app icon. That is why `ios/` is not committed.

## Installing (without a Mac)

The app requires **iOS 14** or later.

- **Sideloadly** (Windows/macOS): sign the IPA with your Apple ID and install it over USB. With a free account the signature expires after 7 days. Developer Mode must be enabled on the device.
- Alternatively AltStore Classic (via AltStore PAL in the EU) or SideStore.

## Differences on iOS

| Area | Android | iOS |
| --- | --- | --- |
| Version / `sdkVersion` | Pigeon `AppEnv` (Kotlin) | `package_info_plus`, `sdkVersion = 99` |
| Download folder | public Downloads folder (Pigeon `StorageUtil`) | app folder `Documents/Boorusphere`, visible in the Files app; optionally also saved to Photos (Settings → Save to Photos) |
| App data (Hive, cookies) | app's private documents folder | `Library/Application Support` (`hive/`, `cookies/`), not visible in the Files app; versions before 1.5.4-ios.18 kept them in `Documents` and are moved once at start (`lib/data/app_storage.dart`) |
| Opening files | Intent (Pigeon `StorageUtil`) | `open_filex` |
| Media scan, "Hide media" | `media_scanner`, `.nomedia` | not applicable (setting hidden) |
| Notification permission for downloads | requested | not requested |
| In-app updater | downloads the APK from this fork's latest release | shows a link to the release page |
| After restoring a backup | app restarts (`restart_app`) | state is reloaded in place |
| Video | media_kit (libmpv) | media_kit (libmpv), plays WebM/VP9 too |

Video now uses `media_kit` instead of `video_player` on **all** platforms, because AVPlayer on iOS cannot play WebM.

## Save to Photos

Settings → Downloads → **Save to Photos** (iOS only). When enabled, every finished download is also added to the Photos library via [`gal`](https://pub.dev/packages/gal); iOS asks for permission when the toggle is first turned on. The copy in the Files app is kept, so the download list keeps working. Photos only accepts MP4/MOV/M4V videos, so WebM files stay in Files only.

## Monbooru as a server

Monbooru can be added as a regular server (parser `Monbooru.json`):

1. Servers → Add, enter the Monbooru address (e.g. `https://booru.example.org` or `http://192.168.x.x:8455`).
2. Enter an **API token** with `read` scope (Monbooru → Settings → Authentication) and tap **Scan**.

Search uses `/api/v1/images/search`, tag suggestions `/api/v1/tags`, and the safe-mode/rating filter maps to Monbooru's `rating:general|sensitive|questionable|explicit`. In post details, **Location** opens the image page in the Monbooru web UI (`/images/{id}`) and **Source** the original source. A `?gallery=<name>` can be added through the URL suffix. AVIF/JXL are shown through Monbooru's WebP still. CBZ archives are shown with their cover (page 1) and a **Read** button; see [Archives](#archives-cbz).

Security:
- The token is stored in the iOS Keychain / Android Keystore (this device only, not synced) and cached in memory. Backups only include it with "Include login data" (`server_tokens.json`), e.g. to move to another device; automatic backups never do.
- It is only attached to requests whose origin matches the server's homepage or API address, including images, videos and downloads.
- The settings warn when the address is plain HTTP outside the local network.
- Known limitation: flutter_downloader keeps the request headers of a download task (including the token) in its local task database inside the app sandbox.

## Automatic backups

Settings → Backup and Restore → **Automatic backup**. iOS gives apps no reliable background time, so the backup runs when the app starts or returns to the foreground and the last automatic backup is older than the chosen interval (daily/weekly). Files are named `boorusphere_autobackup_<time>.zip` in `Documents/Boorusphere/backups`; only the newest N (1/3/5/10) are kept, manual backups (`boorusphere_backup_…`) are never deleted. API tokens are not part of any backup, and automatic backups never contain the login data from URL suffixes.

## Random order

The search option bar has a **random** toggle next to the rating filter. It applies from the next search and is translated per engine: `order:random` (Danbooru, Moebooru, e621, Shimmie), `sort:random` (Gelbooru, Safebooru, Szurubooru), `sf=random` (Philomena), and `sort=random&seed=…` for Monbooru, whose seed keeps paging free of repeats. On the other engines later pages are drawn independently, so already loaded posts are skipped.

## Server icons

Server icons are resolved like a browser does: the server's own `/favicon.ico`; if that returns a page instead (Monbooru answers with its login page to clients without a web session), the icons linked from that page or the start page; SVG icons are skipped because Flutter cannot decode them. Only for public hosts the app falls back to the DuckDuckGo icon service; local addresses (private IPs, `*.local`, `*.lan`) are never sent there. Icons are fetched with a separate client without cookie jar.

## Archives (CBZ)

Monbooru archives (`file_type: cbz`) appear in the timeline with their first page as the cover. In the viewer, **Read (N pages)** opens a reader: swipe left to right, pinch or double-tap to zoom, tap to show the page slider. Pages come from `/api/v1/images/{id}/page/{n}` (`page_count` of the image) with the server's token. Download saves the original `.cbz`; "Save to Photos" skips it.

## Send to Monbooru

The post viewer has a cloud button next to Download. It sends the post page to a monloader instance through its API (`POST /api/v1/queue`); monloader downloads it with gallery-dl and files it into Monbooru. If monloader rejects the page URL, the app falls back to the direct file URL and passes the page as `page_url`.

Set the address and an API token with **write** scope under Settings → "Monbooru (monloader)". With **read** scope as well, the app shows the result of each job. The token is stored in the iOS Keychain (this device only, not synced, in backups only with "Include login data"; tokens from older versions are moved there from Hive on startup), the address in Hive and in the backup. The settings warn when the address is plain HTTP outside the local network. The device must be able to reach the address; for LAN addresses iOS asks for local network access on first use.

### Result after sending

monloader answers with a job id. The app polls `GET /api/v1/queue/{id}` every 2 s (for up to 3 minutes, also after leaving the viewer) and shows the outcome: added, already in Monbooru, skipped, or failed with monloader's reason. Without read scope or when the job takes longer, it says that no result can be shown.

### Duplicates

Boorus report a post's file md5 (Danbooru, Gelbooru, Moebooru, e621, Szurubooru, Shimmie, Safebooru), or the file is named after it. The viewer searches the first Monbooru server in the server list that has a token (`md5:<hash>`, with its `gallery=` from the URL suffix). If the file is there, the send button shows a check mark and sending asks first. Found posts are remembered for the session; misses are checked again after 10 minutes.

### Sending several posts

Long-press a thumbnail in the timeline or in Favorites to start selecting, tap more to add or remove them. The bar on top selects all loaded posts or sends the selection. Posts already in Monbooru (and posts from Monbooru itself) are left out; one message sums up the result.

## Video seek bar

The bar button in the video toolbar shows a larger seek bar with elapsed and total time and buttons to jump 10 s back or forward. While it is on, the toolbar doesn't hide (only the play button and the dimming do); the choice is kept for the next video until the app restarts.

## Signature warning

Sideloaded apps carry `embedded.mobileprovision`; its `ExpirationDate` is read at start. Two days before it expires a banner on top of the timeline says when, so the IPA can be installed again in time. About shows the date. Nothing is shown without a profile.

## Android

- **App ID** `io.github.schw1.boorusphere`, so the APK installs next to the original Boorusphere (Kotlin namespace unchanged). Data moves over with Backup and Restore.
- **Signing:** release APKs are signed with this fork's own key from the repository secrets `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`. A release fails without them. The key is written to the runner's temp folder only for the build and deleted afterwards; it is never in the repository or an artifact. Builds without secrets (e.g. forks) use the debug key and are test builds.
- **Files:** `boorusphere-<abi>.apk` (`arm64-v8a`, `armeabi-v7a`, `x86_64`) and `boorusphere-universal.apk`.
- **Updates:** the in-app updater asks `api.github.com/repos/Schw1/boorusphere-ios/releases/latest` and downloads the APK for the device's ABI from that release. On iOS the same check shows a link to the release page.
- **Plain HTTP** is allowed (`usesCleartextTraffic`), see Security notes.

## Upstream changes

The **Upstream check** workflow runs every Monday and compares `Kropatz/boorusphere` with `main`. If upstream has new commits it opens an issue (label `upstream`) or updates the open one. Close it once the changes are merged or deliberately skipped; it only comes back when upstream moves on.

## Security notes

- **Keychain:** the Monbooru server tokens and the monloader token are stored in the iOS Keychain (`first unlock, this device only`): not synced via iCloud Keychain. They are only written into a backup when "Include login data" is chosen (plain text, red warning in the dialog; automatic backups never include them), so they can be moved to another device, e.g. from iOS to Android.
- **Login data in URL suffixes:** some boorus take credentials as query parameters (e.g. `&api_key=…&user_id=…`). They stay in the app's Hive storage, which is not visible in the Files app. A manual backup leaves them out unless **Include login data** is checked; then they are in plain text in the backup file, which is visible in the Files app. Restoring a backup without login data on the same device keeps the existing keys.
- **Plain HTTP (App Transport Security):** `NSAllowsArbitraryLoads` stays enabled on purpose, so user-added boorus without HTTPS keep working (browsing, video and downloads). The Android build allows cleartext traffic for the same reason. All bundled servers use HTTPS. Token fields warn when the address is plain HTTP outside the local network.
- **Android backup:** Android's own auto backup stays enabled, so app data (including URL suffix credentials) can end up in the Google account backup; tokens in the Keystore don't.
- **Android signing key:** only in the repository secrets and with the maintainer; see [Android](#android).
