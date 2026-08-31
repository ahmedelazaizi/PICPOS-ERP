// صفُّ شاشة حسم القوالب — **خالصٌ بلا واجهةٍ ولا قاعدة**.
//
// محلُّه `domain/models` كأخيه [TemplateCard]: حارسُ
// `presentation_db_import_guard` يمنع أيَّ ملفِّ عرضٍ جديدٍ من استيراد
// `data/database`، فالصفوفُ تصل الشاشةَ نموذجاً خالصاً.
//
// ── ولماذا التصنيفُ هنا لا في الشاشة ─────────────────────────────────────
// «هل هذا المسارُ سليم؟» سؤالٌ يُجاب بالمنطق لا بالتلوين. ووضعُه في `build`
// يجعله غيرَ قابلٍ للقياس إلّا بفتح شاشةٍ وقاعدةٍ وطابعة — فيُكتب بلا
// اختبارٍ ويبيت. وهو هنا دالّةٌ خالصةٌ يقيسها
// `print_resolution_health_test.dart` بلا شيءٍ من ذلك.

import '../../services/printing/paper_compatibility.dart';
import '../../services/printing/template_resolver.dart';

/// حالُ مسارِ طباعةٍ واحد — تصنيفٌ **واحدٌ** لا مجموعة.
///
/// الشاشةُ تعرض شارةً واحدةً في العمود، فالتصنيفُ يرتّب الأسوأَ أوّلاً:
/// مسارٌ بلا قالبٍ **و**غيرُ موصولٍ يُعرَض «بلا قالب» — فذاك ما يواجهه
/// المستخدمُ أوّلاً.
enum ResolutionHealth {
  /// لا قالبَ إطلاقاً: السلسلةُ بلغت السادسَ فيرسم الكودُ المدمج، ولا يملك
  /// المالكُ من شكله شيئاً.
  builtIn,

  /// القالبُ أعرضُ من الطابعة المربوطة — يُقصّ المطبوعُ صامتاً.
  paperMismatch,

  /// حُسم بالفئة (المستوى الخامس) **ونوعٌ آخرُ يحطّ على القالب نفسِه**.
  /// هذا هو تصادمُ المرتجع مع الفاتورة: لا رابطةَ لأيٍّ منهما، فيرثان
  /// افتراضيَّ الفئة معاً ولا يستطيع أحدُهما قالباً خاصّاً.
  collision,

  /// محسومٌ بقالبٍ صحيح، **ولا منادٍ يمرّر نوعَه** — فالرابطةُ تُكتب ولا تصل
  /// ورقة. انظر [TemplateResolver.wiredDocumentTypes].
  unwired,

  /// رابطةٌ مقيَّدةٌ بفرع (المستوى الأوّل أو الثاني).
  branchScoped,

  /// حُسم بالفئة وحدَه ولا يتقاسمه أحد — سلوكُ اليوم، يعمل.
  categoryOnly,

  /// رابطةٌ صريحةٌ عامّة (المستوى الثالث أو الرابع).
  bound,
}

extension ResolutionHealthLabel on ResolutionHealth {
  String get label => switch (this) {
        ResolutionHealth.builtIn => 'بلا قالب',
        ResolutionHealth.paperMismatch => 'ورق غير مطابق',
        ResolutionHealth.collision => 'تصادم فئة',
        ResolutionHealth.unwired => 'بانتظار التوصيل',
        ResolutionHealth.branchScoped => 'من الفرع',
        ResolutionHealth.categoryOnly => 'بالفئة',
        ResolutionHealth.bound => 'مضبوط',
      };

  /// شرحُ الشارة تحت اسم القالب — سببُ الحسم لا اسمُه.
  String get note => switch (this) {
        ResolutionHealth.builtIn => 'يسقط على التصميم المدمج في الكود',
        ResolutionHealth.paperMismatch => 'عرضُ القالب يتجاوز عرضَ الطابعة',
        ResolutionHealth.collision => 'يتقاسم افتراضيَّ الفئة مع نوعٍ آخر',
        ResolutionHealth.unwired => 'القالبُ جاهزٌ والمسارُ لا يستشيره بعد',
        ResolutionHealth.branchScoped => 'رابطةٌ على مستوى الفرع',
        ResolutionHealth.categoryOnly => 'افتراضيُّ الفئة — السلوكُ القائم',
        ResolutionHealth.bound => 'رابطةٌ صريحةٌ لهذا المستند',
      };

