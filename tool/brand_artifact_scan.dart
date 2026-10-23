// Brand artifact scanner — pure Dart (no Flutter), so a build script can run it
// right after `flutter build windows` without starting another Flutter tool
// (a `flutter test` there crashes on the already-copied native-assets
// sqlite3.dll). Used by:
//   * test/structural/brand_artifact_guard_test.dart (policy + assertions)
//   * build_picpos.bat step 5c:  dart tool\brand_artifact_scan.dart <bundleDir>
//
// POLICY (owner requirement 2026-10-23: PicPos only). Forbidden, case-
// insensitive: the token `ural` at the START of a word (so "structural",
// "natural", "plural" are fine; "Ural", "UralCash", "URAL-ERP",
// "ural_api_token" are not), `monexia`, and the Arabic spellings of the other
// brand. EXCEPTIONS (exact, each with a reason; the list must only shrink):
//   * `ural_erp` — the Dart package name (library URIs in the AOT snapshot);
//     internal only, until the mechanical rename to `picpos_erp` (BRAND-006).
//   * brandDeferredCryptoLiterals — crypto salts / secure-storage key names.
//     Renaming invalidates sessions or the invoice hash chain, or makes an
//     existing encrypted DB unopenable without a migration (BRAND-005, B5).
//   * `data/icudtl.dat` "Uralsk.meta" — ICU (Flutter engine) time-zone data for
//     a Kazakh city; unrelated to the other product. File-scoped and exact.
//
// CLI: dart tool/brand_artifact_scan.dart [bundleDir]   (exit 1 on any hit)
//   env PICPOS_BUNDLE_DIR / PICPOS_REQUIRE_BUNDLE=1 as in the guard test.
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

// ── policy ─────────────────────────────────────────────────────────────────

/// Word-start `ural`, `monexia`, or the Arabic spellings. Used on TEXT.
final RegExp forbiddenBrandText = RegExp(
  r'(?<![a-z])ural|monexia|يورال|الأورال',
  caseSensitive: false,
);

/// Dart package name — internal only (BRAND-006, later mechanical rename).
const List<String> brandPackageNameExceptions = ['ural_erp'];

/// Deferred: crypto salts and secure-storage key names (BRAND-005 / step B5).
/// Exact strings; matched case-sensitively at the start of a hit.
const List<String> brandDeferredCryptoLiterals = [
  'UralCash-API-v1',
  'UralCash-Session-v1',
  'UralCash-ERP-Integrity-v1',
  'ural_api_session_hmac_v1',
  'ural_table_bill_hmac_v1',
  'ural_lan_install_secret_v1',
  'ural_lan_device_name',
  'ural_api_token',
  'ural_invoice_integrity_secret_v2',
  'ural_db_fallback_enc_key',
];

/// Third-party data that is not about the other product: ICU's time-zone
/// metazone list (Flutter engine data) names the Kazakh city "Uralsk".
/// File-scoped and exact on purpose.
const Map<String, List<String>> brandThirdPartyDataExceptions = {
  'data/icudtl.dat': ['Uralsk.meta'],
};

List<String> get brandAllowedTokens =>
    [...brandPackageNameExceptions, ...brandDeferredCryptoLiterals];

/// SHA-256 of other-brand images/icons. A file with one of these hashes must
/// never be in a PicPos bundle, whatever its name.
const Map<String, String> brandDenyHashes = {
  'dd23b570c16cd8998157505ef3a7ff99210971a12db6f207987039bbd4c25137':
      'other-brand company logo (logo.PNG)',
  'a1b1b26b2ed1ef14ad49f23a63b24b3b0f44ba087627af6a7b735c2134b71e22':
      'other-brand app icon (.ico)',
  '70e304c91f22e03a4f2f6015ca8979ee1f6ab387a08cfa97b4bdd2b47587827b':
      'other-brand installer wizard image (large)',
  '7be6ea87210f1014fd3e26f5f2e2aeda828dd5042ebacc98a2bb4dc3f148bfd7':
      'other-brand installer wizard image (small)',
};

