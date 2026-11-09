import 'package:auto_route/auto_route.dart';
import 'package:boorusphere/data/repository/saved_search.dart';
import 'package:boorusphere/data/repository/server/entity/server.dart';
import 'package:boorusphere/presentation/i18n/strings.g.dart';
import 'package:boorusphere/presentation/provider/saved_searches.dart';
import 'package:boorusphere/presentation/provider/server_data_state.dart';
import 'package:boorusphere/presentation/routes/app_router.gr.dart';
import 'package:boorusphere/presentation/screens/home/search_session.dart';
import 'package:boorusphere/presentation/utils/extensions/buildcontext.dart';
import 'package:boorusphere/presentation/widgets/favicon.dart';
import 'package:boorusphere/presentation/widgets/notice_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Saved searches with the number of posts that are new since each was
/// last opened. [session] is the search on the home page, which can be
/// saved from here.
@RoutePage()
class SavedSearchesPage extends HookConsumerWidget {
  const SavedSearchesPage({super.key, this.session});
  final SearchSession? session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final searches = ref.watch(savedSearchesProvider);
    final notifier = ref.read(savedSearchesProvider.notifier);
    final servers = ref.watch(serverStateProvider);
    final t = context.t.savedSearches;
    useEffect(() {
      notifier.checkAll();
      return null;
    }, []);

    final current = session;
    // getById: the home page's session may still have no server id (then
    // it shows the first server).
    final currentServer =
        current == null ? Server.empty : servers.getById(current.serverId);
    final canSaveCurrent = current != null &&
        currentServer != Server.empty &&
        !notifier.contains(currentServer.id, current.query);

    return Scaffold(
      appBar: AppBar(title: Text(t.title)),
      floatingActionButton: canSaveCurrent
          ? FloatingActionButton.extended(
              onPressed: () async {
                await notifier.add(currentServer.id, current.query);
                if (!context.mounted) return;
                context.scaffoldMessenger.showSnackBar(SnackBar(
                  content: Text(t.saved(query: _label(context, current.query))),
                ));
              },
              icon: const Icon(Icons.bookmark_add_outlined),
              label: Text(t.saveCurrent),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: () => notifier.checkAll(force: true),
        child: searches.isEmpty
            ? ListView(
                children: [
                  Center(
                    child: NoticeCard(
                      icon: const Icon(Icons.bookmarks_outlined),
                      margin: const EdgeInsets.all(32),
                      children: Text(t.placeholder),
                    ),
                  ),
                ],
              )
            : ListView(
                padding: const EdgeInsets.only(bottom: 96),
                children: [
                  for (final search in searches)
                    _Tile(
                      search: search,
                      serverName: servers.findById(search.serverId)?.name,
                      homepage:
                          servers.findById(search.serverId)?.homepage ?? '',
                    ),
                ],
              ),
      ),
    );
  }

  static String _label(BuildContext context, String query) =>
      query.isEmpty ? context.t.savedSearches.everything : query;
}

class _Tile extends ConsumerWidget {
  const _Tile({
    required this.search,
    required this.serverName,
    required this.homepage,
  });

  final SavedSearch search;

  /// null when the server was removed
  final String? serverName;
  final String homepage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t.savedSearches;
    final count = search.newCount;
    final subtitle = serverName == null
        ? t.serverMissing
        : search.canCount
            ? serverName!
            : '${serverName!} · ${t.noCount}';

    return ListTile(
      leading: Favicon(url: homepage, shape: BoxShape.circle, iconSize: 21),
      title: Text(
        SavedSearchesPage._label(context, search.query),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(subtitle),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (count > 0)
            Badge(
              label: Text(t.newCount(n: search.more ? '$count+' : '$count')),
              backgroundColor: context.colorScheme.primary,
              textColor: context.colorScheme.onPrimary,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            ),
          IconButton(
            tooltip: context.t.remove,
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _remove(context, ref),
          ),
        ],
      ),
      enabled: serverName != null,
      onTap: () {
        context.router.push(HomeRoute(
          session: SearchSession(
              serverId: search.serverId, query: search.query),
        ));
      },
    );
  }

  Future<void> _remove(BuildContext context, WidgetRef ref) async {
    final t = context.t.savedSearches;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.removeTitle),
        content: Text(SavedSearchesPage._label(context, search.query)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.t.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(context.t.remove),
          ),
        ],
      ),
    );
    if (ok ?? false) {
      await ref.read(savedSearchesProvider.notifier).remove(search);
    }
  }
}
