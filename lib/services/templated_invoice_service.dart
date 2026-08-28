import 'dart:async' show unawaited;
import 'dart:convert';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'generators/base_generator.dart';
import 'package:printing/printing.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import '../core/logging/diagnostic_logger.dart';
import '../core/utils/template_json_flags.dart';
import '../data/database/database.dart';
import '../domain/entities/shift_closing_snapshot.dart';
import '../data/repositories/printers_repository_impl.dart';
import 'printer_resolver.dart';

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

  /// دقّةُ المستند الجاري طبعُه. تُحسم مرّةً في `printWithTemplate` **قبل**
  /// بناء أيّ عنصر، لأن الإجمالياتِ قد تُبنى قبل الجدول أو بعده بحسب ترتيب
  /// الأقسام — فحسمُها داخل باني الجدول كان سيترك أحدَ الطرفين على قيمةٍ
  /// بائتة. والطباعةُ متسلسلةٌ فلا تتداخل مستندان.
  static int _docDecimals = kReceiptDecimalPlaces;

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

  /// الخطُّ من المصنع وحدَه.
  ///
  /// كان هنا سلَّمٌ خاصٌّ أوّلُه **Cairo** المحزوم. وCairo ينقصه الياءُ
  /// المنفصلة U+FEF1، فكلُّ اسمٍ آخرُه ي بعد حرفٍ غيرِ موصول («صبري» ·
  /// «بدري» · «المصري») يُطبع والياءُ راكبةٌ على ما قبلها. والمصنعُ عنده
  /// نفسُ السلَّم بأساسٍ يحمل الأشكالَ كلَّها (Noto Naskh).
  /// الوزنُ العريضُ **ملفٌّ لا خاصية**: الحزمة لا تصطنع العريض، فـ
  /// `FontWeight.bold` بلا وجهٍ عريضٍ محمَّلٍ يسقط على العاديّ بلا أثر —
  /// موثَّقٌ في `base_generator.dart:44`. ورسمُ الإيصال أرى ذلك بالعين: صفُّ
  /// العناوين بعد رفع التعبئة عنه بقي بوزن البدن نفسِه.
  static pw.Font? _arabicBoldFont;

  static Future<void> _initFont() async {
    _arabicFont ??= await BaseGenerator.initFont();
    _arabicBoldFont ??= await BaseGenerator.initBoldFont();
  }

  /// بايتاتُ جدولِ الأصناف كما يُرسَم فعلاً — **مِقبضٌ للقياس لا مسارُ إنتاج.**
  ///
  /// `printWithTemplate` يبني `pw.Document` ويدفعه إلى `Printing.*` مباشرةً،
  /// فلا تُرجع الوثيقةَ ولا البايتات. ولذلك كانت حراسُ المطبوع **بنيويةً**
  /// تمنع العودةَ ولا تثبت الخروج. وحين وصل بلاغُ «صفُّ عناوين الأعمدة لا
  /// يظهر في الطباعة» لم يكن ثمّة سبيلٌ لرسم المستند والنظر إليه — وهي
  /// الخطوةُ التي كشفت عطبَ الخطوط بعد ثلاث فرضياتٍ معقولةٍ خاطئة.
  ///
  /// فهذا يبني **نفسَ** الجدول بنفس الدالّة (`_buildItemsTable`) وبنفس هيئة
  /// الورق الحراريّ، ويعيد البايتات كي تُرسَّم وتُفحَص. لا يستنسخ منطقاً:
  /// أيُّ تغييرٍ في الجدول يظهر هنا فوراً.
  /// نمطُ عنصرٍ كما يصل الورقةَ — للقياس الآليّ لوجه الخطّ.
  ///
  /// النيّةُ (`fontWeight`) لم تكن يوماً هي المشكلة؛ **الوجهُ** هو الذي كان
  /// يخون. فيُقاس ما يُرسَم لا ما يُقصَد.
  @visibleForTesting
  static Future<pw.TextStyle> debugStyleFor({required bool isBold}) async {
    await _initFont();
    return _getStyle(InvoiceTemplateElement(
      id: 0,
      templateId: 0,
      elementType: 'variable',
      rowIndex: 0,
      sortOrder: 0,
      flexWidth: 100,
      xPosition: 0,
      yPosition: 0,
      width: 100,
      height: 20,
      textAlign: 'right',
      fontSize: 12,
      isBold: isBold,
      isItalic: false,
      fontColor: '#000000',
      borderWidth: 0,
      content: 'total_amount',
      isVisible: true,
      section: 'footer',
    ));
  }

  @visibleForTesting
  static Future<Uint8List> debugRenderItemsTable({
    required List<Map<String, dynamic>> items,
    InvoiceTableSetting? settings,
    double paperWidthMm = 79,
  }) async {
    await _initFont();
    const mmToPoints = 2.8346;
    final baseStyle = pw.TextStyle(font: _arabicFont, fontSize: 8);
    // `BaseGenerator.newDocument()` لا `pw.Document()` عارياً — وهو ما يستعمله
    // مسارُ الإنتاج في هذا الملفّ (‏السطران ٣٥٢ و١٥٩٣). المستندُ العاري بلا
    // ثيمٍ يرسم بخطٍّ واحدٍ لكلّ النصّ ويحذف الرسمَ الناقصَ بالسكوت، فمِقبضٌ
    // للقياس يبني بغير ما يبني به الإنتاجُ يقيس مستنداً آخر.
    // (‏حارسُ `no_bare_pdf_document_test` اصطاد هذا هنا فعلاً.)
    final pdf = await BaseGenerator.newDocument();
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(
          paperWidthMm * mmToPoints,
          double.infinity,
          marginAll: 2.0 * mmToPoints,
        ),
        textDirection: pw.TextDirection.rtl,
        build: (_) => _buildItemsTable(items, settings, baseStyle),
      ),
    );
    return pdf.save();
  }

  // ── إضافاتُ الصنف وخياراتُه ─────────────────────────────────────────────
  //
  // السلّةُ تركّب الاختياراتِ في نصٍّ واحدٍ (`composeCartItemNote`) يُخزَّن في
  // `sales_invoice_items.note` ويصل هنا في `item['note']`:
  //
  //   الخيار  ⇒ `(اسمُ المجموعة: [مستوى] الاسم)`
  //   الإضافة ⇒ `+الاسم [سعر عملة]`
  //   ملاحظةُ الكاشير ⇒ `📝 نصّ`
  //   والفصلُ بـ` | `
  //
  // فالاستخراجُ من هذا الشكل حتميّ. والملاحظةُ اليدوية لا تُخلط بهما:
  // «بدون بصل» ليست إضافةً ولا خياراً، وخلطُها يجعل المطبخَ يقرأ طلباً لم
  // يُطلب.

  /// أجزاءُ ملاحظةِ بندٍ واحد، مقسَّمةً على الفاصل.
  static Iterable<String> _noteParts(List<Map<String, dynamic>> items) sync* {
    for (final item in items) {
      final raw = (item['note'] as String?)?.trim();
      if (raw == null || raw.isEmpty) continue;
      for (final p in raw.split('|')) {
        final t = p.trim();
        if (t.isNotEmpty) yield t;
      }
    }
  }

  /// يحافظ على ترتيب أوّل ظهورٍ ويُسقط التكرار — الطباعةُ للقارئ لا للآلة.
  static String _joinUnique(Iterable<String> values) {
    final seen = <String>{};
    final out = <String>[];
    for (final v in values) {
      if (v.isEmpty || !seen.add(v)) continue;
      out.add(v);
    }
    return out.join('، ');
  }

  /// `+الاسم [سعر]` ⇒ «الاسم». السعرُ يُسقط: العنصرُ ملخّصٌ لا فاتورة.
  static final _additionPrice = RegExp(r'\s+[\d.,]+\s*\S*$');

  /// إضافاتُ كلّ البنود مجموعةً بلا تكرار — فارغةٌ حين لا إضافات.
  static String extractItemAdditions(List<Map<String, dynamic>> items) {
    return _joinUnique(_noteParts(items)
        .where((p) => p.startsWith('+'))
        .map((p) => p.substring(1).replaceAll(_additionPrice, '').trim()));
  }

  /// `(المجموعة: القيمة)` ⇒ «القيمة». اسمُ المجموعة يُسقط: «كبير» تكفي
  /// القارئَ، و«الحجم: كبير» تطيل سطراً على ورقٍ عرضُه ٨٠ ملّيمتراً.
  static String extractItemOptions(List<Map<String, dynamic>> items) {
    return _joinUnique(_noteParts(items)
        .where((p) => p.startsWith('(') && p.endsWith(')'))
        .map((p) {
      final inner = p.substring(1, p.length - 1);
      final colon = inner.indexOf(':');
      return (colon >= 0 ? inner.substring(colon + 1) : inner).trim();
    }));
  }

  /// قيمةُ عنصرِ ورديةٍ من لقطة الإقفال — أو `null` لو النوعُ ليس منها.
  ///
  /// `null` لا `''` عمداً: المنادي يفرّق بها بين «نوعٌ لا يخصّني» و«يخصّني
  /// وقيمتُه فارغة»، فلا يبتلع الثاني.
  ///
  /// محرِّرُ القوالب يعرض هذه الأنواعَ الستّةَ عشر تحت قالب `shift_closing`،
  /// وكانت كلُّها تسقط على `default: return ''` — فالعنصرُ بلا تسميةٍ يرجع
  /// `SizedBox()` أي **يختفي**، وبتسميةٍ يطبع تسميةً معلَّقةً بلا رقم.
  static String? resolveShiftValue(String type, ShiftClosingSnapshot s) {
    String n(double v) => v.toStringAsFixed(_docDecimals);

    switch (type) {
      case 'shift_invoice_count':
        return s.invoiceCount.toString();
      case 'shift_total_sales':
        return n(s.totalSales);
      case 'shift_system_cash':
        return n(s.systemCash);
      case 'shift_actual_cash':
        return n(s.actualCash);
      case 'shift_cash_variance':
        return n(s.cashVariance);
      case 'shift_system_card':
        return n(s.systemCard);
      case 'shift_actual_card':
        return n(s.actualCard);
      case 'shift_card_variance':
        return n(s.cardVariance);

      // §٥-٢ (بلاغٌ ميدانيّ 2026-08-11): «كليك» قناةُ دفعٍ كاملةٌ في اللقطة
      // وتدخل في `shift_total_system` و`shift_total_actual` تحت — وكانت
      // غائبةً عن **كلّ** طبقات القالب: لا حالةَ هنا، ولا عنصرَ في لوحة
      // المصمّم، ولا صفَّ في القالب المبذور. فالمطبوعُ يعرض النقدَ والبطاقةَ
      // ويطبع إجمالياً يشملها: المرصود `240,000 + 120,000` بإجمالي
      // `560,000`. والقارئُ يجمع ما يراه فلا يطابق، فيظنّ العطبَ في الحساب.
      case 'shift_system_click':
        return n(s.systemClick);
      case 'shift_actual_click':
        return n(s.actualClick);
      case 'shift_click_variance':
        return n(s.clickVariance);

      case 'shift_total_variance':
        return n(s.totalVariance);
      case 'shift_total_expenses':
        return n(s.totalExpenses);
      case 'shift_cash_refunds':
        return n(s.cashRefunds);

      // ── بنودُ «الحركة» الباقيةُ من الشاشة (بلاغ المالك 2026-08-12) ──
      // شاشةُ `picpos_past_shifts_panel` تقرأ اللقطةَ مباشرةً فتعرض ستّةَ
      // بنود؛ ثلاثةٌ منها لم يكن لها مفتاحٌ هنا فسقطت من الورقة وحدَها.
      // والمشغّلُ يقارن الاثنين — بندٌ على الشاشة وغائبٌ عن المطبوع يُقرأ
      // نقصاً في المطبوع لا نقصاً في القالب.
      case 'shift_opening_balance':
        return n(s.openingBalance);
      case 'shift_cash_income':
        return n(s.cashIncome);

      // ⚠️ الآجلُ **للتوضيح لا للتسوية**: مبيعاتٌ لم تُقبَض، فلا خزنةَ
      // تحمله. ضمُّه إلى `shift_total_system` كان يخلق عجزاً وهمياً بقيمته
      // في كلّ ورديةٍ فيها بيعٌ آجل. يُعرض ويبقى خارج المجاميع.
      case 'shift_credit_sales':
        return n(s.creditSales);
      case 'shift_credit_count':
        return s.creditSalesCount.toString();

      // مجاميعُ مشتقّة — لا حقلَ لها في اللقطة. تُجمع من الثلاثة (نقد ·
      // بطاقة · كليك) لا من `totalSales`: الأخيرُ مبيعاتٌ والأولُ متحصَّل،
      // ويفترقان بالآجل والمصروفات.
      case 'shift_total_system':
        return n(s.systemCash + s.systemCard + s.systemClick);
      case 'shift_total_actual':
        return n(s.actualCash + s.actualCard + s.actualClick);

      case 'shift_status':
        // أهمُّ سطرٍ في التقرير — الفرقُ ينطق بكلمته لا برقمه وحدَه.
        if (s.totalVariance.abs() < 0.001) return 'مطابق';
        return s.totalVariance < 0
            ? 'عجز: ${n(s.totalVariance)}'
            : 'زيادة: +${n(s.totalVariance)}';

      case 'shift_number':
        // لا رقمَ ورديةٍ في اللقطة — الموظّفُ والوقتُ هما ما يميّزها للقارئ.
        final who = s.employeeName?.trim();
        final when = s.closedAt;
        if (who != null && who.isNotEmpty && when != null) {
          return '$who — ${when.day}/${when.month}/${when.year}';
        }
        return who?.isNotEmpty == true ? who! : '—';

      case 'shift_closing':
        return 'تقرير إغلاق الوردية';

      default:
        return null;
    }
  }

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
  static Future<Uint8List> printWithTemplate({
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

    // Derive lookup type from category: kitchen templates have type='kitchen'
    final InvoiceTemplateWithData? templateData;
    if (category == 'kitchen') {
      // Kitchen templates have type='kitchen'
      templateData = await db.getDefaultTemplateWithData('kitchen');
    } else {
      templateData = await db.getDefaultTemplateWithDataByCategory(
        type,
        category,
      );
    }

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

    final elements = orderElementsForPrint(templateData.elements);

    debugPrint(
      '[TemplatedInvoice] Template: "${templateData.template.name}", elements: ${elements.length}, items: ${items.length}',
    );

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
    String resolveType(InvoiceTemplateElement element) => _resolveType(element);

    pw.Widget buildFlowWidget(InvoiceTemplateElement element) {
      final resolvedType = resolveType(element);

      // Special handling for logo — scale to actual paper width
      if (resolvedType == 'logo') {
        // Cap at 60% for thermal to prevent oversized logos
        final maxPercent = paperWidthMm <= 80 ? 0.60 : 1.0;
        final sizePercent = (element.width / 100.0).clamp(0.15, maxPercent);
        final logoW = canvasWidth * sizePercent;
        final logoH = logoW * 0.65;
        if (logoBytes != null && logoBytes.isNotEmpty) {
          final image = pw.MemoryImage(logoBytes);
          return pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 4),
            child: pw.Center(
              child: pw.Image(
                image,
                width: logoW,
                height: logoH,
                fit: pw.BoxFit.contain,
              ),
            ),
          );
        }
        return pw.Center(
          child: pw.Container(
            width: logoW, height: logoH,
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey300),
            ),
            child: pw.Center(child: pw.Text('LOGO', style: _getStyle(element))),
          ),
        );
      }

      return _buildElementContent(
        resolvedType: resolvedType,
        element: element,
        shift: shift,
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
        contentWidgets.add(_buildItemsTable(
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
    _addDocumentPages(
      pdf,
      content: contentWidgets,
      canvasWidth: canvasWidth,
      canvasHeightPts: _pageHeightPoints(templateData.template),
      marginPts: marginMm * mmToPoints,
      direction:
          locale == 'en' ? pw.TextDirection.ltr : pw.TextDirection.rtl,
    );

    // البايتاتُ تُحسب مرّةً واحدةً ثم تُقدَّم لكلِّ مسارٍ — بدلَ استدعاء
    // `pdf.save()` داخلَ كلِّ `onLayout`. نفسُ المخرَج، ونداءٌ واحد.
    final bytes = await pdf.save();
    if (debugBuildOnly) return bytes;

    if (directPrint) {
      // Resolve configured printer based on category
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
      } else {
        debugPrint(
          '[TemplatedInvoice] No configured $category printer, showing print dialog',
        );
        await Printing.layoutPdf(onLayout: (_) => bytes);
      }
    } else {
      await Printing.layoutPdf(onLayout: (_) => bytes);
    }
    return bytes;
  }

  /// بناء محتوى عنصر واحد من القالب (resolvedType تم حله بالفعل في الـ caller)
  ///
  /// [shift] — لقطةُ إقفال الوردية حين يكون المطبوعُ تقريرَ وردية. تُقرأ
  /// **قبل** جدول الفاتورة كي تُحلَّ أنواعُ `shift_*` التي يعرضها المحرر.
  static pw.Widget _buildElementContent({
    required String resolvedType,
    required InvoiceTemplateElement element,
    ShiftClosingSnapshot? shift,
    required String invoiceNumber,
    required DateTime date,
    String? customerName,
    String? customerPhone,
    String? customerAddress,
    required List<Map<String, dynamic>> items,
    required double subtotal,
    required double discount,
    required double tax,
    required double deliveryFee,
    required double total,
    required double paid,
    required double remaining,
    required String companyName,
    required String companyAddress,
    required String companyPhone,
    String? companyTaxId,
    String paymentMethod = 'نقدي',
    InvoiceTableSetting? tableSettings,
    Uint8List? logoBytes,
    String? cashierName,
    String? notes,
    String? adhocCustomerName,
    String? adhocCustomerPhone,
    String? salesType,
    String? orderNumber,
    String? platformOrderNumber,
    double? cashAmount,
    double? bankAmount,
  }) {
    final style = _getStyle(element);
    final align = _getAlignment(element.textAlign);

    // عناصرُ الورديّة أولاً: أنواعُها لا تتقاطع مع أنواع الفاتورة، والمُحلِّل
    // يرجّع `null` لأيّ نوعٍ ليس منها — فلا يخطف شيئاً.
    if (shift != null) {
      final shiftValue = resolveShiftValue(resolvedType, shift);
      if (shiftValue != null) {
        final label = element.labelAr?.trim();
        return pw.Text(
          label == null || label.isEmpty ? shiftValue : '$label: $shiftValue',
          style: style,
          textAlign: align,
        );
      }
    }

    switch (resolvedType) {
      // Company Info
      case 'company_name':
        return pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 2),
          child: pw.Text(companyName, style: style, textAlign: align),
        );
      case 'company_address':
        return pw.Text(companyAddress, style: style, textAlign: align);
      case 'company_phone':
        return pw.Text('هاتف: $companyPhone', style: style, textAlign: align);
      case 'company_tax_id':
        return companyTaxId != null
            ? pw.Text(
                'السجل الضريبي: $companyTaxId',
                style: style,
                textAlign: align,
              )
            : pw.SizedBox();
      case 'logo':
        if (logoBytes != null && logoBytes.isNotEmpty) {
          final image = pw.MemoryImage(logoBytes);
          return pw.Center(
            child: pw.Image(
              image,
              width: element.width,
              height: element.height,
              fit: pw.BoxFit.contain,
            ),
          );
        }
        return pw.Center(
          child: pw.Container(
            width: element.width,
            height: element.height,
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey300),
            ),
            child: pw.Center(child: pw.Text('LOGO', style: style)),
          ),
        );

      // Invoice Info
      case 'invoice_title':
        return pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 4),
          child: pw.Text(
            element.content ?? 'فاتورة مبيعات',
            style: style,
            textAlign: align,
          ),
        );
      case 'invoice_number':
        return pw.Text(
          '${element.labelAr ?? 'رقم الفاتورة'}: $invoiceNumber',
          style: style,
          textAlign: align,
        );
      case 'date':
        return pw.Text(
          '${element.labelAr ?? 'التاريخ'}: ${date.day}/${date.month}/${date.year}',
          style: style,
          textAlign: align,
        );
      case 'time':
        return pw.Text(
          '${element.labelAr ?? 'الوقت'}: ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}',
          style: style,
          textAlign: align,
        );
      case 'cashier_name':
        return pw.Text(
          '${element.labelAr ?? 'الكاشير'}: ${cashierName ?? ''}',
          style: style,
          textAlign: align,
        );
      case 'order_number':
        final orderLabel = element.labelAr?.trim().isNotEmpty == true ? element.labelAr! : 'رقم الطلب';
        return pw.Text(
          '$orderLabel: ${platformOrderNumber ?? orderNumber ?? invoiceNumber}',
          style: style,
          textAlign: align,
        );
      case 'table_number':
        final tableValue = platformOrderNumber ?? adhocCustomerName ?? customerName ?? '';
        if (tableValue.isEmpty) return pw.SizedBox();
        final tableLabel = element.labelAr?.trim().isNotEmpty == true ? element.labelAr! : 'رقم الطاولة';
        return pw.Text(
          '$tableLabel: $tableValue',
          style: style,
          textAlign: align,
        );
      case 'payment_method':
        return pw.Text(
          '${element.labelAr ?? 'طريقة الدفع'}: '
          '${mapPaymentMethodLabel(paymentMethod)}',
          style: style,
          textAlign: align,
        );

      // Customer Info
      case 'customer':
        return customerName != null
            ? pw.Text(
                '${element.labelAr ?? 'العميل'}: $customerName',
                style: style,
                textAlign: align,
              )
            : pw.SizedBox();
      case 'customer_phone':
        return customerPhone != null
            ? pw.Text(
                '${element.labelAr ?? 'الهاتف'}: $customerPhone',
                style: style,
                textAlign: align,
              )
            : pw.SizedBox();
      case 'customer_address':
        return customerAddress != null
            ? pw.Text(
                '${element.labelAr ?? 'العنوان'}: $customerAddress',
                style: style,
                textAlign: align,
              )
            : pw.SizedBox();
      case 'adhoc_customer_name':
        return adhocCustomerName != null && adhocCustomerName.isNotEmpty
            ? pw.Text(
                '${element.labelAr ?? 'اسم العميل'}: $adhocCustomerName',
                style: style,
                textAlign: align,
              )
            : pw.SizedBox();
      case 'adhoc_customer_phone':
        return adhocCustomerPhone != null && adhocCustomerPhone.isNotEmpty
            ? pw.Text(
                '${element.labelAr ?? 'هاتف العميل'}: $adhocCustomerPhone',
                style: style,
                textAlign: align,
              )
            : pw.SizedBox();

      // Items Table
      case 'items_table':
        return _buildItemsTable(items, tableSettings, style);

      // Totals
      case 'subtotal':
        return _totalRow(
          element.labelAr ?? 'المجموع الفرعي',
          subtotal,
          style,
          align,
        );
      case 'discount':
        return discount > 0
            ? _totalRow(
                element.labelAr ?? 'الخصم',
                discount,
                style,
                align,
                isSubtraction: true,
              )
            : pw.SizedBox();
      case 'tax':
        return tax > 0
            ? _totalRow(element.labelAr ?? 'الضريبة', tax, style, align)
            : pw.SizedBox();
      case 'total':
        return _totalRow(
          element.labelAr ?? 'الإجمالي',
          total,
          style.copyWith(fontWeight: pw.FontWeight.bold),
          align,
        );
      case 'paid':
        return _totalRow(element.labelAr ?? 'المدفوع', paid, style, align);
      case 'remaining':
        return _totalRow(
          element.labelAr ?? 'المتبقي',
          remaining,
          style.copyWith(color: remaining > 0 ? PdfColors.red : null),
          align,
        );
      case 'delivery_fee':
        return deliveryFee > 0
            ? _totalRow(element.labelAr ?? 'رسوم التوصيل', deliveryFee, style, align)
            : pw.SizedBox();

      // Info-only fields (label: value)
      case 'sale_type':
      case 'invoice_type_label':
        final saleLabel = salesType != null && salesType.isNotEmpty
            ? _mapSaleTypeLabel(salesType)
            : paymentMethod;
        // ⚠️ كانت تُرجع القيمةَ عاريةً وتتجاهل `labelAr` — فيُطبع «مبيعات»
        // بلا عنوانٍ بجوار «طريقة الدفع: نقدي» المُسمّاة، فيقرؤها المشغّلُ
        // كلمةً شاردة. جاراتُها كلُّها تسبق القيمةَ بتسميتها (‏`supplier_name`
        // تحتها مباشرةً مثالاً). رُصد على ورق 2026-08-12.
        final saleTypeLabel = element.labelAr ?? _getLabel(resolvedType);
        return pw.Text(
          saleTypeLabel.isEmpty
              ? (saleLabel ?? '')
              : '$saleTypeLabel: ${saleLabel ?? ''}',
          style: style,
          textAlign: align,
        );
      case 'supplier_name':
        return pw.Text(
          '${element.labelAr ?? 'المورد'}: ${customerName ?? ''}',
          style: style,
          textAlign: align,
        );
      // Visual Elements
      case 'divider':
        return pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 4),
          child: pw.Divider(thickness: 0.5),
        );
      case 'spacer':
        return pw.SizedBox(height: 8);
      case 'qr_code':
        return pw.Center(
          child: pw.BarcodeWidget(
            barcode: pw.Barcode.qrCode(),
            data: invoiceNumber,
            width: 50,
            height: 50,
          ),
        );
      case 'barcode':
        return pw.Center(
          child: pw.BarcodeWidget(
            barcode: pw.Barcode.code128(),
            data: invoiceNumber,
            width: 60,
            height: 25,
          ),
        );

      // Custom text / notes / footer
      case 'text':
      case 'custom_text':
        return element.content != null
            ? pw.Text(element.content!, style: style, textAlign: align)
            : pw.SizedBox();
      case 'notes':
        final noteText = notes ?? element.content;
        return noteText != null && noteText.isNotEmpty
            ? pw.Text(noteText, style: style, textAlign: align)
            : pw.SizedBox();

      // إضافاتُ الأصناف وخياراتُها — مجموعةً على مستوى الفاتورة، وهو ما
      // تعاينه شاشةُ المصمّم («الإضافات: كاتشب، مايونيز»). كانا يسقطان على
      // `default` فيرجعان `SizedBox()` أي يختفيان بلا أثر.
      case 'item_additions':
        final additions = extractItemAdditions(items);
        if (additions.isEmpty) return pw.SizedBox();
        final addLabel = element.labelAr?.trim();
        return pw.Text(
          addLabel == null || addLabel.isEmpty
              ? 'الإضافات: $additions'
              : '$addLabel: $additions',
          style: style,
          textAlign: align,
        );
      case 'item_options':
        final options = extractItemOptions(items);
        if (options.isEmpty) return pw.SizedBox();
        final optLabel = element.labelAr?.trim();
        return pw.Text(
          optLabel == null || optLabel.isEmpty
              ? 'الخيارات: $options'
              : '$optLabel: $options',
          style: style,
          textAlign: align,
        );
      case 'footer':
        return pw.Padding(
          padding: const pw.EdgeInsets.only(top: 8),
          child: pw.Text(
            element.content ?? 'شكراً لتعاملكم معنا',
            style: style, textAlign: align,
          ),
        );

      // ══════════════════════════════════════════════════════════════════
      // SMART DEFAULT — mirrors the preview dialog's fallback behavior.
      // Any element type not explicitly cased above is rendered using
      // its label (from labelAr or _getLabel) + real data value.
      // Totals-like fields render as label ↔ value rows (right-aligned).
      // ══════════════════════════════════════════════════════════════════
      default:
        // نصٌّ ثابتٌ يُرسم كما هو.
        //
        // ⚠️ `_resolveType` يستبدل نوعَ عنصر النصّ **بمحتواه** كي يصلح
        // مفتاحاً للترتيب وإزالة التكرار. فحالةُ `case 'text'` أعلاه لا
        // تُبلَغ أبداً لأيّ نصٍّ له محتوى — يسقط هنا، ولا قيمةَ بيانٍ له،
        // فيختفي بلا أثر. رُصد على ورقٍ حقيقيّ 2026-08-12: عناوينُ قنوات
        // تقرير الوردية **وسطرا التوقيع** غائبةٌ عن كلّ مطبوعٍ بقالب.
        //
        // الشرطُ يفحص النوعَ الخام لا المُحلَّل، ويأتي **داخل** `default`
        // لا قبل الـswitch: عنصرُ نصٍّ محتواه مفتاحُ بياناتٍ معروفٌ يبقى
        // على سلوكه القديم فيُحَلّ قيمةً.
        if ((element.elementType == 'text' ||
                element.elementType == 'custom_text') &&
            (element.content?.isNotEmpty ?? false)) {
          return pw.Text(element.content!, style: style, textAlign: align);
        }

        final label = element.labelAr ?? _getLabel(resolvedType);
        final value = _getDataValue(
          resolvedType,
          invoiceNumber: invoiceNumber,
          date: date,
          customerName: customerName,
          customerPhone: customerPhone,
          customerAddress: customerAddress,
          companyName: companyName,
          companyAddress: companyAddress,
          companyPhone: companyPhone,
          companyTaxId: companyTaxId,
          paymentMethod: paymentMethod,
          cashierName: cashierName,
          notes: notes,
          adhocCustomerName: adhocCustomerName,
          adhocCustomerPhone: adhocCustomerPhone,
          subtotal: subtotal,
          discount: discount,
          tax: tax,
          deliveryFee: deliveryFee,
          total: total,
          paid: paid,
          remaining: remaining,
          orderNumber: orderNumber,
          platformOrderNumber: platformOrderNumber,
          cashAmount: cashAmount,
          bankAmount: bankAmount,
        );

        // §٥-٣ (بلاغٌ ميدانيّ 2026-08-11): كان الشرطُ `&&`، فتسميةٌ **معروفةٌ**
        // بقيمةٍ فارغةٍ تُطبع معلَّقةً بلا رقم: «الكاشير:» و«المخزن:» في
        // الإيصال المرصود. والحقولُ التي ترجع `''` مقصودةٌ ومعلومة — انظر
        // `_getDataValue`: «Fields where data is not yet passed through to the
        // print service» (‏`warehouse_name` · `branch_name` · `cash_amount` ·
        // `bank_amount` · `click_amount` …).
        //
        // فالقاعدة: **عنصرٌ بلا قيمةٍ لا يقول شيئاً فلا يُطبع.** تسميةٌ وحدَها
        // أسوأُ من لا شيء: القارئُ يظنّ البيانَ ناقصاً لا الحقلَ غيرَ مفعَّل.
        if (value.isEmpty) {
          if (label.isEmpty) {
            debugPrint('[TemplatedInvoice] ⚠ Unknown: "$resolvedType"');
          }
          return pw.SizedBox();
        }

        // Totals-like fields → right-aligned label ↔ value row
        if (_isTotalField(resolvedType)) {
          final num? numVal = double.tryParse(value);
          if (numVal != null) {
            final isMainTotal = resolvedType == 'total' || resolvedType == 'total_amount';
            return _totalRow(
              label,
              numVal.toDouble(),
              isMainTotal ? style.copyWith(fontWeight: pw.FontWeight.bold) : style,
              align,
            );
          }
        }

        // Regular field → label: value
        if (label.isNotEmpty && value.isNotEmpty) {
          return pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 1),
            child: pw.Text('$label: $value', style: style, textAlign: align),
          );
        }

        // Label-only or value-only
        return pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 1),
          child: pw.Text(
            label.isNotEmpty ? label : value,
            style: style, textAlign: align,
          ),
        );
    }
  }

  /// Labels for all known element types — mirrors preview dialog's _getLabel
  static String _getLabel(String type) {
    const labels = {
      'invoice_number': 'رقم الفاتورة',
      'order_number': 'رقم الطلب',
      'date': 'التاريخ',
      'time': 'الوقت',
      'customer_name': 'اسم العميل',
      'customer': 'العميل',
      'customer_phone': 'الهاتف',
      'customer_address': 'العنوان',
      'cashier_name': 'الكاشير',
      'payment_method': 'طريقة الدفع',
      'sale_type': 'نوع البيع',
      'invoice_type_label': 'نوع الفاتورة',
      'warehouse_name': 'المخزن',
      'branch_name': 'الفرع',
      'company_name': 'اسم الشركة',
      'company_address': 'عنوان الشركة',
      'company_phone': 'هاتف الشركة',
      'company_tax_number': 'الرقم الضريبي',
      'company_tax_id': 'الرقم الضريبي',
      'tax_registration': 'السجل الضريبي',
      'adhoc_customer_name': 'اسم العميل',
      'adhoc_customer_phone': 'هاتف العميل',
      'supplier_name': 'المورد',
      'subtotal': 'الإجمالي الفرعي',
      'discount': 'الخصم',
      'tax': 'الضريبة',
      'tax_amount': 'الضريبة',
      'total': 'الإجمالي النهائي',
      'total_amount': 'الإجمالي النهائي',
      'grand_total': 'الإجمالي النهائي',
      'paid': 'المدفوع',
      'paid_amount': 'المدفوع',
      'remaining': 'المتبقي',
      'change': 'الباقي',
      'cash_amount': 'مدفوع نقداً',
      'bank_amount': 'مدفوع بنكياً',
      'click_amount': 'مدفوع كليك',
      'notes': 'ملاحظات',
      'kitchen_notes': 'ملاحظات المطبخ',
      'delivery_fee': 'رسوم التوصيل',
      'delivery_type': 'نوع التوصيل',
      'delivery_address': 'عنوان التوصيل',
      'courier_name': 'المندوب',
      'table_number': 'رقم الطاولة',
      'waiter_name': 'الويتر',
      'footer_text': 'التذييل',
    };
    return labels[type] ?? '';
  }

  /// Whether a field should be rendered as a total row (label ↔ value)
  static bool _isTotalField(String type) {
    return const {
      'subtotal', 'discount', 'tax', 'tax_amount', 'total',
      'total_amount', 'grand_total', 'paid', 'paid_amount',
      'remaining', 'change', 'cash_amount', 'bank_amount',
      'click_amount', 'delivery_fee',
    }.contains(type);
  }

  /// Resolve element type from DB element — handles variable, text, image, line
  static String _resolveType(InvoiceTemplateElement element) {
    String resolvedType = element.elementType;
    if ((resolvedType == 'variable' || resolvedType == 'text') &&
        element.content != null &&
        element.content!.isNotEmpty) {
      resolvedType = element.content!;
    } else if (resolvedType == 'line') {
      resolvedType = 'divider';
    } else if (resolvedType == 'image' && element.content == 'logo') {
      resolvedType = 'logo';
    }
    const nameMapping = {
      'customer_name': 'customer',
      'tax_amount': 'tax',
      'grand_total': 'total',
      'total_amount': 'total',
      'paid_amount': 'paid',
      'change': 'remaining',
      'company_tax_number': 'company_tax_id',
      'footer_text': 'footer',
    };
    return nameMapping[resolvedType] ?? resolvedType;
  }

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
    final seenContent = <String>{};
    final elements = <InvoiceTemplateElement>[];
    for (final el in allVisible) {
      if (el.elementType != 'variable') {
        elements.add(el);
        continue;
      }
      final key = _resolveType(el);
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

  /// عددُ صفحات مستندٍ بأصنافٍ معلومة — للقياس الآليّ للتقسيم.
  @visibleForTesting
  static Future<int> debugPageCount({
    required List<Map<String, dynamic>> items,
    required double paperWidthMm,
    double? paperHeightMm,
  }) async {
    final pdf = await _buildPaginationProbe(
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
    final pdf = await _buildPaginationProbe(
      items: items,
      paperWidthMm: paperWidthMm,
      paperHeightMm: paperHeightMm,
    );
    return pdf.save();
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
        _buildItemsTable(
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

  /// تسلسلُ ما يُرسم فعلاً: عناصرُ القالب مرشَّحةً، وقد وقع جدولُ الأصناف
  /// موقعَه بينها. العنصرُ `null` في الناتج = جدولُ الأصناف.
  static List<InvoiceTemplateElement?> layoutSequenceForPrint(
    List<InvoiceTemplateElement> ordered, {
    required bool hasItems,
  }) {
    // Filter elements: only process known elementTypes (variable, text, line, image)
    // This skips old-format seeded elements with elementType like 'customer', 'footer'
    final validElements = ordered
        .where((e) => const {'variable', 'text', 'line', 'image', 'rectangle'}
            .contains(e.elementType))
        .toList();

    // موضعُ الجدول من القالب أوّلاً. فإن خلا القالبُ من عنصرِ جدولٍ — وهو
    // حالُ كلّ قالبٍ مبذورٍ قبل 2026-08-12 — بقي الاستدلالُ القديم احتياطاً
    // كي لا ينقلب مطبوعٌ قائم.
    final hasExplicitTable =
        validElements.any((e) => _resolveType(e) == 'items_table');

    final seq = <InvoiceTemplateElement?>[];
    bool tableInserted = false;
    for (final el in validElements) {
      final resolved = _resolveType(el);
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

  /// كودُ طريقة الدفع → تسميتُه العربية.
  ///
  /// §٥-٣ (بلاغٌ ميدانيّ 2026-08-11): الإيصالُ طبع «طريقة الدفع: cash». كان
  /// `payment_method` يُطبع **خاماً** كما يصل من المنادي، ولا مُحوِّلَ له —
  /// بينما `_mapSaleTypeLabel` المجاور يحوّل نوعَ البيع منذ البداية. فالكودُ
  /// الإنجليزيُّ يظهر للعميل في إيصالٍ عربيٍّ بالكامل.
  ///
  /// وما لا يُعرف يُعاد كما هو لا يُبتلع: تسميةٌ عربيةٌ وصلت جاهزةً من منادٍ
  /// آخر تمرّ، وكودٌ جديدٌ يظهر فيُرى بدل أن يختفي صامتاً.
  static String mapPaymentMethodLabel(String method) {
    switch (method.trim().toLowerCase()) {
      case 'cash':
        return 'نقدي';
      case 'card':
      case 'visa':
      case 'mastercard':
        return 'بطاقة';
      case 'bank':
      case 'transfer':
        return 'تحويل بنكي';
      case 'click':
        return 'كليك';
      case 'credit':
      case 'deferred':
        return 'آجل';
      case 'wallet':
        return 'محفظة';
      case 'mixed':
      case 'multi':
        return 'مختلط';
      default:
        return method;
    }
  }

  /// Map sale type codes to human-readable Arabic labels (with platform hashtags)
  static String _mapSaleTypeLabel(String saleType) {
    switch (saleType.toLowerCase()) {
      case 'delivery':
        return 'توصيل';
      case 'internal':
      case 'default':
        return 'محلي';
      case 'dine_in':
      case 'صالة':
        return 'صالة';
      case 'takeaway':
      case 'سفري':
        return 'سفري';
      case 'talabat':
      case 'طلبات':
        return '#طلبات';
      case 'careem':
      case 'كريم':
        return '#كريم';
      case 'marsool':
      case 'مرسول':
        return '#مرسول';
      case 'jahez':
      case 'جاهز':
        return '#جاهز';
      case 'hungerstation':
        return '#هنقرستيشن';
      case 'toyo':
      case 'toyou':
        return '#ToYou';
      default:
        return saleType;
    }
  }

  /// Get the actual data value for an element type from the print parameters
  static String _getDataValue(
    String type, {
    required String invoiceNumber,
    required DateTime date,
    String? customerName,
    String? customerPhone,
    String? customerAddress,
    required String companyName,
    required String companyAddress,
    required String companyPhone,
    String? companyTaxId,
    required String paymentMethod,
    String? cashierName,
    String? notes,
    String? adhocCustomerName,
    String? adhocCustomerPhone,
    required double subtotal,
    required double discount,
    required double tax,
    required double deliveryFee,
    required double total,
    required double paid,
    required double remaining,
    String? orderNumber,
    String? platformOrderNumber,
    double? cashAmount,
    double? bankAmount,
  }) {
    switch (type) {
      case 'invoice_number': return invoiceNumber;
      case 'order_number': return platformOrderNumber ?? orderNumber ?? invoiceNumber;
      case 'date': return '${date.day}/${date.month}/${date.year}';
      case 'time': return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
      case 'customer_name': case 'customer': return customerName ?? '';
      case 'customer_phone': return customerPhone ?? '';
      case 'customer_address': return customerAddress ?? '';
      case 'adhoc_customer_name': return adhocCustomerName ?? '';
      case 'adhoc_customer_phone': return adhocCustomerPhone ?? '';
      case 'company_name': return companyName;
      case 'company_address': return companyAddress;
      case 'company_phone': return companyPhone;
      case 'company_tax_id': case 'company_tax_number': case 'tax_registration': return companyTaxId ?? '';
      case 'payment_method': return mapPaymentMethodLabel(paymentMethod);
      case 'sale_type': case 'invoice_type_label': return paymentMethod;
      case 'cashier_name': return cashierName ?? '';
      case 'supplier_name': return customerName ?? '';
      case 'notes': case 'kitchen_notes': return notes ?? '';
      case 'subtotal': return subtotal.toStringAsFixed(_docDecimals);
      case 'discount': return discount.toStringAsFixed(_docDecimals);
      case 'tax': case 'tax_amount': return tax.toStringAsFixed(_docDecimals);
      case 'delivery_fee': return deliveryFee.toStringAsFixed(_docDecimals);
      case 'total': case 'total_amount': case 'grand_total': return total.toStringAsFixed(_docDecimals);
      case 'paid': case 'paid_amount': return paid.toStringAsFixed(_docDecimals);
      case 'remaining': case 'change': return remaining.toStringAsFixed(_docDecimals);
      // Fields where data is not yet passed through to the print service
      case 'table_number':
        return platformOrderNumber ?? adhocCustomerName ?? customerName ?? '';
      case 'warehouse_name': case 'branch_name': case 'delivery_type':
      case 'delivery_address': case 'courier_name': case 'waiter_name':
      // استردادُ مرتجع المبيعات — نقداً وبنكياً. كانا يُرجعان `''` دائماً.
      case 'cash_amount':
        return cashAmount == null ? '' : cashAmount.toStringAsFixed(_docDecimals);
      case 'bank_amount':
        return bankAmount == null ? '' : bankAmount.toStringAsFixed(_docDecimals);
      case 'click_amount':
        return '';
      default: return '';
    }
  }

  static pw.Widget _buildItemsTable(
    List<Map<String, dynamic>> items,
    InvoiceTableSetting? settings,
    pw.TextStyle baseStyle,
  ) {
    final showIndex = settings?.showIndex ?? false;
    final showName = settings?.showProductName ?? true;
    final showCode = settings?.showProductCode ?? false;
    final showQty = settings?.showQuantity ?? true;
    final showPrice = settings?.showUnitPrice ?? true;
    final showDiscount = settings?.showDiscount ?? false;
    final showTax = settings?.showTax ?? false;
    final showTotalCol = settings?.showTotal ?? true;

    // Parse custom flex ratios and _decimalPlaces from JSON
    final defaultWidths = <String, double>{
      'index': 0.8,
      'product': 3.0,
      'code': 1.5,
      'quantity': 1.0,
      'price': 1.2,
      'discount': 1.0,
      'tax': 1.0,
      'total': 1.5,
    };
    // §٥-٣ — الدقّةُ محسومةٌ للمستند كلِّه في `_docDecimals` (انظر تعليقَه
    // فوق). كانت تُحسم هنا وحدَها فتفترق عن الإجماليات في نفس الورقة.
    int decimalPlaces = _docDecimals;
    bool headerBold = true;  // Default: header is bold
    bool bodyBold = false;   // Default: body is normal
    bool showHeader = true;  // Default: show header row
    // ⚠️ كان `try` واحدٌ يلفّ فكَّ المفاتيح كلَّها مع `value as bool?` —
    // فقيمةٌ مخزَّنةٌ `1` بدل `true` ترمي، فتُبتلع الرميةُ وتضيع معها
    // **عروضُ الأعمدة والدقّةُ وكلُّ الأعلام** دفعةً واحدة: تصميمٌ مسطَّحٌ
    // بلا رسالةِ خطأٍ واحدة. `parseTableFlags` تعزل كلَّ مفتاحٍ وتتسامح مع
    // الأرقام والنصوص. اقرأ `core/utils/template_json_flags.dart`.
    final flags = parseTableFlags(settings?.columnWidths);
    defaultWidths.addAll(flags.columnWidths);
    decimalPlaces = flags.decimalPlaces ?? decimalPlaces;
    headerBold = flags.headerBold ?? headerBold;
    bodyBold = flags.bodyBold ?? bodyBold;
    showHeader = flags.showHeader ?? showHeader;

    // Number formatter helper
    String fmt(num val) => val.toStringAsFixed(decimalPlaces);

    // Build column widths using Flex ratios — proportional to content importance.
    // Product name gets the most space. Numbers get less.
    // Columns are ordered RTL (reversed) in the cell builders below,
    // so column indices map naturally: 0 = rightmost (last visual column).
    int colIdx = 0;
    final Map<int, pw.TableColumnWidth> colWidths = {};
    // Order: Total | Tax | Discount | Price | Qty | Code | Name | Index
    // (cells already reversed for RTL in the builders below)
    if (showTotalCol) colWidths[colIdx++] = pw.FlexColumnWidth(defaultWidths['total']!);
    if (showTax) colWidths[colIdx++] = pw.FlexColumnWidth(defaultWidths['tax']!);
    if (showDiscount) colWidths[colIdx++] = pw.FlexColumnWidth(defaultWidths['discount']!);
    if (showPrice) colWidths[colIdx++] = pw.FlexColumnWidth(defaultWidths['price']!);
    if (showQty) colWidths[colIdx++] = pw.FlexColumnWidth(defaultWidths['quantity']!);
    if (showCode) colWidths[colIdx++] = pw.FlexColumnWidth(defaultWidths['code']!);
    if (showName) colWidths[colIdx++] = pw.FlexColumnWidth(defaultWidths['product']!);
    if (showIndex) colWidths[colIdx++] = pw.FlexColumnWidth(defaultWidths['index']!);

    // final totalCols = colIdx;

    // Count enabled columns — auto-reduce header font for cramped layouts
    int enabledCols = 0;
    if (showIndex) enabledCols++;
    if (showName) enabledCols++;
    if (showCode) enabledCols++;
    if (showQty) enabledCols++;
    if (showPrice) enabledCols++;
    if (showDiscount) enabledCols++;
    if (showTax) enabledCols++;
    if (showTotalCol) enabledCols++;

    // Use font sizes from settings — clamp to reasonable range for thermal paper
    // Auto-reduce header font when many columns are enabled
    // ⚠️ الحدُّ الأدنى كان `1.0` — أي أن مقاساً فاسداً يُقبل كما هو فيصير
    // صفُّ العناوين موجوداً في الوثيقة وغيرَ مرئيٍّ على الورق. قِيس في
    // قاعدة المالك 2026-08-12: `header_font_size = 1.0` والمحرّرُ يعرض 9.
    final headerFontSize =
        resolveHeaderFontSize(settings?.headerFontSize, enabledColumns: enabledCols);
    final bodyFontSize = (settings?.fontSize ?? 8.0).clamp(1.0, 24.0);
    // ── صفُّ العناوين: حبرٌ لا تعبئة ──────────────────────────────────────
    //
    // البلاغ الميدانيّ (2026-08-11): «صفُّ عناوين أعمدة الجدول لا يظهر في
    // الطباعة». ورسمُ المستند بـ`Windows.Data.Pdf` أثبت أن **الصفَّ موجودٌ
    // في الوثيقة وواضح** — فنفى كلَّ فرضيات الكود (‏`_showHeader` معطَّل ·
    // `headerFontSize` مقصورٌ إلى ١pt · القالبُ بلا صفّ). بقي تفسيرٌ واحد:
    // النصُّ كان **أبيضَ** يتّكئ على تعبئةٍ سوداء، والطابعةُ الحرارية تُسقط
    // تعبئةَ الخلفية ⇒ أبيضُ على ورقٍ أبيض.
    //
    // فالعناوينُ الآن سوداءُ عريضة، والفصلُ من حدود الجدول القائمة لا من
    // مساحةٍ ملوّنة. يُطبع على كلّ جهازٍ سواءٌ رسم التعبئةَ أم أسقطها —
    // **لا يُعتمد على ما قد لا يصل إلى الورق.**
    final headerStyle = baseStyle.copyWith(
      font: _arabicBoldFont ?? baseStyle.font,
      fontWeight: pw.FontWeight.bold,
      fontSize: headerFontSize,
      color: PdfColors.black,
    );
    final bodyStyle = baseStyle.copyWith(
      fontWeight: bodyBold ? pw.FontWeight.bold : pw.FontWeight.normal,
      fontSize: bodyFontSize,
    );

    return pw.Table(
      border: pw.TableBorder.all(width: 0.5, color: PdfColors.grey400),
      columnWidths: colWidths,
      children: [
        // Header (cells in RTL order — rightmost visual column first)
        if (showHeader)
        pw.TableRow(
          // `repeat: true` — الجدولُ ينقسم على صفحات A4، وبلا التكرار تخرج
          // الصفحةُ الثانيةُ أرقاماً بلا رؤوسٍ لا يُعرف أيُّها الكمّيةُ وأيُّها
          // السعر. ولا أثرَ له على الحراريّ: لفّةٌ لا تنقسم أصلاً.
          repeat: true,
          // بلا تعبئة — انظر `headerStyle` فوق. و`headerBold` صار لا يُقرأ
          // هنا قصداً: العناوينُ عريضةٌ دائماً لأن العَرْضَ هو ما يفصلها عن
          // البدن بعد زوال المساحة الملوّنة.
          children: [
            if (showTotalCol)
              _tableCell(
                '\u0627\u0644\u0625\u062c\u0645\u0627\u0644\u064a',
                headerStyle,
              ),
            if (showTax)
              _tableCell(
                '\u0627\u0644\u0636\u0631\u064a\u0628\u0629',
                headerStyle,
              ),
            if (showDiscount)
              _tableCell('\u0627\u0644\u062e\u0635\u0645', headerStyle),
            if (showPrice)
              _tableCell('\u0627\u0644\u0633\u0639\u0631', headerStyle),
            if (showQty)
              _tableCell('العدد', headerStyle),
            if (showCode)
              _tableCell('\u0627\u0644\u0643\u0648\u062f', headerStyle),
            if (showName)
              _tableCell('\u0627\u0644\u0635\u0646\u0641', headerStyle),
            if (showIndex) _tableCell('\u0645', headerStyle),
          ],
        ),
        ...items.asMap().entries.expand((entry) {
          final idx = entry.key + 1;
          final item = entry.value;
          final itemNote = item['note']?.toString() ?? '';
          
          final formattedNote = itemNote.replaceAll(' | ', '\n').replaceAll('📝 ', '\nملاحظة: ').trim();

          pw.Widget productNameWidget() {
            return pw.Padding(
              padding: const pw.EdgeInsets.all(4),
              child: formattedNote.isNotEmpty
                ? pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                    children: [
                      pw.Text(
                        item['name']?.toString() ?? '',
                        style: bodyStyle,
                        textAlign: pw.TextAlign.right,
                        textDirection: pw.TextDirection.rtl,
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        formattedNote,
                        style: bodyStyle.copyWith(
                          fontSize: (bodyStyle.fontSize ?? 10) >= 8.0 ? (bodyStyle.fontSize ?? 10) - 2.0 : 6.0,
                          fontWeight: pw.FontWeight.normal,
                          color: PdfColors.black,
                          lineSpacing: 0.5,
                        ),
                        textAlign: pw.TextAlign.right,
                        textDirection: pw.TextDirection.rtl,
                      ),
                    ],
                  )
                : pw.Text(
                    item['name']?.toString() ?? '',
                    style: bodyStyle,
                    textAlign: pw.TextAlign.right,
                    textDirection: pw.TextDirection.rtl,
                  ),
            );
          }

          // فاصلُ تصنيفٍ لا صنف: سطرٌ واحدٌ بعرض الجدول، عنوانُه في الوسط —
          // كما يرسمه المسارُ الحراريُّ تماماً (`— الاسم —`). وبلا هذا كان
          // يُطبع صنفاً بكمّية صفرٍ وسعرٍ صفر.
          if (isCategoryHeaderRow(item)) {
            // العنوانُ يقع في **عمود الصنف** — أعرضُ الأعمدة وموضعُ الاسم —
            // وبقيةُ الخلايا فارغة. و`pw.Table` لا يدعم دمجَ الأعمدة، فهذا
            // أقربُ ما يُطابق المسارَ الحراريّ بلا كسر الشبكة.
            // ⚠️ وعددُ الخلايا يجب أن يساوي عددَ الأعمدة تماماً.
            final nameCell = pw.Container(
              padding: const pw.EdgeInsets.symmetric(vertical: 3),
              alignment: pw.Alignment.center,
              child: pw.Text(
                '— ${item['name'] ?? ''} —',
                style: headerStyle,
                textAlign: pw.TextAlign.center,
                textDirection: pw.TextDirection.rtl,
              ),
            );
            return [
              pw.TableRow(
                children: [
                  if (showTotalCol) pw.SizedBox(),
                  if (showTax) pw.SizedBox(),
                  if (showDiscount) pw.SizedBox(),
                  if (showPrice) pw.SizedBox(),
                  if (showQty) pw.SizedBox(),
                  if (showCode) pw.SizedBox(),
                  if (showName) nameCell,
                  if (showIndex) pw.SizedBox(),
                ],
              ),
            ];
          }

          final rows = <pw.TableRow>[
            pw.TableRow(
              children: [
                if (showTotalCol) _tableCell(fmt(item['total'] ?? 0), bodyStyle),
                if (showTax) _tableCell(fmt(item['tax'] ?? 0), bodyStyle),
                if (showDiscount)
                  _tableCell(fmt(item['discount'] ?? 0), bodyStyle),
                if (showPrice) _tableCell(fmt(item['price'] ?? 0), bodyStyle),
                if (showQty) _tableCell(fmt(item['quantity'] ?? 1), bodyStyle),
                if (showCode)
                  _tableCell(item['code']?.toString() ?? '', bodyStyle),
                if (showName) productNameWidget(),
                if (showIndex) _tableCell('$idx', bodyStyle),
              ],
            ),
          ];

          return rows;
        }),
      ],
    );
  }

  /// هل هذا السطرُ فاصلَ تصنيفٍ لا صنفاً؟
  ///
  /// `== true` لا `as bool?`: القيمةُ تعبر حدَّ `Map<String, dynamic>` وقد
  /// تصل نصّاً من JSON، والرميةُ تُسقط المطبوعَ كلَّه بدل أن تقرأ.
  @visibleForTesting
  static bool isCategoryHeaderRow(Map<String, dynamic> item) =>
      item['isCategoryHeader'] == true;

  static pw.Widget _tableCell(String text, pw.TextStyle style) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 1, vertical: 2),
      child: pw.Text(text, style: style, textAlign: pw.TextAlign.center),
    );
  }

  static pw.Widget _totalRow(
    String label,
    double value,
    pw.TextStyle style,
    pw.TextAlign align, {
    bool isSubtraction = false,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Flexible(
            child: pw.Text(label, style: style),
          ),
          pw.SizedBox(width: 4),
          pw.Text(
            '${isSubtraction ? "-" : ""}${value.toStringAsFixed(_docDecimals)}',
            style: style,
          ),
        ],
      ),
    );
  }

  static pw.TextStyle _getStyle(InvoiceTemplateElement element) {
    // Clamp font size for thermal-safe rendering (max 12pt).
    // The designer may allow larger sizes for preview, but 79mm paper
    // can't fit long Arabic labels at 14-18pt without overflow.
    final fontSize = element.fontSize.clamp(1.0, 24.0);
    // ⚠️ `font:` مع `fontWeight: bold` فخّ: الحزمةُ تُركّب الخطَّ الممرَّر في
    // **خانة العريض** (`text_style.dart:150-153`)، فيدهس الدمجُ وجهَ الثيم
    // العريضَ الحقيقيّ ويُرسم كلُّ «عريض» عادياً. الوجهُ يُنتقى صراحةً.
    return pw.TextStyle(
      font: element.isBold ? (_arabicBoldFont ?? _arabicFont) : _arabicFont,
      fontSize: fontSize,
      fontWeight: element.isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
      color: _parseColor(element.fontColor),
    );
  }

  static pw.TextAlign _getAlignment(String? alignment) {
    switch (alignment) {
      case 'left':
        return pw.TextAlign.left;
      case 'center':
        return pw.TextAlign.center;
      case 'right':
      default:
        return pw.TextAlign.right;
    }
  }

  static PdfColor _parseColor(String hexColor) {
    try {
      final hex = hexColor.replaceFirst('#', '');
      return PdfColor.fromInt(int.parse('FF$hex', radix: 16));
    } catch (_) {
      return PdfColors.black;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BARCODE LABEL PRINTING
  // ═══════════════════════════════════════════════════════════════════════════

  /// طباعة ملصقات باركود باستخدام القالب المحفوظ
  /// Prints barcode labels using a saved barcode template design.
  /// Each label is laid out according to the template's paper size,
  /// with multiple labels arranged in a grid on A4 pages.
  static Future<void> printBarcodeWithTemplate({
    required AppDatabase db,
    required String barcodeValue,
    required String productName,
    String? productCode,
    double? price,
    String? companyName,
    int copies = 1,
    bool directPrint = true,
    int? templateId,
  }) async {
    await _initFont();

    // Find template
    InvoiceTemplateWithData? templateData;
    if (templateId != null) {
      final t = await db.getTemplateById(templateId);
      if (t != null) {
        final elements = await db.getTemplateElements(templateId);
        templateData = InvoiceTemplateWithData(template: t, elements: elements);
      }
    }
    templateData ??= await db.getDefaultTemplateWithDataByCategory(
      'thermal',
      'barcode',
    );

    if (templateData == null) {
      debugPrint('[BarcodeTemplate] No barcode template found');
      return;
    }

    final template = templateData.template;
    final elements = templateData.elements;

    // Label dimensions in mm → points
    final labelWidthMM = template.paperWidth;
    final labelHeightMM = template.paperHeight ?? 25.0;
    final labelWidth = labelWidthMM * PdfPageFormat.mm;
    final labelHeight = labelHeightMM * PdfPageFormat.mm;

    // Calculate grid layout on A4
    const pageMargin = 10.0;
    const a4Width = 210.0 * PdfPageFormat.mm;
    const a4Height = 297.0 * PdfPageFormat.mm;
    const usableWidth = a4Width - (2 * pageMargin);
    const usableHeight = a4Height - (2 * pageMargin);

    final labelsPerRow = (usableWidth / (labelWidth + 2)).floor().clamp(1, 20);
    final labelsPerCol = (usableHeight / (labelHeight + 2)).floor().clamp(
      1,
      40,
    );
    final labelsPerPage = labelsPerRow * labelsPerCol;
    final totalPages = (copies / labelsPerPage).ceil();

    final pdf = await BaseGenerator.newDocument();

    for (int page = 0; page < totalPages; page++) {
      final labelsOnThisPage = (page == totalPages - 1)
          ? copies - (page * labelsPerPage)
          : labelsPerPage;

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(pageMargin),
          // بدونه تؤول الصفحةُ إلى LTR فلا تُشكَّل العربيةُ ولا يُعاد
          // ترتيبُها: اسمُ الصنف يخرج بحروفٍ منفصلةٍ ومقلوبِ الترتيب على
          // **كلّ ملصقِ باركود**. مقيسٌ بالرسم: «صبري» ⇒ «يربص».
          textDirection: pw.TextDirection.rtl,
          build: (context) => pw.Wrap(
            spacing: 2,
            runSpacing: 2,
            children: List.generate(
              labelsOnThisPage,
              (_) => _buildSingleBarcodeLabel(
                elements: elements,
                labelWidth: labelWidth,
                labelHeight: labelHeight,
                labelWidthMM: labelWidthMM,
                labelHeightMM: labelHeightMM,
                barcodeValue: barcodeValue,
                productName: productName,
                productCode: productCode,
                price: price,
                companyName: companyName,
              ),
            ),
          ),
        ),
      );
    }

    if (directPrint) {
      final printerName = await PrinterResolver.resolveByPurpose(PrintersRepositoryImpl(db), 'barcode');
      await Printing.directPrintPdf(
        printer: printerName ?? (await Printing.listPrinters()).first,
        onLayout: (format) async => pdf.save(),
        name: 'Barcode_${barcodeValue}_x$copies',
      );
    } else {
      await Printing.layoutPdf(
        onLayout: (format) async => pdf.save(),
        name: 'Barcode_${barcodeValue}_x$copies',
      );
    }
  }

  /// Build a single barcode label from template elements
  static pw.Widget _buildSingleBarcodeLabel({
    required List<InvoiceTemplateElement> elements,
    required double labelWidth,
    required double labelHeight,
    required double labelWidthMM,
    required double labelHeightMM,
    required String barcodeValue,
    required String productName,
    String? productCode,
    double? price,
    String? companyName,
  }) {
    // Scale factor from mm units (template coords) to points
    final scaleX = labelWidth / labelWidthMM;
    final scaleY = labelHeight / labelHeightMM;

    final children = <pw.Widget>[];
    for (final el in elements) {
      final x = el.xPosition * scaleX;
      final y = el.yPosition * scaleY;
      final w = el.width * scaleX;
      final h = el.height * scaleY;

      // نفسُ فخّ `_getStyle`: الوجهُ يُنتقى صراحةً وإلا رُسم العريضُ عادياً.
      final style = pw.TextStyle(
        font: el.isBold ? (_arabicBoldFont ?? _arabicFont) : _arabicFont,
        fontSize: el.fontSize,
        fontWeight: el.isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
        fontStyle: el.isItalic ? pw.FontStyle.italic : pw.FontStyle.normal,
        color: _parseColor(el.fontColor),
      );
      final align = _getAlignment(el.textAlign);

      pw.Widget? contentWidget;
      final type = el.elementType;

      switch (type) {
        case 'product_name':
          final displayName = productName.length > 30
              ? '${productName.substring(0, 30)}...'
              : productName;
          contentWidget = pw.Text(
            displayName,
            style: style,
            textAlign: align,
            maxLines: 2,
          );
          break;
        case 'product_code':
          contentWidget = pw.Text(
            productCode ?? barcodeValue,
            style: style,
            textAlign: align,
          );
          break;
        case 'barcode_image':
          final barcodeType = _resolveBarcodeType(el.content);
          contentWidget = pw.BarcodeWidget(
            data: barcodeValue,
            barcode: barcodeType,
            width: w,
            height: h * 0.8,
            drawText: true,
            textStyle: pw.TextStyle(fontSize: el.fontSize),
          );
          break;
        case 'product_price':
          if (price != null) {
            contentWidget = pw.Text(
              price.toStringAsFixed(_docDecimals),
              style: style,
              textAlign: align,
            );
          } else {
            contentWidget = pw.SizedBox();
          }
          break;
        case 'company_name':
          contentWidget = pw.Text(
            companyName ?? '',
            style: style,
            textAlign: align,
          );
          break;
        case 'text':
          contentWidget = pw.Text(
            el.content ?? '',
            style: style,
            textAlign: align,
          );
          break;
        case 'line':
        case 'divider':
          contentWidget = pw.Container(
            width: w,
            height: 0.5,
            decoration: const pw.BoxDecoration(
              border: pw.Border(bottom: pw.BorderSide(width: 0.5)),
            ),
          );
          break;
        case 'rectangle':
          contentWidget = pw.Container(
            width: w,
            height: h,
            decoration: pw.BoxDecoration(
              border: pw.Border.all(
                width: el.borderWidth > 0 ? el.borderWidth : 0.5,
              ),
            ),
          );
          break;
        default:
          contentWidget = pw.Text(
            el.content ?? '',
            style: style,
            textAlign: align,
          );
      }

      children.add(
        pw.Positioned(
          left: x,
          top: y,
          child: pw.SizedBox(width: w, child: contentWidget),
        ),
      );
    }

    return pw.Container(
      width: labelWidth,
      height: labelHeight,
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300, width: 0.3),
      ),
      child: pw.Stack(children: children),
    );
  }

  /// Resolve barcode type from template content string
  static pw.Barcode _resolveBarcodeType(String? type) {
    switch (type) {
      case 'ean13':
        return pw.Barcode.ean13();
      case 'ean8':
        return pw.Barcode.ean8();
      case 'upcA':
        return pw.Barcode.upcA();
      case 'code39':
        return pw.Barcode.code39();
      case 'code93':
        return pw.Barcode.code93();
      case 'codabar':
        return pw.Barcode.codabar();
      case 'qrCode':
        return pw.Barcode.qrCode();
      case 'code128':
      default:
        return pw.Barcode.code128();
    }
  }
}
