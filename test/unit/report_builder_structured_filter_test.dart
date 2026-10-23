// ═══════════════════════════════════════════════════════════════════════════
// §٥/٢ — فلترُ منشئ التقارير: صيغةٌ مهيكلة بمعاملاتٍ مربوطة.
// ═══════════════════════════════════════════════════════════════════════════
//
// السكيما **توثّق العقد** منذ البداية:
//     /// Filter conditions as JSON: [{"field":"price","op":">","value":100}]
//     TextColumn get filters => text().nullable()();
// والتنفيذُ كان يعامل العمودَ **نصَّ SQL خاماً** ويُلحقه بالـ`WHERE` كما هو.
//
// فالعطلُ ليس أمنياً بالدرجة الأولى — لا مسارَ في التطبيق يُنشئ فلتراً أصلاً
// (الواجهةُ لا تمرّره و`custom_reports` غيرُ مُزامَن) — بل **تخالفُ التنفيذِ
// لعقده المكتوب**: من يبني واجهةَ الفلتر يتبع تعليقَ السكيما، فيكتب JSON
// مهيكلاً، فيُبثّ كـSQL ⇒ استعلامٌ مكسور أو تقريرٌ مرفوض.
//
// ── والأمانُ من البناء لا من الفحص ─────────────────────────────────────────
// اسمُ العمود يُختار من `getAvailableFields(sourceEntity)` — **قائمةٌ مغلقة** —
// والقيمةُ تُربَط معاملاً. فلا يوجد نصٌّ من المستخدم يصل إلى الـSQL، والحقنُ
// يصير مستحيلاً بالبناء لا مرفوضاً بفحصٍ يُنسى تحديثه.
//
// ── والمسارُ الخام يبقى مقبولاً ─────────────────────────────────────────────
// UralCash **مطروح**، وحذفُ المسار كسرٌ لمنتجٍ مطروح مقابل فائدةٍ صفر. فالخامُّ
// يبقى محصَّناً للنصوص القديمة، والمهيكلُ هو ما تنتجه الواجهةُ الجديدة. والتمييزُ
// بأول حرفٍ غيرِ فراغ: `[` ⇒ مهيكل.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';

