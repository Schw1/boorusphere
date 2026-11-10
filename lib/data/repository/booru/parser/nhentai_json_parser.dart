import 'package:boorusphere/data/repository/booru/entity/post.dart';
import 'package:boorusphere/data/repository/booru/nhentai_tags.dart';
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

  /// Choices of the language button ('' = all languages).
  static const languages = ['', 'english', 'japanese', 'chinese'];

  /// Adds `language:<language>` unless the search names a language itself.
  static String withLanguage(String query, String language) {
    if (language.isEmpty ||
        RegExp(r'(^|\s)-?language:', caseSensitive: false).hasMatch(query)) {
      return query;
    }
    final token = 'language:$language';
    return query.trim().isEmpty || query.trim() == '*'
        ? token
        : '$query $token';
  }

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
  /// Words of a search; a quoted part (`tag:"big breasts"`, `"two words"`)
  /// is one word.
  static final _words = RegExp(r'-?[^\s"]*"[^"]*"?|\S+');

  static ({String query, String sort, bool hadOrder}) splitQuery(String tags) {
    var sort = '';
    var hadOrder = false;
    final words = <String>[];
    for (final word in _words.allMatches(tags).map((it) => it.group(0)!)) {
      if (word.isEmpty || word == '*' || word.startsWith('rating:')) continue;
      final m = RegExp(
        r'^(?:order|sort):(.+)$',
        caseSensitive: false,
      ).firstMatch(word);
      if (m != null) {
        final alias = sortAliases[m.group(1)!.toLowerCase()];
        if (alias != null) {
          sort = alias;
          hadOrder = true;
          continue;
        }
      }
      words.add(NhentaiTags.instance.toQuery(word));
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
  Iterable<Post> parsePage(Server server, Response res) => postsOf(
    server,
    res.data['result'] is List ? res.data['result'] as List : const [],
  );

  /// Posts of a list of galleries, in the shape of search results. Also
  /// takes the shape of a full gallery (thumbnail as `{path, width,
  /// height}`, title as `{english, japanese, pretty}`, a `pages` list), so
  /// related galleries work in either form.
  static List<Post> postsOf(Server server, Iterable<Object?> entries) {
    final result = <Post>[];
    for (final entry in entries) {
      if (entry is! Map) continue;
      final post = postOf(server, Map<String, dynamic>.from(entry));
      if (post != null) result.add(post);
    }
    return result;
  }

  static Post? postOf(Server server, Map<String, dynamic> post) {
    if (pick(post, 'blacklisted').asBoolOrFalse()) return null;
    final id = pick(post, 'id').asIntOrNull() ?? -1;
    final pages =
        pick(post, 'num_pages').asIntOrNull() ??
        (post['pages'] is List ? (post['pages'] as List).length : 0);
    final thumbData = post['thumbnail'];
    final thumbPath = thumbData is Map ? thumbData['path'] : thumbData;
    final thumb = mediaUrl(thumbHost, thumbPath);
    if (id < 0 || pages <= 0 || thumb.isEmpty) return null;

    int size(String flat, String nested) =>
        pick(post, flat).asIntOrNull() ??
        (thumbData is Map ? pick(thumbData, nested).asIntOrNull() : null) ??
        -1;
    final width = size('thumbnail_width', 'width');
    final height = size('thumbnail_height', 'height');

    final titles = post['title'] is Map ? post['title'] as Map : const {};
    String text(Object? v) => v is String ? v : '';
    final title = [
      text(post['english_title']),
      text(titles['english']),
      text(titles['pretty']),
      text(post['japanese_title']),
      text(titles['japanese']),
    ].firstWhere((it) => it.isNotEmpty, orElse: () => '');

    final home = server.homepage.replaceFirst(RegExp(r'/+$'), '');
    return Post(
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
      title: title,
      // tag ids -> search tokens, once the tag list is loaded
      tags: NhentaiTags.instance.tokensOf(
        pick(post, 'tag_ids').asListOrEmpty((it) => it.asIntOrNull() ?? -1),
      ),
    );
  }

  /// Related galleries: a plain list or `{result: [...]}`.
  static List<Post> parseRelated(Server server, Object? data) {
    final list = data is List
        ? data
        : data is Map && data['result'] is List
        ? data['result'] as List
        : const [];
    return postsOf(server, list);
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
          ? NhentaiJsonParser.mediaUrl(
              NhentaiJsonParser.imageHost,
              page['path'],
            )
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
      id: data['id'] is int
          ? data['id'] as int
          : int.tryParse('${data['id']}') ?? -1,
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

  /// How a tag of the gallery is searched for in the app, e.g.
  /// `big_breasts` or `artist:some_one` (see [NhentaiTags.displayOf]).
  static String searchToken(String type, String name) =>
      NhentaiTags.instance.displayOf(type, name);

  /// Readable name of such a word: `artist:some_one` -> `some one`.
  static String labelOf(String token) => token
      .replaceFirst(RegExp('^-?(${nhentaiTagTypes.join('|')}):'), '')
      .replaceAll('"', '')
      .replaceAll('_', ' ');

  static String galleryApiUrl(Server server, int id) {
    final api = server.apiAddress.replaceFirst(RegExp(r'/+$'), '');
    return '$api/api/v2/galleries/$id';
  }

  static String relatedApiUrl(Server server, int id) =>
      '${galleryApiUrl(server, id)}/related';
}
