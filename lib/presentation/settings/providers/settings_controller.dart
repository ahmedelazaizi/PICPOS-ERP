import 'package:picpos_erp/core/i18n/tr.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/logging/app_logger.dart';
import '../../../data/providers/repository_providers.dart';
import '../../../domain/repositories/settings_repository.dart';
import '../../../data/providers/auth_providers.dart';
import '../../../data/providers/audit_providers.dart';

/// Settings screen state
class SettingsState {
  final bool isLoading;
  final String? error;
  final String? successMessage;
  final List<String> availableBackups;
  final String? companyName;
  final String? companyPhone;
  final String? companyAddress;
  final String? companyTaxId;
  final bool isDarkMode;
  final String language;
  final Map<String, dynamic> receiptSettings;

  const SettingsState({
    this.isLoading = false,
    this.error,
    this.successMessage,
    this.availableBackups = const [],
    this.companyName,
    this.companyPhone,
    this.companyAddress,
    this.companyTaxId,
    this.isDarkMode = false,
    this.language = 'ar',
    this.receiptSettings = const {},
  });

  SettingsState copyWith({
    bool? isLoading,
    String? error,
    String? successMessage,
    List<String>? availableBackups,
    String? companyName,
    String? companyPhone,
    String? companyAddress,
    String? companyTaxId,
    bool? isDarkMode,
    String? language,
    Map<String, dynamic>? receiptSettings,
  }) {
    return SettingsState(
      isLoading: isLoading ?? this.isLoading,
      error: error,
      successMessage: successMessage,
      availableBackups: availableBackups ?? this.availableBackups,
      companyName: companyName ?? this.companyName,
      companyPhone: companyPhone ?? this.companyPhone,
      companyAddress: companyAddress ?? this.companyAddress,
      companyTaxId: companyTaxId ?? this.companyTaxId,
      isDarkMode: isDarkMode ?? this.isDarkMode,
      language: language ?? this.language,
      receiptSettings: receiptSettings ?? this.receiptSettings,
    );
  }
}

/// Settings Controller - Riverpod 3.x Notifier pattern
class SettingsController extends Notifier<SettingsState> {
  late final ISettingsRepository _repository;

  @override
  SettingsState build() {
    _repository = ref.watch(settingsRepositoryProvider);
    // Load settings asynchronously after build
    Future.microtask(() => _loadSettings());
    return const SettingsState();
  }

