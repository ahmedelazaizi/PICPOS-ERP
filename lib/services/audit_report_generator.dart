// ═══════════════════════════════════════════════════════════════════════════
// C-08: Consolidated Audit Report Generator
// Generates a formatted PDF report from audit/activity logs
// ═══════════════════════════════════════════════════════════════════════════

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart' as printing_pkg;
import 'package:intl/intl.dart';

/// Generates a consolidated audit report as PDF
class AuditReportGenerator {
  static final _fmt = DateFormat('yyyy/MM/dd HH:mm');

  /// Generate and print a consolidated audit report
  static Future<void> generateAndPrint({
    required List<AuditReportEntry> entries,
    required String companyName,
    required DateTime fromDate,
    required DateTime toDate,
    String generatedBy = '',
  }) async {
    final font = await printing_pkg.PdfGoogleFonts.cairoRegular();
    final fontBold = await printing_pkg.PdfGoogleFonts.cairoBold();
    final ttf = font;
    final ttfBold = fontBold;

    final pdf = pw.Document();

    // Group entries by category
    final grouped = <String, List<AuditReportEntry>>{};
    for (final e in entries) {
      (grouped[e.category] ??= []).add(e);
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        textDirection: pw.TextDirection.rtl,
        theme: pw.ThemeData.withFont(base: ttf, bold: ttfBold),
        header: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            pw.Text(companyName, style: pw.TextStyle(font: ttfBold, fontSize: 16)),
            pw.SizedBox(height: 4),
            pw.Text(
              'تقرير المراجعة الموحد',
              style: pw.TextStyle(font: ttfBold, fontSize: 14),
            ),
            pw.SizedBox(height: 2),
            pw.Text(
              'من ${_fmt.format(fromDate)} إلى ${_fmt.format(toDate)}',
              style: pw.TextStyle(font: ttf, fontSize: 10, color: PdfColors.grey600),
            ),
            pw.Divider(),
          ],
        ),
        footer: (ctx) => pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'أعده: $generatedBy | ${_fmt.format(DateTime.now())}',
              style: pw.TextStyle(font: ttf, fontSize: 8, color: PdfColors.grey),
            ),
            pw.Text(
              'صفحة ${ctx.pageNumber} من ${ctx.pagesCount}',
              style: pw.TextStyle(font: ttf, fontSize: 8, color: PdfColors.grey),
            ),
          ],
        ),
        build: (ctx) {
          final widgets = <pw.Widget>[];

          // Summary statistics
          widgets.add(pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey300),
              borderRadius: pw.BorderRadius.circular(6),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
              children: [
                _statBox(ttf, ttfBold, 'إجمالي السجلات', entries.length.toString()),
                _statBox(ttf, ttfBold, 'المستخدمون', entries.map((e) => e.userName).toSet().length.toString()),
                _statBox(ttf, ttfBold, 'الفئات', grouped.keys.length.toString()),
              ],
            ),
          ));
          widgets.add(pw.SizedBox(height: 12));

          // Section per category
          for (final category in grouped.keys) {
            final catEntries = grouped[category]!;
            widgets.add(pw.Header(
              level: 2,
              text: category,
              textStyle: pw.TextStyle(font: ttfBold, fontSize: 12),
            ));

            widgets.add(pw.TableHelper.fromTextArray(
              headerStyle: pw.TextStyle(font: ttfBold, fontSize: 9),
              cellStyle: pw.TextStyle(font: ttf, fontSize: 8),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
              cellAlignment: pw.Alignment.centerRight,
              headers: ['التاريخ', 'المستخدم', 'الإجراء', 'التفاصيل'],
              data: catEntries.map((e) => [
                _fmt.format(e.timestamp),
                e.userName,
                e.action,
                e.details,
              ]).toList(),
            ));

            widgets.add(pw.SizedBox(height: 8));
          }

          return widgets;
        },
      ),
    );

    final bytes = await pdf.save();
    await printing_pkg.Printing.layoutPdf(
      onLayout: (_) => bytes,
      name: 'audit_report_${DateFormat('yyyyMMdd').format(fromDate)}_${DateFormat('yyyyMMdd').format(toDate)}',
    );
  }

  static pw.Widget _statBox(pw.Font font, pw.Font fontBold, String label, String value) {
    return pw.Column(
      children: [
        pw.Text(value, style: pw.TextStyle(font: fontBold, fontSize: 18, color: PdfColors.blue800)),
        pw.Text(label, style: pw.TextStyle(font: font, fontSize: 9, color: PdfColors.grey600)),
      ],
    );
  }
}

/// Data model for audit report entries
class AuditReportEntry {
  final DateTime timestamp;
  final String userName;
  final String action;
  final String details;
  final String category;

  const AuditReportEntry({
    required this.timestamp,
    required this.userName,
    required this.action,
    required this.details,
    required this.category,
  });
}
