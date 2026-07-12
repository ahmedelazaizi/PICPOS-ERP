import '../../repositories/parties_repository.dart';
import '../../../data/database/database.dart';
import 'package:drift/drift.dart';

/// Use case: Manage party (customer/supplier) CRUD operations.
///
/// Validates party data before persisting via the repository.
class ManagePartyUseCase {
  final IPartiesRepository _repo;

  const ManagePartyUseCase(this._repo);

  /// Creates a new party (customer or supplier).
  Future<int> createParty({
    required String name,
    required bool isCustomer,
    String? phone,
    String? address,
    String? notes,
    double balance = 0,
  }) async {
    if (name.trim().isEmpty) {
      throw ArgumentError('اسم الطرف مطلوب');
    }
    return _repo.insertParty(PartiesCompanion.insert(
      name: name.trim(),
      isCustomer: Value(isCustomer),
      phone: Value(phone),
      address: Value(address),
      balance: Value(balance),
    ));
  }

  /// Updates an existing party.
  Future<bool> updateParty(Party party) async {
    if (party.name.trim().isEmpty) {
      throw ArgumentError('اسم الطرف مطلوب');
    }
    return _repo.updateParty(party);
  }

  /// Gets all suppliers.
  Future<List<Party>> getSuppliers() => _repo.getSuppliers();
}
