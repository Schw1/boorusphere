Unofficial iOS port of Boorusphere 1.5.4 (unsigned IPA for sideloading, e.g. with Sideloadly or AltStore).

## Fixed
- **Server icons** (e.g. Monbooru) now load: the icon request sends the app's User-Agent like all other image requests, because many servers and proxies reject requests without one.

## New in ios.7
- **Native Monbooru support:** add your Monbooru instance under Servers → Add with an API token (`read` scope). The token is stored in the iOS Keychain, only on this device, not in backups.
- **Automatic backups:** Settings → Backup and Restore. Runs when the app is opened (daily or weekly) and keeps the newest 1/3/5/10 automatic backups; manual backups are never deleted.
- **Random order:** "random" toggle next to the rating filter in the search bar, for every supported booru type.
- **Server icons** are loaded from the server itself first, so self-hosted servers like Monbooru get their icon. Local addresses are no longer sent to DuckDuckGo.
- The in-app changelog now lists the iOS changes.

## Included from earlier releases
- Send to Monbooru (via monloader), Save to Photos, app language support for the new features, version shown in the app, app icon and restore fixes.

## Installation
Download `boorusphere-unsigned.ipa` and install it with Sideloadly over the existing app (same Apple ID, don't delete the app first, so your data is kept). With a free Apple ID the signature expires after 7 days. Developer Mode must be enabled on the iPhone.
