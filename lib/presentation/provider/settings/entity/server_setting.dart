import 'package:boorusphere/data/repository/booru/entity/page_option.dart';
import 'package:boorusphere/presentation/provider/settings/entity/booru_rating.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'server_setting.freezed.dart';

@freezed
abstract class ServerSetting with _$ServerSetting {
  const factory ServerSetting({
    @Default('') String lastActiveId,
    @Default(PageOption.defaultLimit) int postLimit,
    @Default(BooruRating.safe) BooruRating searchRating,
    @Default(false) bool searchRandom,

    /// Sort order per server id ('' = newest; see Server.sortOptions)
    @Default({}) Map<String, String> searchSorts,

    /// Language filter per server id ('' = all; nhentai only)
    @Default({}) Map<String, String> searchLanguages,
  }) = _ServerSetting;
  const ServerSetting._();
}
