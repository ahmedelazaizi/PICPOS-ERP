import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'base_generator.dart';
import '../printing/pdf_compute_helper.dart';
import '../../core/constants/app_constants.dart';
import '../../core/config/brand.dart';

/// Professional Voucher PDF Generator (A4 format)
/// 
/// Handles printing of professional A4 PDF vouchers for receipts and payments.
class VouchersPdfGenerator extends BaseGenerator {
  /// Print Receipt/Payment Voucher (A4)
  static Future<void> printVoucher({
    required String voucherNumber,
    required String voucherType, // 'receipt' or 'payment'
    required DateTime date,
    required double amount,
    double discount = 0,
    String? partyName,
    String? description,
    String? safeName,
    String? employeeName,
    // Check details
    String? paperNumber,
    String? paperType,
    DateTime? paperDueDate,
    String? paperBankName,
    // Company details
    String? companyName,
    String? companyAddress,
    String? companyPhone,
    String? companyTaxId,
    String? companyLogo,
  }) async {
    final arabicFont = await BaseGenerator.initFont();
    final pdf = pw.Document();
    
    final isReceipt = voucherType == 'receipt';
    final voucherTitle = isReceipt ? 'سند قبض' : 'سند صرف';
    final totalAmount = amount + discount;

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        textDirection: pw.TextDirection.rtl,
        margin: const pw.EdgeInsets.all(24),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            // Header Section
            _buildHeader(
              arabicFont,
              voucherNumber,
              date,
              companyName,
              companyAddress,
              companyPhone,
              companyTaxId,
              amount,
            ),
            pw.SizedBox(height: 10),
            pw.Divider(thickness: 1.5, color: PdfColors.grey700),
            pw.SizedBox(height: 10),

            // Voucher Title and Box
            pw.Center(
               child: pw.Container(
                padding: const pw.EdgeInsets.symmetric(vertical: 8, horizontal: 40),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.black, width: 2),
                  borderRadius: pw.BorderRadius.circular(4),
                  color: PdfColors.grey100,
                ),
                child: pw.Text(
                  voucherTitle,
                  style: pw.TextStyle(
                    font: arabicFont,
                    fontSize: 24,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
            ),
            pw.SizedBox(height: 30),

            // Main Content Box
            pw.Container(
              padding: const pw.EdgeInsets.all(16),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey300),
                borderRadius: pw.BorderRadius.circular(8),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  // Party Line
                  pw.Row(
                    children: [
                      pw.Text(
                        isReceipt ? 'استلمنا من السيد/ة: ' : 'صرفنا إلى السيد/ة: ',
                        style: pw.TextStyle(font: arabicFont, fontSize: 14, fontWeight: pw.FontWeight.bold),
                      ),
                      pw.Expanded(
                        child: pw.Container(
                          padding: const pw.EdgeInsets.only(bottom: 2),
                          decoration: const pw.BoxDecoration(
                            border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey400, style: pw.BorderStyle.dotted)),
                          ),
                          child: pw.Text(
                            partyName ?? '......................................................',
                            style: pw.TextStyle(font: arabicFont, fontSize: 14),
                          ),
                        ),
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 20),

                  // Amount Line
                  pw.Row(
                    children: [
                      pw.Text(
                        'مبلغ وقدره: ',
                        style: pw.TextStyle(font: arabicFont, fontSize: 14, fontWeight: pw.FontWeight.bold),
                      ),
                      pw.Container(
                        padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: pw.BoxDecoration(
                          color: PdfColors.grey200,
                          borderRadius: pw.BorderRadius.circular(4),
                          border: pw.Border.all(color: PdfColors.black),
                        ),
                        child: pw.Text(
                          '${amount.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolAr}',
                          style: pw.TextStyle(font: arabicFont, fontSize: 16, fontWeight: pw.FontWeight.bold),
                        ),
                      ),
                      pw.SizedBox(width: 10),
                      if (discount > 0) ...[
                        pw.Text(
                          ' (خصم: ${discount.toStringAsFixed(AppConstants.decimalPlaces)})',
                          style: pw.TextStyle(font: arabicFont, fontSize: 12, color: PdfColors.red),
                        ),
                      ],
                    ],
                  ),
                  pw.SizedBox(height: 20),

                  // Description Line
                  pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'وذلك عن: ',
                        style: pw.TextStyle(font: arabicFont, fontSize: 14, fontWeight: pw.FontWeight.bold),
                      ),
                      pw.Expanded(
                        child: pw.Container(
                          padding: const pw.EdgeInsets.only(bottom: 2),
                          decoration: const pw.BoxDecoration(
                            border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey400, style: pw.BorderStyle.dotted)),
                          ),
                          child: pw.Text(
                            description ?? '................................................................................................................................................',
                            style: pw.TextStyle(font: arabicFont, fontSize: 13),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 30),

            // Check Details Section (If applicable)
            if (paperNumber != null) ...[
              pw.Text(
                'تفاصيل الشيك / ورقة الدفع',
                style: pw.TextStyle(font: arabicFont, fontSize: 16, fontWeight: pw.FontWeight.bold, decoration: pw.TextDecoration.underline),
              ),
              pw.SizedBox(height: 10),
              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey300),
                children: [
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: PdfColors.grey100),
                    children: [
                      _buildCell(arabicFont, 'رقم الشيك', isHeader: true),
                      _buildCell(arabicFont, 'البنك المسحوب عليه', isHeader: true),
                      _buildCell(arabicFont, 'تاريخ الاستحقاق', isHeader: true),
                    ],
                  ),
                  pw.TableRow(
                    children: [
                      _buildCell(arabicFont, paperNumber),
                      _buildCell(arabicFont, paperBankName ?? '-'),
                      _buildCell(arabicFont, paperDueDate != null ? '${paperDueDate.day}/${paperDueDate.month}/${paperDueDate.year}' : '-'),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 30),
            ],

