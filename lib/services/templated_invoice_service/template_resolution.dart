// TemplatedInvoiceService - template resolution, printer push, tax-rate labels and print payload.
part of '../templated_invoice_service.dart';

/// Template lookup, printer hand-off, tax-rate labels and payload building of [TemplatedInvoiceService].
abstract final class _TemplatedInvoiceResolution {
  /// يحسم القالبَ بسلسلة الرابطات، ويسقط إلى الافتراضيِّ القديم.
  ///
  /// ── لماذا لا `getDefaultTemplateWithDataByCategory` وحدَها ──────────────
  /// `isDefault` عَلَمٌ **عالميٌّ لا يعرف فرعاً ولا طابعةً ولا لغة**. وجدولُ
  /// `TemplateBindings` والسلسلةُ السباعيّةُ شُحنا ليحلّا محلَّه — و`grep`
  /// يقول إنّ **لا سطرَ في مسار الطباعة كان يستشيرهما**. فزرُّ «تفعيل
  /// كافتراضي» في المكتبة كان سيكتب رابطةً لا تصل ورقةً أبداً.
  ///
  /// والسقوطُ مضمون: المستوى الأخيرُ في السلسلة هو عينُ الافتراضيِّ
  /// بالفئة، فقاعدةٌ بلا رابطاتٍ تحسم كما كانت بالضبط — والبصماتُ السبعُ
  /// والعشرون هي البرهان.
  static Future<InvoiceTemplateWithData?> _resolveTemplate({
    required AppDatabase db,
    required String type,
    required String category,
    String? documentType,
    int? branchId,
    String? locale,
  }) async {
    if (documentType != null) {
      try {
        final r = await db.resolveTemplateFor(
          documentType: documentType,
          category: category,
          branchId: branchId,
          locale: locale,
          paperType: type,
        );
        if (r.templateId != null) {
          final data = await db.getTemplateWithData(r.templateId!);
          if (data != null) {
            unawaited(DiagnosticLogger.log(DiagnosticLogger.printOut,
                'resolve level=${r.level} template=${r.templateId}'));
            return data;
          }
        }
      } catch (e) {
        // حسمٌ منهارٌ يعني فاتورةً لا تُطبع. فالسلسلةُ تسقط ولا تُسقِط
        // المطبوعَ معها.
        debugPrint('[TemplatedInvoice] resolve failed, falling back: $e');
      }
    }
    // ── السقوطُ الافتراضيّ ────────────────────────────────────────────
    //
    // والمطبخُ يُفهرَس **بالنوع وحدَه**: قوالبُه تحمل `type='kitchen'` وقد
    // تحمل أيَّ فئة — ملفُّ `kitchen_professional.json` بلا
    // `templateCategory` أصلاً فيُستورد فئتُه `receipt`. فالبحثُ بالفئة
    // يُفلته، وهذا هو سببُ الاستثناء لا تفضيلٌ له.
    if (category == 'kitchen') {
      return db.getDefaultTemplateWithData('kitchen');
    }
    return db.getDefaultTemplateWithDataByCategory(type, category);
  }

  /// الدفعُ إلى الطابعة — موضعٌ واحدٌ يخدم نسختَي التخطيط.
  ///
  /// نسخةٌ ثانيةٌ من حلِّ الطابعة تعني أنّ إصلاحَ «المطبخُ يخرج على طابعة
  /// الكاشير» يُصلَح في أحدهما ويبقى في الآخر.
  static Future<bool> _pushToPrinter({
    required AppDatabase db,
    required Uint8List bytes,
    required bool directPrint,
    required String category,
  }) async {
    if (directPrint) {
      final printersRepo = PrintersRepositoryImpl(db);
      final resolvedPrinter = category == 'kitchen'
          ? await PrinterResolver.resolveByPurpose(printersRepo, 'kitchen')
          : await PrinterResolver.resolveReceiptPrinter(printersRepo);

      if (resolvedPrinter != null) {
        debugPrint('[TemplatedInvoice] Printing ($category) to: ${resolvedPrinter.name}');
        await Printing.directPrintPdf(
          printer: resolvedPrinter,
          onLayout: (_) => bytes,
        );
        return true;
      }
      debugPrint(
        '[TemplatedInvoice] No configured $category printer, showing print dialog',
      );
    }
    return PdfComputeHelper.layoutBytes(bytes);
  }

