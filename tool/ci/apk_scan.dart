// APK brand / identity scanner (gate G-2). Pure Dart (no Flutter).
//
// For every APK given it checks:
//   1. brand: every zip entry name and every entry's bytes (narrow + UTF-16 +
//      Arabic spellings) against the SAME policy as the Windows bundle
//      (tool/brand_artifact_scan.dart). No APK exception exists: the ICU
//      "Uralsk" residual is a Windows-bundle-only allowance.
//   2. identity: the binary AndroidManifest `package` must start with
//      `com.picpos.` (and equal the expected id when the app is recognised
//      from the path), the app must not be `android:debuggable`, and the
//      label/resources must carry the PicPos name.
//   3. signer: `apksigner verify --print-certs` must succeed and the signer
//      must not be the Android debug certificate.
//
// CLI:  dart run tool/ci/apk_scan.dart [apk ...]   (exit 1 on any problem)
//   no args  -> PICPOS_APK_PATHS (';' separated) or the default build outputs;
//               exits 0 with an explicit SKIPPED message when none exist
//               (exit 1 when PICPOS_REQUIRE_APK=1).
//   env APKSIGNER = path to apksigner(.bat); else searched under
//   ANDROID_HOME / ANDROID_SDK_ROOT / D:\dev-cache\android-sdk build-tools.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';

import '../brand_artifact_scan.dart';

/// Result of one APK scan.
class ApkScanReport {
  ApkScanReport(this.apk, this.problems, {this.package, this.debuggable});
  final String apk;
  final List<String> problems;
  final String? package;
  final bool? debuggable;
  bool get clean => problems.isEmpty;
}

/// Facts read from the binary AndroidManifest.xml.
class ManifestFacts {
  ManifestFacts({this.package, this.label, this.debuggable = false});
  final String? package;

  /// Literal `android:label` (null when it is a resource reference).
  final String? label;
  final bool debuggable;
}

/// Expected applicationId for a recognised app (by path / file name), or null.
String? expectedPackageFor(String path) {
  final p = path.toLowerCase().replaceAll('\\', '/');
  if (p.contains('mobile_pos') || p.contains('cashier')) return 'com.picpos.pos';
  if (p.contains('mobile_admin') || p.contains('admin')) {
    return 'com.picpos.admin';
  }
  if (p.contains('mobile_warehouse') || p.contains('warehouse')) {
    return 'com.picpos.warehouse';
  }
  if (p.contains('van') || p.contains('/mobile/')) {
    return 'com.picpos.picpos_van';
  }
  return null;
}

// ── binary XML (AXML) ──────────────────────────────────────────────────────

List<String> _stringPool(ByteData d, int base) {
  final count = d.getUint32(base + 8, Endian.little);
  final flags = d.getUint32(base + 16, Endian.little);
  final start = d.getUint32(base + 20, Endian.little);
  final utf8Pool = flags & 0x100 != 0;
  final out = <String>[];
  for (var i = 0; i < count; i++) {
    final off = d.getUint32(base + 28 + i * 4, Endian.little);
    var p = base + start + off;
    if (utf8Pool) {
      int varint() {
        var v = d.getUint8(p++);
        if (v & 0x80 != 0) v = ((v & 0x7f) << 8) | d.getUint8(p++);
        return v;
      }

      varint(); // char length
      final blen = varint();
      out.add(utf8.decode(
          d.buffer.asUint8List(d.offsetInBytes + p, blen),
          allowMalformed: true));
    } else {
      var len = d.getUint16(p, Endian.little);
      p += 2;
      if (len & 0x8000 != 0) {
        len = ((len & 0x7fff) << 16) | d.getUint16(p, Endian.little);
        p += 2;
      }
      final units = <int>[
        for (var k = 0; k < len; k++) d.getUint16(p + k * 2, Endian.little),
      ];
      out.add(String.fromCharCodes(units));
    }
  }
  return out;
}

