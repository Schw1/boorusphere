import 'package:boorusphere/constant/app.dart';
import 'package:boorusphere/data/repository/version/entity/app_version.dart';
import 'package:boorusphere/domain/repository/env_repo.dart';
import 'package:boorusphere/pigeon/app_env.pi.dart';

class CurrentEnvRepo implements EnvRepo {
  CurrentEnvRepo({required this.env});

  @override
  final Env env;

  @override
  int get sdkVersion => env.sdkVersion;

  @override
  AppVersion get appVersion {
    // Fork release (CI build) first, so "What's new" and the User-Agent
    // follow the release, not only the upstream version.
    final release = AppVersion.fromString(kAppRelease);
    if (release.release > 0) return release;
    return AppVersion.fromString(env.versionName);
  }
}
