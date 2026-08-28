// نموذجُ بطاقة القالب في المكتبة — **خالصٌ بلا واجهةٍ ولا قاعدة**.
//
// محلُّه `domain/models` لا `presentation/`: حارسُ
// `presentation_db_import_guard` يمنع أيَّ ملفِّ عرضٍ **جديد** من استيراد
// `data/database`، والقائمةُ البيضاء مقفولة. فالصفوفُ تصل الشاشةَ نموذجاً
// خالصاً والوصلُ يقع في طبقة البيانات.
//
// ── ولماذا تحمل البطاقةُ عمليّاتِ رسمٍ لا «رسماً تخطيطيّاً» ───────────────
// تصميمُ المكتبة يرسم مصغَّرةَ البطاقة بأشرطةٍ رماديّةٍ مكتوبةٍ باليد —
// «‏A4_SKETCH» و«THERMAL_SKETCH» — أي **صورةٌ ثانيةٌ للقالب** لا علاقةَ لها
// بما يُطبع. وهذا عينُ العطب الذي بُني المحرّكُ كلُّه لمنعه: مصدرٌ ثانٍ
// للتخطيط ينحرف عن الأوّل ولا يشكو.
//
// فالمصغَّرةُ هنا تحمل [PaintOp] — **نفسَ** ما يستهلكه راسمُ الـPDF. تكبر
// وتصغر بالقياس وحدَه، ولا تستطيع أن تفترق عن الورق ولو أراد كاتبُها.

import '../../services/printing/paint_plan.dart';

/// مصغَّرةُ القالب — عمليّاتُ الرسم بقياس الصفحة بالمليمتر.
class TemplateThumbnail {
  final double widthMm;
  final double heightMm;
  final List<PaintOp> ops;

  const TemplateThumbnail({
    required this.widthMm,
    required this.heightMm,
    required this.ops,
  });

  static const empty =
      TemplateThumbnail(widthMm: 210, heightMm: 297, ops: <PaintOp>[]);

  bool get isEmpty => ops.isEmpty;
}

/// رابطةٌ كما تُعرض في لوحة التفاصيل.
class TemplateBindingView {
  /// نوعُ المستند بتسميته العربيّة.
  final String documentLabel;

  /// المفتاحُ الخام — يحتاجه زرُّ الفكّ.
  final String documentType;

  /// «كل الفروع · عربي» — نطاقُ الرابطة مقروءاً.
  final String scope;

  const TemplateBindingView({
    required this.documentLabel,
    required this.documentType,
    required this.scope,
  });
}

/// بطاقةُ قالبٍ في المكتبة.
class TemplateCard {
  final int id;
  final String name;

  /// `a4` · `thermal` · `kitchen` · `statement` · `report` …
  final String type;
  final String category;

  final double paperWidthMm;
  final double? paperHeightMm;

  /// «A4» · «A5» · «80mm» — تسميةُ الورق كما تُعرض على الشارة.
  final String paperLabel;

  final int elementCount;
  final int columnCount;

  /// ١ = تدفّق · ٢ = نطاقاتٌ بإحداثيّات.
  final int layoutVersion;

  /// العَلَمُ القديم — «افتراضي» على الشارة.
  final bool isDefault;

  final List<TemplateBindingView> bindings;
  final TemplateThumbnail thumbnail;

  const TemplateCard({
    required this.id,
    required this.name,
    required this.type,
    required this.category,
    required this.paperWidthMm,
    this.paperHeightMm,
    required this.paperLabel,
    required this.elementCount,
    required this.columnCount,
    required this.layoutVersion,
    required this.isDefault,
    this.bindings = const [],
    this.thumbnail = TemplateThumbnail.empty,
  });

  bool get isThermal => paperWidthMm <= 80;

  /// مربوطٌ بمستندٍ واحدٍ على الأقلّ ⇒ حذفُه يُرفض.
  bool get isBound => bindings.isNotEmpty;

  /// «٣٠ عنصراً · ٩ أعمدة».
  String get meta => '$elementCount عنصراً · $columnCount أعمدة';
}

/// تسميةُ الورق من عرضه وارتفاعه.
///
/// المقاساتُ المعروفةُ بأسمائها، وما عداها بعرضه — «١٦٠مم» أصدقُ من «مخصّص».
String paperLabelFor(double widthMm, double? heightMm) {
  if (widthMm <= 60) return '58mm';
  if (widthMm <= 80) return '80mm';
  if (widthMm <= 150) return 'A5';
  if (widthMm <= 215) return 'A4';
  return '${widthMm.toStringAsFixed(0)}mm';
}

/// تصنيفُ المكتبة — مرشّحاتُ الشريط العلويّ.
enum TemplateFilter {
  all('الكل'),
  a4('ورق A4/A5'),
  thermal('حراري'),
  statement('كشوف الحساب'),
  report('تقارير');

  const TemplateFilter(this.label);
  final String label;

  bool accepts(TemplateCard c) {
    switch (this) {
      case TemplateFilter.all:
        return true;
      case TemplateFilter.a4:
        return !c.isThermal &&
            c.type != 'statement' &&
            c.type != 'report';
      case TemplateFilter.thermal:
        return c.isThermal;
      case TemplateFilter.statement:
        return c.type == 'statement';
      case TemplateFilter.report:
        return c.type == 'report';
    }
  }
}

/// يرشّح ويرتّب بطاقاتِ المكتبة.
///
/// حسابٌ خالصٌ يُختبَر بلا `ProviderScope` ولا قاعدةٍ مفتوحة.
List<TemplateCard> filterTemplateCards(
  List<TemplateCard> all, {
  TemplateFilter filter = TemplateFilter.all,
  String query = '',
}) {
  final q = query.trim().toLowerCase();
  final out = [
    for (final c in all)
      if (filter.accepts(c) && (q.isEmpty || c.name.toLowerCase().contains(q)))
        c
  ];
  // المربوطُ أوّلاً — هو ما يخرج على الورق فعلاً، فيُرى بلا بحث. ثمّ
  // الافتراضيُّ، ثمّ بالاسم كي لا يتأرجح الترتيبُ بين فتحتين.
  out.sort((a, b) {
    if (a.isBound != b.isBound) return a.isBound ? -1 : 1;
    if (a.isDefault != b.isDefault) return a.isDefault ? -1 : 1;
    return a.name.compareTo(b.name);
  });
  return out;
}

/// عددُ ما يقبله كلُّ مرشّح — تعرضه الشارةُ بجوار اسمه.
Map<TemplateFilter, int> templateFilterCounts(List<TemplateCard> all) => {
      for (final f in TemplateFilter.values)
        f: all.where(f.accepts).length,
    };
