**Test build** of native Monbooru support (branch `monbooru-native`). Not merged into `main` yet.

## New
- **Monbooru as a server:** add your Monbooru instance under Servers → Add, enter an API token with `read` scope and tap Scan. Browsing, search, tag suggestions, rating filter, videos and downloads work directly against the Monbooru API, no bridge needed.
- Post details: **Location** opens the image in the Monbooru web UI, **Source** the original source.
- The token is stored in the iOS Keychain (this device only, not in backups) and only sent to that server. A warning is shown for plain-HTTP addresses outside the local network.
- "Open link" opens the Monbooru page instead of the raw file; "Send to Monbooru" is hidden for posts that already come from Monbooru.

## Notes
- After restoring a backup, tokens are not included and have to be entered again.
- Archives (CBZ) are not shown.

## Installation
Install `boorusphere-unsigned.ipa` with Sideloadly over the existing app (same Apple ID, don't delete the app first). To go back, install the latest regular release the same way.
