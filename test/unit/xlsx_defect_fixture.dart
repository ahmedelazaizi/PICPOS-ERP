import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:excel/excel.dart';

/// Built-in accounting format re-declared as a custom numFmt — exactly what
/// real Excel writes in the owner's products_520.xlsx.
const kNumFmt43 =
    '<numFmts count="1"><numFmt numFmtId="43" formatCode="_(* #,##0.00_);'
    '_(* \\(#,##0.00\\);_(* &quot;-&quot;??_);_(@_)"/></numFmts>';

/// Builds an xlsx with [rows] on one sheet, then injects [numFmts] as the
/// first child of `<styleSheet>` in xl/styles.xml.
Uint8List buildXlsx(List<List<Object?>> rows, {String numFmts = kNumFmt43}) {
  final excel = Excel.createExcel();
  final sheet = excel[excel.getDefaultSheet()!];
  for (var r = 0; r < rows.length; r++) {
    for (var c = 0; c < rows[r].length; c++) {
      final v = rows[r][c];
      final cell = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r),
      );
      if (v is int) {
        cell.value = IntCellValue(v);
      } else if (v is double) {
        cell.value = DoubleCellValue(v);
      } else if (v != null) {
        cell.value = TextCellValue(v.toString());
      }
    }
  }
  return injectNumFmts(Uint8List.fromList(excel.save()!), numFmts);
}

/// Inserts [numFmts] right after the `<styleSheet ...>` open tag.
Uint8List injectNumFmts(Uint8List xlsx, String numFmts) {
  final src = ZipDecoder().decodeBytes(xlsx);
  final out = Archive();
  for (final f in src.files) {
    var data = f.content as List<int>;
    if (f.name == 'xl/styles.xml') {
      final xml = utf8.decode(data);
      final i = xml.indexOf('<styleSheet');
      final end = xml.indexOf('>', i) + 1;
      data = utf8.encode(xml.substring(0, end) + numFmts + xml.substring(end));
    }
    out.addFile(ArchiveFile(f.name, data.length, data));
  }
  return Uint8List.fromList(ZipEncoder().encode(out)!);
}

String readStylesXml(Uint8List xlsx) => utf8.decode(
  ZipDecoder().decodeBytes(xlsx).findFile('xl/styles.xml')!.content
      as List<int>,
);
