part of '../database.dart';

// ═══════════════════════════════════════════════════════════════════════════
// MODIFIERS DAO — Product Addons & Options (#15)
// ═══════════════════════════════════════════════════════════════════════════
//
// Raw SQL DAO for the modifier_groups, modifier_items, and
// product_modifier_groups tables (created in v70 migration).
//
// ═══ 🔴 عقدُ المزامنة — 2026-09-21 ═══
//
// الجداولُ الثلاثةُ **بياناتٌ رئيسةٌ عامّةٌ** كالأصناف والفئات (قرارُ مالك):
// تعريفٌ واحدٌ يصل كلَّ الأجهزة في كلّ الفروع. وكانت خارجَ قوائم المزامنة
// الثماني كلِّها — فمجموعةٌ يعرّفها المديرُ لا تصل الكاشيرَ أبداً، وسعرُ
// الخيار (‏`extra_price`، وهو **يزيد قيمةَ الصنف في الفاتورة**) يختلف من
// جهازٍ لآخرَ في فاتورتَين.
//
// ولذلك في هذا الملفّ ثلاثةُ التزامات:
//
//   ‏١) **كلُّ إدراجٍ يمنح `global_id` ويختم `last_modified_at`** — صفٌّ بلا
//      معرّفٍ لا يحلّه `_upsertRow` فيُدرَج ثانيةً بمعرّفٍ محلّيٍّ مختلف،
//      وصفٌّ بلا ختمٍ لا يلتقطه السحبُ التفاضليُّ أبداً.
//
//   ‏٢) 🔴 **والحذفُ ناعمٌ لا قاطع** — حذفٌ قاطعٌ محلّيّاً يترك الصفَّ على
//      الخادم فيعود بأوّل سحب: يحذف المستخدمُ الخيارَ فيعود بعد دقائقَ
//      بلا سبب.
//
//   ‏٣) **وكلُّ قراءةٍ ترشّح `deleted_at IS NULL`** — وإلّا بقي المحذوفُ
//      معروضاً ومُسعَّراً، و«حذفٌ» لا يحذف.
// ═══════════════════════════════════════════════════════════════════════════

/// Data class for a modifier group
class ModifierGroupData {
  final int id;
  final String name;
  final String type; // 'addon' or 'option'
  final int minSelect;
  final int maxSelect;
  final bool isRequired;
  final bool isActive;
  final int sortOrder;

  ModifierGroupData({
    required this.id,
    required this.name,
    required this.type,
    required this.minSelect,
    required this.maxSelect,
    required this.isRequired,
    required this.isActive,
    required this.sortOrder,
  });

  factory ModifierGroupData.fromRow(Map<String, dynamic> row) {
    return ModifierGroupData(
      id: row['id'] as int,
      name: row['name'] as String,
      type: row['type'] as String? ?? 'addon',
      minSelect: row['min_select'] as int? ?? 0,
      maxSelect: row['max_select'] as int? ?? 1,
      isRequired: row['is_required'] == true || row['is_required'] == 1,
      isActive: row['is_active'] == true || row['is_active'] == 1,
      sortOrder: row['sort_order'] as int? ?? 0,
    );
  }
}

/// Data class for a modifier item
class ModifierItemData {
  final int id;
  final int groupId;
  final String name;
  final double extraPrice;
  final bool isDefault;
  final bool isActive;
  final int sortOrder;

  ModifierItemData({
    required this.id,
    required this.groupId,
    required this.name,
    required this.extraPrice,
    required this.isDefault,
    required this.isActive,
    required this.sortOrder,
  });

  factory ModifierItemData.fromRow(Map<String, dynamic> row) {
    return ModifierItemData(
      id: row['id'] as int,
      groupId: row['group_id'] as int,
      name: row['name'] as String,
      extraPrice: (row['extra_price'] as num?)?.toDouble() ?? 0,
      isDefault: row['is_default'] == true || row['is_default'] == 1,
      isActive: row['is_active'] == true || row['is_active'] == 1,
      sortOrder: row['sort_order'] as int? ?? 0,
    );
  }
}

/// Data class for a modifier group with its items
class ModifierGroupWithItems {
  final ModifierGroupData group;
  final List<ModifierItemData> items;

