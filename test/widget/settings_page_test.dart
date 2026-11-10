import 'package:boorusphere/data/repository/setting/entity/setting.dart';
import 'package:boorusphere/domain/provider.dart';
import 'package:boorusphere/presentation/provider/settings/entity/download_quality.dart';
import 'package:boorusphere/presentation/provider/shared_storage_handle.dart';
import 'package:boorusphere/presentation/screens/settings/settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../utils/widget.dart';

void main() {
  late FakeSettingsRepo settings;

  Future<void> pumpSettings(WidgetTester tester) => pumpScreen(
    tester,
    const SettingsPage(),
    overrides: [
      settingsRepoProvider.overrideWithValue(settings),
      sharedStorageHandleProvider.overrideWithValue(
        SharedStorageHandle(downloadPath: '/tmp/boorusphere-test'),
      ),
    ],
  );

  setUp(() => settings = FakeSettingsRepo());

  testWidgets('download quality: the dialog marks the current choice and '
      'saves a new one', (tester) async {
    await pumpSettings(tester);
    final tile = find.widgetWithText(ListTile, 'Download quality');
    expect(
      find.descendant(of: tile, matching: find.text('Always ask')),
      findsOneWidget,
    );

    await tester.tap(tile);
    await tester.pumpAndSettle();
    final dialog = find.byType(AlertDialog);
    expect(dialog, findsOneWidget);
    final group = tester.widget<RadioGroup<DownloadQuality>>(
      find.byType(RadioGroup<DownloadQuality>),
    );
    expect(group.groupValue, DownloadQuality.ask);

    await tester.tap(
      find.descendant(of: dialog, matching: find.text('Original file')),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(
      find.descendant(of: tile, matching: find.text('Original file')),
      findsOneWidget,
    );
    expect(
      settings.values[Setting.downloadsQuality.name],
      DownloadQuality.original,
    );
  });

  testWidgets('download quality: closing the dialog keeps the setting', (
    tester,
  ) async {
    settings.values[Setting.downloadsQuality.name] = DownloadQuality.sample;
    await pumpSettings(tester);
    await tester.tap(find.widgetWithText(ListTile, 'Download quality'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<RadioGroup<DownloadQuality>>(
            find.byType(RadioGroup<DownloadQuality>),
          )
          .groupValue,
      DownloadQuality.sample,
    );

    await tester.tapAt(const Offset(5, 5)); // outside the dialog
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(
      settings.values[Setting.downloadsQuality.name],
      DownloadQuality.sample,
    );
  });
}
