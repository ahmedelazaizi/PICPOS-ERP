import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';

const _skip = 'audit repro — pending owner approval';

void main() {
  late AppDatabase db;
  late int userId;
  late int customerId;

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.syncDefaultAccounts();
    final roleId = await db
        .into(db.roles)
        .insert(
          RolesCompanion.insert(
            name: 'Bank audit',
            isSystemRole: const Value(false),
          ),
        );
    userId = await db.createUser(
      username: 'bank_audit',
      password: 'test',
      displayName: 'Bank audit',
      roleId: roleId,
    );
    customerId = await db
        .into(db.parties)
        .insert(
          PartiesCompanion.insert(
            name: 'Returned cheque audit customer',
            isCustomer: const Value(true),
          ),
        );
  });

  tearDown(() => db.close());

  test(
    'a bounced received cheque reverses notes receivable once',
    skip: _skip,
    () async {
      const amount = 1500.0;
      final paperId = await db.createCommercialPaper(
        paperNumber: 'AUDIT-BOUNCE-001',
        type: 'cheque',
        direction: 'received',
        partyId: customerId,
        amount: amount,
        issueDate: DateTime(2026, 6, 1),
        dueDate: DateTime(2026, 6, 15),
        globalId: 'audit-bounce-global-001',
      );

      Future<List<Map<String, dynamic>>> entries() async =>
          (await db
                  .customSelect(
                    'SELECT id, reference_type, reference_id FROM journal_entries '
                    'WHERE reference_type = ? AND reference_id = ? ORDER BY id',
                    variables: [
                      Variable<String>('commercial_paper'),
                      Variable<int>(paperId),
                    ],
                    readsFrom: {db.journalEntries},
                  )
                  .get())
              .map((row) => row.data)
              .toList();

      Future<Map<int, double>> netByAccount() async {
        final rows = await db
            .customSelect(
              'SELECT account_id, COALESCE(SUM(debit),0) - COALESCE(SUM(credit),0) AS net '
              'FROM journal_entry_lines WHERE entry_id IN '
              '(SELECT id FROM journal_entries WHERE reference_type = ? AND reference_id = ?) '
              'GROUP BY account_id',
              variables: [
                Variable<String>('commercial_paper'),
                Variable<int>(paperId),
              ],
              readsFrom: {db.journalEntries, db.journalEntryLines},
            )
            .get();
        return {
          for (final row in rows)
            row.data['account_id'] as int: (row.data['net'] as num).toDouble(),
        };
      }

      await db.changePaperStatus(
        paperId: paperId,
        newStatus: 'bounced',
        changedBy: userId,
        notes: 'audit repro',
      );

      final paper = await db.getCommercialPaper(paperId);
      final posted = await entries();
      final notesReceivableCode = await db.accountingDao.getMappedAccountCode(
        'notes_receivable',
        '1123',
      );
      final receivablesCode = await db.accountingDao.getMappedAccountCode(
        'receivables',
        '1121',
      );
      final notesReceivableId = (await db.accountingDao.getAccountByCode(
        notesReceivableCode,
      ))!.id;
      final receivablesId = (await db.accountingDao.getAccountByCode(
        receivablesCode,
      ))!.id;
      final entryIds = posted.map((entry) => entry['id'] as int).toList();
      final postedLines = await (db.select(
        db.journalEntryLines,
      )..where((line) => line.entryId.isIn(entryIds))).get();
      final receiptLines = postedLines
          .where((line) => line.entryId == entryIds.first)
          .toList();
      final bounceLines = postedLines
          .where((line) => line.entryId == entryIds.last)
          .toList();
      final net = await netByAccount();
      final customer = await (db.select(
        db.parties,
      )..where((party) => party.id.equals(customerId))).getSingle();
      final safeTransactions = await db.select(db.safeTransactions).get();

      // ignore: avoid_print
      print(
        '[AUDIT-BANK-BOUNCE] status=${paper?.status} entries=$posted '
        'net=$net customerBalance=${customer.balance} '
        'safeTransactions=${safeTransactions.length}',
      );
      expect(paper?.status, 'bounced');
      expect(posted, hasLength(2), reason: 'receipt + bounce reversal');
      expect(postedLines, hasLength(4));
      expect(receiptLines, hasLength(2));
      expect(
        receiptLines
            .singleWhere((line) => line.accountId == notesReceivableId)
            .debit,
        amount,
      );
      expect(
        receiptLines
            .singleWhere((line) => line.accountId == receivablesId)
            .credit,
        amount,
      );
      expect(bounceLines, hasLength(2));
      expect(
        bounceLines
            .singleWhere((line) => line.accountId == receivablesId)
            .debit,
        amount,
      );
      expect(
        bounceLines
            .singleWhere((line) => line.accountId == notesReceivableId)
            .credit,
        amount,
      );
      expect(net[notesReceivableId], closeTo(0, 0.001));
      expect(net[receivablesId], closeTo(0, 0.001));
      expect(
        customer.balance,
        closeTo(0, 0.001),
        reason: 'bounced receipt restores AR',
      );
      expect(safeTransactions, isEmpty, reason: 'no cash was received');

      await db.changePaperStatus(
        paperId: paperId,
        newStatus: 'bounced',
        changedBy: userId,
        notes: 'idempotent replay',
      );
      expect(
        await entries(),
        hasLength(2),
        reason: 'same status must not repost',
      );
      final customerAfterReplay = await (db.select(
        db.parties,
      )..where((party) => party.id.equals(customerId))).getSingle();
      expect(
        customerAfterReplay.balance,
        closeTo(0, 0.001),
        reason: 'same-status replay must not adjust AR twice',
      );
      expect(await db.select(db.safeTransactions).get(), isEmpty);
    },
  );
}
