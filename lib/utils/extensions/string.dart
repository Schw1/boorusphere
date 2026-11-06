import 'package:mime/mime.dart';
import 'package:path/path.dart';

extension StringExt on String {
  String get mimeType {
    return lookupMimeType(fileName) ?? 'application/octet-stream';
  }

  /// File name of a URL. Some APIs (e.g. Monbooru) serve media from paths
  /// without an extension; their URLs carry the real name as `?name=`.
  String get fileName {
    final uri = toUri();
    final base = basename(uri.path);
    if (extension(base).isEmpty) {
      final name = uri.queryParameters['name'];
      if (name != null && name.isNotEmpty && !name.contains('/')) {
        return name;
      }
    }
    return base;
  }

  String get fileNameNoExt {
    return withoutExtension(fileName);
  }

  String get fileExt {
    return extension(fileName).replaceFirst('.', '');
  }

  Uri toUri() {
    return Uri.parse(this);
  }

  List<String> toWordList() {
    return replaceAll(RegExp('\\s+'), ' ')
        .trim()
        .split(' ')
        .where((it) => it.isNotEmpty)
        .toList();
  }
}
