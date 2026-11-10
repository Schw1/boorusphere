import 'dart:math';

import 'package:auto_route/auto_route.dart';
import 'package:boorusphere/data/repository/booru/entity/page_option.dart';
import 'package:boorusphere/data/repository/booru/entity/post.dart';
import 'package:boorusphere/data/repository/booru/parser/monbooru_json_parser.dart';
import 'package:boorusphere/data/repository/booru/parser/nhentai_json_parser.dart';
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
/// One search of the feed: a tag on a server, and the next page to load.
class _Query {
  _Query(this.tag, this.server, this.page);

  final String tag;
  final Server server;
  int page;
  bool done = false;
}

@RoutePage()
class ForYouPage extends HookConsumerWidget {
  const ForYouPage({super.key, required this.session});
  final SearchSession session;

  /// With fewer posts of the chosen server, other servers' posts count.
  static const _minSameServer = 5;

  /// Which servers the feed searches, for this app session: null = the
  /// current one, [allServers] = every booru, else a server id.
  static final choice = ValueNotifier<String?>(null);
  static const allServers = '*';

  /// Result pages a search starts at (one of the first few, at random).
  static const _startPages = 4;

  /// Boorus for "all servers": not nhentai (other tags) and not Monbooru
  /// (what's there is already saved).
  static bool _isBooru(Server server) =>
      !NhentaiJsonParser.isNhentai(server) &&
      !MonbooruJsonParser.isMonbooru(server);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final servers = ref.watch(serverStateProvider);
    final chosen = useValueListenable(choice);
    final all = chosen == allServers;
    final server = servers.getById(
      chosen == null || all ? session.serverId : chosen,
    );
    final scrollController = useMemoized(AutoScrollController.new);
    useEffect(() => scrollController.dispose, [scrollController]);

    final queries = useState<List<_Query>>(const []);
    final posts = useState<List<Post>>(const []);
    final loading = useState(true);
    final error = useState(false);
    final noInterests = useState(false);
    final lastPicked = useRef<Set<String>>({});
    final random = useMemoized(Random.new);

    Set<String> blockedTags(Server server) => ref
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

    bool isNhentaiPost(Post post) {
      final s = servers.findById(post.serverId);
      return s != null && NhentaiJsonParser.isNhentai(s);
    }

    Future<List<Post>> fetch(_Query q) async {
      final settings = ref.read(serverSettingStateProvider);
      final repo = ref.read(imageboardRepoProvider(q.server));
      Future<List<Post>> page(int n) async => (await repo.getPage(
        PageOption(
          query: q.tag,
          limit: settings.postLimit,
          searchRating: settings.searchRating,
          language: settings.searchLanguages[q.server.id] ?? '',
        ),
        n,
      )).toList();
      try {
        var result = await page(q.page);
        // fewer pages than the random start: from the first one
        if (result.isEmpty && q.page > 0) {
          q.page = 0;
          result = await page(0);
        }
        q.page++;
        if (result.isEmpty) q.done = true;
        final blocked = blockedTags(q.server);
        return result.where((it) => !it.allTags.any(blocked.contains)).toList();
      } catch (_) {
        q.done = true;
        return const [];
      }
    }

    Future<void> load({bool fresh = false}) async {
      if (loading.value && !fresh) return;
      loading.value = true;
      error.value = false;
      try {
        if (fresh) {
          final boorus = servers.where(_isBooru).toList();
          final everything = await source();
          final List<Post> basis;
          if (all) {
            basis = everything.where((it) => !isNhentaiPost(it)).toList();
          } else if (NhentaiJsonParser.isNhentai(server)) {
            basis = everything.where(isNhentaiPost).toList();
          } else {
            final same = everything
                .where((it) => it.serverId == server.id)
                .toList();
            basis = same.length >= _minSameServer
                ? same
                : everything.where((it) => !isNhentaiPost(it)).toList();
          }
          final interests = ForYou.interests(
            basis,
            blocked: blockedTags(server),
          );
          noInterests.value = interests.isEmpty;
          final tags = ForYou.pick(
            interests,
            count: all ? 6 : 4,
            avoid: lastPicked.value,
            random: random,
          );
          lastPicked.value = tags.toSet();
          posts.value = const [];
          queries.value = [
            for (final tag in tags)
              if (all ? boorus.isNotEmpty : server != Server.empty)
                _Query(
                  tag,
                  all ? boorus[random.nextInt(boorus.length)] : server,
                  random.nextInt(_startPages),
                ),
          ];
        }
        final open = queries.value.where((it) => !it.done).toList();
        if (open.isEmpty) {
          error.value = posts.value.isEmpty && !noInterests.value;
          return;
        }
        final results = await Future.wait(open.map(fetch));
        if (!context.mounted) return;
        // a different order each time, so the same tag doesn't always lead
        results.shuffle(random);
        final favorites = {
          for (final post in ref.read(favoritePostStateProvider)) post.viewId,
        };
        final next = ForYou.mix(
          results,
          seen: {...favorites, for (final it in posts.value) it.viewId},
        );
        posts.value = [...posts.value, ...next];
        error.value = posts.value.isEmpty;
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
    }, [server.id, chosen]);

    final t = context.t.forYou;
    final Widget body;
    if (posts.value.isEmpty) {
      body = loading.value
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: NoticeCard(
                icon: const Icon(Icons.auto_awesome_outlined),
                margin: const EdgeInsets.all(32),
                children: Text(
                  noInterests.value
                      ? t.noInterests
                      : error.value
                      ? t.nothingFound
                      : '',
                ),
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
        timelineControllerProvider.overrideWith(
          (ref) => TimelineController(
            scrollController: scrollController,
            onLoadMore: () => loadRef.value(),
          ),
        ),
      ],
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            all
                ? '${t.title} · ${t.allServers}'
                : '${t.title} · ${server.name}',
          ),
          actions: [
            PopupMenuButton<String>(
              tooltip: t.servers,
              icon: const Icon(Icons.dns_outlined),
              onSelected: (id) =>
                  choice.value = id == session.serverId ? null : id,
              itemBuilder: (context) => [
                CheckedPopupMenuItem(
                  value: allServers,
                  checked: all,
                  child: Text(t.allServers),
                ),
                const PopupMenuDivider(),
                for (final it in servers)
                  CheckedPopupMenuItem(
                    value: it.id,
                    checked: !all && it.id == server.id,
                    child: Text(it.name),
                  ),
              ],
            ),
            IconButton(
              tooltip: t.refresh,
              icon: const Icon(Icons.refresh),
              onPressed: loading.value ? null : () => load(fresh: true),
            ),
          ],
          bottom: queries.value.isEmpty
              ? null
              : PreferredSize(
                  preferredSize: const Size.fromHeight(48),
                  child: SizedBox(
                    height: 48,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      children: [
                        for (final q in queries.value)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ActionChip(
                              label: Text(
                                all ? '${q.tag} · ${q.server.name}' : q.tag,
                              ),
                              onPressed: () => context.router.push(
                                HomeRoute(
                                  session: SearchSession(
                                    serverId: q.server.id,
                                    query: q.tag,
                                  ),
                                ),
                              ),
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
