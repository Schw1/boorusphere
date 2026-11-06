import 'dart:async';
import 'dart:typed_data';

import 'package:boorusphere/domain/provider.dart';
import 'package:boorusphere/data/repository/server/server_auth_store.dart';
import 'package:boorusphere/presentation/utils/extensions/buildcontext.dart';
import 'package:boorusphere/utils/extensions/string.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Server icon, resolved like a browser does:
/// 1. `/favicon.ico` of the server;
/// 2. if that returns a page instead (e.g. a login page, as Monbooru does
///    for clients without a web session), the icons linked in that page,
///    otherwise the icons linked in the start page;
/// 3. only for public hosts, the DuckDuckGo icon service as a last resort.
/// Local addresses are never sent to DuckDuckGo.
class Favicon extends ConsumerWidget {
  const Favicon({
    super.key,
    required this.url,
    this.size,
    this.iconSize,
    this.shape,
  });

  final String url;
  final double? size;
  final double? iconSize;
  final BoxShape? shape;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final iconSize = this.iconSize ?? context.iconTheme.size;
    final fallbackWidget = Icon(Icons.public, size: iconSize);
    final uri = url.toUri();
    final valid = uri.hasAuthority &&
        (uri.scheme == 'http' || uri.scheme == 'https');

    return SizedBox(
      width: size ?? context.iconTheme.size,
      height: size ?? context.iconTheme.size,
      child: Center(
        child: !valid
            ? fallbackWidget
            : FutureBuilder<Uint8List?>(
                future: FaviconLoader.load(
                    'Boorusphere/${ref.read(versionRepoProvider).current}', uri),
                builder: (context, snapshot) {
                  final data = snapshot.data;
                  if (data == null) return fallbackWidget;
                  final image = Image.memory(
                    data,
                    width: iconSize,
                    height: iconSize,
                    fit: BoxFit.contain,
                    gaplessPlayback: true,
                    errorBuilder: (_, __, ___) => fallbackWidget,
                  );
                  return shape == BoxShape.circle
                      ? ClipOval(child: image)
                      : image;
                },
              ),
      ),
    );
  }
}

class FaviconLoader {
  FaviconLoader._();

  static final _cache = <String, Future<Uint8List?>>{};
  static Dio? _dio;

  /// Own lightweight client: no cookie jar (a login page must not leave a
  /// session cookie behind) and no retries.
  static Dio _client(String userAgent) => _dio ??= Dio(BaseOptions(
        headers: {'User-Agent': userAgent},
        connectTimeout: const Duration(seconds: 8),
      ));

  static Future<Uint8List?> load(String userAgent, Uri site) {
    final dio = _client(userAgent);
    final origin = '${site.scheme}://${site.authority}';
    return _cache.putIfAbsent(origin, () {
      final future = _resolve(dio, Uri.parse(origin));
      // Don't keep a miss forever (server offline, network change).
      future.then((data) {
        if (data == null) {
          Timer(const Duration(minutes: 2), () => _cache.remove(origin));
        }
      });
      return future;
    });
  }

  static Future<Uint8List?> _resolve(Dio dio, Uri origin) async {
    try {
      final first = await _get(dio, origin.resolve('/favicon.ico'));
      if (first != null && _isImage(first.data)) return first.data;

      final page = first != null && _isHtml(first.data)
          ? first
          : await _get(dio, origin.resolve('/'));
      if (page != null && _isHtml(page.data)) {
        final html = String.fromCharCodes(page.data.take(256 * 1024));
        for (final href in _iconLinks(html)) {
          final target = page.uri.resolve(href);
          if (target.scheme != 'http' && target.scheme != 'https') continue;
          final icon = await _get(dio, target);
          if (icon != null && _isImage(icon.data)) return icon.data;
        }
      }

      if (!ServerAuthStore.isLocalHost(origin.host)) {
        final ddg = await _get(dio,
            Uri.parse('https://icons.duckduckgo.com/ip3/${origin.host}.ico'));
        if (ddg != null && _isImage(ddg.data)) return ddg.data;
      }
    } catch (e) {
      debugPrint('Favicon($origin): $e');
    }
    return null;
  }

  static Future<({Uint8List data, Uri uri})?> _get(Dio dio, Uri uri) async {
    try {
      final res = await dio.getUri<List<int>>(
        uri,
        options: Options(
          responseType: ResponseType.bytes,
          followRedirects: true,
          validateStatus: (it) => it == 200,
          receiveTimeout: const Duration(seconds: 10),
          sendTimeout: const Duration(seconds: 10),
          headers: {'Accept': 'image/*,text/html;q=0.9,*/*;q=0.5'},
        ),
      );
      final data = res.data;
      if (data == null || data.isEmpty) return null;
      return (data: Uint8List.fromList(data), uri: res.realUri);
    } catch (_) {
      return null;
    }
  }

  /// Formats Flutter can decode (SVG is not one of them).
  static bool _isImage(Uint8List b) {
    bool starts(List<int> sig) {
      if (b.length < sig.length) return false;
      for (var i = 0; i < sig.length; i++) {
        if (b[i] != sig[i]) return false;
      }
      return true;
    }

    return starts([0x89, 0x50, 0x4E, 0x47]) || // PNG
        starts([0xFF, 0xD8, 0xFF]) || // JPEG
        starts([0x47, 0x49, 0x46]) || // GIF
        starts([0x00, 0x00, 0x01, 0x00]) || // ICO
        starts([0x42, 0x4D]) || // BMP
        (b.length > 12 &&
            starts([0x52, 0x49, 0x46, 0x46]) &&
            String.fromCharCodes(b.sublist(8, 12)) == 'WEBP');
  }

  static bool _isHtml(Uint8List b) {
    final head =
        String.fromCharCodes(b.take(512)).trimLeft().toLowerCase();
    return head.startsWith('<!doctype html') || head.startsWith('<html');
  }

  static final _linkTag = RegExp(r'<link\b[^>]*>', caseSensitive: false);
  static final _rel = RegExp(r'''rel\s*=\s*["']([^"']*)["']''',
      caseSensitive: false);
  static final _href = RegExp(r'''href\s*=\s*["']([^"']+)["']''',
      caseSensitive: false);

  /// `<link rel="icon|shortcut icon|apple-touch-icon" href=…>`, SVGs skipped.
  static List<String> _iconLinks(String html) {
    final result = <String>[];
    for (final tag in _linkTag.allMatches(html).map((m) => m.group(0)!)) {
      final rel = _rel.firstMatch(tag)?.group(1)?.toLowerCase() ?? '';
      if (!rel.split(RegExp(r'\s+')).any((r) => r.contains('icon'))) continue;
      final href = _href.firstMatch(tag)?.group(1)?.trim();
      if (href == null || href.isEmpty) continue;
      if (href.toLowerCase().split('?').first.endsWith('.svg')) continue;
      if (tag.toLowerCase().contains('image/svg')) continue;
      result.add(href.replaceAll('&amp;', '&'));
    }
    return result;
  }
}
