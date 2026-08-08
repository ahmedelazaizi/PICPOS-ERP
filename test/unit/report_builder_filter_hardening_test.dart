// ═══════════════════════════════════════════════════════════════════════════
// فلتر منشئ التقارير كان بيتحقن كـSQL خام — وبيكسر حصر الفروع.
// ═══════════════════════════════════════════════════════════════════════════
//
// `_buildWhereClause` كان بيرجّع النص المخزَّن كما هو («Filters are stored as
// pre-built WHERE conditions»)، من غير أي تحقّق.
//
// وده مش سطح حقن نظري: الاستعلام بقى `WHERE (حصر الفروع) AND (فلتر المستخدم)`،
// ففلتر زي `1=1) OR (1=1` بينتج:
//
//     WHERE (branch_id IN (1)) AND (1=1) OR (1=1)
//
// والـOR بيلغي الشرطين اللي قبله ⇒ **الحصر اللي لسه اتركّب بيتكسر**. يعني
// الفلتر مش بس بيقرا جداول تانية، ده بيتخطّى الطبقة الوحيدة اللي بتحمي
// بيانات الفروع.
//
// الإصلاح تحصين لا إعادة تصميم: الصيغة المخزَّنة فضلت «شرط WHERE جاهز»، بس
// بترفض الأشكال اللي بتسمح بالهروب — أقواس غير متوازنة، تعليقات، فاصلة
// منقوطة، اقتباس غير مغلق. تقرير موجود بفلتر سليم بيفضل شغّال زي ما هو.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';

void main() {
  late AppDatabase db;
  late int branchA;
  late int branchB;

  Future<int> report(String filters) =>
      db.into(db.customReports).insert(CustomReportsCompanion.insert(
            name: 'ت',
            sourceEntity: 'sales_invoices',
            columns: 'invoice_number',
            filters: Value(filters),
          ));

  setUp(() async {
    db = AppDatabase.forTesting();
    branchA = await db.into(db.branches).insert(BranchesCompanion.insert(
        name: 'فرع أ', globalId: const Value('gid-br-f-a')));
    branchB = await db.into(db.branches).insert(BranchesCompanion.insert(
        name: 'فرع ب', globalId: const Value('gid-br-f-b')));
    final wh = await db
        .into(db.warehouses)
        .insert(WarehousesCompanion.insert(name: 'مخزن'));

    for (final (n, br) in [('INV-A', branchA), ('INV-B', branchB)]) {
      await db.into(db.salesInvoices).insert(SalesInvoicesCompanion.insert(
            invoiceNumber: n,
            warehouseId: wh,
            userId: 1,
            invoiceDate: DateTime(2026, 8, 10),
            branchId: Value(br),
            total: const Value(100),
          ));
    }
  });

  tearDown(() => db.close());

  test('فلتر سليم لسه شغّال — التحصين مش بيكسر تقارير قائمة', () async {
    final id = await report("sales_invoices.total > 50");
    final rows = await db.executeReport(id);
    expect(rows.length, 2);
  });

  test('🔴 فلتر بيكسر الحصر بأقواس غير متوازنة بيترفض', () async {
    final id = await report('1=1) OR (1=1');
    final rows = await db.executeReport(id, allowedBranchIds: {branchA});
    expect(rows, isEmpty,
        reason: 'من غير التحصين ده كان بيرجّع فاتورة فرع ب كمان — '
            'الـOR بيلغي شرط الحصر اللي قبله');
  });

  test('تعليق SQL بيترفض (بيقص باقي الشرط)', () async {
    final id = await report("1=1 --");
    expect(await db.executeReport(id, allowedBranchIds: {branchA}), isEmpty);
  });

  test('فاصلة منقوطة بترفض (جملة تانية)', () async {
    final id = await report('1=1; DROP TABLE sales_invoices');
    expect(await db.executeReport(id, allowedBranchIds: {branchA}), isEmpty);
    // الجدول لازم يفضل موجود — الرفض قبل التنفيذ لا بعده.
    expect((await db.select(db.salesInvoices).get()).length, 2);
  });

  test('اقتباس غير مغلق بيترفض', () async {
    final id = await report("invoice_number = 'A");
    expect(await db.executeReport(id, allowedBranchIds: {branchA}), isEmpty);
  });

  test('الرفض بيسري كمان على مستخدم بوصول كامل', () async {
    // الحقن مش خطره على الحصر بس — قراءة جداول تانية بـUNION مثلاً.
    final id = await report('1=1) OR (1=1');
    expect(await db.executeReport(id), isEmpty);
  });
}
