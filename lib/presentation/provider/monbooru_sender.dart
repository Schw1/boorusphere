import 'dart:convert';

import 'package:boorusphere/constant/app.dart';
import 'package:boorusphere/data/repository/booru/entity/post.dart';
import 'package:boorusphere/presentation/provider/data_backup/data_backup.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_ce/hive.dart';

/// Sends posts to a monloader instance (the queue service behind Monsender),
/// which downloads them and files them into Monbooru.
///
/// The address is stored in its own Hive box (and is part of the backup), the
/// token in the iOS Keychain (this device only, never in Hive or a backup).
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

/// Result of [MonbooruSender.send]: the monloader job id, or an error.
class MonbooruSendResult {
  const MonbooruSendResult.queued(this.jobId) : error = null;
  const MonbooruSendResult.failed(MonbooruError this.error) : jobId = null;

  final int? jobId;
  final MonbooruError? error;
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

  static const _storage = FlutterSecureStorage(
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );
  static const _tokenKey = 'monloader_token';

  static Future<String> _readToken() async {
    try {
      return await _storage.read(key: _tokenKey) ?? '';
    } catch (e) {
      debugPrint('MonbooruSender._readToken: $e');
      return '';
    }
  }

  static Future<void> _writeToken(String token) async {
    if (token.isEmpty) {
      await _storage.delete(key: _tokenKey);
    } else {
      await _storage.write(key: _tokenKey, value: token);
    }
  }

  /// Older versions kept the token in the (unencrypted) Hive box. Moves it to
  /// the Keychain and removes it from the box file. Returns the token to use.
  static Future<String> _migrateLegacyToken(Box box, String current) async {
    final legacy = box.get('token');
    if (legacy is! String) return current;
    var token = current;
    if (token.isEmpty && legacy.isNotEmpty) {
      try {
        await _writeToken(legacy);
        token = legacy;
      } catch (e) {
        // Keep it in Hive for now rather than losing it.
        debugPrint('MonbooruSender: token not moved to the Keychain: $e');
        return legacy;
      }
    }
    await box.delete('token');
    // Hive appends to its file; compact so the old value is really gone.
    await box.compact();
    return token;
  }

  /// Moves a token stored by an older version into the Keychain. Call once at
  /// startup so the plain-text copy does not wait for the first use.
  static Future<void> migrate() async {
    try {
      await load();
    } catch (e) {
      debugPrint('MonbooruSender.migrate: $e');
    }
  }

  /// The settings as last read. Following a job asks for them every 2 s
  /// per post; without this each of those reads the box and the Keychain.
  /// Dropped whenever they are written ([save], [importBackup]).
  static MonbooruConfig? _cached;

  static Future<MonbooruConfig> load() async => _cached ??= await _read();

  static Future<MonbooruConfig> _read() async {
    final box = await _box();
    final token = await _migrateLegacyToken(box, await _readToken());
    return MonbooruConfig(
      url: box.get('url', defaultValue: '') as String,
      token: token,
    );
  }

  static Future<void> save(String url, String token) async {
    _cached = null;
    final box = await _box();
    await box.put('url', normalizeUrl(url));
    await _writeToken(token.trim());
    if (box.containsKey('token')) {
      await box.delete('token');
      await box.compact();
    }
    _cached = null;
  }

  static const backupKey = 'monloader';

  /// Only the monloader address goes into the backup; the token stays in the
  /// Keychain and has to be entered again after restoring on another device.
  /// The address; the token only with [withToken] ("Include login data").
  static Future<BackupItem> exportBackup({bool withToken = false}) async {
    final config = await load();
    return BackupItem(backupKey, {
      'url': config.url,
      if (withToken && config.token.isNotEmpty) 'token': config.token,
    });
  }

  /// Restores the address, and the token if the backup has one (made with
  /// "Include login data", or by older versions); it goes into the secure
  /// storage. Without one the current token is kept.
  static Future<void> importBackup(String src) async {
    final data = jsonDecode(src);
    if (data is! Map) return;
    final url = '${data['url'] ?? ''}';
    final token = '${data['token'] ?? ''}'.trim();
    if (url.isEmpty && token.isEmpty) return;
    _cached = null;
    final box = await _box();
    if (url.isNotEmpty) await box.put('url', normalizeUrl(url));
    if (token.isNotEmpty) await _writeToken(token);
    _cached = null;
  }

