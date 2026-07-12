import '../database/database.dart';
import 'base_repository.dart';

/// Repository for party (customer/supplier) operations
class PartyRepository extends BaseRepository<Party> {
  PartyRepository(super.db);

  @override
  Stream<List<Party>> watchAll() {
    return (db.select(
      db.parties,
    )..where((p) => p.isActive.equals(true))).watch();
  }

  @override
  Future<Party?> getById(int id) => db.getPartyById(id);

  /// Watch customers only
  Stream<List<Party>> watchCustomers() => db.watchCustomers();

  /// Watch suppliers only
  Stream<List<Party>> watchSuppliers() => db.watchSuppliers();

  /// Insert new party
  Future<int> insert(PartiesCompanion party) => db.insertParty(party);

  /// Update party
  Future<bool> update(Party party) => db.updateParty(party);

  /// Delete party
  Future<void> delete(int id) => db.deleteParty(id);

  /// Search parties by name
  Future<List<Party>> search(
    String query, {
    bool? isCustomer,
    bool? isSupplier,
  }) async {
    final allParties = await (db.select(
      db.parties,
    )..where((p) => p.isActive.equals(true))).get();

    return allParties.where((p) {
      final nameMatch = p.name.toLowerCase().contains(query.toLowerCase());
      final customerMatch = isCustomer == null || p.isCustomer == isCustomer;
      final supplierMatch = isSupplier == null || p.isSupplier == isSupplier;
      return nameMatch && customerMatch && supplierMatch;
    }).toList();
  }

  /// Get party balance
  Future<double> getBalance(int partyId) async {
    final party = await getById(partyId);
    return party?.balance ?? 0;
  }
}
