// Brand artifact guard — "PicPos only" (owner requirement 2026-10-23):
//
//   Nothing that concerns PicPos may mention the other product — no files,
//   images, icons, strings, names, ids, installer text, shipped docs, build
//   outputs or metadata.
//
// Earlier guards only checked `Brand` constants and the exact file name
// `UralCash.exe`; the shipped `logo.PNG`, the i18n catalogs and string
// literals in `app.so` slipped through (axis-C BRAND-012). This guard checks
// the *artifacts*:
//
//   (a) the PicPos asset set + PicPos-visible sources (always runs);
//   (b) the built Windows bundle (`build/windows/x64/runner/Release` and/or
//       `FlavorBuilds/PicPos`) — every file name AND every file's bytes, as
//       narrow (Latin-1/UTF-8) and wide (UTF-16LE) text. Skipped when no
//       PicPos bundle exists, unless PICPOS_REQUIRE_BUNDLE=1 (CI/build script).
//
// The policy (forbidden words, the explicit exception list: the Dart package
// one ICU data entry (no package-name exception: the package is `picpos_erp`); the crypto/storage-literal list is now
// empty) and
// the scanner live in tool/brand_artifact_scan.dart so build_picpos.bat can run
// the same scan without starting a second Flutter tool.
//
// Run: flutter test test/structural/brand_artifact_guard_test.dart
// Env: PICPOS_BUNDLE_DIR=<dir>   scan exactly this bundle
//      PICPOS_REQUIRE_BUNDLE=1   fail (instead of skip) when no bundle found
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../tool/brand_artifact_scan.dart';

/// `lib/` files allowed to carry a forbidden word inside a STRING LITERAL.
/// Everything here is either behind a const `Brand.isPicPos` fork (tree-shaken
/// out of the PicPos binary — proven by the bundle scan below). The crypto
/// salts / storage keys that used to be listed here were migrated. A NEW file with such a literal fails this test.
const Map<String, String> _libLiteralAllowList = {
  'lib/core/config/brand.dart':
      'alternate-brand values behind `isPicPos ?` const forks',
  'lib/core/config/support_env.dart': 'const-folded env prefix fork',
  'lib/core/theme/app_theme.dart': 'designLanguage const fork',
  'lib/presentation/screens/setup_wizard_screen.dart':
      'welcome title const fork',
  'lib/services/log_writer_io.dart': 'log prefix const fork',
  'lib/data/database/daos/api_key_dao.dart': 'dead API-key prefix (no callers)',
};

// ── helpers ────────────────────────────────────────────────────────────────

String _norm(String p) => p.replaceAll('\\', '/');

String _sha256File(File f) => sha256.convert(f.readAsBytesSync()).toString();

String _readText(String path) => utf8.decode(
      File(path).readAsBytesSync(),
      allowMalformed: true,
    );

/// Hits of [forbiddenBrandText] in [text], each with a little context.
List<String> _textHits(String text) {
  return forbiddenBrandText.allMatches(text).map((m) {
    final end = (m.end + 24 < text.length) ? m.end + 24 : text.length;
    final start = m.start >= 12 ? m.start - 12 : 0;
    return text.substring(start, end).replaceAll(RegExp(r'\s+'), ' ');
  }).toList();
}

/// Strips `//` comments (crude: only when preceded by whitespace/line start)
/// and block comments.
String _stripDartComments(String src) {
  final noBlock = src.replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '');
  final out = StringBuffer();
  for (final line in noBlock.split('\n')) {
    if (line.trimLeft().startsWith('//')) continue;
    out.writeln(line.replaceFirst(RegExp(r'(^|\s)//.*$'), ''));
  }
  return out.toString();
}

final RegExp _dartString =
    RegExp(r'''(?:'(?:[^'\\\n]|\\.)*'|"(?:[^"\\\n]|\\.)*")''');

/// Non-comment string literals of a Dart source that contain a forbidden word.
List<String> _dartLiteralHits(String src) => _dartString
    .allMatches(_stripDartComments(src))
    .map((m) => m.group(0)!)
    // No package-name exception any more (renamed to `picpos_erp`).
    .where((s) => forbiddenBrandText.hasMatch(s))
    .toList();

// ── tests ──────────────────────────────────────────────────────────────────

