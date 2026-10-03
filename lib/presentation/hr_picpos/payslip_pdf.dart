// J4 (الجزء ٣) — قسيمةُ الراتب PDF: رأسُ المنشأة (الاسمان والتواصل والرقم
// الضريبيّ)، بياناتُ الموظف والفترة، جدولا الاستحقاقات والاستقطاعات،
// الصافي وحصّةُ المنشأة. بالعربيّة (RTL) أو الإنجليزيّة (LTR) تبعاً للغة
// الواجهة، والتسمياتُ عبر `tr`. يبني على `BaseGenerator.newDocument` (خطُّ
// Noto Naskh الكامل) ولا يمسّ قوالبَ الطباعة.
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/i18n/tr.dart';
import '../../domain/models/hr_payroll.dart';
import '../../services/generators/base_generator.dart' show BaseGenerator;
import '../../services/printing/printing_models.dart' show DocumentCompanyHeader;
import 'hr_payroll_labels.dart';

/// يبني قسائمَ [lines] من [run] — صفحةٌ لكلّ موظف.
Future<pw.Document> buildPayslipDocument({
  required PayrollRun run,
  required List<PayrollLine> lines,
  required DocumentCompanyHeader company,
  required bool english,
}) async {
  final doc = await BaseGenerator.newDocument();
  final dir = english ? pw.TextDirection.ltr : pw.TextDirection.rtl;
  const muted = PdfColor.fromInt(0xFF6B7280);
  const hairline = PdfColor.fromInt(0xFFD1D5DB);
  const accent = PdfColor.fromInt(0xFF4F46E5);

  pw.Widget cell(String text,
          {bool bold = false, bool number = false, PdfColor? color}) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: pw.Text(
          text,
          textAlign: number
              ? (english ? pw.TextAlign.right : pw.TextAlign.left)
              : null,
          style: pw.TextStyle(
            fontSize: 10,
            fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
            color: color,
          ),
        ),
      );

  pw.Widget table(String title, Iterable<PayrollItem> items, double total) =>
      pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
        pw.Text(title,
            style: pw.TextStyle(
                fontSize: 12, fontWeight: pw.FontWeight.bold, color: accent)),
        pw.SizedBox(height: 4),
        pw.Table(
          border: pw.TableBorder.all(color: hairline, width: 0.5),
          columnWidths: const {
            0: pw.FlexColumnWidth(3),
            1: pw.FlexColumnWidth(1.4),
          },
          children: [
            for (final i in items)
              pw.TableRow(children: [
                cell(payItemLabel(i) +
                    ((i.reason ?? '').isNotEmpty ? ' — ${trData(i.reason)}' : '')),
                cell(hrMoney(i.amount), number: true),
              ]),
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: PdfColors.grey200),
              children: [
                cell(tr('المجموع'), bold: true),
                cell(hrMoney(total), bold: true, number: true),
              ],
            ),
          ],
        ),
      ]);

  for (final line in lines) {
    final info = <(String, String)>[
      (tr('الموظف'), line.employeeName),
      if ((line.employeeCode ?? '').isNotEmpty) (tr('الكود'), line.employeeCode!),
      if ((line.departmentName ?? '').isNotEmpty)
        (tr('القسم'), trData(line.departmentName)),
      (tr('الفترة'), run.period),
      (tr('أيام الاستحقاق'),
          '${line.paidDays.toStringAsFixed(line.paidDays % 1 == 0 ? 0 : 2)} / '
              '${line.periodDays.toStringAsFixed(0)}'),
      (tr('الراتب الأساسي'), hrMoney(line.basicSalary)),
    ];
    final secondary = english ? company.displayName : company.secondaryNameLine;
    final primary = english && (company.nameEn ?? '').trim().isNotEmpty
        ? company.nameEn!.trim()
        : company.displayName;
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      textDirection: dir,
      margin: const pw.EdgeInsets.all(28),
      build: (_) => [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(primary,
                      style: pw.TextStyle(
                          fontSize: 16, fontWeight: pw.FontWeight.bold)),
                  if (secondary.trim().isNotEmpty && secondary != primary)
                    pw.Text(secondary,
                        style: const pw.TextStyle(fontSize: 10, color: muted)),
                  if (company.hasContactInfo)
                    pw.Text(company.contactLine,
                        style: const pw.TextStyle(fontSize: 9, color: muted)),
                  if ((company.taxId ?? '').trim().isNotEmpty)
                    pw.Text(
                        tr('الرقم الضريبي: {p0}',
                            {'p0': company.taxId!.trim()}),
                        style: const pw.TextStyle(fontSize: 9, color: muted)),
                ],
              ),
            ),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text(tr('قسيمة راتب'),
                    style: pw.TextStyle(
                        fontSize: 18,
                        fontWeight: pw.FontWeight.bold,
                        color: accent)),
                pw.Text(run.period, style: const pw.TextStyle(fontSize: 12)),
              ],
            ),
          ],
        ),
        pw.Divider(color: hairline),
        pw.Wrap(spacing: 18, runSpacing: 4, children: [
          for (final (k, v) in info)
            pw.Text('$k: $v', style: const pw.TextStyle(fontSize: 10)),
        ]),
        pw.SizedBox(height: 12),
        table(tr('الاستحقاقات'), line.earnings, line.gross),
        pw.SizedBox(height: 10),
        table(tr('الاستقطاعات'), line.deductionItems, line.deductions),
        pw.SizedBox(height: 12),
        pw.Container(
          padding: const pw.EdgeInsets.all(10),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: accent, width: 1),
            borderRadius: pw.BorderRadius.circular(6),
          ),
          child: pw.Row(children: [
            pw.Expanded(
              child: pw.Text(tr('صافي الراتب'),
                  style: pw.TextStyle(
                      fontSize: 13, fontWeight: pw.FontWeight.bold)),
            ),
            pw.Text(hrMoney(line.net),
                style:
                    pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
          ]),
        ),
        if (line.employerCost > 0) ...[
          pw.SizedBox(height: 6),
          pw.Text(
              tr('حصة المنشأة في التأمينات: {p0}',
                  {'p0': hrMoney(line.employerCost)}),
              style: const pw.TextStyle(fontSize: 9, color: muted)),
        ],
        pw.SizedBox(height: 30),
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Text(tr('توقيع الموظف'), style: const pw.TextStyle(fontSize: 10)),
          pw.Text(tr('توقيع المحاسب'), style: const pw.TextStyle(fontSize: 10)),
        ]),
      ],
    ));
  }
  return doc;
}
