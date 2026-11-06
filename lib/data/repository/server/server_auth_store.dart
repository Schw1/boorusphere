import 'package:boorusphere/data/repository/server/entity/server.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// API tokens for servers that need one (e.g. Monbooru).
///
/// Tokens live in the platform keystore (iOS Keychain), never in Hive, so they
/// are not part of backups. On iOS they are bound to this device and are not
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

  /// Authorization header for a request to [url] on [server].
  ///
  /// The token is only attached when [url] points at the server's own
  /// homepage or API origin, so it never leaks to third-party hosts.
  static Map<String, String> headersFor(Server server, String url,
      {String? token}) {
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
    final host = uri.host.toLowerCase();
    if (host == 'localhost' || host.endsWith('.local')) return false;
    final ip = host.split('.').map(int.tryParse).toList();
    if (ip.length == 4 && ip.every((x) => x != null)) {
      final a = ip[0]!, b = ip[1]!;
      if (a == 10 || a == 127) return false;
      if (a == 192 && b == 168) return false;
      if (a == 172 && b >= 16 && b <= 31) return false;
      if (a == 100 && b >= 64 && b <= 127) return false; // CGNAT / Tailscale
    }
    return true;
  }
}
