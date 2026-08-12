/// قراءةُ أعلام إعدادات جدول الأصناف المخزَّنة JSON في `columnWidths`.
///
/// ── لماذا مِقبضٌ مشترك ────────────────────────────────────────────────────
/// ثلاثةُ قرّاءٍ يفكّون نفسَ النصّ: محرّرُ القوالب (ليرسم الرقاقات)،
/// وحوارُ المعاينة، و`TemplatedInvoiceService` (ما يصل الورق). وكلُّهم كان
/// يكتب `value as bool?` — وهي رميةٌ لا قراءة: قيمةٌ مخزَّنةٌ `1` أو
/// `"true"` ترمي `TypeError`.
///
/// والأسوأ أن `try` في المعاينة والطابعة يلفّ **الحلقةَ كلَّها**، فتُبتلع
/// الرميةُ وتضيع معها عروضُ الأعمدة والدقّةُ وكلُّ الأعلام دفعةً واحدة —
/// فيرى المستخدمُ تصميمَه مسطَّحاً بلا رسالةِ خطأٍ واحدة.
///
/// ثلاثُ نسخٍ من منطقٍ واحدٍ تفترق (‏كما افترق نصُّ عنوان القناة في نفس
/// اليوم). فالمنطقُ هنا مرّةً واحدة، ومقيسٌ مرّةً واحدة.
library;

import 'dart:convert';

/// يقرأ علَماً منطقياً من قيمةٍ مفكوكةٍ من JSON، متسامحاً مع ما يصل فعلاً.
///
/// `bool` كما هو · `num` صفرُها كاذبٌ وما عداه صادق · `'true'`/`'false'`
/// و`'1'`/`'0'` نصّاً. وما سوى ذلك — بما فيه `null` — يرجع [defaultValue]
/// بلا رمية.
bool readJsonFlag(Object? value, {required bool defaultValue}) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    switch (value.trim().toLowerCase()) {
      case 'true':
      case '1':
        return true;
      case 'false':
      case '0':
        return false;
    }
  }
  return defaultValue;
}

/// أصغرُ مقاسٍ يُقرأ على ورقٍ حراريّ. ما دونه ليس تصميماً بل قيمةٌ فاسدة.
const double kMinLegibleFontPt = 4.0;

/// يحسم مقاسَ خطّ عناوين الجدول من القيمة المخزَّنة.
///
/// ⚠️ قِيس في قاعدة المالك 2026-08-12: `header_font_size = 1.0` بينما
/// المحرّرُ يعرض 9pt. والطابعةُ كانت تقصّ إلى `clamp(1.0, …)` — فحدُّها
/// الأدنى يقبل النقطةَ الواحدة، أي صفَّ عناوينَ موجوداً في الوثيقة وغيرَ
/// مرئيٍّ على الورق. المستخدمُ يرى «العناوين لا تُطبع» ويبحث في المكان
/// الخطأ.
///
/// فما دون [kMinLegibleFontPt] يُعامَل **غيرَ مضبوط** ويرجع إلى
/// [fallback]. والسقفُ يضيق مع كثرة الأعمدة كما كان.
double resolveHeaderFontSize(
  double? stored, {
  required int enabledColumns,
  double fallback = 9.0,
}) {
  final max = enabledColumns >= 7
      ? 7.0
      : enabledColumns >= 6
          ? 8.0
          : 24.0;
  final base = (stored == null || stored < kMinLegibleFontPt) ? fallback : stored;
  return base.clamp(kMinLegibleFontPt, max);
}

/// إعداداتُ الجدول المفكوكة. الحقولُ `null` تعني «غيرُ مخزَّنة» — يقرّر
/// المستدعي افتراضَه، فيبقى الافتراضُ في موضعٍ واحدٍ لكلّ قارئ.
class TableJsonFlags {
  const TableJsonFlags({
    this.columnWidths = const {},
    this.showHeader,
    this.headerBold,
    this.bodyBold,
    this.decimalPlaces,
  });

  final Map<String, double> columnWidths;
  final bool? showHeader;
  final bool? headerBold;
  final bool? bodyBold;
  final int? decimalPlaces;
}

/// يفكّ نصَّ `columnWidths` **بعزلٍ لكلّ مفتاح**.
///
/// مفتاحٌ فاسدٌ يسقط وحدَه ولا يُسقط جيرانَه — وهذا هو الفرق عن الشكل
/// القديم الذي كان يلفّ الحلقةَ كلَّها في `try` واحد.
TableJsonFlags parseTableFlags(String? raw) {
  if (raw == null || raw.isEmpty) return const TableJsonFlags();

  Map<String, dynamic> decoded;
  try {
    final parsed = jsonDecode(raw);
    if (parsed is! Map<String, dynamic>) return const TableJsonFlags();
    decoded = parsed;
  } catch (_) {
    return const TableJsonFlags();
  }

  final widths = <String, double>{};
  bool? showHeader;
  bool? headerBold;
  bool? bodyBold;
  int? decimalPlaces;

  for (final e in decoded.entries) {
    switch (e.key) {
      case '_showHeader':
        showHeader = readJsonFlag(e.value, defaultValue: true);
      case '_headerBold':
        headerBold = readJsonFlag(e.value, defaultValue: true);
      case '_bodyBold':
        bodyBold = readJsonFlag(e.value, defaultValue: false);
      case '_decimalPlaces':
        final v = e.value;
        if (v is num) decimalPlaces = v.toInt();
        if (v is String) decimalPlaces = int.tryParse(v.trim());
      default:
        // الأعلامُ كلُّها ببادئة `_` — فما بلا بادئةٍ عرضُ عمود.
        if (!e.key.startsWith('_') && e.value is num) {
          widths[e.key] = (e.value as num).toDouble();
        }
    }
  }

  return TableJsonFlags(
    columnWidths: widths,
    showHeader: showHeader,
    headerBold: headerBold,
    bodyBold: bodyBold,
    decimalPlaces: decimalPlaces,
  );
}
