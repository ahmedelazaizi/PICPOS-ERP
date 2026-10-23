import 'package:picpos_erp/core/i18n/tr.dart';
import 'package:flutter/material.dart';
import '../config/brand.dart';

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
  static Map<String, Map<String, String>> get _localizedValues => {
    'ar': {
      'app_name': Brand.nameAr,
      'dashboard': tr('لوحة التحكم'),
      'products': tr('الأصناف'),
      'sales': tr('المبيعات'),
      'purchases': tr('المشتريات'),
      'reports': tr('التقارير'),
      'settings': tr('الإعدادات'),
      'customers': tr('العملاء'),
      'suppliers': tr('الموردين'),
      'inventory': tr('المخزون'),
      'invoices': tr('الفواتير'),
      'search': tr('بحث...'),
      'save': tr('حفظ'),
      'cancel': tr('إلغاء'),
      'delete': tr('حذف'),
      'edit': tr('تعديل'),
      'add': tr('إضافة'),
      'export': tr('تصدير'),
      'import': tr('استيراد'),
      'print': tr('طباعة'),
      'ok': tr('موافق'),
      'yes': tr('نعم'),
      'no': tr('لا'),
      'total': tr('الإجمالي'),
      'currency': tr('ج.م'),
      'loading': tr('جاري التحميل...'),
      'error': tr('خطأ'),
      'success': tr('تم بنجاح'),
      'no_data': tr('لا توجد بيانات'),
      'logout': tr('تسجيل خروج'),
      'login': tr('تسجيل دخول'),
      'backup': tr('نسخة احتياطية'),
      'restore': tr('استعادة'),
    },
    'en': {
      'app_name': Brand.name,
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
