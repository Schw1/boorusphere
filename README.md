<div align="center">
    <div><img src="assets/icons/exported/legacy-circle.png" alt="boorusphere icon" height="92"></div>
    <div><h1 align="center">Boorusphere</h1></div>
    <div>Unofficial fork of Boorusphere, a simple, content-focused booru viewer, for iOS and Android</div>
    <br/>
    <div>
        <a href="https://github.com/Schw1/boorusphere/releases/latest">
            <img alt="Latest release" src="https://img.shields.io/github/v/release/Schw1/boorusphere?style=for-the-badge&logo=pkgsrc&logoColor=ebebf0&labelColor=23232F&color=95b6ff">
        </a>
        <a href="https://github.com/Schw1/boorusphere/actions">
            <img alt="Build status" src="https://img.shields.io/github/actions/workflow/status/Schw1/boorusphere/build-ios.yml?style=for-the-badge&logo=githubactions&logoColor=ebebf0&labelColor=23232F&label=build">
        </a>
        <a href="LICENSE.md">
            <img alt="License" src="https://img.shields.io/github/license/Schw1/boorusphere?style=for-the-badge&logo=gitbook&logoColor=ebebf0&color=b0a8f7&labelColor=23232F"/>
        </a>
    </div>
</div>

> [!WARNING]
> **Please read before using.** Everything this fork adds on top of the original app (the iOS port and all new features below) was written with the help of [Claude](https://claude.ai), an AI assistant by Anthropic. I am not a professional developer. The code has not been reviewed by an experienced iOS, Android or Flutter developer and has only been tested on my own devices. Use it with caution and at your own risk; there is no warranty of any kind.

# Thanks

This app is almost entirely the work of the original authors. All credit for the app itself goes to them:

- **[nullxception/boorusphere](https://github.com/nullxception/boorusphere)**, the original Boorusphere for Android
- **[Kropatz/boorusphere](https://github.com/Kropatz/boorusphere)**, the maintained fork this one is based on

- **[Monbooru](https://github.com/monbooru/monbooru)**, for the self-hosted booru, its API and monloader that the Monbooru features are built on

Please report problems with this fork here, not in the original repositories.

# Platforms

Every release ships both apps, built from the same code by GitHub Actions:

| | iOS | Android |
| --- | --- | --- |
| File | `boorusphere-unsigned.ipa` | `boorusphere-<abi>.apk`, `boorusphere-universal.apk` |
| Install | Sideloading (Sideloadly, AltStore, SideStore) | APK, next to the original Boorusphere |
| Updates | Update notice with a link to the release | Installed from the app |
| Requires | iOS 14 | Android 7.0 |

# Features

From the original app:

- Simple and intuitive UI
- Support for various booru-based imageboards
- Videos and animated images (GIF, WEBM)
- Favorites, tag suggestions, tag blocking
- Download images and videos
- Backup and restore

Added in this fork:

**Browsing**
- **For you**: a feed of posts for the tags you like, learned from your favorites and what you sent to Monbooru
- **Saved searches** with a count of new posts since you last opened them
- **Related posts**: parent post, other versions, child posts and pools in the post details
- **Sort button** (score, favorites, oldest, …) and a **random order** toggle, per booru type
- **Pinned servers** in the menu, the others in a list that opens on tap
- **Translation notes** over translated Danbooru, yande.re/Konachan and Monbooru images

**Reading**
- **nhentai** as a server, with a gallery reader, tag suggestions and related galleries
- **Monbooru archives**: read CBZ archives page by page
- **Continue reading**: recently read galleries and archives with the page you left off

**Monbooru**
- **Native Monbooru support**: browse a [Monbooru](https://github.com/monbooru/monbooru) instance through its API
- **Send to Monbooru**: push posts from any booru to Monbooru through monloader, also several at once (long-press thumbnails), with a duplicate check and the result shown afterwards
- **Monbooru history** of everything sent, with resend for failed posts

**Everyday**
- **Video seek bar** with elapsed/total time and 10-second jumps
- **Automatic backups**: on app start, daily or weekly, keeps the newest backups
- API tokens in the iOS Keychain / Android Keystore, login data left out of backups unless you choose otherwise
- English and German translations for the new features

**iOS only**
- **Save to Photos**: optionally add downloads to the Photos app
- **Signature warning**: reminds you two days before a sideloaded app's signature expires

# Preview

<p align="justify">
    <img width="24%" src="fastlane/metadata/android/en-US/images/phoneScreenshots/1.png" />
    <img width="24%" src="fastlane/metadata/android/en-US/images/phoneScreenshots/2.png" />
    <img width="24%" src="fastlane/metadata/android/en-US/images/phoneScreenshots/3.png" />
    <img width="24%" src="fastlane/metadata/android/en-US/images/phoneScreenshots/4.png" />
</p>

<sub>Screenshots from the original Android app.</sub>

# Installation

Releases marked as **pre-release** are test builds of features that are not finished yet; use the [latest release](https://github.com/Schw1/boorusphere/releases/latest) otherwise.

## iOS

1. Download `boorusphere-unsigned.ipa` from the [latest release](https://github.com/Schw1/boorusphere/releases/latest).
2. Install it with [Sideloadly](https://sideloadly.io) (Windows/macOS) using your Apple ID, or with AltStore/SideStore.
3. Enable Developer Mode on the iPhone (Settings → Privacy & Security → Developer Mode).

With a free Apple ID the signature expires after 7 days; install the IPA again to renew it. To update, install a newer IPA over the existing app without deleting it first, so your data is kept.

## Android

Download `boorusphere-arm64-v8a.apk` (most phones) or `boorusphere-universal.apk` from the [latest release](https://github.com/Schw1/boorusphere/releases/latest) and install it. It has its own app ID, so it installs next to the original Boorusphere; move your data over with Backup and Restore. Later updates can be installed from the app (About → update).

# Building

Both apps are built by the [build workflow](.github/workflows/build-ios.yml) on GitHub Actions; no Mac is needed for iOS. How releases, release notes, signing and the platform differences work is described in [IOS_PORT.md](IOS_PORT.md).

For local development (Flutter 3.41, code generation, translations), see the [original README](https://github.com/Kropatz/boorusphere#building-from-source).

# Security

Known security and dependency topics are tracked in the [issues](https://github.com/Schw1/boorusphere/issues?q=label%3Asecurity). API tokens (Monbooru, monloader) are kept in the iOS Keychain / Android Keystore. Credentials in a server's URL suffix (e.g. `api_key=…`) are stored in the app's private storage and are left out of backups unless you choose "Include login data"; the same option also includes the API tokens, e.g. to move to another device. See [IOS_PORT.md](IOS_PORT.md#security-notes) for details.

# License

[BSD 3-Clause](LICENSE.md), same as the original project.
