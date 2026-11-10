import 'package:boorusphere/data/repository/booru/entity/post.dart';
import 'package:boorusphere/data/repository/server/entity/server.dart';
import 'package:boorusphere/domain/provider.dart';
import 'package:boorusphere/presentation/provider/monbooru_history.dart';
import 'package:boorusphere/presentation/provider/monbooru_queue.dart';
import 'package:boorusphere/presentation/provider/monbooru_sender.dart';
import 'package:boorusphere/presentation/provider/server_data_state.dart';
import 'package:boorusphere/presentation/provider/stores.dart';
import 'package:boorusphere/presentation/screens/monbooru/monbooru_history_page.dart';
import 'package:boorusphere/presentation/screens/reading/continue_reading_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:mocktail/mocktail.dart';

import '../presentation/state/app_version_test.dart';
import '../utils/widget.dart';

const _server = Server(id: 'Danbooru', homepage: 'https://d.example.org');

class _Servers extends ServerState {
  @override
  Iterable<Server> build() => const [_server];
}

class _Box extends Mock implements Box<String> {}

void main() {
  group('Continue reading', () {
    Future<void> pumpPage(WidgetTester tester, List<Post> posts) => pumpScreen(
      tester,
      const ContinueReadingPage(),
      overrides: [
        serverStateProvider.overrideWith(_Servers.new),
        continueReadingProvider.overrideWith((ref) async => posts),
      ],
    );

    testWidgets('an empty list explains what shows up there', (tester) async {
      await pumpPage(tester, const []);
      await tester.pump();
      expect(
        find.text('Galleries and archives you start reading show up here.'),
        findsOneWidget,
      );
      expect(
        find.byWidgetPredicate((it) => it is PopupMenuButton),
        findsNothing,
      );
    });

    testWidgets('posts of removed servers are left out', (tester) async {
      await pumpPage(tester, const [
        Post(id: 1, serverId: 'Removed', pageCount: 10),
      ]);
      await tester.pump();
      expect(
        find.text('Galleries and archives you start reading show up here.'),
        findsOneWidget,
      );
    });
  });

  group('Monbooru history', () {
    late _Box box;

    Future<void> pumpPage(
      WidgetTester tester,
      List<MonbooruHistoryEntry> entries,
    ) => pumpScreen(
      tester,
      const MonbooruHistoryPage(),
      overrides: [
        serverStateProvider.overrideWith(_Servers.new),
        envRepoProvider.overrideWithValue(FakeEnvRepo()),
        settingsRepoProvider.overrideWithValue(FakeSettingsRepo()),
        monbooruHistoryStoreProvider.overrideWithValue(MonbooruHistory(box)),
        monbooruHistoryProvider.overrideWith((ref) async => entries),
      ],
    );

    setUp(() {
      box = _Box();
      // nothing pending to look up when the page opens
      when(() => box.values).thenReturn(const []);
    });

    testWidgets('an empty history explains what shows up there', (
      tester,
    ) async {
      await pumpPage(tester, const []);
      await tester.pump();
      expect(
        find.text('Posts you send to Monbooru show up here with their result.'),
        findsOneWidget,
      );
    });

    testWidgets('each send shows its post, server and outcome', (tester) async {
      await pumpPage(tester, [
        MonbooruHistoryEntry(
          post: const Post(id: 11, serverId: 'Danbooru'),
          time: DateTime(2026, 11, 10, 12),
          jobId: 3,
          report: const MonbooruSendReport(outcome: MonbooruOutcome.added),
        ),
        MonbooruHistoryEntry(
          post: const Post(id: 12, serverId: 'Danbooru'),
          time: DateTime(2026, 11, 10, 11),
          report: const MonbooruSendReport(
            error: MonbooruError(MonbooruErrorKind.http, '500'),
          ),
        ),
        MonbooruHistoryEntry(
          post: const Post(id: 13, serverId: 'Danbooru'),
          time: DateTime(2026, 11, 10, 10),
          jobId: 4,
        ),
      ]);
      await tester.pump();

      expect(find.text('#11'), findsOneWidget);
      expect(find.text('#12'), findsOneWidget);
      expect(find.text('#13'), findsOneWidget);
      expect(find.byIcon(Icons.cloud_done), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      expect(find.byIcon(Icons.hourglass_top), findsOneWidget);
      expect(find.textContaining('Waiting for monloader'), findsOneWidget);
      expect(find.textContaining('Danbooru ·'), findsNWidgets(3));
    });
  });
}
