import 'dart:ffi';
import 'dart:io' show Platform;

/// The in-app updater downloads and installs an APK, so it only makes sense on
/// Android. iOS shows available updates with a link to the release page.
bool get kSupportsInAppUpdate => Platform.isAndroid;

/// Release of this fork (e.g. "v1.5.4-ios.12"), passed by CI via
/// --dart-define=APP_RELEASE=... for the iOS and Android builds; a dev label
/// like "1.5.4-ios-dev+abc1234" for test builds, empty for local builds.
const kAppRelease = String.fromEnvironment('APP_RELEASE');

/// Version shown in the UI: the release label if known, else [appVersion].
String displayVersion(Object appVersion) {
  if (kAppRelease.isEmpty) return '$appVersion';
  return kAppRelease.startsWith('v') ? kAppRelease.substring(1) : kAppRelease;
}

String get kAppArch {
  switch (Abi.current()) {
    case Abi.androidX64:
      return 'x86_64';
    case Abi.androidArm64:
      return 'arm64-v8a';
    // we have no x86 apk, so most likely we're running in arm emulation mode
    case Abi.androidIA32:
    case Abi.androidArm:
      return 'armeabi-v7a';
    case Abi.iosArm64:
      return 'ios-arm64';
    case Abi.iosX64:
      return 'ios-x64';
    default:
      return Abi.current().toString();
  }
}