void main() {
  group('(a) PicPos asset set and PicPos-visible sources', () {
    test('assets/i18n/en.json (shipped catalog) has no other-brand text', () {
      final hits = _textHits(_readText('assets/i18n/en.json'));
      expect(hits, isEmpty, reason: 'en.json is bundled with PicPos: $hits');
    });

    test('assets/ (non-binary) names and contents are brand-clean', () {
      final problems = <String>[];
      for (final e in Directory('assets').listSync(recursive: true)) {
        if (e is! File) continue;
        final rel = _norm(e.path);
        if (forbiddenBrandText.hasMatch(rel)) problems.add('name: $rel');
        final lower = rel.toLowerCase();
        if (lower.endsWith('.json') || lower.endsWith('.txt')) {
          final hits = _textHits(_readText(e.path));
          if (hits.isNotEmpty) problems.add('$rel: $hits');
        }
        final hash = _sha256File(e);
        if (brandDenyHashes.containsKey(hash)) {
          problems.add('$rel is ${brandDenyHashes[hash]}');
        }
      }
      expect(problems, isEmpty);
    });

    test('PicPos logo asset exists and is not an other-brand image', () {
      final f = File('assets/brand/picpos/logo.png');
      expect(f.existsSync(), isTrue);
      expect(brandDenyHashes.containsKey(_sha256File(f)), isFalse);
    });

    test('pubspec: catalog_ar.json is not bundled; foreign assets are pruned',
        () {
      final pub = _readText('pubspec.yaml');
      final assets = <String>[];
      var inAssets = false;
      for (final line in pub.split('\n')) {
        final t = line.trimRight();
        if (t.trim() == 'assets:') {
          inAssets = true;
          continue;
        }
        if (inAssets) {
          final m = RegExp(r'^\s+-\s+(\S+)\s*$').firstMatch(t);
          if (m != null) {
            assets.add(m.group(1)!);
          } else if (t.trim().isNotEmpty && !t.trim().startsWith('#')) {
            break; // end of the assets list
          }
        }
      }
      expect(assets, isNotEmpty, reason: 'could not parse pubspec assets');
      expect(assets.any((a) => a.contains('catalog_ar')), isFalse,
          reason: 'catalog_ar.json maps keys to source files and must not ship');

      // Any declared file that is an other-brand image must be pruned from the
      // PicPos bundle by tool/prune_picpos_bundle.ps1 (Flutter has no
      // per-brand assets on Windows).
      final prune = _readText('tool/prune_picpos_bundle.ps1');
      for (final a in assets) {
        final f = File(a);
        if (!f.existsSync() || a.endsWith('/')) continue;
        final hash = _sha256File(f);
        if (brandDenyHashes.containsKey(hash)) {
          expect(prune.contains("'$a'"), isTrue,
              reason: '$a (${brandDenyHashes[hash]}) is declared in '
                  'pubspec.yaml but not pruned by '
                  'tool/prune_picpos_bundle.ps1');
        }
      }
    });

    test('lib/: string literals with other-brand words only in the allow-list',
        () {
      final offenders = <String>[];
      for (final e in Directory('lib').listSync(recursive: true)) {
        if (e is! File || !e.path.endsWith('.dart')) continue;
        final rel = _norm(e.path);
        if (_libLiteralAllowList.containsKey(rel)) continue;
        final hits = _dartLiteralHits(_readText(e.path));
        if (hits.isNotEmpty) offenders.add('$rel: ${hits.take(3).toList()}');
      }
      expect(offenders, isEmpty,
          reason: 'New other-brand literal(s) in lib/. Route them through a '
              'const `Brand.isPicPos` fork and add the file to '
              '_libLiteralAllowList with a reason, or remove them.');
    });

    test('internal secret/identifier allow-list is EMPTY (migrated, '
        'docs/security/internal-identifier-migration.md)', () {
      expect(brandDeferredCryptoLiterals, isEmpty);
      expect(brandPackageNameExceptions, isEmpty);
      expect(brandThirdPartyDataExceptions, {
        'data/icudtl.dat': ['Uralsk.meta']
      });
    });

    test('lib/: allow-listed files still need their entry (list only shrinks)',
        () {
      final stale = <String>[
        for (final f in _libLiteralAllowList.keys)
          if (_dartLiteralHits(_readText(f)).isEmpty) f,
      ];
      expect(stale, isEmpty, reason: 'remove from _libLiteralAllowList: $stale');
    });

    test('native default identity (CMake, Runner.rc, main.cpp) is PicPos', () {
      String codeOnly(String path, Pattern commentStart) => _readText(path)
          .split('\n')
          .where((l) => !l.trimLeft().startsWith(commentStart))
          .join('\n');
      final cmake = codeOnly('windows/CMakeLists.txt', '#');
      final rc = codeOnly('windows/runner/Runner.rc', '//');
      final cpp = codeOnly('windows/runner/main.cpp', '//');
      // The CMake project name is `picpos_erp` now: no exception needed.
      final cmakeNoPkg = cmake;
      expect(_textHits(cmakeNoPkg), isEmpty);
      expect(_textHits(rc), isEmpty);
      expect(_textHits(cpp), isEmpty);
      expect(cmake, contains('set(BINARY_NAME "PicPos")'));
      expect(cmake, contains('set(BRAND_PRODUCT_NAME "PicPos")'));
      expect(cmake, contains('set(BRAND_COMPANY_NAME "PicPos")'));
      expect(rc, contains('#define BRAND_BINARY_NAME "PicPos"'));
    });

    test('default app_icon.ico is the PicPos icon (no copy step needed)', () {
      final def = _sha256File(File('windows/runner/resources/app_icon.ico'));
      final picpos =
          _sha256File(File('windows/runner/resources/app_icon_picpos.ico'));
      expect(def, picpos);
      expect(brandDenyHashes.containsKey(def), isFalse);
    });

    test('PicPos installer script, info text and wizard art are PicPos-only',
        () {
      for (final p in [
        'installer/setup_picpos.iss',
        'installer/info-ar-picpos.txt',
        'tools/postgresql_setup_guide_picpos.md',
        'build_picpos.bat',
        'build_installer_picpos.bat',
        'tool/prune_picpos_bundle.ps1',
      ]) {
        expect(_textHits(_readText(p)), isEmpty, reason: p);
      }
      final iss = _readText('installer/setup_picpos.iss');
      expect(iss, contains('#define ExeName      "PicPos.exe"'));
      expect(iss, isNot(contains('BrandId ==')));
      for (final e in Directory('installer/assets').listSync()) {
        if (e is! File || !_norm(e.path).contains('-picpos')) continue;
        expect(brandDenyHashes.containsKey(_sha256File(e)), isFalse,
            reason: e.path);
      }
      // The installer batch must use the PicPos-only script.
      expect(_readText('build_installer_picpos.bat'),
          contains(r'installer\setup_picpos.iss'));
    });

    test('CI builds PicPos (not the default brand) and runs the PicPos guards',
        () {
      final ci = _readText('.github/workflows/ci.yml');
      expect(ci, contains('build_picpos.bat'),
          reason: 'the Windows release job must use the PicPos build script');
      expect(ci, contains('--dart-define=APP_BRAND=picpos'));
      expect(ci, contains('brand_artifact_guard_test.dart'));
      expect(ci, contains('brand_picpos_test.dart'));
      expect(ci, isNot(contains('--build-number="\${{ github.run_number }}"')),
          reason: 'the build number must come from pubspec (REL-001)');
    });

    test('Android apps are labelled PicPos and carry no other-brand text', () {
      for (final app in ['mobile', 'mobile_admin', 'mobile_pos']) {
        final files = <String>[
          '$app/pubspec.yaml',
          '$app/android/app/build.gradle.kts',
          '$app/android/app/src/main/AndroidManifest.xml',
        ];
        final res = Directory('$app/android/app/src/main/res');
        if (res.existsSync()) {
          for (final e in res.listSync(recursive: true)) {
            if (e is File && e.path.endsWith('strings.xml')) files.add(e.path);
          }
        }
        for (final f in files) {
          if (!File(f).existsSync()) continue;
          expect(_textHits(_readText(f)), isEmpty, reason: f);
        }
      }
    });
  });

  group('(b) built PicPos Windows bundle', () {
    final dirs = picposBundleDirs();
    final skipReason = (dirs.isEmpty && !requireBrandBundle)
        ? 'no PicPos bundle (build/windows/x64/runner/Release or '
            'FlavorBuilds/PicPos with PicPos.exe); run build_picpos.bat'
        : null;

    test('a PicPos bundle exists when one is required', () {
      if (requireBrandBundle) {
        expect(dirs, isNotEmpty,
            reason: 'PICPOS_REQUIRE_BUNDLE=1 but no PicPos.exe bundle found');
      }
    }, skip: skipReason);

    for (final dir in dirs) {
      test('bundle ${_norm(dir.path)}: names, hashes and bytes are clean', () {
        final allowedSummary = <String, int>{};
        final problems =
            scanBrandBundle(dir, allowedSummary: allowedSummary);
        // ignore: avoid_print
        print('[brand-guard] ${dir.path}; documented exceptions: '
            '$allowedSummary');
        expect(problems, isEmpty,
            reason: 'Other-brand content in the PicPos bundle:\n'
                '${problems.take(40).join('\n')}');
      }, timeout: const Timeout(Duration(minutes: 10)));
    }
  });
}
