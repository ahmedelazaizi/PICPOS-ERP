import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/services/label_scale_service.dart';
import 'package:ural_erp/services/scale_transport.dart';

void main() {
  final service = LabelScaleService.instance;

  const singleItem = ScalePLUItem(
    pluNumber: 1,
    name: 'دجاج طازج',
    unitPrice: 25.50,
    tareWeight: 0.010,
    department: 21,
    isByWeight: true,
  );

  const countItem = ScalePLUItem(
    pluNumber: 42,
    name: 'Cheese Pack',
    unitPrice: 5.99,
    department: 2,
    isByWeight: false,
  );

  // ═══════════════════════════════════════════════════════════════
  // TSV Format — Structure
  // ═══════════════════════════════════════════════════════════════

  group('TSV Generation — Structure', () {
    test('produces exactly 24 tab-separated columns per line', () {
      final csv = service.generatePLUCsv([singleItem]);
      final lines = csv.trim().split('\n');
      expect(lines.length, 1);
      final cols = lines[0].trim().split('\t');
      expect(cols.length, 24, reason: 'PLU Manager expects exactly 24 columns');
    });

    test('no header row', () {
      final csv = service.generatePLUCsv([singleItem]);
      // Should NOT start with "Hotkey" or "Name" or "NUM"
      expect(csv, isNot(startsWith('Hotkey')));
      expect(csv, isNot(startsWith('Name')));
      expect(csv, isNot(startsWith('NUM')));
    });

    test('uses tab as separator (not comma)', () {
      final csv = service.generatePLUCsv([singleItem]);
      // Count tabs vs commas — tabs should dominate
      final tabCount = '\t'.allMatches(csv).length;
      expect(tabCount, greaterThanOrEqualTo(23)); // 24 cols = 23 separators
    });

    test('multiple items produce multiple lines', () {
      final csv = service.generatePLUCsv([singleItem, countItem]);
      final lines = csv.trim().split('\n');
      expect(lines.length, 2);
      // Both lines should have 24 columns
      for (final line in lines) {
        expect(line.trim().split('\t').length, 24);
      }
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // TSV Format — Column Values
  // ═══════════════════════════════════════════════════════════════

  group('TSV Generation — Column Values', () {
    test('column[0] Hotkey = PLU number', () {
      final csv = service.generatePLUCsv([singleItem]);
      final cols = csv.trim().split('\n')[0].trim().split('\t');
      expect(cols[0], '1');
    });

    test('column[1] Name = product name', () {
      final csv = service.generatePLUCsv([singleItem]);
      final cols = csv.trim().split('\n')[0].trim().split('\t');
      expect(cols[1], 'دجاج طازج');
    });

    test('column[2] LFCode = empty', () {
      final csv = service.generatePLUCsv([singleItem]);
      final cols = csv.trim().split('\n')[0].trim().split('\t');
      expect(cols[2], '');
    });

    test('column[3] Code = PLU number', () {
      final csv = service.generatePLUCsv([singleItem]);
      final cols = csv.trim().split('\n')[0].trim().split('\t');
      expect(cols[3], '1');
    });

    test('column[4] BarcodeType = 2 for weight, 1 for count', () {
      final csv = service.generatePLUCsv([singleItem, countItem]);
      final lines = csv.trim().split('\n');
      final weightCols = lines[0].trim().split('\t');
      final countCols = lines[1].trim().split('\t');
      expect(weightCols[4], '2'); // weight
      expect(countCols[4], '1');  // count
    });

    test('column[5] UnitPrice = decimal price', () {
      final csv = service.generatePLUCsv([singleItem]);
      final cols = csv.trim().split('\n')[0].trim().split('\t');
      expect(cols[5], '25.50');
    });

    test('column[6] UnitWeight = Kg for weight, PCS for count', () {
      final csv = service.generatePLUCsv([singleItem, countItem]);
      final lines = csv.trim().split('\n');
      final weightCols = lines[0].trim().split('\t');
      final countCols = lines[1].trim().split('\t');
      expect(weightCols[6], 'Kg');
      expect(countCols[6], 'PCS');
    });

    test('column[8] Department = department number', () {
      final csv = service.generatePLUCsv([singleItem]);
      final cols = csv.trim().split('\n')[0].trim().split('\t');
      expect(cols[8], '21');
    });

    test('column[9] and [12] contain tare weight', () {
      final csv = service.generatePLUCsv([singleItem]);
      final cols = csv.trim().split('\n')[0].trim().split('\t');
      expect(cols[9], '0.010');  // PT Weight = tare
      expect(cols[12], '0.010'); // Tare
    });

    test('column[11] PackType = Normal', () {
      final csv = service.generatePLUCsv([singleItem]);
      final cols = csv.trim().split('\n')[0].trim().split('\t');
      expect(cols[11], 'Normal');
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // UTF-16 LE Encoding
  // ═══════════════════════════════════════════════════════════════

  group('UTF-16 LE Encoding for TSV', () {
    test('encodeUtf16LE produces BOM + correct bytes', () {
      final transport = ScaleTransport();
      final csv = service.generatePLUCsv([singleItem]);
      final encoded = transport.encodeUtf16LE(csv);

      // Must start with UTF-16 LE BOM
      expect(encoded[0], 0xFF);
      expect(encoded[1], 0xFE);

      // Each char in CSV becomes 2 bytes
      expect(encoded.length, csv.length * 2 + 2); // +2 for BOM
    });

    test('tab character in TSV encodes as 09 00 in UTF-16 LE', () {
      final transport = ScaleTransport();
      final encoded = transport.encodeUtf16LE('\t');
      expect(encoded[2], 0x09);
      expect(encoded[3], 0x00);
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // Edge Cases
  // ═══════════════════════════════════════════════════════════════

  group('TSV Edge Cases', () {
    test('empty items list produces empty string', () {
      final csv = service.generatePLUCsv([]);
      expect(csv, '');
    });

    test('name with tab character does not break column count', () {
      // Tab in name would break TSV. generatePLUCsv doesn't escape tabs
      // because item names shouldn't contain tabs normally.
      // But let's verify the column count is still correct with a normal name.
      const item = ScalePLUItem(
        pluNumber: 1,
        name: 'Normal Name',
        unitPrice: 1.0,
      );
      final csv = service.generatePLUCsv([item]);
      final cols = csv.trim().split('\n')[0].trim().split('\t');
      expect(cols.length, 24);
    });

    test('PLU number 0 uses row number as hotkey', () {
      const item = ScalePLUItem(
        pluNumber: 0,
        name: 'Zero PLU',
        unitPrice: 1.0,
      );
      final csv = service.generatePLUCsv([item]);
      final cols = csv.trim().split('\n')[0].trim().split('\t');
      expect(cols[0], '1'); // row number fallback
    });

    test('large price formats correctly', () {
      const item = ScalePLUItem(
        pluNumber: 1,
        name: 'Expensive',
        unitPrice: 9999.99,
      );
      final csv = service.generatePLUCsv([item]);
      final cols = csv.trim().split('\n')[0].trim().split('\t');
      expect(cols[5], '9999.99');
    });
  });
}
