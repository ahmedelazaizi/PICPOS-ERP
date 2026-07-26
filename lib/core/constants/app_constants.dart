import '../config/brand.dart';

/// Application-wide constants
class AppConstants {
  AppConstants._();

  // App Info — ISS-CODE-02: populated at startup by AppVersionService.initialize()
  //
  // الاسم بيجي من [Brand] عشان يفضل مصدر واحد للحقيقة عبر المنتجات
  // المستقلة. بيفضل `const` — ده شرط، مش تفضيل: قيم الهوية مستخدمة جوّه
  // سياقات `const` في مئات المواضع.
  static const String appName = Brand.name;
  static String appVersion = '1.0.0'; // updated from pubspec via package_info_plus
  static String appBuildNumber = '1'; // updated from pubspec via package_info_plus

  // Database
  static const String databaseName = '${Brand.dbPrefix}.db';
  static const int databaseVersion = 1;

  // Pagination
  static const int defaultPageSize = 50;
  static const int maxPageSize = 200;

  // Financial
  static const int decimalPlaces = 3;
  // Currency fields — mutable, set from settings on app startup
  static String currencySymbol = 'د.أ';
  static String currencySymbolAr = 'د.أ';
  static String currencySymbolEn = 'JOD';
  static String currencyNameAr = 'دينار أردني';
  static String currencyCode = 'JOD';

  /// Set the active currency from a currency code ('JOD' or 'EGP')
  static void setCurrency(String code) {
    final info = CurrencyInfo.fromCode(code);
    currencySymbol = info.symbolAr;
    currencySymbolAr = info.symbolAr;
    currencySymbolEn = info.code;
    currencyNameAr = info.nameAr;
    currencyCode = info.code;
  }

  // Invoices
  static const String salesInvoicePrefix = 'INV';
  static const String purchaseInvoicePrefix = 'PUR';
  static const String returnInvoicePrefix = 'RET';
  static const String paymentVoucherPrefix = 'PAY';
  static const String receiptVoucherPrefix = 'REC';

  // Stock
  static const int lowStockWarningDays = 30;
  static const int expiryWarningDays = 30;

  // Date/Time formats
  static const String dateFormat = 'yyyy-MM-dd';
  static const String timeFormat = 'HH:mm:ss';
  static const String dateTimeFormat = 'yyyy-MM-dd HH:mm:ss';
  static const String displayDateFormat = 'dd/MM/yyyy';
  static const String displayTimeFormat = 'hh:mm a';

  // Thermal Printer
  static const int thermalPaperWidth = 80; // mm
  static const int thermalCharsPerLine = 48;

  // Scale
  static const int scaleDefaultBaudRate = 9600;
  static const int scaleReadTimeoutMs = 300;

  // Session
  static const int sessionTimeoutMinutes = 480; // 8 hours

  // Limits
  static const int maxCartItems = 100;
  static const double maxDiscountPercent = 100.0;
  static const double minTransactionAmount = 0.01;

  // B4: Return reason categories
  static const List<String> returnReasonCategories = [
    'تالف',
    'خطأ في الطلب',
    'تغيير رأي العميل',
    'انتهاء الصلاحية',
    'عيب مصنعي',
    'أخرى',
  ];
}

/// Role constants
class UserRoles {
  UserRoles._();

  static const String admin = 'admin';
  static const String manager = 'manager';
  static const String cashier = 'cashier';

  static const List<String> all = [admin, manager, cashier];
}

/// Transaction types
class TransactionTypes {
  TransactionTypes._();

  static const String sale = 'sale';
  static const String purchase = 'purchase';
  static const String saleReturn = 'sale_return';
  static const String purchaseReturn = 'purchase_return';
  static const String payment = 'payment';
  static const String receipt = 'receipt';
  static const String adjustment = 'adjustment';
  static const String transfer = 'transfer';
}

/// Invoice statuses
class InvoiceStatus {
  InvoiceStatus._();

  static const String draft = 'draft';
  static const String pending = 'pending';
  static const String partial = 'partial';
  static const String paid = 'paid';
  static const String cancelled = 'cancelled';
}

/// Stock movement types
class StockMovementTypes {
  StockMovementTypes._();

  static const String purchase = 'purchase';
  static const String sale = 'sale';
  static const String returnIn = 'return';
  static const String adjustment = 'adjustment';
  static const String transfer = 'transfer';
  static const String waste = 'waste';
}

/// Currency configuration info
class CurrencyInfo {
  final String code;
  final String symbolAr;
  final String nameAr;

  const CurrencyInfo({
    required this.code,
    required this.symbolAr,
    required this.nameAr,
  });

  static const CurrencyInfo jod = CurrencyInfo(
    code: 'JOD',
    symbolAr: 'د.أ',
    nameAr: 'دينار أردني',
  );
  static const CurrencyInfo egp = CurrencyInfo(
    code: 'EGP',
    symbolAr: 'ج.م',
    nameAr: 'جنيه مصري',
  );

  static const List<CurrencyInfo> all = [jod, egp];

  static CurrencyInfo fromCode(String code) {
    switch (code.toUpperCase()) {
      case 'EGP':
        return egp;
      case 'JOD':
      default:
        return jod;
    }
  }
}
