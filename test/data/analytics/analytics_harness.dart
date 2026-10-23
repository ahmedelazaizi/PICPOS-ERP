// Shared fixtures for the analytics DB tests (not a test file itself).
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:picpos_erp/data/database/database.dart';

/// Helpers over an in-memory [AppDatabase.forTesting] (which seeds the
/// standard chart, its default account mappings and a current fiscal year).
class Ledger {
  Ledger(this.db);
  final AppDatabase db;
  int _seq = 0;

  Future<int> idOf(String code) async => (await (db.select(db.accounts)
            ..where((a) => a.code.equals(code)))
          .getSingle())
      .id;

  Future<int> addBranch(String name) =>
      db.into(db.branches).insert(BranchesCompanion.insert(name: name));

  Future<int> addCostCenter(String code) => db
      .into(db.costCenters)
      .insert(CostCentersCompanion.insert(code: code, name: 'CC $code'));

  /// A postable child account under the account with code [parentCode].
  Future<int> addChildAccount(String code, String parentCode, String type,
      {String nature = 'detail'}) async {
    final parent = await idOf(parentCode);
    return db.into(db.accounts).insert(AccountsCompanion.insert(
          code: code,
          name: 'acct $code',
          accountType: type,
          accountNature: Value(nature),
          parentId: Value(parent),
        ));
  }

  Future<void> addParty(String name,
      {required double balance, bool supplier = false}) async {
    await db.into(db.parties).insert(PartiesCompanion.insert(
          name: name,
          isCustomer: Value(!supplier),
          isSupplier: Value(supplier),
          balance: Value(balance),
        ));
  }

  /// Posts a balanced entry. Lines are (accountCode, debit, credit).
  Future<int> post(
    DateTime date,
    List<(String, double, double)> lines, {
    int? branchId,
    bool posted = true,
    bool deleted = false,
    String? refType = 'journal',
  }) async {
    final entryId = await db.into(db.journalEntries).insert(
          JournalEntriesCompanion.insert(
            entryNumber: 'T-${++_seq}',
            entryDate: date,
            isPosted: Value(posted),
            isDeleted: Value(deleted),
            branchId: Value(branchId),
            referenceType: Value(refType),
          ),
        );
    for (final l in lines) {
      await db.into(db.journalEntryLines).insert(
            JournalEntryLinesCompanion.insert(
              entryId: entryId,
              accountId: await idOf(l.$1),
              debit: Value(l.$2),
              credit: Value(l.$3),
            ),
          );
    }
    return entryId;
  }

  Future<int> addFiscalYear(String name, DateTime start, DateTime end) => db
      .into(db.fiscalYears)
      .insert(FiscalYearsCompanion.insert(
          name: name, startDate: start, endDate: end));

  /// Budget on [accountCode] whose 12 monthly lines are [months] (index 0 =
  /// fiscal month 1); months not listed are 0.
  Future<int> addBudget(
    int fiscalYearId,
    String accountCode,
    Map<int, double> months, {
    int? costCenterId,
  }) async {
    final id = await db.createBudget(
      fiscalYearId: fiscalYearId,
      accountId: await idOf(accountCode),
      annualAmount: 0,
      costCenterId: costCenterId,
    );
    for (var m = 1; m <= 12; m++) {
      await (db.update(db.budgetLines)
            ..where((l) => l.budgetId.equals(id) & l.month.equals(m)))
          .write(BudgetLinesCompanion(plannedAmount: Value(months[m] ?? 0)));
    }
    return id;
  }
}
