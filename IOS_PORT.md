# Boorusphere iOS port

This fork builds an **unsigned IPA** with GitHub Actions, so no Mac is needed.

## Building

- Every push to `main` runs **Build iOS (unsigned IPA)** and uploads the artifact `boorusphere-unsigned-ipa`.
- To publish a release: Actions → **Build iOS (unsigned IPA)** → *Run workflow*, and enter a tag such as `v1.5.4-ios.2`. The workflow builds the app, creates the tag and attaches `boorusphere-unsigned.ipa` to the release, using `RELEASE_NOTES_IOS.md` as the release text.

The workflow runs on `macos-15-intel`. That only affects the build machine; the app itself is built for iPhone (arm64). The arm64 macOS runner pool frequently cancels jobs for lack of capacity.

The workflow calls `tool/ios_setup.sh`. The script generates `ios/` with `flutter create` and then patches AppDelegate (flutter_downloader), Info.plist, the Podfile and the app icon. That is why `ios/` is not committed.

## Installing (without a Mac)

- **Sideloadly** (Windows/macOS): sign the IPA with your Apple ID and install it over USB. With a free account the signature expires after 7 days. Developer Mode must be enabled on the device.
- Alternatively AltStore Classic (via AltStore PAL in the EU) or SideStore.

## Differences on iOS

| Area | Android | iOS |
| --- | --- | --- |
| Version / `sdkVersion` | Pigeon `AppEnv` (Kotlin) | `package_info_plus`, `sdkVersion = 99` |
| Download folder | public Downloads folder (Pigeon `StorageUtil`) | app folder `Documents/Boorusphere`, visible in the Files app; optionally also saved to Photos (Settings → Save to Photos) |
| Opening files | Intent (Pigeon `StorageUtil`) | `open_filex` |
| Media scan, "Hide media" | `media_scanner`, `.nomedia` | not applicable (setting hidden) |
| Notification permission for downloads | requested | not requested |
| In-app updater (APK) | enabled | hidden |
| After restoring a backup | app restarts (`restart_app`) | state is reloaded in place |
| Video | media_kit (libmpv) | media_kit (libmpv), plays WebM/VP9 too |

Video now uses `media_kit` instead of `video_player` on **all** platforms, because AVPlayer on iOS cannot play WebM.

## Save to Photos

Settings → Downloads → **Save to Photos** (iOS only). When enabled, every finished download is also added to the Photos library via [`gal`](https://pub.dev/packages/gal); iOS asks for permission when the toggle is first turned on. The copy in the Files app is kept, so the download list keeps working. Photos only accepts MP4/MOV/M4V videos, so WebM files stay in Files only.

## Monbooru as a server

Monbooru can be added as a regular server (parser `Monbooru.json`):

1. Servers → Add, enter the Monbooru address (e.g. `https://booru.example.org` or `http://192.168.x.x:8455`).
2. Enter an **API token** with `read` scope (Monbooru → Settings → Authentication) and tap **Scan**.

Search uses `/api/v1/images/search`, tag suggestions `/api/v1/tags`, and the safe-mode/rating filter maps to Monbooru's `rating:general|sensitive|questionable|explicit`. In post details, **Location** opens the image page in the Monbooru web UI (`/images/{id}`) and **Source** the original source. A `?gallery=<name>` can be added through the URL suffix. Archives (CBZ) are skipped; AVIF/JXL are shown through Monbooru's WebP still.

Security:
- The token is stored in the iOS Keychain (this device only, not synced, not part of backups) and cached in memory.
- It is only attached to requests whose origin matches the server's homepage or API address, including images, videos and downloads.
- The settings warn when the address is plain HTTP outside the local network.
- Known limitation: flutter_downloader keeps the request headers of a download task (including the token) in its local task database inside the app sandbox.

## Automatic backups

Settings → Backup and Restore → **Automatic backup**. iOS gives apps no reliable background time, so the backup runs when the app starts or returns to the foreground and the last automatic backup is older than the chosen interval (daily/weekly). Files are named `boorusphere_autobackup_<time>.zip` in `Documents/Boorusphere/backups`; only the newest N (1/3/5/10) are kept, manual backups (`boorusphere_backup_…`) are never deleted. API tokens are not part of any backup.

## Random order

The search option bar has a **random** toggle next to the rating filter. It applies from the next search and is translated per engine: `order:random` (Danbooru, Moebooru, e621, Shimmie), `sort:random` (Gelbooru, Safebooru, Szurubooru), `sf=random` (Philomena), and `sort=random&seed=…` for Monbooru, whose seed keeps paging free of repeats. On the other engines later pages are drawn independently, so already loaded posts are skipped.

## Server icons

Server icons are resolved like a browser does: the server's own `/favicon.ico`; if that returns a page instead (Monbooru answers with its login page to clients without a web session), the icons linked from that page or the start page; SVG icons are skipped because Flutter cannot decode them. Only for public hosts the app falls back to the DuckDuckGo icon service; local addresses (private IPs, `*.local`, `*.lan`) are never sent there. Icons are fetched with a separate client without cookie jar.

## Send to Monbooru

The post viewer has a cloud button next to Download. It sends the post page to a monloader instance through its API (`POST /api/v1/queue`); monloader downloads it with gallery-dl and files it into Monbooru. If monloader rejects the page URL, the app falls back to the direct file URL and passes the page as `page_url`.

Set the address and an API token with write scope under Settings → "Monbooru (monloader)". The token is stored in the iOS Keychain (this device only, not synced, not part of backups; tokens from older versions are moved there from Hive on startup), the address in Hive and in the backup. The settings warn when the address is plain HTTP outside the local network. The device must be able to reach the address; for LAN addresses iOS asks for local network access on first use.
