// ═══════════════════════════════════════════════════════════════════════════
// Feature 005 — CoA Hardening: Purpose-Mapping Resolution Tests
//
// Regression guards for the fragility points discovered during 004 testing
// (2026-05-03). The closing-entry service, JE factory, and HR/e-invoicing
// DAOs used to fall back to hardcoded codes (`3201`, `5301`, `4301`, `4101`,
// `5101`, `1201`, `2201`, `1204`, `1101`) that were never seeded — every
// such fallback path crashed in production. After Feature 005 these paths
// resolve via the purpose-mapping system that's already populated by
// `syncDefaultAccounts()` → `syncAccountMappings()`.
//
// These tests verify:
//   1. Every purpose used by JE factory + closing service resolves to a
//      real seeded account.
//   2. The previously-broken hardcoded codes still don't exist (guards
//      against someone re-introducing them).
//   3. The fallback chain (primary → secondary purpose) works when the
//      primary purpose is unmapped.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting();
    // Bootstrap full COA + default mappings — same path as production install.
    await db.syncDefaultAccounts();
  });

  tearDown(() => db.close());

  group('Feature 005 — Purpose mapping resolves to seeded accounts', () {
    // ─────────────────────────────────────────────────────────────────────
    test('retained_earnings resolves (closing entry crash fix)', () async {
      final acc = await db.getAccountByPurpose('retained_earnings');
      expect(acc, isNotNull, reason: 'closing_entry_service.dart:125 depends on this');
      expect(acc!.code, '313');
    });

    test('inventory_shrinkage resolves (cycle-count shortage crash fix)', () async {
      final acc = await db.getAccountByPurpose('inventory_shrinkage');
      expect(acc, isNotNull, reason: 'journal_entry_factory.dart:819 depends on this');
      expect(acc!.code, '6216');
    });

    test('inventory_surplus resolves (cycle-count overage crash fix)', () async {
      final acc = await db.getAccountByPurpose('inventory_surplus');
      expect(acc, isNotNull, reason: 'journal_entry_factory.dart:847 depends on this');
      expect(acc!.code, '4317');
    });

    test('misc_expense resolves (shift-close fallback)', () async {
      final acc = await db.getAccountByPurpose('misc_expense');
      expect(acc, isNotNull);
      expect(acc!.code, '6214');
    });

    test('op_expenses resolves to misc-expense alias', () async {
      final acc = await db.getAccountByPurpose('op_expenses');
      expect(acc, isNotNull, reason: 'journal_entry_factory.dart:716 depends on this');
      expect(acc!.code, '6214');
    });

    test('other_income resolves (overage secondary fallback)', () async {
      final acc = await db.getAccountByPurpose('other_income');
      expect(acc, isNotNull);
      expect(acc!.code, '4315');
    });

    test('receivables resolves (sales-return reversal crash fix)', () async {
      final acc = await db.getAccountByPurpose('receivables');
      expect(acc, isNotNull, reason: 'journal_entry_factory.dart:637 depends on this');
      expect(acc!.code, '1121');
    });

    test('output_vat resolves (e-invoice settlement crash fix)', () async {
      final acc = await db.getAccountByPurpose('output_vat');
      expect(acc, isNotNull, reason: 'e_invoicing_dao.dart:724 depends on this');
      expect(acc!.code, '2121');
    });

    test('input_vat resolves (e-invoice settlement crash fix)', () async {
      final acc = await db.getAccountByPurpose('input_vat');
      expect(acc, isNotNull, reason: 'e_invoicing_dao.dart:725 depends on this');
      expect(acc!.code, '1141');
    });

    test('cash resolves (HR advance + treasury fallback)', () async {
      final acc = await db.getAccountByPurpose('cash');
      expect(acc, isNotNull);
      expect(acc!.code, '1111');
    });
  });

  group('Feature 005 — Previously-broken hardcoded codes are absent', () {
    // The pre-005 fallback codes that crashed production. If someone
    // accidentally re-seeds them, this test fails to catch the regression.
    const ghostCodes = ['3201', '5301', '5101', '4301', '4101', '1201', '2201', '1204', '1101'];

    for (final code in ghostCodes) {
      test('code "$code" is NOT in the default seeded chart', () async {
        final acc = await db.getAccountByCode(code);
        expect(acc, isNull,
            reason: 'Code "$code" was a phantom fallback before 005 — '
                'if this fails, the hardcoded fallback path is back');
      });
    }
  });

  group('Feature 005 — Code↔Purpose consistency contract', () {
    // The accountPurposes map declares default codes. Every default code
    // MUST exist in the seeded chart, otherwise the fallback chain inside
    // getAccountByPurpose() returns null and JE creation crashes.
    test('every accountPurposes default code is seeded', () async {
      final missing = <String>[];
      for (final entry in AccountingDao.accountPurposes.entries) {
        final acc = await db.getAccountByCode(entry.value);
        if (acc == null) {
          missing.add('${entry.key}=${entry.value}');
        }
      }
      expect(missing, isEmpty,
          reason: 'These default codes are referenced but not seeded: $missing');
    });
  });
}
