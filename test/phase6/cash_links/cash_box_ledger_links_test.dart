import 'package:drift/drift.dart' show Value, Variable;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/providers/cash_box_ledger_reconciliation_provider.dart';
import 'package:picpos_erp/data/providers/providers.dart'
    show BranchScope, SafeData, branchScopeProvider, databaseProvider, scopedSafesProvider;

import '../../scenarios/scenario_world.dart';

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

void main() {
  late ScenarioWorld world;

  setUp(() async => world = await ScenarioWorld.create());
  tearDown(() => world.dispose());

  Future<double> accountMovement(int accountId, String referenceType) async {
    final row = await world.db.customSelect(
      'SELECT COALESCE(SUM(l.debit - l.credit), 0) AS amount '
      'FROM journal_entry_lines l '
      'JOIN journal_entries e ON e.id = l.entry_id '
      'WHERE e.is_deleted = 0 AND e.reference_type = ? AND l.account_id = ?',
      variables: [
        Variable<String>(referenceType),
        Variable<int>(accountId),
      ],
    ).getSingle();
    return (row.data['amount'] as num).toDouble();
  }

  test('cash operational expense credits selected safe account', () async {
    final safe = await world.db.getSafeById(world.cashSafeId);
    final linkedAccountId = safe!.linkedAccountId!;
    final categoryId = await world.db.createExpenseCategory(name: 'Phase6 cash');

    await world.db.recordAndPostOperationalExpense(
      categoryId: categoryId,
      amount: 50,
      expenseDate: DateTime.now(),
      description: 'Phase6 cash expense',
      expenseAccountCode: '6214',
      userId: world.userId,
      paymentMethod: 'cash',
      safeId: safe.id,
    );

    expect(await accountMovement(linkedAccountId, 'op_expense'), -50);
    final updatedSafe = await world.db.getSafeById(safe.id);
    final account = await world.db.getAccountById(linkedAccountId);
    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(world.db),
      branchScopeProvider.overrideWith((ref) async => const BranchScope.fullAccess()),
      scopedSafesProvider.overrideWith(
        (ref) => Stream.value([_toSafeData(updatedSafe!)]),
      ),
    ]);
    addTearDown(container.dispose);

    final beforeRead = await world.safeBalance(safe.id);
    final comparisons = await container.read(cashBoxLedgerReconciliationProvider.future);
    final linkedComparison = comparisons.singleWhere(
      (comparison) => comparison.accountCode == account!.code,
    );
    expect(linkedComparison.difference, 0);
    expect(comparisons.any((comparison) => comparison.isUnlinkedCashControl), isTrue);
    expect(await world.safeBalance(safe.id), beforeRead);
  });

  test('expense routes to the specifically selected second cash safe', () async {
    final safes = await world.db.select(world.db.safes).get();
    final selected = safes.firstWhere(
      (safe) =>
          safe.id != world.cashSafeId &&
          safe.safeType == 'cash' &&
          safe.linkedAccountId != null,
    );
    final categoryId = await world.db.createExpenseCategory(name: 'Phase6 second cash');

    await world.db.recordAndPostOperationalExpense(
      categoryId: categoryId,
      amount: 30,
      expenseDate: DateTime.now(),
      description: 'Phase6 second cash expense',
      expenseAccountCode: '6214',
      userId: world.userId,
      paymentMethod: 'cash',
      safeId: selected.id,
    );

    expect(await accountMovement(selected.linkedAccountId!, 'op_expense'), -30);
  });

  test('unlinked safe keeps mapped cash-account fallback', () async {
    final unlinkedSafeId = await world.db.into(world.db.safes).insert(
      SafesCompanion.insert(
        name: 'Phase6 unlinked cash',
        safeType: const Value('cash'),
      ),
    );
    final mappedCash = await world.db.getAccountByCode('1111');
    final categoryId = await world.db.createExpenseCategory(name: 'Phase6 fallback');

    await world.db.recordAndPostOperationalExpense(
      categoryId: categoryId,
      amount: 20,
      expenseDate: DateTime.now(),
      description: 'Phase6 fallback expense',
      expenseAccountCode: '6214',
      userId: world.userId,
      paymentMethod: 'cash',
      safeId: unlinkedSafeId,
    );

    expect(await accountMovement(mappedCash!.id, 'op_expense'), -20);
  });

  test('cash fixed-asset purchase uses and moves the linked cash safe', () async {
    final safe = await world.db.getSafeById(world.cashSafeId);
    final assetAccount = await world.db.getAccountByCode('1213');
    final depreciationAccount = await world.db.getAccountByCode('1219');
    final categoryId = await world.db.createAssetCategory(
      name: 'Phase6 assets',
      defaultUsefulLife: 1,
      accountId: assetAccount!.id,
      depreciationAccountId: depreciationAccount!.id,
    );

    await world.db.createFixedAsset(
      code: 'P6-ASSET-1',
      name: 'Phase6 cash asset',
      categoryId: categoryId,
      purchasePrice: 1200,
      purchaseDate: DateTime.now(),
      usefulLifeYears: 1,
    );

    expect(await accountMovement(safe!.linkedAccountId!, 'fixed_asset'), -1200);
    expect(await world.safeBalance(safe.id), -1200);
  });

  test('deposited cheque collection uses its selected bank-safe account', () async {
    final safes = await world.db.select(world.db.safes).get();
    final bankSafe = safes.firstWhere(
      (safe) => safe.safeType == 'bank' && safe.linkedAccountId != null,
    );
    final customerId = await world.addCustomer('Phase6 bank cheque customer');
    final paperId = await world.db.createCommercialPaper(
      paperNumber: 'P6-BANK-30',
      type: 'cheque',
      direction: 'received',
      partyId: customerId,
      amount: 30,
      issueDate: DateTime.now(),
      dueDate: DateTime.now(),
      safeId: bankSafe.id,
    );
    await world.db.changePaperStatus(
      paperId: paperId,
      newStatus: 'deposited',
      changedBy: world.userId,
    );
    await world.db.changePaperStatus(
      paperId: paperId,
      newStatus: 'cashed',
      changedBy: world.userId,
    );

    expect(await accountMovement(bankSafe.linkedAccountId!, 'commercial_paper'), 30);
    expect(await world.safeBalance(bankSafe.id), 30);
  });

  test('direct customer cheque collection credits the cash safe account', () async {
    final safe = await world.db.getSafeById(world.cashSafeId);
    final customerId = await world.addCustomer('Phase6 cheque customer');
    final paperId = await world.db.createCommercialPaper(
      paperNumber: 'P6-CASH-40',
      type: 'cheque',
      direction: 'received',
      partyId: customerId,
      amount: 40,
      issueDate: DateTime.now(),
      dueDate: DateTime.now(),
    );

    await world.db.changePaperStatus(
      paperId: paperId,
      newStatus: 'cashed',
      changedBy: world.userId,
    );

    expect(await accountMovement(safe!.linkedAccountId!, 'commercial_paper'), 40);
  });
}
