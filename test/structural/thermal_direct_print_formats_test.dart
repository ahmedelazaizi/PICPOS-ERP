import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _directPrintFiles = <String, Map<String, int>>{
  'lib/services/generators/thermal_receipt_generator.dart': {
    'printOutput.format': 2,
  },
  'lib/services/generators/thermal_voucher_generator.dart': {
    'printOutput.format': 4,
  },
  'lib/services/printing/thermal_receipt_generator.dart': {'output.format': 1},
  'lib/services/printing/template_pdf_renderer.dart': {'pageFormat': 1},
};

const _documentPrintFiles = <String, int>{
  'lib/services/printing/thermal_receipt_generator.dart': 2,
};

const _pageFormatUses = <String, Map<String, int>>{
  'lib/services/generators/thermal_receipt_generator.dart': {
    'thermalFormat': 1,
  },
  'lib/services/generators/thermal_voucher_generator.dart': {
    'thermalFormat': 2,
  },
  'lib/services/printing/thermal_receipt_generator.dart': {
    'thermalFormat': 1,
    'kitchenFormat': 1,
    'pageFormat': 1,
  },
  'lib/services/printing/template_pdf_renderer.dart': {'pageFormat': 1},
};

void main() {
  test('every thermal direct PDF route passes its generated page format', () {
    var directCallCount = 0;
    for (final entry in _directPrintFiles.entries) {
      final source = File(entry.key).readAsStringSync();
      final calls = RegExp(
        r'PdfComputeHelper\.directPrintBytes\(([\s\S]*?)\);',
      ).allMatches(source);
      final blocks = calls.map((call) => call.group(1)!).toList();

      expect(blocks, isNotEmpty, reason: entry.key);
      directCallCount += blocks.length;
      for (final expected in entry.value.entries) {
        final matching = blocks
            .where((block) => block.contains('format: ${expected.key}'))
            .length;
        expect(
          matching,
          expected.value,
          reason: '${entry.key} must pass ${expected.key} for each route',
        );
      }
      for (final block in blocks) {
        expect(block, contains('format:'), reason: entry.key);
      }
      for (final expected in _pageFormatUses[entry.key]!.entries) {
        final matching = source.split('pageFormat: ${expected.key}').length - 1;
        expect(
          matching,
          expected.value,
          reason: '${entry.key} must build the PDF with ${expected.key}',
        );
      }
      expect(
        source,
        isNot(contains('PdfComputeHelper.layoutPdf(pdf);')),
        reason: '${entry.key} dialog fallback must also pass its page format',
      );
      expect(
        source,
        isNot(contains('PdfComputeHelper.layoutBytes(pdfBytes);')),
        reason: '${entry.key} dialog fallback must also pass its page format',
      );
      if (!entry.key.endsWith('template_pdf_renderer.dart')) {
        expect(
          source,
          contains('saveToBytesWithMediaBox(pdf)'),
          reason: '${entry.key} must use the final serialized MediaBox',
        );
      }
    }

    var documentCallCount = 0;
    for (final entry in _documentPrintFiles.entries) {
      final source = File(entry.key).readAsStringSync();
      final directCalls = RegExp(
        r'PdfComputeHelper\.directPrintDocument\(',
      ).allMatches(source).length;
      final dialogCalls = RegExp(
        r'PdfComputeHelper\.layoutPdfWithMediaBox\(',
      ).allMatches(source).length;
      expect(directCalls, entry.value, reason: entry.key);
      expect(dialogCalls, entry.value, reason: entry.key);
      documentCallCount += directCalls;
    }
    expect(directCallCount + documentCallCount, 10);
    final nativeCallFiles = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final lines = entity.readAsLinesSync();
      if (lines.any(
        (line) =>
            line.contains('Printing.directPrintPdf(') &&
            !line.trimLeft().startsWith('//') &&
            !line.trimLeft().startsWith('*'),
      )) {
        nativeCallFiles.add(entity.path.replaceAll('\\', '/'));
      }
    }
    expect(
      nativeCallFiles,
      ['lib/services/printing/pdf_compute_helper.dart'],
      reason: 'all direct native printing must pass through the format guard',
    );

    for (final path in _directPrintFiles.keys) {
      final source = File(path).readAsStringSync();
      expect(source, isNot(contains('Printing.directPrintPdf(')), reason: path);
      expect(
        source,
        isNot(contains('printing_pkg.Printing.directPrintPdf(')),
        reason: path,
      );
    }

    expect(
      File(
        'lib/services/printing/template_pdf_renderer.dart',
      ).readAsStringSync(),
      contains('format: pdf.document.pdfPageList.pages.last.pageFormat,'),
      reason: 'the template print format must come from the saved MediaBox',
    );
  });
}
