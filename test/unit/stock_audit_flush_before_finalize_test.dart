// Pre-deploy BLOCKER (jard audit 2026-07-13) — the STOCK-AUDIT screen has the
// un-fixed TWIN of cycle-count BUG-C.
//
// The editable "الفعلي" field built a fresh `TextEditingController` on every
// rebuild and persisted the typed value ONLY via `onSubmitted` (Enter).
// `_finalizeAudit` went straight to `finalizeAudit(auditId)` with NO flush of
// typed-but-unsubmitted values. So: operator uses the new manual flow (BUG-A
// «إضافة صنف» seeds actual=expected, diff=0), types the real physical count,
// then taps «اعتماد الجرد النهائي» WITHOUT Enter → the typed value never reaches
// the DB → finalizeAudit sees diff=0 → NO stock adjustment, yet a success toast
// fires. Silent lost adjustment — the exact symptom the owner reported for
// cycle-count BUG-C, left unfixed on the sibling screen.
//
// Source-level guard (mirrors the cycle_count BUG-C fix): assert the screen
// holds persistent per-item controllers and flushes them before finalize.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const relPath = 'lib/presentation/screens/stock_audit_screen.dart';
  late String source;

  setUpAll(() {
    final file = File(relPath);
    expect(file.existsSync(), isTrue, reason: 'expected screen at $relPath');
    source = file.readAsStringSync();
  });

  group('Stock-audit flush-before-finalize (cycle-count BUG-C twin)', () {
    test('holds persistent per-item "الفعلي" controllers (survive rebuilds)', () {
      expect(
        source.contains('_actualCtrls'),
        isTrue,
        reason:
            'the editable actual-count field must use a persistent controller '
            'keyed by item id (like cycle-count _countCtrls) so a typed-but-not-'
            'Entered value survives rebuilds and can be flushed before finalize.',
      );
    });

    test('flushes pending counts BEFORE finalizeAudit', () {
      final flushIdx = source.indexOf('_flushPendingActualCounts(');
      final finalizeIdx = source.indexOf('finalizeAudit(auditId)');
      expect(
        flushIdx != -1,
        isTrue,
        reason: 'a _flushPendingActualCounts() must persist typed-but-unsubmitted '
            'counts before the audit is finalized.',
      );
      expect(
        finalizeIdx != -1 && flushIdx < finalizeIdx,
        isTrue,
        reason: 'the flush must run BEFORE finalizeAudit(auditId) — otherwise the '
            'typed physical count is dropped and no stock adjustment happens.',
      );
    });
  });
}
