import 'package:boorusphere/data/repository/booru/entity/post.dart';
import 'package:boorusphere/data/repository/booru/utils/file_md5.dart';
import 'package:boorusphere/presentation/utils/extensions/post.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const md5 = '1dc55dfd8c000ae54b0411d59c39d057';

  group('FileMd5.normalize', () {
    test('valid', () {
      expect(FileMd5.normalize(md5), md5);
      expect(FileMd5.normalize(' ${md5.toUpperCase()} '), md5);
    });
    test('invalid', () {
      expect(FileMd5.normalize(null), '');
      expect(FileMd5.normalize(123), '');
      expect(FileMd5.normalize('abc'), '');
      expect(FileMd5.normalize('${md5}00'), '');
    });
  });

  group('FileMd5.fromUrl', () {
    test('danbooru style file name', () {
      expect(
          FileMd5.fromUrl('https://cdn.donmai.us/original/1d/c5/$md5.jpg'),
          md5);
    });
    test('gelbooru with query', () {
      expect(
          FileMd5.fromUrl(
              'https://img3.gelbooru.com/images/1d/c5/$md5.png?1234'),
          md5);
    });
    test('moebooru path segment', () {
      expect(
          FileMd5.fromUrl(
              'https://files.yande.re/image/$md5/yande.re%20123%20tag.jpg'),
          md5);
    });
    test('prefixed file name', () {
      expect(FileMd5.fromUrl('https://example.org/files/sample_$md5.jpg'),
          md5);
    });
    test('none', () {
      expect(FileMd5.fromUrl('https://example.org/images/12345.jpg'), '');
      expect(FileMd5.fromUrl('https://example.org/${md5}ff.jpg'), '');
      expect(FileMd5.fromUrl(''), '');
    });
  });

  group('Post.fileMd5', () {
    test('prefers the md5 from the booru', () {
      const post = Post(
          md5: md5,
          originalFile:
              'https://example.org/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.jpg');
      expect(post.fileMd5, md5);
    });
    test('falls back to the URL', () {
      const post = Post(originalFile: 'https://example.org/x/$md5.webm');
      expect(post.fileMd5, md5);
    });
  });
}
