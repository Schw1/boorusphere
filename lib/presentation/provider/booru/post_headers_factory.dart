import 'dart:io';

import 'package:boorusphere/data/dio/headers_factory.dart';
import 'package:boorusphere/data/repository/booru/entity/post.dart';
import 'package:boorusphere/data/repository/server/entity/server.dart';
import 'package:boorusphere/data/repository/server/server_auth_store.dart';
import 'package:boorusphere/domain/provider.dart';
import 'package:boorusphere/presentation/provider/server_data_state.dart';
import 'package:boorusphere/presentation/utils/extensions/post.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'post_headers_factory.g.dart';

String createReferer(String url) {
  final uri = Uri.parse(url);
  final path = uri.path.replaceAll(RegExp('/+'), '/');
  return uri.replace(path: uri.hasAbsolutePath ? path : '/').toString();
}

@riverpod
Map<String, String> postHeadersFactory(
  PostHeadersFactoryRef ref,
  Post post, {
  List<Cookie> cookies = const [],
}) {
  final versionRepo = ref.watch(versionRepoProvider);
  final url = post.postUrl.isEmpty ? post.content.url : post.postUrl;
  final referer = createReferer(url);

  final headers = HeadersFactory.builder()
      .setCookies(cookies)
      .setReferer(referer)
      .setUserAgent(versionRepo.current)
      .build();

  // Servers with an API token (e.g. Monbooru) also need it for media.
  final server = ref
      .watch(serverStateProvider)
      .cast<Server?>()
      .firstWhere((it) => it?.id == post.serverId, orElse: () => null);
  if (server != null) {
    headers.addAll(ServerAuthStore.headersFor(server, post.content.url));
  }
  return headers;
}
