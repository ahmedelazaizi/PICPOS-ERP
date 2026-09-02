/// حلُّ رمز الإيصال من القاعدة — يُطعم القرارَ الخالصَ في `domain/models`.
///
/// الرايةُ من `Settings` (بلا سرّ، وتُزامَن) وصفُّ التقديم من
/// `e_invoice_submissions` (يُزامَن منذ v173 ويحمل `qrCode` الذي أصدرته
/// البوّابة). فكلُّ ما يحتاجه الكاشير لطباعة الرمز الصحيح يصله بالسحب —
/// و`EInvoiceConfigs` بسرّها تبقى على الخادم.
///
/// والقراءةُ **لا متزامنة** (`getSettingValue`) لا عبر الكاش المتزامن، فلا
/// تحتاج مفتاحاً في `preloadKeys` ولا تموت صامتةً إن نُسي.
library;

import '../../domain/models/receipt_qr_decision.dart';
import '../database/database.dart';

/// يقرّر ما يُطبع على إيصال البيعة [saleId].
///
/// غيابُ الراية = غيرُ مُفعَّل: منشأةٌ لم تفتح الميزةَ قطُّ لا تكتبها أبداً،
/// ولها الرمزُ البديلُ عن الورق. والنافذةُ بين تفعيل الخادم ووصول الراية
/// بأوّل سحبٍ نافذةُ المزامنة نفسِها.
Future<ReceiptQr> resolveReceiptQrForSale(
  AppDatabase db, {
  required int saleId,
  required ReceiptSaleSummary sale,
}) async {
  final enabled =
      await db.getSettingValue(kEInvoiceEnabledSettingKey) == 'true';

  // غيرُ مُفعَّل ⇒ القرارُ لا يقرأ التقديمَ أصلاً، فلا نستعلم عنه.
  final submission = enabled ? await db.getSubmissionBySaleId(saleId) : null;

  return resolveReceiptQr(
    eInvoiceEnabled: enabled,
    submissionStatus: submission?.status,
    gatewayQrCode: submission?.qrCode,
    sale: sale,
  );
}

/// يقرّر ما يُطبع على **فاتورةٍ مبدئيّةٍ** — مستندٍ ليس بيعةً بعد.
///
/// فاتورةُ الطاولة تُطبع قبل السداد ولا صفَّ بيعٍ لها، فلا معرّفَ تُسأل به عن
/// تقديم — ولذلك لا `saleId` في التوقيع.
///
/// ⚠️ وكانت تُطبع **رقمَ الفاتورة بلا وسم**: رمزٌ يبدو إيصالاً على ورقةٍ
/// مكتوبٌ عليها «ليست إيصالَ سداد». والنتيجةُ هنا:
///   • جهازٌ غيرُ مُفعَّل ⇒ رمزٌ غيرُ ضريبيٍّ **موسوم**.
///   • جهازٌ مُفعَّل ⇒ **لا رمزَ إطلاقاً** — لا مستندَ ضريبيَّ لمبدئيّة،
///     والثابتُ الأمنيُّ يمنع غيرَ الضريبيّ على جهازٍ مسجَّل.
Future<ReceiptQr> resolveReceiptQrForProforma(
  AppDatabase db, {
  required ReceiptSaleSummary sale,
}) async {
  final enabled =
      await db.getSettingValue(kEInvoiceEnabledSettingKey) == 'true';

  return resolveReceiptQr(
    eInvoiceEnabled: enabled,
    submissionStatus: null,
    gatewayQrCode: null,
    sale: sale,
  );
}
