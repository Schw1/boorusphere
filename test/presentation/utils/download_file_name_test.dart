import 'package:boorusphere/presentation/provider/download/downloader.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  String name(String url, {int id = 7}) => downloadFileName(url, postId: id);

  test('booru names stay as they are', () {
    expect(
      name('https://cdn.donmai.us/original/c7/ff/c7ff714745ed5f12f73a.jpg'),
      'c7ff714745ed5f12f73a.jpg',
    );
    expect(
      name('https://example.org/images/1234 - artist (series).png'),
      '1234 - artist (series).png',
    );
  });

  test('encoded names are decoded, letters of any script kept', () {
    expect(
      name('https://example.org/%E3%81%95%E3%81%8F%E3%82%89.jpg'),
      'さくら.jpg',
    );
    expect(
      name('https://example.org/caf%C3%A9%20au%20lait.webm'),
      'café au lait.webm',
    );
  });

  test('characters paths can not take become _', () {
    expect(name('https://example.org/a%3Ab%3Fc%2Fd.png'), 'a_b_c_d.png');
    expect(name('https://example.org/x%25%25y.gif'), 'x_y.gif');
  });

  test('a stray % does not stop the download', () {
    expect(name('https://example.org/100%25off.jpg'), '100_off.jpg');
    expect(name('https://example.org/50%.jpg'), '50_.jpg');
  });

  test('a name with nothing readable left gets the post id', () {
    expect(
      name('https://example.org/%E2%98%85%E2%98%85.jpg', id: 4242),
      '4242.jpg',
    );
    expect(name('https://example.org/___.png', id: 9), '9.png');
  });

  test('Monbooru names from ?name= are used', () {
    expect(
      name('https://booru.example.org/api/v1/images/5/file?name=pic%201.png'),
      'pic 1.png',
    );
  });

  test('very long names are shortened, the extension kept', () {
    final long = 'a' * 300;
    final result = name('https://example.org/$long.jpg');
    expect(result, '${'a' * 60}.jpg');
  });

  test('the update APK keeps its name', () {
    expect(
      name(
        'https://github.com/x/y/releases/download/v1/boorusphere-arm64-v8a.apk',
      ),
      'boorusphere-arm64-v8a.apk',
    );
  });
}
