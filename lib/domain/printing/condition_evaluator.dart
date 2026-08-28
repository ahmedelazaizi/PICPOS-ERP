/// تقييمُ شروطِ الإظهار — `field op value` وحدَها.
///
/// ── لماذا لا مفسِّرَ تعابيرَ كامل ─────────────────────────────────────────
/// المطلوبُ من الشروط في القوالب حالةٌ واحدةٌ متكرّرة: «أظهرْ سطرَ الخصم إن
/// كان الخصمُ أكبرَ من صفر». والمفسِّرُ الكاملُ يجرّ أولويّاتِ عمليّاتٍ
/// وأقواساً ودوالَّ — سطحُ عطبٍ واسعٌ لعائدٍ معدوم.
///
/// ── القاعدةُ الحاكمة: الغموضُ يُظهِر لا يُخفي ─────────────────────────────
/// أيُّ شرطٍ لا يُفهَم — حقلٌ مجهول، عاملٌ غريب، صيغةٌ مكسورة — **يُظهِر**
/// العنصر. لأنّ العطبَ الظاهرَ يُبلَّغ عنه في دقيقة، والعطبَ المخفيَّ يحذف
/// سطرَ الخصم من فواتيرِ شهرٍ كاملٍ ولا يشكو أحد.
///
/// هذا الملفُّ نقيّ: لا `package:pdf` ولا `package:flutter`.
library;

/// العواملُ الستّة — **الأطولُ أوّلاً**.
///
/// الترتيبُ ليس تجميليّاً: قراءةُ `>` قبل `>=` تقصّ `tax >= 0` عند `>`
/// فتصير القيمةُ «= 0» ولا تُقارَن أبداً.
const _operators = <String>['>=', '<=', '==', '!=', '>', '<'];

/// يُقيِّم [condition] على [values].
///
/// الشرطُ الفارغُ أو `null` يعني «يظهر دائماً».
bool evaluateCondition(String? condition, Map<String, String> values) {
  final expr = condition?.trim() ?? '';
  if (expr.isEmpty) return true;

  for (final op in _operators) {
    final at = expr.indexOf(op);
    if (at <= 0) continue;

    final field = expr.substring(0, at).trim();
    // لا تُقصّ القيمةُ عند أوّل مسافة — «مدينة نصر» اسمٌ مركَّبٌ مشروع.
    final rhs = expr.substring(at + op.length).trim();
    if (field.isEmpty || rhs.isEmpty) return true;

    // حقلٌ مجهول ⇒ أظهِر. الغيابُ خطأُ إملاءٍ غالباً لا نيّةَ إخفاء.
    if (!values.containsKey(field)) return true;
    final lhs = values[field] ?? '';

    return _compare(lhs, op, rhs);
  }

  // بلا عاملٍ معروف ⇒ أظهِر.
  return true;
}

bool _compare(String lhs, String op, String rhs) {
  // الحقلُ الفارغُ صفرٌ في المقارنة الرقميّة — «بلا خصم» و«خصمٌ صفر» سواء.
  final left = lhs.trim().isEmpty ? 0.0 : double.tryParse(lhs.trim());
  final right = double.tryParse(rhs);

  final numeric = left != null && right != null;

  switch (op) {
    case '==':
      return numeric ? left == right : lhs.trim() == rhs;
    case '!=':
      return numeric ? left != right : lhs.trim() != rhs;
    case '>':
      return numeric ? left > right : true;
    case '<':
      return numeric ? left < right : true;
    case '>=':
      return numeric ? left >= right : true;
    case '<=':
      return numeric ? left <= right : true;
  }
  return true;
}
