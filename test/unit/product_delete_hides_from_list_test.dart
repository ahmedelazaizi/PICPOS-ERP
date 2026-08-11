// حذفُ الصنف يخفيه من شاشة الأصناف — والتعطيلُ يُبقيه.
//
// ── البلاغ ────────────────────────────────────────────────────────────────
// «عند حذف صنف من شاشة الأصناف تظهر رسالة **تم الحذف** ولكن لا يزال الصنف
// موجوداً ولم يُحذف.»
//
// والرسالةُ لم تكن كاذبة: الديالوج لا يقولها إلا حين يرجع الحذفُ نجاحاً،
// والكتابةُ تنجح فعلاً. **النتيجةُ هي التي تكذّبها.**
//
// ── الجذرُ المقيس ─────────────────────────────────────────────────────────
// `deleteProduct` حذفٌ ناعمٌ عن قصد (‏يرفض أصلاً إن وُجد سجلُّ معاملات)، لكنه
// كان يكتب `isActive: Value(false)` **وحدَها** — وهي نفسُ حالة «تعطيل الصنف»،
// إجراءٌ مستقلٌّ قائمٌ للمشغّل. فانهار الفعلان إلى حالةٍ واحدةٍ لا تفرّق
// بينهما.
//
// وقارئُ شاشة الأصناف (`DriftProductRepository.getProducts`) هو **الوحيد**
// بين قرّاء المنتجات الذي لا يفلتر شيئاً — ونظائرُه في الـDAO
// (`watchAllProducts` · `getAllProducts` · `watchProductsByCategory`) تفلتر
// `isActive == true`، فالمحذوفُ مستبعَدٌ من نقطة البيع والمنتقيات تلقائياً
// ولم يكن ثمّة خطرُ بيعِ صنفٍ محذوف. الفجوةُ في موضعٍ واحدٍ بالضبط.
//
// ── المزلق الذي يحرسه هذا الملفّ ──────────────────────────────────────────
// الفلترةُ على `deletedAt` **وحدَه**. فلترةٌ على `isActive` كانت ستُخفي
// المعطَّلَ أيضاً وتكسر خاصيةَ إعادة التفعيل — وهو أسهلُ خطأٍ يقع فيه من
// يصلح هذا العطل.

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/data/repositories/drift_product_repository.dart';

void main() {
  late AppDatabase db;
  late DriftProductRepository repo;

  setUp(() async {
    db = AppDatabase.forTesting();
    repo = DriftProductRepository(db);
    await db.delete(db.products).go();
  });

  tearDown(() => db.close());

  Future<int> seedProduct(String code, String name) =>
      db.into(db.products).insert(ProductsCompanion.insert(
            code: code,
            name: name,
            salePrice: const Value(10),
            costPrice: const Value(5),
          ));

  Future<Set<int>> visibleIds() async =>
      (await repo.getProducts(limit: 500)).map((p) => p.id).toSet();

  Future<Product> rowOf(int id) =>
      (db.select(db.products)..where((p) => p.id.equals(id))).getSingle();

  test('البلاغُ حرفياً: المحذوفُ يختفي من شاشة الأصناف', () async {
    final kept = await seedProduct('P-KEEP', 'صنفٌ باقٍ');
    final gone = await seedProduct('P-GONE', 'صنفٌ محذوف');
    expect(await visibleIds(), {kept, gone});

    await db.deleteProduct(gone);

    expect(await visibleIds(), {kept},
        reason: 'الرسالةُ تقول «تم الحذف» — فالشاشةُ يجب أن تصدّقها');
  });

  test('والمعطَّلُ **يبقى** معروضاً كي يُعاد تفعيله', () async {
    // الحارسُ على ألّا يكسر الإصلاحُ خاصيةَ التعطيل. فلترةٌ على `isActive`
    // كانت ستُسقط هذا الاختبار — وهي الطريقُ الأقصرُ الخاطئ لإخفاء المحذوف.
    final disabled = await seedProduct('P-OFF', 'صنفٌ معطَّل');
    await (db.update(db.products)..where((p) => p.id.equals(disabled)))
        .write(const ProductsCompanion(isActive: Value(false)));

    expect(await visibleIds(), contains(disabled),
        reason: 'التعطيلُ إجراءٌ قابلٌ للرجوع، والمشغّلُ يحتاج رؤيتَه ليُعيد '
            'تفعيله. إخفاؤه يكسر خاصيةً قائمة');
  });

  test('الختمُ يفصل الفعلين — وهو ما لم يكن موجوداً', () async {
    final deleted = await seedProduct('P-DEL', 'محذوف');
    final disabled = await seedProduct('P-DIS', 'معطَّل');

    await db.deleteProduct(deleted);
    await (db.update(db.products)..where((p) => p.id.equals(disabled)))
        .write(const ProductsCompanion(isActive: Value(false)));

    final d = await rowOf(deleted);
    final s = await rowOf(disabled);

    expect(d.deletedAt, isNotNull, reason: 'الحذفُ يُختم');
    expect(d.isActive, isFalse,
        reason: '`isActive=false` يبقى مكتوباً عمداً، فتظلُّ كلُّ الفلاتر '
            'القائمة تستبعد المحذوفَ بلا تعديل سطرٍ فيها');

    expect(s.deletedAt, isNull, reason: 'التعطيلُ لا يُختم');
    expect(s.isActive, isFalse);
  });

  test('والصفُّ يبقى في القاعدة — يُخفى لا يُمحى', () async {
    final id = await seedProduct('P-SOFT', 'ناعم');
    await db.deleteProduct(id);

    expect(await rowOf(id), isNotNull,
        reason: 'الحذفُ الصلبُ يكسر أيَّ مرجعٍ قائمٍ ولا رجعةَ فيه');
  });

  test('ضابط: حارسُ سجلّ المعاملات لم يتغيّر', () async {
    // بلا هذا لَمرّ «إصلاحٌ» يختم كلَّ شيءٍ ويتخطّى الرفضَ الذي يحمي الدفاتر.
    final id = await seedProduct('P-TXN', 'له معاملات');
    final warehouseId = await db.into(db.warehouses).insert(
          WarehousesCompanion.insert(name: 'مخزن', isActive: const Value(true)),
        );
    await db.into(db.stockMovements).insert(StockMovementsCompanion.insert(
          productId: id,
          warehouseId: warehouseId,
          movementType: 'adjustment',
          quantity: 1,
          balanceAfter: 1,
        ));

    await expectLater(() => db.deleteProduct(id), throwsA(isA<Exception>()));
    expect((await rowOf(id)).deletedAt, isNull,
        reason: 'رفضٌ يعني ألّا يُكتب شيء');
  });
}
