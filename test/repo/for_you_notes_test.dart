import 'dart:math';
import 'dart:ui';

import 'package:boorusphere/data/repository/booru/entity/post.dart';
import 'package:boorusphere/data/repository/booru/post_notes.dart';
import 'package:boorusphere/data/repository/for_you.dart';
import 'package:boorusphere/data/repository/server/entity/server.dart';
import 'package:boorusphere/presentation/screens/post/post_notes_overlay.dart';
import 'package:flutter_test/flutter_test.dart';

Post _post(int id, List<String> tags, {String server = 'Danbooru'}) =>
    Post(id: id, serverId: server, tags: tags);

void main() {
  group('ForYou', () {
    test('tags of a post', () {
      expect(
          ForYou.tagsOf(_post(1, [
            'Cat_Ears',
            'rating:safe',
            'highres',
            'tag:"big hat"',
            'glasses',
            'tag:glasses',
            '',
          ])),
          {'cat_ears', 'glasses'});
    });

    test('interests: counted per post, rare and common ones dropped', () {
      final posts = [
        for (var i = 0; i < 10; i++)
          _post(i, [
            '1girl',
            if (i < 4) 'cat_ears',
            if (i < 2) 'glasses',
            if (i == 0) 'once',
            if (i < 3) 'blocked_tag',
          ]),
        // same post again (favorite and sent): counted once
        _post(0, ['cat_ears', 'glasses']),
      ];
      final interests = ForYou.interests(posts, blocked: {'blocked_tag'});
      expect(interests, [('cat_ears', 4), ('glasses', 2)]);
    });

    test('pick: different tags, at most the pool', () {
      final interests = [('a', 10), ('b', 5), ('c', 1)];
      final picked = ForYou.pick(interests, count: 2, random: Random(1));
      expect(picked, hasLength(2));
      expect(picked.toSet(), hasLength(2));
      expect(ForYou.pick(interests, count: 9, random: Random(2)).toSet(),
          {'a', 'b', 'c'});
      expect(ForYou.pick(const []), isEmpty);
    });

    test('mix takes turns and skips seen and doubles', () {
      final a = [_post(1, []), _post(2, []), _post(3, [])];
      final b = [_post(2, []), _post(4, [])];
      final mixed = ForYou.mix([a, b], seen: {'3-Danbooru'});
      expect(mixed.map((it) => it.id), [1, 2, 4]);
    });
  });

  group('PostNotes', () {
    const danbooru = Server(
      id: 'Danbooru',
      homepage: 'https://danbooru.donmai.us',
      searchUrl: 'posts.json?tags={tags}&page={page-id}&limit={post-limit}',
    );
    const yandere = Server(
      id: 'yande.re',
      homepage: 'https://yande.re',
      searchUrl: 'post.json?tags={tags}&page={page-id}&limit={post-limit}',
    );
    const translated = Post(
        id: 5, originalFile: 'https://x/5.jpg', tags: ['translated', 'cat']);

    test('only posts tagged as translated are asked', () {
      expect(PostNotes.urlOf(danbooru, translated),
          'https://danbooru.donmai.us/notes.json?search[post_id]=5'
          '&search[is_active]=true&limit=200');
      expect(PostNotes.urlOf(yandere, translated),
          'https://yande.re/note.json?post_id=5');
      expect(
          PostNotes.urlOf(danbooru,
              const Post(id: 5, originalFile: 'x', tags: ['cat'])),
          isNull);
      expect(
          PostNotes.urlOf(
              const Server(id: 'g', homepage: 'https://g', searchUrl: 'x'),
              translated),
          isNull);
    });

    test('parse: active notes with text', () {
      final notes = PostNotes.parse([
        {'x': 10, 'y': 20, 'width': 30, 'height': 40, 'body': 'Hello<br>world'},
        {'x': 1, 'y': 1, 'width': 1, 'height': 1, 'body': 'x', 'is_active': false},
        {'x': 1, 'y': 1, 'width': 0, 'height': 1, 'body': 'x'},
        {'x': '5', 'y': '6', 'width': '7', 'height': '8', 'body': '<b>  </b>'},
        'junk',
      ]);
      expect(notes, hasLength(1));
      expect(notes.single.x, 10);
      expect(notes.single.text, 'Hello\nworld');
      expect(PostNotes.parse({'error': 1}), isEmpty);
    });

    test('Monbooru annotations', () {
      const monbooru = Server(
        id: 'Monbooru',
        homepage: 'https://booru.example',
        searchUrl: 'api/v1/images/search?q={tags}',
        urlSuffix: '&gallery=main',
      );
      expect(PostNotes.urlOf(monbooru, const Post(id: 9, originalFile: 'x')),
          'https://booru.example/api/v1/images/9?gallery=main');
      expect(
          PostNotes.urlOf(monbooru, const Post(id: 9, pageCount: 20)), isNull,
          reason: 'archive');
      final notes = PostNotes.parse({
        'id': 9,
        'annotations': [
          {'site': 'danbooru', 'x': 1, 'y': 2, 'w': 3, 'h': 4,
            'body': '[b]Hi[/b]', 'body_text': 'Hi'},
          {'x': 1, 'y': 2, 'w': 3, 'h': 4, 'body': 'plain'},
        ],
      });
      expect(notes.map((it) => it.text), ['Hi', 'plain']);
      expect(notes.first.width, 3);
      expect(PostNotes.parse({'id': 9}), isEmpty);
    });

    test('HTML to text', () {
      expect(
          PostNotes.toText(
              '<p>Tom &amp; Jerry</p><div class="x">say &quot;hi&quot;&#33;</div>'),
          'Tom & Jerry\nsay "hi"!');
    });

    test('where the image is drawn', () {
      // wide image in a tall box: full width, centered vertically
      expect(PostNotesOverlay.imageRect(const Size(400, 800), 2000, 1000),
          const Rect.fromLTWH(0, 300, 400, 200));
      expect(PostNotesOverlay.imageRect(const Size(400, 800), 0, 0),
          const Rect.fromLTWH(0, 0, 400, 800));
    });
  });
}