// ── byte scanner (bundle files) ────────────────────────────────────────────

class BrandHit {
  BrandHit(this.file, this.offset, this.snippet, this.wide);
  final String file;
  final int offset;
  final String snippet;
  final bool wide;
  @override
  String toString() =>
      '$file @0x${offset.toRadixString(16)}${wide ? ' (utf16)' : ''}: "$snippet"';
}

bool _isLetter(int c) {
  final l = c | 0x20;
  return l >= 0x61 && l <= 0x7a;
}

bool _matchWord(Uint8List b, int i, List<int> w, int step) {
  final last = i + (w.length - 1) * step + (step - 1);
  if (last >= b.length) return false;
  for (var k = 0; k < w.length; k++) {
    final p = i + k * step;
    if ((b[p] | 0x20) != w[k]) return false;
    if (step == 2 && b[p + 1] != 0) return false;
  }
  return true;
}

String _snippet(Uint8List b, int i, bool wide) {
  final sb = StringBuffer();
  final step = wide ? 2 : 1;
  for (var k = 0; k < 48; k++) {
    final p = i + k * step;
    if (p >= b.length) break;
    final c = b[p];
    sb.writeCharCode((c >= 0x20 && c < 0x7f) ? c : 0x2e);
  }
  return sb.toString();
}

bool _isAllowedSnippet(String file, String snippet) =>
    brandAllowedTokens.any(snippet.startsWith) ||
    (brandThirdPartyDataExceptions[file] ?? const <String>[])
        .any(snippet.startsWith);

const List<List<int>> _arabicUtf8 = [
  // يورال
  [0xd9, 0x8a, 0xd9, 0x88, 0xd8, 0xb1, 0xd8, 0xa7, 0xd9, 0x84],
  // الأورال
  [0xd8, 0xa7, 0xd9, 0x84, 0xd8, 0xa3, 0xd9, 0x88, 0xd8, 0xb1, 0xd8, 0xa7,
    0xd9, 0x84],
];
const List<List<int>> _arabicUtf16 = [
  // يورال
  [0x4a, 0x06, 0x48, 0x06, 0x31, 0x06, 0x27, 0x06, 0x44, 0x06],
  // الأورال
  [0x27, 0x06, 0x44, 0x06, 0x23, 0x06, 0x48, 0x06, 0x31, 0x06, 0x27, 0x06,
    0x44, 0x06],
];

int _indexOfBytes(Uint8List b, List<int> pat, int from) {
  final n = b.length - pat.length;
  outer:
  for (var i = from; i <= n; i++) {
    if (b[i] != pat[0]) continue;
    for (var k = 1; k < pat.length; k++) {
      if (b[i + k] != pat[k]) continue outer;
    }
    return i;
  }
  return -1;
}

/// All forbidden hits in [b]; documented exceptions are returned separately.
({List<BrandHit> forbidden, List<BrandHit> allowed}) scanBrandBytes(
  String file,
  Uint8List b,
) {
  final forbidden = <BrandHit>[];
  final allowed = <BrandHit>[];
  const ural = [0x75, 0x72, 0x61, 0x6c]; // u r a l
  const monexia = [0x6d, 0x6f, 0x6e, 0x65, 0x78, 0x69, 0x61];

  void add(int i, bool wide, {required bool isUral}) {
    final s = _snippet(b, i, wide);
    // For `ural` at a word start, anything is forbidden unless allow-listed.
    (isUral && _isAllowedSnippet(file, s) ? allowed : forbidden)
        .add(BrandHit(file, i, s, wide));
  }

  for (var i = 0; i < b.length; i++) {
    final c = b[i] | 0x20;
    if (c == 0x75) {
      if (_matchWord(b, i, ural, 1) && (i == 0 || !_isLetter(b[i - 1]))) {
        add(i, false, isUral: true);
      }
      if (i + 7 < b.length &&
          b[i + 1] == 0 &&
          _matchWord(b, i, ural, 2) &&
          (i < 2 || b[i - 1] != 0 || !_isLetter(b[i - 2]))) {
        add(i, true, isUral: true);
      }
    } else if (c == 0x6d) {
      if (_matchWord(b, i, monexia, 1)) add(i, false, isUral: false);
      if (i + 1 < b.length && b[i + 1] == 0 && _matchWord(b, i, monexia, 2)) {
        add(i, true, isUral: false);
      }
    }
  }
  for (final pat in _arabicUtf8) {
    for (var i = _indexOfBytes(b, pat, 0);
        i >= 0;
        i = _indexOfBytes(b, pat, i + 1)) {
      forbidden.add(BrandHit(file, i, 'arabic-utf8', false));
    }
  }
  for (final pat in _arabicUtf16) {
    for (var i = _indexOfBytes(b, pat, 0);
        i >= 0;
        i = _indexOfBytes(b, pat, i + 1)) {
      forbidden.add(BrandHit(file, i, 'arabic-utf16', true));
    }
  }
  return (forbidden: forbidden, allowed: allowed);
}

