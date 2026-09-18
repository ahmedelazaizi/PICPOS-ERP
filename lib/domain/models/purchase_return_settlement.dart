// تسويةُ مردود المشتريات مع المورّد — **قسمةٌ واحدةٌ يقرؤها الجميع.**
//
// ═══ لماذا دالّةٌ لا خمسُ نسخ ═══
//
// مردودُ الشراء يُسوَّى على رِجلَين: ما يُخصَم من **ذمّة المورّد** (بقدر ما
// نَدينُ له فعلاً) والباقي **نقداً يُستردّ منه**. والقسمةُ صيغةٌ واحدةٌ كانت
// مكتوبةً بيدها في **خمسة مواضع**:
//
//   • `processPurchaseReturn` — مسارُ العميل ومسارُ الخادم (موضعان)
//   • `_reversePurchaseReturn` — عكسُ التعديل
//   • `postPurchaseReturn` و`postPurchaseReturnEdit` في معالج الـAPI
//
// وكانت الواجهةُ ستصير **سادسةً**: قرارُ المالك 2026-09-18 أنّ «طريقة
// التسوية» **مرآةٌ مشتقّةٌ لا قائمةُ اختيار** — فالشاشةُ تعرض ما سيفعله
// المحرّك، لا ما يختاره المستخدم.
//
// 🔴 **ومرآةٌ تحسب بنفسها ليست مرآة.** لو انحرفت نسخةُ الواجهة عن المحرّك
// بمقدارٍ واحدٍ لعرضت «الرصيد بعد التسوية» رقماً لا يقع — والمستخدمُ يعتمده
// في قرارِ سدادٍ. وهي بعينها عائلةُ عطبِ [kInvestingJeReferenceTypes]:
// طرفان يقرآن ويكتبان ولا يعرف أحدُهما الآخر.
//
// ⚠️ **والحسابُ بالإجماليّ (شامل الضريبة)**: رصيدُ المورّد مخزَّنٌ إجماليّاً،
// فقسمةُ الصافي وحدَه كانت ستترك الضريبةَ بلا رِجْلٍ تحملها.
//
// وهذا **توأمُ** `sales_return_refund_split.dart` في جانب المبيعات — وُجد
// قبله بنفس العلّة المكتوبةِ في رأسه حرفاً: «نسختان تُجيبان سؤالاً واحداً
// وتنحرفان يوماً». فالنمطُ عرفُ البيت لا اختراعاً هنا. ويفترقان في الجوهر:
// هناك ثلاثُ رِجْلٍ (ذمّةٌ · نقدٌ · بنك) لأنّ الصرفَ للعميل يخرج من درجٍ أو
// حسابٍ بنكيّ، وهنا رِجلان لأنّ المورّدَ هو من يردّ.

/// قسمةُ مردودٍ بين ذمّة المورّد والنقد.
class PurchaseReturnSettlement {
  const PurchaseReturnSettlement({
    required this.gross,
    required this.apPortion,
    required this.cashPortion,
    required this.remainingBefore,
  });

  /// قيمةُ المردود شاملةً الضريبة.
  final double gross;

  /// ما يُخصَم من ذمّة المورّد — لا يتجاوز المستحقَّ عليها.
  final double apPortion;

  /// ما يُستردُّ نقداً — الباقي بعد خصم الذمّة.
  final double cashPortion;

  /// المستحقُّ للمورّد على هذه الفاتورة **قبل** المردود.
  final double remainingBefore;

  /// المستحقُّ بعد التسوية.
  double get remainingAfter => remainingBefore - apPortion;

  /// هل تمسّ التسويةُ الذمّةَ أصلاً؟
  bool get touchesPayable => apPortion > 0;

  /// هل يُستردُّ نقدٌ؟
  bool get touchesCash => cashPortion > 0;

  /// وصفُ الطريقة بالعربيّة — **مشتقٌّ من الأرقام لا مُختارٌ من قائمة**.
  ///
  /// والحالاتُ ثلاثٌ لا اثنتان: فاتورةٌ مسدَّدةٌ جزئيّاً يتجاوز مردودُها
  /// المتبقّيَ عليها تُسوَّى **بالرِّجلَين معاً**.
  String get methodLabel {
    if (touchesPayable && touchesCash) {
      return 'تخفيض ذمة المورد + استرداد نقدي';
    }
    if (touchesPayable) return 'تخفيض ذمة المورد';
    if (touchesCash) return 'استرداد نقدي';
    return 'لا تسوية';
  }
}

/// يقسم مردوداً قيمتُه [returnNet] + [returnVat] على فاتورةٍ إجماليُّها
/// [invoiceTotal] سُدِّد منها [invoicePaid].
///
/// ⚠️ **و`clamp` على الطرفَين مقصود:** فاتورةٌ سُدِّد منها أكثرُ من إجماليّها
/// (‏دفعةٌ زائدةٌ أو صفٌّ قديم) تعطي متبقّياً سالباً، وضربُه في القسمة كان
/// يجعل `apPortion` سالبةً فتُزاد ذمّةُ المورّد بمردود.
PurchaseReturnSettlement resolvePurchaseReturnSettlement({
  required double returnNet,
  required double returnVat,
  required double invoiceTotal,
  required double invoicePaid,
}) {
  final gross = returnNet + returnVat;
  final remaining =
      (invoiceTotal - invoicePaid).clamp(0.0, double.infinity).toDouble();
  final ap = remaining > 0 ? gross.clamp(0.0, remaining).toDouble() : 0.0;
  return PurchaseReturnSettlement(
    gross: gross,
    apPortion: ap,
    cashPortion: gross - ap,
    remainingBefore: remaining,
  );
}
