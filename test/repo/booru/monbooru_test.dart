import 'package:boorusphere/data/repository/booru/parser/monbooru_json_parser.dart';
import 'package:boorusphere/data/repository/server/entity/server.dart';
import 'package:boorusphere/presentation/utils/extensions/post.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

const _md5 = '0123456789abcdef0123456789abcdef';

Map<String, dynamic> _image(int id, String type,
        {int? pages, bool missing = false, String md5 = _md5}) =>
    {
      'id': id,
      'sha256': 'f' * 64,
      'md5': md5,
      'file_type': type,
      'width': 800,
      'height': 600,
      'is_missing': missing,
      'page_count': pages,
      'url': 'https://example.org/post/$id',
      'tags': [
        {'name': 'general', 'category': 'rating'},
        {'name': 'some_artist', 'category': 'artist'},
        {'name': 'cat', 'category': 'general'},
      ],
    };

Response _page(List<Map<String, dynamic>> results) => Response(
      requestOptions:
          RequestOptions(path: 'http://192.168.0.10:8455/api/v1/images/search'),
      statusCode: 200,
      data: {'results': results, 'total': results.length, 'limit': 50},
    );

void main() {
  const server = Server(
    id: 'Monbooru',
    homepage: 'http://192.168.0.10:8455',
    postUrl: 'images/{post-id}',
    searchParserId: MonbooruJsonParser.parserId,
  );
  final parser = MonbooruJsonParser();

  test('recognizes a search page', () {
    expect(parser.canParsePage(_page([_image(1, 'jpeg')])), isTrue);
    expect(parser.canParsePage(_page([])), isTrue);
  });

  test('images and videos', () {
    final posts = parser.parsePage(
        server, _page([_image(1, 'jpeg'), _image(2, 'mp4')]));
    expect(posts, hasLength(2));
    final image = posts.first;
    expect(image.md5, _md5);
    expect(image.fileMd5, _md5);
    expect(image.pageCount, 0);
    expect(image.isArchive, isFalse);
    expect(image.originalFile,
        'http://192.168.0.10:8455/api/v1/images/1/file?name=$_md5.jpg');
    expect(image.tagsArtist, ['some_artist']);
    expect(image.rateValue, 's');
    expect(posts.last.content.isVideo, isTrue);
  });

  test('archives with pages', () {
    final posts = parser.parsePage(server, _page([_image(3, 'cbz', pages: 12)]));
    expect(posts, hasLength(1));
    final archive = posts.single;
    expect(archive.isArchive, isTrue);
    expect(archive.pageCount, 12);
    expect(archive.originalFile, endsWith('/api/v1/images/3/file?name=$_md5.cbz'));
    expect(archive.sampleFile,
        MonbooruJsonParser.pageUrl(server.apiAddress, 3, 1, _md5));
    expect(archive.content.isPhoto, isTrue);
  });

  test('skips archives without pages, missing files and unknown types', () {
    final posts = parser.parsePage(
      server,
      _page([
        _image(4, 'cbz'),
        _image(5, 'jpeg', missing: true),
        _image(6, 'psd'),
        _image(7, 'png'),
      ]),
    );
    expect(posts.map((it) => it.id), [7]);
  });

  test('page URLs', () {
    expect(
      MonbooruJsonParser.pageUrl('http://host:8455/', 9, 2, 'abc'),
      'http://host:8455/api/v1/images/9/page/2?name=abc-2.jpg',
    );
  });
}
