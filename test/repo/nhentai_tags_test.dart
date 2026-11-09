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
    [9000, 'glasses', 10, 1],
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
      expect(tags.length, 7);
      expect(tags.byId(8378)?.name, 'glasses');
      expect(tags.byId(8378)?.type, 'tag');
    });

    test('tokens for tag ids', () {
      // as typed in the app, and as nhentai writes them (old blocked tags)
      expect(tags.tokensOf([2937, 12227, 999]),
          ['big_hat', 'tag:"big hat"', 'english', 'language:english']);
      expect(tags.tokensOf([9000]), ['character:glasses']);
    });

    test('suggestions: prefix first, then contains, by count', () {
      final names = tags.suggest('big').map((it) => it.$1).toList();
      expect(names, ['big_hat', 'bigfoot', 'someone_big']);
      expect(tags.suggest('big_h').single.$1, 'big_hat');
      // same name as a tag: with its type
      expect(tags.suggest('glass').map((it) => it.$1),
          ['glasses', 'character:glasses']);
    });

    test('suggestions with type and minus', () {
      expect(tags.suggest('artist:som').map((it) => it.$1),
          ['artist:someone_big']);
      expect(tags.suggest('-tag:gla').single, ('-tag:glasses', 80000));
      expect(tags.suggest('language:').map((it) => it.$1),
          ['language:english']);
    });

    test('empty word: most used', () {
      expect(tags.suggest('', limit: 2).map((it) => it.$1),
          ['doujinshi', 'big_hat']);
    });

    test('words typed in the app become nhentai tokens', () {
      expect(tags.toQuery('big_hat'), 'tag:"big hat"');
      expect(tags.toQuery('-glasses'), '-tag:glasses');
      expect(tags.toQuery('english'), 'language:english');
      expect(tags.toQuery('someone_big'), 'artist:"someone big"');
      expect(tags.toQuery('character:glasses'), 'character:glasses');
      expect(tags.toQuery('artist:someone_big'), 'artist:"someone big"');
      // unknown names with a type are still quoted for nhentai
      expect(tags.toQuery('artist:new_guy'), 'artist:"new guy"');
      // already nhentai's form, quoted, other filters, title words: as is
      expect(tags.toQuery('tag:"big hat"'), 'tag:"big hat"');
      expect(tags.toQuery('"big hat"'), '"big hat"');
      expect(tags.toQuery('pages:>0'), 'pages:>0');
      expect(tags.toQuery('summer'), 'summer');
    });

    test('how gallery tags are shown and searched', () {
      expect(tags.displayOf('tag', 'big hat'), 'big_hat');
      expect(tags.displayOf('tag', 'glasses'), 'glasses');
      expect(tags.displayOf('character', 'glasses'), 'character:glasses');
      expect(tags.displayOf('tag', 'not listed'), 'tag:not_listed');
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

    test('continue reading: newest first, forget, clear', () async {
      await ReadingProgress.forgetAll();
      const a = Post(id: 1, serverId: 'nhentai.net', pageCount: 10, title: 'A');
      const b = Post(id: 2, serverId: 'Monbooru', pageCount: 3);
      await ReadingProgress.save(a, 0, now: DateTime(2026, 11, 1));
      await ReadingProgress.save(b, 2, now: DateTime(2026, 11, 2));
      expect((await ReadingProgress.recent()).map((it) => it.id), [2, 1]);
      // reading again moves it up, with the post as stored
      await ReadingProgress.save(a, 5, now: DateTime(2026, 11, 3));
      final recent = await ReadingProgress.recent();
      expect(recent.map((it) => it.id), [1, 2]);
      expect(recent.first.title, 'A');
      expect(ReadingProgress.isFinished(b), isTrue);
      expect(ReadingProgress.isFinished(a), isFalse);

      await ReadingProgress.forget(b);
      expect((await ReadingProgress.recent()).map((it) => it.id), [1]);
      expect(await ReadingProgress.pageOf(b), 2, reason: 'page stays');

      // several at once (selection), pages stay
      await ReadingProgress.save(b, 2, now: DateTime(2026, 11, 4));
      await ReadingProgress.forgetAll([a, b]);
      expect(await ReadingProgress.recent(), isEmpty);
      expect(await ReadingProgress.pageOf(a), 5);
      await ReadingProgress.save(a, 5, now: DateTime(2026, 11, 5));

      await ReadingProgress.clear(a);
      expect(await ReadingProgress.recent(), isEmpty);
      expect(await ReadingProgress.pageOf(a), isNull);
    });

    test('continue reading keeps the newest ${ReadingProgress.recentLimit}',
        () async {
      await ReadingProgress.forgetAll();
      final start = DateTime(2026, 1, 1);
      for (var i = 0; i < ReadingProgress.recentLimit + 5; i++) {
        await ReadingProgress.save(
            Post(id: 1000 + i, serverId: 's', pageCount: 2), 0,
            now: start.add(Duration(minutes: i)));
      }
      final recent = await ReadingProgress.recent();
      expect(recent, hasLength(ReadingProgress.recentLimit));
      expect(recent.first.id, 1000 + ReadingProgress.recentLimit + 4);
      expect(recent.any((it) => it.id < 1005), isFalse);
      await ReadingProgress.forgetAll();
    });
  });
}
