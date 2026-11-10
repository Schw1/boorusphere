import 'dart:math';

import 'package:boorusphere/data/repository/booru/entity/page_option.dart';
import 'package:boorusphere/data/repository/booru/entity/post.dart';
import 'package:boorusphere/data/repository/booru/nhentai_tags.dart';
import 'package:boorusphere/data/repository/booru/parser/booru_parser.dart';
import 'package:boorusphere/data/repository/booru/parser/nhentai_json_parser.dart';
import 'package:boorusphere/data/repository/server/entity/server.dart';
import 'package:boorusphere/data/repository/server/server_auth_store.dart';
import 'package:boorusphere/domain/repository/imageboards_repo.dart';
import 'package:boorusphere/presentation/provider/booru/suggestion_state.dart';
import 'package:boorusphere/presentation/provider/server_data_state.dart';
import 'package:boorusphere/utils/logger.dart';
import 'package:dio/dio.dart';
import 'package:logging/logging.dart';

class BooruRepo implements ImageboardRepo {
  BooruRepo({
    required this.parsers,
    required this.client,
    required this.server,
    required this.serverState,
  });

  final Iterable<BooruParser> parsers;
  final Dio client;
  final ServerState serverState;

  final _opt = Options(validateStatus: (it) => it == 200);
  final _log = Logger('BooruRepo');

  /// nhentai has no random order: its result pages are visited in a random
  /// order (fixed by the search's seed), and each page is shuffled.
  final Map<String, List<int>> _randomPageOrder = {};

  @override
  final Server server;

  Future<Response> _request(String url, BooruParser parser) {
    return client.get(
      url,
      options: _opt.copyWith(
        headers: {
          ...parser.headers,
          ...ServerAuthStore.headersFor(server, url),
        },
      ),
    );
  }

  @override
  Future<Set<Suggestion>> getSuggestion(String word) async {
    if (NhentaiJsonParser.isNhentai(server)) {
      final tags = NhentaiTags.instance;
      await tags.ensureLoaded(client);
      return {
        for (final (token, count) in tags.suggest(word))
          Suggestion(token, count),
      };
    }

    var parser = parsers.firstWhere(
      (x) => x.id == server.suggestionParserId,
      orElse: NoParser.new,
    );

    final suggestionUrl = server.suggestionUrlsOf(word);
    final res = await _request(suggestionUrl, parser);

    if (parser.canParseSuggestion(res)) {
      _log.i('getSuggestion(${server.name}): using ${parser.id}_parser');
      return parser.parseSuggestion(server, res).toSet();
    }

    parser = parsers.firstWhere(
      (it) => it.canParseSuggestion(res),
      orElse: NoParser.new,
    );

    if (parser.id.isNotEmpty) {
      _log.i(
        'getSuggestion(${server.name}): parser resolved, now using ${parser.id}_parser',
      );
      await serverState.edit(
        server,
        server.copyWith(suggestionParserId: parser.id),
      );
    }

    return parser.parseSuggestion(server, res).toSet();
  }

  @override
  Future<Set<Post>> getPage(PageOption option, int index) async {
    var parser = parsers.firstWhere(
      (x) => x.id == server.searchParserId,
      orElse: NoParser.new,
    );

    if (parser is NhentaiJsonParser) {
      // Tag names for the tag ids of the results (blocking, details); wait
      // a moment for the stored list, the download continues in the
      // background.
      await NhentaiTags.instance
          .ensureLoaded(client)
          .timeout(const Duration(seconds: 3), onTimeout: () {});
    }

    if (option.random && parser is NhentaiJsonParser) {
      return _nhentaiRandomPage(parser, option, index);
    }

    final searchUrl = server.searchUrlOf(
      option,
      page: index + parser.pageOffset,
    );
    final res = await _request(searchUrl, parser);

    if (parser.canParsePage(res)) {
      _log.i('getPage(${server.name}): using ${parser.id}_parser');
      return parser.parsePage(server, res).toSet();
    }

    parser = parsers.firstWhere(
      (it) => it.canParsePage(res),
      orElse: NoParser.new,
    );

    if (parser.id.isNotEmpty) {
      _log.i(
        'getPage(${server.name}): parser resolved, now using ${parser.id}_parser',
      );
      await serverState.edit(
        server,
        server.copyWith(searchParserId: parser.id),
      );
    }

    return parser.parsePage(server, res).toSet();
  }

  Future<Set<Post>> _nhentaiRandomPage(
    NhentaiJsonParser parser,
    PageOption option,
    int index,
  ) async {
    final key = '${option.query}|${option.sort}|${option.seed}';
    var order = _randomPageOrder[key];
    if (order == null) {
      final first = await _request(server.searchUrlOf(option, page: 1), parser);
      final data = first.data;
      final pages = data is Map && data['num_pages'] is int
          ? data['num_pages'] as int
          : 0;
      order = randomPageOrder(pages, option.seed);
      _randomPageOrder[key] = order;
    }
    if (index >= order.length) return {};

    final res = await _request(
      server.searchUrlOf(option, page: order[index]),
      parser,
    );
    if (!parser.canParsePage(res)) return {};
    final posts = parser.parsePage(server, res).toList()
      ..shuffle(Random(option.seed ^ index));
    return posts.toSet();
  }

  /// Pages 1..[pages] in a random order that only depends on [seed].
  static List<int> randomPageOrder(int pages, int seed) =>
      [for (var i = 1; i <= pages; i++) i]..shuffle(Random(seed));
}