  ModifierGroupWithItems({required this.group, required this.items});
}

/// Extension for Modifier-related database operations
extension ModifiersDao on AppDatabase {
  // ═══════════════════════════════════════════════════════════════════════
  // MODIFIER GROUPS CRUD
  // ═══════════════════════════════════════════════════════════════════════

  /// ختمُ المزامنة — ثوانٍ منذ الحقبة، صيغةُ `last_modified_at` نفسُها في
  /// باقي الجداول (‏`deleted_at` كذلك).
  int _syncStamp() => DateTime.now().millisecondsSinceEpoch ~/ 1000;

  /// Get all modifier groups
  Future<List<ModifierGroupData>> getAllModifierGroups() async {
    final rows = await customSelect(
      'SELECT * FROM modifier_groups WHERE deleted_at IS NULL '
      'ORDER BY sort_order, name',
    ).get();
    return rows.map((r) => ModifierGroupData.fromRow(r.data)).toList();
  }

  /// Get active modifier groups
  Future<List<ModifierGroupData>> getActiveModifierGroups() async {
    final boolTrue = sqlBool(true);
    final rows = await customSelect(
      'SELECT * FROM modifier_groups WHERE is_active = $boolTrue '
      'AND deleted_at IS NULL ORDER BY sort_order, name',
    ).get();
    return rows.map((r) => ModifierGroupData.fromRow(r.data)).toList();
  }

  /// Create a modifier group
  Future<int> createModifierGroup({
    required String name,
    String type = 'addon',
    int minSelect = 0,
    int maxSelect = 1,
    bool isRequired = false,
    int sortOrder = 0,
  }) async {
    final gid = UuidV7.generate();
    final now = _syncStamp();
    if (isPostgres) {
      final result = await customSelect(
        'INSERT INTO modifier_groups (name, type, min_select, max_select, is_required, sort_order, global_id, last_modified_at) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?) RETURNING id',
        variables: [Variable(name), Variable(type), Variable(minSelect), Variable(maxSelect), Variable(isRequired), Variable(sortOrder), Variable(gid), Variable(now)],
      ).getSingle();
      return result.data['id'] as int;
    } else {
      await customStatement(
        'INSERT INTO modifier_groups (name, type, min_select, max_select, is_required, sort_order, global_id, last_modified_at) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
        [name, type, minSelect, maxSelect, isRequired ? 1 : 0, sortOrder, gid, now],
      );
      final result = await customSelect('SELECT last_insert_rowid() as id').getSingle();
      return result.data['id'] as int;
    }
  }

  /// Update a modifier group
  Future<void> updateModifierGroup({
    required int id,
    required String name,
    required String type,
    required int minSelect,
    required int maxSelect,
    required bool isRequired,
    required bool isActive,
    int sortOrder = 0,
  }) async {
    if (isPostgres) {
      await customStatement(
        'UPDATE modifier_groups SET name = ?, type = ?, min_select = ?, max_select = ?, '
        'is_required = ?, is_active = ?, sort_order = ?, last_modified_at = ? WHERE id = ?',
        [name, type, minSelect, maxSelect, isRequired, isActive, sortOrder, _syncStamp(), id],
      );
    } else {
      await customStatement(
        'UPDATE modifier_groups SET name = ?, type = ?, min_select = ?, max_select = ?, '
        'is_required = ?, is_active = ?, sort_order = ?, last_modified_at = ? WHERE id = ?',
        [name, type, minSelect, maxSelect, isRequired ? 1 : 0, isActive ? 1 : 0, sortOrder, _syncStamp(), id],
      );
    }
  }

