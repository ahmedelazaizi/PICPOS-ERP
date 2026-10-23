import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/services/xlsx_sanitizer.dart';

import 'xlsx_defect_fixture.dart';

const _rows = <List<Object?>>[
  ['كود', 'اسم', 'سعر'],
  ['A1', 'صنف أول', 12.5],
  ['A2', 'صنف ثان', 3],
];

List<List<Object?>> _values(Uint8List bytes) {
  final excel = Excel.decodeBytes(bytes);
  final sheet = excel.tables[excel.tables.keys.first]!;
  return [
    for (final r in sheet.rows) [for (final c in r) c?.value?.toString()],
  ];
}

void main() {
  test('repro: raw bytes with numFmtId=43 make Excel.decodeBytes throw', () {
    final raw = buildXlsx(_rows);
    expect(
      () => Excel.decodeBytes(raw),
      throwsA(predicate((e) => e.toString().contains('164'))),
    );
  });

  test('sanitized bytes decode with identical cell values', () {
    final raw = buildXlsx(_rows);
    final fixed = sanitizeXlsxBytes(raw)!;
    final expected = _values(buildXlsx(_rows, numFmts: ''));
    expect(_values(fixed), expected);
    expect(_values(fixed)[1], ['A1', 'صنف أول', '12.5']);
    expect(readStylesXml(fixed), isNot(contains('numFmts')));
  });

  test('idempotent: second pass returns the same bytes', () {
    final once = sanitizeXlsxBytes(buildXlsx(_rows))!;
    final twice = sanitizeXlsxBytes(once)!;
    expect(identical(once, twice), isTrue);
  });

  test('custom ids >= 164 survive; only built-in ids are dropped', () {
    const mixed =
        '<numFmts count="3">'
        '<numFmt numFmtId="43" formatCode="x"/>'
        '<numFmt numFmtId="164" formatCode="0.000"/>'
        '<numFmt numFmtId="170" formatCode="yyyy&quot;/&quot;mm"/>'
        '</numFmts>';
    final fixed = sanitizeXlsxBytes(buildXlsx(_rows, numFmts: mixed))!;
    final styles = readStylesXml(fixed);
    expect(styles, contains('<numFmts count="2">'));
    expect(styles, contains('<numFmt numFmtId="164" formatCode="0.000"/>'));
    expect(
      styles,
      contains('<numFmt numFmtId="170" formatCode="yyyy&quot;/&quot;mm"/>'),
    );
    expect(styles, isNot(contains('numFmtId="43"')));
    expect(_values(fixed), _values(buildXlsx(_rows, numFmts: '')));
  });

  test('file needing no change is returned untouched (same instance)', () {
    final clean = buildXlsx(_rows, numFmts: '');
    expect(identical(sanitizeXlsxBytes(clean), clean), isTrue);
    final custom = buildXlsx(
      _rows,
      numFmts: '<numFmts count="1"><numFmt numFmtId="165" formatCode="0.0"/></numFmts>',
    );
    expect(identical(sanitizeXlsxBytes(custom), custom), isTrue);
  });

  test('garbage / non-zip / empty / null never throw and stay unchanged', () {
    final garbage = Uint8List.fromList(List.generate(300, (i) => (i * 7) % 256));
    expect(identical(sanitizeXlsxBytes(garbage), garbage), isTrue);
    final empty = Uint8List(0);
    expect(identical(sanitizeXlsxBytes(empty), empty), isTrue);
    expect(sanitizeXlsxBytes(null), isNull);
    final truncated = buildXlsx(_rows);
    final cut = Uint8List.sublistView(truncated, 0, truncated.length ~/ 2);
    expect(() => sanitizeXlsxBytes(cut), returnsNormally);
  });

  test('stripBuiltInNumFmts handles empty/self-closing blocks', () {
    expect(
      stripBuiltInNumFmts('<s><numFmts count="1"><numFmt numFmtId="9" formatCode="0%"/></numFmts><fonts/></s>'),
      '<s><fonts/></s>',
    );
    expect(stripBuiltInNumFmts('<s><fonts/></s>'), '<s><fonts/></s>');
  });
}
