/// سلسلةُ حسم القالب — ستّةُ مستوياتٍ من الأخصِّ للأعمّ.
///
/// ── لماذا رابطةٌ لا عَلَم ─────────────────────────────────────────────────
/// الحسمُ اليومَ يقوم على `isDefault`، وهو عَلَمٌ **عالميٌّ لا يعرف فرعاً ولا
/// طابعةً ولا لغة**. فالفرعُ الذي يريد ترويسةً مختلفةً لا يستطيع، والطابعةُ
/// الحراريّةُ تتلقّى قالبَ A4 فيُقصّ المطبوعُ صامتاً.
///
/// والرابطةُ مفتاحٌ رباعيّ: نوعُ المستند + الفرع + الطابعة + اللغة.
///
/// ── والمستوى الخامسُ يبقى عمداً ──────────────────────────────────────────
/// الحسمُ بالفئة هو سلوكُ اليوم. إسقاطُه يعني أنّ كلَّ قاعدةٍ قائمةٍ تفقد
/// قالبَها الافتراضيَّ لحظةَ الترقية — فيبقى ذيلاً للسلسلة لا بديلاً عنها.
///
/// نقيّ: لا `package:pdf` ولا `package:flutter` ولا قاعدةَ بيانات — الـDAO
/// يملأ [BindingRule] ويناديه.
library;

/// رابطةٌ واحدةٌ بين مستندٍ وقالب.
///
/// `null` في أيِّ حقلِ نطاقٍ يعني «أيّاً كان» — وهو ما يجعل الرابطةَ أعمَّ.
/// **الاسمُ `BindingRule` لا `TemplateBinding`** عمداً: الأخيرُ اسمُ صفِّ
/// الصفِّ الذي يولّده drift لجدول `template_bindings`، والتصادمُ بينهما يُجبر
/// كلَّ مستدعٍ على بادئةِ استيراد.
///
/// وهي **قاعدةُ حسمٍ** لا صفٌّ في قاعدة: قد تأتي من جدولٍ أو إعدادٍ أو اختبار،
/// والمحرّكُ لا يعرف من أين — وهذا ما يُبقيه قابلاً للقياس بلا قاعدة.
class BindingRule {
  final int templateId;

  /// `sales_invoice` · `sales_return` · `purchase_invoice` · …
  final String documentType;

  /// `null` = أيُّ فرع.
  final int? branchId;

  /// `null` = أيُّ طابعة.
  final int? printerId;

  /// `null` = أيُّ لغة.
  final String? locale;

  final int copies;
  final bool directPrint;

  /// يفصل عند تساوي الخصوصيّة — الأعلى يفوز.
  final int priority;

  const BindingRule({
    required this.templateId,
    required this.documentType,
    this.branchId,
    this.printerId,
    this.locale,
    this.copies = 1,
    this.directPrint = false,
    this.priority = 0,
  });

  /// مفتاحُ التفرّد — **لا تتعايش رابطتان به**.
  ///
  /// تفعيلُ قالبٍ يُلغي المتعارضَ ويُذكر ذلك في الإشعار صراحةً؛ فالإلغاءُ
  /// الصامتُ يجعل المستخدمَ يظنّ قالبين مفعّلَين.
  String get conflictKey =>
      '$documentType|${branchId ?? '*'}|${printerId ?? '*'}|${locale ?? '*'}';
}

/// نتيجةُ الحسم — بأيِّ مستوىً طابقت، فيُعرض المسارُ في شاشة الحسم.
class TemplateResolution {
  /// `null` يعني التصميمَ المدمجَ في الكود.
  final int? templateId;

  /// ١..٦ — انظر ترتيبَ السلسلة أعلاه.
  final int level;

  final int copies;
  final bool directPrint;

  const TemplateResolution({
    required this.templateId,
    required this.level,
    this.copies = 1,
    this.directPrint = false,
  });

  bool get isBuiltIn => templateId == null;
}

class TemplateResolver {
  const TemplateResolver._();

