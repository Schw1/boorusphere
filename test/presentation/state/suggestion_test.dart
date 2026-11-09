import 'package:boorusphere/data/repository/booru/entity/page_option.dart';
import 'package:boorusphere/data/repository/booru/entity/post.dart';
import 'package:boorusphere/data/repository/server/entity/server.dart';
import 'package:boorusphere/data/repository/tags_blocker/booru_tags_blocker_repo.dart';
import 'package:boorusphere/data/repository/tags_blocker/entity/booru_tag.dart';
import 'package:boorusphere/domain/provider.dart';
import 'package:boorusphere/domain/repository/imageboards_repo.dart';
import 'package:boorusphere/presentation/provider/booru/suggestion_state.dart';
import 'package:boorusphere/presentation/provider/server_data_state.dart';
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

class _Repo implements ImageboardRepo {
  @override
  Server get server => _server;

  @override
  Future<Set<Suggestion>> getSuggestion(String word) async => const {
    Suggestion('cat', 100),
    Suggestion('catgirl', 900),
    Suggestion('cat_ears', 500),
  };

  @override
  Future<Set<Post>> getPage(PageOption option, int index) async => const {};
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('tag suggestions', () {
    final hiveContainer = HiveTestContainer();
    late ProviderContainer ref;

    Future<List<String>> suggest(String query) async {
      await ref.read(suggestionStateProvider.notifier).get(query);
      return ref
          .read(suggestionStateProvider)
          .data
          .map((it) => it.name)
          .toList();
    }

    setUpAll(BooruTagsBlockerRepo.prepare);

    setUp(() async {
      await Hive.box<BooruTag>(BooruTagsBlockerRepo.boxKey).clear();
      ref = ProviderContainer(
        overrides: [
          serverStateProvider.overrideWith(_Servers.new),
          imageboardRepoProvider.overrideWith((ref, server) => _Repo()),
        ],
      );
      ref.setupTestFor(suggestionStateProvider);
    });

    tearDown(() => ref.dispose());
    tearDownAll(hiveContainer.dispose);

    test('are sorted by count', () async {
      expect(await suggest('cat'), ['catgirl', 'cat_ears', 'cat']);
    });

    test('leave out blocked tags', () async {
      final repo = ref.read(tagsBlockerRepoProvider);
      await repo.push(const BooruTag(name: 'catgirl'));
      await repo.push(const BooruTag(name: 'cat', serverId: 'TestBooru'));

      expect(await suggest('cat'), ['cat_ears']);
    });

    test('keep tags that are only blocked on another server', () async {
      await ref
          .read(tagsBlockerRepoProvider)
          .push(const BooruTag(name: 'catgirl', serverId: 'Elsewhere'));

      expect(await suggest('cat'), ['catgirl', 'cat_ears', 'cat']);
    });
  });
}
