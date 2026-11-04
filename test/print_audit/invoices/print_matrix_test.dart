// Full audit is intentionally opt-in: flutter test's default suite must stay fast.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/domain/entities/shift_closing_snapshot.dart';
import 'package:picpos_erp/domain/printing/print_values.dart';
import 'package:picpos_erp/services/printing/template_render_pipeline.dart';
import 'package:picpos_erp/services/printing/paint_plan.dart'
    show PaintDirection;
import 'package:picpos_erp/services/templated_invoice_service.dart';
import '../../helpers/pdf_probe.dart';
import '../../helpers/arabic_pdf_text.dart';

final bool auditSkip = Platform.environment['RUN_PRINT_AUDIT'] != '1';
const _assets = 'assets/invoice_templates';
const _output = r'D:\qa\print_fix_F\invoices';
final _auditLogo = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAAEklEQVR4nGNUjlrAwMDAxAAGAA0JASH1DRq4AAAAAElFTkSuQmCC',
);

class _Case {
  const _Case(
    this.id,
    this.count, {
    this.longName = false,
    this.empty = false,
    this.negative = false,
    this.large = false,
    this.english = false,
    this.withCustomer = true,
    this.withLogo = false,
    this.tenDigits = false,
  });
  final String id;
  final int count;
  final bool longName, empty, negative, large, english, withCustomer, withLogo;
  final bool tenDigits;
}

const _cases = <_Case>[
  _Case('S1_5_items', 5),
  _Case('S2_15_items', 15),
  _Case('S3_25_items', 25),
  _Case('S4_42_items', 42),
  _Case('S5_120_items', 120),
  _Case('S6_long_name_96', 5, longName: true),
  _Case('S7_no_customer_notes_discount', 5, withCustomer: false, empty: true),
  _Case('S8_negative_return', 5, negative: true),
  _Case('S9_eight_digit_discount_tax', 5, large: true),
  _Case('S10_split_payment_delivery', 5),
  _Case('S11_ar_en_logo_qr', 5, english: true, withLogo: true),
  _Case('S12_zero_items', 0),
  _Case('S12_one_item', 1),
  _Case('S13_ten_digit_amount', 1, tenDigits: true),
];

