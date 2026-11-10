import 'dart:convert';
import 'dart:io';

import 'package:boorusphere/data/repository/booru/entity/post.dart';
import 'package:boorusphere/data/repository/reading_backup.dart';
import 'package:boorusphere/data/repository/reading_progress.dart';
import 'package:boorusphere/data/repository/saved_search.dart';
import 'package:boorusphere/presentation/provider/monbooru_history.dart';
import 'package:boorusphere/presentation/provider/monbooru_queue.dart';
import 'package:boorusphere/presentation/provider/monbooru_sender.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

const _post = Post(id: 3, serverId: 'Danbooru', postUrl: 'https://x/3');

void main() {
  late MonbooruHistory history;
  late ReadingProgress progress;
  late SavedSearchStore searches;

  setUpAll(() async {
    Hive.init(Directory.systemTemp.createTempSync('history').path);
    await MonbooruHistory.openBox();
    await ReadingProgress.openBoxes();
    await SavedSearchStore.openBox();
    history = MonbooruHistory.fromOpenBox();
    progress = ReadingProgress.fromOpenBoxes();
    searches = SavedSearchStore.fromOpenBox();
  });

  group('MonbooruHistory', () {
    setUp(() => history.clear());

    test('report JSON round trip', () {
      const reports = [
        MonbooruSendReport(outcome: MonbooruOutcome.added),
        MonbooruSendReport(
          outcome: MonbooruOutcome.failed,
          jobError: 'gallery-dl: 404',
        ),
        MonbooruSendReport(error: MonbooruError(MonbooruErrorKind.http, '500')),
        MonbooruSendReport(unconfirmed: true),
      ];
      for (final report in reports) {
        final back = MonbooruHistoryEntry.reportFromJson(
          jsonDecode(jsonEncode(MonbooruHistoryEntry.reportToJson(report))),
        )!;
        expect(back.outcome, report.outcome);
        expect(back.error?.kind, report.error?.kind);
        expect(back.error?.detail, report.error?.detail);
        expect(back.jobError, report.jobError);
        expect(back.unconfirmed, report.unconfirmed);
      }
      expect(MonbooruHistoryEntry.reportFromJson(null), isNull);
    });

    test('a result keeps the time of the send', () async {
      await history.record(_post, jobId: 9, now: DateTime(2026, 11, 9, 10));
      var entries = await history.all();
      expect(entries.single.isPending, isTrue);
      expect(entries.single.canLookUp, isTrue);

      await history.record(
        _post,
        report: const MonbooruSendReport(outcome: MonbooruOutcome.added),
        isResult: true,
        now: DateTime(2026, 11, 9, 11),
      );
      entries = await history.all();
      expect(entries, hasLength(1));
      expect(entries.single.time, DateTime(2026, 11, 9, 10));
      expect(entries.single.jobId, 9);
      expect(entries.single.report?.outcome, MonbooruOutcome.added);
      expect(entries.single.canLookUp, isFalse);
    });

    test('failed sends, newest first, limit', () async {
      for (var i = 0; i < MonbooruHistory.limit + 3; i++) {
        await history.record(
          Post(id: i, serverId: 's'),
          report: const MonbooruSendReport(
            error: MonbooruError(MonbooruErrorKind.unreachable),
          ),
          now: DateTime(2026).add(Duration(minutes: i)),
        );
      }
      final entries = await history.all();
      expect(entries, hasLength(MonbooruHistory.limit));
      expect(entries.first.post.id, MonbooruHistory.limit + 2);
      expect(entries.first.isFailed, isTrue);
      expect(entries.any((it) => it.post.id < 3), isFalse);
    });

    test('pending sends are looked up again', () async {
      await history.record(_post, jobId: 9);
      await history.record(const Post(id: 4, serverId: 'Danbooru'));
      final asked = <int>[];
      await history.lookUpPending(
        fetchJob: (id) async {
          asked.add(id);
          return const MonbooruJobLookup.found(
            MonbooruJob(id: 9, status: 'succeeded', duplicate: 1),
          );
        },
      );
      expect(asked, [9], reason: 'no job id, nothing to ask');
      final entry = (await history.all()).firstWhere(
        (it) => it.post.id == _post.id,
      );
      expect(entry.report?.outcome, MonbooruOutcome.duplicate);
    });

    test('remove successful ones, keep failed and pending', () async {
      Future<void> add(int id, MonbooruSendReport? report) => history.record(
        Post(id: id, serverId: 's'),
        report: report,
      );
      await add(1, const MonbooruSendReport(outcome: MonbooruOutcome.added));
      await add(
        2,
        const MonbooruSendReport(outcome: MonbooruOutcome.duplicate),
      );
      await add(3, const MonbooruSendReport(outcome: MonbooruOutcome.failed));
      await add(
        4,
        const MonbooruSendReport(
          error: MonbooruError(MonbooruErrorKind.http, '400'),
        ),
      );
      await add(5, null);
      await add(6, const MonbooruSendReport(unconfirmed: true));
      await history.removeSuccessful();
      expect((await history.all()).map((it) => it.post.id).toSet(), {
        3,
        4,
        5,
        6,
      });
    });

    test('remove', () async {
      await history.record(_post);
      await history.remove(_post);
      expect(await history.all(), isEmpty);
    });
  });

  group('ReadingBackup', () {
    test('round trip, merging with what is there', () async {
      const a = Post(id: 1, serverId: 'nhentai.net', pageCount: 20, title: 'A');
      const b = Post(id: 2, serverId: 'Monbooru', pageCount: 5);
      await progress.save(a, 7, now: DateTime(2026, 11, 1));
      await progress.save(b, 2, now: DateTime(2026, 11, 2));
      await searches.put(
        const SavedSearch(
          serverId: 'Danbooru',
          query: 'cat',
          seenId: 50,
          createdAt: 1,
        ),
      );

      final entry = await ReadingBackup.export(progress, searches);
      expect(entry.key, 'reading');
      final json = jsonEncode(entry.value);

      // another device: b read further, a and the search unknown
      await progress.forgetAll();
      await progress.clear(a);
      await progress.save(b, 4, now: DateTime(2026, 11, 5));
      await searches.remove(searches.all().single);

      await ReadingBackup.import(json, progress, searches);
      expect(await progress.pageOf(a), 7);
      expect(await progress.pageOf(b), 4, reason: 'further page kept');
      expect((await progress.recent()).map((it) => it.id), containsAll([1, 2]));
      final search = searches.all().single;
      expect(search.query, 'cat');
      expect(search.seenId, 50);

      // broken data does nothing
      await ReadingBackup.import('not json', progress, searches);
      await ReadingBackup.import('[]', progress, searches);
    });
  });
}
