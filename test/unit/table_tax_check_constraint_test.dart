import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';

/// ضريبةٌ «مفعَّلةٌ» بنسبةِ صفرٍ — الحالةُ التي تكذب على المستخدم.
///
/// الزرُّ يقول «مفعلة (0%)»، والمحرّكان يتّفقان على الصفر فلا حارسَ يُطلق،
/// وتُرحَّل الفاتورةُ بضريبةِ صفرٍ: تقصيرٌ صامتٌ في التحصيل والزرُّ ظاهرٌ أنه
/// مفعَّل. `TableSessionService.setOrderTax` يرفضها عند المفتاح، لكنّ الرفضَ
/// عند بابٍ واحدٍ ليس امتناعاً: أيُّ مسارِ كتابةٍ آخر — DAO جديد، تحديثٌ
/// مجمَّع، سكربتُ إصلاح، SQL بيدٍ — يعيد تمثيلَها.
///
/// هذا الملفُّ يقيس أنها صارت **مستحيلةَ التمثيل** لا مرفوضةً عند الكتابة:
/// القيدُ في الجدول نفسِه، فيسري على `INSERT` و`UPDATE` وعلى كلِّ مَن يكتب.
void main() {
  /// شكلُ `table_orders` قبل v156 بحرفه — منقولٌ من `sqlite_master` على قاعدةٍ
  /// حقيقيّةٍ عند v155، لا مكتوباً بالتخمين. مجموعةُ «قاعدةٌ مُرقّاة» تبني
  /// هذا الشكلَ ثم تُشغّل الترقيةَ الحقيقيّةَ فوقه.
  const v155TableOrders = '''
CREATE TABLE "table_orders" (
  "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  "table_id" INTEGER NOT NULL REFERENCES restaurant_tables (id),
  "status" TEXT NOT NULL DEFAULT 'open',
  "total" REAL NOT NULL DEFAULT 0.0,
  "user_id" INTEGER NULL REFERENCES users (id),
  "merged_to_id" INTEGER NULL REFERENCES table_orders (id),
  "guest_count" INTEGER NOT NULL DEFAULT 1,
  "notes" TEXT NULL,
  "discount_type" TEXT NULL,
  "discount_value" REAL NOT NULL DEFAULT 0.0,
  "tax_enabled" INTEGER NOT NULL DEFAULT 0 CHECK ("tax_enabled" IN (0, 1)),
  "tax_rate" REAL NOT NULL DEFAULT 0.0,
  "paid_amount" REAL NOT NULL DEFAULT 0.0,
  "opened_at" INTEGER NOT NULL DEFAULT (CAST(strftime('%s', CURRENT_TIMESTAMP) AS INTEGER)),
  "closed_at" INTEGER NULL
)''';

  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting();
  });
  tearDown(() => db.close());

  Future<String> tableOrdersSql() async {
    final rows = await db
        .customSelect("SELECT sql FROM sqlite_master WHERE name = 'table_orders'")
        .get();
    return rows.single.read<String>('sql');
  }

  Matcher throwsCheckViolation() => throwsA(predicate(
        (e) => e.toString().toLowerCase().contains('check constraint failed'),
        'throws a CHECK constraint violation',
      ));

  Future<int> seedTable(String name) => db.createTable(name: name);

  // ═══════════════════════════════════════════════════════════════════════
  group('قاعدةٌ جديدة — الحالةُ الكاذبة مرفوضةٌ في الجدول نفسِه', () {
    test('تفعيلٌ بنسبةِ صفرٍ يُرفض عند الإدراج', () async {
      final tableId = await seedTable('ط١');
      await expectLater(
        db.into(db.tableOrders).insert(TableOrdersCompanion.insert(
              tableId: tableId,
              taxEnabled: const Value(true),
              taxRate: const Value(0),
            )),
        throwsCheckViolation(),
      );
    });

    test('تفعيلٌ بنسبةٍ سالبةٍ يُرفض كذلك — لا ثغرةَ تحت الصفر', () async {
      final tableId = await seedTable('ط٢');
      await expectLater(
        db.into(db.tableOrders).insert(TableOrdersCompanion.insert(
              tableId: tableId,
              taxEnabled: const Value(true),
              taxRate: const Value(-0.16),
            )),
        throwsCheckViolation(),
      );
    });

    test('تفعيلٌ بنسبةٍ موجبةٍ يُقبل — الميزةُ لم تُمنع', () async {
      final tableId = await seedTable('ط٣');
      final id = await db.into(db.tableOrders).insert(
            TableOrdersCompanion.insert(
              tableId: tableId,
              taxEnabled: const Value(true),
              taxRate: const Value(0.16),
            ),
          );
      expect(id, greaterThan(0));
    });

    test('إطفاءٌ بنسبةِ صفرٍ يُقبل — وهو حالُ كلِّ طلبٍ يُفتَح', () async {
      final tableId = await seedTable('ط٤');
      final id = await db.into(db.tableOrders).insert(
            TableOrdersCompanion.insert(tableId: tableId),
          );
      expect(id, greaterThan(0));
    });

    test('إطفاءٌ ونسبةٌ محفوظةٌ يُقبل — اللقطةُ تبقى والزرُّ مطفأ', () async {
      // هذا هو حالُ الطلبِ لحظةَ فتحه: النسبةُ تُلقَط من الإعداد و`taxEnabled`
      // يبقى `false` حتى يضغط الكاشيرُ الزرَّ. لو رفضه القيدُ لَما فُتحت طاولةٌ.
      final tableId = await seedTable('ط٥');
      final id = await db.into(db.tableOrders).insert(
            TableOrdersCompanion.insert(
              tableId: tableId,
              taxEnabled: const Value(false),
              taxRate: const Value(0.16),
            ),
          );
      expect(id, greaterThan(0));
    });

    test('تصفيرُ النسبةِ على طلبٍ مفعَّلٍ يُرفض — القيدُ يسري على التحديث',
        () async {
      // الحارسُ في الخدمة يحمي مفتاحَ التفعيل وحدَه. تصفيرُ النسبةِ من تحته
      // يصنع الحالةَ الكاذبةَ نفسَها بلا أن يمرَّ على الحارس.
      final tableId = await seedTable('ط٦');
      final id = await db.into(db.tableOrders).insert(
            TableOrdersCompanion.insert(
              tableId: tableId,
              taxEnabled: const Value(true),
              taxRate: const Value(0.16),
            ),
          );
      await expectLater(
        (db.update(db.tableOrders)..where((o) => o.id.equals(id)))
            .write(const TableOrdersCompanion(taxRate: Value(0))),
        throwsCheckViolation(),
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  group('القيدُ أُضيف ولم يُبدِل — لا مفتاحَ سقط', () {
    // `customConstraints` في drift **تُضاف** إلى تعريف الجدول لا تحلُّ محلَّه
    // (بُرهنَ على قاعدةٍ حقيقيّة). ولو انقلب هذا في ترقيةِ حزمةٍ يوماً،
    // فالثمنُ ثلاثةُ مفاتيحَ خارجيّةٍ ومفتاحٌ أساسيٌّ تسقط بصمت — فهذا الفوجُ
    // يقرأ نصَّ `CREATE TABLE` الفعليَّ ويأبى أن يمرَّ ذلك صامتاً.
    test('نصُّ الجدول يحمل القيدَ الجديدَ والمفاتيحَ الثلاثةَ معاً', () async {
      final sql = await tableOrdersSql();
      expect(sql, contains('REFERENCES restaurant_tables (id)'));
      expect(sql, contains('REFERENCES users (id)'));
      expect(sql, contains('REFERENCES table_orders (id)'));
      expect(sql, contains('PRIMARY KEY AUTOINCREMENT'));
      // `tax_enabled` يحمل أصلاً قيدَ drift للمنطقيّات (`IN (0, 1)`)، فمجرّد
      // ذكرِ CHECK لا يدلّ. القيدُ المقصودُ هو الذي يذكر النسبةَ.
      expect(sql, contains('tax_rate > 0'));
    });

    test('المفتاحُ الخارجيُّ ما زال مُنفَذاً بعد إضافة القيد', () async {
      await expectLater(
        db.into(db.tableOrders).insert(
              TableOrdersCompanion.insert(tableId: 999999),
            ),
        throwsA(predicate((e) =>
            e.toString().toLowerCase().contains('foreign key constraint'))),
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  group('قاعدةٌ مُرقّاة من v155 — لا افتراضاً بل ترقيةً تُشغَّل', () {
    late int tableId;
    late int productId;

    /// يهدم `table_orders` إلى شكلِ v155، يزرع فيه صفوفاً منها الكاذبُ، ثم
    /// يُشغّل `runOnUpgrade` الحقيقيَّ — نفسَ الكود الذي يعمل عند الإقلاع.
    Future<void> degradeToV155AndUpgrade() async {
      await db.customStatement('PRAGMA foreign_keys = OFF');
      await db.customStatement('DROP TABLE table_orders');
      await db.customStatement(v155TableOrders);

      // ١ — الكاذب: مفعَّلٌ بنسبةِ صفر، وله بندٌ وابنٌ في جدول البنود.
      await db.customStatement(
          'INSERT INTO table_orders (id, table_id, status, total, guest_count, '
          'discount_value, tax_enabled, tax_rate, paid_amount, opened_at) '
          "VALUES (1, $tableId, 'open', 100.0, 2, 0.0, 1, 0.0, 0.0, 1000)");
      // ٢ — صحيحٌ مفعَّل: يجب أن يخرج من الترقية كما دخل.
      await db.customStatement(
          'INSERT INTO table_orders (id, table_id, status, total, guest_count, '
          'discount_value, tax_enabled, tax_rate, paid_amount, opened_at) '
          "VALUES (2, $tableId, 'open', 50.0, 4, 5.0, 1, 0.16, 20.0, 2000)");
      // ٣ — مطفأٌ ونسبتُه محفوظة: الحالةُ الشائعةُ بعد v155.
      await db.customStatement(
          'INSERT INTO table_orders (id, table_id, status, total, guest_count, '
          'discount_value, tax_enabled, tax_rate, paid_amount, opened_at) '
          "VALUES (3, $tableId, 'closed', 30.0, 1, 0.0, 0, 0.16, 30.0, 3000)");
      await db.customStatement(
          'INSERT INTO table_order_items (id, table_order_id, product_id, '
          'quantity, unit_price, total, tax_rate, tax_amount) '
          'VALUES (1, 1, $productId, 2.0, 50.0, 100.0, 0.0, 0.0)');
      await db.customStatement('PRAGMA foreign_keys = ON');

      await db.runOnUpgrade(Migrator(db), 155, 156);
    }

    setUp(() async {
      tableId = await seedTable('ط-ترقية');
      productId = await db
          .into(db.products)
          .insert(ProductsCompanion.insert(code: 'MIG-1', name: 'مشويّ'));
      await degradeToV155AndUpgrade();
    });

    test('الصفُّ الكاذبُ سُوّي إلى «بلا ضريبة» — لا حُذف ولا بقي يكذب',
        () async {
      final row = await (db.select(db.tableOrders)
            ..where((o) => o.id.equals(1)))
          .getSingle();
      // الفاتورةُ خرجت بضريبةِ صفرٍ فعلاً، فإطفاءُ الزرِّ هو ما يجعل السجلَّ
      // يطابق ما حُصِّل حقّاً. والصفُّ يبقى — بياناتُه ليست خطأً يُمحى.
      expect(row.taxEnabled, isFalse);
      expect(row.total, 100.0);
      expect(row.guestCount, 2);
    });

    test('الصفُّ الصحيحُ عبر الترقيةَ بلا خدش', () async {
      final row = await (db.select(db.tableOrders)
            ..where((o) => o.id.equals(2)))
          .getSingle();
      expect(row.taxEnabled, isTrue);
      expect(row.taxRate, 0.16);
      expect(row.total, 50.0);
      expect(row.guestCount, 4);
      expect(row.discountValue, 5.0);
      expect(row.paidAmount, 20.0);
      expect(row.status, 'open');
    });

    test('المطفأُ بنسبةٍ محفوظةٍ لم يُمسّ — القيدُ لا يطارد نسبةً مطفأة',
        () async {
      final row = await (db.select(db.tableOrders)
            ..where((o) => o.id.equals(3)))
          .getSingle();
      expect(row.taxEnabled, isFalse);
      expect(row.taxRate, 0.16);
      expect(row.paidAmount, 30.0);
      expect(row.status, 'closed');
    });

    test('القيدُ موجودٌ بعد الترقيةِ ويرفض الحالةَ الكاذبة', () async {
      expect(await tableOrdersSql(), contains('tax_rate > 0'));
      await expectLater(
        db.into(db.tableOrders).insert(TableOrdersCompanion.insert(
              tableId: tableId,
              taxEnabled: const Value(true),
              taxRate: const Value(0),
            )),
        throwsCheckViolation(),
      );
    });

    test('إعادةُ إنشاءِ الجدول لم تكسر ابناً يشير إليه', () async {
      // إعادةُ الإنشاء تُسقط الجدولَ وتُعيد تسميةَ بديله. لو تسرّبت إشارةُ
      // `table_order_items` إلى الاسم المؤقّت لَانقطعت العلاقةُ صامتةً.
      final orphans =
          await db.customSelect('PRAGMA foreign_key_check').get();
      expect(orphans, isEmpty);

      final items = await db.getTableOrderItems(1);
      expect(items, hasLength(1));
      expect(items.single.total, 100.0);

      // والمفتاحُ حيٌّ لا نصٌّ: أبٌ غيرُ موجودٍ يُرفض.
      await expectLater(
        db.customStatement(
            'INSERT INTO table_order_items (table_order_id, product_id, '
            'quantity, unit_price, total) '
            'VALUES (999999, $productId, 1.0, 1.0, 1.0)'),
        throwsA(predicate((e) =>
            e.toString().toLowerCase().contains('foreign key constraint'))),
      );
    });

    test('الإشارةُ الذاتيّةُ ما زالت تُنفَذ بعد إعادة الإنشاء', () async {
      // `merged_to_id` يشير إلى `table_orders` نفسِه — وهو أخطرُ ما في إعادة
      // الإنشاء: الجدولُ المؤقّتُ يُكتَب باسم الجدول الأصليّ في هذه الإشارة.
      await db.customStatement(
          'UPDATE table_orders SET merged_to_id = 2 WHERE id = 3');
      final row = await (db.select(db.tableOrders)
            ..where((o) => o.id.equals(3)))
          .getSingle();
      expect(row.mergedToId, 2);

      await expectLater(
        db.customStatement(
            'UPDATE table_orders SET merged_to_id = 999999 WHERE id = 3'),
        throwsA(predicate((e) =>
            e.toString().toLowerCase().contains('foreign key constraint'))),
      );
    });
  });
}
