import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/domain/printing/template_document.dart';
import 'package:picpos_erp/services/printing/layout_engine.dart';
import 'package:picpos_erp/services/printing/paint_plan.dart';

PositionedPage _pageWithAmountCell(
  double widthMm,
  double cellWidthMm,
  String amount,
) => PositionedPage(
  pageNumber: 1,
  pageCount: 1,
  widthMm: widthMm,
  heightMm: 100,
  elements: const [],
  tables: [
    PositionedTable(
      xMm: 0,
      yMm: 10,
      wMm: widthMm,
      headerCells: const [],
      headerHeightMm: 0,
      bilingualHeaders: false,
      headerFontSize: 8,
      cellFontSize: 8,
      rows: [
        PositionedRow(
          sourceIndex: 0,
          yMm: 10,
          heightMm: 6,
          cells: [
            PositionedCell(
              columnKey: 'total',
              xMm: 0,
              wMm: cellWidthMm,
              align: ColumnAlign.end,
              text: amount,
            ),
          ],
        ),
      ],
    ),
  ],
);

PositionedPage _pageForNarrowItem(List<String> item) {
  final document = TemplateDocument(
    paper: const PaperSpec.continuous(widthMm: 50, margins: MarginsMm.all(2)),
    bands: const [
      TemplateBand(id: BandId.details, heightMm: 80, growsWithData: true),
    ],
    table: const TableSpec(
      fontSize: 8,
      headerFontSize: 8,
      columns: [
        TableColumn(key: 'name', labelAr: 'الصنف', align: ColumnAlign.start),
        TableColumn(key: 'quantity', labelAr: 'الكمية'),
        TableColumn(key: 'price', labelAr: 'السعر'),
        TableColumn(key: 'total', labelAr: 'الإجمالي'),
      ],
    ),
  );
  return LayoutEngine.paginate(document: document, rows: [item]).single;
}

void main() {
  test(
    'narrow amounts retain readable type and truncate only at the hard limit',
    () {
      final narrow = planPage(_pageWithAmountCell(50, 7, '12345678')).single;
      expect(narrow.fontSize, greaterThanOrEqualTo(7));
      expect(narrow.text.endsWith('...'), isTrue);
      final roomy = planPage(_pageWithAmountCell(50, 20, '12345678.00')).single;
      expect(roomy.fontSize, 8);
      expect(roomy.text, '12345678.00');
      final tenDigits = planPage(
        _pageWithAmountCell(50, 25, '1234567890.00'),
      ).single;
      expect(tenDigits.fontSize, greaterThanOrEqualTo(7));
      expect(tenDigits.text, '1234567890.00');
      final tenDigitWidthLimit = planPage(
        _pageWithAmountCell(50, 19.36, '1234567890.00'),
      ).single;
      expect(tenDigitWidthLimit.fontSize, greaterThanOrEqualTo(7));
      expect(tenDigitWidthLimit.text, '1234567890.00');
      expect(
        planPage(_pageWithAmountCell(52, 7, '12345678')).single.fontSize,
        greaterThanOrEqualTo(7),
      );
      expect(
        planPage(_pageWithAmountCell(52.1, 7, '12345678')).single.fontSize,
        8,
      );
      expect(
        planPage(_pageWithAmountCell(50, 7, '1234567')).single.fontSize,
        8,
      );
      expect(
        planPage(_pageWithAmountCell(50, 7, 'ABCD1234')).single.fontSize,
        8,
      );

      for (final pageWidth in [72.0, 140.0, 202.0]) {
        expect(
          planPage(
            _pageWithAmountCell(pageWidth, 7, '12345678'),
          ).single.fontSize,
          8,
        );
      }
    },
  );

  test('5- and 7-digit amounts use compact opposite-aligned item fields', () {
    for (final amount in ['27.50', '1234567.00']) {
      final table = _pageForNarrowItem([
        'صنف',
        '1.00',
        amount,
        amount,
      ]).tables.single;

      expect(table.headerHeightMm, 12);
      expect(table.headerCells.map((cell) => cell.text), [
        'الصنف',
        'الكمية × السعر',
        'الإجمالي',
      ]);
      expect(table.rows.single.heightMm, 15);
      expect(table.rows.single.cells.map((cell) => cell.text), [
        'صنف',
        '1.00 × $amount',
        amount,
      ]);
      expect(table.rows.single.cells.map((cell) => cell.wMm), [
        closeTo(46, 1e-6),
        closeTo(29.44, 1e-6),
        closeTo(16.56, 1e-6),
      ]);
      expect(table.rows.single.cells.map((cell) => cell.topOffsetMm), [
        0,
        9,
        9,
      ]);
      expect(table.rows.single.cells[1].align, ColumnAlign.start);
      expect(table.rows.single.cells.last.align, ColumnAlign.end);
      final numericOps = planPage(
        _pageForNarrowItem(['صنف', '1.00', amount, amount]),
      ).where((op) => op.kind == PaintKind.tableCell);
      expect(numericOps.every((op) => op.fontSize >= 7), isTrue);
      expect(
        numericOps.map((op) => op.text),
        containsAll(['1.00 × $amount', amount]),
      );
    }
  });

  test('long compact-row names truncate visibly within the name area', () {
    const longName =
        'اسم صنف طويل جداً لاختبار التفاف النص والحافة في قالب الفاتورة العربية والإنجليزية ٩٦ حرفاً';
    final row = _pageForNarrowItem([
      longName,
      '1.00',
      '27.50',
      '27.50',
    ]).tables.single.rows.single;

    expect(row.heightMm, 15);
    expect(row.cells.first.text.endsWith('...'), isTrue);
    expect(
      row.cells.first.text.runes.length,
      lessThan(longName.runes.length),
      reason: row.cells.first.text,
    );
    expect(row.cells[1].text, '1.00 × 27.50');
  });

  test('8- and 10-digit amounts use the stacked complete-value layout', () {
    for (final amount in ['12345678.00', '1234567890.00']) {
      final table = _pageForNarrowItem([
        'صنف',
        '1.00',
        amount,
        amount,
      ]).tables.single;

      expect(table.headerHeightMm, 18);
      expect(table.rows.single.heightMm, 21);
      expect(table.rows.single.cells.map((cell) => cell.wMm), [46, 46, 46]);
      expect(table.rows.single.cells[1].text, '1.00 × $amount');
      expect(table.rows.single.cells.last.text, amount);
      expect(table.rows.single.cells.map((cell) => cell.topOffsetMm), [
        0,
        9,
        15,
      ]);
      final planned = planPage(
        _pageForNarrowItem(['صنف', '1.00', amount, amount]),
      );
      final numericOps = planned.where((op) => op.kind == PaintKind.tableCell);
      expect(numericOps.every((op) => op.fontSize >= 7), isTrue);
      expect(numericOps.any((op) => op.text == amount), isTrue);
    }
  });
}