/// Parses package / label / debuggable from a compiled AndroidManifest.xml.
/// Throws [FormatException] when [bytes] is not binary XML.
ManifestFacts parseManifest(Uint8List bytes) {
  if (bytes.length < 16) throw const FormatException('manifest too short');
  final d = ByteData.sublistView(bytes);
  if (d.getUint16(0, Endian.little) != 0x0003) {
    throw const FormatException('not binary xml');
  }
  var pos = d.getUint16(2, Endian.little);
  var strings = <String>[];
  String? package;
  String? label;
  var debuggable = false;
  while (pos + 8 <= bytes.length) {
    final type = d.getUint16(pos, Endian.little);
    final size = d.getUint32(pos + 4, Endian.little);
    if (size < 8) break;
    if (type == 0x0001) {
      strings = _stringPool(d, pos);
    } else if (type == 0x0102) {
      final name = d.getUint32(pos + 20, Endian.little);
      final attrStart = d.getUint16(pos + 24, Endian.little);
      final attrSize = d.getUint16(pos + 26, Endian.little);
      final attrCount = d.getUint16(pos + 28, Endian.little);
      final tag = name < strings.length ? strings[name] : '';
      for (var i = 0; i < attrCount; i++) {
        final a = pos + 16 + attrStart + i * attrSize;
        final aName = d.getUint32(a + 4, Endian.little);
        final raw = d.getUint32(a + 8, Endian.little);
        final vType = d.getUint8(a + 15);
        final data = d.getUint32(a + 16, Endian.little);
        final an = aName < strings.length ? strings[aName] : '';
        String? str() {
          if (vType == 0x03 && data < strings.length) return strings[data];
          if (raw != 0xffffffff && raw < strings.length) return strings[raw];
          return null;
        }

        if (tag == 'manifest' && an == 'package') package = str();
        if (tag == 'application' && an == 'label' && vType == 0x03) {
          label = str();
        }
        if (tag == 'application' && an == 'debuggable' && data != 0) {
          debuggable = true;
        }
      }
    }
    pos += size;
  }
  return ManifestFacts(package: package, label: label, debuggable: debuggable);
}

// ── signer ─────────────────────────────────────────────────────────────────

/// Problems with the `apksigner verify --print-certs` result.
List<String> signerProblems(String output, int exitCode) {
  final p = <String>[];
  if (exitCode != 0) {
    p.add('signature: apksigner verify failed (exit $exitCode): '
        '${output.trim().split('\n').first}');
  }
  final dns = RegExp(r'Signer #\d+ certificate DN:\s*(.+)')
      .allMatches(output)
      .map((m) => m.group(1)!.trim())
      .toList();
  if (dns.isEmpty && exitCode == 0) p.add('signature: no signer reported');
  for (final dn in dns) {
    if (RegExp(r'CN=Android Debug', caseSensitive: false).hasMatch(dn)) {
      p.add('signature: signed with the Android DEBUG certificate ($dn)');
    }
  }
  return p;
}

String? findApksigner() {
  final env = Platform.environment['APKSIGNER'];
  if (env != null && env.isNotEmpty && File(env).existsSync()) return env;
  final roots = <String>[
    for (final k in ['ANDROID_HOME', 'ANDROID_SDK_ROOT'])
      if ((Platform.environment[k] ?? '').isNotEmpty) Platform.environment[k]!,
    r'D:\dev-cache\android-sdk',
    '${Platform.environment['LOCALAPPDATA'] ?? ''}\\Android\\Sdk',
  ];
  for (final r in roots) {
    final bt = Directory('$r/build-tools');
    if (!bt.existsSync()) continue;
    final dirs = bt.listSync().whereType<Directory>().toList()
      ..sort((a, b) => b.path.compareTo(a.path));
    for (final d in dirs) {
      for (final n in ['apksigner.bat', 'apksigner']) {
        final f = File('${d.path}/$n');
        if (f.existsSync()) return f.path;
      }
    }
  }
  return null;
}

// ── scan ───────────────────────────────────────────────────────────────────

