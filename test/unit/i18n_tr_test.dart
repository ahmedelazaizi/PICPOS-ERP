import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/core/i18n/locale_provider.dart';
import 'package:ural_erp/core/i18n/tr.dart';
import 'package:ural_erp/domain/repositories/settings_repository.dart';

class _MemorySettingsRepository implements ISettingsRepository {
  final values = <String, String>{};

  @override
  Future<List<String>> getAvailableBackups() async => [];
  @override
  Future<String?> createBackup() async => null;
  @override
  Future<bool> deleteBackup(String path) async => false;
  @override
  Future<bool> exportBackup(String destinationFolder) async => false;
  @override
  Future<Map<String, dynamic>> getBackupStats() async => {};
  @override
  Future<Map<String, String>> getAllSettings() async => values;
  @override
  Future<String?> getSetting(String key) async => values[key];
  @override
  Future<Map<String, dynamic>> getReceiptSettings() async => {};
  @override
  Future<bool> restoreBackup(String path) async => false;
  @override
  Future<void> saveCompanyInfo({
    required String name,
    String? phone,
    String? address,
    String? taxId,
  }) async {}
  @override
  Future<void> saveReceiptSettings({
    String? companyName,
    String? companyAddress,
    String? companyPhone,
    String? companyPhone2,
    String? companyEmail,
    String? taxNumber,
    String? headerText,
    String? footerText,
    String? termsText,
    dynamic logoImage,
    bool? showLogo,
    bool? showQrCode,
    bool? showBarcode,
    bool? showTaxDetails,
    bool? showItemCode,
    bool? showSalesperson,
    bool? showCustomerInfo,
    int? headerFontSize,
    int? bodyFontSize,
    int? footerFontSize,
    int? paperWidth,
    String? currencySymbol,
  }) async {}
  @override
  Future<void> saveSetting(String key, String value) async => values[key] = value;
  @override
  Stream<dynamic> watchReceiptSettings() => const Stream.empty();
  @override
  Stream<String?> watchSettingValue(String key) => Stream.value(values[key]);
}

void main() {
  tearDown(() {
    I18nCatalog.setCatalog(const {});
    I18nCatalog.setLocale(defaultUserLocale);
  });

  test('English catalog lookup returns the translated value', () {
    I18nCatalog.setCatalog({'حفظ': 'Save'});
    I18nCatalog.setLocale(englishUserLocale);

    expect(tr('حفظ'), 'Save');
  });

  test('missing English entry falls back to Arabic', () {
    I18nCatalog.setCatalog(const {});
    I18nCatalog.setLocale(englishUserLocale);

    expect(tr('نص غير مترجم'), 'نص غير مترجم');
  });

  test('named placeholders are replaced in translated templates', () {
    I18nCatalog.setCatalog({'مرحباً {name}': 'Hello {name}'});
    I18nCatalog.setLocale(englishUserLocale);

    expect(tr('مرحباً {name}', {'name': 'Sara'}), 'Hello Sara');
  });

  test('user locale preference persists by user id', () async {
    final repository = _MemorySettingsRepository();

    await UserLocalePreference.save(repository, 42, const Locale('en', 'US'));

    expect(repository.values, {'user_locale_42': 'en'});
    expect(
      await UserLocalePreference.load(repository, 42),
      englishUserLocale,
    );
    expect(await UserLocalePreference.load(repository, 7), defaultUserLocale);
  });
}
