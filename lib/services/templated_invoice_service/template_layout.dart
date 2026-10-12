// TemplatedInvoiceService - element ordering, layout sequence and pagination.
part of '../templated_invoice_service.dart';

/// Element ordering, layout sequence and pagination of [TemplatedInvoiceService].
abstract final class _TemplatedInvoiceLayout {
  /// ترتيبُ عناصر القالب للطباعة — المرئيُّ منها، مرتَّباً، منقّى من التكرار.
  ///
  /// بذرةٌ خالصةٌ مستخرَجةٌ من `printWithTemplate` كي تُقاس آلياً: الورقةُ
  /// لا تُقاس، لكنّ **ترتيبَها** يُقاس.
  ///
  /// **`sortOrder` هو الحَكَم** — لا جدولُ أولوياتٍ مكتوبٌ في الكود. ومحرّرُ
  /// الأقسام يكتبه عالمياً متسلسلاً عبر الأقسام كلِّها بترتيبها البصريّ، فهو
  /// وصفٌ تامٌّ لتخطيط المصمّم. و`section` **لا يصلح** مفتاحاً أوّل: أقسامُ
  /// `shift_*` تقع بعد جدول الأصناف على الشاشة بينما قيمتُها `'body'` وقيمةُ
  /// الجدول `'details'`، فالفرزُ به يقلبها. و`rowIndex` لا يكتبه أحدٌ فيبقى
  /// صفراً للجميع.
  static List<InvoiceTemplateElement> orderElementsForPrint(
    List<InvoiceTemplateElement> all,
  ) {
    final allVisible = all.where((e) => e.isVisible).toList()
      ..sort((a, b) {
        final orderCmp = a.sortOrder.compareTo(b.sortOrder);
        if (orderCmp != 0) return orderCmp;
        // تساوي الترتيب — قالبٌ لم يمرّ بالمحرّر بعدُ. يحسمه موضعُ الرسم،
        // ثم المعرّفُ كي لا يتأرجح المطبوعُ بين تشغيلتَين.
        final yCmp = a.yPosition.compareTo(b.yPosition);
        if (yCmp != 0) return yCmp;
        return a.id.compareTo(b.id);
      });

    // إزالةُ التكرار **للمتغيّرات وحدَها**: قيمةٌ يولّدها الكودُ لا تُطبع
    // مرّتين (بذرةٌ قديمةٌ كتبت `grand_total` و`total_amount` معاً). أمّا ما
    // رسمه المستخدمُ — فاصلٌ أو نصٌّ ثابتٌ أو شعار — فيتكرّر عمداً، وحذفُه
    // كان يُطبع قالباً بثلاثة فواصلَ بفاصلٍ واحد.
    //
    // ⚠️ **والمعيارُ صار النوعَ المحسومَ لا `elementType == 'variable'`.**
    // بعد رفع القائمة البيضاء في [layoutSequenceForPrint] صار العنصرُ بالصيغة
    // القديمة (‏`elementType == 'total'`) يصل الراسمَ كنظيره الجديد
    // (‏`variable` + `content: 'total_amount'`)، وكلاهما يُحسم إلى `total`.
    // فقالبٌ كُتب بالصيغتَين معاً كان سيطبع الإجماليَّ مرّتَين.
    //
    // ومقيسٌ 2026-09-02: لا ملفَّ في الأصول يخلط الصيغتَين اليومَ (صفرٌ من
    // تسعةَ عشرَ)، فهذا حارسٌ استباقيٌّ لقالبٍ يحرّره المستخدم.
    //
    // ⚠️ **والحذفُ لحقول البيانات المعروفةِ وحدَها.** `_resolveType` تُرجع
    // **محتوى** عنصر النصِّ الحرِّ حرفيّاً (‏`'— — —'`)، فشرطُ «ليس في قائمة
    // المتكرّرات» وحدَه كان يحذف الفاصلَ الثانيَ والثالث: قالبٌ بثلاثة فواصلَ
    // يُطبع بفاصلٍ واحد. أمسكه `print_follows_designer_order_test` القائم.
    final seenContent = <String>{};
    final elements = <InvoiceTemplateElement>[];
    for (final el in allVisible) {
      final key = _TemplatedInvoiceValues._resolveType(el);
      final isSingleInstanceField = kRenderableElementTypes.contains(key) &&
          !kRepeatableElementTypes.contains(key);
      if (!isSingleInstanceField) {
        elements.add(el);
        continue;
      }
      if (seenContent.add(key)) elements.add(el);
    }
    return elements;
  }