  /// «يحتاج معالجة» في عدّاد الترويسة.
  bool get needsAttention =>
      this == ResolutionHealth.builtIn ||
      this == ResolutionHealth.paperMismatch ||
      this == ResolutionHealth.collision;
}

/// يصنّف مسارَ طباعةٍ واحداً من وقائعِه المقيسة.
///
/// [level] مستوى السلسلة الفائز (١..٧) · [wired] هل يمرّر منادٍ حيٌّ نوعَه ·
/// [sharesCategoryDefault] هل نوعٌ آخرُ يحطّ على القالب نفسِه في المستوى
/// **السادس** (الفئة) · [fit] حكمُ عرضِ الورق حين تكون الطابعةُ معروفةً.
///
/// ⚠️ **الترتيبُ أسوأً فأسوأ**: مسارٌ بلا قالبٍ وغيرُ موصولٍ في آنٍ واحدٍ
/// يُعرَض «بلا قالب». وعرضٌ واحدٌ لا يحتمل تصنيفين.
ResolutionHealth classifyResolution({
  required int level,
  required bool wired,
  required bool sharesCategoryDefault,
  PaperFit fit = PaperFit.ok,
}) {
  if (level >= 7) return ResolutionHealth.builtIn;
  if (fit == PaperFit.tooWide) return ResolutionHealth.paperMismatch;
  if (level == 6 && sharesCategoryDefault) return ResolutionHealth.collision;
  if (!wired) return ResolutionHealth.unwired;
  if (level == 6) return ResolutionHealth.categoryOnly;
  // ٥ (مِزلاجُ البيع السريع) يسقط إلى [ResolutionHealth.bound] أدناه: اختيارٌ
  // صريحٌ من المدير، فهو «موصولٌ» لا «بالفئة وحدَها». ولا تصادمَ فيه —
  // المِزلاجُ واحدٌ ولا يخدم إلّا `sales_receipt`.
  if (level <= 2) return ResolutionHealth.branchScoped;
  return ResolutionHealth.bound;
}

/// مستوىً واحدٌ من السلسلة كما تعرضه اللوحة — [ResolutionStep] وقد كُسي
/// اسمَ قالبِه.
class ResolutionStepView {
  final int level;
  final String label;
  final String key;
  final ResolutionStepState state;

  /// «← فاتورة مبيعات ضريبية — A4» عند الفائز، ونصُّ الحالِ عند غيره.
  final String result;

  const ResolutionStepView({
    required this.level,
    required this.label,
    required this.key,
    required this.state,
    required this.result,
  });

  bool get isWinner => state == ResolutionStepState.matched;
}

/// سطرٌ في جدول حسم القوالب — مستندٌ واحدٌ وما يُطبع به اليوم.
class PrintResolutionRow {
  /// `sales_invoice` · `kitchen_order` …
  final String documentType;

  /// «فاتورة مبيعات» — التسميةُ العربيّة.
  final String documentLabel;

  /// فئةُ القالب القديمة (`invoice` · `receipt` · …) — مفتاحُ المستوى الخامس.
  final String category;

  /// `null` حين يفوز المستوى السادس.
  final int? templateId;

  /// «—» حين لا قالب.
  final String templateName;

  /// «A4 · ٢١٠مم» · «80mm» — و«—» حين لا قالب.
  final String paperLabel;

  /// اسمُ الطابعة المربوطة، و`null` حين لا رابطةَ تحدّدها.
  final String? printerName;

  /// «USB001 · المعادي» أو سببُ الغياب.
  final String printerNote;

  final int copies;
  final bool directPrint;

  /// ١..٦.
  final int level;

  final ResolutionHealth health;

  /// السلسلةُ كاملةً — تعرضها اللوحةُ اليمنى.
  final List<ResolutionStepView> chain;

  const PrintResolutionRow({
    required this.documentType,
    required this.documentLabel,
    required this.category,
    required this.templateId,
    required this.templateName,
    required this.paperLabel,
    required this.printerName,
    required this.printerNote,
    required this.copies,
    required this.directPrint,
    required this.level,
    required this.health,
    required this.chain,
  });

  bool get hasTemplate => templateId != null;
}
