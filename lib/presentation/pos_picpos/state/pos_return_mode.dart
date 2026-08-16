import '../../../domain/models/return_refund_calculator.dart';
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

  /// إجماليُّ الفاتورة الأصليّة (`SalesInvoiceData.total`) — أساسُ عامل
  /// التوزيع في [refundTotal]. `null` لاختباراتٍ لا تُعنى بالاسترداد؛
  /// عندها يُشتقّ افتراضياً من مجموع `ReturnableLine.effectiveLineTotal`
  /// (فيصير العاملُ ١، أي بلا تعديل) — راجع [refundTotal].
  final double? invoiceTotal;

  /// رسمُ التوصيل على الفاتورة الأصليّة (`SalesInvoiceData.deliveryFee`) —
  /// يُوزَّع نسبياً على المرتجع الجزئيّ في [refundTotal] (B2).
  final double invoiceDeliveryFee;

  PosReturnMode._({
    required this.invoiceId,
    required this.linesByItemId,
    required this.requestedQty,
    required this.invoiceTotal,
    required this.invoiceDeliveryFee,
  });

  /// يبني حالةً جديدةً من سطور الفاتورة القابلة للإرجاع. الكميّاتُ المطلوبةُ
  /// تبدأ كلُّها صفراً — قرارُ مالكٍ صريح: البدءُ بالكامل يُغري بحفظٍ سريعٍ
  /// يُرجع ما لم يُحضره العميل.
  ///
  /// [invoiceTotal] و[invoiceDeliveryFee] اختياريّان (‏`_showQuickReturn`
  /// يمرّرهما دوماً من ترويسة الفاتورة) كي لا تنكسر اختباراتٌ قديمةٌ لا
  /// تُعنى بحساب [refundTotal].
  factory PosReturnMode.fromLines({
    required int invoiceId,
    required List<ReturnableLine> lines,
    double? invoiceTotal,
    double invoiceDeliveryFee = 0,
  }) {
    return PosReturnMode._(
      invoiceId: invoiceId,
      linesByItemId: {for (final l in lines) l.invoiceItemId: l},
      requestedQty: {for (final l in lines) l.invoiceItemId: 0},
      invoiceTotal: invoiceTotal,
      invoiceDeliveryFee: invoiceDeliveryFee,
    );
  }

  /// مبلغُ الاسترداد الفعليّ لطلب المرتجع الحاليّ (‏[requestedQty]) — نفسُ
  /// صيغة `ReturnsRepositoryImpl._calculateReturnTotal` بالحرف عبر
  /// [calculateReturnRefundTotal] المشتركة، لا `Σ qty × unitPrice` (سعرُ ما
  /// قبل الضريبة وقبل خصم السطر). العطبُ المقيسُ في مراجعة 2026-08-16: كان
  /// المعروضُ يقلّ عمّا يخرج من الدرج فعلياً بمقدار الضريبة (ويزيد مع خصم
  /// سطر) — فائضٌ صامتٌ في الدرج يُقيَّد لاحقاً «فائضَ نقدية».
  double get refundTotal => calculateReturnRefundTotal(
        lines: [
          for (final l in linesByItemId.values)
            (id: l.invoiceItemId, quantity: l.soldQty, lineTotal: l.effectiveLineTotal),
        ],
        invoiceTotal: invoiceTotal ?? _sumEffectiveLineTotals,
        invoiceDeliveryFee: invoiceDeliveryFee,
        returnQuantities: requestedQty,
      );

  double get _sumEffectiveLineTotals =>
      linesByItemId.values.fold(0.0, (sum, l) => sum + l.effectiveLineTotal);

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

  /// يُفرغ سطراً واحداً من طلب الإرجاع (يُعيده صفراً) — الطريقُ الصريحُ
  /// الوحيدُ لاستبعاد صنفٍ من مرتجعٍ افتراضيّه الكاملُ (مهمّةُ الواجهة تبني
  /// [PosReturnMode] بكامل الكمياتِ المتاحة ثم قد تستبعد سطراً بعينه).
  ///
  /// لا يمرّ بـ[setQty] لأن الأخيرة ترفض ٠ **دوماً** (‏`isReturnRequestValid`
  /// تشترط `> 0`)، وهذا تصفيرٌ متعمَّدٌ لا طلبَ إرجاعٍ غيرَ صالح — الفرقُ بين
  /// «الكاشير يستبعد صنفاً» و«الكاشير طلب كميةً غيرَ مقبولة».
  ///
  /// `itemId` غيرُ الموجود في الفاتورة: لا أثر (لا استثناء) — نفسُ سلوكِ
  /// [setQty] حين يرفض صنفاً خارجَ الفاتورة.
  void clearQty(int itemId) {
    if (!linesByItemId.containsKey(itemId)) return;
    requestedQty[itemId] = 0;
  }
}
