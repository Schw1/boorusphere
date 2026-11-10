import 'dart:io';

import 'package:boorusphere/utils/image_cache_cleaner.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('image_cache_test');
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  File fileAged(String name, Duration age) {
    final file = File(p.join(dir.path, name))..writeAsStringSync('x');
    file.setLastModifiedSync(DateTime.now().subtract(age));
    return file;
  }

  int clean(Duration maxAge) => removeFilesOlderThan((
    dir.path,
    DateTime.now().subtract(maxAge).millisecondsSinceEpoch,
  ));

  test('removes only files older than the limit', () {
    final old = fileAged('old', const Duration(days: 9));
    final recent = fileAged('recent', const Duration(days: 2));
    final fresh = fileAged('fresh', Duration.zero);

    expect(clean(const Duration(days: 7)), 1);
    expect(old.existsSync(), false);
    expect(recent.existsSync(), true);
    expect(fresh.existsSync(), true);
  });

  test('leaves folders alone', () {
    final sub = Directory(p.join(dir.path, 'sub'))..createSync();
    fileAged('old', const Duration(days: 30));

    expect(clean(const Duration(days: 7)), 1);
    expect(sub.existsSync(), true);
  });

  test('a missing folder is fine', () {
    dir.deleteSync(recursive: true);
    expect(clean(const Duration(days: 7)), 0);
  });
}
