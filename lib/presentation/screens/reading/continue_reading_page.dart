import 'package:auto_route/auto_route.dart';
import 'package:boorusphere/data/repository/booru/entity/post.dart';
import 'package:boorusphere/presentation/i18n/strings.g.dart';
import 'package:boorusphere/presentation/provider/server_data_state.dart';
import 'package:boorusphere/presentation/provider/stores.dart';
import 'package:boorusphere/presentation/screens/home/search_session.dart';
import 'package:boorusphere/presentation/widgets/notice_card.dart';
import 'package:boorusphere/presentation/widgets/timeline/post_selection.dart';
import 'package:boorusphere/presentation/widgets/timeline/timeline.dart';
import 'package:boorusphere/presentation/widgets/timeline/timeline_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scroll_to_index/scroll_to_index.dart';

/// Archives and galleries read recently, newest first, each with the page
/// it was left at (badge on the thumbnail). Opening one resumes there.
@RoutePage()
class ContinueReadingPage extends HookConsumerWidget {
  const ContinueReadingPage({super.key, this.session});
  final SearchSession? session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final servers = ref.watch(serverStateProvider);
    final recent = ref.watch(continueReadingProvider);
    // Posts of servers that were removed can't be opened anymore.
    final posts = (recent.value ?? const <Post>[])
        .where((it) => servers.any((s) => s.id == it.serverId))
        .toList();
    final scrollController = useMemoized(AutoScrollController.new);
    useEffect(() => scrollController.dispose, [scrollController]);

    return ProviderScope(
      overrides: [
        searchSessionProvider.overrideWith(
          (ref) => session ?? const SearchSession(),
        ),
        timelineControllerProvider.overrideWith(
          (ref) => TimelineController(scrollController: scrollController),
        ),
      ],
      child: Scaffold(
        appBar: AppBar(
          title: Text(context.t.continueReading.title),
          actions: [if (posts.isNotEmpty) _Menu(posts: posts)],
        ),
        body: posts.isEmpty
            ? recent.hasValue
                  ? Center(
                      child: NoticeCard(
                        icon: const Icon(Icons.auto_stories_outlined),
                        margin: const EdgeInsets.all(32),
                        children: Text(context.t.continueReading.placeholder),
                      ),
                    )
                  : const SizedBox.shrink()
            : PostSelectionScope(
                posts: () => posts,
                actions: [
                  PostSelectionAction(
                    icon: Icons.playlist_remove,
                    tooltip: context.t.continueReading.removeSelected,
                    onPressed: (context, selected) async {
                      await ref
                          .read(readingProgressStoreProvider)
                          .forgetAll(selected);
                    },
                  ),
                ],
                // long-press a thumbnail to select
                child: CustomScrollView(
                  controller: scrollController,
                  slivers: [
                    SliverSafeArea(
                      sliver: SliverPadding(
                        padding: const EdgeInsets.all(10),
                        sliver: Timeline(posts: posts),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

enum _Action { removeFinished, removeAll }

class _Menu extends ConsumerWidget {
  const _Menu({required this.posts});

  final List<Post> posts;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t.continueReading;
    final store = ref.read(readingProgressStoreProvider);
    return PopupMenuButton<_Action>(
      onSelected: (action) async {
        switch (action) {
          case _Action.removeFinished:
            await store.forgetAll(posts.where(store.isFinished));
          case _Action.removeAll:
            final ok = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: Text(t.removeAll),
                content: Text(t.removeAllHint),
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
            if (ok ?? false) await store.forgetAll();
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: _Action.removeFinished,
          enabled: posts.any(store.isFinished),
          child: Text(t.removeFinished),
        ),
        PopupMenuItem(value: _Action.removeAll, child: Text(t.removeAll)),
      ],
    );
  }
}
