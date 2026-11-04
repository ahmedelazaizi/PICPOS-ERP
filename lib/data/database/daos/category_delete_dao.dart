part of '../database.dart';

// ═══════════════════════════════════════════════════════════════════════════
// CATEGORY SAFE DELETE — الحذف الناعم الآمن للتصنيفات (بند 10)
// ═══════════════════════════════════════════════════════════════════════════
//
// المصدر الوحيد لحذف التصنيف: الشاشة العاديّة وأدوات المطوّر ومعالج الخادم
// (`DELETE /api/categories/<id>`) كلُّها تمرّ من [CategoryDeleteDao.deleteCategory].
//
// القواعد (تُفحص داخل المعاملة نفسها فلا سباق بين العدّ والحذف):
//   * تصنيفٌ افتراضيٌّ (`isSystemDefault` أو الاسمُ «عام») ⇒ مرفوض.
//   * تصنيفٌ مقفل (`isLocked`) ⇒ مرفوض حتى يُفكّ قفلُه صراحةً.
//   * له تصنيفاتٌ فرعيةٌ نشطة ⇒ مرفوض (يبقى `parentId` معلّقاً بمعطَّل).
//   * وجهةُ نقل الأصناف: غير ذاتِه، ونشطةٌ، وليست من نسله.
//   * `requireEmpty` (أدوات المطوّر): وجودُ أيِّ صنفٍ — نشطٍ أو غير نشط — يمنع.
//   * وإلّا تُنقل **كلُّ** الأصناف (النشطة وغير النشطة) إلى الوجهة أو إلى NULL
//     «بدون تصنيف»، مع رفع `lastModifiedAt/rowVersion` لها كي تنتشر بالمزامنة.
//   * حذفٌ ناعمٌ فقط (`isActive=false` + `deletedAt`)؛ لا حذفَ فعليّاً أبداً —
//     الـtombstone يمنع عودةَ التصنيف مع الـpull (انظر `CategorySyncStrategy`).
//   * الحذفُ المكرّر (بإعادة تشغيل الـoutbox) أو لمعرّفٍ غير موجود: no-op.

/// أسبابُ منعِ حذف التصنيف.
enum CategoryDeleteBlock {
  systemDefault,
  locked,
  hasChildren,
  hasProducts,
  badDestination,
}

class CategoryDeleteBlockedException implements Exception {
  final Set<CategoryDeleteBlock> reasons;
  final CategoryDeleteAnalysis analysis;
  const CategoryDeleteBlockedException(this.reasons, this.analysis);

  @override
  String toString() =>
      'CategoryDeleteBlockedException(${reasons.map((r) => r.name).join(', ')})';
}

/// معاينةُ الحذف: الأعدادُ والأسباب. `category == null` ⇒ غير موجود/محذوف.
class CategoryDeleteAnalysis {
  final Category? category;
  final int activeProducts;
  final int inactiveProducts;
  final int activeChildren;
  final int invoicedItems;
  final int branchLinks;
  final int stationLinks;

  const CategoryDeleteAnalysis({
    required this.category,
    this.activeProducts = 0,
    this.inactiveProducts = 0,
    this.activeChildren = 0,
    this.invoicedItems = 0,
    this.branchLinks = 0,
    this.stationLinks = 0,
  });

  int get totalProducts => activeProducts + inactiveProducts;

  /// الأسبابُ التي تمنع الحذف مهما كان الخيار.
  Set<CategoryDeleteBlock> get hardBlocks {
    final c = category;
    if (c == null) return const {};
    return {
      if (c.isSystemDefault || c.name.trim() == 'عام')
        CategoryDeleteBlock.systemDefault,
      if (c.isLocked) CategoryDeleteBlock.locked,
      if (activeChildren > 0) CategoryDeleteBlock.hasChildren,
    };
  }

  /// أسبابُ منع الحذف «الصارم» (التصنيف يجب أن يكون فارغاً تماماً).
  Set<CategoryDeleteBlock> get strictBlocks => {
        ...hardBlocks,
        if (totalProducts > 0) CategoryDeleteBlock.hasProducts,
      };
}

