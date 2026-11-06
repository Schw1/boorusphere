import 'dart:ffi';
import 'dart:io' show Platform;

/// The in-app updater downloads and installs an APK, so it only makes sense on Android.
bool get kSupportsInAppUpdate => Platform.isAndroid;

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
