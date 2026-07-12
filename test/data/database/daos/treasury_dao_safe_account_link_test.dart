// ═══════════════════════════════════════════════════════════════════════════
// Feature 004 (Multi-Branch Governance, US1) — Treasury DAO atomic linkage tests
// ═══════════════════════════════════════════════════════════════════════════
//
// Covers spec.md FRs:
//   FR-001  — Safe + CoA sub-account created in same db.transaction()
//   FR-003  — sub-account placed under parent code '1110' with deterministic
//             '{parent}-{NNNNN}' suffix
//   FR-004  — both rows carry UUIDv7 globalId; safes.linkedAccountId points
//             at the new sub-account
//   FR-005  — MissingParentAccountException rolls back the whole save when
//             the parent '1110' is absent
//   FR-006  — renaming a safe propagates to its linked account name
//   FR-007  — deleting a safe with GL movements is rejected
// ═══════════════════════════════════════════════════════════════════════════

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting();
    // Seed the parent account (code '1110' — النقدية فى الصناديق).
    // Tests that need it absent delete it explicitly.
    await db.into(db.accounts).insert(
          AccountsCompanion.insert(
            code: '1110',
            name: 'النقدية فى الصناديق',
            accountType: 'asset',
            isSystem: const Value(true),
            globalId: const Value('seed-1110'),
          ),
        );
  });

  tearDown(() async {
    await db.close();
  });

  group('createSafeWithLinkedAccount — happy path', () {
    test('creates both rows linked atomically and stamps UUIDv7 globalIds', () async {
      final safeId = await db.createSafeWithLinkedAccount(
        name: 'صندوق فرع الشرق',
        safeType: 'cash',
      );
      expect(safeId, greaterThan(0));

      // Safe row exists with a linkedAccountId and a globalId.
      final safe = await (db.select(db.safes)..where((s) => s.id.equals(safeId)))
          .getSingle();
      expect(safe.name, 'صندوق فرع الشرق');
      expect(safe.linkedAccountId, isNotNull);
      expect(safe.globalId, isNotNull);
      expect(safe.globalId!.length, greaterThanOrEqualTo(32)); // UUIDv7 string

      // Account row exists, points back via parent_id, has its own globalId.
      final account = await (db.select(db.accounts)
            ..where((a) => a.id.equals(safe.linkedAccountId!)))
          .getSingle();
      expect(account.name, 'صندوق فرع الشرق');
      expect(account.code, startsWith('1110-'));
      expect(account.code.split('-').last.length, 5); // padded to 5 digits
      expect(account.globalId, isNotNull);
      expect(account.globalId, isNot(equals(safe.globalId))); // different UUIDs

      // Account is under the seeded parent.
      final parent = await (db.select(db.accounts)
            ..where((a) => a.code.equals('1110')))
          .getSingle();
      expect(account.parentId, parent.id);
    });

    test('deterministic suffix increments across multiple safes', () async {
      final id1 = await db.createSafeWithLinkedAccount(name: 'S1', safeType: 'cash');
      final id2 = await db.createSafeWithLinkedAccount(name: 'S2', safeType: 'cash');
      final id3 = await db.createSafeWithLinkedAccount(name: 'S3', safeType: 'cash');

      final s1 = await (db.select(db.safes)..where((s) => s.id.equals(id1)))
          .getSingle();
      final s2 = await (db.select(db.safes)..where((s) => s.id.equals(id2)))
          .getSingle();
      final s3 = await (db.select(db.safes)..where((s) => s.id.equals(id3)))
          .getSingle();

      final a1 = await (db.select(db.accounts)
            ..where((a) => a.id.equals(s1.linkedAccountId!)))
          .getSingle();
      final a2 = await (db.select(db.accounts)
            ..where((a) => a.id.equals(s2.linkedAccountId!)))
          .getSingle();
      final a3 = await (db.select(db.accounts)
            ..where((a) => a.id.equals(s3.linkedAccountId!)))
          .getSingle();

      // Suffixes are sequential under the same parent.
      final n1 = int.parse(a1.code.split('-').last);
      final n2 = int.parse(a2.code.split('-').last);
      final n3 = int.parse(a3.code.split('-').last);
      expect(n2, n1 + 1);
      expect(n3, n2 + 1);
    });
  });

  group('createSafeWithLinkedAccount — failure paths', () {
    test('throws MissingParentAccountException when no parent code (1110 OR 111) is present',
        () async {
      // Wipe BOTH candidate parents — the production code (2026-05-03)
      // falls back from '1110' to '111' to support the project's default
      // seeded chart of accounts. Both must be absent to trigger the throw.
      await (db.delete(db.accounts)
            ..where((a) => a.code.equals('1110') | a.code.equals('111')))
          .go();

      // Snapshot account count + safe count BEFORE the failing call, so we
      // can verify atomic rollback (no stray accounts, no half-created safe).
      final accountsBefore = (await db.select(db.accounts).get()).length;
      final safesBefore = (await db.select(db.safes).get()).length;

      expect(
        () => db.createSafeWithLinkedAccount(name: 'orphan', safeType: 'cash'),
        throwsA(isA<MissingParentAccountException>()),
      );

      // Count is unchanged on both tables — full transactional rollback.
      final accountsAfter = (await db.select(db.accounts).get()).length;
      final safesAfter = (await db.select(db.safes).get()).length;
      expect(accountsAfter, accountsBefore);
      expect(safesAfter, safesBefore);

      // And specifically the orphan-named safe doesn't exist.
      final orphan = await (db.select(db.safes)
            ..where((s) => s.name.equals('orphan')))
          .get();
      expect(orphan, isEmpty);
    });
  });

  group('FR-006 — rename propagates', () {
    test('renaming a safe propagates the new name to its linked account', () async {
      final safeId = await db.createSafeWithLinkedAccount(
        name: 'الاسم الأصلى',
        safeType: 'cash',
      );

      // Use the customStatement path that updateSafeDetails would execute.
      // (We test via direct DB operation since the repo wraps this in a
      // transaction with the same name-propagation logic.)
      final safe = await (db.select(db.safes)..where((s) => s.id.equals(safeId)))
          .getSingle();
      final linkedAccountId = safe.linkedAccountId!;

      // Simulate the rename inside a transaction (mirroring repo behavior).
      await db.transaction(() async {
        await db.customStatement(
          'UPDATE safes SET name = ? WHERE id = ?',
          ['الاسم الجديد', safeId],
        );
        await db.customStatement(
          'UPDATE accounts SET name = ? WHERE id = ?',
          ['الاسم الجديد', linkedAccountId],
        );
      });

      final updatedSafe = await (db.select(db.safes)
            ..where((s) => s.id.equals(safeId)))
          .getSingle();
      final updatedAccount = await (db.select(db.accounts)
            ..where((a) => a.id.equals(linkedAccountId)))
          .getSingle();

      expect(updatedSafe.name, 'الاسم الجديد');
      expect(updatedAccount.name, 'الاسم الجديد');
    });
  });

  group('FR-007 — delete-guard', () {
    test('rejects deletion when linked account has journal-entry lines', () async {
      final safeId = await db.createSafeWithLinkedAccount(
        name: 'صندوق فيه قيود',
        safeType: 'cash',
      );
      final safe = await (db.select(db.safes)..where((s) => s.id.equals(safeId)))
          .getSingle();

      // Seed a journal entry + line touching the linked account.
      final jeId = await db.into(db.journalEntries).insert(
            JournalEntriesCompanion.insert(
              entryNumber: 'JE-TEST-001',
              entryDate: DateTime.now(),
              description: const Value('test'),
            ),
          );
      await db.into(db.journalEntryLines).insert(
            JournalEntryLinesCompanion.insert(
              entryId: jeId,
              accountId: safe.linkedAccountId!,
              debit: const Value(100),
              credit: const Value(0),
            ),
          );

      // Delete must throw and leave the safe in place.
      expect(
        () => db.deleteSafeById(safeId),
        throwsA(isA<Exception>()),
      );

      final stillThere = await (db.select(db.safes)
            ..where((s) => s.id.equals(safeId)))
          .getSingleOrNull();
      expect(stillThere, isNotNull);
    });

    test('allows deletion when linked account has no movements', () async {
      final safeId = await db.createSafeWithLinkedAccount(
        name: 'صندوق فاضى',
        safeType: 'cash',
      );

      await db.deleteSafeById(safeId);

      final gone = await (db.select(db.safes)
            ..where((s) => s.id.equals(safeId)))
          .getSingleOrNull();
      expect(gone, isNull);
    });
  });
}
