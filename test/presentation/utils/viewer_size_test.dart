import 'package:boorusphere/data/repository/booru/entity/post.dart';
import 'package:boorusphere/presentation/utils/extensions/post.dart';
import 'package:flutter_test/flutter_test.dart';

const _post = Post(
  id: 1,
  originalFile: 'https://x/original.png',
  sampleFile: 'https://x/sample.jpg',
  width: 12000,
  height: 8000,
  sampleWidth: 850,
  sampleHeight: 567,
);

void main() {
  test('the viewer shows the sample unless the original is asked for', () {
    expect(_post.viewerUrl(loadOriginal: false), _post.sampleFile);
    expect(_post.viewerUrl(loadOriginal: true), _post.originalFile);
  });

  test('archives always show their cover, never the .cbz', () {
    final archive = _post.copyWith(
      originalFile: 'https://x/book.cbz',
      sampleFile: 'https://x/cover.webp',
      pageCount: 30,
    );
    expect(archive.viewerUrl(loadOriginal: true), 'https://x/cover.webp');
  });

  test('a huge original is scaled to the limit, keeping its shape', () {
    final size = _post.viewerDecodeSize(_post.originalFile)!;
    expect(size.width, maxViewerSide);
    expect(size.height, 2731);
  });

  test('portrait originals are limited by their height', () {
    final tall = _post.copyWith(width: 3000, height: 20000);
    final size = tall.viewerDecodeSize(tall.originalFile)!;
    expect(size.height, maxViewerSide);
    expect(size.width, 614);
  });

  test('pictures within the limit and unknown sizes are left alone', () {
    expect(_post.viewerDecodeSize(_post.sampleFile), isNull);
    expect(
      _post
          .copyWith(width: 4096, height: 3000)
          .viewerDecodeSize(_post.originalFile),
      isNull,
    );
    expect(
      _post
          .copyWith(width: -1, height: -1)
          .viewerDecodeSize(_post.originalFile),
      isNull,
    );
    expect(_post.viewerDecodeSize('https://x/other.png'), isNull);
  });
}