extension CategoryDeleteDao on AppDatabase {
  /// يحسب أعدادَ ما يرتبط بالتصنيف دون تعديل شيء.
  Future<CategoryDeleteAnalysis> analyzeCategoryDelete(int categoryId) async {
    final cat = await (select(categories)
          ..where((c) => c.id.equals(categoryId))
          ..limit(1))
        .getSingleOrNull();
    if (cat == null || (!cat.isActive && cat.deletedAt != null)) {
      return const CategoryDeleteAnalysis(category: null);
    }
    Future<int> scalar(String sql, List<Variable> vars) async {
      final r = await customSelect(sql, variables: vars).getSingle();
      return (r.data['n'] as num?)?.toInt() ?? 0;
    }

    final id = Variable.withInt(categoryId);
    return CategoryDeleteAnalysis(
      category: cat,
      activeProducts: await scalar(
          'SELECT COUNT(*) AS n FROM products WHERE category_id = ? '
          'AND is_active = ?',
          [id, Variable.withBool(true)]),
      inactiveProducts: await scalar(
          'SELECT COUNT(*) AS n FROM products WHERE category_id = ? '
          'AND is_active = ?',
          [id, Variable.withBool(false)]),
      activeChildren: await scalar(
          'SELECT COUNT(*) AS n FROM categories WHERE parent_id = ? '
          'AND is_active = ?',
          [id, Variable.withBool(true)]),
      invoicedItems: await scalar(
          'SELECT (SELECT COUNT(*) FROM sales_invoice_items sii '
          'JOIN products p ON p.id = sii.product_id WHERE p.category_id = ?) '
          '+ (SELECT COUNT(*) FROM purchase_invoice_items pii '
          'JOIN products p ON p.id = pii.product_id WHERE p.category_id = ?) '
          'AS n',
          [id, id]),
      branchLinks: await scalar(
          'SELECT COUNT(*) AS n FROM category_branches WHERE category_id = ?',
          [id]),
      stationLinks: await scalar(
          'SELECT COUNT(*) AS n FROM category_station_mappings '
          'WHERE category_id = ? AND deleted_at IS NULL',
          [id]),
    );
  }

  /// معرّفات نسل [categoryId] (أبناء وأحفاد، نشطين أو لا).
  Future<Set<int>> _categoryDescendants(int categoryId) async {
    final rows = await (select(categories)).get();
    final byParent = <int, List<int>>{};
    for (final c in rows) {
      final p = c.parentId;
      if (p != null) (byParent[p] ??= []).add(c.id);
    }
    final out = <int>{};
    final stack = [categoryId];
    while (stack.isNotEmpty) {
      for (final child in byParent[stack.removeLast()] ?? const <int>[]) {
        if (out.add(child)) stack.add(child);
      }
    }
    return out;
  }

  /// حذفٌ ناعمٌ آمن — انظر ترويسةَ الملف. يرمي [CategoryDeleteBlockedException]
  /// عند المنع، و[ArgumentError] لوجهةٍ هي التصنيفُ نفسُه.
  Future<void> deleteCategory(
    int categoryId, {
    int? moveToCategoryId,
    bool requireEmpty = false,
  }) async {
    if (moveToCategoryId != null && moveToCategoryId == categoryId) {
      throw ArgumentError(
        'moveToCategoryId must differ from the category being deleted',
      );
    }
    await transaction(() async {
      final a = await analyzeCategoryDelete(categoryId);
      if (a.category == null) return; // غير موجود/محذوف من قبل ⇒ idempotent.

      final blocks = {...(requireEmpty ? a.strictBlocks : a.hardBlocks)};
      if (moveToCategoryId != null && a.totalProducts > 0) {
        final dest = await (select(categories)
              ..where((c) => c.id.equals(moveToCategoryId)))
            .getSingleOrNull();
        final bad = dest == null ||
            !dest.isActive ||
            dest.deletedAt != null ||
            (await _categoryDescendants(categoryId)).contains(dest.id);
        if (bad) blocks.add(CategoryDeleteBlock.badDestination);
      }
      if (blocks.isNotEmpty) throw CategoryDeleteBlockedException(blocks, a);

      final now = DateTime.now();
      if (a.totalProducts > 0) {
        await customUpdate(
          'UPDATE products SET category_id = ?, last_modified_at = ?, '
          'row_version = row_version + 1 WHERE category_id = ?',
          variables: [
            Variable<int>(moveToCategoryId),
            Variable<DateTime>(now),
            Variable.withInt(categoryId),
          ],
          updates: {products},
        );
      }
      await (delete(categoryBranches)
            ..where((b) => b.categoryId.equals(categoryId)))
          .go();
      await (update(categoryStationMappings)
            ..where((m) =>
                m.categoryId.equals(categoryId) & m.deletedAt.isNull()))
          .write(CategoryStationMappingsCompanion(
        deletedAt: Value(now),
        lastModifiedAt: Value(now),
      ));
      await (update(categories)..where((c) => c.id.equals(categoryId)))
          .write(CategoriesCompanion(
        isActive: const Value(false),
        deletedAt: Value(now),
        lastModifiedAt: Value(now),
      ));
      await customUpdate(
        'UPDATE categories SET row_version = row_version + 1 WHERE id = ?',
        variables: [Variable.withInt(categoryId)],
        updates: {categories},
      );
    });
    invalidateCategoryCache();
    resetProductCaches();
  }
}
