import 'package:boorusphere/data/repository/booru/entity/booru_error.dart';
import 'package:boorusphere/data/repository/booru/entity/page_option.dart';
import 'package:boorusphere/data/repository/booru/entity/post.dart';
import 'package:boorusphere/data/repository/saved_search.dart';
import 'package:boorusphere/data/repository/search_history/user_search_history.dart';
import 'package:boorusphere/data/repository/server/entity/server.dart';
import 'package:boorusphere/data/repository/setting/user_setting_repo.dart';
import 'package:boorusphere/data/repository/tags_blocker/booru_tags_blocker_repo.dart';
import 'package:boorusphere/data/repository/tags_blocker/entity/booru_tag.dart';
import 'package:boorusphere/domain/provider.dart';
import 'package:boorusphere/domain/repository/imageboards_repo.dart';
import 'package:boorusphere/presentation/provider/booru/entity/fetch_result.dart';
import 'package:boorusphere/presentation/provider/booru/page_state.dart';
import 'package:boorusphere/presentation/provider/booru/suggestion_state.dart';
import 'package:boorusphere/presentation/provider/server_data_state.dart';
import 'package:boorusphere/presentation/provider/tags_blocker_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../utils/hive.dart';
import '../../utils/riverpod.dart';

const _server = Server(id: 'TestBooru', homepage: 'https://test.example.org');

class _Servers extends ServerState {
  @override
  Iterable<Server> build() => const [_server];
}

/// Serves [pages] in order and records what was asked for.
class _Repo implements ImageboardRepo {
  List<List<Post>> pages = [];
  final asked = <(PageOption, int)>[];
  Object? failure;

  @override
  Server get server => _server;

  @override
  Future<Set<Suggestion>> getSuggestion(String word) async => const {};

  @override
  Future<Set<Post>> getPage(PageOption option, int index) async {
    asked.add((option, index));
    if (failure case final error?) throw error;
    return index < pages.length ? pages[index].toSet() : {};
  }
}

