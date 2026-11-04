import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/services/printing/pdf_compute_helper.dart';
import 'package:picpos_erp/services/printing/printing_models.dart';
import 'package:picpos_erp/services/printing/report_pdf_generator.dart';

import '../../helpers/pdf_probe.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'party statement pages never end with fewer than four transaction rows',
    () async {
      for (final count in List<int>.generate(28, (index) => index + 18)) {
        final rows = List.generate(
          count,
          (index) => StatementItem(
            date: DateTime(2026, 11, 3).add(Duration(days: index)),
            description: 'حركة مالية ${index + 1}',
            documentNumber: 'DOC-${(index + 1).toString().padLeft(3, '0')}',
            debit: index.isEven ? 100 : 0,
            credit: index.isOdd ? 75 : 0,
            balance: 100.0 + index,
          ),
        );
        Uint8List? output;
        PdfComputeHelper.nativeLayoutOverride = (bytes, _) async {
          output = Uint8List.fromList(bytes);
          return true;
        };
        try {
          expect(
            await ReportPdfGenerator.printPartyStatement(
              partyName: 'طرف اختبار',
              partyType: 'customer',
              currentBalance: 300,
              transactions: rows,
            ),
            isTrue,
          );
        } finally {
          PdfComputeHelper.nativeLayoutOverride = null;
        }

        if (count == 25) {
          final outputDirectory = Directory(r'D:\qa\print_fix_E_2026-11-03');
          await outputDirectory.create(recursive: true);
          await File(
            '${outputDirectory.path}\\party_25_after.pdf',
          ).writeAsBytes(output!, flush: true);
        }
        final pages = probePdf(output!).pages;
        expect(pages, isNotEmpty, reason: 'N=$count');
        final lastRows = pages.last.texts
            .where((run) => run.text.contains('DOC-'))
            .length;
        expect(
          lastRows,
          greaterThanOrEqualTo(4),
          reason:
              'N=$count, pages=${pages.length}, final=${pages.last.texts.map((run) => run.text).join('|')}',
        );
        if (pages.length > 1) {
          expect(
            pages.every(
              (page) => page.texts.any((run) => run.text.contains('ﺍﻟﺘﺎﺭﻳﺦ')),
            ),
            isTrue,
            reason: 'N=$count: repeated table heading missing',
          );
          expect(
            pages.every(
              (page) => page.texts.any((run) => run.text.contains('ﺻﻔﺤﺔ')),
            ),
            isTrue,
            reason: 'N=$count: page numbering missing',
          );
        }
      }
    },
  );
}
