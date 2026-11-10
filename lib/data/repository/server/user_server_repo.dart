import 'dart:convert';

import 'package:boorusphere/data/repository/server/entity/server.dart';
import 'package:boorusphere/data/repository/server/url_suffix_credentials.dart';
import 'package:boorusphere/domain/repository/server_data_repo.dart';
import 'package:boorusphere/presentation/provider/data_backup/data_backup.dart';
import 'package:hive_ce/hive.dart';

class UserServerRepo implements ServerRepo {
  UserServerRepo({
    required Map<String, Server> defaultServers,
    required this.box,
  }) : _defaults = defaultServers;

  final Map<String, Server> _defaults;
  final Box<Server> box;

  @override
  List<Server> get servers => box.values.toList();

  @override
  Map<String, Server> get defaults => _defaults;

  Future<void> _migrateKeys() async {
    final mapped = Map<String, Server>.from(box.toMap());
    for (final data in mapped.entries) {
      if (data.key.startsWith('@')) {
        continue;
      }
      await box.delete(data.key);
      await box.put(data.value.key, data.value);
    }
    await box.flush();
  }

  @override
  Future<void> populate() async {
    if (_defaults.isEmpty) return;

    if (box.isEmpty) {
      await box.putAll(_defaults);
    } else {
      await _migrateKeys();
    }
  }

  @override
  Future<void> add(Server data) async {
    await box.put(
      data.key,
      data.apiAddr == data.homepage ? data.copyWith(apiAddr: '') : data,
    );
  }

  @override
  Future<Server> edit(Server from, Server to) async {
    final data = to.apiAddr == to.homepage
        ? to.copyWith(id: from.id, apiAddr: '')
        : to.copyWith(id: from.id);

    await box.put(from.key, data);
    return data;
  }

  @override
  Future<void> reset() async {
    await box.deleteAll(box.keys);
    await box.putAll(_defaults);
  }

  @override
  Future<void> remove(Server data) async {
    await box.delete(data.key);
  }

  @override
  Future<void> import(String src) async {
    final List maps = jsonDecode(src);
    final previous = {for (final s in box.values) s.id: s};
    // Read the whole backup first: the server list is only replaced once
    // there is something to replace it with.
    final servers = <Server>[];
    for (final map in maps) {
      if (map is! Map) continue;
      try {
        final server = Server.fromJson(Map<String, dynamic>.from(map));
        if (server.id.isEmpty) continue;
        servers.add(_keepCredentials(server, previous));
      } catch (_) {
        // a broken entry is skipped, the others are still restored
      }
    }
    if (servers.isEmpty) return;
    await box.clear();
    for (final server in servers) {
      await add(server);
    }
  }

  /// A backup made without credentials must not wipe the API keys of a
  /// server that is restored on the same device: if the imported URL suffix
  /// is the current one minus its credentials, the current one is kept.
  static Server _keepCredentials(Server server, Map<String, Server> previous) {
    final current = previous[server.id];
    if (current == null || current.urlSuffix == server.urlSuffix) {
      return server;
    }
    if (UrlSuffixCredentials.strip(current.urlSuffix) == server.urlSuffix) {
      return server.copyWith(urlSuffix: current.urlSuffix);
    }
    return server;
  }

  @override
  Future<BackupItem> export({bool withCredentials = true}) async {
    return BackupItem(key, [
      for (final server in box.values)
        (withCredentials
                ? server
                : server.copyWith(
                    urlSuffix: UrlSuffixCredentials.strip(server.urlSuffix),
                  ))
            .toJson(),
    ]);
  }

  static const String key = 'server';

  static Future<void> prepare() async {
    await Hive.openBox<Server>(key);
  }
}
