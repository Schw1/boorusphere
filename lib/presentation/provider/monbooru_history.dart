import 'dart:convert';

import 'package:boorusphere/data/repository/booru/entity/post.dart';
import 'package:boorusphere/presentation/provider/monbooru_queue.dart';
import 'package:boorusphere/presentation/provider/monbooru_sender.dart';
import 'package:boorusphere/presentation/utils/extensions/post.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_ce/hive.dart';

/// One post sent to Monbooru: when, and what came of it so far.
class MonbooruHistoryEntry {
  const MonbooruHistoryEntry({
    required this.post,
    required this.time,
    this.jobId = 0,
    this.report,
  });

  final Post post;
  final DateTime time;

  /// monloader job, 0 if unknown.
  final int jobId;

  /// null while monloader is still working on it.
  final MonbooruSendReport? report;

  bool get isPending => report == null;

  bool get isFailed =>
      report?.error != null || report?.outcome == MonbooruOutcome.failed;

  /// Ended well: added, or already in Monbooru.
  bool get isSuccess =>
      report?.outcome == MonbooruOutcome.added ||
      report?.outcome == MonbooruOutcome.duplicate;

  /// Can be asked again for its result (still running, or no result yet).
  bool get canLookUp =>
      jobId > 0 && (report == null || (report?.unconfirmed ?? false));

  Map<String, dynamic> toJson() => {
    'post': post.toJson(),
    'time': time.millisecondsSinceEpoch,
    'jobId': jobId,
    if (report case final report?) 'report': reportToJson(report),
  };

  static MonbooruHistoryEntry? fromJson(Object? json) {
    if (json is! Map || json['post'] is! Map) return null;
    try {
      return MonbooruHistoryEntry(
        post: Post.fromJson(Map<String, dynamic>.from(json['post'])),
        time: DateTime.fromMillisecondsSinceEpoch(
          json['time'] is int ? json['time'] as int : 0,
        ),
        jobId: json['jobId'] is int ? json['jobId'] as int : 0,
        report: reportFromJson(json['report']),
      );
    } catch (_) {
      return null;
    }
  }

  static Map<String, dynamic> reportToJson(MonbooruSendReport report) => {
    if (report.outcome case final outcome?) 'outcome': outcome.name,
    if (report.error case final error?) ...{
      'error': error.kind.name,
      'detail': error.detail,
    },
    if (report.jobError.isNotEmpty) 'jobError': report.jobError,
    if (report.unconfirmed) 'unconfirmed': true,
  };

  static MonbooruSendReport? reportFromJson(Object? json) {
    if (json is! Map) return null;
    T? byName<T extends Enum>(List<T> values, Object? name) {
      for (final it in values) {
        if (it.name == name) return it;
      }
      return null;
    }

    final kind = byName(MonbooruErrorKind.values, json['error']);
    return MonbooruSendReport(
      outcome: byName(MonbooruOutcome.values, json['outcome']),
      error: kind == null
          ? null
          : MonbooruError(kind, json['detail'] is String ? json['detail'] : ''),
      jobError: json['jobError'] is String ? json['jobError'] : '',
      unconfirmed: json['unconfirmed'] == true,
    );
  }
}

/// Posts sent to Monbooru on this device, newest first, one entry per post
/// (sending again updates it). Kept in a Hive box of JSON strings.
class MonbooruHistory {
  MonbooruHistory(this._history);

  /// The store on the box opened by [openBox].
  factory MonbooruHistory.fromOpenBox() =>
      MonbooruHistory(Hive.box<String>(boxName));

  final Box<String> _history;

  /// Opens the box; call once at startup, before [fromOpenBox].
  static Future<void> openBox() => Hive.openBox<String>(boxName);

  static const boxName = 'monbooru_history';

  /// How many sends are kept.
  static const limit = 300;

  /// Changes whenever the history does, so open screens can update.
  final changes = ValueNotifier(0);

  Future<Box<String>> open() async => _history;

  bool get isEmpty => _history.isEmpty;

  static List<MonbooruHistoryEntry> _entries(Box<String> box) {
    final result = <MonbooruHistoryEntry>[];
    for (final raw in box.values) {
      try {
        final entry = MonbooruHistoryEntry.fromJson(jsonDecode(raw));
        if (entry != null) result.add(entry);
      } catch (_) {
        // a broken entry is skipped
      }
    }
    result.sort((a, b) => b.time.compareTo(a.time));
    return result;
  }

  Future<List<MonbooruHistoryEntry>> all() async => _entries(await open());

  /// Records a send of [post]. A new send ([report] null, or failed right
  /// away) starts at [now]; a result for a running send keeps its time.
  Future<void> record(
    Post post, {
    MonbooruSendReport? report,
    int jobId = 0,
    bool isResult = false,
    DateTime? now,
  }) async {
    final box = await open();
    final key = post.viewId;
    var time = now ?? DateTime.now();
    var id = jobId;
    if (isResult) {
      final raw = box.get(key);
      final old = raw == null
          ? null
          : MonbooruHistoryEntry.fromJson(jsonDecode(raw));
      if (old != null) {
        time = old.time;
        if (id <= 0) id = old.jobId;
      }
    }
    final entry = MonbooruHistoryEntry(
      post: post,
      time: time,
      jobId: id,
      report: report,
    );
    await box.put(key, jsonEncode(entry.toJson()));
    if (box.length > limit) {
      final oldest = _entries(box).skip(limit).map((it) => it.post.viewId);
      await box.deleteAll(oldest.toList());
    }
    changes.value++;
  }

  /// For [MonbooruQueue]: records and never throws (history is a bonus).
  Future<void> recordSafely(
    Post post,
    MonbooruSendReport? report,
    int jobId, {
    bool isResult = false,
  }) async {
    try {
      await record(post, report: report, jobId: jobId, isResult: isResult);
    } catch (e) {
      debugPrint('MonbooruHistory.record: $e');
    }
  }

  /// Asks monloader again for the result of sends that have none yet.
  Future<void> lookUpPending({
    Future<MonbooruJobLookup> Function(int id)? fetchJob,
  }) async {
    final fetch = fetchJob ?? MonbooruSender.fetchJob;
    for (final entry in await all()) {
      if (!entry.canLookUp) continue;
      final lookup = await fetch(entry.jobId);
      final job = lookup.job;
      if (lookup.noRead) return; // the token can't read jobs at all
      if (job == null || !job.isFinished) continue;
      await record(
        entry.post,
        report: MonbooruSendReport(outcome: job.outcome, jobError: job.error),
        jobId: entry.jobId,
        isResult: true,
      );
    }
  }

  Future<void> remove(Post post) async {
    await (await open()).delete(post.viewId);
    changes.value++;
  }

  /// Removes the entries that ended well; failed, pending and unknown
  /// ones stay.
  Future<void> removeSuccessful() async {
    final box = await open();
    final keys = [
      for (final entry in _entries(box))
        if (entry.isSuccess) entry.post.viewId,
    ];
    await box.deleteAll(keys);
    changes.value++;
  }

  Future<void> clear() async {
    await (await open()).clear();
    changes.value++;
  }
}
