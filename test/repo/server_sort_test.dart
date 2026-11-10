import 'package:boorusphere/data/repository/booru/entity/page_option.dart';
import 'package:boorusphere/data/repository/server/entity/server.dart';
import 'package:boorusphere/presentation/provider/settings/entity/booru_rating.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const danbooru = Server(
    id: 'Danbooru',
    homepage: 'https://danbooru.donmai.us',
    searchUrl: 'posts.json?tags={tags}&page={page-id}&limit={post-limit}',
    searchParserId: 'Danbooru.json',
  );
  const gelbooru = Server(
    id: 'Gelbooru',
    homepage: 'https://gelbooru.com',
    searchUrl:
        'index.php?page=dapi&s=post&q=index&tags={tags}&pid={page-id}&limit={post-limit}&json=1',
    searchParserId: 'Gelbooru.json',
  );
  const monbooru = Server(
    id: 'Monbooru',
    homepage: 'http://192.168.0.10:8455',
    searchUrl:
        'api/v1/images/search?q={tags}&page={page-id}&limit={post-limit}',
    searchParserId: 'Monbooru.json',
  );
  const shimmie = Server(
    id: 'Shimmie',
    homepage: 'https://example.org',
    searchUrl:
        'api/danbooru/find_posts/index.xml?tags={tags}&page={page-id}&limit={post-limit}',
    searchParserId: 'Shimmie.xml',
  );

  String tagsOf(Server server, PageOption option) {
    final url = Uri.parse(server.searchUrlOf(option, page: 1));
    return url.queryParameters['tags'] ?? url.queryParameters['q'] ?? '';
  }

  const all = PageOption(searchRating: BooruRating.all);

  test('options per engine', () {
    expect(danbooru.sortOptions, contains('rank'));
    expect(gelbooru.sortOptions, isNot(contains('rank')));
    expect(monbooru.sortOptions, ['', 'oldest', 'size']);
    expect(shimmie.sortOptions, isEmpty);
  });

  test('danbooru tags', () {
    expect(
      tagsOf(danbooru, all.copyWith(sort: 'rank')),
      contains('order:rank'),
    );
    expect(
      tagsOf(danbooru, all.copyWith(sort: 'favcount')),
      contains('order:favcount'),
    );
    expect(tagsOf(danbooru, all), isNot(contains('order:')));
  });

  test('gelbooru tags', () {
    expect(
      tagsOf(gelbooru, all.copyWith(sort: 'score')),
      contains('sort:score:desc'),
    );
    // not offered there: ignored
    expect(
      tagsOf(gelbooru, all.copyWith(sort: 'rank')),
      isNot(contains('sort:')),
    );
  });

  test('monbooru params', () {
    final url = monbooru.searchUrlOf(all.copyWith(sort: 'size'), page: 1);
    expect(Uri.parse(url).queryParameters['sort'], 'filesize');
  });

  test('random and typed order win', () {
    final random = tagsOf(
      danbooru,
      all.copyWith(sort: 'rank', random: true, seed: 1),
    );
    expect(random, contains('order:random'));
    expect(random, isNot(contains('order:rank')));
    final typed = tagsOf(
      danbooru,
      all.copyWith(query: 'cat order:score', sort: 'rank'),
    );
    expect(typed, isNot(contains('order:rank')));
    expect(typed, contains('order:score'));
  });
}
