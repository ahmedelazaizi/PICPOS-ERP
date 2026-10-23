// Spec 067 / SC-004 — Account delete orphan guard regression test.
//
// `deleteAccount(int id)` in lib/data/database/daos/accounting_dao_writes.dart
// MUST refuse to hard-delete an account that has any rows in the 3 audit-
// named child tables: journal_entry_lines.accountId, parties.accountId,
// safes.linkedAccountId. SQLite's FK enforcer would catch the violation,
// but with an opaque English error; the new guards surface table-specific
// Arabic guidance BEFORE the DELETE.
//
// QA finding D5-002 (P0). Companion to bootstrap_admin_guards_test.dart
// (spec 061) and read_filter_gate_predicate_test.dart (spec 064).

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import 'package:picpos_erp/data/database/database.dart';

void main() {
  group('Account delete orphan guard (Spec 067 / SC-004)', () {
    late AppDatabase database;

    setUp(() async {
      database = AppDatabase.forTesting();
    });

    tearDown(() async {
      await database.close();
    });

    // Helper: insert a deletable account with zero balance, no isSystem.
    Future<int> insertOrphanAccount(String code) async {
      return database.into(database.accounts).insert(
            AccountsCompanion.insert(
              code: code,
              name: 'Test Account $code',
              accountType: 'asset',
              accountNature: const Value('debit'),
              normalBalance: const Value('debit'),
              level: const Value(1),
              balance: const Value(0),
              isSystem: const Value(false),
            ),
          );
    }

    test('orphan account with zero balance deletes successfully', () async {
      final id = await insertOrphanAccount('T001');

      // Pre-condition: account exists.
      var found = await database.getAccountById(id);
      expect(found, isNotNull);

      // Act.
      await database.deleteAccount(id);

      // Post-condition: account is gone.
      found = await database.getAccountById(id);
      expect(found, isNull,
          reason: 'orphan account should be removed after deleteAccount');
    });

    test('account with journal_entry_lines reference refuses with Arabic msg',
        () async {
      final accountId = await insertOrphanAccount('T002');

      // Insert a journal entry header first (FK from JEL to JE requires it).
      final jeId = await database.into(database.journalEntries).insert(
            JournalEntriesCompanion.insert(
              entryNumber: 'JE-T002-001',
              entryDate: DateTime.now(),
            ),
          );

      // Insert one journal_entry_line referencing the account.
      await database.into(database.journalEntryLines).insert(
            JournalEntryLinesCompanion.insert(
              entryId: jeId,
              accountId: accountId,
              debit: const Value(0),
              credit: const Value(0),
            ),
          );

      // Act + Assert.
      expect(
        () => database.deleteAccount(accountId),
        throwsA(predicate((e) =>
            e.toString().contains('قيد محاسبي') &&
            e.toString().contains('1'))),
        reason: 'guard must name "قيد محاسبي" AND the count',
      );

      // Post-condition: account still exists.
      final stillThere = await database.getAccountById(accountId);
      expect(stillThere, isNotNull,
          reason: 'account row must be preserved after a refused delete');
    });

    test('account with parties reference refuses with Arabic msg', () async {
      final accountId = await insertOrphanAccount('T003');

      // Insert a party that references the account.
      await database.into(database.parties).insert(
            PartiesCompanion.insert(
              name: 'Test Party',
              accountId: Value(accountId),
            ),
          );

      expect(
        () => database.deleteAccount(accountId),
        throwsA(predicate((e) {
          final msg = e.toString();
          return (msg.contains('عميل') || msg.contains('مورد')) &&
              msg.contains('1');
        })),
        reason: 'guard must name a party-related noun AND the count',
      );

      final stillThere = await database.getAccountById(accountId);
      expect(stillThere, isNotNull);
    });

    test('account with safes reference refuses with Arabic msg', () async {
      final accountId = await insertOrphanAccount('T004');

      await database.into(database.safes).insert(
            SafesCompanion.insert(
              name: 'Test Safe',
              linkedAccountId: Value(accountId),
            ),
          );

      expect(
        () => database.deleteAccount(accountId),
        throwsA(predicate((e) =>
            e.toString().contains('خزنة') &&
            e.toString().contains('1'))),
        reason: 'guard must name "خزنة" AND the count',
      );

      final stillThere = await database.getAccountById(accountId);
      expect(stillThere, isNotNull);
    });

    test('non-existent account id throws "غير موجود"', () async {
      expect(
        () => database.deleteAccount(99999),
        throwsA(predicate(
            (e) => e.toString().contains('الحساب غير موجود'))),
      );
    });
  });
}
