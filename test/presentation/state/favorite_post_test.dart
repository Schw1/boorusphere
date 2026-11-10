import 'package:boorusphere/data/repository/favorite_post/user_favorite_post_repo.dart';
import 'package:boorusphere/presentation/provider/favorite_post_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../utils/fake_data.dart';
import '../../utils/hive.dart';
import '../../utils/riverpod.dart';

void main() async {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('favorite post', () {
    final posts = getSamplePosts();
    final ref = ProviderContainer();
    final hiveContainer = HiveTestContainer();

    notifier() => ref.read(favoritePostStateProvider.notifier);
    state() => ref.read(favoritePostStateProvider);

    setUpAll(() async {
      await UserFavoritePostRepo.prepare();
      ref.setupTestFor(favoritePostStateProvider);
    });

    tearDownAll(() async {
      await hiveContainer.dispose();
      ref.dispose();
    });

    test('push all', () async {
      for (var element in posts) {
        await notifier().save(element);
      }
      expect(state().length, 3);
    });

    test('a favorite is recognized after its score and tags changed',
        () async {
      // what the server returns for the same post some days later
      final later = posts.first.copyWith(
        score: posts.first.score + 25,
        tags: [...posts.first.tags, 'new_tag'],
      );
      expect(state().contains(later), false);
      expect(state().containsPost(later), true);
      expect(state().containsPost(posts.first), true);

      // saving it again doesn't add a second entry
      await notifier().save(later);
      expect(state().length, 3);

      // the same id on another server is another post
      expect(
        state().containsPost(posts.first.copyWith(serverId: 'Elsewhere')),
        false,
      );
    });

    test('remove last', () async {
      await notifier().remove(posts.last);
      expect(state().length, 2);
    });

    test('cleanup', () async {
      await notifier().clear();
      expect(state().length, 0);
    });
  });
}
