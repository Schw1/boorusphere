import 'package:boorusphere/presentation/provider/settings/entity/booru_rating.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'page_option.freezed.dart';

@freezed
class PageOption with _$PageOption {
  const factory PageOption({
    @Default('') String query,
    @Default(false) bool clear,
    @Default(PageOption.defaultLimit) int limit,
    @Default(BooruRating.safe) BooruRating searchRating,
    @Default(false) bool random,
    // Seed for servers that support stable random paging (Monbooru)
    @Default(0) int seed,
  }) = _PageOption;
  const PageOption._();

  static const defaultLimit = 40;
}
