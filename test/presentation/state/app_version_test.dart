import 'package:boorusphere/data/provider.dart';
import 'package:boorusphere/data/repository/version/entity/app_version.dart';
import 'package:boorusphere/domain/provider.dart';
import 'package:boorusphere/domain/repository/env_repo.dart';
import 'package:boorusphere/presentation/provider/app_versions/app_versions_state.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:mocktail/mocktail.dart';

import '../../utils/dio.dart';
import '../../utils/mocktail.dart';
import '../../utils/riverpod.dart';

class FakeEnvRepo extends Mock implements EnvRepo {
  @override
  AppVersion get appVersion => AppVersion.fromString('1.1.1');
}

void main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupMocktailFallbacks();

  group('app version', () {
    test('get', () async {
      final ref = ProviderContainer(
        overrides: [envRepoProvider.overrideWithValue(FakeEnvRepo())],
      );

      addTearDown(ref.dispose);

      ref.setupTestFor(dioProvider);
      ref.setupTestFor(appVersionsStateProvider);

      const edgeTag = 'v9.9.9-ios.3';
      final adapter = DioAdapterMock(ref.read(dioProvider));
      when(() => adapter.fetch(any(), any(), any())).thenAnswer(
        (invocation) async => ResponseBody.fromString(
          '{"tag_name": "$edgeTag", "prerelease": false}',
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        ),
      );

      await ref.read(appVersionsStateProvider.future);
      final versions = ref.read(appVersionsStateProvider).value;
      expect(versions?.current, AppVersion.fromString('1.1.1'));
      expect(versions?.latest, AppVersion.fromString(edgeTag));
      expect(versions?.latest.release, 3);
      expect(
        versions?.latest.apkUrl,
        allOf(
          contains('Schw1/boorusphere-ios/releases/download/$edgeTag/'),
          endsWith('.apk'),
        ),
      );
    });

    test('fromString and toString', () {
      expect(
        AppVersion.fromString('1.5.4+53'),
        const AppVersion(major: 1, minor: 5, patch: 4),
      );
      expect(AppVersion.fromString('v1.5.4-ios.12').release, 12);
      expect(AppVersion.fromString('1.5.4-ios.12-test.1').release, 12);
      expect(AppVersion.fromString('1.5.4-ios-dev+abc1234').release, 0);
      expect('${AppVersion.fromString('v1.5.4-ios.12')}', '1.5.4-ios.12');
      expect(AppVersion.fromString('v1.5.4-ios.12').tag, 'v1.5.4-ios.12');
      expect(AppVersion.fromString('garbage'), AppVersion.zero);
    });

    test('fork releases are newer than their base', () {
      final base = AppVersion.fromString('1.5.4');
      final r11 = AppVersion.fromString('v1.5.4-ios.11');
      final r12 = AppVersion.fromString('v1.5.4-ios.12');
      expect(r12.isNewerThan(r11), true);
      expect(r11.isNewerThan(r12), false);
      expect(r11.isNewerThan(base), true);
      expect(AppVersion.fromString('1.5.5').isNewerThan(r12), true);
      expect(r12.base, base);
    });

    test('isNewerThan', () {
      final first = AppVersion.fromString('9.9.1');
      final second = AppVersion.fromString('9.9.2');
      expect(second.isNewerThan(first), true);
      expect(first.isNewerThan(second), false);
      expect(first.isNewerThan(first), false);
    });

    test('empty response', () async {
      final ref = ProviderContainer(
        overrides: [envRepoProvider.overrideWithValue(FakeEnvRepo())],
      );

      ref.setupTestFor(dioProvider);
      ref.setupTestFor(appVersionsStateProvider);

      final adapter = DioAdapterMock(ref.read(dioProvider));
      when(
        () => adapter.fetch(any(), any(), any()),
      ).thenAnswer((invocation) async => ResponseBody.fromString('', 200));

      addTearDown(ref.dispose);

      await ref.read(appVersionsStateProvider.future);
      expect(ref.read(appVersionsStateProvider).value?.latest, AppVersion.zero);
    });
  });
}
