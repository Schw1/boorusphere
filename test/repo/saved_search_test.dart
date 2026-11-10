import 'dart:io';

import 'package:boorusphere/data/repository/saved_search.dart';
import 'package:boorusphere/presentation/screens/post/post_archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

void main() {
  final now = DateTime(2026, 11, 8);
  const search = SavedSearch(serverId: 'Danbooru', query: 'cat_ears  solo ');

  group('SavedSearch', () {
    test('first check only remembers where it stands', () {
      final first = search.checked([105, 104, 100], now: now);
      expect(first.seenId, 105);
      expect(first.latestId, 105);
      expect(first.newCount, 0);
      expect(first.checkedAt, now.millisecondsSinceEpoch);
    });

    test('counts posts newer than the last seen one', () {
      final first = search.checked([105, 104, 100], now: now);
      final next = first.checked([110, 108, 105, 104], now: now);
      expect(next.newCount, 2);
      expect(next.more, isFalse);
      expect(next.latestId, 110);
      expect(next.seenId, 105);
    });

    test('blocked posts are not counted', () {
      final first = search.checked([100], now: now);
      final next = first.checked(
        [103, 102, 101],
        shownIds: [103, 101],
        now: now,
      );
      expect(next.newCount, 2);
    });

    test('a whole new full page means maybe more', () {
      final first = search.checked([100], now: now);
      final ids = [for (var i = 200; i > 200 - SavedSearch.fullPage; i--) i];
      expect(first.checked(ids, now: now).more, isTrue);
      // a short page that is all new is just that many
      expect(first.checked([102, 101], now: now).more, isFalse);
    });

    test('opening marks everything seen', () {
      final checked = search.checked([100], now: now).checked([
        120,
        110,
      ], now: now);
      final seen = checked.seen();
      expect(seen.seenId, 120);
      expect(seen.newCount, 0);
      // posts loaded when opening can be newer than the last check
      expect(checked.seen([125, 120]).seenId, 125);
      expect(seen.checked([121, 120], now: now).newCount, 1);
    });

    test('an order: tag puts other posts first: no count', () {
      expect(search.canCount, isTrue);
      expect(
        const SavedSearch(serverId: 's', query: 'cat order:score').canCount,
        isFalse,
      );
      expect(
        const SavedSearch(serverId: 's', query: 'sort:popular').canCount,
        isFalse,
      );
    });

    test('same search, other spacing: same key', () {
      expect(search.key, SavedSearch.keyOf('Danbooru', 'cat_ears solo'));
      expect(search.key, isNot(SavedSearch.keyOf('Gelbooru', 'cat_ears solo')));
    });

    test('JSON round trip, broken data is none', () {
      final checked = search.checked([100], now: now);
      final back = SavedSearch.fromJson(checked.toJson())!;
      expect(back.key, checked.key);
      expect(back.seenId, 100);
      expect(back.query, 'cat_ears solo');
      expect(SavedSearch.fromJson({'query': 1}), isNull);
      expect(SavedSearch.fromJson('x'), isNull);
    });
  });

  group('SavedSearchStore', () {
    setUpAll(() {
      Hive.init(Directory.systemTemp.createTempSync('saved').path);
    });

    test('saves in order, replaces, removes', () async {
      await SavedSearchStore.open();
      const a = SavedSearch(serverId: 's', query: 'a', createdAt: 1);
      const b = SavedSearch(serverId: 's', query: 'b', createdAt: 2);
      await SavedSearchStore.put(b);
      await SavedSearchStore.put(a);
      expect(SavedSearchStore.all().map((it) => it.query), ['a', 'b']);
      await SavedSearchStore.put(a.copyWith(newCount: 3));
      expect(SavedSearchStore.all().first.newCount, 3);
      expect(SavedSearchStore.all(), hasLength(2));
      await SavedSearchStore.remove(a);
      expect(SavedSearchStore.all().map((it) => it.query), ['b']);
    });
  });

  group('reader preloading', () {
    test('next pages, then the previous one', () {
      expect(ArchiveReaderPage.preloadRange(0, 10), [1, 2, 3]);
      expect(ArchiveReaderPage.preloadRange(5, 10), [6, 7, 8, 4]);
      expect(ArchiveReaderPage.preloadRange(8, 10), [9, 7]);
      expect(ArchiveReaderPage.preloadRange(9, 10), [8]);
      expect(ArchiveReaderPage.preloadRange(0, 1), isEmpty);
    });
  });
}
