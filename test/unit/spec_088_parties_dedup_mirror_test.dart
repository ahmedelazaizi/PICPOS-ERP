// ═══════════════════════════════════════════════════════════════════════════
// SPEC 088 USR-3 — Parties dedup tool surfaces on mirror (source pins)
// ═══════════════════════════════════════════════════════════════════════════
//
// Field bug: V151 smoke on a mirror showed duplicate party rows
// (delivery companies, customers, suppliers) visible in the parties
// list. The Spec 084d dedup tool ships in Settings → أدوات صيانة
// المسؤول but its mode gate hides the section unless the device is
// running a server. Operators can't fix the mirror's duplicates by
// running the tool on the server because the server's parties table is
// already clean — the duplicates live ONLY on the mirror's local DB.
//
// Fix: widen the gate so the parties section also surfaces on mirror.
// The branches section (Spec 084c) stays server-only because it isn't
// in scope for USR-3 and would need its own audit. The dedup repair
// itself already operates on the local DB inside one Drift
// `transaction()` and emits no server writes (FR-304), so opening it
// on mirror is safe with zero further changes.
//
// These pins ensure:
//   1. The dialog imports SyncInterceptor.
//   2. The parties-section gate accepts `isMirrorMode` in addition to
//      `isServerRunning`.
//   3. The branches-section gate is NOT widened (FR-307 — branches
//      dedup remains server-only).
//   4. The repair function in party_dao still wraps everything in a
//      single transaction() and uses raw Drift updates (NOT a path
//      that goes through ClientWriteInterceptor).
//   5. The confirmation dialog text no longer claims "السيرفر" — it
//      now correctly says "هذا الجهاز" so a mirror operator isn't
//      misled.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Spec 088 USR-3 — mirror parties dedup', () {
    final dialogSrc = File(
            'lib/presentation/widgets/settings/branch_scope_admin_dialog.dart')
        .readAsStringSync();
    final daoSrc =
        File('lib/data/database/daos/party_dao.dart').readAsStringSync();

    test('dialog imports SyncInterceptor', () {
      expect(
          dialogSrc,
          contains(
              "import '../../../data/database/sync_interceptor.dart'"),
          reason:
              'Without the import, the SyncInterceptor.isMirrorMode reference '
              'in the section gate is unresolved.');
    });

    test('parties dedup section is visible on server OR mirror', () {
      // The gate must read both server AND mirror — server alone would
      // not fix the field bug. Use a regex tolerant of whitespace +
      // CRLF/LF so the test does not pin a specific line layout.
      final orGatePattern = RegExp(
        r'NetworkService\.instance\.isServerRunning\s*\|\|\s*'
        r'SyncInterceptor\.isMirrorMode',
        multiLine: true,
      );
      expect(orGatePattern.hasMatch(dialogSrc), isTrue,
          reason: 'Mirror visibility is the entire point of USR-3. Without '
              'this OR condition the section stays hidden on the mirror '
              'and operators see the same duplicates they saw in V151.');
      // Confirm the parties section is the one that lives behind the OR
      // gate (not the branches section, which stays server-only).
      final orGateIdx = dialogSrc.indexOf('SyncInterceptor.isMirrorMode');
      final partySectionIdx = dialogSrc.indexOf('_partyServerDedupSection()');
      expect(orGateIdx, isNot(-1));
      expect(partySectionIdx, isNot(-1));
      expect(orGateIdx < partySectionIdx, isTrue,
          reason: 'OR gate must precede the parties-section call site.');
    });

    test('branches dedup section stays server-only (FR-307 — not in USR-3 scope)',
        () {
      // The branches-section gate should NOT be widened. Spec 084c was
      // never re-audited for mirror; USR-3 is parties-only.
      final start = dialogSrc.indexOf('_branchServerDedupSection()');
      expect(start, isNot(-1));
      // Find the if-gate that immediately precedes the call. Walk a
      // small window backwards looking for the `if (` line that
      // contains the gate.
      final beforeChunk =
          dialogSrc.substring((start - 300).clamp(0, start), start);
      expect(beforeChunk, contains('NetworkService.instance.isServerRunning'),
          reason: 'Branches section gate must still mention isServerRunning.');
      expect(beforeChunk.contains('SyncInterceptor.isMirrorMode'), isFalse,
          reason: 'Adding mirror to the branches gate would require its '
              'own dedup audit (and may emit server-bound writes). Out '
              'of scope for Spec 088 — keep server-only.');
    });

    test('repairDuplicateParties is wrapped in a transaction', () {
      // R3: every multi-step DAO mutation must run inside transaction().
      // Without this, a failed FK remap leaves the DB half-merged.
      final start = daoSrc.indexOf(
          'Future<PartyDedupResult> repairDuplicateParties()');
      expect(start, isNot(-1));
      final block = daoSrc.substring(start, start + 2500);
      expect(block, contains('return await transaction(() async {'),
          reason: 'The whole repair (audit → soft-delete loop) must be '
              'atomic. ENGINEERING_GUIDELINES.md §R3 — multi-step DAO writes must be '
              'transactional. A half-applied dedup leaves orphan rows '
              'that the next sync cannot recover from.');
    });

    test('repair does NOT go through ClientWriteInterceptor (mirror-local only)',
        () {
      // FR-304: the dedup MUST NOT emit any ClientWriteInterceptor
      // call, outbox entry, or ServerProxy request. The server's
      // parties table is already canonical.
      final start = daoSrc.indexOf(
          'Future<PartyDedupResult> repairDuplicateParties()');
      expect(start, isNot(-1));
      final block = daoSrc.substring(start, start + 3000);
      expect(block.contains('ClientWriteInterceptor'), isFalse,
          reason: 'Routing the soft-delete through ClientWriteInterceptor '
              'would push the deletion to the server (which does not '
              'have the duplicate to delete) and would conflict with '
              'FR-304.');
      // Direct Drift update is what FR-304 expects.
      expect(block, contains('update(parties)'),
          reason: 'Repair uses Drift directly on the local DB.');
    });

    test('parties dedup confirmation dialog text says "هذا الجهاز" not "السيرفر"',
        () {
      // Pre-088 wording in the parties confirmation was misleading on
      // mirror — it said the action operates on the server. Now it
      // correctly says "this device". Scoped to the parties confirmation
      // block; the BRANCHES confirmation (still server-only per FR-307)
      // legitimately keeps the "السيرفر" wording, so we extract only
      // the parties-confirmation slice for this assertion.
      // Find the function DECLARATION (not its earlier reference inside
      // the onPressed callback) so the substring captures the actual
      // confirmation dialog markup.
      final partyConfirmStart =
          dialogSrc.indexOf('Future<void> _confirmAndRepairPartyDups()');
      expect(partyConfirmStart, isNot(-1),
          reason: 'The function declaration must exist verbatim.');
      final blockEnd = (partyConfirmStart + 4500).clamp(0, dialogSrc.length);
      final partyConfirmBlock =
          dialogSrc.substring(partyConfirmStart, blockEnd);
      expect(
          partyConfirmBlock,
          contains('هذا الإجراء يعمل على قاعدة بيانات هذا الجهاز'),
          reason: 'On mirror the action operates on the mirror\'s DB, not '
              'the server\'s. Reverting to the old "السيرفر مباشرة" '
              'wording would mislead the operator about the blast '
              'radius of the destructive step.');
      // Defensive: the old phrasing must NOT appear in the parties
      // confirmation block. (It is fine in the branches confirmation
      // higher up the file, which stays server-only.)
      expect(
          partyConfirmBlock.contains('يعمل على السيرفر مباشرة'), isFalse,
          reason: 'Parties confirmation must not claim server-side blast '
              'radius on a mirror.');
    });
  });
}
