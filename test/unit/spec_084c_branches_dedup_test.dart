// ═══════════════════════════════════════════════════════════════════════════
// SPEC 084c — Server-side branches dedup (Settings UI)
// ═══════════════════════════════════════════════════════════════════════════
//
// Source pins (no PG fixture — the DAO uses customStatement/customSelect
// which is exercised against the real server in smoke). These pins protect
// the invariants spec'd in AC-1..AC-9 so a future refactor doesn't silently
// drop them:
//
//   AC-1: dialog section is gated on NetworkService.instance.isServerRunning
//   AC-5: repair runs inside transaction()
//   AC-5: skipped duplicates are detected by attached_txn_refs > 0
//   AC-5: soft-delete sets is_active=false + deleted_at + last_modified_at
//   AC-6: DiagnosticLogger emits one BRANCH-DEDUP line per merged + skipped
//   AC-8: confirmation requires typing the exact branch name
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Spec 084c — DAO source pins', () {
    late String src;

    setUpAll(() {
      src =
          File('lib/data/database/daos/branches_dao.dart').readAsStringSync();
    });

    test('auditDuplicateBranches selects active branches grouped by name', () {
      expect(src, contains('Future<List<DuplicateBranchGroup>> auditDuplicateBranches'),
          reason: 'Renamed/removed audit helper would silently break the UI.');
      expect(src, contains('GROUP BY name HAVING COUNT(*) > 1'),
          reason: 'Audit must restrict to actual name collisions.');
      expect(src, contains('is_active = TRUE'),
          reason: 'Soft-deleted rows must not appear in the audit.');
    });

    test('repairDuplicateBranches runs inside transaction()', () {
      // AC-5 — txn wrap is what allows safe rollback on FK violation.
      final repairIdx = src.indexOf('repairDuplicateBranches');
      expect(repairIdx, isNot(-1));
      final after = src.substring(repairIdx, repairIdx + 400);
      expect(after, contains('transaction(() async'),
          reason: 'Repair must be wrapped in transaction() so a mid-flow '
              'FK violation rolls back ALL the user_branch_access moves and '
              'soft-deletes together.');
    });

    test('repair skips duplicates with attached transactional refs', () {
      // AC-5 — invoices/shifts attached → SKIP, operator handles manually.
      expect(src, contains('if (dup.attachedTxnRefs > 0)'),
          reason: 'Skip-predicate guard missing — would soft-delete branches '
              'still referenced by sales_invoices/shifts and break historical '
              'attribution.');
      expect(src, contains("BRANCH-DEDUP"),
          reason: 'DiagnosticLogger tag must be BRANCH-DEDUP so support can '
              'grep mirror logs.');
      expect(src, contains("'SKIP dupId="),
          reason: 'Skip event must be observable in DiagnosticLogger.');
    });

    test('soft-delete sets is_active=false + deleted_at + last_modified_at', () {
      // AC-5 — mirrors the v131 deactivateBranch shape.
      expect(src, contains('isActive: const Value(false)'),
          reason: 'Hard-delete (issuing DELETE) on a branch with sync history '
              'would create FK orphans on sales/shifts.');
      expect(src, contains('deletedAt: Value(DateTime.now())'),
          reason: 'deletedAt timestamp is needed for the mirror to ignore '
              'the row going forward.');
      expect(src, contains('lastModifiedAt: Value(DateTime.now())'),
          reason: 'lastModifiedAt bump is required so sync strategies pick '
              'up the soft-delete on the next pull.');
    });

    test('BranchDedupResult exposes public merged/skipped lists', () {
      // AC-7 — UI needs to read these to render the result message.
      expect(src, contains('class BranchDedupResult'));
      expect(src, contains('final List<MergedBranchDedupRecord> merged'));
      expect(src, contains('final List<SkippedBranchDedupRecord> skipped'));
    });
  });

  group('Spec 084c — Dialog source pins', () {
    late String src;

    setUpAll(() {
      src = File(
              'lib/presentation/widgets/settings/branch_scope_admin_dialog.dart')
          .readAsStringSync();
    });

    test('section visibility gated on NetworkService.isServerRunning', () {
      // AC-1 — section MUST be hidden on client/mirror/standalone so the
      // operator can never accidentally run server-mutating SQL against
      // their local mirror DB.
      expect(
          src, contains('if (NetworkService.instance.isServerRunning)'),
          reason: 'Without this gate the section appears in client/mirror '
              'mode too, where it would either no-op or mutate the local '
              'mirror SQLite — both wrong.');
    });

    test('repair confirmation requires typing the branch name', () {
      // AC-8 — type-to-confirm guard.
      expect(src, contains('isMatch.value = controller.text.trim() == expectedName'),
          reason: 'Type-to-confirm predicate is the only thing stopping '
              'a fat-fingered click on "تأكيد الإصلاح" from soft-deleting '
              'real branches on production PG.');
      expect(src, contains('اكتب اسم الفرع للتأكيد'),
          reason: 'Operator-facing hint for the type-to-confirm field.');
    });

    test('post-repair re-audit refreshes the section', () {
      // AC-7 — the UI must reflect the new state after repair, not stay
      // stale showing the now-deleted duplicates.
      expect(src, contains('final refreshed = await db.auditDuplicateBranches()'),
          reason: 'Without a re-audit the UI would still show the duplicates '
              'after they have been soft-deleted, misleading the operator.');
    });
  });
}
