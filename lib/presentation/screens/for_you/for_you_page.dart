import 'package:auto_route/auto_route.dart';
import 'package:boorusphere/data/repository/booru/entity/page_option.dart';
import 'package:boorusphere/data/repository/booru/entity/post.dart';
import 'package:boorusphere/data/repository/for_you.dart';
import 'package:boorusphere/data/repository/server/entity/server.dart';
import 'package:boorusphere/domain/provider.dart';
import 'package:boorusphere/presentation/i18n/strings.g.dart';
import 'package:boorusphere/presentation/provider/favorite_post_state.dart';
import 'package:boorusphere/presentation/provider/monbooru_history.dart';
import 'package:boorusphere/presentation/provider/server_data_state.dart';
import 'package:boorusphere/presentation/provider/settings/server_setting_state.dart';
import 'package:boorusphere/presentation/provider/tags_blocker_state.dart';
import 'package:boorusphere/presentation/routes/app_router.gr.dart';
import 'package:boorusphere/presentation/screens/home/search_session.dart';
import 'package:boorusphere/presentation/utils/extensions/post.dart';
import 'package:boorusphere/presentation/widgets/notice_card.dart';
import 'package:boorusphere/presentation/widgets/timeline/post_selection.dart';
import 'package:boorusphere/presentation/widgets/timeline/timeline.dart';
import 'package:boorusphere/presentation/widgets/timeline/timeline_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scroll_to_index/scroll_to_index.dart';

/// Posts of the current server for the tags the user is into, taken from
/// their favorites and what they sent to Monbooru. Each refresh picks a
/// few of those tags anew.
@RoutePage()
class ForYouPage extends HookConsumerWidget {
  const ForYouPage({super.key, required this.session});
  final SearchSession session;

  /// With fewer posts of the current server, all servers' posts count.
  static const _minSameServer = 5;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final server = ref.watch(serverStateProvider).getById(session.serverId);
    final scrollController = useMemoized(AutoScrollController.new);
    useEffect(() => scrollController.dispose, [scrollController]);

    final tags = useState<List<String>>(const []);
    final posts = useState<List<Post>>(const []);
    final loading = useState(true);
    final error = useState(false);
    final noInterests = useState(false);
    final page = useRef(0);
    final ended = useRef(false);

    Set<String> blockedTags() => ref
        .read(tagsBlockerStateProvider)
        .values
        .where((it) => it.serverId.isEmpty || it.serverId == server.id)
        .map((it) => it.name)
        .toSet();

    Future<List<Post>> source() async {
      final history = await MonbooruHistory.all();
      return [
        ...ref.read(favoritePostStateProvider),
        for (final entry in history) entry.post,
      ];
    }

    Future<void> load({bool fresh = false}) async {
      if ((loading.value && !fresh) || (!fresh && ended.value)) return;
      loading.value = true;
      error.value = false;
      try {
        if (fresh) {
          final all = await source();
          final same = all.where((it) => it.serverId == server.id).toList();
          final interests = ForYou.interests(
            same.length >= _minSameServer ? same : all,
            blocked: blockedTags(),
          );
          noInterests.value = interests.isEmpty;
          tags.value = ForYou.pick(interests);
          page.value = 0;
          ended.value = false;
          posts.value = const [];
        }
        if (tags.value.isEmpty || server == Server.empty) return;

        final settings = ref.read(serverSettingStateProvider);
        final repo = ref.read(imageboardRepoProvider(server));
        final results = await Future.wait(tags.value.map((tag) async {
          try {
            return (await repo.getPage(
              PageOption(
                query: tag,
                limit: settings.postLimit,
                searchRating: settings.searchRating,
                language: settings.searchLanguages[server.id] ?? '',
              ),
              page.value,
            ))
                .toList();
          } catch (_) {
            return <Post>[];
          }
        }));
        if (!context.mounted) return;
        page.value++;
        if (results.every((it) => it.isEmpty)) {
          ended.value = true;
          error.value = posts.value.isEmpty;
          return;
        }
        final blocked = blockedTags();
        final favorites = {
          for (final post in ref.read(favoritePostStateProvider)) post.viewId,
        };
        final next = ForYou.mix(
          [
            for (final result in results)
              result
                  .where((it) => !it.allTags.any(blocked.contains))
                  .toList(),
          ],
          seen: {...favorites, for (final it in posts.value) it.viewId},
        );
        posts.value = [...posts.value, ...next];
      } finally {
        if (context.mounted) loading.value = false;
      }
    }

    // The timeline controller calls the latest load.
    final loadRef = useRef(load);
    loadRef.value = load;

    useEffect(() {
      load(fresh: true);
      return null;
    }, [server.id]);

    final t = context.t.forYou;
    final Widget body;
    if (posts.value.isEmpty) {
      body = loading.value
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: NoticeCard(
                icon: const Icon(Icons.auto_awesome_outlined),
                margin: const EdgeInsets.all(32),
                children: Text(noInterests.value
                    ? t.noInterests
                    : error.value
                        ? t.nothingFound
                        : ''),
              ),
            );
    } else {
      body = PostSelectionScope(
        posts: () => posts.value,
        child: RefreshIndicator(
          onRefresh: () => load(fresh: true),
          child: CustomScrollView(
            controller: scrollController,
            slivers: [
              SliverSafeArea(
                sliver: SliverPadding(
                  padding: const EdgeInsets.all(10),
                  sliver: Timeline(posts: posts.value),
                ),
              ),
              if (loading.value)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ),
            ],
          ),
        ),
      );
    }

    return ProviderScope(
      overrides: [
        searchSessionProvider.overrideWith((ref) => session),
        timelineControllerProvider.overrideWith((ref) => TimelineController(
              scrollController: scrollController,
              onLoadMore: () => loadRef.value(),
            )),
      ],
      child: Scaffold(
        appBar: AppBar(
          title: Text(t.title),
          actions: [
            IconButton(
              tooltip: t.refresh,
              icon: const Icon(Icons.refresh),
              onPressed: loading.value ? null : () => load(fresh: true),
            ),
          ],
          bottom: tags.value.isEmpty
              ? null
              : PreferredSize(
                  preferredSize: const Size.fromHeight(48),
                  child: SizedBox(
                    height: 48,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      children: [
                        for (final tag in tags.value)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ActionChip(
                              label: Text(tag),
                              onPressed: () => context.router.push(HomeRoute(
                                session: SearchSession(
                                    serverId: server.id, query: tag),
                              )),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
        ),
        body: body,
      ),
    );
  }
}
