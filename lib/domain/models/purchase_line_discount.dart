// توزيعُ خصم فاتورة المشتريات على سطورها — **قاعدةٌ واحدةٌ بلا حالاتٍ خاصّة.**
//
// ═══ لماذا وُجدت ═══
//
// قرارُ المالك 2026-09-18 على تصميم فاتورة المشتريات: الخصمُ **لكلّ صنف**
// (يُثبَّت، لا مفتاح). وكان للفاتورة خصمٌ واحدٌ على المستند يوزّعه المحرّكُ
// **نسبةً إلى قيمة كلّ سطر** قبل أن يصل السطرَ المخزَّنَ وحركةَ المخزون
// ومتوسّطَ التكلفة.
//
// و`PurchaseInvoiceItems.discount` عمودٌ قائمٌ **بلا كاتب** — وله **قارئ**:
// `getPurchaseReturnItemDetails` يقسّطه بنسبة المرتجَع ويطبعه على مستند
// المرتجع. فهو يطبع صفراً دائماً منذ وُجد.
//
// ═══ القاعدة ═══
//
//   ‏١) خصمُ السطر الصريحُ يُطرَح أوّلاً.
//   ‏٢) وما بقي من خصم المستند يُوزَّع **نسبةً إلى ما بقي من قيمة السطور**.
//
// وهي قاعدةٌ واحدةٌ تغطّي الحالات الثلاث بلا فرعٍ خاصّ:
//   • بلا خصومِ سطورٍ ⇒ الباقي هو الخصمُ كلُّه والقاعدةُ تُنتج **عينَ**
//     التوزيع النسبيّ القديم حرفاً. وهذا شرطُ ألّا يتغيّر رقمٌ في فاتورةٍ
//     قديمةٍ أو في إعادةِ صندوقٍ صادرٍ أو مزامنة.
//   • بخصومٍ مجموعُها خصمُ المستند ⇒ الباقي صفرٌ وكلُّ سطرٍ يأخذ ما كُتب له.
//   • وبينهما ⇒ الصريحُ أوّلاً ثمّ الباقي على الجميع.
//
// ⚠️ 🔴 **والخصمُ يصل التكلفةَ مرّةً واحدةً بالضبط.** لو حُمل السطرُ خصمَه
// الصريحَ **و** ضُرب في معامل التوزيع لطُبِّق مرّتَين — وتكلفةٌ أقلُّ من
// الحقيقة تُضخّم الربحَ في كلّ بيعةٍ تاليةٍ من هذا الصنف، وتجعل مرتجعاً
// يردّ أقلَّ ممّا دُفع. ولهذا يُطرَح الصريحُ من الأساس **قبل** حساب المعامل.
//
// ⚠️ **والنتيجةُ قيمةُ السطر لا سعرُ الوحدة.** القسمةُ على الكمّيّة تقع عند
// المنادي، لأنّ كمّيّةَ صفرٍ حالةٌ يحرسها هو (سطرٌ فارغ) ولا معنى لقسمةٍ
// عليها هنا.

import 'dart:math' as math;

/// قيمُ السطور **بعد** الخصم — بنفس ترتيب [grossPerLine].
///
/// [explicitDiscountPerLine] بنفس الطول؛ صفرٌ يعني «لا خصمَ صريحٌ لهذا
/// السطر» فيأخذ حصّتَه من الباقي وحدَها.
List<double> resolvePurchaseLineNets({
  required List<double> grossPerLine,
  required List<double> explicitDiscountPerLine,
  required double documentDiscount,
}) {
  assert(grossPerLine.length == explicitDiscountPerLine.length);
  if (grossPerLine.isEmpty) return const [];

  final afterExplicit = <double>[
    for (var i = 0; i < grossPerLine.length; i++)
      math.max(0.0, grossPerLine[i] - math.max(0.0, explicitDiscountPerLine[i])),
  ];
  final explicitSum = explicitDiscountPerLine.fold<double>(
      0, (a, d) => a + math.max(0.0, d));

  final residual = math.max(0.0, documentDiscount - explicitSum);
  final base = afterExplicit.fold<double>(0, (a, v) => a + v);
  if (residual <= 0 || base <= 0) return afterExplicit;

  // المعاملُ لا ينزل تحت الصفر: خصمٌ أكبرُ من الباقي يُصفِّر السطورَ ولا
  // يقلبها سالبةً — والحارسُ على «الخصم > الإجمالي» يقع عند المنادي.
  final factor = math.max(0.0, (base - residual) / base);
  return [for (final v in afterExplicit) v * factor];
}

/// عكسُ [resolvePurchaseLineNets] — الإجماليُّ من الصافي المخزَّن.
///
/// ═══ لماذا وُجدت ═══
///
/// المحرّكُ يخزّن تكلفةَ السطر **صافيةً** بعد توزيع الخصم، ويستقبل من
/// النموذج تكلفةً **إجماليّةً** وخصمَ مستندٍ يوزّعه بنفسه. فشاشةُ التحرير
/// التي تملأ حقولَها من المخزَّن حرفاً تعطيه صافياً وتقول له «وزّع» —
/// **فيوزّع مرّةً ثانية**.
///
/// 🔴 **وكلُّ حفظٍ يخفّض التكلفة ثانيةً** ولو لم يُغيَّر حرف: ١٠٠ ← ٩٠ ←
/// ٨١ ← … ولا يظهر على الشاشة، إنّما في **متوسّط تكلفة الصنف** — فيُضخَّم
/// الربحُ في كلّ بيعةٍ تالية، ويردّ المرتجعُ أقلَّ ممّا دُفع.
///
/// ═══ والاشتقاق ═══
///
/// في الاتّجاه الأمام: `net_i = afterExplicit_i × (base − R) / base` حيث
/// `base = Σ afterExplicit` و`R` الباقي من خصم المستند. ومنه:
///
///     Σnet = base − R           ⇒  base = Σnet + R
///     afterExplicit_i = net_i × base / (base − R) = net_i × (Σnet + R) / Σnet
///     gross_i         = afterExplicit_i + explicit_i
///
/// فالعكسُ **دقيقٌ** لا تقريبيّ: الدورةُ تُعيد نفسَ الأرقام حرفاً.
///
/// ⚠️ **وصافٍ مجموعُه صفرٌ لا يُعكَس**: خصمٌ استوعب القيمةَ كلَّها يمحو
/// النِّسَبَ التي تُبنى عليها القسمة. فتُعاد الأصفارُ مضافاً إليها الصريحُ —
/// وهو أقربُ ما يمكن بناؤه بلا اختراع.
List<double> resolvePurchaseLineGross({
  required List<double> netPerLine,
  required List<double> explicitDiscountPerLine,
  required double documentDiscount,
}) {
  assert(netPerLine.length == explicitDiscountPerLine.length);
  if (netPerLine.isEmpty) return const [];

  final explicitSum = explicitDiscountPerLine.fold<double>(
      0, (a, d) => a + math.max(0.0, d));
  final residual = math.max(0.0, documentDiscount - explicitSum);
  final netSum = netPerLine.fold<double>(0, (a, v) => a + v);

  if (residual <= 0 || netSum <= 0) {
    return [
      for (var i = 0; i < netPerLine.length; i++)
        netPerLine[i] + math.max(0.0, explicitDiscountPerLine[i]),
    ];
  }

  final expand = (netSum + residual) / netSum;
  return [
    for (var i = 0; i < netPerLine.length; i++)
      netPerLine[i] * expand + math.max(0.0, explicitDiscountPerLine[i]),
  ];
}
