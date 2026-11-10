import 'package:boorusphere/data/repository/booru/entity/post.dart';
import 'package:boorusphere/data/repository/reading_progress.dart';
import 'package:boorusphere/data/repository/server/server_pins.dart';
import 'package:boorusphere/presentation/provider/monbooru_history.dart';
import 'package:boorusphere/presentation/provider/monbooru_queue.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Riverpod access to the stores that keep their data in static classes
/// ([ReadingProgress], [MonbooruHistory], [ServerPins], [MonbooruQueue]).
///
/// The stores stay the place that reads and writes the data (like the
/// repositories of the older features). Widgets watch these providers
/// instead of the stores' notifiers, the same way as everything else in
/// the app, and tests can override them.

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
  ref.rebuildOn(ReadingProgress.changes);
  return ReadingProgress.pageOfKey(key);
});

/// The "Continue reading" list, newest first.
final continueReadingProvider = FutureProvider.autoDispose<List<Post>>((ref) {
  ref.rebuildOn(ReadingProgress.changes);
  return ReadingProgress.recent();
});

/// Posts sent to Monbooru, newest first.
final monbooruHistoryProvider =
    FutureProvider.autoDispose<List<MonbooruHistoryEntry>>((ref) {
      ref.rebuildOn(MonbooruHistory.changes);
      return MonbooruHistory.all();
    });

/// Whether anything was sent to Monbooru yet.
final monbooruHistoryIsEmptyProvider = Provider.autoDispose<bool>((ref) {
  ref.rebuildOn(MonbooruHistory.changes);
  return MonbooruHistory.isEmpty;
});

/// Ids of the servers pinned to the menu.
final serverPinsProvider = Provider.autoDispose<Set<String>>((ref) {
  ref.rebuildOn(ServerPins.pinned);
  return ServerPins.pinned.value;
});

/// Sends posts to monloader and follows their jobs; one for the whole app.
final monbooruQueueProvider = Provider<MonbooruQueue>(
  (ref) => MonbooruQueue.instance,
);

/// Where each post stands with Monbooru, by `Post.viewId`.
final monbooruStatesProvider =
    Provider.autoDispose<Map<String, MonbooruPostState>>((ref) {
      final queue = ref.watch(monbooruQueueProvider);
      ref.rebuildOn(queue.states);
      return queue.states.value;
    });
