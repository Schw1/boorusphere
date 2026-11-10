import 'dart:convert';

import 'package:boorusphere/data/repository/booru/entity/post.dart';
import 'package:boorusphere/data/repository/favorite_post/entity/favorite_post.dart';
import 'package:boorusphere/domain/repository/favorite_post_repo.dart';
import 'package:boorusphere/presentation/provider/data_backup/data_backup.dart';
import 'package:hive_ce/hive.dart';

class UserFavoritePostRepo implements FavoritePostRepo {
  UserFavoritePostRepo(this.box);

  final Box<FavoritePost> box;

  @override
  Iterable<Post> get() {
    return box.values.map((e) => e.post);
  }

  @override
  Future<void> clear() async {
    await box.clear();
  }

  @override
  Future<void> remove(Post post) async {
    final fav = FavoritePost(post: post);
    await box.delete(fav.key);
  }

  @override
  Future<void> save(Post post) async {
    final fav = FavoritePost(
      post: post,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );

    await box.put(fav.key, fav);
  }

  @override
  Future<void> import(String src) async {
    final List maps = jsonDecode(src);
    // Read the whole backup first: the favorites here are only replaced
    // once there is something to replace them with.
    final favorites = <String, FavoritePost>{};
    for (final map in maps) {
      if (map is! Map) continue;
      try {
        final fav = FavoritePost.fromJson(Map<String, dynamic>.from(map));
        favorites[fav.key] = fav;
      } catch (_) {
        // a broken entry is skipped, the others are still restored
      }
    }
    if (favorites.isEmpty) return;
    await box.clear();
    await box.putAll(favorites);
  }

  @override
  Future<BackupItem> export() async {
    return BackupItem(key, box.values.map((e) => e.toJson()).toList());
  }

  static const String key = 'favorites';
  static Future<void> prepare() => Hive.openBox<FavoritePost>(key);
}
