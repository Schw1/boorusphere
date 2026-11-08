import 'package:boorusphere/data/repository/booru/entity/post.dart';
import 'package:boorusphere/data/repository/booru/parser/booru_parser.dart';
import 'package:boorusphere/data/repository/server/entity/server.dart';
import 'package:deep_pick/deep_pick.dart';
import 'package:dio/dio.dart';

/// nhentai (API v2). Each gallery becomes one post: the timeline shows its
/// thumbnail, the viewer a Read button; pages and tag names are loaded from
/// the gallery itself when it is opened (see [NhentaiGallery]), because
/// search results only carry tag ids.
class NhentaiJsonParser extends BooruParser {
  static const parserId = 'nhentai.json';

  @override
  final id = parserId;

  @override
  final searchQuery = 'api/v2/search?query={tags}&page={page-id}';

  /// Web page of a gallery.
  @override
  final postUrl = 'g/{post-id}/';

  @override
  int get pageOffset => 1;

  @override
  final headers = const {'Accept': 'application/json'};

  @override
  List<BooruParserType> get type => [BooruParserType.search];

  static const imageHost = 'https://i.nhentai.net';
  static const thumbHost = 'https://t.nhentai.net';

  static bool isNhentai(Server? server) =>
      server != null &&
      (server.searchParserId == parserId ||
          server.searchUrl.contains('api/v2/search'));

  /// The search needs a non-empty query; this matches every gallery.
  static const matchAll = 'pages:>0';

  /// `order:`/`sort:` tags of the app's search, turned into nhentai's `sort`
  /// parameter (`popular-week` etc.). Everything else stays in the query.
  /// Choices of the sort button: '' is nhentai's default (newest first).
  static const sortOptions = [
    '',
    'popular-today',
    'popular-week',
    'popular-month',
    'popular',
  ];

  static const sortAliases = {
    'rank': 'popular-week',
    'popular-week': 'popular-week',
    'week': 'popular-week',
    'popular-today': 'popular-today',
    'today': 'popular-today',
    'day': 'popular-today',
    'popular-month': 'popular-month',
    'month': 'popular-month',
    'popular': 'popular',
    'popular-all': 'popular',
    'all': 'popular',
    'score': 'popular',
    // the default order of nhentai's search
    'date': '',
    'recent': '',
    'new': '',
  };

  /// Splits the app's search into nhentai's `query` and `sort`. `*` (the
  /// app's "everything") and rating tags are dropped; nhentai has neither.
  static ({String query, String sort, bool hadOrder}) splitQuery(
      String tags) {
    var sort = '';
    var hadOrder = false;
    final words = <String>[];
    for (final word in tags.split(RegExp(r'\s+'))) {
      if (word.isEmpty || word == '*' || word.startsWith('rating:')) continue;
      final m = RegExp(r'^(?:order|sort):(.+)$', caseSensitive: false)
          .firstMatch(word);
      if (m != null) {
        final alias = sortAliases[m.group(1)!.toLowerCase()];
        if (alias != null) {
          sort = alias;
          hadOrder = true;
          continue;
        }
      }
      words.add(word);
    }
    final query = words.join(' ');
    return (
      query: query.isEmpty ? matchAll : query,
      sort: sort,
      hadOrder: hadOrder,
    );
  }

  /// `galleries/123/thumb.webp` -> full URL on [host].
  static String mediaUrl(String host, Object? path) {
    final p = '${path ?? ''}'.trim();
    if (p.isEmpty) return '';
    if (p.startsWith('http://') || p.startsWith('https://')) return p;
    return '$host/${p.replaceFirst(RegExp(r'^/+'), '')}';
  }

  static bool _isPage(Object? data) =>
      data is Map &&
      data['result'] is List &&
      data.containsKey('per_page') &&
      data.containsKey('num_pages');

  @override
  bool canParsePage(Response res) => _isPage(res.data);