            pw.Spacer(),

            // Signatures Section
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  children: [
                    pw.Text('المحاسب', style: pw.TextStyle(font: arabicFont, fontSize: 14, fontWeight: pw.FontWeight.bold)),
                    pw.SizedBox(height: 40),
                    pw.Text('_________________', style: pw.TextStyle(font: arabicFont)),
                  ],
                ),
                pw.Column(
                  children: [
                    pw.Text('المدير المالي', style: pw.TextStyle(font: arabicFont, fontSize: 14, fontWeight: pw.FontWeight.bold)),
                    pw.SizedBox(height: 40),
                    pw.Text('_________________', style: pw.TextStyle(font: arabicFont)),
                  ],
                ),
                pw.Column(
                  children: [
                    pw.Text(isReceipt ? 'المستلم' : 'توقيع المستلم', style: pw.TextStyle(font: arabicFont, fontSize: 14, fontWeight: pw.FontWeight.bold)),
                    pw.SizedBox(height: 40),
                    pw.Text('_________________', style: pw.TextStyle(font: arabicFont)),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 40),

            // Footer
            pw.Divider(),
            pw.SizedBox(height: 5),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('نظام ${Brand.name} — حلول ذكية للأعمال', style: pw.TextStyle(font: arabicFont, fontSize: 9, color: PdfColors.grey600)),
                pw.Text('مستخدم: ${employeeName ?? 'المدير'}', style: pw.TextStyle(font: arabicFont, fontSize: 9, color: PdfColors.grey600)),
              ],
            ),
          ],
        ),
      ),
    );

    await PdfComputeHelper.layoutPdf(pdf);
  }

  static pw.Widget _buildHeader(
    pw.Font font,
    String voucherNumber,
    DateTime date,
    String? companyName,
    String? companyAddress,
    String? companyPhone,
    String? companyTaxId,
    double total,
  ) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        // Left Side: Voucher Info
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              'رقم السند: $voucherNumber',
              style: pw.TextStyle(font: font, fontSize: 14, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              'التاريخ: ${date.day}/${date.month}/${date.year}',
              style: pw.TextStyle(font: font, fontSize: 12),
            ),
            pw.SizedBox(height: 4),
            pw.BarcodeWidget(
              barcode: pw.Barcode.qrCode(),
              data: 'VOUCHER:$voucherNumber|DATE:${date.toIso8601String()}|AMT:$total',
              width: 50,
              height: 50,
            ),
          ],
        ),

        // Right Side: Company Details
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text(
              companyName ?? Brand.documentCompanyFallback,
              style: pw.TextStyle(font: font, fontSize: 20, fontWeight: pw.FontWeight.bold),
            ),
            if (companyAddress != null)
              pw.Text(companyAddress, style: pw.TextStyle(font: font, fontSize: 10)),
            if (companyPhone != null)
              pw.Text('هاتف: $companyPhone', style: pw.TextStyle(font: font, fontSize: 10)),
            if (companyTaxId != null)
              pw.Text('رقم ضريبي: $companyTaxId', style: pw.TextStyle(font: font, fontSize: 10)),
          ],
        ),
      ],
    );
  }

  static pw.Widget _buildCell(pw.Font font, String text, {bool isHeader = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(8),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          font: font,
          fontSize: isHeader ? 12 : 11,
          fontWeight: isHeader ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
        textAlign: pw.TextAlign.center,
      ),
    );
  }
}