  /// حمولةُ القيم — تُبنى مرّةً ويقرؤها المسارُ الجديد.
  ///
  /// و`_docDecimals` تُحسم قبل هذا في `printWithTemplate` من إعدادات
  /// الجدول، فالمساران يقرآن نفسَ المنازل.
  // ── §٤‑٦ — نسبةُ الضريبة على الورقة تأتي من الإعداد ──────────────────────
  //
  // قرارُ المالك 2026-08-31: الورقةُ تطابق الشاشة. والشاشةُ تعرض
  // `pos_default_tax_rate` مئويّةً، فالورقةُ مثلُها.
  //
  // وكانت النسبةُ **نصّاً في القالب** (‏«ضريبة القيمة المضافة ١٤٪») فتكذب على
  // كلِّ منشأةٍ نسبتُها غيرُ ذلك — ونُزعت. وهذا يُعيدها **محسوبةً**.

  /// حقلٌ يعرض مبلغَ ضريبةِ المستند — لا عمودَ ضريبةٍ في جدول الأصناف.
  ///
  /// ⚠️ **والمخطَّطان معاً**: القوالبُ الحديثةُ `variable`+`tax_amount`،
  /// و`a4_commercial` القديمُ نوعُه `tax` بلا `content`.
  static bool _isDocumentTaxField(InvoiceTemplateElement e) =>
      e.elementType == 'tax' ||
      e.content == 'tax' ||
      e.content == 'tax_amount';

  /// النسبةُ المئويّةُ من الإعداد — أو `null` إن تعذّرت القراءة.
  ///
  /// التخزينُ **كسريّ** (‏0.14 = ١٤٪) كما `posDefaultTaxRateProvider`،
  /// والافتراضُ نفسُه كي لا تختلف الورقةُ عن الشاشة.
  static Future<double?> _systemTaxPercent(AppDatabase db) async {
    try {
      final raw = await db.getSettingValue('pos_default_tax_rate');
      final rate = raw == null ? 0.16 : (double.tryParse(raw) ?? 0.16);
      return rate * 100;
    } catch (_) {
      // إعدادٌ لا يُقرأ لا يُسقط طباعةً — تبقى التسميةُ بلا نسبة.
      return null;
    }
  }

  /// ١٦ لا ١٦٫٠٠ · و١٢٫٥ تبقى ١٢٫٥.
  ///
  /// ⚠️ **ولا `v == v.roundToDouble()`**: التخزينُ كسريٌّ والضربُ في ١٠٠
  /// عائمٌ ثنائيّ، فـ`0.07 * 100` تساوي `7.000000000000001` — فتُطبع على
  /// الورقة بحرفها. مقيسٌ لا مفترَض. والتقريبُ ثمّ قصُّ الأصفار يحسمها،
  /// و`toStringAsFixed` يضمن وجودَ فاصلةٍ فلا يُبتر رقمٌ صحيح.
  static String _fmtPercent(double v) =>
      v.toStringAsFixed(3).replaceFirst(RegExp(r'\.?0+$'), '');