  /// ارتفاعُ الصفحة بالنقاط — و`null` تعني **لفّةً مستمرّة**.
  ///
  /// الحراريُّ لفّةٌ تُقصّ عند آخر سطر، فارتفاعُه لا نهائيٌّ بحقّ. وA4 ورقٌ
  /// مقصوصٌ سلفاً، و`paperHeight` مخزَّنٌ في القالب منذ البذرة ولم يكن يُقرأ
  /// في أيّ موضع — فكانت ستّون صنفاً تخرج ورقةً واحدةً ممتدّة.
  static double? _pageHeightPoints(InvoiceTemplate template) {
    if (template.paperWidth <= 80) return null;
    final h = template.paperHeight;
    if (h == null || h <= 0) return null;
    return h * 2.8346;
  }

  /// إضافةُ صفحات المستند.
  ///
  /// `canvasHeightPts == null` ⇒ **لفّةٌ مستمرّة**: صفحةٌ واحدةٌ يمتدّ طولُها
  /// بالمحتوى، وهو الصوابُ للحراريّ. وغيرُها ⇒ `MultiPage` تنقسم عند حدّ
  /// الورقة، وجدولُ الأصناف `SpanningWidget` فينقسم معها وصفُّ عناوينه
  /// `repeat: true` فيتكرّر في رأس كلّ صفحة.
  static void _addDocumentPages(
    pw.Document pdf, {
    required List<pw.Widget> content,
    required double canvasWidth,
    required double? canvasHeightPts,
    required double marginPts,
    required pw.TextDirection direction,
  }) {
    if (canvasHeightPts == null) {
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat(
            canvasWidth,
            double.infinity,
            marginAll: marginPts,
          ),
          textDirection: direction,
          build: (context) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: content,
          ),
        ),
      );
      return;
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat(
          canvasWidth,
          canvasHeightPts,
          marginAll: marginPts,
        ),
        textDirection: direction,
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        // الافتراضُ ٢٠ صفحة، وتجاوزُه يرمي `TooManyPagesException` فتضيع
        // الفاتورةُ كلُّها. فاتورةٌ بألفَي صنفٍ أهونُ من مطبوعٍ يسقط.
        maxPages: 200,
        build: (context) => content,
      ),
    );
  }

  static Future<pw.Document> _buildPaginationProbe({
    required List<Map<String, dynamic>> items,
    required double paperWidthMm,
    double? paperHeightMm,
  }) async {
    await _initFont();
    final pdf = await BaseGenerator.newDocument();
    const mmToPoints = 2.8346;
    final isThermal = paperWidthMm <= 80;
    _addDocumentPages(
      pdf,
      content: [
        _TemplatedItemsTable._buildItemsTable(
          items,
          null,
          pw.TextStyle(font: _arabicFont, fontSize: 9),
        ),
      ],
      canvasWidth: (isThermal ? paperWidthMm - 8 : paperWidthMm) * mmToPoints,
      canvasHeightPts: (isThermal || paperHeightMm == null)
          ? null
          : paperHeightMm * mmToPoints,
      marginPts: (isThermal ? 2.0 : 4.0) * mmToPoints,
      direction: pw.TextDirection.rtl,
    );
    return pdf;
  }

  static List<InvoiceTemplateElement?> layoutSequenceForPrint(
    List<InvoiceTemplateElement> ordered, {
    required bool hasItems,
  }) {
    // 🔴 §٦‑١ — كانت هنا قائمةٌ بيضاءُ من خمسةِ أنواعٍ **تُسقط القالبَ كلَّه**.
    //
    // نصُّها القديم: «only process known elementTypes … This skips old-format
    // seeded elements with elementType like 'customer', 'footer'». والواقعُ
    // أنّ [_buildElementContent] يعالج تسعةً وثلاثين نوعاً والقائمةُ تُمرّر
    // خمسةً — فكلُّ عنصرٍ بالصيغة القديمة يسقط **قبل** أن يصل الراسمَ الذي
    // يفهمه أصلاً.
    //
    // مقيسٌ 2026-09-02 على الأصول المشحونة:
    //   thermal_classic       ٢١ من ٢١ مُسقَطاً
    //   thermal_modern        ١٩ من ١٩
    //   a4_commercial         ٢٣ من ٢٤
    //   a4_professional       ٢٠ من ٢٨
    //   thermal_comprehensive ٢١ من ٣١
    // أي أنّ خمسةَ قوالبَ كانت تطبع **جدولَ أصنافٍ عارياً**: بلا اسمِ شركةٍ
    // ولا رقمِ فاتورةٍ ولا تاريخٍ ولا عميلٍ ولا مجاميعَ ولا تذييل.
    //
    // فالمعيارُ صار قدرةَ الراسم لا قائمةً مكتوبةً بيد:
    //   · أنواعُ الحاويات تمرُّ دائماً — محتواها يُحسم في [_resolveType] وقد
    //     يكون نصّاً حرّاً لا نوعاً معروفاً.
    //   · وما عداها يمرُّ إن كان الراسمُ يعرف نوعَه المحسوم.
    // ويحرس التطابقَ `printing_element_types_lockstep_test`.
    final validElements = ordered
        .where((e) =>
            kTemplateContainerElementTypes.contains(e.elementType) ||
            kRenderableElementTypes.contains(_TemplatedInvoiceValues._resolveType(e)))
        .toList();

    // موضعُ الجدول من القالب أوّلاً. فإن خلا القالبُ من عنصرِ جدولٍ — وهو
    // حالُ كلّ قالبٍ مبذورٍ قبل 2026-08-12 — بقي الاستدلالُ القديم احتياطاً
    // كي لا ينقلب مطبوعٌ قائم.
    final hasExplicitTable =
        validElements.any((e) => _TemplatedInvoiceValues._resolveType(e) == 'items_table');

    final seq = <InvoiceTemplateElement?>[];
    bool tableInserted = false;
    for (final el in validElements) {
      final resolved = _TemplatedInvoiceValues._resolveType(el);
      if (resolved == 'items_table') {
        // بلا أصنافٍ لا جدولَ يُطبع — تقريرُ الوردية يمرّ بهذا المُصيِّر
        // بقائمةٍ فارغة، وجدولٌ فارغٌ عناوينُ بلا صفوف.
        if (hasItems) {
          seq.add(el);
          tableInserted = true;
        }
        continue;
      }
      // Fallback heuristic: insert before the first totals-like element
      if (!tableInserted &&
          hasItems &&
          !hasExplicitTable &&
          _precedesItemsTable(resolved)) {
        seq.add(null);
        tableInserted = true;
      }
      seq.add(el);
    }
    // If table hasn't been inserted yet, add at end
    if (!tableInserted && hasItems && !hasExplicitTable) seq.add(null);
    return seq;
  }

  /// العناصرُ التي يسبقها جدولُ الأصناف في الاستدلال الاحتياطيّ.
  static bool _precedesItemsTable(String resolvedType) => const {
        'subtotal', 'total', 'discount', 'tax', 'paid', 'remaining',
        'notes', 'footer', 'qr_code',
      }.contains(resolvedType);

  // `_contentSectionPriority` حُذف 2026-08-12 (قرارُ المالك — الخيار ب).
  // كان جدولَ أولوياتٍ مكتوباً في الكود يُفرَز به المطبوعُ **قبل** `sortOrder`،
  // فيهدم كلَّ ترتيبٍ يرسمه المالكُ في المصمّم. والآن `sortOrder` هو الحَكَم
  // (`orderElementsForPrint`). ونسخةٌ منه باقيةٌ في `invoice_preview_dialog.dart`
  // حيث هي **كاسرُ تعادلٍ** بعد `sortOrder` — وهو موضعُها الصحيح.

}
