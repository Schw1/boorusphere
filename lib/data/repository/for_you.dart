import 'dart:math';

import 'package:boorusphere/data/repository/booru/entity/post.dart';

/// The "For you" feed: which tags interest the user, judged by the posts
/// they favorited or sent to Monbooru, and how the searches for them are
/// mixed into one feed.
class ForYou {
  ForYou._();

  /// Tags about the file or the site rather than what's in it.
  static const ignored = {
    'highres',
    'absurdres',
    'incredibly_absurdres',
    'lowres',
    'commentary',
    'commentary_request',
    'english_commentary',
    'symbol-only_commentary',
    'translated',
    'partially_translated',
    'check_translation',
    'translation_request',
    'tagme',
    'artist_request',
    'source_request',
    'character_request',
    'copyright_request',
    'bad_id',
    'bad_pixiv_id',
    'bad_twitter_id',
    'md5_mismatch',
    'duplicate',
    'jpeg_artifacts',
    'third-party_edit',
    'revision',
    'alternate_version_available',
    'animated',
    'video',
    'sound',
    'webm',
    'mp4',
    'gif',
    'audio',
    'ai-generated',
    'ai-assisted',
    'large_filesize',
  };

  /// Same as `Post.viewId` (presentation layer).
  static String _keyOf(Post post) => '${post.id}-${post.serverId}';

  /// A tag only counts from this many posts on.
  static const minCount = 2;

  /// With at least [_commonSample] posts, tags in more than [_commonShare]
  /// of them (1girl, solo …) say little and are left out.
  static const _commonSample = 8;
  static const _commonShare = 0.6;

  /// Tags of one post as they count: no ratings, nhentai's quoted
  /// `tag:"…"` forms or `tag:x` doubles of a bare `x`, no [ignored].
  static Set<String> tagsOf(Post post) {
    final all = post.tags.map((it) => it.trim().toLowerCase()).toSet();
    return {
      for (final tag in all)
        if (tag.isNotEmpty &&
            !tag.contains('"') &&
            !tag.startsWith('rating:') &&
            !ignored.contains(tag) &&
            !(tag.startsWith('tag:') && all.contains(tag.substring(4))))
          tag,
    };
  }

  /// Tags by how many of [posts] have them, most first. [blocked] tags and
  /// tags of fewer than [minCount] posts are left out.
  static List<(String, int)> interests(
    Iterable<Post> posts, {
    Set<String> blocked = const {},
  }) {
    final unique = {for (final post in posts) _keyOf(post): post}.values;
    final counts = <String, int>{};
    for (final post in unique) {
      for (final tag in tagsOf(post)) {
        counts[tag] = (counts[tag] ?? 0) + 1;
      }
    }
    final total = unique.length;
    final result = [
      for (final MapEntry(:key, :value) in counts.entries)
        if (value >= minCount &&
            !blocked.contains(key) &&
            !(total >= _commonSample && value > total * _commonShare))
          (key, value),
    ]..sort((a, b) {
        final byCount = b.$2.compareTo(a.$2);
        return byCount != 0 ? byCount : a.$1.compareTo(b.$1);
      });
    return result;
  }

  /// [count] different tags from the [top] interests, more often the ones
  /// with more posts. A new pick each time, so refreshing shows other
  /// things.
  static List<String> pick(
    List<(String, int)> interests, {
    int count = 4,
    int top = 15,
    Random? random,
  }) {
    final rnd = random ?? Random();
    final pool = interests.take(top).toList();
    final picked = <String>[];
    while (picked.length < count && pool.isNotEmpty) {
      final total = pool.fold(0, (sum, it) => sum + it.$2);
      var at = rnd.nextInt(total);
      var index = 0;
      while (at >= pool[index].$2) {
        at -= pool[index].$2;
        index++;
      }
      picked.add(pool.removeAt(index).$1);
    }
    return picked;
  }

  /// One list from the result pages of several searches, taking turns so
  /// no tag takes over; posts already in [seen] (by view id) or in the
  /// feed are left out ([seen] holds `id-serverId` keys).
  static List<Post> mix(List<List<Post>> pages, {Set<String> seen = const {}}) {
    final taken = {...seen};
    final result = <Post>[];
    final longest = pages.fold(0, (m, it) => max(m, it.length));
    for (var i = 0; i < longest; i++) {
      for (final page in pages) {
        if (i >= page.length) continue;
        final post = page[i];
        if (taken.add(_keyOf(post))) result.add(post);
      }
    }
    return result;
  }
}
