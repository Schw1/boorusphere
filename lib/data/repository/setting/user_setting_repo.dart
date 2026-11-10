import 'dart:convert';

import 'package:boorusphere/data/repository/setting/entity/setting.dart';
import 'package:boorusphere/domain/repository/settings_repo.dart';
import 'package:boorusphere/presentation/provider/data_backup/data_backup.dart';
import 'package:boorusphere/presentation/provider/settings/entity/booru_rating.dart';
import 'package:boorusphere/presentation/provider/settings/entity/download_quality.dart';
import 'package:hive_ce/hive.dart';

class UserSettingsRepo implements SettingsRepo {
  UserSettingsRepo(this.box);

  final Box box;

  @override
  T get<T>(Setting key, {required T or}) => box.get(key.name) ?? or;

  @override
  Future<void> put<T>(Setting key, T value) => box.put(key.name, value);

  @override
  Future<void> import(String src) async {
    final Map map = jsonDecode(src);
    // Read the whole backup first: the settings here are only replaced
    // once there is something to replace them with. The writes are awaited,
    // so a failure reaches the restore instead of getting lost.
    final settings = <String, Object?>{};
    for (final MapEntry(:key, :value) in map.entries) {
      if (key is! String) continue;
      if (key == Setting.downloadsQuality.name) {
        if (value is String) settings[key] = DownloadQuality.fromName(value);
      } else if (key == Setting.searchRating.name) {
        if (value is String) settings[key] = BooruRating.fromName(value);
      } else {
        settings[key] = value;
      }
    }
    if (settings.isEmpty) return;
    await box.clear();
    await box.putAll(settings);
  }

  @override
  Future<BackupItem> export() async {
    return BackupItem(
      key,
      box.toMap().map((key, value) {
        if (value is DownloadQuality) {
          return MapEntry(key, value.name);
        } else if (value is BooruRating) {
          return MapEntry(key, value.name);
        } else {
          return MapEntry(key, value);
        }
      }),
    );
  }

  static const String key = 'settings';
  static Future<void> prepare() async {
    await Hive.openBox(key);
  }
}
