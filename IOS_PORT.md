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

## Send to Monbooru

The post viewer has a cloud button next to Download. It sends the post page to a monloader instance through its API (`POST /api/v1/queue`); monloader downloads it with gallery-dl and files it into Monbooru. If monloader rejects the page URL, the app falls back to the direct file URL and passes the page as `page_url`.

Set the address and an API token with write scope under Settings → "Monbooru (monloader)". Both are stored only on the device and are not part of the backup. The device must be able to reach the address; for LAN addresses iOS asks for local network access on first use.
