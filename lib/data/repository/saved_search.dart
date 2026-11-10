import 'dart:convert';
import 'dart:math' show max;

import 'package:hive_ce/hive.dart';

/// A search kept for later, with how many posts are new since it was last
/// opened. "New" means a higher post id than the newest one seen then, so
/// it only works with the server's default order (newest first).
class SavedSearch {
  const SavedSearch({
    required this.serverId,
    required this.query,
    this.seenId = -1,
    this.latestId = -1,
    this.newCount = 0,
    this.more = false,
    this.checkedAt = 0,
    this.createdAt = 0,
  });

  final String serverId;
  final String query;

  /// Newest post id when the search was last opened, -1 before the first
  /// check.
  final int seenId;

  /// Newest post id found by the last check.
  final int latestId;

  /// Posts newer than [seenId] on the first page at the last check.
  final int newCount;

  /// The whole first page was new, so there may be more than [newCount].
  final bool more;

  /// Last check, ms since epoch; 0 = never.
  final int checkedAt;
  final int createdAt;

  String get key => keyOf(serverId, query);

  static String normalize(String query) =>
      query.trim().split(RegExp(r'\s+')).where((it) => it.isNotEmpty).join(' ');

  static String keyOf(String serverId, String query) =>
      '$serverId\n${normalize(query)}';

  static final _typedOrder = RegExp(
    r'(^|\s)-?(order|sort):',
    caseSensitive: false,
  );

  /// Whether new posts can be counted: not with an `order:`/`sort:` tag,
  /// which puts something other than the newest posts first.
  bool get canCount => !_typedOrder.hasMatch(query);

  /// Smallest first page that counts as "full" for [more].
  static const fullPage = 20;

  /// Result of a check: [ids] are the posts on the first page (newest
  /// first), [shownIds] those of them that aren't hidden by blocked tags.
  /// The first check only remembers where the search stands.
  SavedSearch checked(
    Iterable<int> ids, {
    Iterable<int>? shownIds,
    required DateTime now,
  }) {
    final all = ids.toList();
    final latest = all.isEmpty ? latestId : max(latestId, all.reduce(max));
    if (seenId < 0) {
      return copyWith(
        seenId: latest,
        latestId: latest,
        newCount: 0,
        more: false,
        checkedAt: now.millisecondsSinceEpoch,
      );
    }
    final newIds = all.where((it) => it > seenId).toList();
    final shown = (shownIds ?? all).where((it) => it > seenId).length;
    return copyWith(
      latestId: latest,
      newCount: shown,
      more:
          newIds.isNotEmpty &&
          newIds.length == all.length &&
          all.length >= fullPage,
      checkedAt: now.millisecondsSinceEpoch,
    );
  }

  /// Opened: everything up to the newest known post counts as seen. [ids]
  /// are posts just loaded in newest-first order, if any.
  SavedSearch seen([Iterable<int> ids = const []]) {
    final latest = ids.fold(latestId, max);
    return copyWith(
      seenId: max(seenId, latest),
      latestId: latest,
      newCount: 0,
      more: false,
    );
  }

  SavedSearch copyWith({
    int? seenId,
    int? latestId,
    int? newCount,
    bool? more,
    int? checkedAt,
  }) => SavedSearch(
    serverId: serverId,
    query: query,
    seenId: seenId ?? this.seenId,
    latestId: latestId ?? this.latestId,
    newCount: newCount ?? this.newCount,
    more: more ?? this.more,
    checkedAt: checkedAt ?? this.checkedAt,
    createdAt: createdAt,
  );

  Map<String, dynamic> toJson() => {
    'serverId': serverId,
    'query': query,
    'seenId': seenId,
    'latestId': latestId,
    'newCount': newCount,
    'more': more,
    'checkedAt': checkedAt,
    'createdAt': createdAt,
  };

  static SavedSearch? fromJson(Object? json) {
    if (json is! Map) return null;
    final serverId = json['serverId'];
    final query = json['query'];
    if (serverId is! String || query is! String) return null;
    int number(Object? v, int or) => v is int ? v : or;
    return SavedSearch(
      serverId: serverId,
      query: normalize(query),
      seenId: number(json['seenId'], -1),
      latestId: number(json['latestId'], -1),
      newCount: number(json['newCount'], 0),
      more: json['more'] == true,
      checkedAt: number(json['checkedAt'], 0),
      createdAt: number(json['createdAt'], 0),
    );
  }
}

/// Saved searches on this device (Hive box of JSON strings).
class SavedSearchStore {
  SavedSearchStore(this._box);

  /// The store on the box opened by [openBox].
  factory SavedSearchStore.fromOpenBox() =>
      SavedSearchStore(Hive.box<String>(boxName));

  static const boxName = 'saved_searches';

  final Box<String> _box;

  /// Opens the box; call once at startup, before [fromOpenBox].
  static Future<void> openBox() => Hive.openBox<String>(boxName);

  Future<Box<String>> open() async => _box;

  /// All saved searches, oldest first (the order they were saved in).
  List<SavedSearch> all() {
    final result = <SavedSearch>[];
    for (final raw in _box.values) {
      try {
        final search = SavedSearch.fromJson(jsonDecode(raw));
        if (search != null) result.add(search);
      } catch (_) {
        // a broken entry is skipped
      }
    }
    result.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return result;
  }

  Future<void> put(SavedSearch search) async =>
      (await open()).put(search.key, jsonEncode(search.toJson()));

  /// For backups: all searches as JSON.
  List<Map<String, dynamic>> export() => [for (final it in all()) it.toJson()];

  /// Restores [export]ed searches. Ones already here keep their state.
  Future<void> import(Object? data) async {
    if (data is! List) return;
    final box = await open();
    for (final json in data) {
      final search = SavedSearch.fromJson(json);
      if (search == null || box.containsKey(search.key)) continue;
      await put(search);
    }
  }

  Future<void> remove(SavedSearch search) async =>
      (await open()).delete(search.key);
}
