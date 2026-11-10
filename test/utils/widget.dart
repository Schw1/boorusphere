import 'package:boorusphere/data/repository/setting/entity/setting.dart';
import 'package:boorusphere/domain/repository/settings_repo.dart';
import 'package:boorusphere/presentation/i18n/strings.g.dart';
import 'package:boorusphere/presentation/provider/data_backup/data_backup.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hooks_riverpod/misc.dart' show Override;

/// Shows [child] as a screen of the app: English texts, a ProviderScope
/// with [overrides], Material theme.
Future<void> pumpScreen(
  WidgetTester tester,
  Widget child, {
  List<Override> overrides = const [],
}) async {
  await LocaleSettings.setLocale(AppLocale.en);
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      retry: (_, _) => null,
      child: TranslationProvider(child: MaterialApp(home: child)),
    ),
  );
  await tester.pump();
}

/// Settings kept in memory instead of Hive.
class FakeSettingsRepo implements SettingsRepo {
  final values = <String, Object?>{};

  @override
  T get<T>(Setting key, {required T or}) => (values[key.name] as T?) ?? or;

  @override
  Future<void> put<T>(Setting key, T value) async => values[key.name] = value;

  @override
  Future<void> import(String src) async {}

  @override
  Future<BackupItem> export() async => BackupItem('settings', values);
}
