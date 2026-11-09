import 'package:boorusphere/data/repository/booru/entity/post.dart';
import 'package:boorusphere/data/repository/server/entity/server.dart';

/// A note on an image (mostly a translated speech bubble), in pixels of
/// the original image.
class PostNote {
  const PostNote({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.text,
  });

  final double x;
  final double y;
  final double width;
  final double height;

  /// Plain text (the API gives HTML).
  final String text;
}

/// Notes of Danbooru and Moebooru (yande.re, konachan) posts.
class PostNotes {
  PostNotes._();

  /// Tags that mean a post has (translation) notes. Other posts aren't
  /// asked, so viewing doesn't cost a request per image.
  static const markerTags = {
    'translated',
    'partially_translated',
    'check_translation',
  };

  static bool mayHaveNotes(Post post) =>
      post.originalFile.isNotEmpty && post.tags.any(markerTags.contains);

  static bool _isDanbooru(Server server) =>
      server.searchParserId == 'Danbooru.json' ||
      server.searchUrl.contains('posts.json');

  static bool _isMoebooru(Server server) =>
      server.searchParserId == 'Moebooru.json' ||
      (server.searchUrl.contains('post.json') && !_isDanbooru(server));

  /// Where the notes of [post] are, or null if [server] has none.
  static String? urlOf(Server server, Post post) {
    if (!mayHaveNotes(post)) return null;
    final api = server.apiAddress.replaceFirst(RegExp(r'/+$'), '');
    if (_isDanbooru(server)) {
      return '$api/notes.json?search[post_id]=${post.id}'
          '&search[is_active]=true&limit=200';
    }
    if (_isMoebooru(server)) return '$api/note.json?post_id=${post.id}';
    return null;
  }

  /// Notes of an API answer (both have x, y, width, height, body,
  /// is_active). Inactive, empty and broken ones are left out.
  static List<PostNote> parse(Object? data) {
    if (data is! List) return const [];
    double? n(Object? v) => v is num ? v.toDouble() : double.tryParse('$v');
    final result = <PostNote>[];
    for (final it in data) {
      if (it is! Map || it['is_active'] == false) continue;
      final x = n(it['x']), y = n(it['y']);
      final w = n(it['width']), h = n(it['height']);
      final text = toText('${it['body'] ?? ''}');
      if (x == null || y == null || w == null || h == null) continue;
      if (w <= 0 || h <= 0 || text.isEmpty) continue;
      result.add(PostNote(x: x, y: y, width: w, height: h, text: text));
    }
    return result;
  }

  static const _entities = {
    '&amp;': '&',
    '&lt;': '<',
    '&gt;': '>',
    '&quot;': '"',
    '&#39;': "'",
    '&apos;': "'",
    '&nbsp;': ' ',
  };

  /// Note HTML as plain text: line breaks kept, tags dropped, common
  /// entities decoded.
  static String toText(String html) {
    var text = html
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'</(p|div)>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<[^>]*>'), '');
    _entities.forEach((entity, char) => text = text.replaceAll(entity, char));
    text = text.replaceAllMapped(RegExp(r'&#(\d+);'),
        (m) => String.fromCharCode(int.tryParse(m.group(1)!) ?? 32));
    return text
        .split('\n')
        .map((it) => it.trim())
        .where((it) => it.isNotEmpty)
        .join('\n');
  }
}
