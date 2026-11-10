import 'package:boorusphere/data/repository/booru/entity/post.dart';
import 'package:boorusphere/presentation/i18n/strings.g.dart';
import 'package:boorusphere/presentation/provider/post_pools.dart';
import 'package:boorusphere/presentation/provider/server_data_state.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Parent post, child posts and pools of [post] in the details, each a
/// search on the post's server. Nothing is shown when the post has none or
/// its booru can't search for them.
class PostRelations extends ConsumerWidget {
  const PostRelations({super.key, required this.post, required this.onSearch});

  final Post post;

  /// Opens a search for the query on the post's server.
  final void Function(String query) onSearch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final server = ref.watch(serverStateProvider).findById(post.serverId);
    if (server == null) return const SizedBox.shrink();
    final t = context.t.relations;

    final parentQuery = post.parentId > 0
        ? server.postQuery(post.parentId)
        : null;
    final siblingsQuery = post.parentId > 0
        ? server.childrenQuery(post.parentId)
        : null;
    final childrenQuery = post.hasChildren
        ? server.childrenQuery(post.id)
        : null;
    final hasPoolsApi = server.poolsUrlOf(post.id, post.poolIds) != null;
    final pools = hasPoolsApi ? ref.watch(postPoolsProvider(post)) : null;
    final poolList = pools?.value ?? const <BooruPool>[];

    final tiles = <Widget>[
      if (parentQuery != null)
        _Tile(
          icon: Icons.north_west,
          title: t.parent(id: post.parentId),
          onTap: () => onSearch(parentQuery),
        ),
      if (siblingsQuery != null)
        _Tile(
          icon: Icons.layers_outlined,
          title: t.siblings,
          onTap: () => onSearch(siblingsQuery),
        ),
      if (childrenQuery != null)
        _Tile(
          icon: Icons.subdirectory_arrow_right,
          title: t.children,
          onTap: () => onSearch(childrenQuery),
        ),
      for (final pool in poolList)
        if (server.poolQuery(pool.id) case final query?)
          _Tile(
            icon: Icons.collections_bookmark_outlined,
            title: pool.name.isEmpty ? '${t.pools} #${pool.id}' : pool.name,
            subtitle: pool.postCount > 0
                ? t.poolPosts(n: pool.postCount)
                : null,
            onTap: () => onSearch(query),
          ),
      if (pools?.hasError ?? false)
        ListTile(
          dense: true,
          leading: const Icon(Icons.collections_bookmark_outlined),
          title: Text(t.poolsFailed),
        ),
    ];
    final loading = pools?.isLoading ?? false;
    if (tiles.isEmpty && !loading) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          title: Text(t.title),
          trailing: loading
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : null,
        ),
        ...tiles,
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final subtitle = this.subtitle;
    return ListTile(
      dense: true,
      leading: Icon(icon),
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle),
      trailing: const Icon(Icons.search),
      onTap: onTap,
    );
  }
}
