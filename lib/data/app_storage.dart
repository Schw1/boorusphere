import 'dart:io';

import 'package:boorusphere/utils/logger.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

final _log = Logger('AppStorage');

/// Where the app keeps its own data (Hive boxes, cookies).
///
/// iOS shows the app's Documents folder in the Files app, so downloads and
/// backups can be found there. Older versions also kept the Hive boxes and
/// the cookie jar in it, where they could be deleted by accident and showed
/// login data. They now live in Application Support, which only the app
/// sees; [prepare] moves existing data over once.
///
/// Android keeps everything where it was: its documents folder is private.
class AppStorage {
  const AppStorage({required this.hivePath, required this.cookiePath});

  final String hivePath;
  final String cookiePath;

  static Future<AppStorage> prepare() async {
    final docs = await getApplicationDocumentsDirectory();
    if (!Platform.isIOS) {
      return AppStorage(
        hivePath: docs.path,
        cookiePath: p.join(docs.path, 'cookies'),
      );
    }
    final support = await getApplicationSupportDirectory();
    return AppStorage(
      hivePath: await moveHiveData(
        from: docs,
        to: Directory(p.join(support.path, 'hive')),
      ),
      cookiePath: await moveDirectory(
        from: Directory(p.join(docs.path, 'cookies')),
        to: Directory(p.join(support.path, 'cookies')),
      ),
    );
  }

  /// Marks a target folder whose data is complete. Written only after
  /// every file was copied, so an interrupted move is started over.
  static const marker = '.moved';

  static bool _isHiveFile(FileSystemEntity it) =>
      it is File &&
      (it.path.endsWith('.hive') ||
          it.path.endsWith('.hivec') ||
          it.path.endsWith('.lock'));

  /// Moves the Hive files (`*.hive`, `*.hivec`) lying directly in [from]
  /// into [to] and returns the folder to open Hive in.
  ///
  /// Everything is copied first and the originals are only deleted once the
  /// copies are complete. If copying fails, the data stays in [from] and
  /// [from] is returned, so nothing is lost; the next start tries again.
  static Future<String> moveHiveData({
    required Directory from,
    required Directory to,
  }) async {
    final done = File(p.join(to.path, marker));
    List<File> leftovers() => from.existsSync()
        ? from.listSync().where(_isHiveFile).cast<File>().toList()
        : const [];

    if (done.existsSync()) {
      // Already moved; originals the last start could not delete.
      _deleteAll(leftovers());
      return to.path;
    }

    final files = leftovers()
        .where((it) => !it.path.endsWith('.lock'))
        .toList();
    try {
      // Anything there is from an interrupted move: start over.
      if (to.existsSync()) to.deleteSync(recursive: true);
      to.createSync(recursive: true);
      for (final file in files) {
        file.copySync(p.join(to.path, p.basename(file.path)));
      }
      done.writeAsStringSync('${files.length}');
    } catch (e, s) {
      _log.e('Hive data not moved, using ${from.path}', e, s);
      try {
        if (to.existsSync()) to.deleteSync(recursive: true);
      } catch (_) {
        // the next start deletes it
      }
      return from.path;
    }
    if (files.isNotEmpty) {
      _log.i('Moved ${files.length} Hive files to ${to.path}');
    }
    _deleteAll(leftovers());
    return to.path;
  }

  /// Moves the folder [from] (the cookie jar) to [to] and returns the
  /// folder to use, the same way as [moveHiveData].
  static Future<String> moveDirectory({
    required Directory from,
    required Directory to,
  }) async {
    final done = File(p.join(to.path, marker));
    if (done.existsSync()) {
      _deleteDirectory(from);
      return to.path;
    }
    try {
      if (to.existsSync()) to.deleteSync(recursive: true);
      to.createSync(recursive: true);
      if (from.existsSync()) _copyDirectory(from, to);
      done.writeAsStringSync('');
    } catch (e, s) {
      _log.e('${from.path} not moved', e, s);
      try {
        if (to.existsSync()) to.deleteSync(recursive: true);
      } catch (_) {
        // the next start deletes it
      }
      return from.path;
    }
    _deleteDirectory(from);
    return to.path;
  }

  static void _copyDirectory(Directory from, Directory to) {
    for (final entity in from.listSync(followLinks: false)) {
      final target = p.join(to.path, p.basename(entity.path));
      if (entity is Directory) {
        _copyDirectory(entity, Directory(target)..createSync());
      } else if (entity is File) {
        entity.copySync(target);
      }
    }
  }

  static void _deleteAll(Iterable<File> files) {
    for (final file in files) {
      try {
        file.deleteSync();
      } catch (e) {
        _log.w('Could not delete ${file.path}: $e');
      }
    }
  }

  static void _deleteDirectory(Directory dir) {
    try {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    } catch (e) {
      _log.w('Could not delete ${dir.path}: $e');
    }
  }
}
