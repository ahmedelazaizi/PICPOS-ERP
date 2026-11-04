// بند 10 — الحذف الناعم الآمن للتصنيفات (`CategoryDeleteDao`).
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';

void main() {
  late AppDatabase db;

  Future<int> cat(String name,
          {int? parentId,
          bool isLocked = false,
          bool isSystemDefault = false,
          bool isActive = true}) =>
      db.into(db.categories).insert(CategoriesCompanion.insert(
            name: name,
            parentId: Value(parentId),
            isLocked: Value(isLocked),
            isSystemDefault: Value(isSystemDefault),
            isActive: Value(isActive),
            globalId: Value('gid-$name'),
          ));

  Future<int> prod(String code, int categoryId, {bool active = true}) =>
      db.into(db.products).insert(ProductsCompanion.insert(
            code: code,
            name: code,
            categoryId: Value(categoryId),
            isActive: Value(active),
            globalId: Value('gid-prod-$code'),
          ));

  Future<Category> row(int id) =>
      (db.select(db.categories)..where((c) => c.id.equals(id))).getSingle();

  Future<Set<CategoryDeleteBlock>> blockedWith(
    int id, {
    int? moveTo,
    bool requireEmpty = false,
  }) async {
    try {
      await db.deleteCategory(id,
          moveToCategoryId: moveTo, requireEmpty: requireEmpty);
    } on CategoryDeleteBlockedException catch (e) {
      return e.reasons;
    }
    return const {};
  }

  setUp(() => db = AppDatabase.forTesting());
  tearDown(() => db.close());

  group('analyzeCategoryDelete', () {
    test('يعدّ الأصناف النشطة وغير النشطة والأبناء', () async {
      final a = await cat('A');
      await cat('A-child', parentId: a);
      await cat('A-gone', parentId: a, isActive: false);
      await prod('P1', a);
      await prod('P2', a);
      await prod('P3', a, active: false);

      final r = await db.analyzeCategoryDelete(a);
      expect(r.activeProducts, 2);
      expect(r.inactiveProducts, 1);
      expect(r.totalProducts, 3);
      expect(r.activeChildren, 1, reason: 'الابن المعطّل لا يُحسب');
      expect(r.strictBlocks,
          {CategoryDeleteBlock.hasChildren, CategoryDeleteBlock.hasProducts});
    });

    test('تصنيف غير موجود أو محذوف سابقاً ⇒ category == null', () async {
      expect((await db.analyzeCategoryDelete(9999)).category, isNull);
      final a = await cat('A');
      await db.deleteCategory(a);
      expect((await db.analyzeCategoryDelete(a)).category, isNull);
    });
  });

  group('الحرّاس', () {
    test('الافتراضي (isSystemDefault) والاسم «عام» مرفوضان', () async {
      final sys = await cat('أي اسم', isSystemDefault: true);
      final general = await cat('عام');
      expect(await blockedWith(sys), {CategoryDeleteBlock.systemDefault});
      expect(await blockedWith(general), {CategoryDeleteBlock.systemDefault});
      expect((await row(sys)).isActive, isTrue);
      expect((await row(general)).isActive, isTrue);
    });

    test('المقفل مرفوض', () async {
      final a = await cat('A', isLocked: true);
      expect(await blockedWith(a), {CategoryDeleteBlock.locked});
      expect((await row(a)).isActive, isTrue);
    });

    test('التصنيف ذو الأبناء النشطة مرفوض (ثلاثة مستويات)', () async {
      final a = await cat('A');
      final b = await cat('B', parentId: a);
      await cat('C', parentId: b);
      expect(await blockedWith(a), {CategoryDeleteBlock.hasChildren});
      expect(await blockedWith(b), {CategoryDeleteBlock.hasChildren});
    });

    test('requireEmpty: صنف نشط أو غير نشط يمنع', () async {
      final a = await cat('A');
      final b = await cat('B');
      await prod('P1', a);
      await prod('P2', b, active: false);
      expect(await blockedWith(a, requireEmpty: true),
          {CategoryDeleteBlock.hasProducts});
      expect(await blockedWith(b, requireEmpty: true),
          {CategoryDeleteBlock.hasProducts});
      expect((await row(a)).isActive, isTrue);
      expect((await row(b)).isActive, isTrue);
    });

    test('وجهة غير صالحة: غير موجودة / معطّلة / من النسل', () async {
      final a = await cat('A');
      final off = await cat('Off', isActive: false);
      await prod('P1', a);
      expect(await blockedWith(a, moveTo: 12345),
          {CategoryDeleteBlock.badDestination});
      expect(await blockedWith(a, moveTo: off),
          {CategoryDeleteBlock.badDestination});
      // ابنٌ معطّل من نسل A لا يصلح وجهة.
      final kid = await cat('Kid', parentId: a, isActive: false);
      expect(await blockedWith(a, moveTo: kid),
          {CategoryDeleteBlock.badDestination});
      expect((await row(a)).isActive, isTrue);
    });

    test('وجهة = نفسه ⇒ ArgumentError', () async {
      final a = await cat('A');
      expect(() => db.deleteCategory(a, moveToCategoryId: a),
          throwsArgumentError);
    });
  });

  group('الحذف', () {
    test('فارغ: حذف ناعم + deletedAt + lastModifiedAt + rowVersion', () async {
      final a = await cat('A');
      final before = (await row(a)).rowVersion;
      await db.deleteCategory(a, requireEmpty: true);
      final r = await row(a);
      expect(r.isActive, isFalse);
      expect(r.deletedAt, isNotNull);
      expect(r.lastModifiedAt, isNotNull);
      expect(r.rowVersion, before + 1);
    });

    test('ينقل النشطة وغير النشطة ويرفع lastModifiedAt/rowVersion للأصناف',
        () async {
      final a = await cat('A');
      final dest = await cat('Dest');
      final p1 = await prod('P1', a);
      final p2 = await prod('P2', a, active: false);

      await db.deleteCategory(a, moveToCategoryId: dest);

      for (final id in [p1, p2]) {
        final p = await (db.select(db.products)..where((x) => x.id.equals(id)))
            .getSingle();
        expect(p.categoryId, dest);
        expect(p.lastModifiedAt, isNotNull);
        expect(p.rowVersion, 1);
      }
    });

    test('وجهة null ⇒ بدون تصنيف', () async {
      final a = await cat('A');
      final p1 = await prod('P1', a, active: false);
      await db.deleteCategory(a);
      final p = await (db.select(db.products)..where((x) => x.id.equals(p1)))
          .getSingle();
      expect(p.categoryId, isNull);
    });

    test('تنظيف روابط الفروع وتعطيل روابط المطبخ', () async {
      final a = await cat('A');
      final branch = await db.into(db.branches).insert(
          BranchesCompanion.insert(name: 'B1', globalId: const Value('b1')));
      await db.into(db.categoryBranches).insert(
          CategoryBranchesCompanion.insert(categoryId: a, branchId: branch));
      final station = await db.into(db.kitchenStations).insert(
          KitchenStationsCompanion.insert(name: 'S1', code: 'S1'));
      await db.into(db.categoryStationMappings).insert(
          CategoryStationMappingsCompanion.insert(
              categoryId: a, stationId: station));

      final pre = await db.analyzeCategoryDelete(a);
      expect(pre.branchLinks, 1);
      expect(pre.stationLinks, 1);

      await db.deleteCategory(a);

      expect(await db.select(db.categoryBranches).get(), isEmpty);
      final m = await db.select(db.categoryStationMappings).getSingle();
      expect(m.deletedAt, isNotNull);
    });

    test('حذف مكرّر (إعادة تشغيل outbox) أو معرّف مجهول: no-op بلا خطأ',
        () async {
      final a = await cat('A');
      await db.deleteCategory(a);
      final v = (await row(a)).rowVersion;
      await db.deleteCategory(a);
      await db.deleteCategory(424242);
      expect((await row(a)).rowVersion, v, reason: 'لا رفع ثانٍ للنسخة');
    });

    test('فشل في منتصف المعاملة يتراجع عن كل شيء', () async {
      final a = await cat('A');
      final dest = await cat('Dest');
      final p1 = await prod('P1', a);
      // نُسقط جدول الروابط ليفشل الحذف بعد نقل الأصناف.
      await db.customStatement('DROP TABLE category_branches');

      await expectLater(
          db.deleteCategory(a, moveToCategoryId: dest), throwsA(anything));

      final p = await (db.select(db.products)..where((x) => x.id.equals(p1)))
          .getSingle();
      expect(p.categoryId, a, reason: 'النقل يُلغى مع المعاملة');
      expect((await row(a)).isActive, isTrue);
    });
  });
}
