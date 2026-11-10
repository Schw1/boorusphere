import 'dart:async';

import 'package:boorusphere/data/dio/headers_interceptor.dart';
import 'package:boorusphere/domain/repository/env_repo.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:dio_smart_retry/dio_smart_retry.dart';
import 'package:flutter/foundation.dart';

class AppDio with DioMixin implements Dio {
  AppDio({required CookieJar cookieJar, required EnvRepo envRepo}) {
    options = BaseOptions();
    httpClientAdapter = IOHttpClientAdapter();

    interceptors
      ..add(CookieManager(cookieJar))
      ..add(HeadersInterceptor(envRepo))
      ..add(
        RetryInterceptor(
          dio: this,
          retries: retryDelays.length,
          retryDelays: retryDelays,
          retryEvaluator: shouldRetry,
        ),
      );
  }

  /// Pauses before the 1st, 2nd, … retry. Growing, so a server that limits
  /// how often it may be asked has time to let the next request through.
  static const retryDelays = [
    Duration(milliseconds: 500),
    Duration(seconds: 1),
    Duration(seconds: 2),
    Duration(seconds: 3),
    Duration(seconds: 3),
  ];

  /// How often a 403 is retried.
  static const forbiddenRetries = 3;

  static final _default = DefaultRetryEvaluator(defaultRetryableStatuses);

  /// Whether a failed request is sent again ([attempt] counts from 1).
  ///
  /// Besides what dio_smart_retry retries (timeouts, 429, 5xx …), a 403 is
  /// retried [forbiddenRetries] times. Some boorus behind Cloudflare, such
  /// as rule34.xxx, answer a quick series of requests (scrolling loads the
  /// next page) with a 403 that is gone a moment later; until now that
  /// needed a tap on Retry. A 403 that stays (no access, missing API key)
  /// shows after those retries, about 3.5 seconds later.
  @visibleForTesting
  static FutureOr<bool> shouldRetry(DioException error, int attempt) {
    if (error.type == DioExceptionType.badResponse &&
        error.response?.statusCode == 403) {
      return attempt <= forbiddenRetries;
    }
    return _default.evaluate(error, attempt);
  }
}
