// Spec 029 / US2 — Mode-equality grep guard.
//
// Prevent re-introduction of `_mode == NetworkMode.client` (or `mode ==
// NetworkMode.client`) used as a write gate without mirror coverage.
// The legacy strict-client predicate evaluates FALSE in mirror mode — so any
// new code that gates a server-bound write on it would silently drop the
// write on mirror devices (the same incident class as Feature 007 root cause
// and Feature 010 / Cluster A).
//
// Mirror mode IS a flavour of client. The broadened predicate
// `SyncInterceptor.isClientMode` (true for client OR mirror) is the
// correct gate. See specs/007-mirror-sync-multibranch/contracts/
// globalid-flow.md.
//
// Allowed forms (all PASS the guard):
//   (a) Mirror coverage in the same conditional / nearby:
//         if (_mode == NetworkMode.client || _mode == NetworkMode.mirror)
//   (b) Operator-marked exception:
//         // strict-client OK: <one-line reason>
//         if (_mode == NetworkMode.client) { ... }
//   (c) Use of the broadened predicate (no equality match → not seen by guard):
//         if (SyncInterceptor.isClientMode) { ... }
//
// Disallowed:
//   (d) Bare strict-client equality, no mirror in window, no exception:
//         if (_mode == NetworkMode.client) { /* write */ }
//
// Scanned roots: lib/ only (excludes generated code, tools/, web_app/, docs/).
// Window: 300 chars before + 300 after the hit (~600 total). Same window
// size as the existing orchestrator_gate_predicate_test.dart.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _scanRoots = <String>['lib'];

final _antiPattern = RegExp(r'\b_?mode\s*==\s*NetworkMode\.client\b');

const _exceptionMarker = '// strict-client OK:';

void main() {
  test('no `_mode == NetworkMode.client` write gates without mirror coverage',
      () {
    final hits = <String>[];

    for (final root in _scanRoots) {
      final dir = Directory(root);
      expect(
        dir.existsSync(),
        isTrue,
        reason: 'scan root $root does not exist (run from repo root)',
      );

      for (final entity in dir.listSync(recursive: true, followLinks: false)) {
        if (entity is! File) continue;
        final path = entity.path.replaceAll('\\', '/');
        if (!path.endsWith('.dart')) continue;
        // Skip auto-generated files — Drift / freezed / json output is not
        // hand-written and never gates a write.
        if (path.endsWith('.g.dart') ||
            path.endsWith('.freezed.dart') ||
            path.endsWith('.gen.dart')) {
          continue;
        }

        final source = entity.readAsStringSync();
        for (final match in _antiPattern.allMatches(source)) {
          if (_isAllowed(source, match)) continue;
          final line = _lineNumber(source, match.start);
          hits.add('$path:$line  → ${_lineSnippet(source, match)}');
        }
      }
    }

    expect(
      hits,
      isEmpty,
      reason: 'Strict-client equality used as a possible write gate. Mirror '
          'mode evaluates FALSE on this predicate, so writes will silently '
          'fall through. Use SyncInterceptor.isClientMode (broadened to '
          'include mirror), OR cover both modes explicitly:\n'
          '  if (_mode == NetworkMode.client || _mode == NetworkMode.mirror) ...\n'
          'OR mark the line with the exception comment if it is a genuine '
          'strict-client check (e.g., UI-only, leaving-client transition):\n'
          '  // strict-client OK: <one-line reason>\n\n'
          'Hits:\n${hits.join('\n')}\n\n'
          'See specs/007-mirror-sync-multibranch/contracts/globalid-flow.md '
          'and specs/029-sync-regression-hardening/contracts/'
          'mode-equality-guard.md.',
    );
  });
}

bool _isAllowed(String source, Match match) {
  final start = (match.start - 300).clamp(0, source.length);
  final end = (match.end + 300).clamp(0, source.length);
  final window = source.substring(start, end);

  if (window.contains('NetworkMode.mirror')) return true;
  if (window.contains(_exceptionMarker)) return true;
  return false;
}

int _lineNumber(String source, int offset) =>
    '\n'.allMatches(source.substring(0, offset)).length + 1;

String _lineSnippet(String source, Match match) {
  final lineStart = source.lastIndexOf('\n', match.start) + 1;
  final lineEndIdx = source.indexOf('\n', match.start);
  final lineEnd = lineEndIdx > 0 ? lineEndIdx : source.length;
  return source.substring(lineStart, lineEnd).trim();
}
