// ═══════════════════════════════════════════════════════════════════════════
// أرشفةُ حركات المخزون القديمة — عمودٌ موجودٌ وربطٌ بالثواني
// ═══════════════════════════════════════════════════════════════════════════
//
// `archiveOldStockMovements()` كانت ترشِّح على `movement_date` — عمودٌ لا وجودَ
// له في `stock_movements`؛ التعريفُ يحمل `createdAt` فيولّده drift باسم
// `created_at`، و`grep movement_date database.g.dart` يعطي صفراً. فكانت الدالّةُ
// ترمي «no such column» في كلِّ نداء، ولم يكشفها شيءٌ لأنّها بلا اختبار.
//
// وكان الربطُ متناقضاً كذلك: `SELECT` يمرّر `Variable(DateTime)` بينما `DELETE`
// يمرّر ثوانيَ الحقبة. والاتّفاقُ في المستودع ثوانٍ — انظر `AppDatabase.dateVar`.
//
// فهذه الاختباراتُ تستدعي الدالّةَ فعلاً على قاعدةٍ في الذاكرة: تؤكّد أنّ القديمَ
// يُؤرشَف، وأنّ الحديثَ ينجو، وأنّ العددَ المُعادَ هو عينُ ما حُذف — أي أنّ
// `SELECT` و`DELETE` يقيسان بنفس المسطرة.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';

void main() {
  late AppDatabase db;
  late int warehouseId;
  late int productId;

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.delete(db.stockMovements).go();

    warehouseId = await db.into(db.warehouses).insert(
      WarehousesCompanion.insert(
        name: 'مخزنُ الأرشفة',
        isActive: const Value(true),
      ),
    );
    productId = await db.into(db.products).insert(
      ProductsCompanion.insert(
        code: 'ARC-1',
        name: 'صنفُ الأرشفة',
        salePrice: const Value(10.0),
        costPrice: const Value(5.0),
        trackInventory: const Value(true),
      ),
    );
  });

  tearDown(() async {
    await db.close();
  });

  /// يُدرج حركةً واحدةً بتاريخِ إنشاءٍ صريح، ويعيد معرِّفها.
  Future<int> insertMovement(DateTime createdAt) {
    return db.into(db.stockMovements).insert(
      StockMovementsCompanion.insert(
        productId: productId,
        warehouseId: warehouseId,
        movementType: 'adjustment',
        quantity: 1.0,
        balanceAfter: 1.0,
        createdAt: Value(createdAt),
      ),
    );
  }

  Future<List<int>> remainingIds() async {
    final rows = await db.select(db.stockMovements).get();
    return rows.map((r) => r.id).toList()..sort();
  }

  group('archiveOldStockMovements', () {
    test('يؤرشف الحركةَ القديمةَ ويُبقي الحديثة', () async {
      final now = DateTime.now();
      final oldId = await insertMovement(now.subtract(const Duration(days: 900)));
      final recentId = await insertMovement(now.subtract(const Duration(days: 10)));

      // الافتراضيُّ ٢٤ شهراً ⇒ عتبةٌ عند ٧٢٠ يوماً: ٩٠٠ خارجها و١٠ داخلها.
      final archived = await db.archiveOldStockMovements();

      expect(archived, 1, reason: 'حركةٌ واحدةٌ فقط أقدمُ من العتبة');
      expect(await remainingIds(), [recentId],
          reason: 'الحديثةُ تنجو والقديمةُ ($oldId) تُحذَف');
    });

    test('العددُ المُعادُ هو عينُ ما حُذف — SELECT وDELETE بنفس المسطرة', () async {
      final now = DateTime.now();
      for (var i = 0; i < 3; i++) {
        await insertMovement(now.subtract(Duration(days: 800 + i)));
      }
      final survivors = <int>[
        await insertMovement(now.subtract(const Duration(days: 5))),
        await insertMovement(now.subtract(const Duration(days: 400))),
      ];
      survivors.sort();

      final archived = await db.archiveOldStockMovements();

      expect(archived, 3, reason: 'ثلاثُ حركاتٍ أقدمُ من ٧٢٠ يوماً');
      expect(await remainingIds(), survivors,
          reason: 'ما نجا يطابق ما وعد به العدُّ — لا حذفَ زائدٌ ولا ناقص');
    });

    test('لا يحذف شيئاً حين تكون كلُّ الحركات داخل مدّة الاحتفاظ', () async {
      final now = DateTime.now();
      final ids = <int>[
        await insertMovement(now.subtract(const Duration(days: 1))),
        await insertMovement(now.subtract(const Duration(days: 100))),
      ];
      ids.sort();

      final archived = await db.archiveOldStockMovements();

      expect(archived, 0);
      expect(await remainingIds(), ids,
          reason: 'عتبةٌ مقيسةٌ بالمللي بدل الثواني كانت ستمحوها جميعاً');
    });

    test('retentionMonths يُغيِّر العتبةَ فعلاً', () async {
      final now = DateTime.now();
      await insertMovement(now.subtract(const Duration(days: 45)));
      final recentId = await insertMovement(now.subtract(const Duration(days: 10)));

      // شهرٌ واحد ⇒ عتبةٌ عند ٣٠ يوماً: ٤٥ خارجها و١٠ داخلها.
      final archived = await db.archiveOldStockMovements(retentionMonths: 1);

      expect(archived, 1);
      expect(await remainingIds(), [recentId]);
    });
  });
}
