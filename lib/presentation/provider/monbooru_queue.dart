import 'dart:async';

import 'package:boorusphere/constant/app.dart';
import 'package:boorusphere/data/repository/booru/entity/post.dart';
import 'package:boorusphere/data/repository/booru/parser/monbooru_json_parser.dart';
import 'package:boorusphere/data/repository/server/entity/server.dart';
import 'package:boorusphere/data/repository/server/server_auth_store.dart';
import 'package:boorusphere/presentation/provider/monbooru_history.dart';
import 'package:boorusphere/presentation/provider/monbooru_sender.dart';
import 'package:boorusphere/presentation/utils/extensions/post.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// Where a post stands with Monbooru, as shown on its send button.
enum MonbooruPostStatus {
  /// Not checked, or no Monbooru server to check against.
  unknown,

  /// Found in Monbooru by its file md5.
  present,

  /// Being handed to monloader.
  sending,

  /// Accepted by monloader, waiting for the job to finish.
  queued,

  /// Job finished: the file was added (or was already there).
  done,

  /// Sending or the job failed.
  failed,
}

class MonbooruPostState {
  const MonbooruPostState(this.status, {this.outcome, this.error});

  static const unknown = MonbooruPostState(MonbooruPostStatus.unknown);

  final MonbooruPostStatus status;
  final MonbooruOutcome? outcome;
  final MonbooruError? error;

  bool get isBusy =>
      status == MonbooruPostStatus.sending ||
      status == MonbooruPostStatus.queued;

  bool get isInMonbooru =>
      status == MonbooruPostStatus.present ||
      (status == MonbooruPostStatus.done &&
          (outcome == MonbooruOutcome.added ||
              outcome == MonbooruOutcome.duplicate));
}

/// Outcome of one send, reported when its job has finished (or polling gave
/// up).
class MonbooruSendReport {
  const MonbooruSendReport({
    this.outcome,
    this.error,
    this.jobError = '',
    this.unconfirmed = false,
  });

  final MonbooruOutcome? outcome;

  /// Sending itself failed (not configured, unreachable, bad token, …).
  final MonbooruError? error;

  /// Reason given by monloader for a failed job.
  final String jobError;

  /// Queued, but the result is unknown (token without `read` scope, or the
  /// job did not finish in time).
  final bool unconfirmed;
}

/// Summary of a batch send.
class MonbooruBatchReport {
  const MonbooruBatchReport({
    this.added = 0,
    this.duplicate = 0,
    this.skipped = 0,
    this.failed = 0,
    this.unconfirmed = 0,
    this.alreadyThere = 0,
    this.error,
  });

  final int added;
  final int duplicate;
  final int skipped;
  final int failed;
  final int unconfirmed;

  /// Left out because the duplicate check found them in Monbooru.
  final int alreadyThere;

  /// First sending error, e.g. monloader not set up.
  final MonbooruError? error;
}

/// Keeps a send in the history ([MonbooruHistory]); `report` null = sent,
/// result pending.
typedef MonbooruRecorder =
    Future<void> Function(
      Post post,
      MonbooruSendReport? report,
      int jobId, {
      bool isResult,
    });

/// Sends posts to monloader, follows the jobs and checks for duplicates.
///
/// Lives for the whole app session; widgets listen to [states].
class MonbooruQueue {
  MonbooruQueue({
    Duration pollInterval = const Duration(seconds: 2),
    Duration pollTimeout = const Duration(minutes: 3),
    Future<MonbooruSendResult> Function(Post post)? sender,
    Future<MonbooruJobLookup> Function(int id)? jobFetcher,
    String Function(String serverId)? tokenOf,
    Dio? client,
    MonbooruRecorder? recorder,
  }) : _pollInterval = pollInterval,
       _record = recorder ?? MonbooruHistory.recordSafely,
       _tokenOf = tokenOf ?? ServerAuthStore.tokenOf,
       _pollTimeout = pollTimeout,
       _send = sender ?? MonbooruSender.send,
       _fetchJob = jobFetcher ?? MonbooruSender.fetchJob,
       _client = client;

  static final instance = MonbooruQueue();

