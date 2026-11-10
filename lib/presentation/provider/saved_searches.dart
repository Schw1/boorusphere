import 'package:boorusphere/data/repository/booru/entity/page_option.dart';
import 'package:boorusphere/data/repository/saved_search.dart';
import 'package:boorusphere/domain/provider.dart';
import 'package:boorusphere/presentation/provider/server_data_state.dart';
import 'package:boorusphere/presentation/provider/settings/server_setting_state.dart';
import 'package:boorusphere/presentation/provider/tags_blocker_state.dart';
import 'package:boorusphere/presentation/utils/extensions/post.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final savedSearchesProvider =
    NotifierProvider<SavedSearches, List<SavedSearch>>(SavedSearches.new);

/// Saved searches and their "new" counts. Counts are refreshed when the app
/// starts and when the list is opened (not in the background; iOS doesn't
/// let a sideloaded app do that reliably).
class SavedSearches extends Notifier<List<SavedSearch>> {
  /// A search isn't checked again within this time, unless asked to.
  static const checkInterval = Duration(minutes: 10);

  bool _checking = false;

  @override
  List<SavedSearch> build() => SavedSearchStore.all();

  SavedSearch? find(String serverId, String query) {
    final key = SavedSearch.keyOf(serverId, query);
    for (final it in state) {
      if (it.key == key) return it;
    }
    return null;
  }

  bool contains(String serverId, String query) => find(serverId, query) != null;

  /// Total new posts, for a badge.
  int get totalNew => state.fold(0, (sum, it) => sum + it.newCount);

  Future<void> _put(SavedSearch search) async {
    await SavedSearchStore.put(search);
    if (!ref.mounted) return;
    state = [
      for (final it in state)
        if (it.key == search.key) search else it,
      if (!state.any((it) => it.key == search.key)) search,
    ];
  }

  Future<void> add(String serverId, String query) async {
    if (contains(serverId, query)) return;
    final search = SavedSearch(
      serverId: serverId,
      query: SavedSearch.normalize(query),
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    await _put(search);
    // Remember where it stands now, so later checks have something to
    // compare with.
    await check(search);
  }

  Future<void> remove(SavedSearch search) async {
    await SavedSearchStore.remove(search);
    if (!ref.mounted) return;
    state = state.where((it) => it.key != search.key).toList();
  }

  /// The search was opened: its new posts count as seen. [ids] are posts
  /// just loaded newest first (pass none when loaded in another order).
  Future<void> markSeen(
    String serverId,
    String query, [
    Iterable<int> ids = const [],
  ]) async {
    final search = find(serverId, query);
    if (search == null) return;
    if (search.newCount == 0 && ids.every((it) => it <= search.seenId)) {
      return;
    }
    await _put(search.seen(ids));
  }

  Future<void> checkAll({bool force = false}) async {
    if (_checking) return;
    _checking = true;
    try {
      final now = DateTime.now();
      for (final search in List.of(state)) {
        final due =
            now.millisecondsSinceEpoch - search.checkedAt >=
            checkInterval.inMilliseconds;
        if (!force && !due) continue;
        await check(search);
        if (!ref.mounted) return;
      }
    } finally {
      _checking = false;
    }
  }

  /// Loads the first page in newest-first order and counts what's new.
  /// Failures (server offline etc.) leave the old count.
  Future<void> check(SavedSearch search) async {
    if (!search.canCount) return;
    final server = ref.read(serverStateProvider).findById(search.serverId);
    if (server == null) return;
    final settings = ref.read(serverSettingStateProvider);
    final option = PageOption(
      query: search.query,
      limit: settings.postLimit,
      searchRating: settings.searchRating,
      // newest first, whatever the sort button says
      random: false,
      sort: '',
      language: settings.searchLanguages[server.id] ?? '',
    );
    try {
      final posts = await ref
          .read(imageboardRepoProvider(server))
          .getPage(option, 0);
      if (!ref.mounted) return;
      final blocked = ref
          .read(tagsBlockerStateProvider)
          .values
          .where((it) => it.serverId.isEmpty || it.serverId == server.id)
          .map((it) => it.name)
          .toSet();
      final shown = posts.where((it) => !it.allTags.any(blocked.contains));
      final current = find(search.serverId, search.query) ?? search;
      await _put(
        current.checked(
          posts.map((it) => it.id),
          shownIds: shown.map((it) => it.id),
          now: DateTime.now(),
        ),
      );
    } catch (_) {
      // try again next time
    }
  }
}
