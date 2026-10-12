// ═══════════════════════════════════════════════════════════════════════════
// SPEC 084d — Server-side parties dedup (source pins)
// ═══════════════════════════════════════════════════════════════════════════
//
// Mirrors Spec 084c. Pins:
//   1. party_dao exposes auditDuplicateParties + repairDuplicateParties.
//   2. The audit query reads attached_txn_refs from the 4 transactional
//      tables (sales_invoices, purchase_invoices, safe_transactions,
//      commercial_papers).
//   3. Repair skips duplicates with attachedTxnRefs > 0 and emits a
//      [PARTY-DEDUP] SKIP log line.
//   4. The UI section is gated on NetworkService.isServerRunning.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import '../helpers/dao_source.dart';

void main() {
  group('Spec 084d — parties dedup', () {
    late String daoSrc;
    late String uiSrc;

    setUpAll(() {
      daoSrc = readDaoSourceMerged('lib/data/database/daos/party_dao.dart');
      uiSrc = File(
              'lib/presentation/widgets/settings/branch_scope_admin_dialog.dart')
          .readAsStringSync();
    });

    test('DAO exposes auditDuplicateParties + repairDuplicateParties', () {
      expect(daoSrc, contains('auditDuplicateParties()'),
          reason: 'Audit entry point required for the Settings UI scan.');
      expect(daoSrc, contains('repairDuplicateParties()'),
          reason: 'Repair entry point required for the Settings UI merge.');
    });

    test('audit query counts refs across 4 transactional tables', () {
      // The shared CTE must read from these specifically; if a future
      // refactor drops one, the "in-use" SKIP check goes silent and
      // duplicates with that ref get incorrectly soft-deleted.
      expect(daoSrc, contains('FROM sales_invoices'),
          reason: 'sales_invoices.customer_id ref is load-bearing.');
      expect(daoSrc, contains('FROM purchase_invoices'),
          reason: 'purchase_invoices.supplier_id ref is load-bearing.');
      expect(daoSrc, contains('FROM safe_transactions'),
          reason: 'safe_transactions.party_id ref is load-bearing '
              '(receipt/payment vouchers).');
      expect(daoSrc, contains('FROM commercial_papers'),
          reason: 'commercial_papers.party_id ref is load-bearing '
              '(cheques + promissory notes).');
    });

    test('repair SKIP path emits PARTY-DEDUP diagnostic line', () {
      expect(daoSrc, contains("'PARTY-DEDUP'"),
          reason: 'Diagnostic tag missing — support cannot trace which '
              'parties were skipped vs merged after a repair run.');
      expect(daoSrc, contains('SKIP dupId='),
          reason: 'SKIP log lines must carry dupId so support can '
              'correlate with the actual rows in the DB.');
    });

    test('Settings UI section is gated on server-running', () {
      // The section sits inside the same `if (NetworkService.instance.
      // isServerRunning)` block as the branches dedup section.
      expect(
        uiSrc.contains('NetworkService.instance.isServerRunning') &&
            uiSrc.contains('_partyServerDedupSection'),
        isTrue,
        reason: 'Section MUST be hidden in standalone/client/mirror — '
            'the audit query reads server-side counts and would surface '
            'misleading numbers to a non-server caller.',
      );
    });

    test('Settings UI uses type-to-confirm guard', () {
      // ValueListenableBuilder + isMatch == true gating the Confirm
      // button is the type-to-confirm pattern shared with 084c.
      // The party dedup confirm dialog must use the same protection
      // because parties are tied to financial history.
      // The method body is sizable (textfield + dialog + valuelistenable);
      // 8000 chars covers it comfortably.
      final start = uiSrc.indexOf('_confirmAndRepairPartyDups');
      final partySection = uiSrc.substring(
        start,
        (start + 8000).clamp(0, uiSrc.length),
      );
      expect(partySection, contains('ValueListenableBuilder<bool>'),
          reason: 'Type-to-confirm dialog requires reactive button gating.');
      expect(partySection, contains('controller.text.trim() == expectedName'),
          reason: 'The match check must require an EXACT (trimmed) '
              'name match so a stray typo cannot accidentally confirm.');
    });
  });
}
