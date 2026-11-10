import 'dart:convert';

import 'package:boorusphere/data/repository/booru/entity/post.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_ce/hive.dart';

/// Last page read of archives and galleries (Monbooru CBZ, nhentai), kept
/// on this device only. Pages are 0-based.
///
/// Besides the page, the post itself is kept (with the time it was last
/// read), so a "Continue reading" list can show it again.
class ReadingProgress {
  ReadingProgress(this._pages, this._recent);

  /// The store on the boxes opened by [openBoxes].
  factory ReadingProgress.fromOpenBoxes() =>
      ReadingProgress(Hive.box<int>(boxName), Hive.box<String>(recentBoxName));

  final Box<int> _pages;
  final Box<String> _recent;

  static const boxName = 'reading_progress';
  static const recentBoxName = 'reading_recent';

  /// How many posts the "Continue reading" list keeps.
  static const recentLimit = 100;

  /// Changes whenever a page is saved, so open screens can update.
  final changes = ValueNotifier(0);

  static String keyOf(Post post) => '${post.serverId}:${post.id}';

  Future<Box<int>> _box() async => _pages;

  Future<Box<String>> _recentBox() async => _recent;

  /// Opens the boxes; call once at startup, before [fromOpenBoxes].
  static Future<void> openBoxes() async {
    await Hive.openBox<int>(boxName);
    await Hive.openBox<String>(recentBoxName);
  }

  /// Last page read, or null if never opened.
  int? pageOfSync(Post post) => pageOfKey(keyOf(post));

  /// Like [pageOfSync], for a [keyOf] key.
  int? pageOfKey(String key) => _pages.get(key);

  Future<int?> pageOf(Post post) async => (await _box()).get(keyOf(post));

  Future<void> save(Post post, int page, {DateTime? now}) async {
    final box = await _box();
    if (box.get(keyOf(post)) != page) await box.put(keyOf(post), page);
    await _touch(post, now ?? DateTime.now());
    changes.value++;
  }

  /// Moves [post] to the top of the "Continue reading" list.
  Future<void> _touch(Post post, DateTime now) async {
    final box = await _recentBox();
    await box.put(
      keyOf(post),
      jsonEncode({'time': now.millisecondsSinceEpoch, 'post': post.toJson()}),
    );
    if (box.length <= recentLimit) return;
    final oldest = _entries(box).skip(recentLimit).map((it) => keyOf(it.post));
    await box.deleteAll(oldest.toList());
  }

  static List<({Post post, int time})> _entries(Box<String> box) {
    final result = <({Post post, int time})>[];
    for (final raw in box.values) {
      try {
        final map = jsonDecode(raw);
        if (map is! Map || map['post'] is! Map) continue;
        final post = Post.fromJson(Map<String, dynamic>.from(map['post']));
        final time = map['time'] is int ? map['time'] as int : 0;
        result.add((post: post, time: time));
      } catch (_) {
        // a broken entry is skipped, not fatal
      }
    }
    result.sort((a, b) => b.time.compareTo(a.time));
    return result;
  }

  /// Posts read recently, newest first.
  Future<List<Post>> recent() async =>
      _entries(await _recentBox()).map((it) => it.post).toList();

  /// Removes [post] from the "Continue reading" list; its page stays.
  Future<void> forget(Post post) async {
    await (await _recentBox()).delete(keyOf(post));
    changes.value++;
  }

  /// Removes [posts] from the "Continue reading" list, or empties it when
  /// none are given; pages read stay.
  Future<void> forgetAll([Iterable<Post>? posts]) async {
    final box = await _recentBox();
    if (posts == null) {
      await box.clear();
    } else {
      await box.deleteAll(posts.map(keyOf).toList());
    }
    changes.value++;
  }

  /// Whether the last page of [post] was reached.
  bool isFinished(Post post) {
    final page = pageOfSync(post);
    return page != null && post.pageCount > 0 && page >= post.pageCount - 1;
  }

  /// Pages and the "Continue reading" list, for backups.
  Future<Map<String, dynamic>> export() async => {
    'pages': Map<String, int>.from((await _box()).toMap()),
    'recent': Map<String, String>.from((await _recentBox()).toMap()),
  };

  /// Restores [export]ed data. Merges: entries of the backup replace the
  /// same posts here, others stay. Pages read further here are kept.
  Future<void> import(Object? data) async {
    if (data is! Map) return;
    final pages = data['pages'];
    if (pages is Map) {
      final box = await _box();
      for (final MapEntry(:key, :value) in pages.entries) {
        if (key is! String || value is! int) continue;
        final current = box.get(key);
        if (current == null || current < value) await box.put(key, value);
      }
    }
    final recent = data['recent'];
    if (recent is Map) {
      final box = await _recentBox();
      for (final MapEntry(:key, :value) in recent.entries) {
        if (key is String && value is String) await box.put(key, value);
      }
      if (box.length > recentLimit) {
        final oldest = _entries(
          box,
        ).skip(recentLimit).map((it) => keyOf(it.post));
        await box.deleteAll(oldest.toList());
      }
    }
    changes.value++;
  }

  Future<void> clear(Post post) async {
    await (await _box()).delete(keyOf(post));
    await (await _recentBox()).delete(keyOf(post));
    changes.value++;
  }
}
