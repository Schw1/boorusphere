Unofficial iOS port of Boorusphere 1.5.4 (unsigned IPA for sideloading, e.g. with Sideloadly or AltStore).

## New
- **Send to Monbooru:** a cloud button in the post viewer sends the post to Monbooru through the monloader API. Set it up under Settings → "Monbooru (monloader)" (address + API token with write scope).
- **App icon** now matches the Android app (earlier builds still showed the default Flutter icon).

## Fixed
- After restoring a backup, the server list stayed empty until the app was restarted.

## iOS port in general
- Videos (including WebM) play through media_kit.
- Downloads and backups are stored in the Files app under "On My iPhone → Boorusphere".
- No in-app updater and no Android-specific options.

## Installation
Download `boorusphere-unsigned.ipa` and install it with Sideloadly. With a free Apple ID the signature expires after 7 days and must be renewed. Developer Mode must be enabled on the iPhone.
