@Tags(['pg'])
library;

import 'package:drift/drift.dart' show Value, Variable;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/data/providers/cash_box_ledger_reconciliation_provider.dart';
import 'package:picpos_erp/data/providers/providers.dart'
    show BranchScope, SafeData, branchScopeProvider, databaseProvider, scopedSafesProvider;

import '../../integration_pg/_support/pg_fixture.dart';

SafeData _toSafeData(Safe safe) => SafeData(
      id: safe.id,
      name: safe.name,
      safeType: safe.safeType,
      balance: safe.balance,
      isDefault: safe.isDefault,
      isActive: safe.isActive,
      bankName: safe.bankName,
      accountNumber: safe.accountNumber,
      costCenterId: safe.costCenterId,
      branchId: safe.branchId,
      linkedAccountId: safe.linkedAccountId,
    );

const _pgSkip = 'requires a task-owned PG_TEST_DSN';

void main() {
  test('PostgreSQL keeps operational expense and cheque cash links',
      skip: _pgSkip, timeout: const Timeout(Duration(minutes: 5)), () async {
    final fixture = await bootPgTestSchema();
    addTearDown(fixture.tearDown);
    final db = fixture.db;
    await db.customSelect('SELECT 1').get();
    await db.syncDefaultAccounts();

    final roleId = await db.into(db.roles).insert(
      RolesCompanion.insert(name: 'phase6b_pg_cash_links'),
    );
    final userId = await db.createUser(
      username: 'phase6b_pg_cash_links',
      password: 'phase6b-pw',
      displayName: 'Phase 6B',
      roleId: roleId,
    );
    final cashSafe = await db.getDefaultSafeByType('cash');
    final safeAccountId = cashSafe!.linkedAccountId!;
    final safeId = cashSafe.id;

    final expenseCategory = await db.createExpenseCategory(
      name: 'Phase6B PG expense',
    );
    final expenseId = await db.recordAndPostOperationalExpense(
      categoryId: expenseCategory,
      amount: 50,
      expenseDate: DateTime.now(),
      description: 'Phase6B PG expense',
      expenseAccountCode: '6214',
      userId: userId,
      paymentMethod: 'cash',
      safeId: safeId,
    );

    final customerId = await db.insertParty(
      PartiesCompanion.insert(
        name: 'Phase6B PG customer',
        isCustomer: const Value(true),
      ),
    );
    final paperId = await db.createCommercialPaper(
      paperNumber: 'P6B-PG-40',
      type: 'cheque',
      direction: 'received',
      partyId: customerId,
      amount: 40,
      issueDate: DateTime.now(),
      dueDate: DateTime.now(),
    );
    await db.changePaperStatus(
      paperId: paperId,
      newStatus: 'cashed',
      changedBy: userId,
    );

    final rows = await db.customSelect(
      'SELECT e.reference_type, e.reference_id, l.debit, l.credit, l.account_id '
      'FROM journal_entries e '
      'JOIN journal_entry_lines l ON l.entry_id = e.id '
      'WHERE e.is_deleted = false AND '
      '((e.reference_type = ? AND e.reference_id = ?) OR '
      '(e.reference_type = ? AND e.reference_id = ?))',
      variables: [
        const Variable<String>('op_expense'),
        Variable<int>(expenseId),
        const Variable<String>('commercial_paper'),
        Variable<int>(paperId),
      ],
    ).get();
    expect(rows.any((r) =>
        r.data['account_id'] == safeAccountId &&
        (r.data['credit'] as num).toDouble() == 50), isTrue);
    expect(rows.any((r) =>
        r.data['account_id'] == safeAccountId &&
        (r.data['debit'] as num).toDouble() == 40), isTrue);
    final safe = await db.getSafeById(safeId);
    expect(safe!.balance, -10);

    final providerContainer = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      branchScopeProvider.overrideWith((ref) async => const BranchScope.fullAccess()),
      scopedSafesProvider.overrideWith(
        (ref) => Stream.value([_toSafeData(safe)]),
      ),
    ]);
    addTearDown(providerContainer.dispose);
    final comparisons = await providerContainer.read(
      cashBoxLedgerReconciliationProvider.future,
    );
    final cashAccount = await db.getAccountById(safeAccountId);
    final comparison = comparisons.singleWhere(
      (row) => row.accountCode == cashAccount!.code,
    );
    expect(comparison.difference, 0);
  });
}
