/// File md5 of a booru post, used to find it in Monbooru.
class FileMd5 {
  const FileMd5._();

  static final _hex32 = RegExp(r'^[0-9a-f]{32}$');
  static final _inUrl = RegExp(r'(?:^|[/_.-])([0-9a-fA-F]{32})(?=$|[/_.?#-])');

  /// Lowercase md5 if [value] is one, otherwise ''.
  static String normalize(Object? value) {
    final s = (value is String ? value : '').trim().toLowerCase();
    return _hex32.hasMatch(s) ? s : '';
  }

  /// Most boorus name files after their md5 (`…/ab/cd/<md5>.jpg`,
  /// `…/image/<md5>/…`). Returns the md5 found in the URL's path, or ''.
  static String fromUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return '';
    final path = uri.path;
    final matches = _inUrl.allMatches(path).toList();
    if (matches.isEmpty) return '';
    // The file name is the most specific place; prefer the last match.
    return matches.last.group(1)!.toLowerCase();
  }
}
