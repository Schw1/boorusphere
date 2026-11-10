import 'dart:convert';

import 'package:boorusphere/data/repository/reading_progress.dart';
import 'package:boorusphere/data/repository/saved_search.dart';

/// Backup entry for reading progress, the "Continue reading" list and saved
/// searches (`reading.json`).
class ReadingBackup {
  ReadingBackup._();

  static const backupKey = 'reading';

  static Future<MapEntry<String, Object>> export(
    ReadingProgress progress,
    SavedSearchStore searches,
  ) async {
    return MapEntry(backupKey, {
      'progress': await progress.export(),
      'savedSearches': searches.export(),
    });
  }

  static Future<void> import(
    String src,
    ReadingProgress progress,
    SavedSearchStore searches,
  ) async {
    final Object? data;
    try {
      data = jsonDecode(src);
    } catch (_) {
      return;
    }
    if (data is! Map) return;
    await progress.import(data['progress']);
    await searches.import(data['savedSearches']);
  }
}
