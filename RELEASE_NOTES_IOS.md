Unofficial iOS port of Boorusphere 1.5.4 (unsigned IPA for sideloading, e.g. with Sideloadly or AltStore).

## New
- The iOS port's own features (Send to Monbooru, Save to Photos) now follow the app language. Translations: English and German; other languages fall back to English.
- The installed version (including the iOS release number) is now always shown in the drawer and on the About page, even without the online update check.

## Included from earlier releases
- **Save to Photos:** toggle under Settings → Downloads; finished downloads are also added to the Photos app (WebM stays in Files).
- **Send to Monbooru:** cloud button in the post viewer (images and videos) sends the post to Monbooru through the monloader API. Set it up under Settings → "Monbooru (monloader)".
- App icon matches the Android app; restoring a backup no longer leaves the server list empty.
- Videos (including WebM) play through media_kit; downloads and backups are stored in the Files app under "On My iPhone → Boorusphere".

## Installation
Download `boorusphere-unsigned.ipa` and install it with Sideloadly over the existing app (same Apple ID, don't delete the app first, so your data is kept). With a free Apple ID the signature expires after 7 days. Developer Mode must be enabled on the iPhone.
