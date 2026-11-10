import 'package:boorusphere/data/repository/booru/entity/post.dart';
import 'package:boorusphere/data/repository/reading_progress.dart';
import 'package:boorusphere/data/repository/saved_search.dart';
import 'package:boorusphere/data/repository/server/server_pins.dart';
import 'package:boorusphere/presentation/provider/monbooru_history.dart';
import 'package:boorusphere/presentation/provider/monbooru_queue.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// The stores of the newer features ([ReadingProgress], [SavedSearchStore],
/// [MonbooruHistory], [ServerPins]) and the [MonbooruQueue], and what
/// widgets watch of them.
///
/// Like the repositories of the older features, each store is one object
/// on its Hive box, created here; tests override these providers. The
/// boxes are opened in `main` before the app starts.

final readingProgressStoreProvider = Provider<ReadingProgress>(
  (ref) => ReadingProgress.fromOpenBoxes(),
);

final savedSearchStoreProvider = Provider<SavedSearchStore>(
  (ref) => SavedSearchStore.fromOpenBox(),
);

final monbooruHistoryStoreProvider = Provider<MonbooruHistory>(
  (ref) => MonbooruHistory.fromOpenBox(),
);

final serverPinsStoreProvider = Provider<ServerPins>(
  (ref) => ServerPins.fromOpenBox(),
);

extension _RebuildOn on Ref {
  /// Rebuilds this provider whenever [listenable] reports a change.
  void rebuildOn(Listenable listenable) {
    listenable.addListener(invalidateSelf);
    onDispose(() => listenable.removeListener(invalidateSelf));
  }
}

/// Last page read (0-based) of the post with [ReadingProgress.keyOf], or
/// null if it was never opened.
final readingPageProvider = Provider.autoDispose.family<int?, String>((
  ref,
  key,
) {
  final store = ref.watch(readingProgressStoreProvider);
  ref.rebuildOn(store.changes);
  return store.pageOfKey(key);
});

/// The "Continue reading" list, newest first.
final continueReadingProvider = FutureProvider.autoDispose<List<Post>>((ref) {
  final store = ref.watch(readingProgressStoreProvider);
  ref.rebuildOn(store.changes);
  return store.recent();
});

/// Posts sent to Monbooru, newest first.
final monbooruHistoryProvider =
    FutureProvider.autoDispose<List<MonbooruHistoryEntry>>((ref) {
      final store = ref.watch(monbooruHistoryStoreProvider);
      ref.rebuildOn(store.changes);
      return store.all();
    });

/// Whether anything was sent to Monbooru yet.
final monbooruHistoryIsEmptyProvider = Provider.autoDispose<bool>((ref) {
  final store = ref.watch(monbooruHistoryStoreProvider);
  ref.rebuildOn(store.changes);
  return store.isEmpty;
});

/// Ids of the servers pinned to the menu.
final serverPinsProvider = Provider.autoDispose<Set<String>>((ref) {
  final store = ref.watch(serverPinsStoreProvider);
  ref.rebuildOn(store.pinned);
  return store.pinned.value;
});

/// Sends posts to monloader and follows their jobs; one for the whole app.
final monbooruQueueProvider = Provider<MonbooruQueue>(
  (ref) => MonbooruQueue(
    recorder: ref.watch(monbooruHistoryStoreProvider).recordSafely,
  ),
);

/// Where each post stands with Monbooru, by `Post.viewId`.
final monbooruStatesProvider =
    Provider.autoDispose<Map<String, MonbooruPostState>>((ref) {
      final queue = ref.watch(monbooruQueueProvider);
      ref.rebuildOn(queue.states);
      return queue.states.value;
    });
