import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:boorusphere/data/repository/booru/entity/post.dart';
import 'package:boorusphere/data/repository/booru/parser/monbooru_json_parser.dart';
import 'package:boorusphere/data/repository/server/entity/server.dart';
import 'package:boorusphere/presentation/provider/monbooru_queue.dart';
import 'package:boorusphere/presentation/provider/monbooru_sender.dart';
import 'package:boorusphere/presentation/widgets/timeline/post_selection.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

const _md5a = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _md5b = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

Post _post(int id, {String md5 = ''}) => Post(
      id: id,
      serverId: 'Danbooru',
      md5: md5,
      postUrl: 'https://danbooru.donmai.us/posts/$id',
      originalFile: 'https://cdn.donmai.us/original/$id.jpg',
    );

const _monbooru = Server(
  id: 'Monbooru',
  homepage: 'http://192.168.0.10:8455',
  searchParserId: MonbooruJsonParser.parserId,
);

/// Answers Monbooru md5 searches: `total` 1 for md5s in [present].
class _SearchAdapter implements HttpClientAdapter {
  _SearchAdapter(this.present);

  final Set<String> present;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options);
    final q = options.uri.queryParameters['q'] ?? '';
    final hit = present.contains(q.replaceFirst('md5:', ''));
    return ResponseBody.fromString(
      jsonEncode({'results': hit ? [{'id': 1}] : [], 'total': hit ? 1 : 0}),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

MonbooruJob _job(String status, {int created = 0, int duplicate = 0}) =>
    MonbooruJob.fromJson({
      'id': 7,
      'status': status,
      'summary': {'created': created, 'duplicate': duplicate, 'failed': 0},
    });

void main() {
  group('MonbooruJob', () {
    test('outcomes', () {
      expect(_job('succeeded', created: 1).outcome, MonbooruOutcome.added);
      expect(
          _job('succeeded', duplicate: 1).outcome, MonbooruOutcome.duplicate);
      expect(_job('failed').outcome, MonbooruOutcome.failed);
      expect(_job('succeeded').outcome, MonbooruOutcome.skipped);
      expect(_job('queued').isFinished, isFalse);
      expect(_job('running').isFinished, isFalse);
      expect(_job('partial', created: 1).isFinished, isTrue);
    });

    test('error from items', () {
      final job = MonbooruJob.fromJson({
        'id': 1,
        'status': 'failed',
        'summary': {'failed': 1},
        'items': [
          {'status': 'failed', 'error': 'HTTP 404'},
        ],
      });
      expect(job.error, 'HTTP 404');
    });
  });

  group('MonbooruSender helpers', () {
    test('job id', () {
      expect(MonbooruSender.jobIdOf({'job_id': 12}), 12);
      expect(MonbooruSender.jobIdOf('{"job_id": 13}'), 13);
      expect(MonbooruSender.jobIdOf({'id': 14, 'status': 'succeeded'}), 14);
      expect(MonbooruSender.jobIdOf('nope'), isNull);
    });

    test('error codes', () {
      expect(MonbooruSender.errorOf(401).kind, MonbooruErrorKind.invalidToken);
      expect(MonbooruSender.errorOf(403).kind, MonbooruErrorKind.noWriteScope);
      expect(MonbooruSender.errorOf(409).kind, MonbooruErrorKind.unavailable);
      expect(MonbooruSender.errorOf(500).kind, MonbooruErrorKind.http);
    });
  });

  group('MonbooruQueue', () {
    MonbooruQueue queue({
      Future<MonbooruSendResult> Function(Post)? sender,
      Future<MonbooruJobLookup> Function(int)? jobs,
      Set<String> present = const {},
      _SearchAdapter? adapter,
    }) {
      final dio = Dio()..httpClientAdapter = adapter ?? _SearchAdapter(present);
      return MonbooruQueue(
        pollInterval: const Duration(milliseconds: 1),
        pollTimeout: const Duration(seconds: 2),
        sender: sender ?? (_) async => const MonbooruSendResult.queued(7),
        jobFetcher: jobs ??
            (_) async =>
                MonbooruJobLookup.found(_job('succeeded', created: 1)),
        tokenOf: (id) => id == _monbooru.id ? 'secret' : '',
        client: dio,
      );
    }

    test('gallery from URL suffix', () {
      expect(MonbooruQueue.galleryOf(_monbooru), isNull);
      expect(
          MonbooruQueue.galleryOf(
              _monbooru.copyWith(urlSuffix: '&gallery=cats&x=1')),
          'cats');
      expect(MonbooruQueue.galleryOf(_monbooru.copyWith(urlSuffix: '?gallery=')),
          isNull);
    });

    test('lookup server needs a Monbooru server with token', () {
      final q = queue();
      expect(q.lookupServer([]), isNull);
      expect(q.lookupServer([_monbooru.copyWith(id: 'other')]), isNull);
      expect(q.lookupServer([_monbooru]), _monbooru);
    });

    test('duplicate check by md5', () async {
      final adapter = _SearchAdapter({_md5a});
      final q = queue(adapter: adapter);
      expect(await q.check(_post(1, md5: _md5a), [_monbooru]), isTrue);
      expect(q.stateOf(_post(1, md5: _md5a)).isInMonbooru, isTrue);
      expect(await q.check(_post(2, md5: _md5b), [_monbooru]), isFalse);
      // No md5 / no server: unknown
      expect(await q.check(_post(3), [_monbooru]), isNull);
      expect(await q.check(_post(4, md5: _md5b), []), isFalse,
          reason: 'recent miss is cached');

      final first = adapter.requests.first;
      expect(first.uri.queryParameters['q'], 'md5:$_md5a');
      expect(first.headers['Authorization'], 'Bearer secret');
      expect(first.uri.path, '/api/v1/images/search');

      // Cached hit: no new request
      final count = adapter.requests.length;
      expect(await q.check(_post(5, md5: _md5a), [_monbooru]), isTrue);
      expect(adapter.requests.length, count);
    });

    test('send follows the job until it is done', () async {
      var polls = 0;
      final q = queue(jobs: (_) async {
        polls++;
        return MonbooruJobLookup.found(polls < 3
            ? _job('running')
            : _job('succeeded', created: 1));
      });
      final post = _post(1, md5: _md5a);
      final report = Completer<MonbooruSendReport>();
      final error = await q.send(post, onReport: report.complete);
      expect(error, isNull);
      expect(q.stateOf(post).status, MonbooruPostStatus.queued);

      final result = await report.future;
      expect(result.outcome, MonbooruOutcome.added);
      expect(polls, 3);
      expect(q.stateOf(post).status, MonbooruPostStatus.done);
      expect(q.stateOf(post).isInMonbooru, isTrue);
      // Now known to be in Monbooru without asking
      expect(await q.check(_post(9, md5: _md5a), [_monbooru]), isTrue);
    });

    test('token without read scope', () async {
      final q = queue(jobs: (_) async => const MonbooruJobLookup.noReadScope());
      final report = Completer<MonbooruSendReport>();
      await q.send(_post(1), onReport: report.complete);
      expect((await report.future).unconfirmed, isTrue);
    });

    test('failed send', () async {
      final q = queue(
        sender: (_) async => const MonbooruSendResult.failed(
            MonbooruError(MonbooruErrorKind.invalidToken)),
      );
      final error = await q.send(_post(1));
      expect(error?.kind, MonbooruErrorKind.invalidToken);
      expect(q.stateOf(_post(1)).status, MonbooruPostStatus.failed);
    });

    test('batch skips posts already in Monbooru', () async {
      final sent = <int>[];
      final q = queue(
        present: {_md5a},
        sender: (post) async {
          sent.add(post.id);
          return const MonbooruSendResult.queued(7);
        },
      );
      final report = await q.sendAll(
        [_post(1, md5: _md5a), _post(2, md5: _md5b), _post(3)],
        [_monbooru],
      );
      expect(sent, [2, 3]);
      expect(report.alreadyThere, 1);
      expect(report.added, 2);
      expect(report.failed, 0);
    });

    test('batch stops when monloader is not set up', () async {
      final q = queue(
        sender: (_) async => const MonbooruSendResult.failed(
            MonbooruError(MonbooruErrorKind.notConfigured)),
      );
      final report = await q.sendAll([_post(1), _post(2), _post(3)], []);
      expect(report.error?.kind, MonbooruErrorKind.notConfigured);
      expect(report.failed, 3);
    });
  });

  group('PostSelection', () {
    test('toggle, select all, clear', () {
      final selection = PostSelection();
      var notified = 0;
      selection.addListener(() => notified++);
      selection.toggle(_post(1));
      expect(selection.isActive, isTrue);
      selection.toggle(_post(1));
      expect(selection.isActive, isFalse);
      selection.selectAll([_post(1), _post(2), Post.appReserved]);
      expect(selection.length, 2);
      expect(selection.contains(_post(2)), isTrue);
      selection.clear();
      expect(selection.length, 0);
      expect(notified, 4);
    });
  });
}
