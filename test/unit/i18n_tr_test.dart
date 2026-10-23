import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/core/i18n/locale_provider.dart';
import 'package:picpos_erp/core/i18n/tr.dart';
import 'package:picpos_erp/domain/repositories/settings_repository.dart';
import 'package:picpos_erp/services/stock_shortage_policy_service.dart';

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

  test('trData translates only exact seeded defaults in English', () {
    I18nCatalog.setCatalog({'الأصول': 'Assets'});
    I18nCatalog.setLocale(englishUserLocale);

    expect(trData('الأصول'), 'Assets');
    expect(trData('حسابي الخاص'), 'حسابي الخاص');
    expect(trData(null), isEmpty);
  });

  test('trData translates only valid seeded fiscal-year names', () {
    I18nCatalog.setCatalog({
      'السنة المالية {year}': 'Fiscal Year {year}',
    });
    I18nCatalog.setLocale(englishUserLocale);

    expect(trData('السنة المالية 2026'), 'Fiscal Year 2026');
    expect(trData('السنة المالية التجريبية'), 'السنة المالية التجريبية');
  });

  test('trData preserves seeded stored values in Arabic', () {
    I18nCatalog.setCatalog({'الأصول': 'Assets'});
    I18nCatalog.setLocale(defaultUserLocale);

    expect(trData('الأصول'), 'الأصول');
  });

  test('stock-shortage labels localize without changing wire values', () {
    I18nCatalog.setCatalog({
      'منع البيع': 'Block Sale',
      'تحذير مع السماح بالسالب': 'Warn and Allow Negative Stock',
      'تحذير وإيقاف الخصم عند صفر': 'Warn and Stop at Zero',
    });
    I18nCatalog.setLocale(englishUserLocale);

    expect(StockShortagePolicy.block.displayLabel, 'Block Sale');
    expect(
      StockShortagePolicy.allowNegative.displayLabel,
      'Warn and Allow Negative Stock',
    );
    expect(StockShortagePolicy.clampToZero.displayLabel, 'Warn and Stop at Zero');
    expect(StockShortagePolicy.allowNegative.wireName, 'allow_negative');
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
