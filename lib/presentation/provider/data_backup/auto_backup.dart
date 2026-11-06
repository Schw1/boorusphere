import 'dart:io';

import 'package:boorusphere/data/repository/setting/entity/setting.dart';
import 'package:boorusphere/domain/provider.dart';
import 'package:boorusphere/domain/repository/settings_repo.dart';
import 'package:boorusphere/presentation/provider/data_backup/data_backup.dart';
import 'package:boorusphere/presentation/provider/data_backup/entity/backup_option.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'auto_backup.g.dart';

enum AutoBackupInterval {
  daily(Duration(days: 1)),
  weekly(Duration(days: 7));

  const AutoBackupInterval(this.duration);

  final Duration duration;

  static AutoBackupInterval fromName(String name) => AutoBackupInterval.values
      .firstWhere((it) => it.name == name, orElse: () => daily);
}

@Riverpod(keepAlive: true)
AutoBackup autoBackup(AutoBackupRef ref) => AutoBackup(ref);

/// Automatic backups. iOS gives apps no reliable background time, so a
/// backup is made when the app starts or returns to the foreground and the
/// last one is older than the chosen interval. Only the newest [keep]
/// automatic backups are kept; manual backups are never touched.
class AutoBackup {
  AutoBackup(this.ref);

  final Ref ref;
  bool _running = false;

  static const kind = 'autobackup';
  static const keepOptions = [1, 3, 5, 10];
  static String get _prefix => '${DataBackupState.appId}_${kind}_';

  SettingsRepo get _repo => ref.read(settingsRepoProvider);

  bool get enabled => _repo.get(Setting.backupAutoEnabled, or: false);

  AutoBackupInterval get interval => AutoBackupInterval.fromName(
      _repo.get(Setting.backupAutoInterval, or: AutoBackupInterval.daily.name));

  int get keep => _repo.get(Setting.backupAutoKeep, or: 3);

  DateTime? get lastRun {
    final ms = _repo.get(Setting.backupAutoLast, or: 0);
    return ms > 0 ? DateTime.fromMillisecondsSinceEpoch(ms) : null;
  }

  Future<void> setEnabled(bool value) async {
    await _repo.put(Setting.backupAutoEnabled, value);
    if (value) await runIfDue();
  }

  Future<void> setInterval(AutoBackupInterval value) =>
      _repo.put(Setting.backupAutoInterval, value.name);

  Future<void> setKeep(int value) async {
    await _repo.put(Setting.backupAutoKeep, value);
    await _rotate();
  }

  Future<void> runIfDue() async {
    if (_running || !enabled) return;
    final last = lastRun;
    if (last != null &&
        DateTime.now().difference(last) < interval.duration) {
      return;
    }
    _running = true;
    try {
      await writeBackupFile(ref, const BackupOption(), kind: kind);
      await _repo.put(
          Setting.backupAutoLast, DateTime.now().millisecondsSinceEpoch);
      await _rotate();
    } catch (e, s) {
      debugPrint('AutoBackup failed: $e\n$s');
    } finally {
      _running = false;
    }
  }

  Future<void> _rotate() async {
    try {
      final dir = await backupDirectory(ref);
      final files = dir
          .listSync()
          .whereType<File>()
          .where((f) {
            final name = p.basename(f.path);
            return name.startsWith(_prefix) && name.endsWith('.zip');
          })
          .toList()
        // the timestamp in the name sorts chronologically
        ..sort((a, b) => p.basename(b.path).compareTo(p.basename(a.path)));
      for (final old in files.skip(keep < 1 ? 1 : keep)) {
        old.deleteSync();
      }
    } catch (e) {
      debugPrint('AutoBackup rotate failed: $e');
    }
  }
}
