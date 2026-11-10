import 'package:boorusphere/data/repository/booru/entity/page_option.dart';
import 'package:boorusphere/data/repository/booru/parser/nhentai_json_parser.dart';
import 'package:boorusphere/presentation/provider/settings/entity/booru_rating.dart';
import 'package:boorusphere/utils/extensions/string.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:hive_ce/hive.dart';

part 'server.freezed.dart';
part 'server.g.dart';

@freezed
abstract class Server with _$Server {
  @HiveType(typeId: 2, adapterName: 'ServerAdapter')
  const factory Server({
    @HiveField(0, defaultValue: '') @Default('') String id,
    @HiveField(1, defaultValue: '') @Default('') String homepage,
    @HiveField(2, defaultValue: '') @Default('') String postUrl,
    @HiveField(3, defaultValue: '') @Default('') String searchUrl,
    @HiveField(4, defaultValue: '') @Default('') String apiAddr,
    @HiveField(7, defaultValue: '') @Default('') String tagSuggestionUrl,
    @HiveField(8, defaultValue: '') @Default('') String alias,
    @HiveField(9, defaultValue: '') @Default('') String searchParserId,
    @HiveField(10, defaultValue: '') @Default('') String suggestionParserId,
    @HiveField(11, defaultValue: '') @Default('') String urlSuffix,
  }) = _Server;

  factory Server.fromJson(Map<String, dynamic> json) => _$ServerFromJson(json);

  const Server._();

  bool get canSuggestTags =>
      tagSuggestionUrl.contains('{tag-part}') ||
      // nhentai: suggestions from the downloaded tag list (NhentaiTags)
      NhentaiJsonParser.isNhentai(this);

  String searchUrlOf(PageOption option, {required int page}) {
    final query = option.query.trim();
    var tags = query.isEmpty ? Server.defaultTag : query;
    if (searchUrl.contains('api/v2/search')) {
      // nhentai: everything is explicit (no rating), `order:` tags become
      // its sort parameter, and the query must not be empty
      final split = NhentaiJsonParser.splitQuery(
        NhentaiJsonParser.withLanguage(tags, option.language),
      );
      // an order: tag in the search wins over the sort button
      final order = split.sort.isNotEmpty || split.hadOrder
          ? split.sort
          : option.sort;
      final sort = order.isEmpty ? '' : '&sort=$order';
      return '$homepage/$searchUrl$urlSuffix$sort'
          .replaceAll('{tags}', Uri.encodeComponent(split.query))
          .replaceAll('{page-id}', '$page')
          .replaceAll('{post-offset}', (page * option.limit).toString())
          .replaceAll('{post-limit}', '${option.limit}');
    }
    if (searchUrl.contains('api/v1/images/search')) {
      // Monbooru: no catch-all tag, and its own rating levels
      if (tags == Server.defaultTag) tags = '';
      tags += ' ${_monbooruRateString(option.searchRating)}';
    } else if (searchUrl.toUri().queryParameters.containsKey('offset')) {
      // Szurubooru has exclusive-way (but still same shit) of rating
      tags += ' ${_szuruRateString(option.searchRating)}';
    } else if (searchUrl.contains('api/v1/json/search')) {
      // booru-on-rails didn't support rating
      tags = tags.replaceAll('rating:', '');
    } else {
      tags += ' ${_rateString(option.searchRating)}';
    }
    var extraParams = '';
    // Sort button: random order and an order:/sort: tag typed into the
    // search take precedence.
    if (!option.random &&
        option.sort.isNotEmpty &&
        sortOptions.contains(option.sort) &&
        !_typedOrder.hasMatch(query)) {
      final sort = _sortOrder(option.sort);
      tags += sort.tag;
      extraParams += sort.params;
    }
    if (option.random) {
      final random = _randomOrder(option.seed);
      tags += random.tag;
      extraParams = random.params;
    }
    tags = Uri.encodeComponent(tags.trim());

    return '$homepage/$searchUrl$urlSuffix$extraParams'
        .replaceAll('{tags}', tags)
        .replaceAll('{page-id}', '$page')
        .replaceAll('{post-offset}', (page * option.limit).toString())
        .replaceAll('{post-limit}', '${option.limit}');
  }

