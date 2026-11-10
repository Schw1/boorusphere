import 'dart:convert';
import 'dart:io';

import 'package:boorusphere/data/repository/server/entity/server.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// API tokens for servers that need one (e.g. Monbooru).
///
/// Tokens live in the platform keystore (iOS Keychain, Android Keystore), never
/// in Hive. Backups only carry them when "Include login data" is chosen (to
/// move to another device); automatic backups never do. On iOS they are bound to this device and are not
/// synced via iCloud Keychain. A copy is cached in memory because request
/// headers are built synchronously.
class ServerAuthStore {
  ServerAuthStore._();

  static const _storage = FlutterSecureStorage(
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  static final Map<String, String> _cache = {};

  static String _key(String serverId) => 'server_token:$serverId';

  /// Loads the tokens of [servers] into memory. Call once at startup.
  static Future<void> load(Iterable<Server> servers) async {
    for (final server in servers) {
      try {
        final token = await _storage.read(key: _key(server.id));
        if (token != null && token.isNotEmpty) {
          _cache[server.id] = token;
        }
      } catch (e) {
        debugPrint('ServerAuthStore.load(${server.id}): $e');
      }
    }
  }

  static String tokenOf(String serverId) => _cache[serverId] ?? '';

  static Future<void> save(String serverId, String token) async {
    final value = token.trim();
    if (value.isEmpty) {
      await remove(serverId);
      return;
    }
    await _storage.write(key: _key(serverId), value: value);
    _cache[serverId] = value;
  }

  static Future<void> remove(String serverId) async {
    _cache.remove(serverId);
    try {
      await _storage.delete(key: _key(serverId));
    } catch (e) {
      debugPrint('ServerAuthStore.remove($serverId): $e');
    }
  }

  static const backupKey = 'server_tokens';

  /// Tokens of [servers] for a backup with login data (`{serverId: token}`).
  static MapEntry<String, Object> exportBackup(Iterable<Server> servers) =>
      MapEntry(backupKey, {
        for (final server in servers)
          if (tokenOf(server.id).isNotEmpty) server.id: tokenOf(server.id),
      });

  /// Saves the tokens of a backup made with login data. Returns the ids of
  /// the servers that got a token from it.
  static Future<Set<String>> importBackup(String src) async {
    final data = jsonDecode(src);
    if (data is! Map) return const {};
    final restored = <String>{};
    for (final entry in data.entries) {
      final id = '${entry.key}';
      final token = '${entry.value ?? ''}'.trim();
      if (id.isEmpty || token.isEmpty) continue;
      try {
        await save(id, token);
        restored.add(id);
      } catch (e) {
        debugPrint('ServerAuthStore.importBackup($id): $e');
      }
    }
    return restored;
  }

  /// Ids of servers in [after] whose address points somewhere else than
  /// that of the same server in [before]. Their stored token belongs to
  /// the old address and must not be sent to the new one.
  static Set<String> movedServers(
    Iterable<Server> before,
    Iterable<Server> after,
  ) {
    final old = {for (final s in before) s.id: s};
    return {
      for (final server in after)
        if (old[server.id] case final previous?)
          if (_origin(previous.homepage) != _origin(server.homepage) ||
              _origin(previous.apiAddress) != _origin(server.apiAddress))
            server.id,
    };
  }

  /// Authorization header for a request to [url] on [server].
  ///
  /// The token is only attached when [url] points at the server's own
  /// homepage or API origin, so it never leaks to third-party hosts.
  static Map<String, String> headersFor(
    Server server,
    String url, {
    String? token,
  }) {
    final value = token ?? tokenOf(server.id);
    if (value.isEmpty || !isOwnOrigin(server, url)) return const {};
    return {'Authorization': 'Bearer $value'};
  }

  static bool isOwnOrigin(Server server, String url) {
    final target = _origin(url);
    if (target == null) return false;
    return target == _origin(server.homepage) ||
        target == _origin(server.apiAddress);
  }

  static String? _origin(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) return null;
    if (uri.scheme != 'http' && uri.scheme != 'https') return null;
    return '${uri.scheme}://${uri.host.toLowerCase()}:${uri.port}';
  }

  /// True if [url] is plain HTTP to a host outside the local network.
  static bool isInsecureRemote(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || uri.scheme != 'http') return false;
    return !isLocalHost(uri.host);
  }

  /// Names that only resolve inside a home or company network.
  static const _localSuffixes = [
    '.local',
    '.lan',
    '.home.arpa',
    '.internal',
    '.intranet',
    '.localdomain',
    '.home',
    '.fritz.box',
  ];

  /// True for addresses inside the local network: localhost, names
  /// without a dot (`nas`), names ending in one of [_localSuffixes]
  /// (`*.local`, `*.fritz.box` …), private, CGNAT (Tailscale) and
  /// link-local IPv4 addresses, and loopback, unique-local (`fc00::/7`)
  /// and link-local (`fe80::/10`) IPv6 addresses.
  static bool isLocalHost(String rawHost) {
    var host = rawHost.toLowerCase().trim();
    if (host.startsWith('[') && host.endsWith(']')) {
      host = host.substring(1, host.length - 1);
    }
    if (host.endsWith('.')) host = host.substring(0, host.length - 1);
    if (host.isEmpty) return false;
    if (host == 'localhost' || host.endsWith('.localhost')) return true;

    if (host.contains(':')) return _isLocalIpv6(host);

    final ip = host.split('.').map(int.tryParse).toList();
    if (ip.length == 4 && ip.every((x) => x != null)) {
      final a = ip[0]!, b = ip[1]!;
      if (a == 10 || a == 127) return true;
      if (a == 192 && b == 168) return true;
      if (a == 172 && b >= 16 && b <= 31) return true;
      if (a == 100 && b >= 64 && b <= 127) return true; // CGNAT / Tailscale
      if (a == 169 && b == 254) return true; // link-local
      return false;
    }

    if (!host.contains('.')) return true; // `nas`, `raspberrypi`
    return _localSuffixes.any(host.endsWith);
  }

  static bool _isLocalIpv6(String host) {
    final address = InternetAddress.tryParse(host.split('%').first);
    if (address == null || address.type != InternetAddressType.IPv6) {
      return false;
    }
    if (address.isLoopback || address.isLinkLocal) return true;
    final first = address.rawAddress.first;
    return first & 0xfe == 0xfc; // fc00::/7, unique local
  }
}
