// ═══════════════════════════════════════════════════════════════════════════
// ما تُرمّزه واجهةُ الفلتر لا بد أن يفهمه المحرِّك — والفحصُ بالتنفيذ لا بالشكل.
// ═══════════════════════════════════════════════════════════════════════════
//
// [ReportFilterCondition] هو ما تحمله صفوفُ حوار الإنشاء، و[encodeReportFilters]
// هو الجسرُ الوحيد بينها وبين العمود `filters`. فلو رمّزت الواجهةُ القيمةَ
// نصّاً حيث ينتظر المحرِّك رقماً — أو رمّزت التاريخَ بصيغةٍ لا تُقرأ — رُفض
// التقريرُ **كلُّه** عند التشغيل: صفرُ صفوفٍ بلا رسالةِ خطأ.
//
// ولذلك لا يفحص هذا الاختبارُ **شكلَ** الـJSON، بل يمرّره في `executeReport`
// ويقيس الصفوفَ الراجعة. فحصُ الشكل يُثبّت التنفيذَ الحاليّ ولا يثبت أنه
// مفهوم.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/domain/models/report_filter_condition.dart';

void main() {
  late AppDatabase db;
  var seq = 0;

  Future<int> product(String name, double price, {bool isActive = true}) =>
      db.into(db.products).insert(ProductsCompanion.insert(
            code: 'P${++seq}',
            name: name,
            salePrice: Value(price),
            isActive: Value(isActive),
          ));

  /// يمرّ بنفس مسار الواجهة: شرطٌ يُبنى من حقل، ثم يُرمَّز، ثم يُنفَّذ.
  Future<List<String>> run(
      String entity, String columns, List<ReportFilterCondition> conds) async {
    final id = await db.into(db.customReports).insert(
          CustomReportsCompanion.insert(
            name: 'ت',
            sourceEntity: entity,
            columns: columns,
            filters: Value(encodeReportFilters(conds)),
          ),
        );
    final rows = await db.executeReport(id);
    return rows.map((r) => r[columns.split(',').first.trim()].toString())
        .toList();
  }

  ReportFilterCondition cond(String entity, String key, String op, String v) {
    final f = db.getAvailableFields(entity).firstWhere((e) => e['key'] == key);
    return ReportFilterCondition.forField(f, db.getFilterOperators).copyWith(op: op, value: v);
  }

  setUp(() async {
    seq = 0;
    db = AppDatabase.forTesting();
    await product('قلم', 10);
    await product('دفتر', 100);
    await product('حاسوب', 5000);
  });

  tearDown(() => db.close());

  test('الشرطُ الجديد يبدأ بأوّل عاملٍ معروضٍ لنوع الحقل', () {
    final f = db
        .getAvailableFields('products')
        .firstWhere((e) => e['key'] == 'price');
    final c = ReportFilterCondition.forField(f, db.getFilterOperators);
    expect(c.field, 'price');
    expect(c.type, 'number');
    expect(db.getFilterOperators('number').map((o) => o['op']),
        contains(c.op),
        reason: 'عاملٌ ابتدائيّ خارج المعروض = منسدلةٌ فارغةُ الاختيار');
  });

  test('قيمةٌ رقميةٌ مكتوبةٌ نصّاً في الحقل تُقارَن رقماً', () async {
    // ‏`TextFormField` يعطي `String` دائماً. فلو رُمّزت كما هي لصارت مقارنةَ
    // نصٍّ برقمٍ في SQLite — ولا تطابق شيئاً.
    final rows = await run(
        'products', 'name', [cond('products', 'price', '>', '50')]);
    expect(rows, containsAll(<String>['دفتر', 'حاسوب']));
    expect(rows, isNot(contains('قلم')));
  });

  test('المنطقيُّ يُرمَّز قيمةً منطقيةً لا نصَّ "false"', () async {
    await product('موقوف', 9, isActive: false);
    final rows = await run(
        'products', 'name', [cond('products', 'is_active', '=', 'false')]);
    expect(rows, ['موقوف']);
  });

  test('التاريخُ يُرمَّز بصيغةٍ يقرأها المحرِّك', () async {
    final wh = await db
        .into(db.warehouses)
        .insert(WarehousesCompanion.insert(name: 'مخزن'));
    for (final (n, d) in [
      ('INV-1', DateTime(2026, 8, 10, 14, 30)),
      ('INV-2', DateTime(2026, 8, 12, 8, 0)),
    ]) {
      await db.into(db.salesInvoices).insert(SalesInvoicesCompanion.insert(
            invoiceNumber: n,
            warehouseId: wh,
            userId: 1,
            invoiceDate: d,
          ));
    }

    final rows = await run('sales_invoices', 'invoice_number',
        [cond('sales_invoices', 'date', '=', '2026-08-10')]);
    expect(rows, ['INV-1']);
  });

  test('شرطان يُجمعان بـAND', () async {
    final rows = await run('products', 'name', [
      cond('products', 'price', '>', '5'),
      cond('products', 'price', '<', '1000'),
    ]);
    expect(rows, containsAll(<String>['قلم', 'دفتر']));
    expect(rows, isNot(contains('حاسوب')));
  });

  test('بلا شروطٍ ⇒ `null` لا نصٌّ فارغٌ ولا "[]"', () {
    expect(encodeReportFilters(const []), isNull,
        reason: 'العمودُ nullable — وقيمةٌ غيرُ فارغةٍ بلا شرطٍ تُوهم '
            'أن للتقرير فلتراً');
  });

  group('اكتمالُ الشرط', () {
    test('شرطٌ بلا قيمة غيرُ مكتمل', () {
      expect(cond('products', 'name', '=', '').isComplete, isFalse);
    });

    test('المنطقيُّ مكتملٌ دائماً — "لا" قيمةٌ صحيحة', () {
      expect(cond('products', 'is_active', '=', 'false').isComplete, isTrue);
    });

    test('الرقميُّ بقيمةٍ غيرِ رقميةٍ غيرُ مكتمل', () {
      expect(cond('products', 'price', '>', 'غالي').isComplete, isFalse,
          reason: 'يرفضه المحرِّك، فمنعُه عند الحفظ أوضح من تقريرٍ '
              'محفوظٍ لا يُنتج صفاً أبداً');
    });
  });
}
