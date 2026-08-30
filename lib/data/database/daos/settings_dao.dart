// ═══════════════════════════════════════════════════════════════════════════
// SETTINGS DAO - Settings and System Configuration Operations
// ═══════════════════════════════════════════════════════════════════════════
//
// This file contains all settings-related database operations extracted from
// the main database.dart file for better organization and maintainability.
//
// Usage: Import in database.dart and access via AppDatabase instance.
// ═══════════════════════════════════════════════════════════════════════════

part of '../database.dart';

/// Extension for Settings-related database operations
extension SettingsDao on AppDatabase {
  // ═══════════════════════════════════════════════════════════════════════
  // SETTINGS CRUD
  // ═══════════════════════════════════════════════════════════════════════

  /// Get setting by key.
  ///
  /// Tolerates duplicate rows (can occur from sync conflicts, aborted migrations,
  /// or pre-primary-key data). `key` is declared as PRIMARY KEY but legacy
  /// rows may violate the constraint — we defensively use `.get()` with
  /// `limit(1)` rather than `.getSingleOrNull()` which throws
  /// "Bad state: Too many elements" on duplicates.
  Future<Setting?> getSetting(String key) async {
    final rows = await (select(settings)
          ..where((s) => s.key.equals(key))
          ..limit(1))
        .get();
    return rows.isEmpty ? null : rows.first;
  }

  /// Get setting value by key
  Future<String?> getSettingValue(String key) async {
    final setting = await getSetting(key);
    return setting?.value;
  }

  /// Save multiple settings from a map — **ذرّيّاً**.
  ///
  /// ⚠️ كانت حلقةَ `setSetting` عارية: كلُّ مفتاحٍ كتابةٌ مستقلّة. فإخفاقٌ في
  /// منتصف الحلقة (‏قرصٌ ممتلئ، قفلُ قاعدة، انقطاعُ وصلة PostgreSQL) يترك
  /// **نصفَ سياسةٍ محفوظاً**: بعضُ مفاتيح السياسة بالقيم الجديدة وبعضُها
  /// بالقديمة، بلا خطأٍ يظهر للمستخدم لأنّ الاستثناء يقع بعد أن كُتب ما كُتب.
  /// والأسوأ أنّ `POST /api/settings` يبثّ `settings` بعدها، فتُدفَع الحالةُ
  /// النصفيّةُ إلى **كلِّ** الأجهزة.
  ///
  /// والمعاملةُ تجعلها كلَّها أو لا شيء.
  Future<void> saveSettings(Map<String, String> data) async {
    if (data.isEmpty) return;
    await transaction(() async {
      for (final entry in data.entries) {
        await setSetting(entry.key, entry.value);
      }
    });
  }

  /// Get all settings with a specific prefix
  Future<List<Setting>> getSettingsByPrefix(String prefix) {
    return (select(settings)..where((s) => s.key.like('$prefix%'))).get();
  }

  /// Set a setting value
  Future<void> setSetting(String key, String value) async {
    await into(settings).insertOnConflictUpdate(
      SettingsCompanion(key: Value(key), value: Value(value)),
    );
  }

  /// Watch a setting
  Stream<Setting?> watchSetting(String key) {
    return (select(
      settings,
    )..where((s) => s.key.equals(key))).watchSingleOrNull();
  }

  /// Watch setting value
  Stream<String?> watchSettingValue(String key) {
    return watchSetting(key).map((s) => s?.value);
  }

  /// Get all settings
  Future<List<Setting>> getAllSettings() {
    return select(settings).get();
  }

  /// Get all settings as map
  Future<Map<String, String>> getSettingsMap() async {
    final settingsList = await getAllSettings();
    return Map.fromEntries(
      settingsList
          .where((s) => s.value != null)
          .map((s) => MapEntry(s.key, s.value!)),
    );
  }


  // ═══════════════════════════════════════════════════════════════════════
  // RECEIPT SETTINGS
  // ═══════════════════════════════════════════════════════════════════════

  /// Get receipt settings (returns first record or creates default)
  Future<ReceiptSettingData> getReceiptSettings() async {
    final result = await select(receiptSettings).getSingleOrNull();
    if (result != null) return result;

    // Create default settings if none exist
    await initDefaultReceiptSettings();
    return (await select(receiptSettings).getSingleOrNull())!;
  }

  /// Watch receipt settings
  Stream<ReceiptSettingData?> watchReceiptSettings() {
    return select(receiptSettings).watchSingleOrNull();
  }

  /// Initialize default receipt settings
  Future<void> initDefaultReceiptSettings() async {
    await into(receiptSettings).insert(ReceiptSettingsCompanion.insert());
  }

