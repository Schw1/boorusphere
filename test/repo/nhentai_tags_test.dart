import 'dart:convert';
import 'dart:io';

import 'package:boorusphere/data/repository/booru/entity/post.dart';
import 'package:boorusphere/data/repository/booru/nhentai_tags.dart';
import 'package:boorusphere/data/repository/reading_progress.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

// Same format as tool/nhentai_tags.py writes (made-up tags).
final _list = jsonEncode({
  'version': 1,
  'updated': '2026-11-08T00:00:00Z',
  'types': ['parody', 'character', 'tag', 'artist', 'group', 'language', 'category'],
  'tags': [
    [12227, 'english', 150000, 5],
    [2937, 'big hat', 240000, 2],
    [8378, 'glasses', 80000, 2],
    [100, 'bigfoot', 50, 2],
    [8847, 'someone big', 68, 3],
    [33172, 'doujinshi', 500000, 6],
    ['bad', 'row', 1, 2],
  ],
});

void main() {
  group('NhentaiTags', () {
    late NhentaiTags tags;
    setUp(() {
      tags = NhentaiTags()..loadJson(_list);
    });

    test('loads the list', () {
      expect(tags.length, 6);
      expect(tags.byId(8378)?.name, 'glasses');
      expect(tags.byId(8378)?.type, 'tag');
    });

    test('tokens for tag ids', () {
      expect(tags.tokensOf([2937, 12227, 999]),
          ['tag:"big hat"', 'language:english']);
    });

    test('suggestions: prefix first, then contains, by count', () {
      final names = tags.suggest('big').map((it) => it.$1).toList();
      expect(names, ['tag:"big hat"', 'tag:bigfoot', 'artist:"someone big"']);
    });

    test('suggestions with type and minus', () {
      expect(tags.suggest('artist:som').map((it) => it.$1),
          ['artist:"someone big"']);
      expect(tags.suggest('-tag:gla').single, ('-tag:glasses', 80000));
      expect(tags.suggest('language:').map((it) => it.$1),
          ['language:english']);
    });

    test('empty word: most used', () {
      expect(tags.suggest('', limit: 2).map((it) => it.$1),
          ['category:doujinshi', 'tag:"big hat"']);
    });

    test('rejects other files', () {
      expect(() => NhentaiTags().loadJson('{"result": []}'),
          throwsFormatException);
      expect(NhentaiTags().suggest('big'), isEmpty);
    });
  });

  group('ReadingProgress', () {
    setUpAll(() {
      Hive.init(Directory.systemTemp.createTempSync('progress').path);
    });

    test('saves and reads the last page', () async {
      const post = Post(id: 7, serverId: 'nhentai.net', pageCount: 20);
      expect(await ReadingProgress.pageOf(post), isNull);
      final before = ReadingProgress.changes.value;
      await ReadingProgress.save(post, 4);
      expect(await ReadingProgress.pageOf(post), 4);
      expect(ReadingProgress.pageOfSync(post), 4);
      expect(ReadingProgress.changes.value, greaterThan(before));
      // other server, same id: separate
      expect(
          await ReadingProgress.pageOf(post.copyWith(serverId: 'Monbooru')),
          isNull);
      await ReadingProgress.clear(post);
      expect(await ReadingProgress.pageOf(post), isNull);
    });
  });
}
