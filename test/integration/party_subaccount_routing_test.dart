// ═══════════════════════════════════════════════════════════════════════════
// Feature 005 Phase 6 — Party Sub-Account Routing Tests
// ═══════════════════════════════════════════════════════════════════════════
//
// Verifies that the parent-account constants are aligned with the seeded
// chart of accounts:
//
//   _arParentCode = '1121'  (ذمم عملاء محليون, seeded under 112)
//   _apParentCode = '2111'  (ذمم موردون محليون, seeded under 211)
//
// Pre-005 the constants were '1201' / '2101' — codes that did NOT exist in
// seedChartOfAccounts(). On every party-creation flow the system created
// those codes as orphan roots, producing two parallel control accounts
// per role and silently splitting per-supplier balances between them.
//
// These tests guard the realigned behaviour:
//   1. Inserting a customer/supplier creates a sub-account under the
//      seeded parent — never under the phantom 1201/2101.
//   2. The orphan codes 1201/2101 stay absent from the seeded chart.
//   3. parties.accountId is populated and points at the new sub-account.
//   4. ensurePartyParentAccounts() returns the seeded ids (no duplicates).
// ═══════════════════════════════════════════════════════════════════════════

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting();
    // Bootstrap full COA — same path as production install.
    await db.syncDefaultAccounts();
  });

  tearDown(() => db.close());

  group('Party parent constants align with seeded chart', () {
    test('seeded chart contains 1121 (AR) and 2111 (AP)', () async {
      final ar = await db.getAccountByCode('1121');
      final ap = await db.getAccountByCode('2111');
      expect(ar, isNotNull,
          reason: 'AR control "1121" must be seeded under 112');
      expect(ap, isNotNull,
          reason: 'AP control "2111" must be seeded under 211');
    });

    test('phantom codes 1201 and 2101 are absent (no runtime creation)',
        () async {
      final phantom1201 = await db.getAccountByCode('1201');
      final phantom2101 = await db.getAccountByCode('2101');
      expect(phantom1201, isNull,
          reason: 'pre-005 phantom AR parent must not be created');
      expect(phantom2101, isNull,
          reason: 'pre-005 phantom AP parent must not be created');
    });

    test('ensurePartyParentAccounts returns the seeded ids — no duplicates',
        () async {
      final map = await db.ensurePartyParentAccounts();
      expect(map.keys, containsAll(['1121', '2111']));

      final arSeeded = await db.getAccountByCode('1121');
      final apSeeded = await db.getAccountByCode('2111');
      expect(map['1121'], arSeeded!.id,
          reason: 'reuse the seeded 1121, do not insert a duplicate');
      expect(map['2111'], apSeeded!.id,
          reason: 'reuse the seeded 2111, do not insert a duplicate');

      // Also: only one row per code exists in `accounts`.
      final ar = await (db.select(db.accounts)
            ..where((a) => a.code.equals('1121')))
          .get();
      final ap = await (db.select(db.accounts)
            ..where((a) => a.code.equals('2111')))
          .get();
      expect(ar, hasLength(1));
      expect(ap, hasLength(1));
    });
  });

  group('Party creation routes to seeded parents', () {
    test('inserting a customer creates a sub-account under 1121', () async {
      final partyId = await db.insertParty(const PartiesCompanion(
        name: Value('عميل اختبار'),
        isCustomer: Value(true),
        isSupplier: Value(false),
      ));

      final party = await db.getPartyById(partyId);
      expect(party, isNotNull);
      expect(party!.accountId, isNotNull,
          reason: 'every party must be linked to a sub-account');

      final sub = await db.getAccountById(party.accountId!);
      expect(sub, isNotNull);
      expect(sub!.code, startsWith('1121-'),
          reason: 'sub-account code must mirror the seeded AR parent');

      final parent = await db.getAccountById(sub.parentId!);
      expect(parent!.code, '1121');
    });

    test('inserting a supplier creates a sub-account under 2111', () async {
      final partyId = await db.insertParty(const PartiesCompanion(
        name: Value('مورد اختبار'),
        isCustomer: Value(false),
        isSupplier: Value(true),
      ));

      final party = await db.getPartyById(partyId);
      expect(party!.accountId, isNotNull);

      final sub = await db.getAccountById(party.accountId!);
      expect(sub!.code, startsWith('2111-'),
          reason: 'sub-account code must mirror the seeded AP parent');

      final parent = await db.getAccountById(sub.parentId!);
      expect(parent!.code, '2111');
    });

    test('inserting a customer-AND-supplier creates ONE sub-account under 1121 '
        '(AR side wins, matching legacy convention)', () async {
      final partyId = await db.insertParty(const PartiesCompanion(
        name: Value('عميل ومورد'),
        isCustomer: Value(true),
        isSupplier: Value(true),
      ));

      final party = await db.getPartyById(partyId);
      final sub = await db.getAccountById(party!.accountId!);
      expect(sub!.code, startsWith('1121-'),
          reason: 'when both roles set, party_dao routes to the AR parent');
    });

    test('phantom 1201/2101 stay absent after party creation', () async {
      await db.insertParty(const PartiesCompanion(
        name: Value('عميل ١'),
        isCustomer: Value(true),
      ));
      await db.insertParty(const PartiesCompanion(
        name: Value('مورد ١'),
        isSupplier: Value(true),
      ));

      final phantom1201 = await db.getAccountByCode('1201');
      final phantom2101 = await db.getAccountByCode('2101');
      expect(phantom1201, isNull);
      expect(phantom2101, isNull);
    });

    test('multiple parties get distinct sub-account codes', () async {
      final ids = <int>[];
      for (var i = 1; i <= 3; i++) {
        ids.add(await db.insertParty(PartiesCompanion(
          name: Value('عميل $i'),
          isCustomer: const Value(true),
        )));
      }

      final accountCodes = <String>{};
      for (final id in ids) {
        final p = await db.getPartyById(id);
        final acc = await db.getAccountById(p!.accountId!);
        accountCodes.add(acc!.code);
      }

      expect(accountCodes, hasLength(3),
          reason: 'each customer must get a unique sub-account code');
      // All must share the same prefix.
      expect(accountCodes.every((c) => c.startsWith('1121-')), isTrue);
    });
  });
}