  /// Save receipt settings (update if exists, insert if not)
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
    Uint8List? logoImage,
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
  }) async {
    final existing = await select(receiptSettings).getSingleOrNull();

    if (existing != null) {
      await (update(
        receiptSettings,
      )..where((r) => r.id.equals(existing.id))).write(
        ReceiptSettingsCompanion(
          companyName: companyName != null
              ? Value(companyName)
              : const Value.absent(),
          companyAddress: companyAddress != null
              ? Value(companyAddress)
              : const Value.absent(),
          companyPhone: companyPhone != null
              ? Value(companyPhone)
              : const Value.absent(),
          companyPhone2: companyPhone2 != null
              ? Value(companyPhone2)
              : const Value.absent(),
          companyEmail: companyEmail != null
              ? Value(companyEmail)
              : const Value.absent(),
          taxNumber: taxNumber != null
              ? Value(taxNumber)
              : const Value.absent(),
          headerText: headerText != null
              ? Value(headerText)
              : const Value.absent(),
          footerText: footerText != null
              ? Value(footerText)
              : const Value.absent(),
          termsText: termsText != null
              ? Value(termsText)
              : const Value.absent(),
          logoImage: logoImage != null
              ? Value(logoImage)
              : const Value.absent(),
          showLogo: showLogo != null ? Value(showLogo) : const Value.absent(),
          showQrCode: showQrCode != null
              ? Value(showQrCode)
              : const Value.absent(),
          showBarcode: showBarcode != null
              ? Value(showBarcode)
              : const Value.absent(),
          showTaxDetails: showTaxDetails != null
              ? Value(showTaxDetails)
              : const Value.absent(),
          showItemCode: showItemCode != null
              ? Value(showItemCode)
              : const Value.absent(),
          showSalesperson: showSalesperson != null
              ? Value(showSalesperson)
              : const Value.absent(),
          showCustomerInfo: showCustomerInfo != null
              ? Value(showCustomerInfo)
              : const Value.absent(),
          headerFontSize: headerFontSize != null
              ? Value(headerFontSize)
              : const Value.absent(),
          bodyFontSize: bodyFontSize != null
              ? Value(bodyFontSize)
              : const Value.absent(),
          footerFontSize: footerFontSize != null
              ? Value(footerFontSize)
              : const Value.absent(),
          paperWidth: paperWidth != null
              ? Value(paperWidth)
              : const Value.absent(),
          currencySymbol: currencySymbol != null
              ? Value(currencySymbol)
              : const Value.absent(),
          updatedAt: Value(DateTime.now()),
        ),
      );
    } else {
      await into(receiptSettings).insert(
        ReceiptSettingsCompanion.insert(
          companyName: Value(companyName ?? 'اسم الشركة'),
          companyAddress: Value(companyAddress),
          companyPhone: Value(companyPhone),
          companyPhone2: Value(companyPhone2),
          companyEmail: Value(companyEmail),
          taxNumber: Value(taxNumber),
          headerText: Value(headerText ?? 'مرحباً بكم'),
          footerText: Value(footerText ?? 'شكراً لزيارتكم'),
          termsText: Value(termsText),
          showLogo: Value(showLogo ?? false),
          showQrCode: Value(showQrCode ?? true),
          showBarcode: Value(showBarcode ?? false),
          showTaxDetails: Value(showTaxDetails ?? true),
          showItemCode: Value(showItemCode ?? false),
          showSalesperson: Value(showSalesperson ?? true),
          showCustomerInfo: Value(showCustomerInfo ?? true),
          headerFontSize: Value(headerFontSize ?? 14),
          bodyFontSize: Value(bodyFontSize ?? 10),
          footerFontSize: Value(footerFontSize ?? 9),
          paperWidth: Value(paperWidth ?? 80),
          currencySymbol: Value(currencySymbol ?? 'JOD'),
        ),
      );
    }
  }

  /// Get receipt settings as map for invoice generator
  Future<Map<String, dynamic>> getReceiptSettingsMap() async {
    final rs = await getReceiptSettings();
    return {
      'companyName': rs.companyName,
      'companyAddress': rs.companyAddress,
      'companyPhone': rs.companyPhone,
      'companyPhone2': rs.companyPhone2,
      'companyEmail': rs.companyEmail,
      'taxNumber': rs.taxNumber,
      'headerText': rs.headerText,
      'footerText': rs.footerText,
      'termsText': rs.termsText,
      'logoImage': rs.logoImage,
      'showLogo': rs.showLogo,
      'showQrCode': rs.showQrCode,
      'showBarcode': rs.showBarcode,
      'showTaxDetails': rs.showTaxDetails,
      'showItemCode': rs.showItemCode,
      'showSalesperson': rs.showSalesperson,
      'showCustomerInfo': rs.showCustomerInfo,
      'headerFontSize': rs.headerFontSize,
      'bodyFontSize': rs.bodyFontSize,
      'footerFontSize': rs.footerFontSize,
      'paperWidth': rs.paperWidth,
      'currencySymbol': rs.currencySymbol,
    };
  }
}
