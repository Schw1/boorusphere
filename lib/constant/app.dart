import 'dart:ffi';
import 'dart:io' show Platform;

/// The in-app updater downloads and installs an APK, so it only makes sense on Android.
bool get kSupportsInAppUpdate => Platform.isAndroid;

/// iOS port release (e.g. "v1.5.4-ios.5"), passed by CI via
/// --dart-define=IOS_RELEASE=... ; empty for local/Android builds.
const kIosRelease = String.fromEnvironment('IOS_RELEASE');

/// Version shown in the UI: the iOS port release if known, else [appVersion].
String displayVersion(Object appVersion) {
  if (kIosRelease.isEmpty) return '$appVersion';
  return kIosRelease.startsWith('v') ? kIosRelease.substring(1) : kIosRelease;
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
