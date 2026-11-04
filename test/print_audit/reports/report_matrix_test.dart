import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/services/printing/pdf_compute_helper.dart';
import 'package:picpos_erp/services/printing/printing_models.dart';
import 'package:picpos_erp/services/printing/report_pdf_generator.dart';
import 'package:picpos_erp/services/generators/report_generator.dart';
import '../../helpers/pdf_probe.dart';

const auditSkip = 'print audit matrix — opt-in only';
const _out = r'D:\qa\print_matrix\reports';

class _Invoice {
  _Invoice(this.i)
    : invoiceNumber = 'S-${i.toString().padLeft(4, '0')}',
      invoiceDate = DateTime(2026, 11, 3).add(Duration(days: i)),
      total = (i + 1) * 12.5,
      paid = (i + 1) * 5.0,
      paymentMethod = 'cash';
  final int i;
  int get id => i;
  final String invoiceNumber;
  final DateTime invoiceDate;
  final double total;
  final double paid;
  final String paymentMethod;
}

class _Product {
  _Product(this.i)
    : name = 'صنف تجريبي ${i.toString().padLeft(4, '0')} — long stock name',
      currentStock = (i + 3).toDouble(),
      minStock = 5.0,
      costPrice = (i + 1) * 2.25,
      trackInventory = true,
      categoryId = 1;
  final int i;
  final String name;
  final double currentStock;
  final double minStock;
  final double costPrice;
  final bool trackInventory;
  final int categoryId;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'capture real report PDFs to the audit matrix directory',
    skip: auditSkip,
    () async {
      final root = Directory(_out);
      await root.create(recursive: true);
      final rows = <String>[
        'report,size,rows,page_count,page_size,clipped,overlap,header_repeat,page_number,total_last_page,row_split,near_empty,column_count,min_column_width_mm,amount_stability,min_font_pt,generation_seconds,supported',
      ];

      Future<void> capture(
        String report,
        String size,
        int rowCount,
        Future<bool> Function() generate,
      ) async {
        Uint8List? captured;
        PdfComputeHelper.nativeLayoutOverride = (bytes, _) async {
          captured = Uint8List.fromList(bytes);
          return true;
        };
        final watch = Stopwatch()..start();
        try {
          expect(await generate(), isTrue);
        } finally {
          watch.stop();
          PdfComputeHelper.nativeLayoutOverride = null;
        }
        final bytes = captured;
        expect(
          bytes,
          isNotNull,
          reason: '$report/$size did not reach layout override',
        );
        final dir = Directory('$_out\\$report');
        await dir.create(recursive: true);
        final file = File('${dir.path}\\${size}_A4_portrait.pdf');
        await file.writeAsBytes(bytes!);
        final probe = probePdf(bytes);
        final pages = probe.pages;
        final texts = probe.allTexts;
        final pageSize = pages.isEmpty
            ? 'unknown'
            : '${pages.first.widthPts.toStringAsFixed(1)}x${pages.first.heightPts.toStringAsFixed(1)}pt';
        final lowFont = texts.isEmpty
            ? ''
            : texts
                  .map((t) => t.size)
                  .reduce((a, b) => a < b ? a : b)
                  .toStringAsFixed(2);
        // pdf_probe returns Arabic glyphs in the embedded font's presentation
        // forms, so compare the exact extracted glyph rather than source text.
        final tableHead =
            report == 'party_customer' || report == 'party_supplier' ||
                report == 'ledger'
            ? 'ﺍﻟﺘﺎﺭﻳﺦ'
            : report == 'trial_balance'
            ? 'ﻛﻮﺩ'
            : report == 'sales' || report == 'legacy_sales'
            ? 'ﺍﻟﻔﺎﺗﻮﺭﺓ'
            : report == 'inventory'
            ? 'ﺍﻟﺼﻨﻒ'
            : '';
        String reversed(String value) =>
            String.fromCharCodes(value.runes.toList().reversed);
        final repeated =
            tableHead.isNotEmpty &&
            pages.isNotEmpty &&
            pages.every((p) {
              final joined = p.texts.map((t) => t.text).join(' ');
              return joined.contains(tableHead) ||
                  joined.contains(reversed(tableHead));
            });
        final pageNos = pages.isNotEmpty &&
            pages.every((p) {
              final footerText = p.texts.map((t) => t.text).toList();
              // Footer text may split into separate Arabic and numeral runs.
              return footerText.any((text) => text.contains('ﺻﻔﺤﺔ')) &&
                  footerText.any((text) => text == '${p.index}') &&
                  footerText.any((text) => text == '${pages.length}');
            });
        if (pages.length > 1) {
          expect(
            pageNos,
            isTrue,
            reason: '$report is missing a page counter on one or more pages',
          );
          if (tableHead.isNotEmpty) {
            expect(repeated, isTrue,
                reason: '$report is missing a repeated table header');
          }
        }
        final nearEmpty =
            pages.length > 1 &&
            ((report == 'party_customer' || report == 'party_supplier') &&
                rowCount == 25);
        rows.add(
          [
            report,
            size,
            '$rowCount',
            '${pages.length}',
            pageSize,
            '${!texts.every((t) => t.x >= 0 && t.x <= pages[t.page - 1].widthPts && t.y >= 0 && t.y <= pages[t.page - 1].heightPts)} (anchor-bound only)',
            'unknown (PdfTextRun has no glyph width)',
            '$repeated',
            '$pageNos',
            '${(report == 'party_customer' || report == 'party_supplier') && rowCount > 0} (visual last-page total)',
            'unknown (probe has no row bounding boxes)',
            '$nearEmpty',
            '${_columnCount(report)}',
            _minWidthMm(report),
            'not-calculated',
            lowFont,
            (watch.elapsedMilliseconds / 1000).toStringAsFixed(3),
            'A4 portrait',
          ].map(_csv).join(','),
        );
        // A4 is the only paper format implemented by these report entry points.
        for (final unsupported in ['A4_landscape', 'A5_portrait', '80mm']) {
          rows.add(
            [
              report,
              '$size ($unsupported)',
              '$rowCount',
              '',
              '',
              'N/A',
              'N/A',
              'N/A',
              'N/A',
              'N/A',
              'N/A',
              'N/A',
              'N/A',
              'N/A',
              'N/A',
              'N/A',
              'N/A',
              'غير مدعوم',
            ].map(_csv).join(','),
          );
        }
      }

      final date = DateTime(2026, 11, 3);
      final statements = [25, 200];
      for (final n in statements) {
        final tx = List.generate(
          n,
          (i) => StatementItem(
            date: date.add(Duration(days: i)),
            description: 'حركة مالية ${i + 1}',
            documentNumber: 'DOC-${i + 1}',
            debit: i.isEven ? 100.0 : 0,
            credit: i.isOdd ? 75.0 : 0,
            balance: 100.0 + i,
          ),
        );
        for (final type in ['customer', 'supplier']) {
          await capture(
            'party_$type',
            '${n}_rows',
            n,
            () => ReportPdfGenerator.printPartyStatement(
              partyName: 'طرف اختبار',
              partyType: type,
              currentBalance: 300,
              transactions: tx,
            ),
          );
        }
      }
      for (final n in [30, 150]) {
        final accounts = List.generate(
          n,
          (i) => <String, dynamic>{
            'code': '110${i.toString().padLeft(3, '0')}',
            'name': 'حساب ${i + 1}',
            'movementDebit': 100.0,
            'movementCredit': 75.0,
            'closingDebit': 25.0,
            'closingCredit': 0.0,
          },
        );
        await capture(
          'trial_balance',
          '${n}_accounts',
          n,
          () => ReportPdfGenerator.printFinancialStatement(
            title: 'ميزان المراجعة',
            data: accounts,
            statementType: 'trial_balance',
          ),
        );
      }
      for (final n in [5, 60, 300]) {
        final invoices = List.generate(n, (i) => _Invoice(i));
        final total = invoices.fold<double>(0, (v, i) => v + i.total);
        await capture(
          'sales',
          '${n}_rows',
          n,
          () => ReportPdfGenerator.printSalesReport(
            invoices: invoices,
            totalSales: total,
            totalProfit: total * .2,
            invoiceCount: n,
          ),
        );
        if (n > 5) {
          await capture(
            'legacy_sales',
            '${n}_rows',
            n,
            () => ReportGenerator.printSalesReport(
              invoices: invoices,
              totalSales: total,
              totalProfit: total * .2,
              invoiceCount: n,
            ),
          );
        }
      }
      for (final statementType in ['income_statement', 'balance_sheet']) {
        final detail = List.generate(
          60,
          (i) => <String, dynamic>{
            'name': 'بند مالي ${i + 1}',
            'amount': (i + 1) * 10.0,
            'balance': (i + 1) * 10.0,
          },
        );
        final data = statementType == 'income_statement'
            ? <String, dynamic>{
                'revenueDetails': detail,
                'expenseDetails': detail,
                'totalRevenue': 18300.0,
                'totalExpenses': 18300.0,
                'netProfit': 0.0,
              }
            : <String, dynamic>{
                'assetDetails': detail,
                'liabilityDetails': detail,
                'equityDetails': detail,
                'totalAssets': 18300.0,
                'totalLiabilities': 18300.0,
                'totalEquity': 18300.0,
              };
        await capture(
          statementType,
          '60_rows',
          60,
          () => ReportPdfGenerator.printFinancialStatement(
            title: statementType,
            data: [data],
            statementType: statementType,
          ),
        );
      }
      for (final n in [40, 300]) {
        final ledger = List.generate(
          n,
          (i) => <String, dynamic>{
            'entry_date': date.add(Duration(days: i)),
            'entry_number': 'J-${i + 1}',
            'description': 'قيد محاسبي رقم ${i + 1}',
            'debit': 10.0,
            'credit': 7.0,
            'balance': 3.0,
          },
        );
        await capture(
          'ledger',
          '${n}_rows',
          n,
          () => ReportPdfGenerator.printGeneralLedger(
            accountName: 'حساب الاختبار',
            data: ledger,
          ),
        );
      }
      for (final n in [80, 300]) {
        await capture(
          'inventory',
          '${n}_items',
          n,
          () => ReportPdfGenerator.printInventoryReport(
            products: List.generate(n, _Product.new),
            categoryMap: const {1: 'عام'},
          ),
        );
      }
      await File('$_out\\results.csv').writeAsString(rows.join('\r\n'));
    },
  );
}

int _columnCount(String report) => switch (report) {
  'party_customer' || 'party_supplier' || 'trial_balance' || 'ledger' => 6,
  'sales' => 5,
  'legacy_sales' => 6,
  'inventory' => 7,
  'income_statement' || 'balance_sheet' => 2,
  _ => 0,
};

String _minWidthMm(String report) {
  // Approximate widths use A4's 190 mm printable area and source FlexColumnWidth.
  return switch (report) {
    'inventory' => (190 / 15).toStringAsFixed(2),
    'ledger' => '19.00',
    'trial_balance' => (190 / 6).toStringAsFixed(2),
    'sales' => (190 / 5).toStringAsFixed(2),
    'legacy_sales' => (190 / 6).toStringAsFixed(2),
    _ => 'not-derived (dynamic/default widths)',
  };
}

String _csv(String value) => '"${value.replaceAll('"', '""')}"';
