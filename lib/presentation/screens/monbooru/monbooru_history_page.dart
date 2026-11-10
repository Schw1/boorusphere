import 'dart:ui';

import 'package:auto_route/auto_route.dart';
import 'package:boorusphere/presentation/i18n/strings.g.dart';
import 'package:boorusphere/presentation/provider/booru/post_headers_factory.dart';
import 'package:boorusphere/presentation/provider/monbooru_history.dart';
import 'package:boorusphere/presentation/provider/monbooru_queue.dart';
import 'package:boorusphere/presentation/provider/server_data_state.dart';
import 'package:boorusphere/presentation/provider/settings/content_setting_state.dart';
import 'package:boorusphere/presentation/screens/home/search_session.dart';
import 'package:boorusphere/presentation/screens/post/post_viewer.dart';
import 'package:boorusphere/presentation/utils/extensions/buildcontext.dart';
import 'package:boorusphere/presentation/utils/extensions/monbooru_error.dart';
import 'package:boorusphere/presentation/utils/extensions/post.dart';
import 'package:boorusphere/presentation/utils/root_messenger.dart';
import 'package:boorusphere/presentation/widgets/notice_card.dart';
import 'package:boorusphere/presentation/widgets/timeline/timeline_controller.dart';
import 'package:extended_image/extended_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:scroll_to_index/scroll_to_index.dart';

/// Posts sent to Monbooru on this device, newest first, with their result.
/// Failed ones can be sent again; sends without a result yet are asked
/// for again when the page opens (or pulled down).
@RoutePage()
class MonbooruHistoryPage extends HookConsumerWidget {
  const MonbooruHistoryPage({super.key, this.session});
  final SearchSession? session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    useValueListenable(MonbooruHistory.changes);
    final entries = useFuture(
      useMemoized(MonbooruHistory.all, [MonbooruHistory.changes.value]),
    );
    // Swiped away: hidden at once, before the store has caught up (a
    // dismissed item must leave the list in the same frame).
    final removed = useState(<String>{});
    final list = (entries.data ?? const <MonbooruHistoryEntry>[])
        .where((it) => !removed.value.contains(it.post.viewId))
        .toList();
    final scrollController = useMemoized(AutoScrollController.new);
    useEffect(() => scrollController.dispose, [scrollController]);
    useEffect(() {
      MonbooruHistory.lookUpPending();
      return null;
    }, []);
    final t = context.t.monbooru.history;

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
          title: Text(t.title),
          actions: [
            if (list.any((it) => it.isSuccess))
              IconButton(
                tooltip: t.removeSuccessful,
                icon: const Icon(Icons.done_all),
                onPressed: MonbooruHistory.removeSuccessful,
              ),
            if (list.isNotEmpty)
              IconButton(
                tooltip: t.clear,
                icon: const Icon(Icons.delete_sweep_outlined),
                onPressed: () => _confirmClear(context),
              ),
          ],
        ),
        body: RefreshIndicator(
          onRefresh: MonbooruHistory.lookUpPending,
          child: list.isEmpty
              ? ListView(
                  children: [
                    if (entries.hasData)
                      Center(
                        child: NoticeCard(
                          icon: const Icon(Icons.cloud_upload_outlined),
                          margin: const EdgeInsets.all(32),
                          children: Text(t.placeholder),
                        ),
                      ),
                  ],
                )
              : ListView.builder(
                  controller: scrollController,
                  itemCount: list.length,
                  itemBuilder: (context, index) => AutoScrollTag(
                    key: ValueKey(list[index].post.viewId),
                    controller: scrollController,
                    index: index,
                    child: Dismissible(
                      key: ValueKey('dismiss-${list[index].post.viewId}'),
                      // only this entry; nothing is removed from Monbooru
                      direction: DismissDirection.endToStart,
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        color: context.colorScheme.error,
                        child: Icon(
                          Icons.delete_outline,
                          color: context.colorScheme.onError,
                        ),
                      ),
                      onDismissed: (_) {
                        final post = list[index].post;
                        removed.value = {...removed.value, post.viewId};
                        MonbooruHistory.remove(post);
                      },
                      child: _Tile(
                        entry: list[index],
                        onTap: () => PostViewer.open(
                          context,
                          index: index,
                          posts: [for (final it in list) it.post],
                        ),
                      ),
                    ),
                  ),
                ),
        ),
      ),
    );
  }

  Future<void> _confirmClear(BuildContext context) async {
    final t = context.t.monbooru.history;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.clear),
        content: Text(t.clearHint),
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
    if (ok ?? false) await MonbooruHistory.clear();
  }
}

class _Tile extends HookConsumerWidget {
  const _Tile({required this.entry, required this.onTap});

  final MonbooruHistoryEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t.monbooru.history;
    final post = entry.post;
    final server = ref.watch(serverStateProvider).findById(post.serverId);
    final headers = ref.watch(postHeadersFactoryProvider(post));
    final blur = ref.watch(
      contentSettingStateProvider.select((it) => it.blurExplicit),
    );
    final states = useValueListenable(MonbooruQueue.instance.states);
    final busy = states[post.viewId]?.isBusy ?? false;
    final report = entry.report;

    final (icon, color) = switch (entry) {
      _ when busy || entry.isPending => (
        Icons.hourglass_top,
        context.colorScheme.onSurfaceVariant,
      ),
      _ when entry.isFailed => (Icons.error_outline, Colors.redAccent),
      _ when (report?.unconfirmed ?? false) => (
        Icons.help_outline,
        context.colorScheme.onSurfaceVariant,
      ),
      _ => (Icons.cloud_done, Colors.lightGreen),
    };
    final status = busy || report == null
        ? t.pending
        : report.describe(context);
    final time = DateFormat.yMd().add_Hm().format(entry.time);
    final title = post.title.isNotEmpty ? post.title : '#${post.id}';

    return ListTile(
      onTap: onTap,
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(
          width: 48,
          height: 48,
          child: post.previewFile.isEmpty
              ? const Icon(Icons.image_outlined)
              : ImageFiltered(
                  enabled: blur && post.rating.isExplicit,
                  imageFilter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                  child: ExtendedImage.network(
                    post.previewFile,
                    headers: headers,
                    cache: true,
                    fit: BoxFit.cover,
                  ),
                ),
        ),
      ),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${server?.name ?? post.serverId} · $time\n$status',
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      ),
      isThreeLine: true,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 20),
          PopupMenuButton<_Action>(
            onSelected: (action) => _onAction(context, action),
            itemBuilder: (context) => [
              PopupMenuItem(
                value: _Action.resend,
                enabled: !busy && !entry.isPending,
                child: Text(t.resend),
              ),
              PopupMenuItem(
                value: _Action.remove,
                child: Text(context.t.remove),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _onAction(BuildContext context, _Action action) async {
    switch (action) {
      case _Action.resend:
        final messenger = ScaffoldMessenger.of(context);
        final sent = context.t.monbooru.sent;
        final error = await MonbooruQueue.instance.send(
          entry.post,
          onReport: (report) {
            showRootSnackBar((c) => report.describe(c));
          },
        );
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Builder(
                builder: (c) => Text(error?.describe(c) ?? sent),
              ),
            ),
          );
      case _Action.remove:
        await MonbooruHistory.remove(entry.post);
    }
  }
}

enum _Action { resend, remove }
