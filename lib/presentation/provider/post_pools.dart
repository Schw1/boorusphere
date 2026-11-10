import 'package:boorusphere/data/provider.dart';
import 'package:boorusphere/data/repository/booru/entity/post.dart';
import 'package:boorusphere/data/repository/server/server_auth_store.dart';
import 'package:boorusphere/presentation/provider/server_data_state.dart';
import 'package:dio/dio.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// A pool (an ordered set of posts, e.g. a comic) a post is in.
class BooruPool {
  const BooruPool({required this.id, required this.name, this.postCount = 0});

  final int id;
  final String name;
  final int postCount;

  /// Pools of a Danbooru-style `pools.json` answer; broken entries are
  /// skipped. Names use `_` for spaces.
  static List<BooruPool> listOf(Object? data) {
    if (data is! List) return const [];
    return [
      for (final it in data)
        if (it is Map && it['id'] is int)
          BooruPool(
            id: it['id'] as int,
            name: '${it['name'] ?? ''}'.replaceAll('_', ' ').trim(),
            postCount: it['post_count'] is int ? it['post_count'] as int : 0,
          ),
    ];
  }
}

/// The pools [post] is in, for the details page. Empty when the booru has
/// no pools API or the post is in none.
final postPoolsProvider = FutureProvider.autoDispose
    .family<List<BooruPool>, Post>((ref, post) async {
      final server = ref.read(serverStateProvider).findById(post.serverId);
      if (server == null) return const [];
      final url = server.poolsUrlOf(post.id, post.poolIds);
      if (url == null) return const [];
      final res = await ref
          .read(dioProvider)
          .get(
            url,
            options: Options(
              headers: {
                'Accept': 'application/json',
                ...ServerAuthStore.headersFor(server, url),
              },
              validateStatus: (it) => it == 200,
            ),
          );
      return BooruPool.listOf(res.data);
    });
