// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Arabic (`ar`).
class AppLocalizationsAr extends AppLocalizations {
  AppLocalizationsAr([String locale = 'ar']) : super(locale);

  @override
  String get treasuryManagement => 'إدارة الخزينة';

  @override
  String get totalTreasuryBalance => 'إجمالي رصيد الخزائن';

  @override
  String get receiptVoucher => 'سند قبض';

  @override
  String get paymentVoucher => 'سند صرف';

  @override
  String get cashSafes => 'الخزائن النقدية';

  @override
  String get bankAccounts => 'الحسابات البنكية';

  @override
  String get dailyClosing => 'الإقفال اليومي';

  @override
  String get noBankAccounts => 'لا توجد حسابات بنكية';

  @override
  String get recentTransactions => 'آخر الحركات';

  @override
  String get noTransactions => 'لا توجد حركات';

  @override
  String get defaultSafe => 'الخزينة الافتراضية';

  @override
  String get cash => 'نقدي';

  @override
  String get bank => 'بنكي';

  @override
  String get customerPayment => 'تحصيل من عميل';

  @override
  String get supplierPayment => 'سداد لمورد';

  @override
  String get sales => 'مبيعات';

  @override
  String get purchase => 'مشتريات';

  @override
  String get expense => 'مصروفات';

  @override
  String get salary => 'رواتب';

  @override
  String get advance => 'سلفة';

  @override
  String get loan => 'قرض';

  @override
  String get other => 'أخرى';

  @override
  String get resetBalances => 'تصفير أرصدة الخزائن وترحيل الأرباح';

  @override
  String get close => 'إقفال';

  @override
  String dailyClosingTitle(Object safeName) {
    return 'إقفال يومي - $safeName';
  }

  @override
  String get confirmClosing => 'هل أنت متأكد من رغبتك في إقفال الخزينة؟';

  @override
  String closingWarning(Object balance) {
    return 'هذا الإجراء سيقوم بتصفير الرصيد الحالي ($balance JOD) وبداية فترة جديدة.';
  }

  @override
  String get closingNote =>
      'ملاحظة: سيتم تسجيل كافة الحركات السابقة في التقارير ولن تُحذف.';

  @override
  String get cancel => 'إلغاء';

  @override
  String get confirmCloseAndReset => 'إقفال وتصفير الرصيد';

  @override
  String closingSuccess(Object safeName) {
    return 'تم إقفال الخزينة $safeName بنجاح';
  }

  @override
  String get enterValidAmount => 'يرجى إدخال مبلغ صحيح';

  @override
  String get selectSupplier => 'يرجى اختيار المورد';

  @override
  String get paymentVoucherCreated => 'تم إنشاء سند الصرف';

  @override
  String get save => 'حفظ';

  @override
  String get voucherType => 'نوع السند';

  @override
  String get category => 'التصنيف';

  @override
  String get amount => 'المبلغ';

  @override
  String get description => 'البيان (اختياري)';

  @override
  String get party => 'الجهة (عميل/مورد)';

  @override
  String get safe => 'الخزينة';
}
