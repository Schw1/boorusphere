import 'package:boorusphere/data/repository/server/url_suffix_credentials.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('UrlSuffixCredentials.strip', () {
    test('empty', () {
      expect(UrlSuffixCredentials.strip(''), '');
    });

    test('only credentials', () {
      expect(UrlSuffixCredentials.strip('&api_key=abc&user_id=123'), '');
      expect(UrlSuffixCredentials.strip('&login=me&api_key=abc'), '');
      expect(UrlSuffixCredentials.strip('?key=abc'), '');
      expect(UrlSuffixCredentials.strip('&password_hash=x'), '');
    });

    test('keeps other parameters', () {
      expect(UrlSuffixCredentials.strip('&tags=-video&api_key=abc'),
          '&tags=-video');
      expect(UrlSuffixCredentials.strip('?gallery=cats&key=abc'),
          '?gallery=cats');
      expect(UrlSuffixCredentials.strip('&API_KEY=abc&json=1'), '&json=1');
    });

    test('unchanged without credentials', () {
      expect(UrlSuffixCredentials.strip('&json=1'), '&json=1');
      expect(UrlSuffixCredentials.strip('?gallery=cats'), '?gallery=cats');
      expect(UrlSuffixCredentials.contains('&json=1'), isFalse);
    });

    test('contains', () {
      expect(UrlSuffixCredentials.contains('&json=1&api_key=x'), isTrue);
    });

    test('malformed percent encoding', () {
      expect(UrlSuffixCredentials.strip('&a%zz=1&token=x'), '&a%zz=1');
    });
  });
}