List<Map<String, dynamic>> _items(_Case c) => [
  for (var i = 0; i < c.count; i++)
    {
      'name': c.longName && i == 0
          ? 'اسم صنف طويل جداً لاختبار التفاف النص والحافة في قالب الفاتورة العربية والإنجليزية ٩٦ حرفاً'
          : '${c.english ? 'Product' : 'صنف'} ${i + 1}',
      'code': 'SKU-${1000 + i}',
      'quantity': c.negative ? -1.0 : 1.0,
      'price': c.tenDigits ? 1234567890.0 : (c.large ? 12345678.0 : 27.5),
      'discount': c.large ? 123456.0 : 0.0,
      'tax': c.large ? 1728390.0 : 0.0,
      'total': c.negative
          ? -27.5
          : (c.tenDigits
                ? 1234567890.0
                : (c.large ? 12345678.0 - 123456.0 + 1728390.0 : 27.5)),
    },
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'render seeded JSON template PDFs for the invoice content matrix',
    () async {
      final db = AppDatabase.forTesting();
      try {
        final files =
            Directory(_assets)
                .listSync()
                .whereType<File>()
                .where((f) => f.path.toLowerCase().endsWith('.json'))
                .toList()
              ..sort((a, b) => a.path.compareTo(b.path));
        expect(files, isNotEmpty);
        final written = <String>[];
        final csv = StringBuffer(
          'template,size,scenario,pages,page_size_points,clipped_text_runs,text_overlaps,total_delta,header_every_page,total_occurrences,total_page,last_page_total,single_item_orphan,min_font_pt,bottom_blank_ratio,images\n',
        );
        for (final file in files) {
          final raw = await file.readAsString();
          final data = jsonDecode(raw) as Map<String, dynamic>;
          final templateId = await db.importTemplateFromJson(raw);
          final bundle = await db.getTemplateWithData(templateId);
          if (bundle == null)
            throw StateError('Imported template data missing: ${file.path}');
          final templateName = file.uri.pathSegments.last.replaceAll(
            '.json',
            '',
          );
          for (final c in _cases) {
            final rows = _items(c);
            final sum = rows.fold<double>(
              0,
              (v, row) => v + (row['total'] as num).toDouble(),
            );
            final discount = c.empty ? 0.0 : (c.large ? 123456.0 : 0.0);
            final tax = c.large ? 1728390.0 : 0.0;
            final payload = PrintPayload(
              invoiceNumber: 'AUDIT-${c.id}',
              date: DateTime.utc(2026, 11, 3),
              companyName: 'مؤسسة النور',
              companyNameEn: 'Al Noor Trading',
              companyAddress: 'شارع الجمهورية',
              companyPhone: '01001234567',
              companyTaxId: '310123456789',
              customerName: c.withCustomer ? 'عميل التدقيق' : null,
              customerPhone: c.withCustomer ? '01119876543' : null,
              cashierName: 'مدقق',
              notes: c.empty ? null : 'ملاحظات اختبار',
              locale: c.english ? 'en' : 'ar',
              paymentMethod: 'نقدي + بنك + آجل',
              subtotal: c.large
                  ? rows.fold<double>(
                      0,
                      (v, row) => v + (row['price'] as num).toDouble(),
                    )
                  : sum,
              discount: c.large ? discount * rows.length : discount,
              tax: c.large ? tax * rows.length : tax,
              deliveryFee: c.id.startsWith('S10') ? 35 : 0,
              total: c.large
                  ? sum
                  : sum - discount + tax + (c.id.startsWith('S10') ? 35 : 0),
              paid: sum / 2,
              remaining: sum / 2,
              cashAmount: sum / 3,
              bankAmount: sum / 3,
              orderNumber: templateName == 'thermal58_kitchen' ? 'K-1' : null,
              adhocCustomerName: templateName == 'thermal58_kitchen'
                  ? '5'
                  : null,
            );
            // The shift-specific keys are resolved from the real snapshot,
            // using the same values already supported by the v1 print path.
            final shift = data['type'] == 'shift_closing'
                ? ShiftClosingSnapshot(
                    invoiceCount: c.count,
                    totalSales: sum,
                    systemCash: 100,
                    systemCard: 50,
                    systemClick: 25,
                    actualCash: 100,
                    actualCard: 48,
                    actualClick: 25,
                    cashVariance: 0,
                    cardVariance: -2,
                    clickVariance: 0,
                    totalVariance: -2,
                    totalExpenses: 0,
                    cashRefunds: 0,
                    cashIncome: 0,
                    creditSales: 0,
                    creditSalesCount: 0,
                    openingBalance: 0,
                    employeeName: 'مدقق',
                    closedAt: DateTime.utc(2026, 11, 3),
                  )
                : null;
            final bytes = await TemplateRenderPipeline.render(
              template: bundle.template,
              orderedElements: TemplatedInvoiceService.orderElementsForPrint(
                bundle.elements,
              ),
              tableSettings: bundle.tableSettings,
              payload: payload,
              items: rows,
              direction: c.english ? PaintDirection.ltr : PaintDirection.rtl,
              logoBytes: c.withLogo ? _auditLogo : null,
              shift: shift,
            );
            final size = (data['paperSize'] as String? ?? 'unknown').replaceAll(
              '/',
              '_',
            );
            final dir = Directory('$_output\\$size\\$templateName');
            await dir.create(recursive: true);
            final target = File('${dir.path}\\${c.id}.pdf');
            await target.writeAsBytes(bytes, flush: true);
            written.add(target.path);
            final probe = probePdf(bytes);
            if (templateName == 'thermal58_kitchen' && c.id == 'S1_5_items') {
              final printedText = probe.allTexts
                  .map((text) => text.text)
                  .join(' ');
              expect(printedText, contains('K-1'));
              final normalizedText = deshapeArabic(printedText);
              expect(normalizedText, contains('الطاولة: 5'));
              expect(normalizedText, contains('ملاحظات اختبار'));
            }
            final margins =
                (bundle.template.paperWidth <= 80 ? 2.0 : 4.0) * 72 / 25.4;
            var clipped = 0;
            var overlaps = 0;
            final normalizedByPage = <int, List<String>>{};
            for (final page in probe.pages) {
              final texts = page.texts;
              normalizedByPage[page.index] = texts
                  .map((t) => deshapeArabic(t.text))
                  .toList();
              for (final t in texts) {
                final estimatedWidth = t.text.runes.length * t.size * .52;
                if (t.x < margins ||
                    t.x + estimatedWidth > page.widthPts - margins)
                  clipped++;
              }
              for (var a = 0; a < texts.length; a++) {
                final ta = texts[a];
                final aw = ta.text.runes.length * ta.size * .52;
                for (var b = a + 1; b < texts.length; b++) {
                  final tb = texts[b];
                  final bw = tb.text.runes.length * tb.size * .52;
                  if ((ta.x < tb.x + bw && tb.x < ta.x + aw) &&
                      (ta.y - ta.size < tb.y && tb.y - tb.size < ta.y))
                    overlaps++;
                }
              }
            }
            final totalHits = <int>[];
            for (final page in probe.pages) {
              final txt = normalizedByPage[page.index]!.join(' ');
              if (txt.contains('الإجمالي') ||
                  txt.toUpperCase().contains('TOTAL'))
                totalHits.add(page.index);
            }
            final pageSize = probe.pages.isEmpty
                ? ''
                : '${probe.pages.first.widthPts.toStringAsFixed(2)}x${probe.pages.first.heightPts.toStringAsFixed(2)}';
            final minFont = probe.allTexts.isEmpty
                ? ''
                : probe.allTexts
                      .map((t) => t.size)
                      .reduce((a, b) => a < b ? a : b)
                      .toStringAsFixed(2);
            final bottomBlank = probe.pages.isEmpty
                ? ''
                : ((probe.pages.last.heightPts -
                              (probe.pages.last.texts
                                  .map((t) => t.y)
                                  .fold<double>(0, (a, b) => a > b ? a : b))) /
                          probe.pages.last.heightPts)
                      .toStringAsFixed(4);
            String csvCell(String value) => '"${value.replaceAll('"', '""')}"';
            csv.writeln(
              [
                templateName,
                size,
                c.id,
                probe.pageCount,
                pageSize,
                clipped,
                overlaps,
                '',
                '',
                totalHits.length,
                totalHits.isEmpty ? '' : totalHits.last,
                totalHits.isNotEmpty && totalHits.last == probe.pageCount,
                '',
                minFont,
                bottomBlank,
                probe.allImages.length,
              ].map((v) => csvCell('$v')).join(','),
            );
          }
        }
        // 78mm cannot be passed as paperWidth=78 without the renderer subtracting 8mm.
        // The production width policy is recorded in the report; no production override is made.
        await File(
          '$_output\\generated_files.txt',
        ).writeAsString(written.join('\n'));
        await File('$_output\\results.csv').writeAsString(csv.toString());
        expect(written, isNotEmpty);
      } finally {
        await db.close();
      }
    },
    skip: auditSkip,
  );
}
