Unofficial iOS port of Boorusphere 1.5.4: unsigned IPA for sideloading (Sideloadly, AltStore) and, new, Android APKs with the same features.

## New
- **Android:** APKs for Android, signed with this fork's own key. The app ID is `io.github.schw1.boorusphere`, so it installs next to the original Boorusphere (move your data with Backup and Restore). Updates can be installed from the app.
- **Send several posts to Monbooru:** long-press a thumbnail (timeline or Favorites) to select posts, then send them in one go.
- **Result after sending:** the app follows the monloader job and shows whether the post was added, was already in Monbooru, or failed (and why). Needs read scope on the monloader token in addition to write.
- **Duplicates:** the send button shows a check mark when the post is already in your Monbooru server (from the server list), and asks before sending it again. Batch sends skip those posts.
- **CBZ archives from Monbooru:** shown with their cover and a **Read** button that opens a page reader (swipe left to right, zoom, page slider).
- **Video seek bar:** new button in the video toolbar for a bigger seek bar with times and 10-second jumps.
- **Signature warning:** two days before the sideloading signature expires, a banner reminds you to install the app again. About shows the date.
- **Update notice on iOS:** the drawer and About page show when a newer release is out, with a link to it.

## Earlier in 1.5.4-ios
- **Another zoom step:** the grid button now goes down to two columns less than the width-based default (e.g. 2 columns on a tablet in portrait), for even bigger thumbnails.
- **Requires iOS 14 or later** (was iOS 13).

## Security
- The monloader token ("Send to Monbooru") is now stored in the iOS Keychain instead of the app database and is no longer part of backups. An existing token is moved automatically.
- Login data in a server's URL suffix (e.g. `api_key=…`) is left out of backups unless you check **Include login data**. Restoring such a backup on the same device keeps your keys.
- Built with Flutter 3.41 and updated dependencies (including a file_picker security fix).

## New in ios.9
- Monbooru server icons load (icons linked from the server's login/start page).
- Backups can include the monloader settings (address and token for "Send to Monbooru"; the token is stored in plain text in the backup file).
- Zoom step with one column less.

## New in ios.7
- **Native Monbooru support:** add your Monbooru instance under Servers → Add with an API token (`read` scope). The token is stored in the iOS Keychain, only on this device, not in backups.
- **Automatic backups:** Settings → Backup and Restore. Runs when the app is opened (daily or weekly) and keeps the newest 1/3/5/10 automatic backups; manual backups are never deleted.
- **Random order:** "random" toggle next to the rating filter in the search bar, for every supported booru type.
- **Server icons** are loaded from the server itself first, so self-hosted servers like Monbooru get their icon. Local addresses are no longer sent to DuckDuckGo.
- The in-app changelog now lists the iOS changes.

## Included from earlier releases
- Send to Monbooru (via monloader), Save to Photos, app language support for the new features, version shown in the app, app icon and restore fixes.

## Installation
- **iOS:** download `boorusphere-unsigned.ipa` and install it with Sideloadly over the existing app (same Apple ID, don't delete the app first, so your data is kept). With a free Apple ID the signature expires after 7 days. Developer Mode must be enabled on the iPhone.
- **Android:** `boorusphere-arm64-v8a.apk` fits most phones; `boorusphere-universal.apk` works everywhere.