  String suggestionUrlsOf(String query) {
    final url = '$homepage/$tagSuggestionUrl$urlSuffix'
        .replaceAll('{post-limit}', '$tagSuggestionLimit')
        .replaceAll('{tag-limit}', '$tagSuggestionLimit');

    final encq = Uri.encodeComponent(query);
    if (!canSuggestTags) {
      throw Exception('no suggestion config for server $name');
    }

    if (query.isEmpty) {
      if (url.contains('name_pattern=') || url.contains('?q=')) {
        return url.replaceAll(RegExp(r'[*%]*{tag-part}[*%]*'), '');
      }
      return url.replaceAll(RegExp(r'[*%]*{tag-part}[*%]*'), '*');
    }
    return url.replaceAll('{tag-part}', encq);
  }

  /// How each booru engine is asked for a random order: either an extra
  /// search tag or extra URL parameters.
  ({String tag, String params}) _randomOrder(int seed) {
    if (searchUrl.contains('api/v1/images/search')) {
      // Monbooru: a seed keeps paging stable (no repeats across pages)
      return (tag: '', params: '&sort=random&seed=$seed');
    }
    if (searchUrl.contains('api/v1/json/search')) {
      // Philomena / booru-on-rails
      return (tag: '', params: '&sf=random');
    }
    final parser = searchParserId.toLowerCase();
    if (parser.startsWith('gelbooru') ||
        parser.startsWith('safebooru') ||
        parser.startsWith('szurubooru') ||
        searchUrl.toUri().queryParameters.containsKey('offset')) {
      return (tag: ' sort:random', params: '');
    }
    // Danbooru, Moebooru, e621, Shimmie
    return (tag: ' order:random', params: '');
  }

  static final _typedOrder = RegExp(
    r'(^|\s)-?(order|sort|ordpool):',
    caseSensitive: false,
  );

  /// Search for the post with [id], or null where the booru has no such
  /// search.
  String? postQuery(int id) => _hasRelations ? 'id:$id' : null;

  /// Search for the child posts of [id] (on Danbooru and Moebooru also the
  /// post itself), or null.
  String? childrenQuery(int id) => _hasRelations ? 'parent:$id' : null;

  /// Search for the posts of pool [id], in the pool's order where the
  /// booru has one, or null.
  String? poolQuery(int id) => switch (_engine) {
    'danbooru' => 'ordpool:$id',
    'e621' || 'moebooru' || 'danbooru1' => 'pool:$id',
    _ => null,
  };

  bool get _hasRelations => switch (_engine) {
    'danbooru' || 'e621' || 'moebooru' || 'danbooru1' || 'gelbooru' => true,
    _ => false,
  };

  /// API address listing the pools a post is in: by the post id on
  /// Danbooru, by the pool ids the post lists on e621. Null where the
  /// booru has no such API or the post is in no pool.
  String? poolsUrlOf(int postId, List<int> poolIds) {
    final api = apiAddress.replaceFirst(RegExp(r'/+$'), '');
    return switch (_engine) {
      'danbooru' =>
        '$api/pools.json?search[post_ids_include_all]=$postId&limit=20',
      'e621' when poolIds.isNotEmpty =>
        '$api/pools.json?search[id]=${poolIds.join(',')}&limit=20',
      _ => null,
    };
  }

  /// Booru engine, as far as sorting is concerned.
  String get _engine {
    final parser = searchParserId.toLowerCase();
    if (searchUrl.contains('api/v2/search')) return 'nhentai';
    if (searchUrl.contains('api/v1/images/search')) return 'monbooru';
    if (searchUrl.contains('api/v1/json/search')) return 'philomena';
    if (parser.startsWith('szurubooru') ||
        searchUrl.toUri().queryParameters.containsKey('offset')) {
      return 'szurubooru';
    }
    if (parser.startsWith('gelbooru') || parser.startsWith('safebooru')) {
      return 'gelbooru';
    }
    if (parser.startsWith('danbooru-v1.13')) return 'danbooru1';
    if (parser.startsWith('danbooru')) return 'danbooru';
    if (parser.startsWith('e621')) return 'e621';
    if (parser.startsWith('moebooru')) return 'moebooru';
    return '';
  }

