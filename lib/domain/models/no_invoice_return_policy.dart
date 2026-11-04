// سياسةُ «المرتجع السريع بلا فاتورة» — سقفُ قيمةِ الاسترداد النقديّ.
//
// ── لماذا ملفٌّ مستقلّ لا صفٌّ في `kQuickSaleRows` ──────────────────────────
// `quick_sale_policy.dart` عند سقفِ حجمه المسجَّل في `file_size_baseline.txt`
// ولا يقبل سطراً إضافياً، وإضافةُ صفٍّ لـ`kQuickSaleRows` تكسر أيضاً عدَّ الصفوف
// المثبَّت في `quick_sale_policy_test` وحارسَ «كلُّ صفٍّ منفَّذٍ له قارئ». فالمفتاحُ
// هنا مستقلٌّ، يُقرأ من نفس خريطة القاعدة (`QuickSalePolicyValues.raw`) ويُعرَض
// في شاشة «إعدادات البيع السريع» ببطاقةٍ خاصّةٍ بخطوة «الدفع».
//
// ── القرار ──────────────────────────────────────────────────────────────────
// مرتجعٌ بلا فاتورةٍ باب احتيالٍ (إرجاعُ صنفٍ لم يُشترَ من الفرع)، فالاستردادُ
// نقداً فقط، وفوقَ السقف **لا يُرفَض صامتاً بل يحتاج موافقةَ مسؤول** بآلية
// `requestManagerApproval` القائمة نفسِها (كخصمِ ما فوق `disccap`).

import 'quick_sale_policy.dart';

/// مفتاحُ القاعدة.
const String kNoInvoiceReturnCapKey = 'pos_no_invoice_return_cap';

/// القيمةُ الافتراضيّة (بالعملة المحلّية). **افتراضٌ مسجَّل**: ٥٠٠ — أقلُّ من
/// حدّ «تأكيد مدير للمبالغ فوق» الافتراضيّ (٥٬٠٠٠)، لأنّ المرتجعَ بلا فاتورةٍ
/// أحوجُ للحذر من البيع. وتُعدَّل من إعدادات البيع السريع.
const double kNoInvoiceReturnCapDefault = 500;

/// أقصى ما يعرضه المنزلقُ في الشاشة.
const double kNoInvoiceReturnCapSliderMax = 5000;

/// خطوةُ المنزلق.
const double kNoInvoiceReturnCapStep = 50;

/// سقفُ قيمةِ المرتجع بلا فاتورة. صفرٌ مسموحٌ ومعناه «كلُّ مرتجعٍ يحتاج مسؤولاً».
///
/// ⚠️ الفاسدُ (ليس رقماً · سالب · لا نهائي) يعود **للافتراض** لا لـ«بلا حدّ»:
/// إخفاقُ القراءة يجب ألّا يفتح البابَ الأخطر.
double noInvoiceReturnCap(QuickSalePolicyValues values) {
  final parsed = double.tryParse(values.raw[kNoInvoiceReturnCapKey] ?? '');
  if (parsed == null || parsed.isNaN || parsed.isInfinite || parsed < 0) {
    return kNoInvoiceReturnCapDefault;
  }
  return parsed;
}

/// ما يُكتب في القاعدة لقيمةِ السقف.
Map<String, String> writeNoInvoiceReturnCap(double value) =>
    {kNoInvoiceReturnCapKey: value.toString()};

/// حكمُ السقف على قيمةِ مرتجعٍ بلا فاتورة.
enum NoInvoiceReturnVerdict {
  /// داخلَ السقف (المساواةُ مسموحة) — يمضي دون سؤال.
  withinCap,

  /// فوقَ السقف — لا يُحفَظ إلّا بموافقةِ مسؤول.
  needsManager,
}

NoInvoiceReturnVerdict judgeNoInvoiceReturn({
  required double returnValue,
  required double cap,
}) =>
    returnValue <= cap + 0.0001
        ? NoInvoiceReturnVerdict.withinCap
        : NoInvoiceReturnVerdict.needsManager;
