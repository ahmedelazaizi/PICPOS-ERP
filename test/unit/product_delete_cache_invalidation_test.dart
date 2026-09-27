// ═══════════════════════════════════════════════════════════════════════════
// حذف الصنف كان بيسيب الصنف في كاش القراءة بالمعرّف.
// ═══════════════════════════════════════════════════════════════════════════
//
// `deleteProduct` (product_crud_dao.dart) بيمسح `_productSearchCache` بس،
// ومش بينده `invalidateProductCache(productId)` — رغم إن تعليق الدالة دي
// مكتوب فيه حرفياً «call after insert/update/**delete**». الحذف هو المكان
// الوحيد اللي نسيها.
//
// النتيجة: `_productByIdCache` — الكاش الموصوف في الكود بإنه «for barcode scan
// flow» — بيفضل شايل نسخة الصنف بـ`isActive: true`، و`getProductById` بيرجّعها
// من الكاش (سطر 258) من غير ما يلمس قاعدة البيانات. فالصنف «المحذوف» لسه
// بيتحلّ في مسار الباركود لحد ما الكاش يتطرد بالـLRU (٢٠٠ صنف) أو التطبيق
// يتقفل.
//
// جيرانها بيعملوا الصح: updateProductStock (‏:668) و adjustProductStockGlobal
// (‏:679) الاتنين بيندهوا invalidateProductCache.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';

void main() {
  late AppDatabase db;
  late int productId;
  late int warehouseId;

  setUp(() async {
    db = AppDatabase.forTesting();
    productId = await db.into(db.products).insert(ProductsCompanion.insert(
          name: 'صنف للاختبار',
          code: 'P-DEL-1',
        ));
    warehouseId = await db
        .into(db.warehouses)
        .insert(WarehousesCompanion.insert(name: 'مخزن'));
  });

  tearDown(() => db.close());

  test('الصنف بيتقرا نشط قبل الحذف (ضابط)', () async {
    final p = await db.getProductById(productId);
    expect(p, isNotNull);
    expect(p!.isActive, isTrue);
  });

  test('بعد الحذف، القراءة بالمعرّف بتدّي isActive=false مش النسخة المكاشة',
      () async {
    // بيملا _productByIdCache — ده بالظبط اللي بيحصل مع أول مسح باركود.
    final before = await db.getProductById(productId);
    expect(before!.isActive, isTrue);

    await db.deleteProduct(productId);

    final after = await db.getProductById(productId);
    expect(after, isNotNull);
    expect(after!.isActive, isFalse,
        reason: 'الكاش كان بيرجّع الصنف المحذوف كأنه لسه نشط');
  });

  test('الحذف بيشيله من نتائج القائمة النشطة', () async {
    await db.getProductById(productId); // يملا الكاش
    await db.deleteProduct(productId);
    final all = await db.getAllProducts();
    expect(all.any((p) => p.id == productId), isFalse);
  });

  test('الحذف بيترفض لو الصنف عليه معاملات (سلوك مقصود، غير متغيّر)', () async {
    await db.into(db.stockMovements).insert(StockMovementsCompanion.insert(
          productId: productId,
          warehouseId: warehouseId,
          movementType: 'in',
          quantity: 5,
          balanceAfter: 5,
        ));
    await expectLater(
      db.deleteProduct(productId),
      throwsA(isA<Exception>()),
      reason: 'الرسالة بتوجّه المستخدم لإلغاء التفعيل بدل الحذف',
    );
  });
}
