// Audit B DATA-007 (CSV formula injection) and DATA-008 (barcode trimmed).
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/services/csv_import_export_service.dart';

void main() {
  test('formula-looking cells are neutralised with a leading apostrophe', () {
    expect(escapeCsvCell('=HYPERLINK("http://x")'), contains("'=HYPERLINK"));
    expect(escapeCsvCell('+cmd|calc'), "'+cmd|calc");
    expect(escapeCsvCell('@SUM(A1)'), "'@SUM(A1)");
    expect(escapeCsvCell('-2+3'), "'-2+3");
    expect(escapeCsvCell('\tTAB'), "'\tTAB");
  });

  test('plain numbers and normal text are untouched', () {
    expect(escapeCsvCell('-5'), '-5');
    expect(escapeCsvCell('+3.5'), '+3.5');
    expect(escapeCsvCell('1200'), '1200');
    expect(escapeCsvCell('Milk'), 'Milk');
    expect(escapeCsvCell(''), '');
  });

  test('quoting rules still apply after neutralising', () {
    expect(escapeCsvCell('=A,B'), '"\'=A,B"');
    expect(escapeCsvCell('say "hi"'), '"say ""hi"""');
  });
}
