import 'dart:convert';

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

  static Future<MonbooruConfig> load() async {
    final box = await _box();
    final token = await _migrateLegacyToken(box, await _readToken());
    return MonbooruConfig(
      url: box.get('url', defaultValue: '') as String,
      token: token,
    );
  }

  static Future<void> save(String url, String token) async {
    final box = await _box();
    await box.put('url', normalizeUrl(url));
    await _writeToken(token.trim());
    if (box.containsKey('token')) {
      await box.delete('token');
      await box.compact();
    }
  }

  static const backupKey = 'monloader';

  /// Only the monloader address goes into the backup; the token stays in the
  /// Keychain and has to be entered again after restoring on another device.
  static Future<BackupItem> exportBackup() async {
    final config = await load();
    return BackupItem(backupKey, {'url': config.url});
  }

  /// Restores the address. A token is only present in backups made by older
  /// versions; it is moved into the Keychain. Without one the current token is
  /// kept.
  static Future<void> importBackup(String src) async {
    final data = jsonDecode(src);
    if (data is! Map) return;
    final url = '${data['url'] ?? ''}';
    final token = '${data['token'] ?? ''}'.trim();
    if (url.isEmpty && token.isEmpty) return;
    final box = await _box();
    if (url.isNotEmpty) await box.put('url', normalizeUrl(url));
    if (token.isNotEmpty) await _writeToken(token);
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