void main() {
  late AppDatabase db;
  late int branchA;
  late int whA;
  var seq = 0;

  Future<int> report(String entity, String columns, {Object? filters}) =>
      db.into(db.customReports).insert(CustomReportsCompanion.insert(
            name: 'ت',
            sourceEntity: entity,
            columns: columns,
            filters: Value(filters is String ? filters : jsonEncode(filters)),
          ));

  Future<int> product(String name, double price,
          {String? barcode, bool isActive = true}) =>
      db.into(db.products).insert(ProductsCompanion.insert(
            code: 'P${++seq}',
            name: name,
            barcode: Value(barcode),
            salePrice: Value(price),
            costPrice: Value(price / 2),
            isActive: Value(isActive),
          ));

  Future<int> invoice(String number, DateTime date, {double total = 100}) =>
      db.into(db.salesInvoices).insert(SalesInvoicesCompanion.insert(
            invoiceNumber: number,
            warehouseId: whA,
            userId: 1,
            invoiceDate: date,
            branchId: Value(branchA),
            total: Value(total),
          ));

  setUp(() async {
    seq = 0;
    db = AppDatabase.forTesting();
    branchA = await db.into(db.branches).insert(BranchesCompanion.insert(
        name: 'فرع أ', globalId: const Value('gid-sf-a')));
    whA = await db.into(db.warehouses).insert(
        WarehousesCompanion.insert(name: 'مخزن أ', branchId: Value(branchA)));
    await product('قلم', 10);
    await product('دفتر', 100);
    await product('حاسوب', 5000);
  });

  tearDown(() => db.close());

  Future<List<String>> names(int reportId, {Set<int>? scope}) async {
    final rows = await db.executeReport(reportId, allowedBranchIds: scope);
    return rows.map((r) => r['name'] as String).toList();
  }

  group('عوامل المقارنة على الأرقام', () {
    test('أكبر من', () async {
      final id = await report('products', 'name',
          filters: [
            {'field': 'price', 'op': '>', 'value': 50}
          ]);
      expect(await names(id), containsAll(<String>['دفتر', 'حاسوب']));
      expect(await names(id), isNot(contains('قلم')));
    });

    test('أصغر من أو يساوي', () async {
      final id = await report('products', 'name',
          filters: [
            {'field': 'price', 'op': '<=', 'value': 100}
          ]);
      final n = await names(id);
      expect(n, containsAll(<String>['قلم', 'دفتر']));
      expect(n, isNot(contains('حاسوب')));
    });

    test('يساوي', () async {
      final id = await report('products', 'name',
          filters: [
            {'field': 'price', 'op': '=', 'value': 100}
          ]);
      expect(await names(id), ['دفتر']);
    });

    test('لا يساوي', () async {
      final id = await report('products', 'name',
          filters: [
            {'field': 'price', 'op': '!=', 'value': 100}
          ]);
      expect(await names(id), isNot(contains('دفتر')));
    });

    test('الفلترُ يترجم اسمَ الحقل بنفس خريطة الأعمدة', () async {
      // `price` ليس اسمَ العمود — العمودُ `sale_price`. لو افترق الفلترُ عن
      // خريطةِ `SELECT` لصار `no such column` أو فلترةً على عمودٍ آخر.
      final id = await report('products', 'name, price',
          filters: [
            {'field': 'price', 'op': '>', 'value': 4000}
          ]);
      final rows = await db.executeReport(id);
      expect(rows.map((r) => r['name']), ['حاسوب']);
      expect(rows.first['price'], 5000);
    });
  });

  group('عوامل النصّ', () {
    test('يحتوي', () async {
      final id = await report('products', 'name',
          filters: [
            {'field': 'name', 'op': 'contains', 'value': 'حاس'}
          ]);
      expect(await names(id), ['حاسوب']);
    });

    test('يحتوي — % في القيمة نصٌّ لا محرفُ بدل', () async {
      await product('خصم %50', 7);
      // ‏«دفتر ٥٠ ورقة» هو ما يوقع الطفرة: بلا هروبِ `%` يصير النمطُ `%%50%`
      // فيلتقطه، ومعه يصير النمطُ `%\%50%` فلا يلتقطه إلا حرفياً.
      await product('دفتر 50 ورقة', 8);
      final id = await report('products', 'name',
          filters: [
            {'field': 'name', 'op': 'contains', 'value': '%50'}
          ]);
      expect(await names(id), ['خصم %50'],
          reason: 'القيمةُ مربوطةٌ معاملاً ومهروبةٌ، فـ% داخلها نصٌّ');
    });

    test('يحتوي — _ في القيمة نصٌّ لا محرفَ واحدٍ أيّاً كان', () async {
      await product('A_B', 3);
      await product('AXB', 4);
      final id = await report('products', 'name',
          filters: [
            {'field': 'name', 'op': 'contains', 'value': 'A_B'}
          ]);
      expect(await names(id), ['A_B'],
          reason: '`_` محرفُ بدلٍ في LIKE تماماً كـ%');
    });

    test('لا يساوي يشمل الصفوفَ الخالية', () async {
      await product('بلا باركود', 3);
      await product('له باركود', 4, barcode: 'BC-1');
      final id = await report('products', 'name',
          filters: [
            {'field': 'barcode', 'op': '!=', 'value': 'BC-1'}
          ]);
      expect(await names(id), contains('بلا باركود'),
          reason: 'صنفٌ بلا باركود «ليس BC-1» فعلاً — و`!= ?` وحدَه '
              'يُسقطه لأن مقارنةَ NULL تُنتج NULL');
      expect(await names(id), isNot(contains('له باركود')));
    });
  });

  group('المنطقيّ', () {
    test('يساوي false يرجّع غيرَ النشط وحده', () async {
      await product('موقوف', 9, isActive: false);
      final id = await report('products', 'name',
          filters: [
            {'field': 'is_active', 'op': '=', 'value': false}
          ]);
      expect(await names(id), ['موقوف']);
    });
  });

  group('التواريخ — دلالةُ اليوم لا اللحظة', () {
    setUp(() async {
      await invoice('INV-08', DateTime(2026, 8, 10, 14, 30));
      await invoice('INV-09', DateTime(2026, 8, 11, 9, 0));
      await invoice('INV-10', DateTime(2026, 8, 12, 23, 59));
    });

    Future<List<String>> numbers(int id) async {
      final rows = await db.executeReport(id);
      return rows.map((r) => r['invoice_number'] as String).toList();
    }

    test('يساوي يوماً يشمل اليومَ كلَّه لا لحظةَ منتصف الليل', () async {
      final id = await report('sales_invoices', 'invoice_number',
          filters: [
            {'field': 'date', 'op': '=', 'value': '2026-08-10'}
          ]);
      expect(await numbers(id), ['INV-08'],
          reason: 'الفاتورةُ في ١٤:٣٠ — مطابقةُ اللحظةِ تُرجع صفراً صامتاً');
    });

    test('أصغر من أو يساوي يشمل آخرَ اليوم', () async {
      final id = await report('sales_invoices', 'invoice_number',
          filters: [
            {'field': 'date', 'op': '<=', 'value': '2026-08-11'}
          ]);
      expect(await numbers(id), ['INV-08', 'INV-09'],
          reason: 'فاتورةُ ٠٩:٠٠ من يوم ١١ داخلةٌ في «حتى ١١»');
    });

    test('أكبر من يومٍ يبدأ من اليوم التالي', () async {
      final id = await report('sales_invoices', 'invoice_number',
          filters: [
            {'field': 'date', 'op': '>', 'value': '2026-08-11'}
          ]);
      expect(await numbers(id), ['INV-10']);
    });
  });

  group('شروطٌ متعدّدة تُجمَع بـAND', () {
    test('نطاقٌ سعريّ', () async {
      final id = await report('products', 'name',
          filters: [
            {'field': 'price', 'op': '>', 'value': 5},
            {'field': 'price', 'op': '<', 'value': 1000},
          ]);
      final n = await names(id);
      expect(n, containsAll(<String>['قلم', 'دفتر']));
      expect(n, isNot(contains('حاسوب')));
    });
  });

  group('الرفض — الأمان من البناء', () {
    test('حقلٌ خارج القائمة المغلقة يُرفَض التقريرُ كلُّه', () async {
      final id = await report('products', 'name',
          filters: [
            {'field': 'id) OR 1=1 --', 'op': '=', 'value': 1}
          ]);
      expect(await names(id), isEmpty,
          reason: 'اسمُ العمود من `getAvailableFields` وحدها');
    });

    test('حقلٌ سليمُ الشكل لكن ليس من حقول الكيان يُرفَض', () async {
      final id = await report('products', 'name',
          filters: [
            {'field': 'balance', 'op': '>', 'value': 0}
          ]);
      expect(await names(id), isEmpty,
          reason: '`balance` حقلُ الأطراف لا الأصناف');
    });

    test('عاملٌ غيرُ مدعوم يُرفَض', () async {
      final id = await report('products', 'name',
          filters: [
            {'field': 'price', 'op': 'GLOB', 'value': '*'}
          ]);
      expect(await names(id), isEmpty);
    });

    test('عاملٌ لا يليق بنوع الحقل يُرفَض', () async {
      final id = await report('products', 'name',
          filters: [
            {'field': 'price', 'op': 'contains', 'value': '10'}
          ]);
      expect(await names(id), isEmpty,
          reason: '«يحتوي» على رقمٍ يفلتر بالنصّ فيعطي نتائجَ غيرَ متوقَّعة');
    });

    test('قيمةٌ غيرُ رقميةٍ لحقلٍ رقميّ تُرفَض لا تُرجع صفراً صامتاً', () async {
      final id = await report('products', 'name',
          filters: [
            {'field': 'price', 'op': '>', 'value': 'غالي'}
          ]);
      expect(await names(id), isEmpty);
      // ⚠️ «فارغ» وحدَه **لا يميّز**: لو مُرِّر النصُّ معاملاً لكان
      // `sale_price > 'غالي'` فارغاً أيضاً — فالنصُّ في SQLite أكبرُ من كلِّ
      // رقم. فالدليلُ أن الاستعلامَ **لم يُنفَّذ أصلاً**: سجلُّ التشغيل
      // (`saved_report_runs`) لا يُكتَب إلا بعد تنفيذٍ فعليّ.
      expect(await db.select(db.savedReportRuns).get(), isEmpty,
          reason: 'الرفضُ قبل التنفيذ لا بعده');
    });

    test('JSON مهيكلٌ فاسد يُرفَض لا يُبَثّ SQL', () async {
      final id = await report('products', 'name', filters: '[{"field":');
      expect(await names(id), isEmpty);
    });

    test('قائمةٌ فارغة لا تكسر الاستعلام', () async {
      final id = await report('products', 'name', filters: <Object>[]);
      expect(await names(id), hasLength(3),
          reason: 'بلا شروطٍ ⇒ بلا تقييد، لا `WHERE ()` مكسور');
    });

    test('قيمةٌ نصّيةٌ فيها اقتباسٌ لا تكسر الاستعلام', () async {
      await product("قلم O'Brien", 3);
      final id = await report('products', 'name',
          filters: [
            {'field': 'name', 'op': '=', 'value': "قلم O'Brien"}
          ]);
      expect(await names(id), ["قلم O'Brien"],
          reason: 'المعاملُ المربوطُ يمرّر الاقتباسَ نصّاً');
    });
  });

  group('الحصرُ يبقى فوق الفلتر', () {
    test('فلترٌ مهيكلٌ لا يوسّع نطاق الفروع', () async {
      await invoice('INV-A', DateTime(2026, 8, 10));
      final id = await report('sales_invoices', 'invoice_number',
          filters: [
            {'field': 'total', 'op': '>', 'value': 0}
          ]);

      final rows = await db.executeReport(id, allowedBranchIds: <int>{});
      expect(rows, isEmpty, reason: 'الحصرُ الفاشلُ مقفولاً يغلب أي فلتر');
    });
  });

  group('المسارُ الخام لم يُكسَر', () {
    test('نصُّ SQL سليمٌ لا يزال يعمل', () async {
      final id = await report('products', 'name',
          filters: 'products.sale_price > 50');
      expect(await names(id), containsAll(<String>['دفتر', 'حاسوب']));
    });

    test('نصٌّ خامٌّ يحاول الهروب لا يزال يُرفَض', () async {
      final id = await report('products', 'name', filters: '1=1) OR (1=1');
      expect(await names(id), isEmpty);
    });
  });
}
