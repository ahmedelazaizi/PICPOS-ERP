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

/// حالُ مستوىً واحدٍ في السلسلة كما رآه الحسم.
enum ResolutionStepState {
  /// جُرِّب وطابق — **وهو الفائز**. لا يقع إلّا مرّةً في السلسلة.
  matched,

  /// جُرِّب ولم يطابق.
  missed,

  /// لم يُجرَّب: الحسمُ توقّف عند مستوىً أخصَّ منه.
  notTried,
}

/// مستوىً واحدٌ من سلسلة الحسم — تعرضه شاشةُ الحسم سطراً.
class ResolutionStep {
  /// ١..٦.
  final int level;

  /// اسمُ المستوى كما يُقرأ.
  final String label;

  /// المفتاحُ الذي جُرِّب به — `*` تعني «أيّاً كان».
  final String key;

  final ResolutionStepState state;

  /// القالبُ الفائز، و`null` في كلِّ مستوىً آخرَ **وفي المستوى السادس**:
  /// المدمجُ لا قالبَ له في القاعدة.
  final int? templateId;

  const ResolutionStep({
    required this.level,
    required this.label,
    required this.key,
    required this.state,
    this.templateId,
  });

  bool get isWinner => state == ResolutionStepState.matched;
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

  /// أنواعُ المستندات التي **يمرّرها منادٍ حيٌّ اليوم**.
  ///
  /// ── لماذا ثابتٌ لا استنتاج ─────────────────────────────────────────────
  /// نوعٌ معلَنٌ في [documentTypes] بلا منادٍ يمرّره هو رابطةٌ تُكتب ولا تصل
  /// ورقةً أبداً: المستخدمُ يفعّل القالبَ، والشاشةُ تقول «مضبوط»، والمطبوعُ
  /// يخرج من مسارٍ آخرَ لا يعرف الرابطات. فشاشةُ الحسم تحتاج أن تفرّق بين
  /// «محسومٌ ويطبع» و«محسومٌ وينتظر توصيلاً».
  ///
  /// ⚠️ **ولا يُحدَّث باليد**: يقيسه
  /// `print_callers_pass_document_type_test.dart` بمسحِ ملفّات المنادين، فأيُّ
  /// نوعٍ يُوصَل غداً يُحمِّر الحارسَ حتى يُضاف هنا — وأيُّ نوعٍ يُفقد توصيلُه
  /// كذلك. وبلا هذا تبقى الشاشةُ تقول «بانتظار التوصيل» عن مسارٍ صار يعمل.
  ///
  /// و`report` و`quotation` خارجَه اليوم: الأوّلُ يُطبع من `report_pdf_generator.dart`
  /// بعشرين دالّةٍ ثابتةٍ لا تمرّ على منظومة القوالب (‏`EXTENSION-SPEC.md` §١)،
  /// والثاني بلا مسارِ طباعةٍ بعد.
  ///
  /// و`party_statement` **دخل** بامتداد §٣: `InvoiceGenerator.printPartyStatement`
  /// يبني [PartyStatementSnapshot] ويمرّ بالقوالب، ويسقط إلى المولّد الثابت
  /// حين لا قالبَ محسوماً.
  static const wiredDocumentTypes = <String>{
    'sales_invoice',
    'sales_return',
    'purchase_invoice',
    'purchase_return',
    'sales_receipt',
    'kitchen_order',
    'shift_closing',
    'party_statement',
  };

  /// الزوجُ `(type, category)` الذي يمرّره منادي كلِّ نوع.
  ///
  /// المستوى الخامسُ يُفهرَس بهما لا بنوع المستند (‏`getDefaultTemplateByCategory`
  /// تأخذ النوعَ الورقيَّ والفئة). فشاشةُ الحسم لا تستطيع أن تعرض المستوى
  /// الخامسَ بصدقٍ ما لم تسأل بنفس الزوج الذي يسأل به المنادي — وزوجٌ مخالف
  /// يجعلها تعرض قالباً غيرَ الذي يخرج من الطابعة.
  ///
  /// والثلاثةُ غيرُ الموصولة (`quotation` · `party_statement` · `report`)
  /// تحمل زوجَ ملفّاتِ قوالبها المبذورة، فحين يُوصَل مسارُها يسأل بنفسه.
  ///
  /// ⚠️ **مقيسٌ لا مفترَض**: `print_callers_pass_document_type_test.dart`
  /// يقرأ ملفّاتِ المنادين ويشترط حضورَ فئةِ كلِّ نوعٍ موصولٍ فيها نصّاً.
  static const documentContexts = <String, ({String type, String category})>{
    'sales_invoice': (type: 'a4', category: 'invoice'),
    'sales_return': (type: 'thermal', category: 'sales_return'),
    'purchase_invoice': (type: 'a4', category: 'purchase'),
    'purchase_return': (type: 'a4', category: 'purchase_return'),
    // `printing_service` لا تمرّر `type` — فالقيمةُ افتراضيُّ الوسيط في
    // `printWithTemplate` وهو `'thermal'`.
    'sales_receipt': (type: 'thermal', category: 'receipt'),
    'quotation': (type: 'a4', category: 'quotation'),
    'kitchen_order': (type: 'kitchen', category: 'kitchen'),
    'shift_closing': (type: 'shift_closing', category: 'shift_closing'),
    'party_statement': (type: 'statement', category: 'party_statement'),
    'report': (type: 'report', category: 'report'),
  };

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

