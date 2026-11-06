import 'package:boorusphere/data/repository/booru/entity/post.dart';
import 'package:boorusphere/data/repository/booru/parser/booru_parser.dart';
import 'package:boorusphere/data/repository/server/entity/server.dart';
import 'package:boorusphere/presentation/provider/booru/suggestion_state.dart';
import 'package:deep_pick/deep_pick.dart';
import 'package:dio/dio.dart';

/// Native support for Monbooru (https://github.com/monbooru/monbooru).
///
/// All API endpoints, including media, need a bearer token with `read`
/// scope; see ServerAuthStore. Media URLs carry a `name` query parameter
/// (ignored by Monbooru) so the app can tell the file type and name a
/// download, because the API paths have no file extension.
class MonbooruJsonParser extends BooruParser {
  static const parserId = 'Monbooru.json';

  @override
  final id = parserId;

  @override
  final searchQuery =
      'api/v1/images/search?q={tags}&page={page-id}&limit={post-limit}';

  @override
  final suggestionQuery =
      'api/v1/tags?q={tag-part}&limit={post-limit}&sort=usage';

  /// Web UI page of an image (shown as "Location" in post details).
  @override
  final postUrl = 'images/{post-id}';

  @override
  int get pageOffset => 1;

  @override
  final headers = const {'Accept': 'application/json'};

  @override
  List<BooruParserType> get type => [
        BooruParserType.search,
        BooruParserType.suggestion,
      ];

  static bool isMonbooru(Server server) =>
      server.searchParserId == parserId ||
      server.searchUrl.contains('api/v1/images/search');

  static bool _isPaged(Object? data) =>
      data is Map &&
      data['results'] is List &&
      data.containsKey('total') &&
      data.containsKey('limit');

  @override
  bool canParsePage(Response res) {
    final data = res.data;
    if (!_isPaged(data)) return false;
    final results = (data as Map)['results'] as List;
    if (results.isEmpty) {
      return res.requestOptions.uri.path.endsWith('/api/v1/images/search');
    }
    final first = results.first;
    return first is Map &&
        first.containsKey('sha256') &&
        first.containsKey('file_type');
  }

  static const _extByType = {
    'jpeg': 'jpg',
    'png': 'png',
    'webp': 'webp',
    'avif': 'avif',
    'jxl': 'jxl',
    'gif': 'gif',
    'mp4': 'mp4',
    'webm': 'webm',
  };

  // Flutter cannot decode these; Monbooru renders a WebP still for them.
  static const _needsStill = {'avif', 'jxl'};

  static String _rateValue(String rating) => switch (rating) {
        'general' => 's',
        'sensitive' => 'sensitive',
        'explicit' => 'e',
        _ => 'q',
      };

  @override
  List<Post> parsePage(Server server, Response res) {
    final api = server.apiAddress.replaceFirst(RegExp(r'/+$'), '');
    final entries = List.from(res.data['results']);
    final result = <Post>[];
    for (final post in entries.whereType<Map<String, dynamic>>()) {
      final id = pick(post, 'id').asIntOrNull() ?? -1;
      if (id < 0 || result.any((it) => it.id == id)) continue;
      if (pick(post, 'is_missing').asBoolOrFalse()) continue;

      final fileType = pick(post, 'file_type').asStringOrNull() ?? '';
      final ext = _extByType[fileType];
      // Archives (cbz) are not supported by the viewer.
      if (ext == null) continue;

      final hash = pick(post, 'md5').asStringOrNull() ??
          pick(post, 'sha256').asStringOrNull() ??
          '$id';
      final name = Uri.encodeQueryComponent('$hash.$ext');
      final base = '$api/api/v1/images/$id';
      final original = '$base/file?name=$name';
      final sample = _needsStill.contains(fileType)
          ? '$base/still?name=${Uri.encodeQueryComponent('$hash.webp')}'
          : original;
      final preview =
          '$base/thumbnail?name=${Uri.encodeQueryComponent('$hash.jpg')}';

      var width = pick(post, 'width').asIntOrNull() ?? 0;
      var height = pick(post, 'height').asIntOrNull() ?? 0;
      if (width <= 0 || height <= 0) {
        width = 1000;
        height = 1000;
      }

      final artist = <String>[];
      final character = <String>[];
      final copyright = <String>[];
      final meta = <String>[];
      final general = <String>[];
      var rating = '';
      for (final tag in pick(post, 'tags').asListOrEmpty((p) => p.asMapOrEmpty())) {
        final tagName = '${tag['name'] ?? ''}'.trim();
        if (tagName.isEmpty) continue;
        switch ('${tag['category'] ?? ''}') {
          case 'rating':
            rating = tagName;
          case 'artist':
            artist.add(tagName);
          case 'character':
            character.add(tagName);
          case 'copyright':
            copyright.add(tagName);
          case 'meta':
            meta.add(tagName);
          default:
            general.add(tagName);
        }
      }

      final sourceUrl = pick(post, 'url').asStringOrNull() ?? '';
      final originalSource = pick(post, 'original_source').asStringOrNull() ?? '';

      result.add(
        Post(
          id: id,
          originalFile: original,
          sampleFile: sample,
          previewFile: preview,
          tags: [...artist, ...character, ...copyright, ...general, ...meta],
          tagsArtist: artist,
          tagsCharacter: character,
          tagsCopyright: copyright,
          tagsGeneral: general,
          tagsMeta: meta,
          width: width,
          height: height,
          serverId: server.id,
          postUrl: server.postUrlOf(id),
          rateValue: _rateValue(rating),
          source: sourceUrl.isNotEmpty ? sourceUrl : originalSource,
        ),
      );
    }

    return result;
  }

  @override
  bool canParseSuggestion(Response res) {
    final data = res.data;
    if (!_isPaged(data)) return false;
    final results = (data as Map)['results'] as List;
    if (results.isEmpty) {
      return res.requestOptions.uri.path.endsWith('/api/v1/tags');
    }
    final first = results.first;
    return first is Map &&
        first.containsKey('usage_count') &&
        first.containsKey('is_alias');
  }

  @override
  Set<Suggestion> parseSuggestion(Server server, Response res) {
    final entries = List.from(res.data['results']);
    final result = <Suggestion>{};
    for (final entry in entries.whereType<Map<String, dynamic>>()) {
      final name = pick(entry, 'name').asStringOrNull() ?? '';
      final category = pick(entry, 'category').asStringOrNull() ?? '';
      final usage = pick(entry, 'usage_count').asIntOrNull() ?? 0;
      // Rating tags are searched as rating:<level>, not as plain tags.
      if (name.isEmpty || category == 'rating') continue;
      result.add(Suggestion(name, usage));
    }
    return result;
  }
}
