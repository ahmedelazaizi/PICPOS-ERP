
abstract class ISettingsRepository {
  /// Get current settings from database
  Future<Map<String, String>> getAllSettings();

  /// Get specific setting value
  Future<String?> getSetting(String key);

  /// Save a setting
  Future<void> saveSetting(String key, String value);

  /// Save company information
  Future<void> saveCompanyInfo({
    required String name,
    String? phone,
    String? address,
    String? taxId,
  });

  /// Get available backups
  Future<List<String>> getAvailableBackups();

  /// Create a new backup
  Future<String?> createBackup();

  /// Get backup statistics
  Future<Map<String, dynamic>> getBackupStats();

  /// Export backup to a folder
  Future<bool> exportBackup(String destinationFolder);

  /// Delete a backup file
  Future<bool> deleteBackup(String path);

  /// Restore from backup
  Future<bool> restoreBackup(String path);

  /// Get receipt settings
  Future<Map<String, dynamic>> getReceiptSettings();

  /// Save receipt settings
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
    dynamic logoImage, // Can be Uint8List
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
  });

  /// Watch receipt settings
  Stream<dynamic> watchReceiptSettings();

  /// Watch setting value
  Stream<String?> watchSettingValue(String key);
}
