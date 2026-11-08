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
    @HiveField(11, defaultValue: '') @Default('') String urlSuffix ,
  }) = _Server;

  factory Server.fromJson(Map<String, dynamic> json) => _$ServerFromJson(json);

  const Server._();

  bool get canSuggestTags => tagSuggestionUrl.contains('{tag-part}');

  String searchUrlOf(PageOption option, {required int page}) {
    final query = option.query.trim();
    var tags = query.isEmpty ? Server.defaultTag : query;
    if (searchUrl.contains('api/v2/search')) {
      // nhentai: everything is explicit (no rating), `order:` tags become
      // its sort parameter, and the query must not be empty
      final split = NhentaiJsonParser.splitQuery(tags);
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
    _ => ''
  };
}

String _monbooruRateString(BooruRating searchRating) {
  return switch (searchRating) {
    BooruRating.safe => 'rating:general',
    BooruRating.questionable => 'rating:questionable',
    BooruRating.explicit => 'rating:explicit',
    BooruRating.sensitive => 'rating:sensitive',
    _ => ''
  };
}

String _szuruRateString(BooruRating searchRating) {
  return switch (searchRating) {
    BooruRating.safe => 'safety:safe',
    BooruRating.questionable => 'safety:sketchy',
    BooruRating.sensitive || BooruRating.explicit => 'safety:unsafe',
    _ => ''
  };
}