  /// Sort orders the sort button offers for this server ('' = the
  /// engine's default, newest first). Empty: no sort button.
  List<String> get sortOptions => switch (_engine) {
    'nhentai' => NhentaiJsonParser.sortOptions,
    'danbooru' => const ['', 'rank', 'score', 'favcount', 'oldest'],
    'e621' => const ['', 'score', 'favcount', 'oldest'],
    'danbooru1' || 'moebooru' => const ['', 'score', 'oldest'],
    'gelbooru' => const ['', 'score', 'oldest'],
    'szurubooru' => const ['', 'score', 'favcount'],
    'philomena' => const ['', 'score', 'favcount', 'oldest'],
    'monbooru' => const ['', 'oldest', 'size'],
    _ => const [],
  };

  /// How the engine is asked for [sort]: an extra search tag or extra URL
  /// parameters (see [sortOptions] for the ids).
  ({String tag, String params}) _sortOrder(String sort) {
    const none = (tag: '', params: '');
    switch (_engine) {
      case 'danbooru':
      case 'e621':
      case 'danbooru1':
      case 'moebooru':
        return switch (sort) {
          'rank' => (tag: ' order:rank', params: ''),
          'score' => (tag: ' order:score', params: ''),
          'favcount' => (tag: ' order:favcount', params: ''),
          'oldest' => (tag: ' order:id', params: ''),
          _ => none,
        };
      case 'gelbooru':
        return switch (sort) {
          'score' => (tag: ' sort:score:desc', params: ''),
          'oldest' => (tag: ' sort:id:asc', params: ''),
          _ => none,
        };
      case 'szurubooru':
        return switch (sort) {
          'score' => (tag: ' sort:score', params: ''),
          'favcount' => (tag: ' sort:fav-count', params: ''),
          _ => none,
        };
      case 'philomena':
        return switch (sort) {
          'score' => (tag: '', params: '&sf=score&sd=desc'),
          'favcount' => (tag: '', params: '&sf=faves&sd=desc'),
          'oldest' => (tag: '', params: '&sf=created_at&sd=asc'),
          _ => none,
        };
      case 'monbooru':
        return switch (sort) {
          'oldest' => (tag: '', params: '&order=asc'),
          'size' => (tag: '', params: '&sort=filesize'),
          _ => none,
        };
      default:
        return none;
    }
  }

  String postUrlOf(int id) {
    if (postUrl.isEmpty) {
      return homepage;
    }

    final query = postUrl.replaceAll('{post-id}', id.toString());
    return '$homepage/$query';
  }

  // Key used in hive box
  String get key {
    final asKey = id.replaceAll(RegExp('[^A-Za-z0-9]'), '-');
    return '@${asKey.toLowerCase()}';
  }

  String get apiAddress => apiAddr.isEmpty ? homepage : apiAddr;

  String get name => alias.isNotEmpty ? alias : id;

  static const Server empty = Server();
  static const String defaultTag = '*';
  static const tagSuggestionLimit = 20;
}

String _rateString(BooruRating searchRating) {
  return switch (searchRating) {
    BooruRating.safe => 'rating:safe',
    BooruRating.questionable => 'rating:questionable',
    BooruRating.explicit => 'rating:explicit',
    BooruRating.sensitive => 'rating:sensitive',
    _ => '',
  };
}

String _monbooruRateString(BooruRating searchRating) {
  return switch (searchRating) {
    BooruRating.safe => 'rating:general',
    BooruRating.questionable => 'rating:questionable',
    BooruRating.explicit => 'rating:explicit',
    BooruRating.sensitive => 'rating:sensitive',
    _ => '',
  };
}

String _szuruRateString(BooruRating searchRating) {
  return switch (searchRating) {
    BooruRating.safe => 'safety:safe',
    BooruRating.questionable => 'safety:sketchy',
    BooruRating.sensitive || BooruRating.explicit => 'safety:unsafe',
    _ => '',
  };
}
