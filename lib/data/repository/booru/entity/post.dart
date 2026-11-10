import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:hive_ce/hive.dart';

part 'post.freezed.dart';
part 'post.g.dart';

@freezed
abstract class Post with _$Post {
  @HiveType(typeId: 3, adapterName: 'PostAdapter')
  const factory Post({
    @HiveField(0, defaultValue: -1) @Default(-1) int id,
    @HiveField(1, defaultValue: '') @Default('') String originalFile,
    @HiveField(2, defaultValue: '') @Default('') String sampleFile,
    @HiveField(3, defaultValue: '') @Default('') String previewFile,
    @HiveField(4, defaultValue: []) @Default([]) List<String> tags,
    @HiveField(5, defaultValue: -1) @Default(-1) int width,
    @HiveField(6, defaultValue: -1) @Default(-1) int height,
    @HiveField(7, defaultValue: '') @Default('') String serverId,
    @HiveField(8, defaultValue: '') @Default('') String postUrl,
    @HiveField(9, defaultValue: 'q') @Default('q') String rateValue,
    @HiveField(10, defaultValue: -1) @Default(-1) int sampleWidth,
    @HiveField(11, defaultValue: -1) @Default(-1) int sampleHeight,
    @HiveField(12, defaultValue: -1) @Default(-1) int previewWidth,
    @HiveField(13, defaultValue: -1) @Default(-1) int previewHeight,
    @HiveField(14, defaultValue: '') @Default('') String source,
    @HiveField(15, defaultValue: []) @Default([]) List<String> tagsArtist,
    @HiveField(16, defaultValue: []) @Default([]) List<String> tagsCharacter,
    @HiveField(17, defaultValue: []) @Default([]) List<String> tagsCopyright,
    @HiveField(18, defaultValue: []) @Default([]) List<String> tagsGeneral,
    @HiveField(19, defaultValue: []) @Default([]) List<String> tagsMeta,
    @HiveField(20, defaultValue: 0) @Default(0) int score,

    /// md5 of the original file, '' when the booru doesn't tell.
    @HiveField(21, defaultValue: '') @Default('') String md5,

    /// Number of pages for archives (Monbooru CBZ), 0 for single files.
    @HiveField(22, defaultValue: 0) @Default(0) int pageCount,

    /// Title of a gallery (nhentai), '' for ordinary posts.
    @HiveField(23, defaultValue: '') @Default('') String title,

    /// Id of the parent post, 0 when there is none.
    @HiveField(24, defaultValue: 0) @Default(0) int parentId,

    /// The post has child posts (other versions, the rest of a set).
    @HiveField(25, defaultValue: false) @Default(false) bool hasChildren,

    /// Pools the post is in, when the booru lists them with the post
    /// (e621). Danbooru's are loaded with the details.
    @HiveField(26, defaultValue: <int>[]) @Default(<int>[]) List<int> poolIds,
  }) = _Post;

  factory Post.fromJson(Map<String, dynamic> json) => _$PostFromJson(json);

  static const empty = Post();
  static const appReserved = Post(id: -100);
}
