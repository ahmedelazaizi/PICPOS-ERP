/// البند 4 (متطلبات العميل 2026-07-25) — سلّم نسب الضريبة المسموح بها للأصناف.
///
/// The product tax field was a bare `TextField` with no validator, no input
/// formatter and no range check, backed by a plain REAL column with no CHECK —
/// and there was no guard in the DAO, the server API or the Excel importer
/// either. `37.5`, `999` and even `-16` persisted verbatim; a negative rate
/// then generated negative VAT on every sale and purchase line of that item.
///
/// The ladder is CONFIGURABLE on purpose. This product already ships two
/// e-invoicing integrations (ETA/Egypt at 14%, JoFotara/Jordan at 16%), so
/// hard-coding one country's ladder would be wrong for the next tenant. The
/// default is the ladder the customer supplied; a deployment can override it
/// through the `allowed_product_tax_rates` setting (comma-separated).
///
/// NOT covered here — «معفي» (exempt) vs «صفري» (zero-rated) are both stored as
/// rate `0` and are indistinguishable numerically, though they are reported
/// differently on a VAT return. Telling them apart needs a `taxSubtypeCode`
/// column on products; that is a schema change and is deliberately left out.
library;

import 'package:flutter/foundation.dart' show visibleForTesting;

class TaxRatePolicy {
  const TaxRatePolicy._();

  /// المفتاح الذي يقرأ منه النظام سلّماً مخصّصاً (قيم مفصولة بفواصل).
  static const settingKey = 'allowed_product_tax_rates';

  /// السلّم القانوني كما ورد من العميل: معفي/صفر · 1 · 2 · 4 · 5 · 10 · 16.
  /// («معفي» يُخزَّن كـ 0 — انظر ملاحظة الصنف أعلاه.)
  ///
  /// قرارُ المالك: أُضيفت **14 و15** ليصحّ في كلّ مكانٍ (‏API · استيراد Excel ·
  /// حوار الصنف) أيُّ معدّلٍ يختاره معالجُ الإعداد: 0 · 1 · 2 · 4 · 5 · 10 ·
  /// 14 · 15 · 16.
  static const List<double> defaultAllowedRates = [0, 1, 2, 4, 5, 10, 14, 15, 16];

  /// السلّم المضبوط للتركيب الحالي، أو `null` قبل قراءة الإعدادات.
  ///
  /// ── ليه حالة ساكنة؟ ──────────────────────────────────────────────────
  /// السلّم كان **إعداداً ميتاً**: `settingKey` و[parseAllowedRates] موجودين
  /// من أول يوم، لكن ولا موضع في المشروع كان بينادي [parseAllowedRates] ولا
  /// بيمرّر `allowed:`. فتركيب ظابط سلّم مخصّص (مصر ١٤٪ مثلاً) كان النظام
  /// بيتجاهله بالكامل ويرفض ١٤٪ من الفورم ومن الاستيراد ومن الـ API.
  ///
  /// التوصيل عبر المُعاملات كان معناه تمرير السلّم في كل مسار كتابة —
  /// و`ExcelService` مثلاً مالوش وصول للإعدادات أصلاً (مفيش settings repo في
  /// مُنشئه)، فكان لازم يتغيّر مُنشئه وكل مواضع بنائه. السلّم إعداد على مستوى
  /// التركيب زيّه زي `AppConfig.features`، فحالة ساكنة تُكتب مرة عند الإقلاع
  /// هي نفس الشكل المستخدم في المشروع أصلاً.
  ///
  /// **كاتب واحد فقط:** [configureFromSetting] عند الإقلاع (و[resetForTests]
  /// في الاختبارات). متكتبهاش من أي مكان تاني.
  static List<double>? _configured;

  /// السلّم الفعّال — المضبوط إن وُجد، وإلا الافتراضي.
  static List<double> get activeRates => _configured ?? defaultAllowedRates;

  /// يضبط السلّم من القيمة النصية المحفوظة في الإعدادات (قيم مفصولة بفواصل).
  static void configureFromSetting(String? raw) {
    _configured = parseAllowedRates(raw);
  }

  @visibleForTesting
  static void resetForTests() => _configured = null;

  /// هامش يستوعب فروق الفاصلة العائمة دون قبول انحراف حقيقي.
  static const double _epsilon = 1e-6;

  static bool isAllowed(num rate, {List<double>? allowed}) {
    final ladder = allowed ?? activeRates;
    final value = rate.toDouble();
    if (value < 0) return false;
    return ladder.any((r) => (r - value).abs() < _epsilon);
  }

  /// يرمي [ArgumentError] برسالة عربية تذكر النسبة المرفوضة والسلّم المسموح.
  static void assertAllowed(num rate, {List<double>? allowed}) {
    if (isAllowed(rate, allowed: allowed)) return;
    final ladder = allowed ?? activeRates;
    throw ArgumentError(
      'نسبة الضريبة "${_fmt(rate.toDouble())}" غير مسموح بها. '
      'النسب المتاحة: ${ladder.map(_fmt).join('٪، ')}٪ (و«معفي» = 0٪).',
    );
  }

  /// يقرأ سلّماً من إعداد نصّي. القيم المشوَّهة تُتجاهل فرادى؛ وإعداد فارغ أو
  /// فاسد بالكامل يرجع للسلّم الافتراضي بدل ترك النظام بلا سلّم إطلاقاً.
  static List<double> parseAllowedRates(String? raw) {
    if (raw == null || raw.trim().isEmpty) return defaultAllowedRates;
    final parsed = raw
        .split(',')
        .map((s) => double.tryParse(s.trim()))
        .whereType<double>()
        .where((v) => v >= 0)
        .toList();
    if (parsed.isEmpty) return defaultAllowedRates;
    return parsed;
  }

  static String _fmt(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();
}
