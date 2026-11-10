import 'package:boorusphere/data/dio/headers_factory.dart';
import 'package:boorusphere/domain/repository/env_repo.dart';
import 'package:dio/dio.dart';

/// Referer for an API request: the server's origin only. The request URL
/// itself can carry login data (`api_key=…`, `user_id=…` from the URL
/// suffix), and a Referer is passed on when a server redirects to another
/// host.
String refererOf(Uri uri) {
  if (!uri.hasScheme || uri.host.isEmpty) return '';
  return '${uri.scheme}://${uri.authority}/';
}

class HeadersInterceptor extends Interceptor {
  HeadersInterceptor(this.envRepo);

  final EnvRepo envRepo;

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    options.headers.addAll(
      HeadersFactory.builder()
          .setReferer(refererOf(options.uri))
          .setUserAgent(envRepo.appVersion)
          .build(),
    );
    super.onRequest(options, handler);
  }
}
