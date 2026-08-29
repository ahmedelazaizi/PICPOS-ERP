/// توافقُ عرضِ القالب مع عرضِ الطابعة.
///
/// ── العطبُ الذي يعالجه ───────────────────────────────────────────────────
/// قالبُ A4 على طابعةٍ ٨٠مم **يُقصّ صامتاً**: لا رسالةَ ولا سجلّ، فقط نصفُ
/// فاتورةٍ يخرج من الطابعة. والمستخدمُ لا يربط القالبَ الخطأ عمداً — بل يختار
/// من قائمةٍ لا تقول له إنّ العرضين لا يلتقيان.
///
/// نقيّ: لا `package:pdf` ولا `package:flutter`.
library;

/// تسامحٌ بالمليمتر بين عرض الورق وعرض المساحة المطبوعة.
///
/// طابعةُ ٨٠مم مساحتُها المطبوعةُ ٧٢مم شائعاً، وطابعةُ ٥٨مم نحوَ ٤٨. فالفرقُ
/// الصغيرُ ليس عدمَ توافق، وتشديدُه يرفض تركيباتٍ تعمل يوميّاً.
const double paperFitToleranceMm = 3.0;

enum PaperFit {
  /// العرضان متوافقان.
  ok,

  /// القالبُ أضيقُ من الطابعة — يطبع كاملاً بهامشٍ أبيض.
  narrower,

  /// القالبُ أعرضُ من الطابعة — **يفقد بياناً**.
  tooWide,
}

class PaperFitVerdict {
  final PaperFit fit;
  final String reason;

  const PaperFitVerdict(this.fit, this.reason);

  bool get isOk => fit == PaperFit.ok;
  bool get isWarning => fit == PaperFit.narrower;
  bool get isRejected => fit == PaperFit.tooWide;
}

/// يفحص قالباً بعرض [templateWidthMm] على طابعةٍ بعرض [printerWidthMm].
///
/// [printerWidthMm] فارغاً أو صفراً يعني طابعةً لم يُسجَّل عرضُها — وهي ليست
/// طابعةً غيرَ متوافقة. المنعُ على المجهول يقفل الربطَ على كلِّ طابعةٍ لم
/// تُعرَّف بعد.
PaperFitVerdict checkPaperFit({
  required double templateWidthMm,
  double? printerWidthMm,
}) {
  if (printerWidthMm == null || printerWidthMm <= 0) {
    return const PaperFitVerdict(PaperFit.ok, '');
  }

  final delta = templateWidthMm - printerWidthMm;

  if (delta.abs() <= paperFitToleranceMm) {
    return const PaperFitVerdict(PaperFit.ok, '');
  }

  // الأعرضُ يفقد بياناً — وعمودُ الإجمالي آخرُ ما يُقصّ، فيخرج المطبوعُ
  // صحيحَ الشكل ناقصَ الرقم.
  if (delta > 0) {
    return PaperFitVerdict(
      PaperFit.tooWide,
      'عرضُ القالب ${_n(templateWidthMm)}مم أكبرُ من عرض الطابعة '
      '${_n(printerWidthMm)}مم — سيُقصّ المطبوعُ من الحافّة، وعمودُ الإجمالي '
      'أوّلُ ما يضيع.',
    );
  }

  // الأضيقُ يطبع كاملاً — قبحٌ لا فقدُ بيان، فيُحذَّر ولا يُمنع.
  return PaperFitVerdict(
    PaperFit.narrower,
    'عرضُ القالب ${_n(templateWidthMm)}مم أصغرُ من عرض الطابعة '
    '${_n(printerWidthMm)}مم — سيُطبع كاملاً بهامشٍ أبيضَ على الجانب.',
  );
}

/// يحذف الصفرَ العشريَّ الزائد: ٢١٠.٠ ⇒ ٢١٠.
String _n(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
