// فحوصُ المطبوع — **مقيسةٌ من خطّة الرسم لا مكتوبةٌ بجانبها**.
//
// ── لماذا هذا الملفُّ موجود ───────────────────────────────────────────────
// عقدُ الأزرار يقول: زرُّ الطباعة في المعاينة التجريبيّة **يُرفض إن كان في
// الحالة فحصٌ أحمر**، «فالغرضُ من الشاشة منعُ الورق المعطوب لا إنتاجُه».
//
// وهذا يجعل الفحوصَ **حاكماً** لا زينةً: قائمةٌ مكتوبةٌ باليد لكلِّ حالةٍ
// (كما في ملفّ التصميم) تعني زرّاً يرفض ما لا عيبَ فيه ويمرّر ما فيه العيب —
// وهو أسوأُ من ألّا يرفض شيئاً، لأنّه يُكسِب الثقةَ ثمّ يكذب.
//
// فكلُّ فحصٍ هنا يُحسب من [PositionedPage] و[PaintOp] — نفسِ ما يصل الورق.
//
// نقيّ: لا `package:pdf` ولا `package:flutter`.
library;

import '../../services/printing/layout_engine.dart';
import '../../services/printing/paint_plan.dart';
import '../../services/printing/paper_compatibility.dart';
import 'template_document.dart';

/// شدّةُ الفحص.
enum ProbeLevel {
  /// سليم.
  pass,

  /// يعمل، وفيه ما يُراجَع على الورق المطبوع.
  warn,

  /// **يمنع الطباعة**: ورقٌ يفقد بياناً أو لا يخرج أصلاً.
  fail,
}

class PrintCheck {
  final ProbeLevel level;
  final String title;
  final String note;

  const PrintCheck(this.level, this.title, this.note);
}

/// صفحةٌ مخطَّطةٌ ومعها عمليّاتُ رسمها — ما يفحصه [probePrintout].
class ProbedPage {
  final PositionedPage page;
  final List<PaintOp> ops;

  const ProbedPage(this.page, this.ops);
}

/// أضيقُ عمودِ جدولٍ يبقى مقروءاً بالمليمتر.
///
/// ١٢مم تسع نحوَ ستّةِ محارفَ عند ٧pt — وهو أضيقُ ما يُقرأ منه رقمٌ بخانتين
/// عشريّتين. وما دونها يُقصّ المحتوى فعليّاً لا شكلاً.
const double minReadableColumnMm = 12;

/// حدُّ التحذير: عمودٌ تحته ضيّقٌ ولمّا يفقد بياناً بعد.
const double tightColumnMm = 16;

/// تسامحُ الحوافّ بالمليمتر — الحسابُ بالنقاط العشريّة يُنتج فروقاً مجهريّة
/// لا تعني تجاوزاً.
const double _edgeToleranceMm = 0.5;

/// يفحص مطبوعاً كاملاً ويُرجع فحوصَه مرتَّبةً: الفاشلُ أوّلاً.
///
/// [printerWidthMm] عرضُ الطابعة الوجهةِ حين يُعرَف — و`null` يعني «لا أعرف»
/// وهو **ليس** عدمَ توافق.
List<PrintCheck> probePrintout({
  required List<ProbedPage> pages,
  required TemplateDocument document,
  double? printerWidthMm,
}) {
  final checks = <PrintCheck>[
    _pagesProduced(pages),
    if (pages.isNotEmpty) ...[
      _horizontalOverflow(pages),
      _verticalOverflow(pages, document),
      _emptyPages(pages),
      _tableHeaderRepeat(pages),
      _totalsReached(pages, document),
      _narrowestColumn(pages),
    ],
    _paperFit(document, printerWidthMm),
  ];

  // الأسوأُ أوّلاً: المستخدمُ يقرأ الأوّلَ ويتصرّف.
  checks.sort((a, b) => a.level.index.compareTo(b.level.index) * -1);
  return List.unmodifiable(checks);
}

/// هل في المجموعة ما يمنع الطباعة؟ — هذا ما يقرؤه الزرّ.
bool hasBlockingFailure(List<PrintCheck> checks) =>
    checks.any((c) => c.level == ProbeLevel.fail);

// ═══════════════════════════════════════════════════════════════════════════

