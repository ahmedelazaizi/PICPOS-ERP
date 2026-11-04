// مولّد PDF لملصقات الباركود بأي تنسيق [LabelSpec] — المسار الموحّد لكل
// الشاشات (ReportPdfGenerator.printBarcodeLabel يفوّض إليه).
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/constants/app_constants.dart';
import '../generators/base_generator.dart' hide InvoiceItem, StatementItem;
import 'barcode_label_spec.dart';
import 'label_preset_store.dart';
import 'pdf_compute_helper.dart';

abstract final class BarcodeLabelPrinter {
  static const double _mm = PdfPageFormat.mm;

  /// يبني المستند: صفحة لكل صف رول، أو صفحة A4 لكل شبكة.
  static Future<pw.Document> buildDocument(
      List<BarcodeLabelItem> items, LabelSpec spec) async {
    final font = await BaseGenerator.initFont();
    final pdf = await BaseGenerator.newDocument();
    final format = PdfPageFormat(
      spec.pageWidthMm * _mm,
      spec.pageHeightMm * _mm,
      marginAll: spec.pageMarginMm * _mm,
    );
    for (final page in LabelLayout.paginate(spec, items)) {
      pdf.addPage(
        pw.Page(
          pageFormat: format,
          // بدون اتجاه RTL تُطبع أسماء الأصناف العربية مقطّعة ومعكوسة.
          textDirection: pw.TextDirection.rtl,
          build: (_) => _buildPage(page, spec, font),
        ),
      );
    }
    return pdf;
  }

  static pw.Widget _buildPage(
      List<LabelJob> page, LabelSpec spec, pw.Font font) {
    final cellW = spec.cellWidthMm * _mm;
    final cellH = spec.cellHeightMm * _mm;
    final gap = spec.gapMm * _mm;
    final rows = <pw.Widget>[];
    for (var r = 0; r < spec.rows; r++) {
      final cells = <pw.Widget>[];
      for (var c = 0; c < spec.columns; c++) {
        final idx = r * spec.columns + c;
        if (c > 0 && gap > 0) cells.add(pw.SizedBox(width: gap));
        cells.add(pw.SizedBox(
          width: cellW,
          height: cellH,
          child: idx < page.length
              ? _label(page[idx].item, spec, font, cellW, cellH)
              : null,
        ));
      }
      if (r > 0 && gap > 0) rows.add(pw.SizedBox(height: gap));
      if (r * spec.columns < page.length) {
        rows.add(pw.Row(children: cells));
      }
    }
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: rows,
    );
  }

  /// يقيس الخط والباركود نسبةً إلى الأساس 50×25 مم.
  static pw.Widget _label(BarcodeLabelItem item, LabelSpec spec, pw.Font font,
      double cellW, double cellH) {
    final pad = spec.innerPaddingMm * _mm;
    final contentW = cellW - 2 * pad;
    final contentH = cellH - 2 * pad;
    final rawScale = cellW / (50 * _mm) < cellH / (25 * _mm)
        ? cellW / (50 * _mm)
        : cellH / (25 * _mm);
    final double scale = rawScale.clamp(0.6, 3.0).toDouble();
    final double barcodeH = (15 * scale).clamp(8.0, contentH * 0.5).toDouble();
    return pw.Padding(
      padding: pw.EdgeInsets.all(pad),
      child: pw.Column(
        mainAxisAlignment: pw.MainAxisAlignment.center,
        children: [
          pw.Text(
            item.name,
            style: pw.TextStyle(
              font: font,
              fontSize: 7 * scale,
              fontWeight: pw.FontWeight.bold,
            ),
            textAlign: pw.TextAlign.center,
            maxLines: 1,
          ),
          pw.SizedBox(height: 2 * scale),
          pw.BarcodeWidget(
            data: item.barcode,
            barcode: pw.Barcode.code128(),
            width: contentW - 4,
            height: barcodeH,
            drawText: true,
            textStyle: pw.TextStyle(fontSize: 5 * scale),
          ),
          if (item.price != null)
            pw.Text(
              // عملة الشركة المهيأة لا نصاً ثابتاً.
              '${item.price!.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbol}',
              style: pw.TextStyle(
                font: font,
                fontSize: 8 * scale,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
        ],
      ),
    );
  }

  /// يطبع الأصناف بالتنسيق [spec] (أو المقاس النشط المحفوظ إن لم يُمرَّر).
  /// يرجع `false` إن ألغى المستخدم أو لم توجد ملصقات.
  static Future<bool> print(List<BarcodeLabelItem> items,
      {LabelSpec? spec}) async {
    if (LabelLayout.totalLabels(items) == 0) return false;
    final effective = spec ?? await LabelPresetStore.activeSpec();
    final pdf = await buildDocument(items, effective);
    // مقاسُ الورقة للسائق = مقاسُ الصفحة — وإلّا طلبت `printing` ورقةَ A4
    // ورُسمت صفحةُ الرول صغيرةً في ركنها (‏انظر `PdfComputeHelper`).
    return PdfComputeHelper.layoutPdf(
      pdf,
      documentLabel: 'ملصق باركود',
      format: PdfPageFormat(
        effective.pageWidthMm * _mm,
        effective.pageHeightMm * _mm,
      ),
    );
  }
}
