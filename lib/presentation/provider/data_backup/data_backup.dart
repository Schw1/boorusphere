import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:boorusphere/data/repository/favorite_post/user_favorite_post_repo.dart';
import 'package:boorusphere/data/repository/reading_backup.dart';
import 'package:boorusphere/data/repository/search_history/user_search_history.dart';
import 'package:boorusphere/data/repository/server/server_auth_store.dart';
import 'package:boorusphere/data/repository/server/user_server_repo.dart';
import 'package:boorusphere/data/repository/setting/user_setting_repo.dart';
import 'package:boorusphere/data/repository/tags_blocker/booru_tags_blocker_repo.dart';
import 'package:boorusphere/domain/provider.dart';
import 'package:boorusphere/presentation/provider/data_backup/entity/backup_option.dart';
import 'package:boorusphere/presentation/provider/data_backup/entity/backup_result.dart';
import 'package:boorusphere/presentation/provider/favorite_post_state.dart';
import 'package:boorusphere/presentation/provider/monbooru_sender.dart';
import 'package:boorusphere/presentation/provider/saved_searches.dart';
import 'package:boorusphere/presentation/provider/search_history_state.dart';
import 'package:boorusphere/presentation/provider/server_data_state.dart';
import 'package:boorusphere/presentation/provider/settings/content_setting_state.dart';
import 'package:boorusphere/presentation/provider/settings/download_setting_state.dart';
import 'package:boorusphere/presentation/provider/settings/server_setting_state.dart';
import 'package:boorusphere/presentation/provider/settings/ui_setting_state.dart';
import 'package:boorusphere/presentation/provider/shared_storage_handle.dart';
import 'package:boorusphere/presentation/provider/tags_blocker_state.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart' show Ref;
import 'package:intl/intl.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:restart_app/restart_app.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'data_backup.g.dart';

typedef BackupItem = MapEntry<String, Object>;

enum DataBackupType { backup, restore }

/// Folder of all backups (manual and automatic), visible in the Files app.
Future<Directory> backupDirectory(Ref ref) async {
  final sharedStorageHandle = ref.read(sharedStorageHandleProvider);
  await sharedStorageHandle.init();
  return sharedStorageHandle.createSubDir('backups');
}

/// Writes a backup zip into [backupDirectory] and returns its path.
/// [kind] becomes part of the file name (`boorusphere_<kind>_<time>.zip`).
Future<String> writeBackupFile(
  Ref ref,
  BackupOption option, {
  String kind = 'backup',
}) async {
  final versionRepo = ref.read(versionRepoProvider);
  final entries = [
    Future.value(BackupItem(DataBackupState.appId,
        {'version': '${versionRepo.current}'})),
    if (option.server)
      ref
          .read(serverRepoProvider)
          .export(withCredentials: option.credentials),
    if (option.blockedTags) ref.read(tagsBlockerRepoProvider).export(),
    if (option.favoritePost) ref.read(favoritePostRepoProvider).export(),
    if (option.setting) ref.read(settingsRepoProvider).export(),
    if (option.searchHistory) ref.read(searchHistoryRepoProvider).export(),
    if (option.monloader)
      MonbooruSender.exportBackup(withToken: option.credentials),
    if (option.reading) ReadingBackup.export(),
    // API tokens of servers (Keychain/Keystore) only with login data, e.g.
    // to move to another device.
    if (option.server && option.credentials)
      Future.value(
          ServerAuthStore.exportBackup(ref.read(serverRepoProvider).servers)),
  ];

  // Own temp folder per run, so a manual and an automatic backup can't clash.
  final basedir = await getTemporaryDirectory();
  final temp = Directory(path.join(basedir.path,
      '.backup.tmp-${DateTime.now().microsecondsSinceEpoch}'));
  temp.createSync(recursive: true);
  try {
    final zipPath = path.join(temp.path, 'data.zip');
    final encoder = ZipFileEncoder();
    encoder.create(zipPath);
    await Future.wait(entries.map((entry) async {
      final item = await entry;
      final data = item.value;
      if (data is List && data.isEmpty) return;

      final file = File('${temp.path}/${item.key}.json');
      await file.writeAsString(jsonEncode(data));
      return encoder.addFile(file);
    }));
    await encoder.close();

    final dir = await backupDirectory(ref);
    final time = DateFormat('yyyy-MM-dd-HH-mm-ss').format(DateTime.now());
    final name = '${DataBackupState.appId}_${kind}_$time.zip';
    final zip = File(path.join(dir.path, name));
    if (zip.existsSync()) {
      zip.deleteSync();
    }
    await File(zipPath).copy(zip.path);
    await ref.read(sharedStorageHandleProvider).rescan();
    return zip.path;
  } finally {
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  }
}