  /// أنواعُ المستندات المعترَفُ بها.
  ///
  /// `sales_return` و`purchase_return` **فئتان قائمتان بذاتهما**: بدونهما
  /// يتقاسم المرتجعُ فئةَ الفاتورة ويستحيل أن يكون له قالبٌ افتراضيٌّ خاصّ.
  static const documentTypes = <String>[
    'sales_invoice',
    'sales_return',
    'purchase_invoice',
    'purchase_return',
    'sales_receipt',
    'quotation',
    'kitchen_order',
    'shift_closing',
    'party_statement',
    'report',
  ];

  /// خريطةُ الفئة القديمة ⇒ نوعِ المستند — تُملأ منها الرابطاتُ آليّاً عند
  /// الترقية، فينتج سلوكٌ مطابقٌ لليوم بالضبط.
  static const categoryToDocumentType = <String, String>{
    'receipt': 'sales_receipt',
    'invoice': 'sales_invoice',
    'purchase': 'purchase_invoice',
    'kitchen': 'kitchen_order',
    'quotation': 'quotation',
    'shift_closing': 'shift_closing',
    'party_statement': 'party_statement',
    'report': 'report',
  };

  /// يحسم القالبَ بالمفتاح الرباعيّ.
  ///
  /// [categoryDefaultTemplateId] هو `isDefault` القائم — المستوى الخامس.
  static TemplateResolution resolve({
    required String documentType,
    required String category,
    required List<BindingRule> bindings,
    int? branchId,
    int? printerId,
    String? locale,
    int? categoryDefaultTemplateId,
  }) {
    final mine =
        bindings.where((b) => b.documentType == documentType).toList();

    // المستوياتُ الأربعةُ الأولى — من الأخصِّ للأعمّ.
    // الشرطُ في كلٍّ منها: الحقلُ المحدَّدُ يطابق، والحقلُ المعمَّمُ `null`.
    // فالرابطةُ لا تُحسب في مستوىً أعمَّ من درجتها ولا أخصَّ منها.
    for (var level = 1; level <= 4; level++) {
      final matches = mine.where((b) => _matchesLevel(
            b,
            level,
            branchId: branchId,
            printerId: printerId,
            locale: locale,
          ));

      if (matches.isEmpty) continue;

      // الأولويّةُ تفصل عند تساوي الخصوصيّة.
      final best = matches.reduce((a, b) => b.priority > a.priority ? b : a);
      return TemplateResolution(
        templateId: best.templateId,
        level: level,
        copies: best.copies,
        directPrint: best.directPrint,
      );
    }

    // ٥ · الحسمُ بالفئة — سلوكُ اليوم، يبقى للتوافق.
    if (categoryDefaultTemplateId != null) {
      return TemplateResolution(
        templateId: categoryDefaultTemplateId,
        level: 5,
      );
    }

    // ٦ · التصميمُ المدمجُ في الكود.
    return const TemplateResolution(templateId: null, level: 6);
  }

  static bool _matchesLevel(
    BindingRule b,
    int level, {
    int? branchId,
    int? printerId,
    String? locale,
  }) {
    switch (level) {
      case 1: // مستند + فرع + طابعة + لغة
        return b.branchId != null &&
            b.branchId == branchId &&
            b.printerId != null &&
            b.printerId == printerId &&
            b.locale != null &&
            b.locale == locale;
      case 2: // مستند + فرع + أيُّ طابعة + لغة
        return b.branchId != null &&
            b.branchId == branchId &&
            b.printerId == null &&
            b.locale != null &&
            b.locale == locale;
      case 3: // مستند + أيُّ فرع + أيُّ طابعة + لغة
        return b.branchId == null &&
            b.printerId == null &&
            b.locale != null &&
            b.locale == locale;
      case 4: // مستند + الكلّ
        return b.branchId == null && b.printerId == null && b.locale == null;
    }
    return false;
  }

  /// الرابطاتُ التي يُلغيها تفعيلُ [incoming] — تُذكر في الإشعار صراحةً.
  static List<BindingRule> conflictsWith(
    BindingRule incoming,
    List<BindingRule> existing,
  ) =>
      existing
          .where((b) =>
              b.conflictKey == incoming.conflictKey &&
              b.templateId != incoming.templateId)
          .toList(growable: false);
}
