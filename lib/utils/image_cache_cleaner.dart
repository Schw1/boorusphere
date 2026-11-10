import 'dart:io';

import 'package:extended_image/extended_image.dart' show cacheImageFolderName;
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Keeps the disk cache of images (thumbnails, samples, reader pages) from
/// growing without end: files stored more than [maxAge] ago are removed
/// when the app starts. Until now the cache was only emptied by hand
/// (Settings → Clear cache).
class ImageCacheCleaner {
  ImageCacheCleaner._();

  static const maxAge = Duration(days: 7);

  /// Removes the old files in a background isolate (the cache can hold
  /// tens of thousands of files). Returns how many were removed; never
  /// throws.
  static Future<int> run({Duration maxAge = maxAge}) async {
    try {
      final temp = await getTemporaryDirectory();
      // the folder extended_image caches network images in
      final dir = p.join(temp.path, cacheImageFolderName);
      final before = DateTime.now().subtract(maxAge);
      return await compute(removeFilesOlderThan, (
        dir,
        before.millisecondsSinceEpoch,
      ));
    } catch (e) {
      debugPrint('ImageCacheCleaner: $e');
      return 0;
    }
  }
}

/// Deletes the files directly in the folder `args.$1` that were last
/// written before `args.$2` (ms since epoch). Returns how many were
/// deleted. Top-level, so it can run in a background isolate.
int removeFilesOlderThan((String, int) args) {
  final (path, beforeMs) = args;
  final dir = Directory(path);
  if (!dir.existsSync()) return 0;
  var removed = 0;
  for (final entity in dir.listSync(followLinks: false)) {
    if (entity is! File) continue;
    try {
      if (entity.lastModifiedSync().millisecondsSinceEpoch < beforeMs) {
        entity.deleteSync();
        removed++;
      }
    } catch (_) {
      // gone or in use: leave it for the next run
    }
  }
  return removed;
}