  @override
  Iterable<Post> parsePage(Server server, Response res) {
    final entries = List.from(res.data['result']);
    final result = <Post>[];
    final home = server.homepage.replaceFirst(RegExp(r'/+$'), '');
    for (final post in entries.whereType<Map<String, dynamic>>()) {
      if (pick(post, 'blacklisted').asBoolOrFalse()) continue;
      final id = pick(post, 'id').asIntOrNull() ?? -1;
      final pages = pick(post, 'num_pages').asIntOrNull() ?? 0;
      final thumb = mediaUrl(thumbHost, pick(post, 'thumbnail').value);
      if (id < 0 || pages <= 0 || thumb.isEmpty) continue;

      final width = pick(post, 'thumbnail_width').asIntOrNull() ?? -1;
      final height = pick(post, 'thumbnail_height').asIntOrNull() ?? -1;
      final english = pick(post, 'english_title').asStringOrNull() ?? '';
      final japanese = pick(post, 'japanese_title').asStringOrNull() ?? '';

      result.add(Post(
        id: id,
        // No single original file; the pages come from the gallery.
        originalFile: '',
        sampleFile: thumb,
        previewFile: thumb,
        width: width,
        height: height,
        sampleWidth: width,
        sampleHeight: height,
        previewWidth: width,
        previewHeight: height,
        serverId: server.id,
        postUrl: '$home/g/$id/',
        rateValue: 'e',
        score: pick(post, 'num_favorites').asIntOrNull() ?? 0,
        pageCount: pages,
        title: english.isNotEmpty ? english : japanese,
      ));
    }
    return result;
  }
}

/// A gallery as returned by `api/v2/galleries/{id}`.
class NhentaiGallery {
  const NhentaiGallery({
    required this.id,
    required this.title,
    required this.cover,
    required this.pages,
    required this.tags,
  });

  /// Parses the gallery JSON; null if it isn't one.
  static NhentaiGallery? fromJson(Object? data) {
    if (data is! Map || data['pages'] is! List) return null;
    final title = data['title'] is Map ? data['title'] as Map : const {};
    String text(Object? v) => v is String ? v : '';
    final pretty = text(title['english']).isNotEmpty
        ? text(title['english'])
        : text(title['pretty']).isNotEmpty
            ? text(title['pretty'])
            : text(title['japanese']);

    final pages = <String>[];
    for (final page in data['pages'] as List) {
      final url = page is Map
          ? NhentaiJsonParser.mediaUrl(NhentaiJsonParser.imageHost, page['path'])
          : '';
      if (url.isNotEmpty) pages.add(url);
    }

    final tags = <String, List<String>>{};
    if (data['tags'] is List) {
      for (final tag in data['tags'] as List) {
        if (tag is! Map) continue;
        final type = text(tag['type']);
        final name = text(tag['name']);
        if (type.isEmpty || name.isEmpty) continue;
        (tags[type] ??= []).add(name);
      }
    }

    final cover = data['cover'] is Map ? (data['cover'] as Map)['path'] : null;
    return NhentaiGallery(
      id: data['id'] is int ? data['id'] as int : int.tryParse('${data['id']}') ?? -1,
      title: pretty,
      cover: NhentaiJsonParser.mediaUrl(NhentaiJsonParser.thumbHost, cover),
      pages: pages,
      tags: tags,
    );
  }

  final int id;
  final String title;

  /// Large cover image, '' if the gallery has none.
  final String cover;

  /// Full-size page URLs in reading order.
  final List<String> pages;

  /// Tag names by nhentai's tag type (artist, group, parody, character, tag,
  /// language, category).
  final Map<String, List<String>> tags;

  /// The order the details page lists the tag types in.
  static const typeOrder = [
    'artist',
    'group',
    'parody',
    'character',
    'tag',
    'language',
    'category',
  ];

  /// A search token for [name] of [type], e.g. `tag:"big breasts"`.
  static String searchToken(String type, String name) =>
      name.contains(' ') ? '$type:"$name"' : '$type:$name';

  static String galleryApiUrl(Server server, int id) {
    final api = server.apiAddress.replaceFirst(RegExp(r'/+$'), '');
    return '$api/api/v2/galleries/$id';
  }
}