// ── bundle discovery ───────────────────────────────────────────────────────

bool get requireBrandBundle =>
    Platform.environment['PICPOS_REQUIRE_BUNDLE'] == '1';

/// PicPos bundle directories to scan (those that actually hold PicPos.exe).
List<Directory> picposBundleDirs() {
  final forced = Platform.environment['PICPOS_BUNDLE_DIR'];
  final candidates = forced != null && forced.isNotEmpty
      ? [forced]
      : ['build/windows/x64/runner/Release', 'FlavorBuilds/PicPos'];
  return [
    for (final c in candidates)
      if (File('$c/PicPos.exe').existsSync()) Directory(c),
  ];
}

/// Scans every file of [dir] (names, SHA-256 deny-list, bytes narrow + wide).
/// Returns the problems; fills [allowedSummary] with documented exceptions.
List<String> scanBrandBundle(
  Directory dir, {
  Map<String, int>? allowedSummary,
}) {
  final problems = <String>[];
  for (final e in dir.listSync(recursive: true)) {
    if (e is! File) continue;
    final rel = e.path.substring(dir.path.length + 1).replaceAll('\\', '/');
    if (forbiddenBrandText.hasMatch(rel)) problems.add('file name: $rel');
    if (rel.endsWith('catalog_ar.json')) {
      problems.add('source map must not ship: $rel');
    }
    final bytes = e.readAsBytesSync();
    final hash = sha256.convert(bytes).toString();
    if (brandDenyHashes.containsKey(hash)) {
      problems.add('$rel is ${brandDenyHashes[hash]}');
    }
    final r = scanBrandBytes(rel, bytes);
    for (final h in r.forbidden) {
      problems.add(h.toString());
    }
    if (allowedSummary != null) {
      for (final h in r.allowed) {
        final token = h.snippet.split(RegExp(r'[^A-Za-z0-9_\-]')).first;
        final key = '$rel :: $token';
        allowedSummary[key] = (allowedSummary[key] ?? 0) + 1;
      }
    }
  }
  return problems;
}

void main(List<String> args) {
  final dirs = args.isNotEmpty ? [Directory(args.first)] : picposBundleDirs();
  if (dirs.isEmpty || !dirs.first.existsSync()) {
    stderr.writeln('brand scan: no PicPos bundle found '
        '(expected <dir>/PicPos.exe).');
    exit(requireBrandBundle || args.isNotEmpty ? 1 : 0);
  }
  var failed = false;
  for (final dir in dirs) {
    final allowed = <String, int>{};
    final problems = scanBrandBundle(dir, allowedSummary: allowed);
    stdout.writeln('brand scan: ${dir.path}: '
        '${problems.isEmpty ? 'CLEAN' : '${problems.length} PROBLEM(S)'}; '
        'documented exceptions: $allowed');
    for (final p in problems.take(60)) {
      stdout.writeln('  FORBIDDEN  $p');
    }
    if (problems.isNotEmpty) failed = true;
  }
  exit(failed ? 1 : 0);
}