  /// حذفٌ **ناعم** — راجع عقدَ المزامنة في رأس الملفّ.
  ///
  /// ⚠️ **وعناصرُها تُوسَم معها**: الحذفُ القاطعُ كان يعتمد على
  ///    `ON DELETE CASCADE`، والناعمُ لا يُشغّله — فعناصرُ مجموعةٍ محذوفةٍ
  ///    كانت ستبقى قائمةً وتظهر لو رُبط معرّفُها ثانيةً.
  Future<void> deleteModifierGroup(int id) async {
    final now = _syncStamp();
    await customStatement(
      'UPDATE modifier_groups SET deleted_at = ?, last_modified_at = ? '
      'WHERE id = ?',
      [now, now, id],
    );
    await customStatement(
      'UPDATE modifier_items SET deleted_at = ?, last_modified_at = ? '
      'WHERE group_id = ? AND deleted_at IS NULL',
      [now, now, id],
    );
    await customStatement(
      'UPDATE product_modifier_groups SET deleted_at = ?, '
      'last_modified_at = ? WHERE modifier_group_id = ? AND deleted_at IS NULL',
      [now, now, id],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // MODIFIER ITEMS CRUD
  // ═══════════════════════════════════════════════════════════════════════

  /// Get items for a modifier group
  Future<List<ModifierItemData>> getModifierItems(int groupId) async {
    final rows = await customSelect(
      'SELECT * FROM modifier_items WHERE group_id = ? AND deleted_at IS NULL '
      'ORDER BY sort_order, name',
      variables: [Variable.withInt(groupId)],
    ).get();
    return rows.map((r) => ModifierItemData.fromRow(r.data)).toList();
  }

  /// Create a modifier item
  Future<int> createModifierItem({
    required int groupId,
    required String name,
    double extraPrice = 0,
    bool isDefault = false,
    int sortOrder = 0,
  }) async {
    final gid = UuidV7.generate();
    final now = _syncStamp();
    if (isPostgres) {
      final result = await customSelect(
        'INSERT INTO modifier_items (group_id, name, extra_price, is_default, sort_order, global_id, last_modified_at) '
        'VALUES (?, ?, ?, ?, ?, ?, ?) RETURNING id',
        variables: [Variable(groupId), Variable(name), Variable(extraPrice), Variable(isDefault), Variable(sortOrder), Variable(gid), Variable(now)],
      ).getSingle();
      return result.data['id'] as int;
    } else {
      await customStatement(
        'INSERT INTO modifier_items (group_id, name, extra_price, is_default, sort_order, global_id, last_modified_at) '
        'VALUES (?, ?, ?, ?, ?, ?, ?)',
        [groupId, name, extraPrice, isDefault ? 1 : 0, sortOrder, gid, now],
      );
      final result = await customSelect('SELECT last_insert_rowid() as id').getSingle();
      return result.data['id'] as int;
    }
  }

  /// Update a modifier item
  Future<void> updateModifierItem({
    required int id,
    required String name,
    required double extraPrice,
    required bool isDefault,
    required bool isActive,
    int sortOrder = 0,
  }) async {
    if (isPostgres) {
      await customStatement(
        'UPDATE modifier_items SET name = ?, extra_price = ?, is_default = ?, is_active = ?, sort_order = ?, last_modified_at = ? WHERE id = ?',
        [name, extraPrice, isDefault, isActive, sortOrder, _syncStamp(), id],
      );
    } else {
      await customStatement(
        'UPDATE modifier_items SET name = ?, extra_price = ?, is_default = ?, is_active = ?, sort_order = ?, last_modified_at = ? WHERE id = ?',
        [name, extraPrice, isDefault ? 1 : 0, isActive ? 1 : 0, sortOrder, _syncStamp(), id],
      );
    }
  }

  /// Delete a modifier item
  Future<void> deleteModifierItem(int id) async {
    final now = _syncStamp();
    await customStatement(
      'UPDATE modifier_items SET deleted_at = ?, last_modified_at = ? '
      'WHERE id = ?',
      [now, now, id],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // PRODUCT-MODIFIER LINKING
  // ═══════════════════════════════════════════════════════════════════════

  /// Get modifier groups linked to a product (with their items)
  Future<List<ModifierGroupWithItems>> getProductModifiers(int productId) async {
    final boolTrue = sqlBool(true);
    final rows = await customSelect(
      'SELECT mg.* FROM modifier_groups mg '
      'JOIN product_modifier_groups pmg ON mg.id = pmg.modifier_group_id '
      'WHERE pmg.product_id = ? AND mg.is_active = $boolTrue '
      'AND pmg.deleted_at IS NULL AND mg.deleted_at IS NULL '
      'ORDER BY pmg.sort_order, mg.name',
      variables: [Variable.withInt(productId)],
    ).get();

    final groups = rows.map((r) => ModifierGroupData.fromRow(r.data)).toList();
    final result = <ModifierGroupWithItems>[];
    for (final group in groups) {
      final items = await getModifierItems(group.id);
      final activeItems = items.where((i) => i.isActive).toList();
      result.add(ModifierGroupWithItems(group: group, items: activeItems));
    }
    return result;
  }

  /// Get modifier group IDs linked to a product
  Future<List<int>> getProductModifierGroupIds(int productId) async {
    final rows = await customSelect(
      'SELECT modifier_group_id FROM product_modifier_groups '
      'WHERE product_id = ? AND deleted_at IS NULL ORDER BY sort_order',
      variables: [Variable.withInt(productId)],
    ).get();
    return rows.map((r) => r.data['modifier_group_id'] as int).toList();
  }

  /// Link a modifier group to a product
  Future<void> linkModifierToProduct({
    required int productId,
    required int modifierGroupId,
    int sortOrder = 0,
  }) async {
    final now = _syncStamp();
    // 🔴 **يُحيي قبل أن يُدرج.** الحذفُ صار ناعماً، والصفُّ الموسومُ ما زال
    //    يشغل قيدَ `UNIQUE(product_id, modifier_group_id)` — فإدراجٌ بـ
    //    `ON CONFLICT DO NOTHING` يُهمَل بصمتٍ ويبقى الربطُ محذوفاً. أي
    //    إعادةُ ربطِ إضافةٍ بصنفٍ **لا تعمل أبداً** بعد فكٍّ واحد.
    await customStatement(
      'UPDATE product_modifier_groups SET deleted_at = NULL, sort_order = ?, '
      'last_modified_at = ? WHERE product_id = ? AND modifier_group_id = ?',
      [sortOrder, now, productId, modifierGroupId],
    );
    final gid = UuidV7.generate();
    if (isPostgres) {
      await customStatement(
        'INSERT INTO product_modifier_groups (product_id, modifier_group_id, sort_order, global_id, last_modified_at) '
        'VALUES (?, ?, ?, ?, ?) ON CONFLICT DO NOTHING',
        [productId, modifierGroupId, sortOrder, gid, now],
      );
    } else {
      await customStatement(
        'INSERT OR IGNORE INTO product_modifier_groups (product_id, modifier_group_id, sort_order, global_id, last_modified_at) '
        'VALUES (?, ?, ?, ?, ?)',
        [productId, modifierGroupId, sortOrder, gid, now],
      );
    }
  }

  /// Unlink a modifier group from a product
  Future<void> unlinkModifierFromProduct({
    required int productId,
    required int modifierGroupId,
  }) async {
    final now = _syncStamp();
    await customStatement(
      'UPDATE product_modifier_groups SET deleted_at = ?, last_modified_at = ? '
      'WHERE product_id = ? AND modifier_group_id = ?',
      [now, now, productId, modifierGroupId],
    );
  }

  /// Set all modifier groups for a product (replaces existing links)
  Future<void> setProductModifierGroups(int productId, List<int> groupIds) async {
    final now = _syncStamp();
    await customStatement(
      'UPDATE product_modifier_groups SET deleted_at = ?, last_modified_at = ? '
      'WHERE product_id = ? AND deleted_at IS NULL',
      [now, now, productId],
    );
    for (int i = 0; i < groupIds.length; i++) {
      await linkModifierToProduct(
        productId: productId,
        modifierGroupId: groupIds[i],
        sortOrder: i,
      );
    }
  }

  /// Check if a product has any modifiers
  Future<bool> productHasModifiers(int productId) async {
    final result = await customSelect(
      'SELECT COUNT(*) as cnt FROM product_modifier_groups WHERE product_id = ?',
      variables: [Variable.withInt(productId)],
    ).getSingle();
    return (result.data['cnt'] as int) > 0;
  }

  /// Get product IDs linked to a specific modifier group (reverse lookup)
  Future<List<int>> getLinkedProductIdsForGroup(int groupId) async {
    final rows = await customSelect(
      'SELECT product_id FROM product_modifier_groups WHERE modifier_group_id = ?',
      variables: [Variable.withInt(groupId)],
    ).get();
    return rows.map((r) => r.data['product_id'] as int).toList();
  }
}
