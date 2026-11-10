import 'dart:io';

import 'package:boorusphere/data/repository/booru/entity/post.dart';
import 'package:boorusphere/data/repository/reading_progress.dart';
import 'package:boorusphere/data/repository/server/server_pins.dart';
import 'package:boorusphere/presentation/provider/monbooru_history.dart';
import 'package:boorusphere/presentation/provider/monbooru_queue.dart';
import 'package:boorusphere/presentation/provider/monbooru_sender.dart';
import 'package:boorusphere/presentation/provider/stores.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

const _a = Post(id: 1, serverId: 'Mine', pageCount: 20);
const _b = Post(id: 2, serverId: 'Mine', pageCount: 10);

/// The providers have to follow the stores: a widget that watches one is
/// rebuilt when the store's data changes.
void main() {
  late ProviderContainer ref;
  late ReadingProgress progress;
  late MonbooruHistory history;
  late ServerPins pins;

  setUpAll(() async {
    Hive.init(Directory.systemTemp.createTempSync('stores').path);
    await ReadingProgress.openBoxes();
    await MonbooruHistory.openBox();
    await ServerPins.openBox();
  });

  setUp(() {
    // the providers create the stores on the open boxes
    ref = ProviderContainer();
    progress = ref.read(readingProgressStoreProvider);
    history = ref.read(monbooruHistoryStoreProvider);
    pins = ref.read(serverPinsStoreProvider);
  });
  tearDown(() => ref.dispose());

  test('the page read follows the reader', () async {
    final key = ReadingProgress.keyOf(_a);
    final seen = <int?>[];
    ref.listen(
      readingPageProvider(key),
      (_, next) => seen.add(next),
      fireImmediately: true,
    );
    expect(seen, [null]);

    await progress.save(_a, 4);
    await ref.pump();
    expect(ref.read(readingPageProvider(key)), 4);

    await progress.save(_a, 5);
    await ref.pump();
    expect(seen, [null, 4, 5]);
  });

  test('the continue reading list follows the reader', () async {
    ref.listen(continueReadingProvider, (_, _) {});
    await progress.forgetAll();
    expect(await ref.read(continueReadingProvider.future), isEmpty);

    await progress.save(_a, 1, now: DateTime(2026, 1, 1));
    await progress.save(_b, 1, now: DateTime(2026, 1, 2));
    final list = await ref.read(continueReadingProvider.future);
    expect(list.map((it) => it.id), [2, 1]);
  });

  test('pins follow the store', () async {
    ref.listen(serverPinsProvider, (_, _) {});
    expect(ref.read(serverPinsProvider), isEmpty);

    await pins.toggle('Mine');
    expect(ref.read(serverPinsProvider), {'Mine'});

    await pins.toggle('Mine');
    expect(ref.read(serverPinsProvider), isEmpty);
  });

  test('the Monbooru history follows the store', () async {
    ref.listen(monbooruHistoryProvider, (_, _) {});
    ref.listen(monbooruHistoryIsEmptyProvider, (_, _) {});
    await history.clear();
    expect(ref.read(monbooruHistoryIsEmptyProvider), true);

    await history.record(
      _a,
      report: const MonbooruSendReport(outcome: MonbooruOutcome.added),
    );
    expect(ref.read(monbooruHistoryIsEmptyProvider), false);
    final list = await ref.read(monbooruHistoryProvider.future);
    expect(list.single.post.id, 1);
  });

  test('post states follow the queue, which tests can replace', () async {
    final queue = MonbooruQueue(
      sender: (_) async => const MonbooruSendResult.failed(
        MonbooruError(MonbooruErrorKind.notConfigured),
      ),
      recorder: (_, _, _, {isResult = false}) async {},
    );
    final scoped = ProviderContainer(
      overrides: [monbooruQueueProvider.overrideWithValue(queue)],
    );
    addTearDown(scoped.dispose);
    scoped.listen(monbooruStatesProvider, (_, _) {});
    expect(scoped.read(monbooruStatesProvider), isEmpty);

    await queue.send(_a);
    expect(
      scoped.read(monbooruStatesProvider)['1-Mine']?.status,
      MonbooruPostStatus.failed,
    );
  });
}
