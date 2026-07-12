import 'package:flutter/material.dart';

/// B5 — i18n support scaffold.
/// Provides locale switching infrastructure.
/// Phase 1: Arabic only (default). Phase 2: English translations.
class AppLocalizations {
  final Locale locale;

  AppLocalizations(this.locale);

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations) ??
        AppLocalizations(const Locale('ar'));
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  static const List<Locale> supportedLocales = [
    Locale('ar'),
    Locale('en'),
  ];

  /// Translation map — extend with full translations in Phase 2
  static final Map<String, Map<String, String>> _localizedValues = {
    'ar': {
      'app_name': 'يورال كاش',
      'dashboard': 'لوحة التحكم',
      'products': 'الأصناف',
      'sales': 'المبيعات',
      'purchases': 'المشتريات',
      'reports': 'التقارير',
      'settings': 'الإعدادات',
      'customers': 'العملاء',
      'suppliers': 'الموردين',
      'inventory': 'المخزون',
      'invoices': 'الفواتير',
      'search': 'بحث...',
      'save': 'حفظ',
      'cancel': 'إلغاء',
      'delete': 'حذف',
      'edit': 'تعديل',
      'add': 'إضافة',
      'export': 'تصدير',
      'import': 'استيراد',
      'print': 'طباعة',
      'ok': 'موافق',
      'yes': 'نعم',
      'no': 'لا',
      'total': 'الإجمالي',
      'currency': 'ج.م',
      'loading': 'جاري التحميل...',
      'error': 'خطأ',
      'success': 'تم بنجاح',
      'no_data': 'لا توجد بيانات',
      'logout': 'تسجيل خروج',
      'login': 'تسجيل دخول',
      'backup': 'نسخة احتياطية',
      'restore': 'استعادة',
    },
    'en': {
      'app_name': 'UralCash',
      'dashboard': 'Dashboard',
      'products': 'Products',
      'sales': 'Sales',
      'purchases': 'Purchases',
      'reports': 'Reports',
      'settings': 'Settings',
      'customers': 'Customers',
      'suppliers': 'Suppliers',
      'inventory': 'Inventory',
      'invoices': 'Invoices',
      'search': 'Search...',
      'save': 'Save',
      'cancel': 'Cancel',
      'delete': 'Delete',
      'edit': 'Edit',
      'add': 'Add',
      'export': 'Export',
      'import': 'Import',
      'print': 'Print',
      'ok': 'OK',
      'yes': 'Yes',
      'no': 'No',
      'total': 'Total',
      'currency': 'EGP',
      'loading': 'Loading...',
      'error': 'Error',
      'success': 'Success',
      'no_data': 'No data available',
      'logout': 'Logout',
      'login': 'Login',
      'backup': 'Backup',
      'restore': 'Restore',
    },
  };

  String translate(String key) {
    return _localizedValues[locale.languageCode]?[key] ??
        _localizedValues['ar']?[key] ??
        key;
  }

  /// Short alias for translate
  String t(String key) => translate(key);

  bool get isArabic => locale.languageCode == 'ar';
  bool get isEnglish => locale.languageCode == 'en';
  TextDirection get textDirection =>
      isArabic ? TextDirection.rtl : TextDirection.ltr;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) =>
      AppLocalizations.supportedLocales.any((l) => l.languageCode == locale.languageCode);

  @override
  Future<AppLocalizations> load(Locale locale) async {
    return AppLocalizations(locale);
  }

  @override
  bool shouldReload(covariant LocalizationsDelegate<AppLocalizations> old) => false;
}
