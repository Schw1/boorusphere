import 'package:boorusphere/data/repository/booru/entity/post.dart';
import 'package:boorusphere/domain/provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'favorite_post_state.g.dart';

@riverpod
class FavoritePostState extends _$FavoritePostState {
  @override
  Iterable<Post> build() {
    final repo = ref.read(favoritePostRepoProvider);
    return repo.get();
  }

  Future<void> clear() async {
    final repo = ref.read(favoritePostRepoProvider);
    await repo.clear();
    if (!ref.mounted) return;
    state = repo.get();
  }

  Future<void> remove(Post post) async {
    final repo = ref.read(favoritePostRepoProvider);
    await repo.remove(post);
    if (!ref.mounted) return;
    state = repo.get();
  }

  Future<void> save(Post post) async {
    if (state.contains(post)) return;

    final repo = ref.read(favoritePostRepoProvider);
    await repo.save(post);
    if (!ref.mounted) return;
    state = repo.get();
  }
}
