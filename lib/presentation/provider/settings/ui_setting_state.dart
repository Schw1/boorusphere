import 'dart:async';

import 'package:boorusphere/data/repository/setting/entity/setting.dart';
import 'package:boorusphere/domain/provider.dart';
import 'package:boorusphere/presentation/i18n/strings.g.dart';
import 'package:boorusphere/presentation/provider/settings/entity/ui_setting.dart';
import 'package:flutter/material.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'ui_setting_state.g.dart';

@riverpod
class UiSettingState extends _$UiSettingState {
  @override
  UiSetting build() {
    final repo = ref.read(settingsRepoProvider);
    return UiSetting(
      blur: repo.get(Setting.uiBlur, or: true),
      grid: repo.get(Setting.uiTimelineGrid, or: 1),
      locale: localeFromStr(repo.get(Setting.uiLanguage, or: '')),
      themeMode: ThemeMode
          .values[repo.get(Setting.uiThemeMode, or: ThemeMode.system.index)],
      midnightMode: repo.get(Setting.uiMidnightMode, or: false),
      imeIncognito: repo.get(Setting.imeIncognito, or: false),
    );
  }

  Future<int> cycleGrid() async {
    // -2/-1 = two/one columns less than the width-based default (bigger
    // thumbnails, mainly for tablets), up to +2 columns.
    final grid = state.grid < 2 ? state.grid + 1 : -2;
    state = state.copyWith(grid: grid);
    final repo = ref.read(settingsRepoProvider);

    await repo.put(Setting.uiTimelineGrid, grid);
    return grid;
  }

  Future<bool> showBlur(bool value) async {
    state = state.copyWith(blur: value);
    final repo = ref.read(settingsRepoProvider);

    await repo.put(Setting.uiBlur, value);
    return value;
  }

  AppLocale? localeFromStr(String name) {
    try {
      return AppLocale.values.firstWhere((it) => it.name == name);
    } on StateError {
      return null;
    }
  }

  Future<AppLocale?> setLocale(AppLocale? locale) async {
    final repo = ref.read(settingsRepoProvider);
    state = state.copyWith(locale: locale);
    if (locale == null) {
      unawaited(LocaleSettings.useDeviceLocale());
    } else {
      unawaited(LocaleSettings.setLocale(locale));
    }

    await repo.put(Setting.uiLanguage, locale == null ? '' : locale.name);
    return locale;
  }

  Future<ThemeMode> setThemeMode(ThemeMode mode) async {
    final repo = ref.read(settingsRepoProvider);

    state = state.copyWith(themeMode: mode);
    await repo.put(Setting.uiThemeMode, mode.index);
    return mode;
  }

  Future<ThemeMode> cycleThemeMode() {
    return switch (state.themeMode) {
      ThemeMode.dark => setThemeMode(ThemeMode.light),
      ThemeMode.light => setThemeMode(ThemeMode.system),
      _ => setThemeMode(ThemeMode.dark),
    };
  }

  Future<bool> setMidnightMode(bool value) async {
    final repo = ref.read(settingsRepoProvider);
    state = state.copyWith(midnightMode: value);
    await repo.put(Setting.uiMidnightMode, value);
    return value;
  }

  Future<bool> setImeIncognito(bool value) async {
    final repo = ref.read(settingsRepoProvider);
    state = state.copyWith(imeIncognito: value);
    await repo.put(Setting.imeIncognito, value);
    return value;
  }
}
