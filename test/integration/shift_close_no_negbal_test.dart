// Feature 041 — End-to-end guard against the v122 NEG-BAL regression.
//
// Field scenario (2026-05-12, JE-2026-00063): a CLIENT install paired to a
// SERVER closed a shift with a small cash sale; the SERVER's `safes.balance`
// drifted to `-amount` and the JE viewer displayed negative debit/credit
// values with empty line cells. Root cause: two duplicate `shift_closing`
// rows on the server — one from `/api/shifts/close` (server's own
// `_closeShiftSafes`) and one from the client mirror's
// `/api/safes/transaction`. Each side minted its own random UUIDv7 globalId
// and used its own local shift id as `referenceId`, so neither of the two
// existing dedup checks matched.
//
// These tests pin the post-Feature-041 guarantee at the data layer:
//   1. A single close produces exactly ONE safe_txn row + ONE balanced JE.
//   2. Replaying the close (outbox retry case) stays idempotent.
//   3. When the "other side" already wrote a `shift_closing` row with the
//      deterministic globalId but a different referenceId, the local close
//      detects the duplicate and skips — safe balance stays at 0, NOT -amount.

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/core/utils/uuid_v7.dart';
import 'package:ural_erp/data/database/database.dart';

void main() {
  late AppDatabase db;
  late int userId;
  late int branchId;
  late int safeId;
  late String safeGlobalId;

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.syncDefaultAccounts();

    branchId = await db.into(db.branches).insert(
          BranchesCompanion.insert(
            name: 'BR-041-INT',
            globalId: const Value('gid-br-041-int'),
          ),
        );

    final roleId = await db.into(db.roles).insert(
          RolesCompanion.insert(
            name: 'cashier-041-int',
            isSystemRole: const Value(false),
          ),
        );
    userId = await db.createUser(
      username: 'cashier_041_int',
      password: 'pw',
      displayName: 'F041-INT',
      roleId: roleId,
    );
    await db.into(db.userBranchAccess).insert(
          UserBranchAccessCompanion.insert(userId: userId, branchId: branchId),
        );

    safeGlobalId = 'gid-safe-041-int';
    safeId = await db.into(db.safes).insert(
          SafesCompanion.insert(
            name: 'cash-041-int',
            branchId: Value(branchId),
            balance: const Value(0),
            safeType: const Value('cash'),
            globalId: Value(safeGlobalId),
          ),
        );
  });

  tearDown(() async => db.close());

  test('open → cash sale +5 → close: safe balance = 0, JE amounts positive',
      () async {
    // Repro of the v122 field cycle, condensed: one shift, one sale, one
    // close. Pre-fix saw safes.balance drift to -5 on the server side.
    const shiftGlobalId = 'gid-shift-041-INT-A';
    final shiftId = await db.openShift(userId, 0, globalId: shiftGlobalId);

    await db.createReceiptVoucher(
      amount: 5.0,
      category: 'sales',
      safeId: safeId,
      userId: userId,
    );

    final preCloseSafe = await (db.select(db.safes)
          ..where((s) => s.id.equals(safeId)))
        .getSingle();
    expect(preCloseSafe.balance, 5.0,
        reason: 'sanity: cash sale should put 5.0 in the safe before close');

    await db.closeShiftWithAudit(shiftId, 5.0);

    final postSafe = await (db.select(db.safes)
          ..where((s) => s.id.equals(safeId)))
        .getSingle();
    expect(postSafe.balance, 0.0,
        reason: 'AC-1: safe.balance must be zero after a clean close cycle.');

    // AC-2 — exactly ONE shift_closing row per (safe, shift).
    final closingRows = await (db.select(db.safeTransactions)
          ..where((t) =>
              t.safeId.equals(safeId) &
              t.referenceType.equals('shift_closing')))
        .get();
    expect(closingRows.length, 1);
    expect(
      closingRows.first.globalId,
      UuidV7.deriveShiftClosingGlobalId(
        shiftGlobalId: shiftGlobalId,
        safeGlobalId: safeGlobalId,
      ),
      reason: 'globalId is the deterministic UUIDv5 derived from shift+safe.',
    );

    // AC-3 — JE lines for shift_closing carry POSITIVE debit + credit
    // (the field bug rendered them negative + empty in the journal viewer).
    final je = await (db.select(db.journalEntries)
          ..where((j) =>
              j.referenceType.equals('shift_closing') &
              j.referenceId.equals(closingRows.first.id)))
        .getSingleOrNull();
    expect(je, isNotNull, reason: 'shift_closing must post a balanced JE');
    final lines = await (db.select(db.journalEntryLines)
          ..where((l) => l.entryId.equals(je!.id)))
        .get();
    expect(lines.length, 2, reason: 'standard double-entry: debit + credit');
    for (final l in lines) {
      expect(l.debit, isNonNegative,
          reason: 'AC-3: line debit must NOT be negative');
      expect(l.credit, isNonNegative,
          reason: 'AC-3: line credit must NOT be negative');
    }
    final totalDebit = lines.fold<double>(0, (a, l) => a + l.debit);
    final totalCredit = lines.fold<double>(0, (a, l) => a + l.credit);
    expect(totalDebit, closeTo(5.0, 0.001));
    expect(totalCredit, closeTo(5.0, 0.001));
  });

  test('Spec 136: linked-account safe derives close globalId from the account '
      'code (cross-device stable), not the divergent safe.globalId', () async {
    // Field bug: safes are created independently on mirror vs server, so
    // safe.globalId differs per device → each side derived a different
    // shift_closing globalId → dedup missed → duplicate "إقفال وردية" JEs.
    // Fix: derive the key from the safe's LINKED ACCOUNT CODE (synced master
    // data) + name, which is identical on both devices.
    final acctId = await db.into(db.accounts).insert(
          AccountsCompanion.insert(
            code: '111-S136',
            name: 'صندوق مربوط',
            accountType: 'asset',
            globalId: const Value('acc-gid-s136'),
          ),
        );
    const linkedSafeGid = 'gid-safe-LINKED-s136';
    final linkedSafeId = await db.into(db.safes).insert(
          SafesCompanion.insert(
            name: 'صندوق مربوط',
            branchId: Value(branchId),
            balance: const Value(0),
            safeType: const Value('cash'),
            globalId: const Value(linkedSafeGid),
            linkedAccountId: Value(acctId),
          ),
        );

    const shiftGlobalId = 'gid-shift-s136-linked';
    final shiftId = await db.openShift(userId, 0, globalId: shiftGlobalId);
    await db.createReceiptVoucher(
      amount: 9.0,
      category: 'sales',
      safeId: linkedSafeId,
      userId: userId,
    );
    await db.closeShiftWithAudit(shiftId, 9.0);

    final closingRows = await (db.select(db.safeTransactions)
          ..where((t) =>
              t.safeId.equals(linkedSafeId) &
              t.referenceType.equals('shift_closing')))
        .get();
    expect(closingRows.length, 1);
    // Key derives from the linked account code + name (stable across devices).
    expect(
      closingRows.first.globalId,
      UuidV7.deriveShiftClosingGlobalId(
        shiftGlobalId: shiftGlobalId,
        safeGlobalId: 'acct:111-S136:صندوق مربوط',
      ),
      reason: 'Spec 136: close key must come from the linked account code',
    );
    // And NOT from the divergent safe.globalId (the old, duplicate-prone key).
    expect(
      closingRows.first.globalId,
      isNot(UuidV7.deriveShiftClosingGlobalId(
        shiftGlobalId: shiftGlobalId,
        safeGlobalId: linkedSafeGid,
      )),
      reason: 'must no longer key on safe.globalId',
    );
  });

  test('AC-4: replaying the close 3× still produces ONE safe_txn + ONE JE',
      () async {
    const shiftGlobalId = 'gid-shift-041-INT-B';
    final shiftId = await db.openShift(userId, 0, globalId: shiftGlobalId);
    await db.createReceiptVoucher(
      amount: 12.5,
      category: 'sales',
      safeId: safeId,
      userId: userId,
    );

    await db.closeShiftWithAudit(shiftId, 12.5); // real-time
    await db.closeShiftWithAudit(shiftId, 12.5); // outbox retry #1
    await db.closeShiftWithAudit(shiftId, 12.5); // outbox retry #2

    final closingRows = await (db.select(db.safeTransactions)
          ..where((t) =>
              t.safeId.equals(safeId) &
              t.referenceType.equals('shift_closing')))
        .get();
    expect(closingRows.length, 1,
        reason: 'replay-safety: outbox retries must not duplicate rows');

    final jes = await (db.select(db.journalEntries)
          ..where((j) =>
              j.referenceType.equals('shift_closing') &
              j.referenceId.equals(closingRows.first.id)))
        .get();
    expect(jes.length, 1);

    final safe = await (db.select(db.safes)
          ..where((s) => s.id.equals(safeId)))
        .getSingle();
    expect(safe.balance, 0.0);
  });

  test('cross-side race: "other side" already wrote the deterministic row '
      'with a different referenceId → no duplicate, balance stays 0',
      () async {
    // The exact field condition: server's /api/shifts/close inserted the
    // shift_closing row keyed by SERVER's local shift id (e.g. 999); now
    // the same close is being processed locally with referenceId = the
    // LOCAL shift id (different integer). With Route B.1 both sides derive
    // the same globalId, and the new globalId-based skip catches it.
    const shiftGlobalId = 'gid-shift-041-INT-C';
    final shiftId = await db.openShift(userId, 0, globalId: shiftGlobalId);
    await db.createReceiptVoucher(
      amount: 5.0,
      category: 'sales',
      safeId: safeId,
      userId: userId,
    );

    // Pre-seed the "other side" row: same deterministic globalId, but
    // referenceId is a foreign integer (simulating the SERVER's local
    // shift id) so the legacy (safeId, refType, refId) check misses.
    final deterministicGid = UuidV7.deriveShiftClosingGlobalId(
      shiftGlobalId: shiftGlobalId,
      safeGlobalId: safeGlobalId,
    );
    await db.into(db.safeTransactions).insert(
          SafeTransactionsCompanion.insert(
            voucherNumber: 'OTHER-SIDE-${DateTime.now().millisecondsSinceEpoch}',
            safeId: safeId,
            transactionType: 'withdrawal',
            category: 'shift_closing',
            amount: 5.0,
            balanceAfter: 0,
            referenceType: const Value('shift_closing'),
            referenceId: const Value(999), // foreign id — bypasses old check
            globalId: Value(deterministicGid),
          ),
        );
    // Reflect that the "other side" already zeroed the safe.
    await (db.update(db.safes)..where((s) => s.id.equals(safeId)))
        .write(const SafesCompanion(balance: Value(0)));

    // Now run the close on this side. The dedup must catch the existing
    // row via globalId and skip the second insert + skip the second
    // balance-zero write (which would otherwise post a -5 zeroing
    // transaction and drive balance negative).
    await db.closeShiftWithAudit(shiftId, 5.0);

    final closingRows = await (db.select(db.safeTransactions)
          ..where((t) =>
              t.safeId.equals(safeId) &
              t.referenceType.equals('shift_closing')))
        .get();
    expect(closingRows.length, 1,
        reason: 'globalId dedup must catch the cross-side duplicate');
    expect(closingRows.first.globalId, deterministicGid);

    final safe = await (db.select(db.safes)
          ..where((s) => s.id.equals(safeId)))
        .getSingle();
    expect(safe.balance, 0.0,
        reason: 'AC-1: balance must NOT drift negative under the race');
  });
}
