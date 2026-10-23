// SEC-016 (audit 2026-10-23): xlsx input limits against zip bombs / huge files.
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/services/xlsx_sanitizer.dart';

Uint8List _zip(int entries, {int bytesEach = 10}) {
  final a = Archive();
  for (var i = 0; i < entries; i++) {
    final data = List<int>.filled(bytesEach, 65);
    a.addFile(ArchiveFile('f$i.txt', data.length, data));
  }
  return Uint8List.fromList(ZipEncoder().encode(a)!);
}

void main() {
  test('input over the byte limit is refused', () {
    expect(sanitizeXlsxBytes(Uint8List(2048), maxBytes: 1024), isNull);
  });

  test('too many entries is refused', () {
    expect(sanitizeXlsxBytes(_zip(30), maxEntries: 10), isNull);
  });

  test('declared uncompressed size over the limit is refused', () {
    expect(
        sanitizeXlsxBytes(_zip(5, bytesEach: 1000), maxUncompressed: 2000),
        isNull);
  });

  test('a normal small archive passes through', () {
    expect(sanitizeXlsxBytes(_zip(3)), isNotNull);
  });

  test('null stays null', () => expect(sanitizeXlsxBytes(null), isNull));
}