// Structural guard — every server submit must go through
// `ClientWriteInterceptor.dispatchWrite`, never `unawaited(...)` directly.
//
// Why this is a structural test and not a behavioural one: the defect class
// is "a NEW write path forgot the mirror contract". Behavioural tests can only
// cover the paths someone remembered to write a test for; this one fails the
// moment anybody adds a raw fire-and-forget submit anywhere in the codebase.
//
// The contract (SYNC_ARCHITECTURE §8.3): mirror mode has NO outbox. A submit
// that fails there means the write did not happen, so the caller must abort
// instead of writing a local row the operator will read as saved. `_tryOrQueue`
// already throws `MirrorOfflineException` for exactly this; the bug was that
// every caller launched the submit with `unawaited(...).catchError(debugPrint)`
// and carried on regardless — including a log line claiming "queued in outbox",
// which is false in mirror mode.
//
// `dispatchWrite` encodes the branch once: awaited in mirror, unchanged
// fire-and-forget in client (where the outbox IS the safety net).
//
// ── Baseline ────────────────────────────────────────────────────────────────
// The migration is partial ON PURPOSE. It covers the paths where the submit
// already precedes the local write, so aborting leaves nothing half-written.
// The files below still hold raw call sites because their local write happens
// FIRST — fixing them means reordering the flow, which is a separate change
// with its own risk (in `inventory_service` the current order is a documented
// past decision: "نُعتبر الـ local save authoritative"). Each entry is a known
// remaining mirror-write-loss path, not an accepted pattern.
//
// To migrate a file off the baseline: move the submit ahead of the local
// write, wrap it in `dispatchWrite`, re-run, and lower the number here.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Documented exemptions — fire-and-forget here is CORRECT, not a gap.
///
/// `main.dart` → `reconcileOpeningStocks()` is a startup reconciliation sweep,
/// not a user write. It is idempotent server-side (skips any product/warehouse
/// that already has an opening_stock movement) and must never block app
/// startup, so there is no local row for a failure to falsify.
const Map<String, int> _exempt = {'lib/main.dart': 1};

/// Remaining raw `unawaited(ClientWriteInterceptor.…)` submit sites, per file.
/// A file absent from this map (and from [_exempt]) must contain zero.
const Map<String, int> _baseline = {
  // Local write happens inside `_db.transaction` before the submit.
  'lib/data/repositories/sales_transaction_orchestrator.dart': 1,
  // UI-layer paths; each writes locally first.
  'lib/presentation/widgets/dialogs/add_product_dialog.dart': 1,
  'lib/presentation/screens/shift_close_screen.dart': 1,
  'lib/presentation/shift_close_picpos/screens/shift_close_picpos_screen.dart':
      1,
  'lib/app_main_screen.dart': 0,
  'lib/app_main_screen_shift.dart': 1,
};

void main() {
  test('no new raw fire-and-forget ClientWriteInterceptor submits', () {
    // `unawaited(` followed by a ClientWriteInterceptor call on the same line —
    // the exact shape every one of the 20 known loss paths had.
    final pattern = RegExp(r'unawaited\(\s*ClientWriteInterceptor\s*\.');
    final offenders = <String, int>{};

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final rel = entity.path.replaceAll(r'\', '/');
      final count = pattern.allMatches(entity.readAsStringSync()).length;
      if (count > 0) offenders[rel] = count;
    }

    final failures = <String>[];
    offenders.forEach((file, count) {
      final allowed = _exempt[file] ?? _baseline[file] ?? 0;
      if (count > allowed) {
        failures.add('$file: $count raw submit(s), baseline $allowed');
      }
    });

    // A count BELOW baseline is progress, not a failure — but the baseline
    // must be lowered so it keeps its teeth.
    final stale = <String>[];
    _baseline.forEach((file, allowed) {
      final actual = offenders[file] ?? 0;
      if (actual < allowed) {
        stale.add('$file: now $actual, baseline still $allowed — lower it');
      }
    });

    expect(
      failures,
      isEmpty,
      reason:
          'New raw submit sites bypass the mirror contract. Route them '
          'through ClientWriteInterceptor.dispatchWrite (and make sure the '
          'submit runs BEFORE the local write, so mirror can abort cleanly).'
          '\n${failures.join('\n')}',
    );
    expect(
      stale,
      isEmpty,
      reason:
          'Baseline is stale — a path was migrated but the number was '
          'not lowered, so the guard has slack.\n${stale.join('\n')}',
    );
  });
}
