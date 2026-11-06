Unofficial iOS port of Boorusphere 1.5.4 (unsigned IPA for sideloading, e.g. with Sideloadly or AltStore).

## New
- **Save to Photos:** new toggle under Settings → Downloads. When enabled, finished downloads are also added to the Photos app (the copy in Files is kept). WebM videos are not supported by Photos and stay in Files.

## Fixed
- The "Send to Monbooru" button is now also shown for videos.

## Included from earlier releases
- **Send to Monbooru:** a cloud button in the post viewer sends the post to Monbooru through the monloader API. Set it up under Settings → "Monbooru (monloader)".
- **App icon** matches the Android app.
- Restoring a backup no longer leaves the server list empty until restart.
- Videos (including WebM) play through media_kit; downloads and backups are stored in the Files app under "On My iPhone → Boorusphere".

## Installation
Download `boorusphere-unsigned.ipa` and install it with Sideloadly over the existing app (same Apple ID, don't delete the app first, so your data is kept). With a free Apple ID the signature expires after 7 days. Developer Mode must be enabled on the iPhone.
