import 'dart:convert';

import 'package:boorusphere/data/repository/reading_progress.dart';
import 'package:boorusphere/data/repository/saved_search.dart';

/// Backup entry for reading progress, the "Continue reading" list and saved
/// searches (`reading.json`).
class ReadingBackup {
  ReadingBackup._();

  static const backupKey = 'reading';

  static Future<MapEntry<String, Object>> export() async {
    await SavedSearchStore.open();
    return MapEntry(backupKey, {
      'progress': await ReadingProgress.export(),
      'savedSearches': SavedSearchStore.export(),
    });
  }

  static Future<void> import(String src) async {
    final Object? data;
    try {
      data = jsonDecode(src);
    } catch (_) {
      return;
    }
    if (data is! Map) return;
    await ReadingProgress.import(data['progress']);
    await SavedSearchStore.import(data['savedSearches']);
  }
}