  final Duration _pollInterval;
  final Duration _pollTimeout;
  final Future<MonbooruSendResult> Function(Post post) _send;
  final Future<MonbooruJobLookup> Function(int id) _fetchJob;
  final String Function(String serverId) _tokenOf;
  final MonbooruRecorder _record;
  Dio? _client;

  /// Per post ([Post.viewId]).
  final states = ValueNotifier<Map<String, MonbooruPostState>>(const {});

  /// md5 -> found in Monbooru. Only positive results are kept for good;
  /// misses are re-checked after a while because they may be added later.
  final Map<String, bool> _present = {};
  final Map<String, DateTime> _missCheckedAt = {};
  final Map<String, Future<bool?>> _checking = {};

  static const _missTtl = Duration(minutes: 10);

  MonbooruPostState stateOf(Post post) =>
      states.value[post.viewId] ?? MonbooruPostState.unknown;

  void _set(Post post, MonbooruPostState state) {
    states.value = {...states.value, post.viewId: state};
  }

  /// The Monbooru server the duplicate check runs against: the first
  /// Monbooru server that has a token.
  Server? lookupServer(Iterable<Server> servers) {
    for (final server in servers) {
      if (MonbooruJsonParser.isMonbooru(server) &&
          _tokenOf(server.id).isNotEmpty) {
        return server;
      }
    }
    return null;
  }

  /// `gallery=<name>` from the server's URL suffix, if any.
  static String? galleryOf(Server server) {
    final suffix = server.urlSuffix.trim();
    if (suffix.isEmpty) return null;
    final query = suffix.replaceFirst(RegExp(r'^[?&]+'), '');
    try {
      final gallery = Uri.splitQueryString(query)['gallery'];
      return gallery == null || gallery.isEmpty ? null : gallery;
    } catch (_) {
      return null;
    }
  }

  /// Whether [post] is already in Monbooru: true/false, or null when it
  /// can't be told (no Monbooru server, no md5, request failed).
  Future<bool?> check(Post post, Iterable<Server> servers) async {
    final md5 = post.fileMd5;
    if (md5.isEmpty) return null;
    if (_present[md5] ?? false) {
      _markPresent(post);
      return true;
    }
    final missAt = _missCheckedAt[md5];
    if (missAt != null && DateTime.now().difference(missAt) < _missTtl) {
      return false;
    }
    final server = lookupServer(servers);
    if (server == null) return null;

    final found = await (_checking[md5] ??= _query(server, md5));
    unawaited(_checking.remove(md5));
    if (found ?? false) {
      _present[md5] = true;
      _markPresent(post);
    } else if (found == false) {
      _missCheckedAt[md5] = DateTime.now();
    }
    return found;
  }

  void _markPresent(Post post) {
    final current = stateOf(post);
    if (current.status == MonbooruPostStatus.unknown) {
      _set(post, const MonbooruPostState(MonbooruPostStatus.present));
    }
  }

