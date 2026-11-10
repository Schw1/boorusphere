import 'dart:convert';

import 'package:boorusphere/data/dio/app_dio.dart';
import 'package:boorusphere/data/repository/server/entity/server.dart';
import 'package:boorusphere/domain/provider.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'provider.g.dart';

@Riverpod(keepAlive: true)
CookieJar cookieJar(Ref ref) {
  return CookieJar();
}

/// The cookie jar, kept in [path] (see `AppStorage`).
CookieJar provideCookieJar(String path) {
  return PersistCookieJar(storage: FileStorage(path));
}

@Riverpod(keepAlive: true)
Map<String, Server> defaultServers(Ref ref) {
  return {};
}

Future<Map<String, Server>> provideDefaultServers() async {
  final json = await rootBundle.loadString('assets/servers.json');
  final servers = jsonDecode(json) as List;
  return Map.fromEntries(
    servers.map((it) {
      final value = Server.fromJson(it);
      return MapEntry(value.key, value);
    }),
  );
}

@riverpod
Dio dio(Ref ref) {
  final cookieJar = ref.watch(cookieJarProvider);
  final envRepo = ref.watch(envRepoProvider);
  return AppDio(cookieJar: cookieJar, envRepo: envRepo);
}