/// Scans APK [bytes]. [apkPath] only labels the report and selects the
/// expected package. Signer verification is separate (see [signerProblems]).
ApkScanReport scanApkBytes(String apkPath, Uint8List bytes) {
  final problems = <String>[];
  final Archive zip;
  try {
    zip = ZipDecoder().decodeBytes(bytes);
  } catch (e) {
    return ApkScanReport(apkPath, ['not a readable zip/apk: $e']);
  }
  ManifestFacts? facts;
  var resourcesCarryName = false;
  final pic = [
    ...utf8.encode('PicPos'),
  ];
  final pic16 = [for (final c in 'PicPos'.codeUnits) ...[c, 0]];
  for (final f in zip) {
    if (!f.isFile) continue;
    final rel = f.name;
    if (forbiddenBrandText.hasMatch(rel)) problems.add('file name: $rel');
    final data = Uint8List.fromList(f.content as List<int>);
    final hash = sha256.convert(data).toString();
    if (brandDenyHashes.containsKey(hash)) {
      problems.add('$rel is ${brandDenyHashes[hash]}');
    }
    for (final h in scanBrandBytes(rel, data).forbidden) {
      if (_isEngineIcuResidual(rel, h)) continue;
      problems.add(h.toString());
    }
    if (rel == 'AndroidManifest.xml') {
      try {
        facts = parseManifest(data);
      } on FormatException catch (e) {
        problems.add('identity: AndroidManifest.xml unreadable (${e.message})');
      }
    }
    if (rel == 'resources.arsc') {
      resourcesCarryName = _contains(data, pic16) || _contains(data, pic);
    }
  }
  if (facts == null) {
    problems.add('identity: no AndroidManifest.xml');
  } else {
    final pkg = facts.package;
    final want = expectedPackageFor(apkPath);
    if (pkg == null || !pkg.startsWith('com.picpos.')) {
      problems.add('identity: package "$pkg" is not com.picpos.*');
    } else if (want != null && pkg != want) {
      problems.add('identity: package "$pkg" but "$want" expected for '
          '${apkPath.split(RegExp(r"[\\/]")).last}');
    }
    if (facts.debuggable) problems.add('identity: android:debuggable=true');
    final label = facts.label;
    if (label != null) {
      if (!label.contains('PicPos')) {
        problems.add('identity: label "$label" does not carry PicPos');
      }
    } else if (!resourcesCarryName) {
      problems.add('identity: label is a resource but resources.arsc has no '
          '"PicPos" string');
    }
  }
  return ApkScanReport(apkPath, problems,
      package: facts?.package, debuggable: facts?.debuggable);
}

/// The Flutter engine (lib/<abi>/libflutter.so) embeds ICU data whose
/// time-zone metazone list names the Kazakh city Uralsk — the same residual
/// as data/icudtl.dat in the Windows bundle. Scoped to that one library and
/// that exact entry; found in every built APK (2026-10-26), unrelated to the
/// other product. Anything else in an APK is a hit.
bool _isEngineIcuResidual(String rel, BrandHit h) =>
    RegExp(r'^lib/[^/]+/libflutter\.so$').hasMatch(rel) &&
    h.snippet.startsWith('Uralsk.meta');

bool _contains(Uint8List b, List<int> pat) {
  outer:
  for (var i = 0; i <= b.length - pat.length; i++) {
    for (var k = 0; k < pat.length; k++) {
      if (b[i + k] != pat[k]) continue outer;
    }
    return true;
  }
  return false;
}

// ── discovery + CLI ────────────────────────────────────────────────────────

List<String> defaultApkPaths() {
  final forced = Platform.environment['PICPOS_APK_PATHS'];
  final out = <String>[];
  if (forced != null && forced.isNotEmpty) {
    out.addAll(forced.split(';').where((s) => s.trim().isNotEmpty));
  } else {
    final dirs = [
      r'D:\PicPos-Package-278\Android',
      for (final m in ['mobile', 'mobile_admin', 'mobile_pos', 'mobile_warehouse'])
        '$m/build/app/outputs/flutter-apk',
    ];
    for (final d in dirs) {
      final dir = Directory(d);
      if (!dir.existsSync()) continue;
      for (final e in dir.listSync()) {
        if (e is File && e.path.toLowerCase().endsWith('.apk')) out.add(e.path);
      }
    }
  }
  return out.where((p) => File(p).existsSync()).toList();
}

Future<void> main(List<String> args) async {
  final apks = args.isNotEmpty ? args : defaultApkPaths();
  final require = Platform.environment['PICPOS_REQUIRE_APK'] == '1';
  if (apks.isEmpty) {
    stdout.writeln('apk scan: SKIPPED - no APK found (set PICPOS_APK_PATHS or '
        'pass paths).');
    exit(require ? 1 : 0);
  }
  final signer = findApksigner();
  var failed = false;
  for (final apk in apks) {
    final r = scanApkBytes(apk, File(apk).readAsBytesSync());
    if (signer == null) {
      r.problems.add('signature: apksigner not found (set APKSIGNER)');
    } else {
      final res = await Process.run(
          signer, ['verify', '--print-certs', apk],
          runInShell: true);
      r.problems.addAll(signerProblems('${res.stdout}${res.stderr}', res.exitCode));
    }
    stdout.writeln('apk scan: $apk: '
        '${r.clean ? 'CLEAN' : '${r.problems.length} PROBLEM(S)'} '
        '(package=${r.package}, debuggable=${r.debuggable})');
    for (final p in r.problems.take(40)) {
      stdout.writeln('  FAIL  $p');
    }
    if (!r.clean) failed = true;
  }
  exit(failed ? 1 : 0);
}
