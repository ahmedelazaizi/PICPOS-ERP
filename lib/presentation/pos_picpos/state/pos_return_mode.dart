import '../../../domain/models/returnable_line.dart';

/// حالةُ وضع المرتجع في سلّة PicPos — الأقفالُ الأربعة (§٥ من المواصفة):
/// السعرُ مقفول (‏[unitPriceOf])، الكميةُ مسقوفة (‏[setQty])، لا أصنافَ خارجَ
/// الفاتورة (‏[canAcceptProduct])، وترويسةٌ حمراءُ ظاهرة (‏مهمّةُ الواجهة
/// اللاحقة تقرأ `PosReturnMode? != null` لعرضها).
///
/// خالصةٌ عمداً: لا تستورد `data/database` ولا Riverpod — حارسُ
/// `presentation_db_import_guard` يمنع أيَّ ملفِّ عرضٍ **جديد** من استيراد
/// القاعدة. `invoiceId` رقمٌ لا كائنَ صفٍّ `SalesInvoiceData`.
class PosReturnMode {
  final int invoiceId;
  final Map<int, ReturnableLine> linesByItemId;
  final Map<int, double> requestedQty;

  PosReturnMode._({
    required this.invoiceId,
    required this.linesByItemId,
    required this.requestedQty,
  });

  /// يبني حالةً جديدةً من سطور الفاتورة القابلة للإرجاع. الكميّاتُ المطلوبةُ
  /// تبدأ كلُّها صفراً — قرارُ مالكٍ صريح: البدءُ بالكامل يُغري بحفظٍ سريعٍ
  /// يُرجع ما لم يُحضره العميل.
  factory PosReturnMode.fromLines({
    required int invoiceId,
    required List<ReturnableLine> lines,
  }) {
    return PosReturnMode._(
      invoiceId: invoiceId,
      linesByItemId: {for (final l in lines) l.invoiceItemId: l},
      requestedQty: {for (final l in lines) l.invoiceItemId: 0},
    );
  }

  /// قفلٌ: لا صنفَ خارجَ الفاتورة الأصليّة — `false` لأيّ `productId` لم
  /// يَرِد في سطورها.
  bool canAcceptProduct(int productId) =>
      linesByItemId.values.any((line) => line.productId == productId);

  /// قفلٌ: الكميةُ مسقوفةٌ بالمتبقّي غيرِ المُشبَّع — التحقّقُ عبر
  /// `ReturnableLine.isReturnRequestValid` حرفياً (لا مقارنةً مباشرةً
  /// بـ`availableQty`، فالفرقُ بينهما مقصودٌ: الأخيرة قيمةُ عرضٍ مُشبَّعة
  /// عند الصفر، والتحقّقُ يطابق ما يقبله المستودعُ عند الحفظ).
  ///
  /// يرجع `true` عند القبول وتُحدَّث `requestedQty`. يرجع `false` عند
  /// الرفض مع إبقاء القيمة القديمة كما هي — لا تصفيرَ ولا تشبيع.
  bool setQty(int itemId, double qty) {
    final line = linesByItemId[itemId];
    if (line == null) return false;
    if (!line.isReturnRequestValid(qty)) return false;
    requestedQty[itemId] = qty;
    return true;
  }

  /// قفلٌ: السعرُ من الفاتورة الأصليّة لا من شاشة الأصناف الحاليّة.
  double unitPriceOf(int itemId) => linesByItemId[itemId]!.unitPrice;
}
