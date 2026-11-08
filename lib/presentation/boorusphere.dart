import 'dart:async';
import 'dart:io';

import 'package:boorusphere/data/provider.dart';
import 'package:boorusphere/domain/provider.dart';
import 'package:boorusphere/presentation/i18n/helper.dart';
import 'package:boorusphere/presentation/i18n/strings.g.dart';
import 'package:boorusphere/presentation/provider/app_updater.dart';
import 'package:boorusphere/presentation/provider/data_backup/auto_backup.dart';
import 'package:boorusphere/presentation/provider/download/download_state.dart';
import 'package:boorusphere/presentation/provider/download/flutter_downloader_handle.dart';
import 'package:boorusphere/presentation/provider/photos_saver.dart';
import 'package:boorusphere/presentation/provider/server_data_state.dart';
import 'package:boorusphere/presentation/provider/settings/download_setting_state.dart';
import 'package:boorusphere/presentation/provider/settings/ui_setting_state.dart';
import 'package:boorusphere/presentation/provider/shared_storage_handle.dart';
import 'package:boorusphere/presentation/routes/app_route_observer.dart';
import 'package:boorusphere/presentation/routes/app_router.dart';
import 'package:boorusphere/presentation/utils/root_messenger.dart';
import 'package:boorusphere/presentation/widgets/app_theme_builder.dart';
import 'package:boorusphere/utils/http/overrides.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:path/path.dart' as p;

class Boorusphere extends HookConsumerWidget {
  const Boorusphere({super.key});

  Future<void> initializeAsyncStates(
    WidgetRef ref,
    Function onCompleted,
  ) async {
    await ref.read(serverStateProvider.notifier).populate();

    final envRepo = ref.read(envRepoProvider);
    final appStateRepo = ref.read(appStateRepoProvider);
    if (envRepo.appVersion.isNewerThan(appStateRepo.version)) {
      await ref.read(appUpdaterProvider).clear();
    }

    onCompleted();
    unawaited(ref.read(autoBackupProvider).runIfDue());
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(uiSettingStateProvider.select((ui) => ui.locale));
    final theme =
        ref.watch(uiSettingStateProvider.select((ui) => ui.themeMode));
    final isMidnight =
        ref.watch(uiSettingStateProvider.select((ui) => ui.midnightMode));
    final envRepo = ref.watch(envRepoProvider);
    final cookieJar = ref.watch(cookieJarProvider);
    final router = useMemoized(AppRouter.new);
    final initialized = useState(false);

    useEffect(() {
      initializeAsyncStates(ref, () {
        initialized.value = true;
      });
    }, []);

    useOnAppLifecycleStateChange((previous, current) {
      if (current == AppLifecycleState.resumed && initialized.value) {
        unawaited(ref.read(autoBackupProvider).runIfDue());
      }
    });

    if (!initialized.value) {
      return const SizedBox.shrink();
    }

    useEffect(() {
      HttpOverrides.global = CustomHttpOverrides(cookieJar: cookieJar);
      return () {
        HttpOverrides.global = null;
      };
    }, [cookieJar]);

    useEffect(() {
      LocaleHelper.update(locale);
    }, [locale]);

    useEffect(() {
      ref.read(downloaderHandleProvider).listen((progress) async {
        if (progress.status.isDownloaded) {
          await ref.read(sharedStorageHandleProvider).rescan();
          if (Platform.isIOS &&
              ref.read(downloadSettingStateProvider).saveToPhotos) {
            final entry =
                ref.read(downloadEntryStateProvider).getById(progress.id);
            if (entry.dest.isNotEmpty) {
              final path = p.join(ref.read(sharedStorageHandleProvider).path,
                  Uri.decodeFull(entry.dest));
              await PhotosSaver.save(progress.id, path);
            }
          }
        }

        await ref.read(downloadProgressStateProvider.notifier).update(progress);
      });
    }, []);

    if (envRepo.sdkVersion > 28) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }

    return AppThemeBuilder(
      builder: (context, appTheme) => MaterialApp.router(
        debugShowCheckedModeBanner: false,
        scaffoldMessengerKey: rootMessengerKey,
        title: 'Boorusphere',
        theme: appTheme.day,
        darkTheme: isMidnight ? appTheme.midnight : appTheme.night,
        themeMode: theme,
        routerConfig: router.config(
          navigatorObservers: () => [
            AppRouteObserver(ref),
          ],
        ),
        locale: TranslationProvider.of(context).locale.digestedFlutterLocale,
        supportedLocales: AppLocaleUtils.supportedLocales,
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        builder: (context, child) => child ?? Container(),
      ),
    );
  }
}

// Convert slang locale to flutter locale
extension on AppLocale {
  Locale get digestedFlutterLocale {
    if (this == AppLocale.uwu) {
      return AppLocale.en.flutterLocale;
    }

    // Return the actual locale
    return flutterLocale;
  }
}
