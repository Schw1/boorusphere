Unofficial iOS port of Boorusphere 1.5.4: unsigned IPA for sideloading (Sideloadly, AltStore) and, new, Android APKs with the same features.

## New
- **Server list in the menu:** only pinned servers and the active one are listed; all servers are in a list that opens on tap. Pin or unpin with the pin icon or a long press. Pins are in backups (with the server list).
- **Fix:** blocked tags no longer show up in the tag suggestions while typing.
- **Fix:** the favorite heart and the download mark stay on a post after its score or tags changed on the server.
- **Restore:** a backup only replaces favorites, servers, blocked tags, search history and settings once that part of the backup could be read; a broken entry is skipped instead of leaving the data half restored.
- **Faster:** pages load quicker with many blocked tags; the first nhentai search no longer stutters; following jobs after "Send to Monbooru" reuses one connection.
- **Caches:** server icons are kept between app starts (for 7 days). Cached images older than 7 days are removed when the app starts; "Clear cache" also removes the server icons.
- **Privacy:** API requests no longer send their own address (with login data from the URL suffix) as Referer, only the server's address. Links in the post details only open web addresses; a source that is plain text is shown as text.

## In 1.5.4-ios.16
- **For you:** new feed in the menu with posts of the current server for tags you like, learned from your favorites and what you sent to Monbooru. Each refresh picks other tags and starts at a random result page; the server button switches the server or searches all boorus at once; tap a tag to search it.
- **Translation notes:** translated Danbooru and yande.re/konachan images, and Monbooru images with annotations (from its booru lookups), show boxes over the speech bubbles; tap one for its text. The translate button in the viewer hides them. Shown while the image isn't zoomed.
- **Continue reading:** new list in the menu with the galleries and Monbooru archives you read recently, newest first, with the page you left off. Long-press to select entries and remove them from the list. Galleries read before this version show up once you open them again.
- **Saved searches:** save the current search (menu → Saved searches) and see how many posts are new since you last opened it, for every server. Checked when the app starts and when the list is opened (pull down to check again). Searches with their own `order:` get no count.
- **Faster reading:** the reader loads the next pages in the background.
- **Monbooru history:** menu → Monbooru history lists the posts you sent with their result (added, already there, failed and why). Failed ones can be sent again, swipe left to remove an entry (only from the list), or remove all successful ones with the button at the top; sends without a result are asked for again when the list opens. Errors from monloader now include its reason (e.g. `Error 400: …`).
- **Backups** now also include reading progress, the Continue reading list and saved searches (new checkbox, on by default).
- **nhentai:** related galleries in the gallery details. Tags are typed like on Danbooru (`big_breasts -netorare english`); the app turns them into nhentai's `tag:"…"` form. Words that aren't tags search titles; put a title in quotes (`"school days"`) to keep it a title search. The old form still works.
- **Fix:** posts with more than 64 tags (often rule34) were rejected by monloader (`Error 400: at most 64 tags`); the first 64 are sent now.

## In 1.5.4-ios.15
- Sending an nhentai gallery to Monbooru added the app's search tokens as extra tags (`tag:_big_breasts`, `language:english`, `category:manga`). Now only the tags gallery-dl reads from the gallery are used.

## In 1.5.4-ios.14
- **Reading progress:** galleries and Monbooru CBZ archives remember the last page read; the Read button continues there, the thumbnail shows the progress.
- **nhentai tag suggestions** while typing in the search (also `tag:`, `artist:`, `-tag:` …). Search results now know their tags, so blocked tags hide galleries too.

## In 1.5.4-ios.13
- **Sort button:** the search bar has a sort button next to rating and random, with what the server supports, e.g. Danbooru rank/score/favorites/oldest, Gelbooru score/oldest, Monbooru oldest/file size. Remembered per server.
- **nhentai:** can be added as a server (Servers → Add, address `https://nhentai.net`). Galleries open in the reader. The search bar gets a sort button (newest, popular today/this week/this month/all time) instead of the rating; `order:rank` etc. in the search does the same, e.g. `language:english order:rank`. A language button filters English, Japanese or Chinese galleries. Random order shuffles the result pages.

## In 1.5.4-ios.12
- **Android:** APKs for Android, signed with this fork's own key. The app ID is `io.github.schw1.boorusphere`, so it installs next to the original Boorusphere (move your data with Backup and Restore). Updates can be installed from the app.
- **Send several posts to Monbooru:** long-press a thumbnail (timeline or Favorites) to select posts, then send them in one go.
- **Result after sending:** the app follows the monloader job and shows whether the post was added, was already in Monbooru, or failed (and why). Needs read scope on the monloader token in addition to write.
- **Duplicates:** the send button shows a check mark when the post is already in your Monbooru server (from the server list), and asks before sending it again. Batch sends skip those posts.
- **CBZ archives from Monbooru:** shown with their cover and a **Read** button that opens a page reader (swipe left to right, zoom, page slider).
- **Video seek bar:** new button in the video toolbar for a bigger seek bar with times and 10-second jumps.
- **Signature warning:** two days before the sideloading signature expires, a banner reminds you to install the app again. About shows the date.
- **Moving to another device:** "Include login data" in the backup dialog now also includes the API tokens (Monbooru servers, monloader), e.g. to move from iPhone to Android. Off by default, automatic backups never include them.
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
