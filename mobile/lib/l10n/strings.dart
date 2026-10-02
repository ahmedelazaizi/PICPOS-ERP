import 'package:flutter/widgets.dart';

/// Arabic (default) + English strings. Small, explicit table; moves to ARB /
/// gen-l10n when the string set grows (I-2).
class S {
  S(this.locale);
  final Locale locale;
  bool get isAr => locale.languageCode == 'ar';

  static S of(BuildContext context) => S(Localizations.localeOf(context));

  static const supported = [Locale('ar'), Locale('en')];

  static const Map<String, (String, String)> _t = {
    'appTitle': ('بيك بوس - المندوب', 'PicPos Van'),
    'pairTitle': ('ربط الجهاز', 'Pair this device'),
    'serverUrl': ('عنوان الخادم', 'Server address'),
    'pairingCode': ('رمز الربط', 'Pairing code'),
    'pair': ('ربط', 'Pair'),
    'loginTitle': ('دخول المندوب', 'Rep sign-in'),
    'pin': ('الرمز السري', 'PIN'),
    'login': ('دخول', 'Sign in'),
    'todayRoute': ('خط اليوم', "Today's route"),
    'vanStock': ('مخزون السيارة', 'Van stock'),
    'sync': ('المزامنة', 'Sync'),
    'visited': ('تمت الزيارة', 'Visited'),
    'notVisited': ('لم تتم الزيارة', 'Not visited'),
    'balance': ('الرصيد', 'Balance'),
    'creditLimit': ('الحد الائتماني', 'Credit limit'),
    'noLimit': ('بلا حد', 'No limit'),
    'available': ('المتاح', 'Available'),
    'newSale': ('فاتورة بيع', 'New sale'),
    'collect': ('سند قبض', 'Collect'),
    'scanBarcode': ('امسح أو اكتب الباركود', 'Scan or type barcode'),
    'add': ('إضافة', 'Add'),
    'cart': ('السلة', 'Cart'),
    'emptyCart': ('السلة فارغة. امسح صنفاً أو اختره من القائمة.', 'Cart is empty. Scan an item or pick it from the list.'),
    'subtotal': ('المجموع', 'Subtotal'),
    'tax': ('الضريبة', 'Tax'),
    'total': ('الإجمالي', 'Total'),
    'cash': ('نقدي', 'Cash'),
    'credit': ('آجل', 'Credit'),
    'collectNow': ('المبلغ المقبوض الآن', 'Collected now'),
    'remaining': ('المتبقي', 'Remaining'),
    'save': ('حفظ', 'Save'),
    'amount': ('المبلغ', 'Amount'),
    'voucherBook': ('دفتر السندات', 'Voucher book'),
    'leafNumber': ('رقم السند', 'Voucher number'),
    'pending': ('بانتظار الإرسال', 'Pending'),
    'accepted': ('مقبول', 'Accepted'),
    'rejected': ('مرفوض', 'Rejected'),
    'syncNow': ('زامن الآن', 'Sync now'),
    'lastSync': ('آخر مزامنة', 'Last sync'),
    'never': ('لم تتم بعد', 'Never'),
    'saved': ('تم الحفظ في قائمة الإرسال', 'Saved to the outbox'),
    'insufficientStock': ('الكمية غير متوفرة في السيارة', 'Not enough stock in the van'),
    'creditExceeded': ('يتجاوز الحد الائتماني للعميل', "Exceeds the customer's credit limit"),
    'unknownBarcode': ('لا يوجد صنف بهذا الباركود', 'No item with this barcode'),
    'noNumbers': ('لا توجد أرقام فواتير متاحة. زامن أولاً.', 'No invoice numbers left. Sync first.'),
    'noBook': ('لا يوجد دفتر سندات مسلّم لك', 'No voucher book assigned to you'),
    'leafInvalid': ('رقم السند غير صالح لهذا الدفتر', 'Voucher number is not valid for this book'),
    'pendingNote': ('يشمل المستندات غير المُرسلة', 'Includes unsent documents'),
    'outbox': ('قائمة الإرسال', 'Outbox'),
    'nothingPending': ('لا توجد مستندات معلّقة', 'Nothing pending'),
    'quantity': ('الكمية', 'Qty'),
    'language': ('English', 'العربية'),
    'invalidPin': ('الرمز السري غير صحيح', 'Incorrect PIN'),
    'error': ('تعذّر الاتصال بالخادم', 'Could not reach the server'),
  };

  String t(String key) {
    final v = _t[key];
    if (v == null) return key;
    return isAr ? v.$1 : v.$2;
  }
}
