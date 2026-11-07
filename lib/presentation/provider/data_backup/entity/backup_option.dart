import 'package:freezed_annotation/freezed_annotation.dart';

part 'backup_option.freezed.dart';

@freezed
class BackupOption with _$BackupOption {
  const factory BackupOption({
    @Default(true) bool searchHistory,
    @Default(true) bool server,
    @Default(true) bool blockedTags,
    @Default(true) bool favoritePost,
    @Default(true) bool setting,
    @Default(true) bool monloader,
    /// Credential parameters in the servers' URL suffix (api_key=…, …).
    /// Off by default: they would be in plain text in the backup file.
    @Default(false) bool credentials,
  }) = _BackupOption;
}

extension BackupOptionX on BackupOption {
  bool isValid() =>
      (searchHistory ||
          server ||
          blockedTags ||
          favoritePost ||
          setting ||
          monloader);
}