  /// يُلحق النسبةَ بتسمية حقلِ الضريبة — **موضعٌ واحدٌ يكفي المحرّكَين**.
  ///
  /// كلاهما يقرأ `labelAr`/`labelEn` من العنصر نفسِه (‏`_resolveValue` في
  /// راسم التدفّق، و`_labelOf` في مسار النطاقات)، فالتزيينُ هنا يغطّي ١ و٢
  /// معاً بلا تكرارِ منطقٍ في راسمَين.
  ///
  /// ⚠️ **و`ltrTagInRtl` شرطٌ لا زينة**: مقيسٌ أنّ `١٤٪` تصل الورقةَ `٤١٪`
  /// و`(14%)` تصل `(%14)` — الرقمُ ينقلب داخلَ فقرةٍ عربيّة بقاعدة W2.
  /// وLRM في الصدر يصير أقربَ صنفٍ قويٍّ سابقٍ فتبقى الأرقامُ `EN` وتتّصل.
  ///
  /// وRLM في الختم لا LRM: راسمُ التدفّق يكتب `'$label: $value'` سطراً
  /// واحداً، وختمٌ يساريٌّ يجرّ النقطتين **والقيمةَ** إلى جزيرةٍ واحدةٍ
  /// فتُرسَم القيمةُ يمينَ النسبة — أي تُقرأ قيمةٌ في موضع نسبة. مقيسٌ على
  /// البصمة الذهبيّة، وتفصيلُه في [pv.ltrTagInRtl].
  ///
  /// ولا تُلحَق بتسميةٍ فارغة: «14%» وحدَها في مكان التسمية أسوأُ من غيابها.
  static Future<List<InvoiceTemplateElement>> _withTaxRateLabels(
    AppDatabase db,
    List<InvoiceTemplateElement> elements,
  ) async {
    if (!elements.any(_isDocumentTaxField)) return elements;

    final percent = await _systemTaxPercent(db);
    if (percent == null || percent <= 0) return elements;
    final suffix = ' ${pv.ltrTagInRtl('${_fmtPercent(percent)}%')}';

    return [
      for (final e in elements)
        if (!_isDocumentTaxField(e))
          e
        else
          e.copyWith(
            labelAr: (e.labelAr == null || e.labelAr!.isEmpty)
                ? const Value.absent()
                : Value('${e.labelAr}$suffix'),
            labelEn: (e.labelEn == null || e.labelEn!.isEmpty)
                ? const Value.absent()
                : Value('${e.labelEn}$suffix'),
          ),
    ];
  }

  static pv.PrintPayload _payloadOf({
    required String invoiceNumber,
    required DateTime date,
    String? customerName,
    String? customerPhone,
    String? customerAddress,
    String? adhocCustomerName,
    String? adhocCustomerPhone,
    required String companyName,
    required String companyAddress,
    required String companyPhone,
    String? companyTaxId,
    required String paymentMethod,
    String? cashierName,
    String? notes,
    required double subtotal,
    required double discount,
    required double tax,
    required double deliveryFee,
    required double total,
    required double paid,
    String? orderNumber,
    String? platformOrderNumber,
    double? cashAmount,
    double? bankAmount,
    String? companyNameEn,
    String? companyCrNumber,
    String locale = 'ar',
  }) =>
      pv.PrintPayload(
        invoiceNumber: invoiceNumber,
        date: date,
        customerName: customerName,
        customerPhone: customerPhone,
        customerAddress: customerAddress,
        adhocCustomerName: adhocCustomerName,
        adhocCustomerPhone: adhocCustomerPhone,
        companyName: companyName,
        companyAddress: companyAddress,
        companyPhone: companyPhone,
        companyTaxId: companyTaxId,
        companyNameEn: companyNameEn,
        companyCrNumber: companyCrNumber,
        locale: locale,
        paymentMethod: paymentMethod,
        cashierName: cashierName,
        notes: notes,
        subtotal: subtotal,
        discount: discount,
        tax: tax,
        deliveryFee: deliveryFee,
        total: total,
        paid: paid,
        remaining: total - paid,
        orderNumber: orderNumber,
        platformOrderNumber: platformOrderNumber,
        cashAmount: cashAmount,
        bankAmount: bankAmount,
        decimals: _docDecimals,
      );
}
