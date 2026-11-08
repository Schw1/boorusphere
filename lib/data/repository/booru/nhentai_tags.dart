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

  /// Search token for the tag, e.g. `tag:"big breasts"`.
  String get token =>
      name.contains(' ') ? '$type:"$name"' : '$type:$name';
}

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
        loadJson(await file.readAsString());
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
      loadJson(body);
      await file.parent.create(recursive: true);
      await file.writeAsString(body);
    } catch (e) {
      // Keep using the stored copy, if any.
      debugPrint('NhentaiTags: download failed: $e');
    }
  }

  /// Reads the list format written by tool/nhentai_tags.py. Throws on
  /// anything else.
  @visibleForTesting
  void loadJson(String source) {
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
    _tags = tags;
    _byId = {for (final tag in tags) tag.id: tag};
  }

  NhentaiTag? byId(int id) => _byId[id];

  /// Search tokens of the tag ids of a search result (unknown ids skipped).
  List<String> tokensOf(Iterable<int> ids) => [
        for (final id in ids)
          if (_byId[id] case final tag?) tag.token,
      ];

  static final _typed = RegExp(r'^(-?)([a-z]+):"?(.*)$');

  /// Tags for the last word typed: `big`, `tag:big`, `-artist:"some` …
  /// Names starting with the word come first, then names containing it,
  /// each by popularity. Returns `(token, count)` pairs; a leading `-` is
  /// kept.
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
    return [
      for (final tag in [...starts, ...contains].take(limit))
        ('$minus${tag.token}', tag.count),
    ];
  }
}