PrintCheck _pagesProduced(List<ProbedPage> pages) {
  if (pages.isEmpty) {
    return const PrintCheck(ProbeLevel.fail, 'لم تنتج الورقةُ صفحةً واحدة',
        'القالبُ بلا عناصرَ ظاهرة، أو الحساب انهار — لا شيءَ يصل الطابعة');
  }
  return PrintCheck(ProbeLevel.pass, 'الترقيمُ سليم',
      '${pages.length} صفحةً محسوبةً بالتخطيط نفسِه الذي يطبع');
}

/// نصٌّ يتجاوز حافّةَ الورق **يُقصّ صامتاً** — وعمودُ الإجمالي أوّلُ ما يضيع.
PrintCheck _horizontalOverflow(List<ProbedPage> pages) {
  var worst = 0.0;
  var count = 0;
  String? sample;

  for (final p in pages) {
    for (final op in p.ops) {
      final over = (op.leftMm + op.widthMm) - p.page.widthMm;
      final under = -op.leftMm;
      final excess = over > under ? over : under;
      if (excess > _edgeToleranceMm) {
        count++;
        if (excess > worst) {
          worst = excess;
          sample = op.text.isEmpty ? op.id : op.text;
        }
      }
    }
  }

  if (count == 0) {
    return const PrintCheck(ProbeLevel.pass, 'لا شيءَ يتجاوز حافّةَ الورق',
        'كلُّ عنصرٍ داخلَ عرض الصفحة');
  }
  return PrintCheck(
    ProbeLevel.fail,
    '$count عنصراً يتجاوز حافّةَ الورق',
    'أبعدُها بـ${worst.toStringAsFixed(1)}مم${sample == null ? '' : ' («$sample»)'} — '
        'يُقصّ في الطباعة بلا رسالةِ خطأ',
  );
}

/// ورقٌ ثابتُ الارتفاع: ما يتجاوز قاعَه لا يُطبع. والمتّصلُ (الحراريّ) لا
/// قاعَ له، فالفحصُ لا يسري عليه.
PrintCheck _verticalOverflow(List<ProbedPage> pages, TemplateDocument doc) {
  if (doc.paper.isContinuous) {
    return const PrintCheck(ProbeLevel.pass, 'ورقٌ متّصلٌ بلا قاع',
        'الحراريُّ يتدفّق، فلا تجاوزَ رأسيّاً ممكن');
  }

  var count = 0;
  var worst = 0.0;
  for (final p in pages) {
    for (final op in p.ops) {
      final over = (op.topMm + op.heightMm) - p.page.heightMm;
      if (over > _edgeToleranceMm) {
        count++;
        if (over > worst) worst = over;
      }
    }
  }

  if (count == 0) {
    return const PrintCheck(ProbeLevel.pass, 'لا شيءَ يتجاوز قاعَ الصفحة',
        'النطاقاتُ دفعت ولم تدهس');
  }
  return PrintCheck(
    ProbeLevel.fail,
    '$count عنصراً يتجاوز قاعَ الصفحة',
    'أبعدُها بـ${worst.toStringAsFixed(1)}مم — لا يُطبع إطلاقاً',
  );
}

PrintCheck _emptyPages(List<ProbedPage> pages) {
  final empty = pages.where((p) => p.ops.isEmpty).length;
  if (empty == 0) {
    return const PrintCheck(
        ProbeLevel.pass, 'لا صفحةَ فارغة', 'كلُّ صفحةٍ تحمل محتوىً');
  }
  return PrintCheck(ProbeLevel.warn, '$empty صفحةً فارغة',
      'ورقٌ يخرج من الطابعة بلا حبر — راجع ارتفاعاتِ النطاقات');
}

/// رؤوسُ الأعمدة على كلِّ صفحةٍ تحمل جدولاً — وإلّا قرأ المحاسبُ أرقاماً
/// بلا عناوين في الصفحة الثانية.
PrintCheck _tableHeaderRepeat(List<ProbedPage> pages) {
  final withCells = pages
      .where((p) => p.ops.any((o) => o.kind == PaintKind.tableCell))
      .toList();

  if (withCells.length <= 1) {
    return const PrintCheck(ProbeLevel.pass, 'الجدولُ في صفحةٍ واحدة',
        'لا تكرارَ مطلوبٌ للرؤوس');
  }

  final missing = withCells
      .where((p) => !p.ops.any((o) => o.kind == PaintKind.tableHeader))
      .map((p) => p.page.pageNumber)
      .toList();

  if (missing.isEmpty) {
    return PrintCheck(ProbeLevel.pass, 'رؤوسُ الأعمدة معادةٌ على كلِّ صفحة',
        '${withCells.length} صفحاتِ جدولٍ وكلٌّ منها يحمل رؤوسَه');
  }
  return PrintCheck(
    ProbeLevel.warn,
    'رؤوسُ الأعمدة غائبةٌ عن ${missing.length} صفحة',
    'الصفحاتُ ${missing.join('، ')} تحمل أرقاماً بلا عناوين — '
        'فعّل «تكرار رأس الجدول»',
  );
}

