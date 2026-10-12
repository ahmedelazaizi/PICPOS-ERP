import 'dart:async' show unawaited;
import 'dart:convert';
// ⚠️ `show Value` وحدَها: استيرادُ drift كاملاً يُظلّل `isNull`/`isNotNull`
// اللتين يعرّفهما `matcher` — وهو التباسٌ وقع في هذا المستودع من قبل.
import 'package:drift/drift.dart' show Value;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'generators/base_generator.dart';
import 'package:printing/printing.dart';
import 'printing/pdf_compute_helper.dart';
import 'printing/pdf_text_sanitizer.dart' show sanitizeForPdf;
import 'package:flutter/foundation.dart';
import '../core/logging/diagnostic_logger.dart';
import '../core/utils/template_json_flags.dart';
import '../data/database/database.dart';
import '../domain/entities/shift_closing_snapshot.dart';
import '../domain/models/receipt_qr_decision.dart';
import '../domain/printing/company_identity.dart';
import '../domain/printing/print_values.dart' as pv;
import '../domain/printing/party_statement_snapshot.dart';
import 'printing/paint_plan.dart' show PaintDirection;
import 'printing/template_render_pipeline.dart';
import '../data/repositories/printers_repository_impl.dart';
import 'printer_resolver.dart';

part 'templated_invoice_service/template_render_state.dart';
part 'templated_invoice_service/template_element_types.dart';
part 'templated_invoice_service/template_resolution.dart';
part 'templated_invoice_service/template_values.dart';
part 'templated_invoice_service/template_element_content.dart';
part 'templated_invoice_service/template_layout.dart';
part 'templated_invoice_service/template_items_table.dart';
part 'templated_invoice_service/template_barcode_labels.dart';

/// خدمة طباعة الفواتير باستخدام القوالب المخصصة
/// تقرأ القالب الافتراضي وتطبق إعداداته على PDF الفاتورة
class TemplatedInvoiceService {
  static pw.Font? _arabicFont;

  /// دقّةُ الأرقام في المستند المطبوع — **خانتان، والمصدرُ واحد.**
  ///
  /// البلاغ الميدانيّ (2026-08-11): «خانتان عشريتان في الجدول وثلاثٌ في
  /// الإجماليات» — في **نفس الورقة**. مصدران مستقلّان: الجدولُ كان يبدأ من
  /// رقمٍ مكتوبٍ عنده، والإجمالياتُ تُنسَّق بـ`AppConstants.decimalPlaces`.
  ///
  /// والمطبوعُ سطحُ عرضٍ له عرفُه: إيصالٌ حراريٌّ يكتب «2.000» لقطعتَي جبنٍ
  /// يقرؤه العميلُ ثقيلاً. فدقّةُ الإيصال ثنتان، ودفاترُ النظام تبقى على
  /// `AppConstants.decimalPlaces` بلا مساس — الثابتةُ المحروسةُ ليست «رقمٌ
  /// بعينه» بل **دقّةٌ واحدةٌ داخل المستند الواحد**.
  ///
  /// ويتجاوزها `_decimalPlaces` في إعدادات جدول القالب حين يضبطه المستخدم،
  /// فتسري على الجدول **والإجماليات معاً** — لا على الجدول وحدَه كما كان.
  static const int kReceiptDecimalPlaces = 2;