  Future<bool?> _query(Server server, String md5) async {
    final api = server.apiAddress.replaceFirst(RegExp(r'/+$'), '');
    final gallery = galleryOf(server);
    final url = '$api/api/v1/images/search';
    try {
      final res =
          await (_client ??= Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 15),
              validateStatus: (_) => true,
            ),
          )).get(
            url,
            queryParameters: {'q': 'md5:$md5', 'limit': 1, 'gallery': ?gallery},
            options: Options(
              headers: {
                'Accept': 'application/json',
                // The app strips Dart's default User-Agent; some proxies in front
                // of Monbooru reject requests without one.
                'User-Agent': 'Boorusphere/${displayVersion('dev')}',
                ...ServerAuthStore.headersFor(
                  server,
                  url,
                  token: _tokenOf(server.id),
                ),
              },
            ),
          );
      final data = res.data;
      if (res.statusCode != 200 || data is! Map) return null;
      final total = data['total'];
      final results = data['results'];
      if (total is int) return total > 0;
      return results is List && results.isNotEmpty;
    } catch (e) {
      debugPrint('MonbooruQueue._query: $e');
      return null;
    }
  }

  /// Sends one post. [onReport] is called once the job has finished or the
  /// app stopped waiting for it.
  Future<MonbooruError?> send(
    Post post, {
    void Function(MonbooruSendReport report)? onReport,
  }) async {
    _set(post, const MonbooruPostState(MonbooruPostStatus.sending));
    final result = await _send(post);
    final error = result.error;
    if (error != null) {
      _set(post, MonbooruPostState(MonbooruPostStatus.failed, error: error));
      final report = MonbooruSendReport(error: error);
      unawaited(_record(post, report, 0));
      onReport?.call(report);
      return error;
    }
    _set(post, const MonbooruPostState(MonbooruPostStatus.queued));
    final jobId = result.jobId ?? 0;
    unawaited(_record(post, null, jobId));
    unawaited(
      _follow(post, jobId).then((report) {
        unawaited(_record(post, report, jobId, isResult: true));
        onReport?.call(report);
      }),
    );
    return null;
  }

  Future<MonbooruSendReport> _follow(Post post, int jobId) async {
    if (jobId <= 0) {
      _set(post, const MonbooruPostState(MonbooruPostStatus.done));
      return const MonbooruSendReport(unconfirmed: true);
    }
    final deadline = DateTime.now().add(_pollTimeout);
    var errors = 0;
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(_pollInterval);
      final lookup = await _fetchJob(jobId);
      if (lookup.noRead) {
        _set(post, const MonbooruPostState(MonbooruPostStatus.done));
        return const MonbooruSendReport(unconfirmed: true);
      }
      final job = lookup.job;
      if (job == null) {
        // A few failed polls in a row: stop asking.
        if (++errors >= 5) break;
        continue;
      }
      errors = 0;
      if (!job.isFinished) continue;

      final outcome = job.outcome;
      if (outcome == MonbooruOutcome.added ||
          outcome == MonbooruOutcome.duplicate) {
        final md5 = post.fileMd5;
        if (md5.isNotEmpty) _present[md5] = true;
      }
      _set(
        post,
        MonbooruPostState(
          outcome == MonbooruOutcome.failed
              ? MonbooruPostStatus.failed
              : MonbooruPostStatus.done,
          outcome: outcome,
        ),
      );
      return MonbooruSendReport(outcome: outcome, jobError: job.error);
    }
    _set(post, const MonbooruPostState(MonbooruPostStatus.done));
    return const MonbooruSendReport(unconfirmed: true);
  }

  /// Sends [posts], leaving out those the duplicate check finds in
  /// Monbooru. [onProgress] gets the number of posts handed over so far.
  Future<MonbooruBatchReport> sendAll(
    List<Post> posts,
    Iterable<Server> servers, {
    void Function(int sent, int total)? onProgress,
  }) async {
    final toSend = <Post>[];
    var alreadyThere = 0;
    for (final post in posts) {
      if (stateOf(post).isInMonbooru || stateOf(post).isBusy) {
        alreadyThere++;
        continue;
      }
      if (await check(post, servers) ?? false) {
        alreadyThere++;
      } else {
        toSend.add(post);
      }
    }

    final reports = <Future<MonbooruSendReport>>[];
    MonbooruError? firstError;
    var sent = 0;
    for (final post in toSend) {
      final completer = Completer<MonbooruSendReport>();
      reports.add(completer.future);
      final error = await send(post, onReport: completer.complete);
      firstError ??= error;
      onProgress?.call(++sent, toSend.length);
      // monloader not set up or unreachable: the rest would fail the same.
      if (error != null &&
          error.kind != MonbooruErrorKind.noUrl &&
          error.kind != MonbooruErrorKind.http) {
        break;
      }
    }

    final done = await Future.wait(reports);
    int count(bool Function(MonbooruSendReport r) test) =>
        done.where(test).length;
    return MonbooruBatchReport(
      added: count((r) => r.outcome == MonbooruOutcome.added),
      duplicate: count((r) => r.outcome == MonbooruOutcome.duplicate),
      skipped: count((r) => r.outcome == MonbooruOutcome.skipped),
      failed:
          count((r) => r.error != null || r.outcome == MonbooruOutcome.failed) +
          (toSend.length - done.length),
      unconfirmed: count((r) => r.unconfirmed),
      alreadyThere: alreadyThere,
      error: firstError,
    );
  }
}
