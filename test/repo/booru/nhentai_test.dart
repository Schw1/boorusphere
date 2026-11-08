import 'package:boorusphere/data/repository/booru/entity/page_option.dart';
import 'package:boorusphere/data/repository/booru/parser/nhentai_json_parser.dart';
import 'package:boorusphere/data/repository/server/entity/server.dart';
import 'package:boorusphere/presentation/utils/extensions/post.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

// Shapes as returned by nhentai's API v2 (titles and tags made up).
Map<String, dynamic> _item(int id, {int pages = 12, bool blacklisted = false}) =>
    {
      'id': id,
      'media_id': '${id + 1000}',
      'english_title': 'Gallery $id [English]',
      'japanese_title': 'ギャラリー $id',
      'thumbnail': 'galleries/${id + 1000}/thumb.webp',
      'thumbnail_width': 250,
      'thumbnail_height': 353,
      'num_pages': pages,
      'num_favorites': 42,
      'tag_ids': [1, 2, 3],
      'blacklisted': blacklisted,
      'suggestion': null,
    };

Response _page(List<Map<String, dynamic>> items) => Response(
      requestOptions:
          RequestOptions(path: 'https://nhentai.net/api/v2/search'),
      statusCode: 200,
      data: {
        'result': items,
        'num_pages': 20,
        'per_page': 25,
        'total': 500,
      },
    );

const _gallery = {
  'id': 5,
  'media_id': '1005',
  'title': {
    'english': 'Gallery 5 [English]',
    'japanese': 'ギャラリー 5',
    'pretty': 'Gallery 5',
  },
  'cover': {'path': 'galleries/1005/cover.webp.webp', 'width': 350},
  'thumbnail': {'path': 'galleries/1005/thumb.webp'},
  'tags': [
    {'id': 1, 'type': 'category', 'name': 'doujinshi'},
    {'id': 2, 'type': 'language', 'name': 'english'},
    {'id': 3, 'type': 'tag', 'name': 'school uniform'},
    {'id': 4, 'type': 'tag', 'name': 'glasses'},
    {'id': 5, 'type': 'artist', 'name': 'someone'},
  ],
  'num_pages': 2,
  'pages': [
    {'number': 1, 'path': 'galleries/1005/1.webp', 'width': 1280},
    {'number': 2, 'path': 'galleries/1005/2.jpg', 'width': 1280},
  ],
};

void main() {
  const server = Server(
    id: 'nhentai.net',
    homepage: 'https://nhentai.net',
    searchUrl: 'api/v2/search?query={tags}&page={page-id}',
    postUrl: 'g/{post-id}/',
    searchParserId: NhentaiJsonParser.parserId,
  );
  final parser = NhentaiJsonParser();

  group('search URL', () {
    String url(String query) =>
        server.searchUrlOf(PageOption(query: query), page: 1);

    test('empty search matches everything', () {
      expect(url(''), contains('query=${Uri.encodeComponent('pages:>0')}'));
      expect(url(''), isNot(contains('sort=')));
    });

    test('order tags become the sort parameter', () {
      expect(url('order:rank'), endsWith('&sort=popular-week'));
      expect(url('order:rank'),
          contains('query=${Uri.encodeComponent('pages:>0')}'));
      expect(url('language:german order:popular-today'),
          allOf(contains('query=language%3Agerman&'),
              endsWith('&sort=popular-today')));
      expect(url('sort:month'), endsWith('&sort=popular-month'));
      expect(url('order:popular'), endsWith('&sort=popular'));
      expect(url('order:recent tag:glasses'), isNot(contains('sort=')));
    });

    test('no rating tags and no catch-all', () {
      final split = NhentaiJsonParser.splitQuery('* rating:safe tag:glasses');
      expect(split.query, 'tag:glasses');
      expect(split.sort, '');
    });

    test('unknown order values stay in the query', () {
      expect(NhentaiJsonParser.splitQuery('order:foo').query, 'order:foo');
    });

    test('page and quoted tags', () {
      final u = server.searchUrlOf(
          PageOption(query: 'tag:"school uniform"'), page: 3);
      expect(u, startsWith('https://nhentai.net/api/v2/search?query='));
      expect(Uri.parse(u).queryParameters['query'], 'tag:"school uniform"');
      expect(Uri.parse(u).queryParameters['page'], '3');
    });
  });

  group('parser', () {
    test('recognizes search pages only', () {
      expect(parser.canParsePage(_page([_item(1)])), isTrue);
      expect(
          parser.canParsePage(Response(
              requestOptions: RequestOptions(),
              data: {'results': [], 'total': 0})),
          isFalse);
      expect(NhentaiJsonParser.isNhentai(server), isTrue);
    });

    test('galleries become posts', () {
      final posts = parser.parsePage(server, _page([_item(5)])).toList();
      expect(posts, hasLength(1));
      final post = posts.single;
      expect(post.id, 5);
      expect(post.previewFile, 'https://t.nhentai.net/galleries/1005/thumb.webp');
      expect(post.sampleFile, post.previewFile);
      expect(post.originalFile, isEmpty);
      expect(post.pageCount, 12);
      expect(post.isArchive, isTrue);
      expect(post.postUrl, 'https://nhentai.net/g/5/');
      expect(post.title, 'Gallery 5 [English]');
      expect(post.rateValue, 'e');
      expect(post.width, 250);
      expect(post.height, 353);
      expect(post.content.isPhoto, isTrue);
    });

    test('skips blacklisted and empty galleries', () {
      final posts = parser.parsePage(
        server,
        _page([
          _item(1, blacklisted: true),
          _item(2, pages: 0),
          _item(3),
        ]),
      );
      expect(posts.map((it) => it.id), [3]);
    });
  });

  group('gallery', () {
    test('pages, cover and tags', () {
      final gallery = NhentaiGallery.fromJson(_gallery)!;
      expect(gallery.id, 5);
      expect(gallery.title, 'Gallery 5 [English]');
      expect(gallery.cover,
          'https://t.nhentai.net/galleries/1005/cover.webp.webp');
      expect(gallery.pages, [
        'https://i.nhentai.net/galleries/1005/1.webp',
        'https://i.nhentai.net/galleries/1005/2.jpg',
      ]);
      expect(gallery.tags['tag'], ['school uniform', 'glasses']);
      expect(gallery.tags['artist'], ['someone']);
      expect(NhentaiGallery.galleryApiUrl(server, 5),
          'https://nhentai.net/api/v2/galleries/5');
    });

    test('not a gallery', () {
      expect(NhentaiGallery.fromJson({'error': 'Not found'}), isNull);
      expect(NhentaiGallery.fromJson('nope'), isNull);
    });

    test('search tokens', () {
      expect(NhentaiGallery.searchToken('tag', 'glasses'), 'tag:glasses');
      expect(NhentaiGallery.searchToken('tag', 'school uniform'),
          'tag:"school uniform"');
    });
  });
}
