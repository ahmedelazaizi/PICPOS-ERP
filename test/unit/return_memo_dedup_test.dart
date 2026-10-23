// Feature 012 / Issue M-DUP-PRET — return-memo dedup regression guard.
//
// Reproduces the legacy mirror state where the local seed
// (lib/data/repositories/purchases_repository_impl.dart:407-480) wrote a
// memo using the LOCAL default safe AND the server's authoritative memo
// (different safeId) was inserted by SafeTransactionSyncStrategy via the
// old safeId-keyed dedup → both rows survived → كشف حساب المورد showed
// the return twice.
//
// The fix is two-pronged:
//   1. SafeTransactionSyncStrategy now dedups return memos by
//      (referenceType, referenceId, partyId), so future server pulls
//      collapse onto the existing local seed.
//   2. ReturnMemoDedupExtension.mergeDuplicateReturnMemos() removes
//      legacy duplicates already on disk.
//
// This test covers BOTH paths.

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/data/database/extensions/return_memo_dedup_extension.dart';
import 'package:picpos_erp/services/sync/strategies/safe_transaction_sync_strategy.dart';

void main() {
  late AppDatabase db;
  late int safeLocalId;
  late int safeServerId;
  late int supplierId;

  setUp(() async {
    db = AppDatabase.forTesting();
    safeLocalId = await db.into(db.safes).insert(
          SafesCompanion.insert(
            name: 'الخزينة المحلية',
            safeType: const Value('cash'),
          ),
        );
    safeServerId = await db.into(db.safes).insert(
          SafesCompanion.insert(
            name: 'خزينة الخادم',
            safeType: const Value('cash'),
          ),
        );
    supplierId = await db.into(db.parties).insert(
          PartiesCompanion.insert(
            name: 'مورد تجريبي',
            isSupplier: const Value(true),
          ),
        );
  });

  tearDown(() => db.close());

  group('ReturnMemoDedupExtension', () {
    test('clean DB: dryRun returns 0 and merge is a no-op', () async {
      expect(await db.dryRunDuplicateReturnMemos(), 0);
      expect(await db.mergeDuplicateReturnMemos(), 0);
    });

    test('collapses (refType, refId, partyId) duplicates and prefers '
        'the server voucher (non-PRET-LOC) survivor', () async {
      // Mirror's local seed — uses PRET-LOC-* placeholder voucher.
      final localMemoId = await db.into(db.safeTransactions).insert(
            SafeTransactionsCompanion.insert(
              voucherNumber: 'PRET-LOC-42',
              safeId: safeLocalId,
              transactionType: 'memo',
              category: 'purchase_return_balance',
              amount: 100.0,
              balanceAfter: 0.0,
              referenceType: const Value('purchase_return'),
              referenceId: const Value(42),
              partyId: Value(supplierId),
              description: const Value('local seed'),
            ),
          );
      // Server's authoritative memo — different safe, real voucher.
      final serverMemoId = await db.into(db.safeTransactions).insert(
            SafeTransactionsCompanion.insert(
              voucherNumber: 'PRET-7',
              safeId: safeServerId,
              transactionType: 'memo',
              category: 'purchase_return_balance',
              amount: 100.0,
              balanceAfter: 0.0,
              referenceType: const Value('purchase_return'),
              referenceId: const Value(42),
              partyId: Value(supplierId),
              description: const Value('server authoritative'),
            ),
          );

      expect(await db.dryRunDuplicateReturnMemos(), 1);

      final removed = await db.mergeDuplicateReturnMemos();
      expect(removed, 1);

      // Server memo survives; local placeholder is gone.
      final survivor = await (db.select(db.safeTransactions)
            ..where((t) => t.id.equals(serverMemoId)))
          .getSingleOrNull();
      expect(survivor, isNotNull);
      final dropped = await (db.select(db.safeTransactions)
            ..where((t) => t.id.equals(localMemoId)))
          .getSingleOrNull();
      expect(dropped, isNull);
    });

    test('does not touch legitimate distinct returns for the same supplier',
        () async {
      // Two purchase returns (different invoice ids) for the same
      // supplier — both must survive.
      await db.into(db.safeTransactions).insert(
            SafeTransactionsCompanion.insert(
              voucherNumber: 'PRET-1',
              safeId: safeLocalId,
              transactionType: 'memo',
              category: 'purchase_return_balance',
              amount: 50.0,
              balanceAfter: 0.0,
              referenceType: const Value('purchase_return'),
              referenceId: const Value(1),
              partyId: Value(supplierId),
            ),
          );
      await db.into(db.safeTransactions).insert(
            SafeTransactionsCompanion.insert(
              voucherNumber: 'PRET-2',
              safeId: safeLocalId,
              transactionType: 'memo',
              category: 'purchase_return_balance',
              amount: 75.0,
              balanceAfter: 0.0,
              referenceType: const Value('purchase_return'),
              referenceId: const Value(2),
              partyId: Value(supplierId),
            ),
          );
      expect(await db.dryRunDuplicateReturnMemos(), 0);
      expect(await db.mergeDuplicateReturnMemos(), 0);
      final all = await db.select(db.safeTransactions).get();
      expect(all.where((r) => r.category == 'purchase_return_balance').length, 2);
    });

    test('idempotent — second call returns 0', () async {
      await db.into(db.safeTransactions).insert(
            SafeTransactionsCompanion.insert(
              voucherNumber: 'PRET-LOC-1',
              safeId: safeLocalId,
              transactionType: 'memo',
              category: 'purchase_return_balance',
              amount: 10.0,
              balanceAfter: 0.0,
              referenceType: const Value('purchase_return'),
              referenceId: const Value(1),
              partyId: Value(supplierId),
            ),
          );
      await db.into(db.safeTransactions).insert(
            SafeTransactionsCompanion.insert(
              voucherNumber: 'PRET-1',
              safeId: safeServerId,
              transactionType: 'memo',
              category: 'purchase_return_balance',
              amount: 10.0,
              balanceAfter: 0.0,
              referenceType: const Value('purchase_return'),
              referenceId: const Value(1),
              partyId: Value(supplierId),
            ),
          );
      expect(await db.mergeDuplicateReturnMemos(), 1);
      expect(await db.mergeDuplicateReturnMemos(), 0);
    });
  });

  group('SafeTransactionSyncStrategy: return-memo dedup '
      '(refType, refId, partyId)', () {
    test('server memo for the same (refType, refId, partyId) updates the '
        'local placeholder instead of inserting a duplicate', () async {
      // Mirror's local seed lands first.
      final localMemoId = await db.into(db.safeTransactions).insert(
            SafeTransactionsCompanion.insert(
              voucherNumber: 'PRET-LOC-99',
              safeId: safeLocalId,
              transactionType: 'memo',
              category: 'purchase_return_balance',
              amount: 200.0,
              balanceAfter: 0.0,
              referenceType: const Value('purchase_return'),
              referenceId: const Value(99),
              partyId: Value(supplierId),
              description: const Value('local seed'),
            ),
          );

      // Server pulls back the authoritative row — different safeId,
      // different voucher, no globalId on the local row to match against.
      final strategy = SafeTransactionSyncStrategy(db);
      // Pick a server-side id that does NOT collide with the local row.
      // SafeTransactionSyncStrategy's serverId-match check would short-
      // circuit on (id == localMemoId) and update deletedAt only,
      // which is not the path we want to exercise. Use localMemoId + 100
      // to force the new (refType, refId, partyId) dedup branch.
      final fabricatedServerId = localMemoId + 100;
      await strategy.syncFromJson({
        'transactions': [
          {
            'id': fabricatedServerId,
            'voucherNumber': 'PRET-7',
            'safeId': safeServerId,
            'transactionType': 'memo',
            'category': 'purchase_return_balance',
            'amount': 200.0,
            'balanceAfter': 0.0,
            'referenceType': 'purchase_return',
            'referenceId': 99,
            'partyId': supplierId,
            'description': 'server authoritative',
            'globalId': '019dfc99-aaaa-bbbb-cccc-000000000001',
            'createdAt': DateTime.now().toIso8601String(),
          },
        ],
      });

      // Exactly ONE memo row for this (refType, refId, partyId).
      final memos = await (db.select(db.safeTransactions)
            ..where((t) =>
                t.referenceType.equals('purchase_return') &
                t.referenceId.equals(99) &
                t.partyId.equals(supplierId))
            ..orderBy([(t) => OrderingTerm.asc(t.id)]))
          .get();
      expect(memos, hasLength(1),
          reason: 'server pull must dedup against the local placeholder');
      // Survivor is the local row — but updated with the server's
      // identifiers (voucher number, safeId, globalId).
      expect(memos.first.id, localMemoId);
      expect(memos.first.voucherNumber, 'PRET-7');
      expect(memos.first.safeId, safeServerId);
      expect(memos.first.globalId, '019dfc99-aaaa-bbbb-cccc-000000000001');
    });

    // Spec 136 ISS-7 — MULTIPLE partial returns on the SAME invoice.
    test('two server memos for the same (refType, refId, partyId) with '
        'DISTINCT globalIds are kept as two rows (not collapsed)', () async {
      final strategy = SafeTransactionSyncStrategy(db);
      // A second device with NO local placeholders pulls two return memos for
      // the same purchase invoice (refId=99) — two partial returns, each with
      // its own per-event globalId. Pre-fix the (refType,refId,partyId) merge
      // collapsed the second into the first; the gid-scoped match must now
      // insert both.
      await strategy.syncFromJson({
        'transactions': [
          {
            'id': 5001,
            'voucherNumber': 'PRET-A',
            'safeId': safeServerId,
            'transactionType': 'memo',
            'category': 'purchase_return_balance',
            'amount': 45.0,
            'balanceAfter': 0.0,
            'referenceType': 'purchase_return',
            'referenceId': 99,
            'partyId': supplierId,
            'description': 'return #1',
            'globalId': '019e8200-0000-7000-8000-00000000aaaa',
            'createdAt': DateTime.now().toIso8601String(),
          },
          {
            'id': 5002,
            'voucherNumber': 'PRET-B',
            'safeId': safeServerId,
            'transactionType': 'memo',
            'category': 'purchase_return_balance',
            'amount': 105.0,
            'balanceAfter': 0.0,
            'referenceType': 'purchase_return',
            'referenceId': 99,
            'partyId': supplierId,
            'description': 'return #2',
            'globalId': '019e8200-0000-7000-8000-00000000bbbb',
            'createdAt': DateTime.now().toIso8601String(),
          },
        ],
      });

      final memos = await (db.select(db.safeTransactions)
            ..where((t) =>
                t.referenceType.equals('purchase_return') &
                t.referenceId.equals(99) &
                t.partyId.equals(supplierId))
            ..orderBy([(t) => OrderingTerm.asc(t.id)]))
          .get();
      expect(memos, hasLength(2),
          reason: 'two distinct return events must both survive — distinct '
              'per-event globalIds are not the same logical row');
      expect(
        memos.map((m) => m.globalId).toSet(),
        {
          '019e8200-0000-7000-8000-00000000aaaa',
          '019e8200-0000-7000-8000-00000000bbbb',
        },
      );
    });
  });
}
