import 'package:boorusphere/data/repository/version/entity/app_version.dart';
import 'package:boorusphere/domain/repository/env_repo.dart';
import 'package:boorusphere/domain/repository/version_repo.dart';
import 'package:dio/dio.dart';

class AppVersionRepo implements VersionRepo {
  AppVersionRepo({required this.envRepo, required this.client});

  final EnvRepo envRepo;
  final Dio client;

  /// Includes the fork's release number for CI builds (see CurrentEnvRepo).
  @override
  AppVersion get current => envRepo.appVersion;

  /// Newest published (non-pre-) release of this fork.
  @override
  Future<AppVersion> fetch() async {
    final res = await client.get(
      latestReleaseUrl,
      options: Options(
        headers: {'Accept': 'application/vnd.github+json'},
        validateStatus: (_) => true,
      ),
    );
    final data = res.data;
    if (res.statusCode == 200 && data is Map) {
      final tag = data['tag_name'];
      if (tag is String && tag.startsWith('v')) {
        return AppVersion.fromString(tag);
      }
    }
    return AppVersion.zero;
  }

  static const repo = 'Schw1/boorusphere-ios';
  static const gitUrl = 'https://github.com/$repo';
  static const latestReleaseUrl =
      'https://api.github.com/repos/$repo/releases/latest';
}
