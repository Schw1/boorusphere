<div align="center">
    <div><img src="assets/icons/exported/legacy-circle.png" alt="boorusphere icon" height="92"></div>
    <div><h1 align="center">Boorusphere for iOS</h1></div>
    <div>Unofficial iOS port of Boorusphere, a simple, content-focused booru viewer</div>
    <br/>
    <div>
        <a href="https://github.com/Schw1/boorusphere-ios/releases/latest">
            <img alt="Latest release" src="https://img.shields.io/github/v/release/Schw1/boorusphere-ios?style=for-the-badge&logo=pkgsrc&logoColor=ebebf0&labelColor=23232F&color=95b6ff">
        </a>
        <a href="https://github.com/Schw1/boorusphere-ios/actions">
            <img alt="Build status" src="https://img.shields.io/github/actions/workflow/status/Schw1/boorusphere-ios/build-ios.yml?style=for-the-badge&logo=githubactions&logoColor=ebebf0&labelColor=23232F&label=iOS%20build">
        </a>
        <a href="LICENSE.md">
            <img alt="License" src="https://img.shields.io/github/license/Schw1/boorusphere-ios?style=for-the-badge&logo=gitbook&logoColor=ebebf0&color=b0a8f7&labelColor=23232F"/>
        </a>
    </div>
</div>

> [!WARNING]
> **Please read before using.** Everything this fork adds on top of the original app (the iOS port and all new features below) was written with the help of [Claude](https://claude.ai), an AI assistant by Anthropic. I am not a professional developer. The code has not been reviewed by an experienced iOS or Flutter developer and has only been tested on my own device. Use it with caution and at your own risk; there is no warranty of any kind.

# Thanks

This app is almost entirely the work of the original authors. All credit for the app itself goes to them:

- **[nullxception/boorusphere](https://github.com/nullxception/boorusphere)**, the original Boorusphere for Android
- **[Kropatz/boorusphere](https://github.com/Kropatz/boorusphere)**, the maintained fork this port is based on

- **[Monbooru](https://github.com/monbooru/monbooru)**, for the self-hosted booru, its API and monloader that the Monbooru features are built on

This fork only adds the iOS port and a few features on top. Please report problems with this port here, not in the original repositories.

# Features

From the original app:

- Simple and intuitive UI
- Support for various booru-based imageboards
- Videos and animated images (GIF, WEBM)
- Favorites, tag suggestions, tag blocking
- Download images and videos
- Backup and restore

Added in this fork:

- **iOS support**: unsigned IPA built with GitHub Actions, no Mac needed
- **Native Monbooru support**: browse a [Monbooru](https://github.com/monbooru/monbooru) instance directly through its API (token stored in the iOS Keychain)
- **Send to Monbooru**: push posts from any booru to Monbooru through monloader
- **Save to Photos**: optionally add downloads to the iOS Photos app
- **Automatic backups**: on app start, daily or weekly, keeps the newest backups
- **Random order**: random sorting toggle for search, for every supported booru type
- English and German translations for the new features

# Preview

<p align="justify">
    <img width="24%" src="fastlane/metadata/android/en-US/images/phoneScreenshots/1.png" />
    <img width="24%" src="fastlane/metadata/android/en-US/images/phoneScreenshots/2.png" />
    <img width="24%" src="fastlane/metadata/android/en-US/images/phoneScreenshots/3.png" />
    <img width="24%" src="fastlane/metadata/android/en-US/images/phoneScreenshots/4.png" />
</p>

<sub>Screenshots from the original Android app.</sub>

# Installation (iOS)

1. Download `boorusphere-unsigned.ipa` from the [latest release](https://github.com/Schw1/boorusphere-ios/releases/latest).
2. Install it with [Sideloadly](https://sideloadly.io) (Windows/macOS) using your Apple ID, or with AltStore/SideStore.
3. Enable Developer Mode on the iPhone (Settings → Privacy & Security → Developer Mode).

With a free Apple ID the signature expires after 7 days; install the IPA again to renew it. To update, install a newer IPA over the existing app without deleting it first, so your data is kept.

Releases marked as **pre-release** are test builds of features that are not finished yet.

# Building

The iOS app is built by the [Build iOS workflow](.github/workflows/build-ios.yml) on GitHub Actions. Details about the build, the iOS-specific changes and the new features are in [IOS_PORT.md](IOS_PORT.md).

For building the Android app and for general development (code generation, translations), see the [original README](https://github.com/Kropatz/boorusphere#building-from-source).

# Security

Known security and dependency topics are tracked in the [issues](https://github.com/Schw1/boorusphere-ios/issues?q=label%3Asecurity). API tokens (Monbooru, monloader) are kept in the iOS Keychain. Credentials in a server's URL suffix (e.g. `api_key=…`) are stored in plain app storage and are left out of backups unless you choose "Include login data". See [IOS_PORT.md](IOS_PORT.md#security-notes) for details.

# License

[BSD 3-Clause](LICENSE.md), same as the original project.
