import 'package:boorusphere/data/dio/headers_interceptor.dart';
import 'package:boorusphere/presentation/utils/open_url.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('refererOf', () {
    test('is the origin, without the path or login data of the request', () {
      final uri = Uri.parse(
        'https://booru.example.org/index.php?page=dapi&q=index&api_key=SECRET&user_id=42',
      );
      expect(refererOf(uri), 'https://booru.example.org/');
      expect(refererOf(uri), isNot(contains('SECRET')));
    });

    test('keeps a port', () {
      expect(
        refererOf(Uri.parse('http://192.168.1.5:8455/api/v1/tags?q=a')),
        'http://192.168.1.5:8455/',
      );
    });

    test('is empty without a host', () {
      expect(refererOf(Uri.parse('/relative/path')), '');
    });
  });

  group('webUriOf', () {
    test('accepts http and https', () {
      expect(webUriOf('https://www.pixiv.net/artworks/1'), isNotNull);
      expect(webUriOf(' http://example.org/a.png '), isNotNull);
    });

    test('rejects other schemes', () {
      expect(webUriOf('tel:+4912345'), isNull);
      expect(webUriOf('javascript:alert(1)'), isNull);
      expect(webUriOf('otherapp://open?x=1'), isNull);
      expect(webUriOf('file:///etc/passwd'), isNull);
    });

    test('rejects free text and empty sources', () {
      expect(webUriOf('Pixiv 12345'), isNull);
      expect(webUriOf('artist twitter'), isNull);
      expect(webUriOf(''), isNull);
      expect(webUriOf('https://'), isNull);
    });
  });
}