@riverpod
class DataBackupState extends _$DataBackupState {
  @override
  BackupResult build() {
    return const BackupResult.idle();
  }

  Future<Directory> _backupDir() => backupDirectory(ref);

  void _invalidateProviders() {
    ref.invalidate(serverStateProvider);
    ref.invalidate(tagsBlockerStateProvider);
    ref.invalidate(searchHistoryStateProvider);
    ref.invalidate(favoritePostStateProvider);
    ref.invalidate(uiSettingStateProvider);
    ref.invalidate(contentSettingStateProvider);
    ref.invalidate(downloadSettingStateProvider);
    ref.invalidate(serverSettingStateProvider);
    ref.invalidate(savedSearchesProvider);
  }

  /// Restores a backup picked by the user. If a file in it can't be read,
  /// the restore stops with an error instead of hanging; what was restored
  /// up to then is shown, and each kind of data is only replaced once its
  /// file turned out readable (see the `import` of the repositories).
  Future<void> restore({Future<bool?> Function()? onConfirm}) async {
    try {
      await _restore(onConfirm: onConfirm);
    } catch (e, s) {
      debugPrint('Restore failed: $e\n$s');
      if (!ref.mounted) return;
      try {
        _invalidateProviders();
        await ref.read(serverStateProvider.notifier).populate();
      } catch (e) {
        debugPrint('Restore: reloading failed: $e');
      }
      if (!ref.mounted) return;
      state = BackupResult.error(error: e, stackTrace: s);
    }
  }

  Future<void> _restore({Future<bool?> Function()? onConfirm}) async {
    final backupsDir = await _backupDir();
    await FilePicker.clearTemporaryFiles();

    final picked = await FilePicker.pickFile(
      initialDirectory: backupsDir.absolute.path,
      type: FileType.custom,
      allowedExtensions: ['zip'],
    );

    if (picked == null) {
      state = const BackupResult.idle();
      return;
    }
    // Backups are small JSON files: decoding from memory leaves no open file
    // handle behind (archive 4 has no decodeBuffer anymore).
    final decoder = ZipDecoder().decodeBytes(await picked.readAsBytes());
    if (!decoder.files.any((it) => it.name == '$appId.json')) {
      state = const BackupResult.error();
      return;
    }

    final confirm = onConfirm ?? () async => true;
    final continueRestore = await confirm.call() ?? false;
    if (!continueRestore) {
      state = const BackupResult.idle();
      return;
    }

    state = const BackupResult.loading(DataBackupType.restore);
    for (final json in decoder.files) {
      final content = utf8.decode(json.content);
      switch (json.name.replaceAll('.json', '')) {
        case UserServerRepo.key:
          await ref.read(serverRepoProvider).import(content);
          break;
        case BooruTagsBlockerRepo.boxKey:
          await ref.read(tagsBlockerRepoProvider).import(content);
          break;
        case UserFavoritePostRepo.key:
          await ref.read(favoritePostRepoProvider).import(content);
          break;
        case UserSettingsRepo.key:
          await ref.read(settingsRepoProvider).import(content);
          break;
        case UserSearchHistoryRepo.key:
          await ref.read(searchHistoryRepoProvider).import(content);
          break;
        case MonbooruSender.backupKey:
          await MonbooruSender.importBackup(content);
          break;
        case ServerAuthStore.backupKey:
          await ServerAuthStore.importBackup(content);
          break;
        case ReadingBackup.backupKey:
          await ReadingBackup.import(content);
          break;
        default:
          break;
      }
    }

    _invalidateProviders();
    // ServerState is keepAlive and only filled by populate() at app start. Android
    // restarts the app after a restore, iOS cannot, so refill the list here.
    await ref.read(serverStateProvider.notifier).populate();
    state = const BackupResult.imported();
    // restart_app cannot relaunch the app by itself on iOS
    if (Platform.isAndroid) {
      await Restart.restartApp();
    }
  }

  Future<void> backup({BackupOption option = const BackupOption()}) async {
    if (!option.isValid()) return;

    state = const BackupResult.loading(DataBackupType.backup);
    final zip = await writeBackupFile(ref, option);
    state = BackupResult.exported(zip);
  }

  static const appId = 'boorusphere';
}