  /// One client for all requests to monloader, so its connection is kept
  /// open and reused. A client per request (as before) connects anew every
  /// time, which adds up when the jobs of a batch are polled every 2 s.
  /// Address and token are passed per request, so it never goes stale.
  static final Dio _client = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 20),
      validateStatus: (_) => true,
      // The app strips Dart's default User-Agent (see CustomHttpClient).
      headers: {'User-Agent': 'Boorusphere/${displayVersion('dev')}'},
    ),
  );

  /// Returns null when reachable, otherwise the error.
  static Future<MonbooruError?> testConnection(String url) async {
    try {
      final res = await _client.get('${normalizeUrl(url)}/health');
      if (res.statusCode == 200) return null;
      return MonbooruError(MonbooruErrorKind.http, '${res.statusCode}');
    } catch (e) {
      return MonbooruError(
        MonbooruErrorKind.unreachable,
        e is DioException ? e.message ?? e.type.name : '$e',
      );
    }
  }

  /// Queues [post] in monloader. Returns the job id on success.
  static Future<MonbooruSendResult> send(Post post) async {
    final config = await load();
    if (!config.isComplete) {
      return const MonbooruSendResult.failed(
        MonbooruError(MonbooruErrorKind.notConfigured),
      );
    }

    final pageUrl = post.postUrl;
    final fileUrl = post.originalFile;
    final target = pageUrl.isNotEmpty ? pageUrl : fileUrl;
    if (target.isEmpty) {
      return const MonbooruSendResult.failed(
        MonbooruError(MonbooruErrorKind.noUrl),
      );
    }

    try {
      var res = await _post(config, target, post, pageUrl: pageUrl);
      // Page not supported by gallery-dl: fall back to the direct file.
      if (res.statusCode == 400 && target != fileUrl && fileUrl.isNotEmpty) {
        res = await _post(config, fileUrl, post, pageUrl: pageUrl);
      }
      final code = res.statusCode ?? 0;
      if (code == 200 || code == 202) {
        return MonbooruSendResult.queued(jobIdOf(res.data) ?? 0);
      }
      return MonbooruSendResult.failed(errorOf(code, messageOf(res.data)));
    } catch (e) {
      return MonbooruSendResult.failed(
        MonbooruError(
          MonbooruErrorKind.unreachable,
          e is DioException ? e.message ?? e.type.name : '$e',
        ),
      );
    }
  }

  /// [message] is monloader's reason, shown with other HTTP errors (e.g.
  /// `400: unsupported URL`).
  @visibleForTesting
  static MonbooruError errorOf(int code, [String message = '']) =>
      switch (code) {
        401 => const MonbooruError(MonbooruErrorKind.invalidToken),
        403 => const MonbooruError(MonbooruErrorKind.noWriteScope),
        409 => const MonbooruError(MonbooruErrorKind.unavailable),
        503 => const MonbooruError(MonbooruErrorKind.apiDisabled),
        _ => MonbooruError(
          MonbooruErrorKind.http,
          message.isEmpty ? '$code' : '$code: $message',
        ),
      };

  /// The reason in an error answer: `error`/`message`/`detail` of a JSON
  /// body, or a short plain-text body. Empty if there is none.
  @visibleForTesting
  static String messageOf(Object? data) {
    final body = data is String ? (_tryJson(data) ?? data) : data;
    String text(Object? v) => v is String ? v.trim() : '';
    if (body is Map) {
      for (final key in ['error', 'message', 'detail']) {
        final value = body[key];
        if (value is Map) {
          final nested = text(value['message']).isNotEmpty
              ? text(value['message'])
              : text(value['code']);
          if (nested.isNotEmpty) return nested;
        }
        if (text(value).isNotEmpty) return text(value);
      }
      return '';
    }
    final plain = text(body);
    // an HTML error page says nothing useful
    if (plain.isEmpty || plain.startsWith('<')) return '';
    return plain.length > 200 ? '${plain.substring(0, 200)}…' : plain;
  }

  /// `job_id` of a 202 answer, or `id` of a job returned inline (200).
  @visibleForTesting
  static int? jobIdOf(Object? data) {
    final map = data is String ? _tryJson(data) : data;
    if (map is! Map) return null;
    final id = map['job_id'] ?? map['id'];
    return id is int ? id : int.tryParse('$id');
  }

  static Object? _tryJson(String s) {
    try {
      return jsonDecode(s);
    } catch (_) {
      return null;
    }
  }

  /// Current state of a monloader job. Needs the `read` scope; a token with
  /// only `write` gets [MonbooruJobLookup.noReadScope].
  static Future<MonbooruJobLookup> fetchJob(int id) async {
    final config = await load();
    if (!config.isComplete) return const MonbooruJobLookup.error();
    try {
      final res = await _client.get(
        '${config.url}/api/v1/queue/$id',
        options: Options(
          headers: {'Authorization': 'Bearer ${config.token}'},
          responseType: ResponseType.json,
        ),
      );
      final code = res.statusCode ?? 0;
      if (code == 403) return const MonbooruJobLookup.noReadScope();
      final data = res.data is String ? _tryJson(res.data) : res.data;
      if (code == 200 && data is Map) {
        return MonbooruJobLookup.found(MonbooruJob.fromJson(data));
      }
      return const MonbooruJobLookup.error();
    } catch (e) {
      return const MonbooruJobLookup.error();
    }
  }

  /// Tags handed to monloader with a post. Galleries (nhentai) send none:
  /// their tags in the app are search tokens like `tag:"big breasts"` or
  /// `language:english`, which monloader would store verbatim, and
  /// gallery-dl already reads the gallery's tags with their categories.
  ///
  /// monloader takes at most [maxTags] tags (`400: at most 64 tags`);
  /// posts with more (rule34 often) send the first ones, gallery-dl reads
  /// the full list from the post anyway.
  @visibleForTesting
  static List<String> tagsFor(Post post) {
    final isGallery = post.pageCount > 0 && post.originalFile.isEmpty;
    if (isGallery) return const [];
    final tags = post.tags.toSet().where((it) => it.isNotEmpty).toList();
    return tags.length > maxTags ? tags.sublist(0, maxTags) : tags;
  }

  static const maxTags = 64;

  static Future<Response> _post(
    MonbooruConfig config,
    String url,
    Post post, {
    required String pageUrl,
  }) {
    final options = <String, dynamic>{
      'via': 'boorusphere',
      if (tagsFor(post) case final tags when tags.isNotEmpty) 'tags': tags,
      if (pageUrl.isNotEmpty) 'page_url': pageUrl,
    };
    return _client.post(
      '${config.url}/api/v1/queue',
      data: {'url': url, 'options': options},
      options: Options(
        headers: {'Authorization': 'Bearer ${config.token}'},
        contentType: Headers.jsonContentType,
      ),
    );
  }
}

