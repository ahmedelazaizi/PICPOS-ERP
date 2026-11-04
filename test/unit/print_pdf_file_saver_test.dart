import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/services/printing/print_pdf_file_saver.dart';

void main() {
  test('selected PDF path receives the rendered PDF bytes', () async {
    final directory = await Directory.systemTemp.createTemp('picpos-pdf-');
    addTearDown(() => directory.delete(recursive: true));
    final target = '${directory.path}${Platform.pathSeparator}saved.pdf';
    final pdf = Uint8List.fromList('%PDF-1.7\nfixture'.codeUnits);

    final savedPath = await PrintPdfFileSaver.save(
      bytes: pdf,
      suggestedName: 'saved.pdf',
      pickPath: (_) async => target,
    );

    expect(savedPath, target);
    final contents = await File(target).readAsBytes();
    expect(String.fromCharCodes(contents.take(4)), '%PDF');
    expect(contents, pdf);
  });
}
