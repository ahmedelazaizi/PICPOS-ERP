import '../../domain/repositories/modifier_repository.dart';
import '../database/database.dart' as db;

class ModifierRepositoryImpl implements IModifierRepository {
  final db.AppDatabase _db;

  ModifierRepositoryImpl(this._db);

  @override
  Future<List<db.ModifierGroupData>> getAllGroups() => _db.getAllModifierGroups();

  @override
  Future<void> ensureTables() => _db.ensureModifierTables();

  @override
  Future<void> createGroup({
    required String name,
    required String type,
    required int minSelect,
    required int maxSelect,
    required bool isRequired,
  }) => _db.createModifierGroup(
    name: name,
    type: type,
    minSelect: minSelect,
    maxSelect: maxSelect,
    isRequired: isRequired,
  );

  @override
  Future<void> deleteGroup(int id) => _db.deleteModifierGroup(id);

  @override
  Future<List<db.ModifierItemData>> getItems(int groupId) => _db.getModifierItems(groupId);

  @override
  Future<void> createItem({
    required int groupId,
    required String name,
    required double extraPrice,
    required bool isDefault,
  }) => _db.createModifierItem(
    groupId: groupId,
    name: name,
    extraPrice: extraPrice,
    isDefault: isDefault,
  );

  @override
  Future<void> deleteItem(int id) => _db.deleteModifierItem(id);

  @override
  Future<List<db.Product>> getAllProducts() => _db.getAllProducts();

  @override
  Future<List<db.Category>> getAllCategories() => _db.getAllCategories();

  @override
  Future<List<int>> getLinkedProductIdsForGroup(int groupId) => _db.getLinkedProductIdsForGroup(groupId);

  @override
  Future<void> linkModifierToProduct({required int productId, required int modifierGroupId}) =>
      _db.linkModifierToProduct(productId: productId, modifierGroupId: modifierGroupId);

  @override
  Future<void> unlinkModifierFromProduct({required int productId, required int modifierGroupId}) =>
      _db.unlinkModifierFromProduct(productId: productId, modifierGroupId: modifierGroupId);

  @override
  Future<List<db.ModifierGroupWithItems>> getProductModifiers(int productId) =>
      _db.getProductModifiers(productId);

  @override
  Future<db.ModifierGroupData?> getGroupByName(String name) async {
    final groups = await _db.getAllModifierGroups();
    for (final g in groups) {
      if (g.name == name) return g;
    }
    return null;
  }

  @override
  Future<int> getOrCreateGroupByName({
    required String name,
    required String type,
    int minSelect = 0,
    int maxSelect = 1,
    bool isRequired = false,
  }) async {
    final existing = await getGroupByName(name);
    if (existing != null) return existing.id;
    return _db.createModifierGroup(
      name: name,
      type: type,
      minSelect: minSelect,
      maxSelect: maxSelect,
      isRequired: isRequired,
    );
  }
}
