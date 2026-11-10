import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// One nhentai tag.
class NhentaiTag {
  const NhentaiTag(this.id, this.name, this.count, this.type);

  final int id;
  final String name;
  final int count;

  /// parody, character, tag, artist, group, language or category.
  final String type;

  /// Search token for the tag as nhentai wants it, e.g. `tag:"big breasts"`.
  String get token => name.contains(' ') ? '$type:"$name"' : '$type:$name';
}

/// A parsed tag list with its lookup tables.
typedef NhentaiTagList = ({
  List<NhentaiTag> tags,
  Map<int, NhentaiTag> byId,
  Map<String, NhentaiTag> byName,
  Map<String, NhentaiTag> byTypeName,
});

/// Parses the list format written by tool/nhentai_tags.py and builds the
/// lookup tables; throws on anything else.
///
/// A top-level function, so it can run in a background isolate: the list
/// is a few MB of JSON, and parsing it on the UI isolate made the first
/// search stutter.
NhentaiTagList parseNhentaiTagList(String source) {
  final data = jsonDecode(source);
  if (data is! Map || data['tags'] is! List || data['types'] is! List) {
    throw const FormatException('not an nhentai tag list');
  }
  final types = [for (final t in data['types'] as List) '$t'];
  final tags = <NhentaiTag>[];
  for (final row in data['tags'] as List) {
    if (row is! List || row.length < 4) continue;
    final id = row[0], name = row[1], count = row[2], type = row[3];
    if (id is! int || name is! String || type is! int) continue;
    if (type < 0 || type >= types.length) continue;
    tags.add(NhentaiTag(id, name, count is int ? count : 0, types[type]));
  }
  if (tags.isEmpty) throw const FormatException('empty tag list');
  tags.sort((a, b) => b.count.compareTo(a.count));
  int rank(String type) {
    final i = nhentaiTagTypes.indexOf(type);
    return i < 0 ? nhentaiTagTypes.length : i;
  }

  final byName = <String, NhentaiTag>{};
  for (final tag in tags) {
    final other = byName[tag.name];
    if (other == null || rank(tag.type) < rank(other.type)) {
      byName[tag.name] = tag;
    }
  }
  return (
    tags: tags,
    byId: {for (final tag in tags) tag.id: tag},
    byName: byName,
    byTypeName: {for (final tag in tags) '${tag.type}\n${tag.name}': tag},
  );
}

/// Reads and parses the stored copy at [path] (for a background isolate).
NhentaiTagList _readTagList(String path) =>
    parseNhentaiTagList(File(path).readAsStringSync());

/// nhentai's tag types, in the order a bare name is looked up in when it
/// exists in several (e.g. a tag and a character of the same name).
const nhentaiTagTypes = [
  'tag',
  'parody',
  'character',
  'artist',
  'group',
  'language',
  'category',
];

/// nhentai's tag list (id, name, count, type), for tag suggestions and for
/// naming the tag ids of search results.
///
/// nhentai has no autocomplete API, so the list is built weekly by the
/// "nhentai tag list" workflow (tool/nhentai_tags.py) on this repository's
/// `data` branch. The app keeps a copy and refreshes it once a week.
class NhentaiTags {
  NhentaiTags({this.directory});

  static final instance = NhentaiTags();

  static const url =
      'https://raw.githubusercontent.com/Schw1/boorusphere-ios/data/nhentai-tags.json';
  static const maxAge = Duration(days: 7);
  static const _fileName = 'nhentai-tags.json';

  /// Where the copy is kept; the app support folder if null.
  final Directory? directory;

  List<NhentaiTag> _tags = const [];
  Map<int, NhentaiTag> _byId = const {};

  /// name -> tag, the first type in [nhentaiTagTypes] wins
  Map<String, NhentaiTag> _byName = const {};

  /// `type\nname` -> tag
  Map<String, NhentaiTag> _byTypeName = const {};
  Future<void>? _loading;

  bool get isLoaded => _tags.isNotEmpty;
  int get length => _tags.length;

  /// Loads the stored copy and downloads a new one if it is missing or
  /// older than [maxAge]. Safe to call often; only the first call works.
  Future<void> ensureLoaded(Dio client) =>
      _loading ??= _load(client).whenComplete(() {
        // allow another try after a failed download
        if (!isLoaded) _loading = null;
      });

  Future<File> _file() async {
    final dir = directory ?? await getApplicationSupportDirectory();
    return File(p.join(dir.path, _fileName));
  }

  Future<void> _load(Dio client) async {
    final file = await _file();
    var stale = true;
    if (await file.exists()) {
      try {
        _apply(await compute(_readTagList, file.path));
        final age = DateTime.now().difference(await file.lastModified());
        stale = age > maxAge;
      } catch (e) {
        debugPrint('NhentaiTags: stored list unreadable: $e');
      }
    }
    if (!stale) return;
    try {
      final res = await client.get<String>(
        url,
        options: Options(
          responseType: ResponseType.plain,
          validateStatus: (it) => it == 200,
        ),
      );
      final body = res.data ?? '';
      _apply(await compute(parseNhentaiTagList, body));
      await file.parent.create(recursive: true);
      await file.writeAsString(body);
    } catch (e) {
      // Keep using the stored copy, if any.
      debugPrint('NhentaiTags: download failed: $e');
    }
  }

