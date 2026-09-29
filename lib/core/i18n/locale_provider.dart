import 'dart:ui' show Locale;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers/auth_providers.dart';
import '../../data/providers/repository_providers.dart';
import '../../domain/repositories/settings_repository.dart';
import 'tr.dart';

const Locale defaultUserLocale = Locale('ar', 'EG');
const Locale englishUserLocale = Locale('en', 'US');

String userLocaleSettingKey(int userId) => 'user_locale_$userId';

class UserLocalePreference {
  const UserLocalePreference._();

  static Future<Locale> load(
    ISettingsRepository repository,
    int userId,
  ) async {
    final code = await repository.getSetting(userLocaleSettingKey(userId));
    return localeForCode(code);
  }

  static Future<void> save(
    ISettingsRepository repository,
    int userId,
    Locale locale,
  ) {
    return repository.saveSetting(
      userLocaleSettingKey(userId),
      locale.languageCode == 'en' ? 'en' : 'ar',
    );
  }
}

Locale localeForCode(String? code) =>
    code == 'en' ? englishUserLocale : defaultUserLocale;

final userLocaleProvider =
    NotifierProvider<UserLocaleNotifier, Locale>(UserLocaleNotifier.new);

class UserLocaleNotifier extends Notifier<Locale> {
  int _loadGeneration = 0;

  @override
  Locale build() {
    final userId = ref.watch(authProvider).user?.id;
    final generation = ++_loadGeneration;
    if (userId == null) {
      I18nCatalog.setLocale(defaultUserLocale);
      return defaultUserLocale;
    }
    Future<void>.microtask(() => _loadForUser(userId, generation));
    I18nCatalog.setLocale(defaultUserLocale);
    return defaultUserLocale;
  }

  Future<void> _loadForUser(int userId, int generation) async {
    try {
      final repository = ref.read(settingsRepositoryProvider);
      final locale = await UserLocalePreference.load(repository, userId);
      if (generation != _loadGeneration) return;
      state = locale;
      I18nCatalog.setLocale(locale);
    } catch (error) {
      debugPrint('[i18n] Could not load locale for user $userId: $error');
    }
  }

  Future<void> setLocale(Locale locale) async {
    final userId = ref.read(authProvider).user?.id;
    final normalized = localeForCode(locale.languageCode);
    state = normalized;
    I18nCatalog.setLocale(normalized);
    if (userId == null) return;
    await UserLocalePreference.save(
      ref.read(settingsRepositoryProvider),
      userId,
      normalized,
    );
  }
}
