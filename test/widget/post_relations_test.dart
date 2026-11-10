import 'package:boorusphere/data/repository/booru/entity/post.dart';
import 'package:boorusphere/data/repository/server/entity/server.dart';
import 'package:boorusphere/presentation/provider/post_pools.dart';
import 'package:boorusphere/presentation/provider/server_data_state.dart';
import 'package:boorusphere/presentation/screens/post/post_relations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../utils/widget.dart';

const _danbooru = Server(
  id: 'Danbooru',
  homepage: 'https://danbooru.example.org',
  searchUrl: 'posts.json?tags={tags}',
  searchParserId: 'Danbooru.json',
);

const _szuru = Server(
  id: 'Szuru',
  homepage: 'https://szuru.example.org',
  searchUrl: 'api/posts/?offset={post-offset}&query={tags}',
  searchParserId: 'Szurubooru.json',
);

class _Servers extends ServerState {
  @override
  Iterable<Server> build() => const [_danbooru, _szuru];
}

void main() {
  late List<String> searched;

  Future<void> pumpRelations(
    WidgetTester tester,
    Post post, {
    List<BooruPool> pools = const [],
  }) {
    return pumpScreen(
      tester,
      Scaffold(
        body: ListView(
          children: [PostRelations(post: post, onSearch: searched.add)],
        ),
      ),
      overrides: [
        serverStateProvider.overrideWith(_Servers.new),
        postPoolsProvider(post).overrideWith((ref) async => pools),
      ],
    );
  }

  setUp(() => searched = []);

  testWidgets('parent, other versions, children and pools open searches', (
    tester,
  ) async {
    const post = Post(
      id: 100,
      serverId: 'Danbooru',
      parentId: 42,
      hasChildren: true,
    );
    await pumpRelations(
      tester,
      post,
      pools: const [BooruPool(id: 7, name: 'Some Comic', postCount: 24)],
    );
    await tester.pumpAndSettle();

    expect(find.text('Related posts'), findsOneWidget);
    expect(find.text('24 posts'), findsOneWidget);

    await tester.tap(find.text('Parent post #42'));
    await tester.tap(find.text('Other versions'));
    await tester.tap(find.text('Child posts'));
    await tester.tap(find.text('Some Comic'));
    expect(searched, ['id:42', 'parent:42', 'parent:100', 'ordpool:7']);
  });

  testWidgets('a post without relations shows nothing', (tester) async {
    await pumpRelations(tester, const Post(id: 1, serverId: 'Danbooru'));
    await tester.pumpAndSettle();
    expect(find.text('Related posts'), findsNothing);
    expect(find.byType(ListTile), findsNothing);
  });

  testWidgets('a booru without these searches shows nothing', (tester) async {
    await pumpRelations(
      tester,
      const Post(id: 1, serverId: 'Szuru', parentId: 5, hasChildren: true),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ListTile), findsNothing);
  });

  testWidgets('pools that fail to load say so, the rest stays', (tester) async {
    const post = Post(id: 100, serverId: 'Danbooru', hasChildren: true);
    await pumpScreen(
      tester,
      Scaffold(
        body: ListView(
          children: [PostRelations(post: post, onSearch: searched.add)],
        ),
      ),
      overrides: [
        serverStateProvider.overrideWith(_Servers.new),
        postPoolsProvider(post).overrideWith(
          (ref) => Future<List<BooruPool>>.error(Exception('offline')),
        ),
      ],
    );
    await tester.pumpAndSettle();
    expect(find.text('Child posts'), findsOneWidget);
    expect(find.text("Couldn't load the pools of this post."), findsOneWidget);
  });
}
