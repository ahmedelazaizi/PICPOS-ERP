// Gate G-2: APK brand / identity / signer scanner (tool/ci/apk_scan.dart),
// driven with synthetic zip + binary-manifest fixtures.
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../tool/ci/apk_scan.dart';

// The forbidden brand word is assembled at runtime so this file stays clean.
const String _bad = 'U${'ra'}l${'Cash'}';

Uint8List _axml({
  required String package,
  String? label,
  bool debuggable = false,
}) {
  final strings = <String>[
    'package',
    'label',
    'debuggable',
    'manifest',
    'application',
    package,
    ?label,
  ];
  final pool = BytesBuilder();
  final body = BytesBuilder();
  final offsets = <int>[];
  for (final s in strings) {
    offsets.add(body.length);
    final b = ByteData(2)..setUint16(0, s.length, Endian.little);
    body.add(b.buffer.asUint8List());
    for (final c in s.codeUnits) {
      final u = ByteData(2)..setUint16(0, c, Endian.little);
      body.add(u.buffer.asUint8List());
    }
    body.add([0, 0]);
  }
  while (body.length % 4 != 0) {
    body.addByte(0);
  }
  final stringsStart = 28 + strings.length * 4;
  final poolSize = stringsStart + body.length;
  final h = ByteData(28)
    ..setUint16(0, 1, Endian.little)
    ..setUint16(2, 28, Endian.little)
    ..setUint32(4, poolSize, Endian.little)
    ..setUint32(8, strings.length, Endian.little)
    ..setUint32(16, 0, Endian.little)
    ..setUint32(20, stringsStart, Endian.little);
  pool.add(h.buffer.asUint8List());
  for (final o in offsets) {
    final b = ByteData(4)..setUint32(0, o, Endian.little);
    pool.add(b.buffer.asUint8List());
  }
  pool.add(body.toBytes());

  Uint8List element(int nameIdx, List<List<int>> attrs) {
    // attr = [nameIdx, rawIdx(-1 none), type, data]
    final size = 36 + attrs.length * 20;
    final d = ByteData(size)
      ..setUint16(0, 0x0102, Endian.little)
      ..setUint16(2, 16, Endian.little)
      ..setUint32(4, size, Endian.little)
      ..setUint32(12, 0xffffffff, Endian.little)
      ..setUint32(16, 0xffffffff, Endian.little)
      ..setUint32(20, nameIdx, Endian.little)
      ..setUint16(24, 20, Endian.little)
      ..setUint16(26, 20, Endian.little)
      ..setUint16(28, attrs.length, Endian.little);
    for (var i = 0; i < attrs.length; i++) {
      final a = 36 + i * 20;
      d
        ..setUint32(a, 0xffffffff, Endian.little)
        ..setUint32(a + 4, attrs[i][0], Endian.little)
        ..setUint32(a + 8, attrs[i][1], Endian.little)
        ..setUint16(a + 12, 8, Endian.little)
        ..setUint8(a + 15, attrs[i][2])
        ..setUint32(a + 16, attrs[i][3], Endian.little);
    }
    return d.buffer.asUint8List();
  }

  final manifest = element(3, [
    [0, 5, 0x03, 5],
  ]);
  final app = element(4, [
    if (label != null) [1, 6, 0x03, 6] else [1, 0xffffffff, 0x01, 0x7f010000],
    if (debuggable) [2, 0xffffffff, 0x12, 0xffffffff],
  ]);
  final total = 8 + pool.length + manifest.length + app.length;
  final head = ByteData(8)
    ..setUint16(0, 3, Endian.little)
    ..setUint16(2, 8, Endian.little)
    ..setUint32(4, total, Endian.little);
  return Uint8List.fromList(
      [...head.buffer.asUint8List(), ...pool.toBytes(), ...manifest, ...app]);
}

Uint8List _apk(Map<String, List<int>> files) {
  final a = Archive();
  files.forEach((n, c) => a.addFile(ArchiveFile(n, c.length, c)));
  return Uint8List.fromList(ZipEncoder().encode(a)!);
}

Map<String, List<int>> _good({String pkg = 'com.picpos.pos'}) => {
      'AndroidManifest.xml': _axml(package: pkg, label: 'PicPos Cashier'),
      'classes.dex': utf8.encode('dex PicPos clean'),
      'resources.arsc': utf8.encode('PicPos'),
    };

