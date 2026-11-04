// ignore_for_file: avoid_dynamic_calls
// Statement presentation sections are isolated to keep the report generator below its ratchet.
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../core/constants/app_constants.dart';

class FinancialStatementPdfSections {
  static String _fmtNum(dynamic val) {
    if (val == null) return '-';
    final d = (val is num) ? val.toDouble() : 0.0;
    if (d == 0) return '-';
    return d.toStringAsFixed(AppConstants.decimalPlaces);
  }

  static pw.Widget income(Map<String, dynamic> data, pw.Font? font) {
    final revenueDetails = (data['revenueDetails'] as List?) ?? [];
    final expenseDetails = (data['expenseDetails'] as List?) ?? [];
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'الإيرادات',
          style: pw.TextStyle(
            font: font,
            fontSize: 13,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        pw.SizedBox(height: 5),
        ...revenueDetails.map(
          (item) => pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                _fmtNum(item['amount']),
                style: pw.TextStyle(font: font, fontSize: 11),
              ),
              pw.Text(
                item['name']?.toString() ?? '-',
                style: pw.TextStyle(font: font, fontSize: 11),
              ),
            ],
          ),
        ),
        pw.Divider(),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              _fmtNum(data['totalRevenue']),
              style: pw.TextStyle(
                font: font,
                fontSize: 12,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.Text(
              'إجمالي الإيرادات',
              style: pw.TextStyle(
                font: font,
                fontSize: 12,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 15),
        pw.Text(
          'المصروفات',
          style: pw.TextStyle(
            font: font,
            fontSize: 13,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        pw.SizedBox(height: 5),
        ...expenseDetails.map(
          (item) => pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                _fmtNum(item['amount']),
                style: pw.TextStyle(font: font, fontSize: 11),
              ),
              pw.Text(
                item['name']?.toString() ?? '-',
                style: pw.TextStyle(font: font, fontSize: 11),
              ),
            ],
          ),
        ),
        pw.Divider(),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              _fmtNum(data['totalExpenses']),
              style: pw.TextStyle(
                font: font,
                fontSize: 12,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.Text(
              'إجمالي المصروفات',
              style: pw.TextStyle(
                font: font,
                fontSize: 12,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 15),
        pw.Container(
          padding: const pw.EdgeInsets.all(8),
          decoration: pw.BoxDecoration(
            color: PdfColors.grey100,
            borderRadius: pw.BorderRadius.circular(4),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                _fmtNum(data['netProfit']),
                style: pw.TextStyle(
                  font: font,
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.Text(
                'صافي الربح',
                style: pw.TextStyle(
                  font: font,
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static pw.Widget balanceSheet(Map<String, dynamic> data, pw.Font? font) {
    final assetDetails = (data['assetDetails'] as List?) ?? [];
    final liabilityDetails = (data['liabilityDetails'] as List?) ?? [];
    final equityDetails = (data['equityDetails'] as List?) ?? [];
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'الأصول',
          style: pw.TextStyle(
            font: font,
            fontSize: 13,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        pw.SizedBox(height: 5),
        ...assetDetails.map(
          (item) => pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                _fmtNum(item['balance']),
                style: pw.TextStyle(font: font, fontSize: 11),
              ),
              pw.Text(
                item['name']?.toString() ?? '-',
                style: pw.TextStyle(font: font, fontSize: 11),
              ),
            ],
          ),
        ),
        pw.Divider(),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              _fmtNum(data['totalAssets']),
              style: pw.TextStyle(
                font: font,
                fontSize: 12,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.Text(
              'إجمالي الأصول',
              style: pw.TextStyle(
                font: font,
                fontSize: 12,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 15),
        pw.Text(
          'الخصوم',
          style: pw.TextStyle(
            font: font,
            fontSize: 13,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        pw.SizedBox(height: 5),
        ...liabilityDetails.map(
          (item) => pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                _fmtNum(item['balance']),
                style: pw.TextStyle(font: font, fontSize: 11),
              ),
              pw.Text(
                item['name']?.toString() ?? '-',
                style: pw.TextStyle(font: font, fontSize: 11),
              ),
            ],
          ),
        ),
        pw.Divider(),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              _fmtNum(data['totalLiabilities']),
              style: pw.TextStyle(
                font: font,
                fontSize: 12,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.Text(
              'إجمالي الخصوم',
              style: pw.TextStyle(
                font: font,
                fontSize: 12,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 15),
        pw.Text(
          'حقوق الملكية',
          style: pw.TextStyle(
            font: font,
            fontSize: 13,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        pw.SizedBox(height: 5),
        ...equityDetails.map(
          (item) => pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                _fmtNum(item['balance']),
                style: pw.TextStyle(font: font, fontSize: 11),
              ),
              pw.Text(
                item['name']?.toString() ?? '-',
                style: pw.TextStyle(font: font, fontSize: 11),
              ),
            ],
          ),
        ),
        pw.Divider(),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              _fmtNum(data['totalEquity']),
              style: pw.TextStyle(
                font: font,
                fontSize: 12,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.Text(
              'إجمالي حقوق الملكية',
              style: pw.TextStyle(
                font: font,
                fontSize: 12,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