Post _post(int id, [List<String> tags = const ['cat']]) =>
    Post(id: id, serverId: 'TestBooru', tags: tags);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('page loading', () {
    final hiveContainer = HiveTestContainer();
    late ProviderContainer ref;
    late _Repo repo;

    PageState notifier() => ref.read(pageStateProvider.notifier);
    FetchResult state() => ref.read(pageStateProvider);
    List<int> shown() => ref
        .read(pageStateProvider)
        .data
        .filteredPosts
        .map((it) => it.id)
        .toList();
    List<int> all() =>
        ref.read(pageStateProvider).data.posts.map((it) => it.id).toList();

    // as the app does it, so open pages hear about the change
    Future<void> block(String tag, {String serverId = ''}) => ref
        .read(tagsBlockerStateProvider.notifier)
        .push(serverId: serverId, tag: tag);

    Future<void> search(String query) =>
        notifier().update((it) => it.copyWith(query: query, clear: true));

    setUpAll(() async {
      await BooruTagsBlockerRepo.prepare();
      await UserSearchHistoryRepo.prepare();
      await UserSettingsRepo.prepare();
      await SavedSearchStore.open();
    });

    setUp(() async {
      await Hive.box<BooruTag>(BooruTagsBlockerRepo.boxKey).clear();
      repo = _Repo();
      ref = ProviderContainer(
        overrides: [
          serverStateProvider.overrideWith(_Servers.new),
          imageboardRepoProvider.overrideWith((ref, server) => repo),
        ],
      );
      ref.setupTestFor(pageStateProvider);
    });

    tearDown(() => ref.dispose());
    tearDownAll(hiveContainer.dispose);

    test('the first page is shown', () async {
      repo.pages = [
        [_post(3), _post(2), _post(1)],
      ];
      await search('cat');

      expect(state(), isA<DataFetchResult>());
      expect(shown(), [3, 2, 1]);
      expect(repo.asked.single.$2, 0);
      expect(repo.asked.single.$1.query, 'cat');
    });

    test('loading more appends the next page with the same seed', () async {
      repo.pages = [
        [_post(4), _post(3)],
        [_post(2), _post(1)],
      ];
      await search('cat');
      await notifier().loadMore();

      expect(shown(), [4, 3, 2, 1]);
      expect(repo.asked.map((it) => it.$2), [0, 1]);
      expect(repo.asked[0].$1.seed, isNot(0));
      expect(repo.asked[1].$1.seed, repo.asked[0].$1.seed);
    });

    test('a new search starts over with another seed', () async {
      repo.pages = [
        [_post(2), _post(1)],
      ];
      await search('cat');
      final firstSeed = repo.asked.last.$1.seed;
      repo.pages = [
        [_post(9)],
      ];
      await search('dog');

      expect(shown(), [9]);
      expect(repo.asked.last.$2, 0);
      // seeds are random; equal ones are possible but as good as never
      expect(repo.asked.last.$1.seed, isNot(firstSeed));
    });

    test('posts already loaded are not added twice', () async {
      repo.pages = [
        [_post(3), _post(2)],
        // the booru got a new post meanwhile, so page 2 repeats one
        [_post(2), _post(1)],
      ];
      await search('cat');
      await notifier().loadMore();

      expect(shown(), [3, 2, 1]);
      expect(all(), [3, 2, 1]);
    });

    test('the same post with changed data is still a duplicate', () async {
      repo.pages = [
        [_post(2)],
        [_post(2).copyWith(score: 50), _post(1)],
      ];
      await search('cat');
      await notifier().loadMore();

      expect(shown(), [2, 1]);
    });

    test('posts with blocked tags are hidden, not dropped', () async {
      await block('gore');
      repo.pages = [
        [
          _post(3),
          _post(2, ['cat', 'gore']),
          _post(1),
        ],
      ];
      await search('cat');

      expect(shown(), [3, 1]);
      expect(all(), [3, 2, 1]);
    });

    test('a tag blocked on another server does not hide posts', () async {
      await block('gore', serverId: 'Elsewhere');
      repo.pages = [
        [
          _post(2, ['cat', 'gore']),
          _post(1),
        ],
      ];
      await search('cat');

      expect(shown(), [2, 1]);
    });

    test('a page of only blocked posts is skipped', () async {
      await block('gore');
      repo.pages = [
        [
          _post(4, ['gore']),
          _post(3, ['gore']),
        ],
        [_post(2), _post(1)],
      ];
      await search('cat');

      expect(shown(), [2, 1]);
      expect(repo.asked.map((it) => it.$2), [0, 1]);
    });

    test(
      'blocking a tag later hides loaded posts, unblocking shows them',
      () async {
        repo.pages = [
          [
            _post(3),
            _post(2, ['cat', 'gore']),
            _post(1),
          ],
        ];
        await search('cat');
        expect(shown(), [3, 2, 1]);

        await block('gore');
        expect(shown(), [3, 1]);

        final key = ref.read(tagsBlockerStateProvider).keys.single;
        await ref.read(tagsBlockerStateProvider.notifier).delete(key);
        expect(shown(), [3, 2, 1]);
      },
    );

    test(
      'searching a blocked tag is refused without asking the server',
      () async {
        await block('gore');
        await search('cat gore');

        final result = state();
        expect(result, isA<ErrorFetchResult>());
        expect((result as ErrorFetchResult).error, BooruError.tagsBlocked);
        expect(repo.asked, isEmpty);
      },
    );

    test('an empty result is reported as empty', () async {
      repo.pages = [];
      await search('nothing');

      final result = state();
      expect(result, isA<ErrorFetchResult>());
      expect((result as ErrorFetchResult).error, BooruError.empty);
    });

    test('the end of the results keeps what is loaded', () async {
      repo.pages = [
        [_post(2), _post(1)],
      ];
      await search('cat');
      await notifier().loadMore();

      expect(state(), isA<ErrorFetchResult>());
      expect(shown(), [2, 1]);
    });

    test('a failing request is reported and keeps what is loaded', () async {
      repo.pages = [
        [_post(2), _post(1)],
      ];
      await search('cat');
      repo.failure = Exception('offline');
      await notifier().loadMore();

      expect(state(), isA<ErrorFetchResult>());
      expect(shown(), [2, 1]);
    });
  });
}
