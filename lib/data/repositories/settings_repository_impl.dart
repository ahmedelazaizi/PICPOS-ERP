import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../database/database.dart';
import '../database/connection_io.dart';
import '../../domain/repositories/settings_repository.dart';
import 'base_repository.dart';

class SettingsRepositoryImpl extends BaseRepository<Setting> implements ISettingsRepository {
  SettingsRepositoryImpl(super.db);

  @override
  Stream<List<Setting>> watchAll() => db.select(db.settings).watch();

  @override
  Future<Setting?> getById(int id) async => null; // Settings use String keys

  @override
  Future<Map<String, String>> getAllSettings() async {
    final settingsArr = await db.getAllSettings();
    return {for (var s in settingsArr) s.key: s.value ?? ''};
  }

  @override
  Future<String?> getSetting(String key) {
    return db.getSettingValue(key);
  }

  @override
  Future<void> saveSetting(String key, String value) {
    return db.setSetting(key, value);
  }

  @override
  Future<void> saveCompanyInfo({
    required String name,
    String? phone,
    String? address,
    String? taxId,
  }) async {
    await db.setSetting('companyName', name);
    if (phone != null) await db.setSetting('companyPhone', phone);
    if (address != null) await db.setSetting('companyAddress', address);
    if (taxId != null) await db.setSetting('companyTaxId', taxId);
  }

  @override
  Future<List<String>> getAvailableBackups() async {
    if (kIsWeb) return [];
    final entities = await listBackups();
    return entities.map((e) => e.path).toList();
  }

  @override
  Future<String?> createBackup() async {
    if (kIsWeb) return null;
    return createDatabaseBackup();
  }

  @override
  Future<Map<String, dynamic>> getBackupStats() async {
    if (kIsWeb) return {'count': 0, 'totalSize': 0, 'lastBackup': null};
    return getBackupStats(); // Use the one from connection_io.dart
  }

  @override
  Future<bool> exportBackup(String destinationFolder) async {
    if (kIsWeb) return false;
    return exportBackupToPath(destinationFolder);
  }

  @override
  Future<bool> deleteBackup(String path) async {
    if (kIsWeb) return false;
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  @override
  Future<bool> restoreBackup(String path) async {
    if (kIsWeb) return false;
    return restoreDatabaseBackup(path);
  }

  @override
  Future<Map<String, dynamic>> getReceiptSettings() {
    return db.getReceiptSettingsMap();
  }

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
  }) {
    return db.saveReceiptSettings(
      companyName: companyName,
      companyAddress: companyAddress,
      companyPhone: companyPhone,
      companyPhone2: companyPhone2,
      companyEmail: companyEmail,
      taxNumber: taxNumber,
      headerText: headerText,
      footerText: footerText,
      termsText: termsText,
      logoImage: logoImage,
      showLogo: showLogo,
      showQrCode: showQrCode,
      showBarcode: showBarcode,
      showTaxDetails: showTaxDetails,
      showItemCode: showItemCode,
      showSalesperson: showSalesperson,
      showCustomerInfo: showCustomerInfo,
      headerFontSize: headerFontSize,
      bodyFontSize: bodyFontSize,
      footerFontSize: footerFontSize,
      paperWidth: paperWidth,
      currencySymbol: currencySymbol,
    );
  }

  @override
  Stream<dynamic> watchReceiptSettings() {
    return db.watchReceiptSettings();
  }

  @override
  Stream<String?> watchSettingValue(String key) {
    return db.watchSettingValue(key);
  }
}
