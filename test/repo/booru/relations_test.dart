import 'dart:convert';

import 'package:boorusphere/data/repository/booru/entity/page_option.dart';
import 'package:boorusphere/data/repository/booru/entity/post.dart';
import 'package:boorusphere/data/repository/booru/parser/booru_parser.dart';
import 'package:boorusphere/data/repository/booru/parser/danbooru_json_parser.dart';
import 'package:boorusphere/data/repository/booru/parser/e621_json_parser.dart';
import 'package:boorusphere/data/repository/booru/parser/gelbooru_json_parser.dart';
import 'package:boorusphere/data/repository/booru/parser/gelbooru_xml_parser.dart';
import 'package:boorusphere/data/repository/booru/parser/moebooru_json_parser.dart';
import 'package:boorusphere/data/repository/booru/parser/safebooru_xml_parser.dart';
import 'package:boorusphere/data/repository/server/entity/server.dart';
import 'package:boorusphere/presentation/provider/post_pools.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../utils/fake_data.dart';

const _server = Server(id: 'Test', homepage: 'https://booru.example.org');

List<Post> _parse(BooruParser parser, Object data) => parser
    .parsePage(_server, Response(data: data, requestOptions: RequestOptions()))
    .toList();

/// The fixture as JSON, with [edit] applied to each post.
Object _json(String fixture, void Function(Map post) edit, {String? key}) {
  final data = jsonDecode(getFixture(fixture).readAsStringSync());
  final posts = key == null ? data as List : (data as Map)[key] as List;
  for (final post in posts.whereType<Map>()) {
    edit(post);
  }
  return data;
}

void main() {
  group('parsers read parent, children and pools', () {
    void expectRelations(List<Post> posts, {List<int> pools = const []}) {
      expect(posts, isNotEmpty);
      for (final post in posts) {
        expect(post.parentId, 4242, reason: '${post.id}');
        expect(post.hasChildren, true, reason: '${post.id}');
        expect(post.poolIds, pools, reason: '${post.id}');
      }
    }

    test('Danbooru', () {
      final data = _json('danbooru/posts.json', (post) {
        post['parent_id'] = 4242;
        post['has_children'] = true;
      });
      expectRelations(_parse(DanbooruJsonParser(), data));
    });

    test('e621', () {
      final data = _json('e621/posts.json', (post) {
        post['relationships'] = {'parent_id': 4242, 'has_children': true};
        post['pools'] = [12, 'broken', 34];
      }, key: 'posts');
      expectRelations(_parse(E621JsonParser(), data), pools: [12, 34]);
    });

    test('Gelbooru JSON (string flags)', () {
      final data = _json('gelbooru/posts.json', (post) {
        post['parent_id'] = '4242';
        post['has_children'] = 'true';
      }, key: 'post');
      expectRelations(_parse(GelbooruJsonParser(), data));
    });

    test('Gelbooru XML', () {
      final xml = getFixture('gelbooru/posts.xml')
          .readAsStringSync()
          .replaceAll(
            RegExp('<parent_id>[^<]*</parent_id>'),
            '<parent_id>4242</parent_id>',
          )
          .replaceAll(
            RegExp('<has_children>[^<]*</has_children>'),
            '<has_children>true</has_children>',
          );
      expectRelations(_parse(GelbooruXmlParser(), xml));
    });

    test('Moebooru (Konachan)', () {
      final data = _json('konachan/posts.json', (post) {
        post['parent_id'] = 4242;
        post['has_children'] = true;
      });
      expectRelations(_parse(MoebooruJsonParser(), data));
    });

    test('Safebooru XML', () {
      final xml = getFixture('safebooru/posts.xml')
          .readAsStringSync()
          .replaceAll('parent_id=""', 'parent_id="4242"')
          .replaceAll('has_children="false"', 'has_children="true"');
      expectRelations(_parse(SafebooruXmlParser(), xml));
    });

    test('no parent and no children by default', () {
      final posts = _parse(
        DanbooruJsonParser(),
        jsonDecode(getFixture('danbooru/posts.json').readAsStringSync()),
      );
      expect(posts.where((it) => it.parentId != 0), isEmpty);
      expect(posts.where((it) => it.poolIds.isNotEmpty), isEmpty);
    });
  });

  group('relation searches per booru', () {
    Server server(
      String parser, {
      String searchUrl = 'posts.json?tags={tags}',
    }) => Server(
      id: 'S',
      homepage: 'https://booru.example.org',
      searchUrl: searchUrl,
      searchParserId: parser,
    );

    test('Danbooru reads pools in pool order', () {
      final s = server('Danbooru.json');
      expect(s.postQuery(5), 'id:5');
      expect(s.childrenQuery(5), 'parent:5');
      expect(s.poolQuery(7), 'ordpool:7');
      expect(
        s.poolsUrlOf(5, const []),
        'https://booru.example.org/pools.json?search[post_ids_include_all]=5&limit=20',
      );
    });

    test('e621 looks pools up by the ids the post lists', () {
      final s = server('E621.json');
      expect(s.poolQuery(7), 'pool:7');
      expect(s.poolsUrlOf(5, const []), isNull);
      expect(
        s.poolsUrlOf(5, const [7, 8]),
        'https://booru.example.org/pools.json?search[id]=7,8&limit=20',
      );
    });

    test('Gelbooru has parents and children but no pools', () {
      final s = server('Gelbooru.json');
      expect(s.childrenQuery(5), 'parent:5');
      expect(s.poolQuery(7), isNull);
      expect(s.poolsUrlOf(5, const [7]), isNull);
    });

    test('engines without relations get nothing', () {
      final s = server(
        'Szurubooru.json',
        searchUrl: 'api/posts/?offset={post-offset}&query={tags}',
      );
      expect(s.postQuery(5), isNull);
      expect(s.childrenQuery(5), isNull);
      expect(s.poolQuery(5), isNull);
    });

    test('a typed ordpool keeps the sort button out of the search', () {
      final s = server('Danbooru.json');
      final url = s.searchUrlOf(
        const PageOption(query: 'ordpool:7', sort: 'score'),
        page: 1,
      );
      expect(url, isNot(contains('order%3Ascore')));
    });
  });

  test('pools from a pools.json answer', () {
    final pools = BooruPool.listOf([
      {'id': 7, 'name': 'Some_Comic_Series', 'post_count': 24},
      {'id': 'x'},
      {'id': 8},
    ]);
    expect(pools.map((it) => (it.id, it.name, it.postCount)), [
      (7, 'Some Comic Series', 24),
      (8, '', 0),
    ]);
    expect(BooruPool.listOf({'error': 'nope'}), isEmpty);
  });
}
