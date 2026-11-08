import 'package:boorusphere/constant/app.dart';
import 'package:boorusphere/data/repository/version/app_version_repo.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'app_version.freezed.dart';

/// App version, e.g. `1.5.4`, or a release of this fork, e.g. `1.5.4-ios.12`
/// (tag `v1.5.4-ios.12`). [release] is the fork's release number, 0 for a
/// plain upstream version.
@freezed
abstract class AppVersion with _$AppVersion {
  const factory AppVersion({
    @Default(0) int major,
    @Default(0) int minor,
    @Default(0) int patch,
    @Default(0) int release,
  }) = _AppVersion;
  const AppVersion._();

  static final _pattern =
      RegExp(r'^v?(\d+)(?:\.(\d+))?(?:\.(\d+))?(?:-ios\.(\d+))?');

  /// Parses `1.5.4`, `1.5.4+53`, `v1.5.4-ios.12` and `1.5.4-ios.12-test.1`
  /// (the suffix after the release number is ignored).
  factory AppVersion.fromString(String string) {
    final m = _pattern.firstMatch(string.trim());
    if (m == null) return zero;
    int at(int i) => int.tryParse(m.group(i) ?? '') ?? 0;
    return AppVersion(
      major: at(1),
      minor: at(2),
      patch: at(3),
      release: at(4),
    );
  }

  @override
  String toString() =>
      '$major.$minor.$patch${release > 0 ? '-ios.$release' : ''}';

  /// The upstream version without the fork's release number.
  AppVersion get base => copyWith(release: 0);

  bool isNewerThan(AppVersion version) {
    final a = [major, minor, patch, release];
    final b = [version.major, version.minor, version.patch, version.release];
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return a[i] > b[i];
    }
    return false;
  }

  /// Release tag on GitHub.
  String get tag => 'v$this';

  /// Release page of this version.
  String get releaseUrl => '${AppVersionRepo.gitUrl}/releases/tag/$tag';

  /// APK for the running device's ABI, as attached to the release.
  String get apkUrl =>
      '${AppVersionRepo.gitUrl}/releases/download/$tag/${apkFileName(kAppArch)}';

  static String apkFileName(String arch) => 'boorusphere-$arch.apk';

  static const zero = AppVersion();
}
