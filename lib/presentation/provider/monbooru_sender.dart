import 'package:boorusphere/data/repository/booru/entity/post.dart';
import 'package:dio/dio.dart';
import 'package:hive_ce/hive.dart';

/// Sends posts to a monloader instance (the queue service behind Monsender),
/// which downloads them and files them into Monbooru.
///
/// Address and token are stored in their own Hive box, so they are not part of
/// the settings backup.
class MonbooruConfig {
  const MonbooruConfig({this.url = '', this.token = ''});

  final String url;
  final String token;

  bool get isComplete => url.isNotEmpty && token.isNotEmpty;
}

enum MonbooruErrorKind {
  notConfigured,
  noUrl,
  unreachable,
  invalidToken,
  noWriteScope,
  unavailable,
  apiDisabled,
  http,
}

/// Error from monloader; the UI turns it into a translated message.
class MonbooruError {
  const MonbooruError(this.kind, [this.detail = '']);

  final MonbooruErrorKind kind;
  final String detail;
}

class MonbooruSender {
  static const _boxName = 'monbooru';

  static Future<Box> _box() async {
    if (Hive.isBoxOpen(_boxName)) return Hive.box(_boxName);
    return Hive.openBox(_boxName);
  }

  static String normalizeUrl(String input) {
    var url = input.trim();
    if (url.isEmpty) return '';
    if (!url.contains('://')) url = 'http://$url';
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    return url;
  }

  static Future<MonbooruConfig> load() async {
    final box = await _box();
    return MonbooruConfig(
      url: box.get('url', defaultValue: '') as String,
      token: box.get('token', defaultValue: '') as String,
    );
  }

  static Future<void> save(String url, String token) async {
    final box = await _box();
    await box.put('url', normalizeUrl(url));
    await box.put('token', token.trim());
  }

  static Dio _dio() => Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 20),
        validateStatus: (_) => true,
      ));

  /// Returns null when reachable, otherwise the error.
  static Future<MonbooruError?> testConnection(String url) async {
    try {
      final res = await _dio().get('${normalizeUrl(url)}/health');
      if (res.statusCode == 200) return null;
      return MonbooruError(MonbooruErrorKind.http, '${res.statusCode}');
    } catch (e) {
      return MonbooruError(MonbooruErrorKind.unreachable,
          e is DioException ? e.message ?? e.type.name : '$e');
    }
  }

  /// Returns null on success, otherwise the error.
  static Future<MonbooruError?> send(Post post) async {
    final config = await load();
    if (!config.isComplete) {
      return const MonbooruError(MonbooruErrorKind.notConfigured);
    }

    final pageUrl = post.postUrl;
    final fileUrl = post.originalFile;
    final target = pageUrl.isNotEmpty ? pageUrl : fileUrl;
    if (target.isEmpty) return const MonbooruError(MonbooruErrorKind.noUrl);

    try {
      var res = await _post(config, target, post, pageUrl: pageUrl);
      // Page not supported by gallery-dl: fall back to the direct file.
      if (res.statusCode == 400 && target != fileUrl && fileUrl.isNotEmpty) {
        res = await _post(config, fileUrl, post, pageUrl: pageUrl);
      }
      final code = res.statusCode ?? 0;
      if (code == 200 || code == 202) return null;
      return switch (code) {
        401 => const MonbooruError(MonbooruErrorKind.invalidToken),
        403 => const MonbooruError(MonbooruErrorKind.noWriteScope),
        409 => const MonbooruError(MonbooruErrorKind.unavailable),
        503 => const MonbooruError(MonbooruErrorKind.apiDisabled),
        _ => MonbooruError(MonbooruErrorKind.http, '$code'),
      };
    } catch (e) {
      return MonbooruError(MonbooruErrorKind.unreachable,
          e is DioException ? e.message ?? e.type.name : '$e');
    }
  }

  static Future<Response> _post(
    MonbooruConfig config,
    String url,
    Post post, {
    required String pageUrl,
  }) {
    final options = <String, dynamic>{
      'via': 'boorusphere',
      if (post.tags.isNotEmpty) 'tags': post.tags,
      if (pageUrl.isNotEmpty) 'page_url': pageUrl,
    };
    return _dio().post(
      '${config.url}/api/v1/queue',
      data: {'url': url, 'options': options},
      options: Options(
        headers: {'Authorization': 'Bearer ${config.token}'},
        contentType: Headers.jsonContentType,
      ),
    );
  }
}
