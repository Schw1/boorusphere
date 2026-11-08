import 'package:boorusphere/data/repository/booru/entity/post.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_ce/hive.dart';

/// Last page read of archives and galleries (Monbooru CBZ, nhentai), kept
/// on this device only. Pages are 0-based.
class ReadingProgress {
  ReadingProgress._();

  static const boxName = 'reading_progress';

  /// Changes whenever a page is saved, so open screens can update.
  static final changes = ValueNotifier(0);

  static String keyOf(Post post) => '${post.serverId}:${post.id}';

  static Future<Box<int>> _box() async => Hive.isBoxOpen(boxName)
      ? Hive.box<int>(boxName)
      : await Hive.openBox<int>(boxName);

  /// Opens the store early, so [pageOfSync] has data.
  static Future<void> open() => _box();

  /// Last page read, or null if never opened (or the store isn't open).
  static int? pageOfSync(Post post) =>
      Hive.isBoxOpen(boxName) ? Hive.box<int>(boxName).get(keyOf(post)) : null;

  static Future<int?> pageOf(Post post) async => (await _box()).get(keyOf(post));

  static Future<void> save(Post post, int page) async {
    final box = await _box();
    if (box.get(keyOf(post)) == page) return;
    await box.put(keyOf(post), page);
    changes.value++;
  }

  static Future<void> clear(Post post) async {
    await (await _box()).delete(keyOf(post));
    changes.value++;
  }
}
