import '../../data/database/database.dart';

/// Parties repository interface
///
/// Defines the contract for customer/supplier operations.
abstract class IPartiesRepository {
  /// Watch all customers
  Stream<List<Party>> watchCustomers();

  /// Watch every party flagged as a customer regardless of `isActive`.
  /// Use for invoice-list name-lookup maps where every FK must resolve.
  Stream<List<Party>> watchAllCustomersForLookup();

  /// Watch all suppliers
  Stream<List<Party>> watchSuppliers();

  /// Watch all delivery companies
  Stream<List<Party>> watchDeliveryParties();

  /// Watch all parties
  Stream<List<Party>> watchAllParties();

  /// Branch-scoped variants — pass `null` for full access (admin), or
  /// the set returned by [branchScopeProvider] to hide rows tagged for
  /// branches the current user can't see. See PartyDao for the
  /// is_global / branch_ids CSV semantics.
  Stream<List<Party>> watchAllPartiesForBranches(Set<int>? allowedBranchIds);
  Stream<List<Party>> watchCustomersForBranches(Set<int>? allowedBranchIds);
  Stream<List<Party>> watchSuppliersForBranches(Set<int>? allowedBranchIds);

  /// Get suppliers list
  Future<List<Party>> getSuppliers();

  /// Get party by ID
  Future<Party?> getPartyById(int id);

  /// Search parties by query
  Stream<List<Party>> searchParties(String query);

  /// Insert a new party
  Future<int> insertParty(PartiesCompanion party);

  /// Update a party
  Future<bool> updateParty(Party party);

  /// Soft delete a party
  Future<void> deleteParty(int partyId);

  /// Hard delete a party (only without transactions)
  Future<int> hardDeleteParty(int partyId);

  /// Adjust party balance
  Future<void> adjustPartyBalance(int partyId, double amount);

  /// Check if party has transactions
  Future<bool> partyHasTransactions(int partyId);

  /// Get parties with outstanding balances
  Future<List<Party>> getPartiesWithBalance({bool? isCustomer});

  /// Get total receivables
  Future<double> getTotalReceivables();

  /// Get total payables
  Future<double> getTotalPayables();

  /// Get party summary with totals
  Future<PartySummary> getPartySummary(int partyId);

  /// Get party by name
  Future<Party?> getPartyByName(String name, bool isSupplier);

  /// Get party statement
  Future<List<PartyStatementEntry>> getPartyStatement(
    int partyId, {
    DateTime? fromDate,
    DateTime? toDate,
    int? branchId,
  });

  /// Get party transactions
  Future<List<SafeTransactionData>> getPartyTransactions(int partyId);

  /// Search customer by phone number
  Future<List<Party>> searchCustomerByPhone(String phone);

  /// Get all parties (generic)
  Future<List<Party>> getAllPartiesList();

  /// Get calculated balance from movements (PIR Integrity)
  Future<double> getCalculatedPartyBalance(int partyId);

  /// Update party balance directly (Manual adjustment or reconciliation)
  Future<void> updatePartyBalance(int partyId, double balance);

  /// Get parties with optional filters
  Future<List<Party>> getParties({bool? isCustomer, bool? isSupplier});
}
