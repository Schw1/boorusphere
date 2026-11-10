import 'dart:convert';

import 'package:boorusphere/data/repository/tags_blocker/entity/booru_tag.dart';
import 'package:boorusphere/domain/repository/tags_blocker_repo.dart';
import 'package:boorusphere/presentation/provider/data_backup/data_backup.dart';
import 'package:hive_ce/hive.dart';

class BooruTagsBlockerRepo implements TagsBlockerRepo {
  BooruTagsBlockerRepo(this.box);

  final Box<BooruTag> box;

  @override
  Map<int, BooruTag> get() {
    return Map.from(box.toMap());
  }

  @override
  Future<void> delete(key) async {
    await box.delete(key);
  }

  @override
  Future<void> push(BooruTag value) async {
    final tag = value.copyWith(name: value.name.trim());
    if (tag.name.isNotEmpty && !box.values.contains(tag)) {
      await box.add(tag);
    }
  }

  @override
  Future<void> import(String src) async {
    final List maps = jsonDecode(src);
    // Read the whole backup first: the list here is only replaced once
    // there is something to replace it with.
    final tags = <BooruTag>[];
    for (final data in maps) {
      try {
        if (data is Map) {
          tags.add(BooruTag.fromJson(Map<String, dynamic>.from(data)));
        } else if (data is String) {
          tags.add(BooruTag(name: data));
        }
      } catch (_) {
        // a broken entry is skipped, the others are still restored
      }
    }
    if (tags.isEmpty) return;
    await box.clear();
    for (final tag in tags) {
      await push(tag);
    }
  }

  @override
  Future<BackupItem> export() async {
    return BackupItem(boxKey, box.values.map((e) => e.toJson()).toList());
  }

  static const String boxKey = 'blockedTags';

  static Future<void> prepare() async {
    final box = await Hive.openBox(boxKey);
    for (final tag in box.toMap().entries) {
      if (tag.value is String) {
        await box.put(tag.key, BooruTag(name: tag.value));
      }
    }
    await box.close();
    await Hive.openBox<BooruTag>(boxKey);
  }
}
