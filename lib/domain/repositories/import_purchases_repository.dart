import '../../data/database/database.dart'
    show ImportPurchaseRow, ImportPurchaseDetailData;
import '../models/import_purchase_plan.dart';

/// قراءةُ وسمِ الاستيراد وتحريرُه — **بلا إنشاء**.
///
/// 🔴 **ولا دالّةَ إنشاءٍ هنا عمداً.** الوسمُ يُولَد مع الفاتورة داخلَ
/// معاملتها (`CreatePurchaseInvoiceParams.importDetails`)، وبابٌ ثانٍ
/// لإنشائه كان يحوّل فاتورةً محلّيّةً إلى خارجيّةٍ بعد أن رُحِّلت — تصنيفٌ
/// يتبدّل من الخلف، وتقاريرُ الاستيراد تختلف عن نفسها بين شهرَين.
abstract class ImportPurchasesRepository {
  /// صفوفُ شاشة المشتريات الخارجيّة.
  Future<List<ImportPurchaseRow>> getRows({int limit});

  /// وسمُ فاتورةٍ بعينها، أو `null` إن كانت محلّيّة.
  Future<ImportPurchaseDetailData?> getForInvoice(int purchaseInvoiceId);

  /// تحريرُ الحقول المستنديّة لفاتورةٍ **موسومةٍ سلفاً**.
  Future<void> updateDetails({
    required int purchaseInvoiceId,
    required ImportDocumentFields fields,
  });
}