/// نطاقُ المجاميع يجب أن يبلغ الورقَ. وغيابُه فاتورةٌ بلا إجمالي.
PrintCheck _totalsReached(List<ProbedPage> pages, TemplateDocument doc) {
  final declared = doc.bands.any(
      (b) => b.id == BandId.totals && b.visible && b.elements.isNotEmpty);

  if (!declared) {
    return const PrintCheck(ProbeLevel.pass, 'لا نطاقَ مجاميعَ في القالب',
        'ليس كلُّ مطبوعٍ فاتورةً — التقاريرُ والكشوفُ بلا مجاميعَ نطاقيّة');
  }

  final printed =
      pages.any((p) => p.ops.any((o) => o.band == BandId.totals));
  if (printed) {
    return const PrintCheck(ProbeLevel.pass, 'المجاميعُ بلغت الورق',
        'نطاقُ المجاميع خرج بعد الجدول');
  }
  return const PrintCheck(
    ProbeLevel.fail,
    'نطاقُ المجاميع لم يصل الورق',
    'القالبُ يعلنه والصفحاتُ خرجت بلا إجمالي — فاتورةٌ بلا رقمٍ مستحقّ',
  );
}

/// أضيقُ عمودٍ في الجدول — تحتَ حدِّ القراءة يُقصّ المحتوى فعليّاً.
PrintCheck _narrowestColumn(List<ProbedPage> pages) {
  double? min;
  for (final p in pages) {
    for (final op in p.ops) {
      if (op.kind != PaintKind.tableHeader &&
          op.kind != PaintKind.tableCell) {
        continue;
      }
      if (min == null || op.widthMm < min) min = op.widthMm;
    }
  }

  if (min == null) {
    return const PrintCheck(
        ProbeLevel.pass, 'لا جدولَ في هذا المطبوع', 'الفحصُ لا يسري');
  }

  final w = min.toStringAsFixed(1);
  if (min < minReadableColumnMm) {
    return PrintCheck(ProbeLevel.fail, 'أضيقُ عمودٍ $wمم',
        'تحتَ ${minReadableColumnMm.toStringAsFixed(0)}مم يُقصّ المحتوى — '
            'أسقِط عموداً أو وسّعه');
  }
  if (min < tightColumnMm) {
    return PrintCheck(ProbeLevel.warn, 'أضيقُ عمودٍ $wمم',
        'يمرّ، وأيُّ قيمةٍ أطولَ من المتوقَّع ستُقصّ — راجعه على الورق');
  }
  return PrintCheck(ProbeLevel.pass, 'أضيقُ عمودٍ $wمم',
      'فوق حدِّ القراءة بمريح');
}

PrintCheck _paperFit(TemplateDocument doc, double? printerWidthMm) {
  final verdict = checkPaperFit(
    templateWidthMm: doc.paper.widthMm,
    printerWidthMm: printerWidthMm,
  );

  if (printerWidthMm == null || printerWidthMm <= 0) {
    return const PrintCheck(ProbeLevel.pass, 'عرضُ الطابعة غيرُ مسجَّل',
        'لا يُحكَم على المجهول — والمنعُ عليه يقفل كلَّ طابعةٍ لم تُعرَّف');
  }
  if (verdict.isRejected) {
    return PrintCheck(
        ProbeLevel.fail, 'عرضُ القالب يتجاوز الطابعة', verdict.reason);
  }
  if (verdict.isWarning) {
    return PrintCheck(
        ProbeLevel.warn, 'القالبُ أضيقُ من الطابعة', verdict.reason);
  }
  return PrintCheck(ProbeLevel.pass, 'عرضُ القالب يطابق الطابعة',
      '${doc.paper.widthMm.toStringAsFixed(0)}مم على '
          '${printerWidthMm.toStringAsFixed(0)}مم');
}
