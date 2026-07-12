import '../../data/database/database.dart' as db;

abstract class IModifierRepository {
  Future<List<db.ModifierGroupData>> getAllGroups();
  Future<void> ensureTables();
  Future<void> createGroup({
    required String name,
    required String type,
    required int minSelect,
    required int maxSelect,
    required bool isRequired,
  });
  Future<void> deleteGroup(int id);
  Future<List<db.ModifierItemData>> getItems(int groupId);
  Future<void> createItem({
    required int groupId,
    required String name,
    required double extraPrice,
    required bool isDefault,
  });
  Future<void> deleteItem(int id);
  Future<List<db.Product>> getAllProducts();
  Future<List<db.Category>> getAllCategories();
  Future<List<int>> getLinkedProductIdsForGroup(int groupId);
  Future<void> linkModifierToProduct({required int productId, required int modifierGroupId});
  Future<void> unlinkModifierFromProduct({required int productId, required int modifierGroupId});
  Future<List<db.ModifierGroupWithItems>> getProductModifiers(int productId);
  Future<db.ModifierGroupData?> getGroupByName(String name);
  Future<int> getOrCreateGroupByName({required String name, required String type, int minSelect = 0, int maxSelect = 1, bool isRequired = false});
}
