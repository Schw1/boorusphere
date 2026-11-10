import 'dart:typed_data';

import 'package:boorusphere/data/dio/app_dio.dart';
import 'package:dio/dio.dart';
import 'package:dio_smart_retry/dio_smart_retry.dart';
import 'package:flutter_test/flutter_test.dart';

DioException _status(int code) {
  final options = RequestOptions(path: 'https://booru.example.org/index.php');
  return DioException(
    requestOptions: options,
    response: Response(requestOptions: options, statusCode: code),
    type: DioExceptionType.badResponse,
  );
}

/// Answers with [statuses] in turn, then 200.
class _Server implements HttpClientAdapter {
  _Server(this.statuses);

  final List<int> statuses;
  int requests = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final status = requests < statuses.length ? statuses[requests] : 200;
    requests++;
    return ResponseBody.fromString(
      '[]',
      status,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  group('which failures are retried', () {
    test('a 403 is retried a few times, then given up', () async {
      for (var attempt = 1; attempt <= AppDio.forbiddenRetries; attempt++) {
        expect(await AppDio.shouldRetry(_status(403), attempt), isTrue);
      }
      expect(
        await AppDio.shouldRetry(_status(403), AppDio.forbiddenRetries + 1),
        isFalse,
      );
    });

    test('server errors and rate limits are retried as before', () async {
      expect(await AppDio.shouldRetry(_status(429), 1), isTrue);
      expect(await AppDio.shouldRetry(_status(503), 4), isTrue);
    });

    test('other client errors are not retried', () async {
      expect(await AppDio.shouldRetry(_status(401), 1), isFalse);
      expect(await AppDio.shouldRetry(_status(404), 1), isFalse);
    });

    test('a cancelled request is not retried', () async {
      final error = DioException(
        requestOptions: RequestOptions(),
        type: DioExceptionType.cancel,
      );
      expect(await AppDio.shouldRetry(error, 1), isFalse);
    });
  });

  test('pauses grow between retries', () {
    for (var i = 1; i < AppDio.retryDelays.length; i++) {
      expect(AppDio.retryDelays[i] >= AppDio.retryDelays[i - 1], isTrue);
    }
  });

  test('a page that is refused once loads on the retry', () async {
    // The same setup as AppDio, without its fixed pauses.
    final dio = Dio(BaseOptions(validateStatus: (it) => it == 200));
    final server = _Server([403, 403]);
    dio.httpClientAdapter = server;
    dio.interceptors.add(
      RetryInterceptor(
        dio: dio,
        retries: 5,
        retryDelays: const [],
        retryEvaluator: AppDio.shouldRetry,
      ),
    );
    final res = await dio.get<Object?>('https://booru.example.org/page');
    expect(res.statusCode, 200);
    expect(server.requests, 3);
  });

  test('a 403 that stays shows after the retries', () async {
    final dio = Dio(BaseOptions(validateStatus: (it) => it == 200));
    final server = _Server(List.filled(10, 403));
    dio.httpClientAdapter = server;
    dio.interceptors.add(
      RetryInterceptor(
        dio: dio,
        retries: 5,
        retryDelays: const [],
        retryEvaluator: AppDio.shouldRetry,
      ),
    );
    await expectLater(
      dio.get<Object?>('https://booru.example.org/page'),
      throwsA(
        isA<DioException>().having(
          (it) => it.response?.statusCode,
          'status',
          403,
        ),
      ),
    );
    expect(server.requests, 1 + AppDio.forbiddenRetries);
  });
}
