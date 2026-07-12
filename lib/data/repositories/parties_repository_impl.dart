import 'package:drift/drift.dart';
import '../database/database.dart';
import '../../domain/repositories/parties_repository.dart';

/// Data-layer implementation of IPartiesRepository
/// Delegates all operations to the Drift AppDatabase DAO extensions.
class PartiesRepositoryImpl implements IPartiesRepository {
  final AppDatabase _db;

  PartiesRepositoryImpl(this._db);

  @override
  Stream<List<Party>> watchCustomers() => _db.watchCustomers();

  @override
  Stream<List<Party>> watchAllCustomersForLookup() =>
      _db.watchAllCustomersForLookup();

  @override
  Stream<List<Party>> watchSuppliers() => _db.watchSuppliers();

  @override
  Stream<List<Party>> watchDeliveryParties() => _db.watchDeliveryParties();

  @override
  Stream<List<Party>> watchAllParties() => _db.watchAllParties();

  @override
  Stream<List<Party>> watchAllPartiesForBranches(Set<int>? allowedBranchIds) =>
      _db.watchAllPartiesForBranches(allowedBranchIds);

  @override
  Stream<List<Party>> watchCustomersForBranches(Set<int>? allowedBranchIds) =>
      _db.watchCustomersForBranches(allowedBranchIds);

  @override
  Stream<List<Party>> watchSuppliersForBranches(Set<int>? allowedBranchIds) =>
      _db.watchSuppliersForBranches(allowedBranchIds);

  @override
  Future<List<Party>> getSuppliers() => _db.getSuppliers();

  @override
  Future<Party?> getPartyById(int id) => _db.getPartyById(id);

  @override
  Stream<List<Party>> searchParties(String query) => _db.searchParties(query);

  @override
  Future<int> insertParty(PartiesCompanion party) => _db.insertParty(party);

  @override
  Future<bool> updateParty(Party party) => _db.updateParty(party);

  @override
  Future<void> deleteParty(int partyId) => _db.deleteParty(partyId);

  @override
  Future<int> hardDeleteParty(int partyId) => _db.hardDeleteParty(partyId);

  @override
  Future<void> adjustPartyBalance(int partyId, double amount) =>
      _db.adjustPartyBalance(partyId, amount);

  @override
  Future<bool> partyHasTransactions(int partyId) =>
      _db.partyHasTransactions(partyId);

  @override
  Future<List<Party>> getPartiesWithBalance({bool? isCustomer}) =>
      _db.getPartiesWithBalance(isCustomer: isCustomer);

  @override
  Future<double> getTotalReceivables() => _db.getTotalReceivables();

  @override
  Future<double> getTotalPayables() => _db.getTotalPayables();

  @override
  Future<PartySummary> getPartySummary(int partyId) =>
      _db.getPartySummary(partyId);

  @override
  Future<Party?> getPartyByName(String name, bool isSupplier) =>
      _db.getPartyByName(name, isSupplier);

  @override
  Future<List<PartyStatementEntry>> getPartyStatement(
    int partyId, {
    DateTime? fromDate,
    DateTime? toDate,
    int? branchId,
  }) => _db.getPartyStatement(partyId, fromDate: fromDate, toDate: toDate, branchId: branchId);

  @override
  Future<List<SafeTransactionData>> getPartyTransactions(int partyId) =>
      _db.getPartyTransactions(partyId);

  @override
  Future<List<Party>> searchCustomerByPhone(String phone) =>
      _db.searchCustomerByPhone(phone);

  @override
  Future<List<Party>> getAllPartiesList() =>
      (_db.select(_db.parties)..where((p) => p.isActive.equals(true))).get();

  @override
  Future<double> getCalculatedPartyBalance(int partyId) async {
    // Sales invoices increase customer balance (they owe us)
    final salesResult = await _db.customSelect(
      'SELECT COALESCE(SUM(total - paid), 0) as receivable '
      'FROM sales_invoices '
      'WHERE customer_id = ? AND status != ?',
      variables: [Variable(partyId), const Variable('cancelled')],
      readsFrom: {_db.salesInvoices},
    ).getSingle();

    // Purchase invoices increase supplier balance (we owe them)
    final purchaseResult = await _db.customSelect(
      'SELECT COALESCE(SUM(total - paid), 0) as payable '
      'FROM purchase_invoices '
      'WHERE supplier_id = ? AND status != ?',
      variables: [Variable(partyId), const Variable('cancelled')],
      readsFrom: {_db.purchaseInvoices},
    ).getSingle();

    // Receipt vouchers reduce customer balance (they paid us)
    final receiptsResult = await _db.customSelect(
      'SELECT COALESCE(SUM(amount), 0) as total_receipts '
      'FROM safe_transactions '
      'WHERE party_id = ? AND transaction_type = ?',
      variables: [Variable(partyId), const Variable('receipt')],
      readsFrom: {_db.safeTransactions},
    ).getSingle();

    // Payment vouchers reduce supplier balance (we paid them)
    final paymentsResult = await _db.customSelect(
      'SELECT COALESCE(SUM(amount), 0) as total_payments '
      'FROM safe_transactions '
      'WHERE party_id = ? AND transaction_type = ?',
      variables: [Variable(partyId), const Variable('payment')],
      readsFrom: {_db.safeTransactions},
    ).getSingle();

    final receivable =
        (salesResult.data['receivable'] as num?)?.toDouble() ?? 0.0;
    final payable =
        (purchaseResult.data['payable'] as num?)?.toDouble() ?? 0.0;
    final receipts =
        (receiptsResult.data['total_receipts'] as num?)?.toDouble() ?? 0.0;
    final payments =
        (paymentsResult.data['total_payments'] as num?)?.toDouble() ?? 0.0;

    // Net balance: what the party owes us (positive) or we owe them (negative)
    return (receivable - receipts) - (payable - payments);
  }

  @override
  Future<void> updatePartyBalance(int partyId, double balance) async {
    await (_db.update(_db.parties)..where((p) => p.id.equals(partyId))).write(
      PartiesCompanion(balance: Value(balance)),
    );
  }

  @override
  Future<List<Party>> getParties({bool? isCustomer, bool? isSupplier}) {
    final query = _db.select(_db.parties);
    if (isCustomer != null) {
      query.where((p) => p.isCustomer.equals(isCustomer));
    }
    if (isSupplier != null) {
      query.where((p) => p.isSupplier.equals(isSupplier));
    }
    return query.get();
  }
}