  /// نفسُ السلسلةِ التي يمشيها [resolve] — **بكلِّ مستوىً لا بالفائز وحدَه**.
  ///
  /// ── لماذا دالّةٌ ثانيةٌ لا حقلٌ في [TemplateResolution] ─────────────────
  /// مسارُ الطباعة يريد الفائزَ ويقف؛ وبناءُ السلسلةِ كاملةً لكلِّ فاتورةٍ
  /// عملٌ لا يُقرأ. أمّا شاشةُ الحسم فتريد **لماذا** — أيُّ مستوىً جُرّب
  /// وأخفق قبل الفائز، وأيُّها لم يُجرَّب أصلاً.
  ///
  /// ⚠️ **والخطرُ أنّ تفترقا**: شاشةٌ تعرض سلسلةً غيرَ التي يمشيها الراسمُ
  /// أسوأُ من شاشةٍ لا توجد — فهي تشرح عطباً غيرَ الواقع. لذلك يقيس
  /// `template_resolution_chain_test.dart` أنّ فائزَ [explain] هو مستوى
  /// [resolve] نفسُه على كلِّ تركيبة.
  static List<ResolutionStep> explain({
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

    // ── نجمةٌ وشَرطةٌ ليستا سواءً ────────────────────────────────────────
    // `*` = **المستوى** يعمّم هذا الحقل، فأيُّ قيمةٍ تمرّ.
    // `—` = المستوى يشترط الحقلَ و**الاستعلامُ لم يحمله**، فلا يطابق أبداً.
    //
    // وبلا هذا التفريق تظهر المستوياتُ الثلاثةُ الأولى بمفتاحٍ **واحدٍ
    // حرفيّاً** حين يُفحَص «كلُّ الفروع» بلا طابعة — ثلاثةُ سطورٍ متطابقةٍ
    // في اللوحة، ولا تقول أيُّها أخفق ولماذا. مقيسٌ في اختبار الشاشة.
    const gen = '*';
    const unset = '—';
    String req(Object? v) => v?.toString() ?? unset;

    final keys = <String>[
      // ١ · الفرعُ والطابعةُ واللغةُ كلُّها مشروطة.
      '$documentType · ${req(branchId)} · ${req(printerId)} · ${req(locale)}',
      // ٢ · الطابعةُ معمَّمةٌ بالمستوى، والفرعُ واللغةُ مشروطان.
      '$documentType · ${req(branchId)} · $gen · ${req(locale)}',
      // ٣ · الفرعُ والطابعةُ معمَّمان، واللغةُ مشروطة.
      '$documentType · $gen · $gen · ${req(locale)}',
      // ٤ · الكلُّ معمَّم.
      '$documentType · $gen · $gen · $gen',
      // ٥ · يُفهرَس بالفئة لا بنوع المستند.
      '$category · $gen · $gen · $gen',
      'built-in',
    ];

    const labels = <String>[
      '١ · مستند + فرع + طابعة + لغة',
      '٢ · مستند + فرع + لغة',
      '٣ · مستند + لغة',
      '٤ · مستند',
      '٥ · الفئة (السلوك القائم)',
      '٦ · التصميم المدمج في الكود',
    ];

    var winner = 0; // ١..٦ — صفرٌ يعني «لم يُحسم بعد».
    int? winnerTemplate;

    for (var level = 1; level <= 4 && winner == 0; level++) {
      final matches = mine.where((r) => _matchesLevel(
            r,
            level,
            branchId: branchId,
            printerId: printerId,
            locale: locale,
          ));
      if (matches.isEmpty) continue;
      winner = level;
      winnerTemplate =
          matches.reduce((a, c) => c.priority > a.priority ? c : a).templateId;
    }

    if (winner == 0 && categoryDefaultTemplateId != null) {
      winner = 5;
      winnerTemplate = categoryDefaultTemplateId;
    }

    // ٦ يفوز دائماً حين يصله الدور — التصميمُ المدمجُ لا يُخفق، وقالبُه
    // `null` عن قصدٍ لا عن فقد.
    if (winner == 0) winner = 6;

    return [
      for (var level = 1; level <= 6; level++)
        ResolutionStep(
          level: level,
          label: labels[level - 1],
          key: keys[level - 1],
          state: level == winner
              ? ResolutionStepState.matched
              : level < winner
                  ? ResolutionStepState.missed
                  : ResolutionStepState.notTried,
          templateId: level == winner ? winnerTemplate : null,
        ),
    ];
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
