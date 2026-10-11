// ═══════════════════════════════════════════════════════════════════════════
// SPEC 082b — Cheque counter-account override diagnostics (source pins)
// ═══════════════════════════════════════════════════════════════════════════
//
// Pins:
//   1. The DAO's counterAccountId-not-found fallback emits a
//      DiagnosticLogger line tagged CP-AUTOPOST-OVERRIDE-FALLBACK.
//      Reverting to debugPrint loses the field-support trail.
//   2. The server-side globalId remap emits CP-AUTOPOST-GLOBALID-REMAP
//      when client/server ids diverge (benign, but visible).
//   3. The server-side globalId NOT FOUND case (sync gap) emits
//      CP-AUTOPOST-GLOBALID-MISS — this is the new field-debugging
//      signal that was previously silent.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import '../helpers/api_data_handler_source.dart';

void main() {
  group('Spec 082b — counter-account override diagnostics', () {
    test('DAO override-fallback uses DiagnosticLogger, not debugPrint', () {
      final src = File('lib/data/database/daos/commercial_papers_dao.dart')
          .readAsStringSync();
      expect(src, contains("'CP-AUTOPOST-OVERRIDE-FALLBACK'"),
          reason: 'Field bug: when override counterAccountId does not '
              'resolve to a local account, the silent debugPrint left '
              'support unable to trace why the JE landed on the default '
              'instead of the user-chosen account. Must persist via '
              'DiagnosticLogger so the support log carries the signal.');
      // The old debugPrint line should be gone (a literal that referenced
      // "[CP-AUTOPOST] counterAccountId=" + "not found locally").
      expect(
        src.contains("debugPrint('[CP-AUTOPOST] counterAccountId="),
        isFalse,
        reason: 'Stale debugPrint left over — replace with DiagnosticLogger.',
      );
    });

    test('API handler emits CP-AUTOPOST-GLOBALID-MISS on resolve fail', () {
      final src =
          readApiDataHandlerSource();
      expect(src, contains("'CP-AUTOPOST-GLOBALID-MISS'"),
          reason: 'New signal — surfaces the sync gap (client picked an '
              'account whose globalId does not exist on server). '
              'Without this, the resolver silently keeps the client id '
              'and the JE lands on whatever account happens to share '
              'that id on the server, with no log trail.');
    });

    test('API handler emits CP-AUTOPOST-GLOBALID-REMAP on benign remap', () {
      final src =
          readApiDataHandlerSource();
      expect(src, contains("'CP-AUTOPOST-GLOBALID-REMAP'"),
          reason: 'Benign trace — when client.id != server.id but '
              'globalId resolves correctly. Useful to confirm the happy '
              'path is firing during field smoke.');
      expect(
        src.contains("debugPrint('[API] putCommercialPaperStatus: remapped"),
        isFalse,
        reason: 'Stale debugPrint left over — replace with DiagnosticLogger.',
      );
    });
  });
}
