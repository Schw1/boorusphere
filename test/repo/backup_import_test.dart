import 'dart:convert';

import 'package:boorusphere/data/repository/favorite_post/entity/favorite_post.dart';
import 'package:boorusphere/data/repository/favorite_post/user_favorite_post_repo.dart';
import 'package:boorusphere/data/repository/search_history/entity/search_history.dart';
import 'package:boorusphere/data/repository/search_history/user_search_history.dart';
import 'package:boorusphere/data/repository/server/entity/server.dart';
import 'package:boorusphere/data/repository/server/user_server_repo.dart';
import 'package:boorusphere/data/repository/setting/entity/setting.dart';
import 'package:boorusphere/data/repository/setting/user_setting_repo.dart';
import 'package:boorusphere/data/repository/tags_blocker/booru_tags_blocker_repo.dart';
import 'package:boorusphere/data/repository/tags_blocker/entity/booru_tag.dart';
import 'package:boorusphere/presentation/provider/settings/entity/booru_rating.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

import '../utils/fake_data.dart';
import '../utils/hive.dart';

/// Restoring a backup replaces what is on the device. That must only
/// happen once the backup file turned out readable, and one broken entry
/// must not take the others with it.
void main() {
  final hiveContainer = HiveTestContainer();
  final posts = getSamplePosts().toList();

  setUpAll(() async {
    await UserFavoritePostRepo.prepare();
    await UserServerRepo.prepare();
    await BooruTagsBlockerRepo.prepare();
    await UserSearchHistoryRepo.prepare();
    await UserSettingsRepo.prepare();
  });

  tearDownAll(hiveContainer.dispose);

  group('favorites', () {
    late UserFavoritePostRepo repo;

    setUp(() async {
      repo = UserFavoritePostRepo(
        Hive.box<FavoritePost>(UserFavoritePostRepo.key),
      );
      await repo.clear();
      await repo.save(posts[0]);
    });

    test('an unreadable file leaves the favorites alone', () async {
      await expectLater(repo.import('{"not": "a list"'), throwsA(anything));
      await expectLater(repo.import('{"a": 1}'), throwsA(anything));
      expect(repo.get().map((it) => it.id), [posts[0].id]);
    });

    test('a file without usable entries leaves the favorites alone', () async {
      await repo.import('[]');
      await repo.import('[1, "x", {"post": 5}]');
      expect(repo.get().map((it) => it.id), [posts[0].id]);
    });

    test(
      'a broken entry is skipped, the others replace the favorites',
      () async {
        final backup = jsonEncode([
          FavoritePost(post: posts[1], timestamp: 1).toJson(),
          {'post': 'broken', 'timestamp': 2},
          FavoritePost(post: posts[2], timestamp: 3).toJson(),
        ]);
        await repo.import(backup);
        expect(repo.get().map((it) => it.id).toSet(), {
          posts[1].id,
          posts[2].id,
        });
      },
    );
  });

  group('servers', () {
    late UserServerRepo repo;
    const mine = Server(id: 'Mine', homepage: 'https://mine.example.org');

    setUp(() async {
      final box = Hive.box<Server>(UserServerRepo.key);
      await box.clear();
      repo = UserServerRepo(defaultServers: const {}, box: box);
      await repo.add(mine);
    });

    test('a file without usable entries leaves the servers alone', () async {
      await repo.import('[]');
      await repo.import('[{"id": ""}, 7]');
      expect(repo.servers.map((it) => it.id), ['Mine']);
    });

    test('a broken entry is skipped, the others replace the servers', () async {
      await repo.import(
        jsonEncode([
          const Server(
            id: 'Other',
            homepage: 'https://other.example.org',
          ).toJson(),
          {'id': 5, 'homepage': []},
        ]),
      );
      expect(repo.servers.map((it) => it.id), ['Other']);
    });
  });

  group('blocked tags', () {
    late BooruTagsBlockerRepo repo;

    setUp(() async {
      final box = Hive.box<BooruTag>(BooruTagsBlockerRepo.boxKey);
      await box.clear();
      repo = BooruTagsBlockerRepo(box);
      await repo.push(const BooruTag(name: 'mine'));
    });

    test('a file without usable entries leaves the list alone', () async {
      await repo.import('[]');
      await repo.import('[3, null]');
      expect(repo.get().values.map((it) => it.name), ['mine']);
    });

    test('both forms of a backup are read', () async {
      await repo.import(
        jsonEncode([
          'old_form',
          const BooruTag(name: 'new_form', serverId: 'Mine').toJson(),
          {'name': 5},
        ]),
      );
      expect(repo.get().values.map((it) => it.name).toSet(), {
        'old_form',
        'new_form',
      });
    });
  });

  group('search history', () {
    late UserSearchHistoryRepo repo;

    setUp(() async {
      final box = Hive.box<SearchHistory>(UserSearchHistoryRepo.key);
      await box.clear();
      repo = UserSearchHistoryRepo(box);
      await box.add(const SearchHistory(query: 'mine', server: 'Mine'));
    });

    test('a file without usable entries leaves the history alone', () async {
      await repo.import('[]');
      await repo.import('[1, {"query": []}]');
      expect(repo.all.values.map((it) => it.query), ['mine']);
    });

    test('a broken entry is skipped', () async {
      await repo.import(
        jsonEncode([
          const SearchHistory(query: 'a', server: 'Mine').toJson(),
          {'query': 5},
          const SearchHistory(query: 'b', server: 'Mine').toJson(),
        ]),
      );
      expect(repo.all.values.map((it) => it.query), ['a', 'b']);
    });
  });

  group('settings', () {
    late UserSettingsRepo repo;

    setUp(() async {
      final box = Hive.box(UserSettingsRepo.key);
      await box.clear();
      repo = UserSettingsRepo(box);
      await repo.put(Setting.serverPostLimit, 40);
    });

    test('an empty file leaves the settings alone', () async {
      await repo.import('{}');
      expect(repo.get(Setting.serverPostLimit, or: 0), 40);
    });

    test('values are there when the import returns', () async {
      await repo.import(
        jsonEncode({
          Setting.serverPostLimit.name: 80,
          Setting.searchRating.name: BooruRating.explicit.name,
        }),
      );
      // read from the box file's view, not only from memory
      expect(repo.get(Setting.serverPostLimit, or: 0), 80);
      expect(
        repo.get<BooruRating>(Setting.searchRating, or: BooruRating.safe),
        BooruRating.explicit,
      );
    });

    test('a rating of the wrong type is skipped, not fatal', () async {
      await repo.import(
        jsonEncode({
          Setting.serverPostLimit.name: 60,
          Setting.searchRating.name: 3,
        }),
      );
      expect(repo.get(Setting.serverPostLimit, or: 0), 60);
      expect(
        repo.get<BooruRating>(Setting.searchRating, or: BooruRating.safe),
        BooruRating.safe,
      );
    });
  });
}