  static int _resolveDocDecimals(InvoiceTableSetting? settings) {
    final raw = settings?.columnWidths;
    if (raw == null || raw.isEmpty) return kReceiptDecimalPlaces;
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final v = decoded['_decimalPlaces'];
      if (v is num) return v.toInt();
    } catch (_) {}
    return kReceiptDecimalPlaces;
  }

  /// Style of an element as it reaches the paper (measurement handle).
  @visibleForTesting
  static Future<pw.TextStyle> debugStyleFor({required bool isBold}) =>
      _TemplatedItemsTable.debugStyleFor(isBold: isBold);

  @visibleForTesting
  static Future<Uint8List> debugRenderItemsTable({
    required List<Map<String, dynamic>> items,
    InvoiceTableSetting? settings,
    double paperWidthMm = 79,
  }) =>
      _TemplatedItemsTable.debugRenderItemsTable(
        items: items,
        settings: settings,
        paperWidthMm: paperWidthMm,
      );

  /// إضافاتُ كلّ البنود مجموعةً بلا تكرار — فارغةٌ حين لا إضافات.
  static String extractItemAdditions(List<Map<String, dynamic>> items) =>
      _TemplatedInvoiceValues.extractItemAdditions(items);

  /// `(المجموعة: القيمة)` ⇒ «القيمة». اسمُ المجموعة يُسقط: «كبير» تكفي
  /// القارئَ، و«الحجم: كبير» تطيل سطراً على ورقٍ عرضُه ٨٠ ملّيمتراً.
  static String extractItemOptions(List<Map<String, dynamic>> items) =>
      _TemplatedInvoiceValues.extractItemOptions(items);

  /// قيمةُ عنصرِ ورديةٍ من لقطة الإقفال — أو `null` لو النوعُ ليس منها.
  ///
  /// `null` لا `''` عمداً: المنادي يفرّق بها بين «نوعٌ لا يخصّني» و«يخصّني
  /// وقيمتُه فارغة»، فلا يبتلع الثاني.
  ///
  /// محرِّرُ القوالب يعرض هذه الأنواعَ الستّةَ عشر تحت قالب `shift_closing`،
  /// وكانت كلُّها تسقط على `default: return ''` — فالعنصرُ بلا تسميةٍ يرجع
  /// `SizedBox()` أي **يختفي**، وبتسميةٍ يطبع تسميةً معلَّقةً بلا رقم.
  static String? resolveShiftValue(String type, ShiftClosingSnapshot s) =>
      _TemplatedInvoiceValues.resolveShiftValue(type, s);

  /// التحقق من وجود قالب افتراضي لنوع معين (مع فئة اختيارية)
  static Future<bool> hasDefaultTemplate(
    AppDatabase db,
    String type, {
    String? category,
  }) async {
    if (category != null) {
      // When a specific category is requested, only check that category.
      // Do NOT fall back to any thermal template — kitchen ≠ receipt.
      final template = await db.getDefaultTemplateByCategory(type, category);
      return template != null;
    }
    final template = await db.getDefaultTemplate(type);
    return template != null;
  }

  /// طباعة فاتورة باستخدام القالب المخصصة (Thermal أو A4)
  static Future<({Uint8List bytes, bool printed})> printWithTemplate({
    required AppDatabase db,
    required String invoiceNumber,
    required DateTime date,
    required String? customerName,
    required String? customerPhone,
    required String? customerAddress,
    required List<Map<String, dynamic>> items,
    required double subtotal,
    required double discount,
    required double tax,
    required double deliveryFee,
    required double total,
    required double paid,
    required String companyName,
    required String companyAddress,
    required String companyPhone,
    required String? companyTaxId,
    Uint8List? logoBytes,
    String paymentMethod = 'نقدي',
    bool directPrint = false,
    String type = 'thermal',
    String category = 'receipt',
    String? cashierName,
    String? notes,
    String? adhocCustomerName,
    String? adhocCustomerPhone,
    String? salesType,
    String? orderNumber,
    String? platformOrderNumber,
    String locale = 'ar',
    /// مبلغا الاسترداد في مرتجع المبيعات — يحلّان `cash_amount` و
    /// `bank_amount`. كانا يُرجعان `''` دائماً («حقولٌ لم تصل الخدمةَ بعد»)،
    /// فمرتجعٌ نصفُه نقدٌ ونصفُه بنكيٌّ يُطبع بلا تفصيلٍ للاسترداد.
    double? cashAmount,
    double? bankAmount,
    /// لقطةُ إقفال الوردية — تُمرَّر حين يكون المطبوعُ تقريرَ وردية
    /// (`type: 'shift_closing'`)، فتُحلّ بها عناصرُ `shift_*` التي يعرضها
    /// محرّرُ القوالب. `null` لكلّ مطبوعٍ آخر.
    ShiftClosingSnapshot? shift,

    /// لقطةُ كشف حساب الطرف — تُمرَّر حين يكون المطبوعُ كشفاً
    /// (`documentType: 'party_statement'`). `null` لكلّ مطبوعٍ آخر.
    ///
    /// ⚠️ ومُحلِّلُها يُسأل **قبل** مُحلِّل الفاتورة ويُرجع `null` لما ليس له،
    /// فلا يخطف حقلاً — نفسُ عقد [shift].
    PartyStatementSnapshot? statement,

    /// نوعُ المستند في سلسلة الحسم (`sales_invoice` · `sales_return` …).
    ///
    /// `null` يعني «لا رابطاتٍ تُستشار» فيسقط الحسمُ فوراً إلى الافتراضيِّ
    /// القديم — وهو سلوكُ كلِّ منادٍ لم يُحدَّث بعد.
    String? documentType,

    /// فرعُ المستند — رابطةٌ مخصَّصةٌ لفرعٍ تتقدّم على العامّة.
    int? branchId,

    /// قرارُ رمز الإيصال — ضريبيٌّ أو غيرُ ضريبيٍّ أو لا شيء.
    ///
    /// `null` تُبقي السلوكَ القديم (رقمُ الفاتورة) للمستندات التي ليست إيصالَ
    /// بيعٍ أصلاً. وإيصالُ البيع يمرّره من `printing_service` بعد حلّه من
    /// القاعدة (‏`resolveReceiptQrForSale`).
    ReceiptQr? receiptQr,

    /// تُبنى الوثيقةُ وتُعاد بايتاتُها **بلا دفعٍ إلى الطابعة**.
    ///
    /// كانت هذه الدالّةُ تبني `pw.Document` وتدفعه إلى `Printing.*` في نفس
    /// النَّفَس، فلا مِقبضَ يقيس ما يصل الورقة — ولذلك كانت حراسُ المطبوع
    /// **بنيويةً** تقرأ المصدرَ ولا ترى ورقة. واختباراتُ التوصيف تحتاج
    /// البايتات: ترسم القوالبَ المبذورةَ كلَّها وتُثبّت بصمتَها قبل أن
    /// يتحرّك سطرٌ واحدٌ في الراسم.
    ///
    /// ولا يغيّر هذا المطبوعَ بحرف: نفسُ الوثيقةِ تُبنى في الحالتين.
    @visibleForTesting
    bool debugBuildOnly = false,
  }) async {
    await _initFont();

    // الاسمُ الإنجليزيُّ والسجلُّ التجاريّ من إعدادات الشركة (يحفظهما معالجُ
    // الإعداد وتحرّرهما «معلومات الشركة»). تُقرأ هنا لا في كلّ منادٍ: عشراتُ
    // المنادين يمرّرون الاسمَ والرقمَ الضريبيَّ ولا أحدَ منهم يعرف هذين.
    // الفارغُ يبقى فارغاً فلا يُطبع شيء.
    final companyNameEn =
        (await db.getSettingValue(kCompanyNameEnSetting))?.trim();
    final companyCrNumber =
        (await db.getSettingValue(kCompanyCrNumberSetting))?.trim();

    // Derive lookup type from category: kitchen templates have type='kitchen'
    final InvoiceTemplateWithData? templateData;
    templateData = await _TemplatedInvoiceResolution._resolveTemplate(
      db: db,
      type: type,
      category: category,
      documentType: documentType,
      branchId: branchId,
      locale: locale,
    );

    if (templateData == null) {
      throw Exception('لا يوجد قالب افتراضي - سيتم استخدام التصميم الافتراضي');
    }

    // أيُّ قالبٍ أخرج هذا المستند — أوّلُ سؤالٍ عند أيّ بلاغِ طباعة.
    unawaited(DiagnosticLogger.log(
        DiagnosticLogger.printOut,
        'renderer=TemplatedInvoiceService type=$type category=$category '
        'template="${templateData.template.name}" '
        'paper=${templateData.template.paperWidth}mm '
        'elements=${templateData.elements.length} '
        'shift=${shift != null}'));

    final elements =
        await _TemplatedInvoiceResolution._withTaxRateLabels(db, orderElementsForPrint(templateData.elements));

    debugPrint(
      '[TemplatedInvoice] Template: "${templateData.template.name}", elements: ${elements.length}, items: ${items.length}',
    );

    // ── بوّابةُ نسخة التخطيط ────────────────────────────────────────────
    //
    // ١ = التدفّقُ القديم (‏`sortOrder` + `flexWidth`) — يبقى بحرفه.
    // ٢ = النطاقاتُ بإحداثيّاتٍ بالمليمتر عبر المحرّك.
    //
    // والقوالبُ غيرُ المهاجَرة كلُّها عند ١، فلا يتغيّر مطبوعٌ واحدٌ اليوم.
    // وهذا مقيسٌ لا مأمول: سبعٌ وعشرون بصمةً ذهبيّةً في
    // `test/unit/printing_characterization_test.dart`.
    if (templateData.template.layoutVersion >= kBandLayoutVersion) {
      // ⚠️ المنازلُ تُحسم **قبل** بناء الحمولة. `_docDecimals` ساكنٌ يحمل
      // قيمةَ آخرِ مستندٍ طُبع، فالبوّابةُ تقع قبل موضع حسمِه في المسار
      // القديم — ولولا هذا السطر لطُبعت فاتورةٌ بمنازلِ التي سبقتها.
      _docDecimals = _resolveDocDecimals(templateData.tableSettings);

      final bytes = await TemplateRenderPipeline.render(
        template: templateData.template,
        orderedElements: elements,
        tableSettings: templateData.tableSettings,
        payload: _TemplatedInvoiceResolution._payloadOf(
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
          paymentMethod: paymentMethod,
          cashierName: cashierName,
          notes: notes,
          subtotal: subtotal,
          discount: discount,
          tax: tax,
          deliveryFee: deliveryFee,
          total: total,
          paid: paid,
          orderNumber: orderNumber,
          platformOrderNumber: platformOrderNumber,
          cashAmount: cashAmount,
          bankAmount: bankAmount,
          companyNameEn: companyNameEn,
          companyCrNumber: companyCrNumber,
          locale: locale,
        ),
        items: items,
        direction: locale == 'en' ? PaintDirection.ltr : PaintDirection.rtl,
        logoBytes: logoBytes,
        statement: statement,
      );
      if (debugBuildOnly) return (bytes: bytes, printed: false);
      final printed = await _TemplatedInvoiceResolution._pushToPrinter(
        db: db,
        bytes: bytes,
        directPrint: directPrint,
        category: category,
      );
      return (bytes: bytes, printed: printed);
    }

    final pdf = await BaseGenerator.newDocument();
    final remaining = total - paid;

    const mmToPoints = 2.8346;
    // For thermal printers (80mm paper), the actual print head width is ~72mm.
    // The remaining 8mm is non-printable hardware margin (4mm each side).
    final paperWidthMm = templateData.template.paperWidth;
    final printableWidthMm = paperWidthMm <= 80
        ? paperWidthMm - 8  // 80mm → 72mm actual printable
        : paperWidthMm;      // A4 stays as-is
    final canvasWidth = printableWidthMm * mmToPoints;
    final ts = templateData.tableSettings;
    _docDecimals = _resolveDocDecimals(ts);

    // ─── FLOW-BASED LAYOUT ───────────────────────────────────────────
    // Matches the Section Editor's preview: elements flow vertically,
    // consecutive inline elements (flexWidth < 100) share a row with
    // Expanded, single elements take full paper width.
    // Text wraps naturally — no clipping, fits within paper size.

    // --- Helper to resolve element type (wraps static) ---
    String resolveType(InvoiceTemplateElement element) => _TemplatedInvoiceValues._resolveType(element);

    pw.Widget buildFlowWidget(InvoiceTemplateElement element) {
      final resolvedType = resolveType(element);

      // ── الشعارُ يمرُّ بـ`_buildElementContent` كسائر العناصر ──────────────
      //
      // كان هنا اعتراضٌ يقرأ `element.width` **نسبةً مئويّة**
      // (‏`width / 100` من عرض الورقة) ويحسب الارتفاعَ `0.65×` متجاهلاً
      // `element.height`. وهو خطأٌ في الوحدة: `width` نقاطٌ كما في كلِّ عنصرٍ
      // آخر، ومقيسٌ أنّ الأثرَ ستّةُ أضعافٍ تقريباً في **كلِّ** قالب:
      //
      //   a4_professional  ١٣٠ نقطةً مكتوبةً ⇒ ٥٩٥ مطبوعةً (عرضُ الورقة)
      //   a4_commercial    ١٠٠            ⇒ ٥٩٥
      //   القوالبُ الحديثة  ٣٨             ⇒ ٢٢٦
      //
      // فشعارُ المنشأة يخرج على ورقتها بعرض A4 كاملاً وارتفاعِ ٣٨٧ نقطةً —
      // ٤٦٪ من الصفحة. وحين لا شعارَ مضبوطاً كان يُملأ ذلك الصندوقُ بكلمة
      // `LOGO` الحرفيّة، وهي التي تدفع المجاميعَ إلى صفحةٍ ثانية.
      //
      // والتنفيذُ الصحيحُ كان **موجوداً وميّتاً** في `_buildElementContent`
      // يقرأ `width`/`height` نقاطاً — يعترضه هذا البلوكُ قبل أن يُبلَغ.
      // فحُذف، ولا سقفَ حراريٌّ يلزم: أوسعُ شعارٍ مكتوبٍ ٩٠ نقطةً على ورقةٍ
      // سعتُها ٢٠٤، وأوسعُ A4 ‏١٣٠ على ٥٩٥.

      return _TemplatedElementContent._buildElementContent(
        resolvedType: resolvedType,
        element: element,
        shift: shift,
        statement: statement,
        invoiceNumber: invoiceNumber,
        date: date,
        customerName: customerName,
        customerPhone: customerPhone,
        customerAddress: customerAddress,
        items: items,
        subtotal: subtotal,
        discount: discount,
        tax: tax,
        deliveryFee: deliveryFee,
        total: total,
        paid: paid,
        remaining: remaining,
        companyName: companyName,
        companyAddress: companyAddress,
        companyPhone: companyPhone,
        companyTaxId: companyTaxId,
        paymentMethod: paymentMethod,
        tableSettings: ts,
        logoBytes: logoBytes,
        cashierName: cashierName,
        notes: notes,
        adhocCustomerName: adhocCustomerName,
        adhocCustomerPhone: adhocCustomerPhone,
        salesType: salesType,
        orderNumber: orderNumber,
        platformOrderNumber: platformOrderNumber,
        cashAmount: cashAmount,
        bankAmount: bankAmount,
        receiptQr: receiptQr,
        companyNameEn: companyNameEn,
        companyCrNumber: companyCrNumber,
        locale: locale,
      );
    }

    // ── Group elements: consecutive inline (flexWidth < 100) → row ──
    // التسلسلُ يُحسم في `layoutSequenceForPrint` — بذرةٌ خالصةٌ تُقاس آلياً.
    // و`null` فيه = جدولُ الأصناف المُقحَم استدلالاً (قوالبُ بلا عنصرِ جدول).
    final layoutSequence =
        layoutSequenceForPrint(elements, hasItems: items.isNotEmpty);

    final contentWidgets = <pw.Widget>[];
    int i = 0;

    while (i < layoutSequence.length) {
      final el = layoutSequence[i];

      if (el == null) {
        contentWidgets.add(_TemplatedItemsTable._buildItemsTable(
          items,
          ts,
          pw.TextStyle(font: _arabicFont, fontSize: ts?.fontSize ?? 9),
        ));
        i++;
        continue;
      }

      // Check if this element and the next form an inline group
      // (الجدولُ المُقحَمُ يقطع الصفَّ — لا يُضمّ إلى مجموعةٍ جانبية)
      if (el.flexWidth < 100 &&
          i + 1 < layoutSequence.length &&
          layoutSequence[i + 1] != null) {
        // Collect consecutive inline elements
        final group = <InvoiceTemplateElement>[el];
        while (i + group.length < layoutSequence.length &&
            group.last.flexWidth < 100 &&
            layoutSequence[i + group.length] != null) {
          group.add(layoutSequence[i + group.length]!);
        }
        // If last element in group is NOT inline, it was just pulled in
        // as the "next" — that's correct for side-by-side layout

        try {
          contentWidgets.add(
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: group
                  .map((g) => pw.Expanded(child: buildFlowWidget(g)))
                  .toList(),
            ),
          );
        } catch (e) {
          debugPrint(
            '[TemplatedInvoice] ❌ Row group FAILED: $e',
          );
        }
        i += group.length;
      } else {
        // Single element — full width
        try {
          contentWidgets.add(buildFlowWidget(el));
        } catch (e) {
          debugPrint(
            '[TemplatedInvoice] ❌ Element "${el.elementType}" FAILED: $e',
          );
        }
        i++;
      }
    }

    // ── Build the page — thermal uses minimal margins, A4 uses standard ──
    final isThermalPrint = templateData.template.paperWidth <= 80;
    final marginMm = isThermalPrint ? 2.0 : 4.0;
    _TemplatedInvoiceLayout._addDocumentPages(
      pdf,
      content: contentWidgets,
      canvasWidth: canvasWidth,
      canvasHeightPts: _TemplatedInvoiceLayout._pageHeightPoints(templateData.template),
      marginPts: marginMm * mmToPoints,
      direction:
          locale == 'en' ? pw.TextDirection.ltr : pw.TextDirection.rtl,
    );

    // البايتاتُ تُحسب مرّةً واحدةً ثم تُقدَّم لكلِّ مسارٍ — بدلَ استدعاء
    // `pdf.save()` داخلَ كلِّ `onLayout`. نفسُ المخرَج، ونداءٌ واحد.
    final bytes = await pdf.save();
    if (debugBuildOnly) return (bytes: bytes, printed: false);

    final printed = await _TemplatedInvoiceResolution._pushToPrinter(
      db: db,
      bytes: bytes,
      directPrint: directPrint,
      category: category,
    );
    return (bytes: bytes, printed: printed);
  }

  /// Print order of the template elements (see template_layout.dart).
  static List<InvoiceTemplateElement> orderElementsForPrint(
    List<InvoiceTemplateElement> all,
  ) =>
      _TemplatedInvoiceLayout.orderElementsForPrint(all);

  /// عددُ صفحات مستندٍ بأصنافٍ معلومة — للقياس الآليّ للتقسيم.
  @visibleForTesting
  static Future<int> debugPageCount({
    required List<Map<String, dynamic>> items,
    required double paperWidthMm,
    double? paperHeightMm,
  }) async {
    final pdf = await _TemplatedInvoiceLayout._buildPaginationProbe(
      items: items,
      paperWidthMm: paperWidthMm,
      paperHeightMm: paperHeightMm,
    );
    await pdf.save();
    return pdf.document.pdfPageList.pages.length;
  }

  /// نفسُ المستند بايتاتٍ — كي يُرسَّم ويُنظر إليه.
  @visibleForTesting
  static Future<Uint8List> debugRenderPaginated({
    required List<Map<String, dynamic>> items,
    required double paperWidthMm,
    double? paperHeightMm,
  }) async {
    final pdf = await _TemplatedInvoiceLayout._buildPaginationProbe(
      items: items,
      paperWidthMm: paperWidthMm,
      paperHeightMm: paperHeightMm,
    );
    return pdf.save();
  }

  /// تسلسلُ ما يُرسم فعلاً: عناصرُ القالب مرشَّحةً، وقد وقع جدولُ الأصناف
  /// موقعَه بينها. العنصرُ `null` في الناتج = جدولُ الأصناف.
  static List<InvoiceTemplateElement?> layoutSequenceForPrint(
    List<InvoiceTemplateElement> ordered, {
    required bool hasItems,
  }) =>
      _TemplatedInvoiceLayout.layoutSequenceForPrint(ordered, hasItems: hasItems);

  /// كودُ طريقة الدفع → تسميتُه العربية.
  ///
  /// §٥-٣ (بلاغٌ ميدانيّ 2026-08-11): الإيصالُ طبع «طريقة الدفع: cash». كان
  /// `payment_method` يُطبع **خاماً** كما يصل من المنادي، ولا مُحوِّلَ له —
  /// بينما `_mapSaleTypeLabel` المجاور يحوّل نوعَ البيع منذ البداية. فالكودُ
  /// الإنجليزيُّ يظهر للعميل في إيصالٍ عربيٍّ بالكامل.
  ///
  /// وما لا يُعرف يُعاد كما هو لا يُبتلع: تسميةٌ عربيةٌ وصلت جاهزةً من منادٍ
  /// آخر تمرّ، وكودٌ جديدٌ يظهر فيُرى بدل أن يختفي صامتاً.
  static String mapPaymentMethodLabel(String method) =>
      pv.mapPaymentMethodLabel(method);

  /// هل هذا السطرُ فاصلَ تصنيفٍ لا صنفاً؟
  ///
  /// `== true` لا `as bool?`: القيمةُ تعبر حدَّ `Map<String, dynamic>` وقد
  /// تصل نصّاً من JSON، والرميةُ تُسقط المطبوعَ كلَّه بدل أن تقرأ.
  @visibleForTesting
  static bool isCategoryHeaderRow(Map<String, dynamic> item) =>
      item['isCategoryHeader'] == true;

  // ═══════════════════════════════════════════════════════════════════════════
  // BARCODE LABEL PRINTING
  // ═══════════════════════════════════════════════════════════════════════════

  /// طباعة ملصقات باركود باستخدام القالب المحفوظ
  /// Prints barcode labels using a saved barcode template design.
  /// Each label is laid out according to the template's paper size,
  /// with multiple labels arranged in a grid on A4 pages.
  static Future<bool> printBarcodeWithTemplate({
    required AppDatabase db,
    required String barcodeValue,
    required String productName,
    String? productCode,
    double? price,
    String? companyName,
    int copies = 1,
    bool directPrint = true,
    int? templateId,
  }) =>
      _TemplatedBarcodeLabels.printBarcodeWithTemplate(
        db: db,
        barcodeValue: barcodeValue,
        productName: productName,
        productCode: productCode,
        price: price,
        companyName: companyName,
        copies: copies,
        directPrint: directPrint,
        templateId: templateId,
      );
}