/// What came out of a monloader job, as far as the app cares.
enum MonbooruOutcome { added, duplicate, skipped, failed }

/// A monloader job (`GET /api/v1/queue/{id}`).
class MonbooruJob {
  const MonbooruJob({
    required this.id,
    required this.status,
    this.created = 0,
    this.duplicate = 0,
    this.skipped = 0,
    this.failed = 0,
    this.error = '',
  });

  factory MonbooruJob.fromJson(Map data) {
    final summary = data['summary'] is Map ? data['summary'] as Map : const {};
    int n(Object? v) => v is int ? v : int.tryParse('$v') ?? 0;
    var error = '${data['error'] ?? ''}';
    if (error.isEmpty && data['items'] is List) {
      for (final item in data['items'] as List) {
        if (item is Map && '${item['error'] ?? ''}'.isNotEmpty) {
          error = '${item['error']}';
          break;
        }
      }
    }
    return MonbooruJob(
      id: n(data['id']),
      status: '${data['status'] ?? ''}',
      created: n(summary['created']) + n(summary['replaced']),
      duplicate: n(summary['duplicate']) + n(summary['enriched']),
      skipped: n(summary['skipped']),
      failed: n(summary['failed']),
      error: error,
    );
  }

  final int id;
  final String status;
  final int created;
  final int duplicate;
  final int skipped;
  final int failed;
  final String error;

  bool get isFinished => status != 'queued' && status != 'running';

  MonbooruOutcome get outcome {
    if (created > 0) return MonbooruOutcome.added;
    if (duplicate > 0) return MonbooruOutcome.duplicate;
    if (status == 'failed' ||
        status == 'canceled' ||
        status == 'interrupted' ||
        failed > 0) {
      return MonbooruOutcome.failed;
    }
    return MonbooruOutcome.skipped;
  }
}

/// Result of [MonbooruSender.fetchJob].
class MonbooruJobLookup {
  const MonbooruJobLookup.found(MonbooruJob this.job) : noRead = false;
  const MonbooruJobLookup.noReadScope() : job = null, noRead = true;
  const MonbooruJobLookup.error() : job = null, noRead = false;

  final MonbooruJob? job;
  final bool noRead;
}