  /// Load settings from repository
  Future<void> _loadSettings() async {
    try {
      state = state.copyWith(isLoading: true);

      final settings = await _repository.getAllSettings();

      state = state.copyWith(
        isLoading: false,
        companyName: settings['companyName'],
        companyPhone: settings['companyPhone'],
        companyAddress: settings['companyAddress'],
        companyTaxId: settings['companyTaxId'],
        isDarkMode: settings['isDarkMode'] == 'true',
        language: settings['language'] ?? 'ar',
      );

      await _loadBackups();
      logger.info('Settings loaded', correlationId: 'SETTINGS');
    } catch (e, stack) {
      logger.error('Failed to load settings', e, stack, 'SETTINGS');
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  /// Load available backups
  Future<void> _loadBackups() async {
    if (kIsWeb) return;
    try {
      final backups = await _repository.getAvailableBackups();
      state = state.copyWith(availableBackups: backups);
    } catch (e) {
      logger.error('Failed to load backups', e, null, 'SETTINGS');
    }
  }

  /// Save company information
  Future<bool> saveCompanyInfo({
    required String name,
    String? phone,
    String? address,
    String? taxId,
  }) async {
    try {
      state = state.copyWith(isLoading: true);

      await _repository.saveCompanyInfo(
        name: name,
        phone: phone,
        address: address,
        taxId: taxId,
      );

      state = state.copyWith(
        isLoading: false,
        companyName: name,
        companyPhone: phone,
        companyAddress: address,
        companyTaxId: taxId,
        successMessage: tr('تم حفظ بيانات الشركة بنجاح'),
      );

      return true;
    } catch (e, stack) {
      logger.error('Failed to save company info', e, stack, 'SETTINGS');
      state = state.copyWith(isLoading: false, error: e.toString());
      return false;
    }
  }

  /// Load receipt settings
  Future<void> loadReceiptSettings() async {
    try {
      state = state.copyWith(isLoading: true);
      final settings = await _repository.getReceiptSettings();
      state = state.copyWith(isLoading: false, receiptSettings: settings);
    } catch (e, stack) {
      logger.error('Failed to load receipt settings', e, stack, 'SETTINGS');
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  /// Save receipt settings
  Future<bool> saveReceiptSettings(Map<String, dynamic> settings) async {
    try {
      state = state.copyWith(isLoading: true);
      await _repository.saveReceiptSettings(
        companyName: settings['companyName'],
        companyAddress: settings['companyAddress'],
        companyPhone: settings['companyPhone'],
        companyPhone2: settings['companyPhone2'],
        companyEmail: settings['companyEmail'],
        taxNumber: settings['taxNumber'],
        headerText: settings['headerText'],
        footerText: settings['footerText'],
        termsText: settings['termsText'],
        logoImage: settings['logoImage'],
        showLogo: settings['showLogo'],
        showQrCode: settings['showQrCode'],
        showBarcode: settings['showBarcode'],
        showTaxDetails: settings['showTaxDetails'],
        showItemCode: settings['showItemCode'],
        showSalesperson: settings['showSalesperson'],
        showCustomerInfo: settings['showCustomerInfo'],
        headerFontSize: settings['headerFontSize'],
        bodyFontSize: settings['bodyFontSize'],
        footerFontSize: settings['footerFontSize'],
        paperWidth: settings['paperWidth'],
        currencySymbol: settings['currencySymbol'],
      );

      state = state.copyWith(
        isLoading: false,
        receiptSettings: settings,
        successMessage: tr('تم حفظ إعدادات الإيصال بنجاح'),
      );
      return true;
    } catch (e, stack) {
      logger.error('Failed to save receipt settings', e, stack, 'SETTINGS');
      state = state.copyWith(isLoading: false, error: e.toString());
      return false;
    }
  }

  /// Create database backup
  Future<String?> createBackup() async {
    if (kIsWeb) return null;
    final path = await _repository.createBackup();
    if (path != null) {
      await _loadBackups();
      
      final user = ref.read(authProvider).user;
      if (user != null) {
        await ref.read(activityLoggerProvider).logBackup(
          user.id,
          user.displayName,
          path,
        );
      }
    }
    return path;
  }

  /// Restore database from backup
  Future<bool> restoreBackup(String backupPath) async {
    try {
      state = state.copyWith(isLoading: true);
      final success = await _repository.restoreBackup(backupPath);
      
      if (!success) {
        state = state.copyWith(isLoading: false, error: tr('فشل استعادة النسخة الاحتياطية'));
        return false;
      }

      logger.info(
        'Database restored from: $backupPath',
        correlationId: 'SETTINGS',
      );
      
      final user = ref.read(authProvider).user;
      if (user != null) {
        await ref.read(activityLoggerProvider).logRestore(
          user.id,
          user.displayName,
          backupPath,
        );
      }
      state = state.copyWith(
        isLoading: false,
        successMessage: tr('تم استعادة النسخة الاحتياطية بنجاح'),
      );
      return true;
    } catch (e, stack) {
      logger.error('Failed to restore backup', e, stack, 'SETTINGS');
      state = state.copyWith(isLoading: false, error: e.toString());
      return false;
    }
  }

  /// Get backup statistics
  Future<Map<String, dynamic>> getBackupStats() async {
    try {
      return await _repository.getBackupStats();
    } catch (e) {
      return {'count': 0, 'totalSize': 0, 'lastBackup': null};
    }
  }

  /// Export backup
  Future<bool> exportBackup(String destinationFolder) async {
    try {
      state = state.copyWith(isLoading: true);
      final success = await _repository.exportBackup(destinationFolder);
      state = state.copyWith(
        isLoading: false,
        successMessage: success ? tr('تم تصدير النسخة الاحتياطية بنجاح') : tr('فشل تصدير النسخة الاحتياطية'),
      );
      return success;
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
      return false;
    }
  }

  /// Delete backup
  Future<bool> deleteBackup(String path) async {
    try {
      state = state.copyWith(isLoading: true);
      final success = await _repository.deleteBackup(path);
      if (success) {
        await _loadBackups();
      }
      state = state.copyWith(
        isLoading: false,
        successMessage: success ? tr('تم حذف النسخة الاحتياطية بنجاح') : tr('فشل حذف النسخة الاحتياطية'),
      );
      return success;
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
      return false;
    }
  }

  /// Toggle dark mode
  Future<void> toggleDarkMode(bool enabled) async {
    await _repository.saveSetting('isDarkMode', enabled.toString());
    state = state.copyWith(isDarkMode: enabled);
    logger.debug('Dark mode: $enabled', correlationId: 'SETTINGS');
  }

  /// Set language
  Future<void> setLanguage(String language) async {
    await _repository.saveSetting('language', language);
    state = state.copyWith(language: language);
    logger.debug('Language set: $language', correlationId: 'SETTINGS');
  }

  /// Clear error/success messages
  void clearMessages() {
    state = state.copyWith(error: null, successMessage: null);
  }

  /// Get role label in Arabic
  String getRoleLabel(String role) {
    switch (role) {
      case 'admin':
        return tr('مدير');
      case 'manager':
        return tr('مشرف');
      case 'cashier':
        return tr('كاشير');
      default:
        return role;
    }
  }
}

/// Settings Controller Provider - Riverpod 3.x NotifierProvider
final settingsControllerProvider =
    NotifierProvider<SettingsController, SettingsState>(SettingsController.new);
