// ═══════════════════════════════════════════════════════════════════════════
// الفلترُ المهيكل على PostgreSQL — ‏`IS NOT` ليست لغةً مشتركة.
// ═══════════════════════════════════════════════════════════════════════════
//
// المحرِّك يبني `!=` بـ`IS NOT` كي لا تُسقِط مقارنةُ NULL الصفوفَ الخالية.
// و`x IS NOT y` عاملٌ صحيح في SQLite — أما في PostgreSQL فـ`IS NOT` لا يقبل
// إلا `NULL`/`TRUE`/`FALSE`/`UNKNOWN`، ونظيرُه هناك `IS DISTINCT FROM`.
//
// فالفرقُ **خطأٌ نحويّ عند التشغيل** لا اختلافُ نتيجة: تقريرٌ بشرط «لا يساوي»
// ينفجر على أيّ تنصيبٍ يعمل على PostgreSQL بينما يمرّ أخضرَ في كلّ اختبارات
// SQLite. ولا تلتقطه سويّةُ الوحدات مهما كثرت.
//
// وهذا الملفّ يشغّل الصيغةَ المهيكلة كاملةً على قاعدةٍ حيّة: العواملُ الرقمية
// والنصّية و«يحتوي» بمحارف البدل و«لا يساوي» على عمودٍ يقبل NULL.
// ═══════════════════════════════════════════════════════════════════════════

@Tags(['pg'])
library;

import 'dart:convert';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';

import '_support/pg_fixture.dart';

void main() {
  late PgTestFixture fx;

  setUpAll(() async {
    fx = await bootPgTestSchema();
    final db = fx.db;
    await db.into(db.products).insert(ProductsCompanion.insert(
        code: 'PG1', name: 'قلم', salePrice: const Value(10)));
    await db.into(db.products).insert(ProductsCompanion.insert(
        code: 'PG2',
        name: 'حاسوب',
        barcode: const Value('BC-1'),
        salePrice: const Value(5000)));
    await db.into(db.products).insert(ProductsCompanion.insert(
        code: 'PG3', name: 'خصم %50', salePrice: const Value(7)));
    await db.into(db.products).insert(ProductsCompanion.insert(
        code: 'PG4', name: 'دفتر 50 ورقة', salePrice: const Value(8)));
  });

  tearDownAll(() async => fx.tearDown());

  Future<List<String>> names(List<Map<String, Object?>> filters) async {
    final db = fx.db;
    final id = await db.into(db.customReports).insert(
          CustomReportsCompanion.insert(
            name: 'ت',
            sourceEntity: 'products',
            columns: 'name',
            filters: Value(jsonEncode(filters)),
          ),
        );
    final rows = await db.executeReport(id);
    return rows.map((r) => r['name'] as String).toList()..sort();
  }

  group('الفلترُ المهيكل على PostgreSQL', () {
    test('مقارنةٌ رقمية', () async {
      expect(await names([
        {'field': 'price', 'op': '>', 'value': 1000}
      ]), ['حاسوب']);
    });

    test('«لا يساوي» يشمل الصفوفَ الخالية ولا يكسر الاستعلام', () async {
      // ‏🔴 هنا كان ينفجر: `products.barcode IS NOT $1` خطأٌ نحويّ في
      // PostgreSQL. والثلاثةُ بلا باركود «ليست BC-1» فعلاً.
      expect(await names([
        {'field': 'barcode', 'op': '!=', 'value': 'BC-1'}
      ]), ['خصم %50', 'دفتر 50 ورقة', 'قلم']);
    });

    test('«يحتوي» يهرب محارفَ البدل', () async {
      expect(await names([
        {'field': 'name', 'op': 'contains', 'value': '%50'}
      ]), ['خصم %50'],
          reason: 'بلا هروبٍ يلتقط «دفتر 50 ورقة» أيضاً');
    });

    test('«يحتوي» لا يفرّق بين حالتَي الحرف — كما في SQLite', () async {
      // ‏`LIKE` في SQLite لا يفرّق بين `abc` و`ABC`، وفي PostgreSQL يفرّق.
      // فبلا `ILIKE` يعطي **نفسُ التقرير** نتيجتَين بحسب المحرِّك تحته.
      final db = fx.db;
      await db.into(db.products).insert(ProductsCompanion.insert(
          code: 'PG5', name: 'Laptop PRO', salePrice: const Value(99)));

      expect(await names([
        {'field': 'name', 'op': 'contains', 'value': 'pro'}
      ]), ['Laptop PRO']);
    });

    test('حقلٌ خارج القائمة المغلقة يُرفَض هنا أيضاً', () async {
      expect(await names([
        {'field': 'balance', 'op': '>', 'value': 0}
      ]), isEmpty);
    });
  });
}