void main() {
  test('parseManifest reads package, literal label and debuggable', () {
    final f = parseManifest(
        _axml(package: 'com.picpos.pos', label: 'PicPos', debuggable: true));
    expect(f.package, 'com.picpos.pos');
    expect(f.label, 'PicPos');
    expect(f.debuggable, isTrue);
  });

  test('a clean PicPos APK passes', () {
    final r = scanApkBytes('PicPos-Cashier-0.1.0.apk', _apk(_good()));
    expect(r.problems, isEmpty);
    expect(r.package, 'com.picpos.pos');
  });

  test('forbidden brand text in dex, asset, name and UTF-16 is reported', () {
    final files = _good()
      ..['classes.dex'] = utf8.encode('x $_bad y')
      ..['assets/${_bad.toLowerCase()}.json'] = utf8.encode('{}')
      ..['lib/arm64-v8a/libx.so'] = [
        for (final c in _bad.codeUnits) ...[c, 0],
      ];
    final r = scanApkBytes('PicPos-Cashier-0.1.0.apk', _apk(files));
    expect(r.problems.where((p) => p.contains('classes.dex')), isNotEmpty);
    expect(r.problems.where((p) => p.startsWith('file name:')), isNotEmpty);
    expect(r.problems.where((p) => p.contains('libx.so')), isNotEmpty);
  });

  test('words that merely contain the letters are not brand hits', () {
    final files = _good()..['classes.dex'] = utf8.encode('structural natural');
    expect(scanApkBytes('PicPos-Cashier-0.1.0.apk', _apk(files)).problems,
        isEmpty);
  });

  test('ICU "Uralsk" is NOT allowed in an APK', () {
    final files = _good()
      ..['assets/icudtl.dat'] = utf8.encode('zone U${'ra'}lsk.meta');
    expect(scanApkBytes('x.apk', _apk(files)).problems, isNotEmpty);
  });

  test('engine ICU Uralsk is allowed ONLY inside lib/<abi>/libflutter.so', () {
    final zone = utf8.encode('zone U${'ra'}lsk.meta:Uruguay.meta');
    final ok = _good()..['lib/arm64-v8a/libflutter.so'] = zone;
    expect(scanApkBytes('x.apk', _apk(ok)).problems, isEmpty);
    final bad = _good()..['lib/arm64-v8a/libother.so'] = zone;
    expect(scanApkBytes('x.apk', _apk(bad)).problems, isNotEmpty);
    final mixed = _good()
      ..['lib/arm64-v8a/libflutter.so'] = utf8.encode('x $_bad y');
    expect(scanApkBytes('x.apk', _apk(mixed)).problems, isNotEmpty);
  });

  test('wrong package, non-picpos package and debuggable are reported', () {
    var r = scanApkBytes(
        'PicPos-Cashier-0.1.0.apk', _apk(_good(pkg: 'com.picpos.admin')));
    expect(r.problems.single, contains('com.picpos.pos'));
    r = scanApkBytes('a.apk', _apk(_good(pkg: 'com.example.app')));
    expect(r.problems.single, contains('not com.picpos'));
    final dbg = _good()
      ..['AndroidManifest.xml'] =
          _axml(package: 'com.picpos.pos', label: 'PicPos', debuggable: true);
    r = scanApkBytes('PicPos-Cashier-0.1.0.apk', _apk(dbg));
    expect(r.problems.single, contains('debuggable'));
  });

  test('label from resources needs a PicPos string in resources.arsc', () {
    final noName = _good()
      ..['AndroidManifest.xml'] = _axml(package: 'com.picpos.pos')
      ..['resources.arsc'] = utf8.encode('other');
    expect(scanApkBytes('PicPos-Cashier-0.1.0.apk', _apk(noName)).problems,
        isNotEmpty);
    final ok = _good()..['AndroidManifest.xml'] = _axml(package: 'com.picpos.pos');
    expect(scanApkBytes('PicPos-Cashier-0.1.0.apk', _apk(ok)).problems, isEmpty);
  });

  test('a missing manifest or a non-zip is a problem', () {
    expect(scanApkBytes('x.apk', _apk({'a.txt': [1]})).problems,
        contains('identity: no AndroidManifest.xml'));
    expect(scanApkBytes('x.apk', Uint8List.fromList([1, 2, 3])).problems,
        isNotEmpty);
  });

  test('expectedPackageFor maps known apps', () {
    expect(expectedPackageFor(r'mobile_pos\build\app-release.apk'),
        'com.picpos.pos');
    expect(expectedPackageFor('PicPos-Warehouse-0.1.0.apk'),
        'com.picpos.warehouse');
    expect(expectedPackageFor('PicPos-Admin-0.1.0.apk'), 'com.picpos.admin');
    expect(expectedPackageFor('PicPos-Van-0.1.0.apk'),
        'com.picpos.picpos_van');
    expect(expectedPackageFor('mystery.apk'), isNull);
  });

  group('signerProblems', () {
    const release = 'Signer #1 certificate DN: CN=PicPos Release, O=PicPos\n';
    const debug =
        'Signer #1 certificate DN: C=US, O=Android, CN=Android Debug\n';
    test('release signer passes', () {
      expect(signerProblems(release, 0), isEmpty);
    });
    test('the Android debug certificate fails', () {
      expect(signerProblems(debug, 0).single, contains('DEBUG'));
    });
    test('unverifiable / unsigned fails', () {
      expect(signerProblems('Failed to parse APK', 1), isNotEmpty);
      expect(signerProblems('', 0), isNotEmpty);
    });
  });
}
