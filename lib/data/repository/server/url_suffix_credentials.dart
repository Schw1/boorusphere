/// Credentials that boorus accept as query parameters in a server's URL
/// suffix, e.g. `&api_key=…&user_id=…` (Gelbooru) or `&login=…&api_key=…`
/// (Danbooru).
abstract final class UrlSuffixCredentials {
  static const _names = {
    'api_key',
    'apikey',
    'key',
    'user_id',
    'userid',
    'login',
    'user',
    'username',
    'password',
    'password_hash',
    'pass_hash',
    'passwd',
    'pwd',
    'token',
    'access_token',
    'auth',
    'auth_token',
    'session',
    'sessionid',
    'sid',
    'secret',
  };

  static bool isCredential(String name) {
    final n = name.trim().toLowerCase();
    return _names.contains(n) ||
        n.contains('key') ||
        n.contains('token') ||
        n.contains('pass') ||
        n.contains('secret');
  }

  static String _nameOf(String param) {
    final raw = param.split('=').first;
    try {
      return Uri.decodeQueryComponent(raw);
    } catch (_) {
      return raw; // malformed percent encoding
    }
  }

  /// True if [suffix] contains at least one credential parameter.
  static bool contains(String suffix) => strip(suffix) != suffix;

  /// Removes credential parameters from [suffix] and keeps everything else,
  /// e.g. `&tags=-video&api_key=x` becomes `&tags=-video`.
  static String strip(String suffix) {
    if (suffix.isEmpty) return suffix;
    var prefix = '';
    var body = suffix;
    if (body.startsWith('?')) {
      prefix = '?';
      body = body.substring(1);
    }
    final parts = body.split('&');
    final kept = [
      for (final part in parts)
        if (part.isEmpty || !isCredential(_nameOf(part))) part,
    ];
    if (kept.length == parts.length) return suffix;
    final result = kept.join('&');
    if (result.replaceAll('&', '').isEmpty) return '';
    return '$prefix$result';
  }
}