  /// Reads the list format written by tool/nhentai_tags.py. Throws on
  /// anything else. The app itself parses in a background isolate (see
  /// [_load]); this is the same parser, run right here.
  @visibleForTesting
  void loadJson(String source) => _apply(parseNhentaiTagList(source));

  void _apply(NhentaiTagList list) {
    _tags = list.tags;
    _byId = list.byId;
    _byName = list.byName;
    _byTypeName = list.byTypeName;
  }

  NhentaiTag? byId(int id) => _byId[id];

  /// Tags of the tag ids of a search result (unknown ids skipped), as typed
  /// in the app (`big_breasts`) and as nhentai writes them
  /// (`tag:"big breasts"`), so blocked tags of either form match.
  List<String> tokensOf(Iterable<int> ids) => [
    for (final id in ids)
      if (_byId[id] case final tag?) ...{display(tag), tag.token},
  ];

  static String underscored(String name) => name.replaceAll(' ', '_');

  /// How a tag is typed in the app: its name with underscores, like on
  /// Danbooru (`big_breasts`). With its type in front (`artist:some_one`)
  /// when the bare name means another tag, or the list isn't loaded.
  String displayOf(String type, String name) {
    final bare = _byName[name];
    return bare != null && bare.type == type
        ? underscored(name)
        : '$type:${underscored(name)}';
  }

  String display(NhentaiTag tag) => displayOf(tag.type, tag.name);

  NhentaiTag? _find(String value, {String? type}) {
    final lower = value.toLowerCase();
    for (final name in {lower, lower.replaceAll('_', ' ')}) {
      final tag = type == null ? _byName[name] : _byTypeName['$type\n$name'];
      if (tag != null) return tag;
    }
    return null;
  }

  static final _prefixed = RegExp(
    '^(-?)(${nhentaiTagTypes.join('|')}):(.+)\$',
    caseSensitive: false,
  );

  /// One word of a search as nhentai wants it: known tag names become
  /// `type:"name"` tokens (`-big_breasts` -> `-tag:"big breasts"`),
  /// `artist:some_one` gets quoted. Quoted words (`"school days"`) and
  /// unknown words stay as they are: nhentai searches those in titles.
  String toQuery(String word) {
    if (word.startsWith('"') || word.startsWith('-"')) return word;
    final m = _prefixed.firstMatch(word);
    if (m != null) {
      final minus = m.group(1)!;
      final type = m.group(2)!.toLowerCase();
      final value = m.group(3)!;
      if (value.startsWith('"')) return word;
      final tag =
          _find(value, type: type) ??
          NhentaiTag(0, value.toLowerCase().replaceAll('_', ' '), 0, type);
      return '$minus${tag.token}';
    }
    final minus = word.startsWith('-') ? '-' : '';
    final value = word.substring(minus.length);
    if (value.isEmpty) return word;
    final tag = _find(value);
    return tag == null ? word : '$minus${tag.token}';
  }

  static final _typed = RegExp(r'^(-?)([a-z]+):"?(.*)$');

  /// Tags for the last word typed: `big`, `big_br`, `tag:big`,
  /// `-artist:some` … Names starting with the word come first, then names
  /// containing it, each by popularity. Returns `(word, count)` pairs as
  /// typed in the app (`big_breasts`); a leading `-` is kept.
  List<(String, int)> suggest(String word, {int limit = 30}) {
    if (_tags.isEmpty) return const [];
    var text = word.trim().toLowerCase();
    var minus = '';
    String? type;
    final m = _typed.firstMatch(text);
    if (m != null) {
      minus = m.group(1)!;
      type = m.group(2);
      text = m.group(3)!;
    } else if (text.startsWith('-')) {
      minus = '-';
      text = text.substring(1);
    }
    text = text.replaceAll('"', '').replaceAll('_', ' ').trim();

    final starts = <NhentaiTag>[];
    final contains = <NhentaiTag>[];
    for (final tag in _tags) {
      if (type != null && tag.type != type) continue;
      final name = tag.name;
      if (text.isEmpty || name.startsWith(text)) {
        starts.add(tag);
        if (starts.length >= limit) break;
      } else if (contains.length < limit && name.contains(text)) {
        contains.add(tag);
      }
    }
    // as typed in the app; with the type when it was typed
    return [
      for (final tag in [...starts, ...contains].take(limit))
        (
          type != null
              ? '$minus${tag.type}:${underscored(tag.name)}'
              : '$minus${display(tag)}',
          tag.count,
        ),
    ];
  }
}
