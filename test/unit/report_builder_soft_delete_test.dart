// ═══════════════════════════════════════════════════════════════════════════
// §٣‑٤(أ) — بانِي التقارير كان يعرض المحذوفَ مع القائم.
// ═══════════════════════════════════════════════════════════════════════════
//
// `report_builder_dao.dart` لم يكن فيه ذكرٌ **واحد** لحذفٍ ناعمٍ إطلاقاً — لا
// `deleted_at` ولا `is_deleted`. فأيُّ تقريرٍ مخصَّصٍ على أيٍّ من ستّةِ كياناتٍ
// كان يجمع الفاتورةَ المحذوفةَ والعميلَ المحذوفَ والقيدَ الملغى مع القائم.
//
// وخطرُه أنّه **غيرُ مرئيّ**: التقريرُ لا يعرض عمودَ الحذف، فالصفُّ المحذوفُ
// يبدو صفّاً عاديّاً، ومجموعُ عمودٍ ماليٍّ يزيد بمقدارِ ما حُذف. ومَن يبني
// تقريرَ مبيعاتٍ مخصَّصاً يقارنه بتقرير المبيعات الرسميّ فيجد فرقاً بلا سبب
// ظاهر — والرسميُّ هو الصحيح.
//
// ── والعمودُ الحاكمُ يختلف بالكيان ────────────────────────────────────────
//   • الفواتيرُ والقيود              → `is_deleted`
//   • الأصنافُ والأطرافُ والموظفون   → `deleted_at IS NULL`
//   • أرصدةُ المخزون                 → لا عمودَ حذفٍ أصلاً
//
// ⚠️ **ولا يُقصى الملغى (`voided`)**: هذا حارسُ حذفٍ لا حارسُ حالة — الفاتورةُ
// الملغاةُ مستندٌ قائمٌ له حالةٌ معروضة. وآخرُ اختبارٍ هنا يقفل ذلك.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';

void main() {
  late AppDatabase db;

  Future<int> report(String entity, String columns) =>
      db.into(db.customReports).insert(CustomReportsCompanion.insert(
          name: 'ت', sourceEntity: entity, columns: columns));

  /// أسماءُ الصفوف الراجعة تحت [key] — أوضحُ من العدّ حين يسقط الفحص.
  Future<List<Object?>> rows(String entity, String columns, String key) async {
    final id = await report(entity, columns);
    final res = await db.executeReport(id);
    return res.map((r) => r[key]).toList();
  }

  setUp(() async {
    db = AppDatabase.forTesting();
  });

  tearDown(() => db.close());

  // ───────────────────────────────────────────────────────────────────────
  // الفواتيرُ — `is_deleted`
  // ───────────────────────────────────────────────────────────────────────

  test('🔴 الفاتورةُ المحذوفةُ لا تظهر في تقريرٍ مخصَّص', () async {
    for (final (no, deleted) in [('INV-LIVE', false), ('INV-GONE', true)]) {
      await db.into(db.salesInvoices).insert(SalesInvoicesCompanion.insert(
            invoiceNumber: no,
            warehouseId: 1,
            userId: 1,
            invoiceDate: DateTime(2026, 3, 5),
            total: const Value(100),
            isDeleted: Value(deleted),
            deletedAt: Value(deleted ? DateTime(2026, 3, 6) : null),
          ));
    }

    final got = await rows('sales_invoices', 'invoice_number', 'invoice_number');

    // مرساة: الاستخراجُ يعمل — القائمةُ ليست فارغةً لسببٍ آخر.
    expect(got, contains('INV-LIVE'),
        reason: 'الفاتورةُ القائمةُ يجب أن تظهر — وإلّا فالفحصُ يقيس عطباً آخر');
    expect(got, isNot(contains('INV-GONE')),
        reason: 'المحذوفةُ كانت تُجمَع مع القائمة بلا عمودٍ يميّزها');
  });

  test('الفاتورةُ الملغاةُ (`voided`) تبقى ظاهرةً — حارسُ حذفٍ لا حارسُ حالة',
      () async {
    await db.into(db.salesInvoices).insert(SalesInvoicesCompanion.insert(
          invoiceNumber: 'INV-VOID',
          warehouseId: 1,
          userId: 1,
          invoiceDate: DateTime(2026, 3, 7),
          total: const Value(100),
          status: const Value('voided'),
        ));

    expect(await rows('sales_invoices', 'invoice_number', 'invoice_number'),
        contains('INV-VOID'),
        reason: 'الملغى مستندٌ قائمٌ له حالةٌ معروضة — إقصاؤه إصلاحٌ زائد');
  });

  // ───────────────────────────────────────────────────────────────────────
  // الأطرافُ والأصناف — `deleted_at`
  // ───────────────────────────────────────────────────────────────────────

  test('🔴 الطرفُ المحذوفُ لا يظهر', () async {
    for (final (name, gone) in [('عميل قائم', false), ('عميل محذوف', true)]) {
      await db.into(db.parties).insert(PartiesCompanion.insert(
            name: name,
            deletedAt: Value(gone ? DateTime(2026, 3, 6) : null),
          ));
    }

    final got = await rows('parties', 'name', 'name');
    expect(got, contains('عميل قائم'));
    expect(got, isNot(contains('عميل محذوف')));
  });

  test('🔴 الصنفُ المحذوفُ لا يظهر', () async {
    for (final (code, gone) in [('P-LIVE', false), ('P-GONE', true)]) {
      await db.into(db.products).insert(ProductsCompanion.insert(
            code: code,
            name: code,
            deletedAt: Value(gone ? DateTime(2026, 3, 6) : null),
          ));
    }

    final got = await rows('products', 'code', 'code');
    expect(got, contains('P-LIVE'));
    expect(got, isNot(contains('P-GONE')));
  });

  // ───────────────────────────────────────────────────────────────────────
  // القيود — `is_deleted`
  // ───────────────────────────────────────────────────────────────────────

  test('🔴 القيدُ المحذوفُ لا يظهر', () async {
    for (final (no, gone) in [('JE-LIVE', false), ('JE-GONE', true)]) {
      await db.into(db.journalEntries).insert(JournalEntriesCompanion.insert(
            entryNumber: no,
            entryDate: DateTime(2026, 3, 5),
            isDeleted: Value(gone),
          ));
    }

    final got = await rows('journal_entries', 'entry_number', 'entry_number');
    expect(got, contains('JE-LIVE'));
    expect(got, isNot(contains('JE-GONE')));
  });

  // ───────────────────────────────────────────────────────────────────────
  // كيانٌ بلا عمودِ حذف
  // ───────────────────────────────────────────────────────────────────────

  test('أرصدةُ المخزون بلا عمودِ حذف ⇒ لا شرطَ ولا رفض', () async {
    final productId = await db.into(db.products).insert(
          ProductsCompanion.insert(code: 'P-BAL', name: 'صنفٌ برصيد'),
        );
    await db.into(db.inventoryBalances).insert(
          InventoryBalancesCompanion.insert(
            productId: productId,
            warehouseId: 1,
            quantity: const Value(5),
          ),
        );

    final id = await report('inventory_balances', 'quantity');
    expect(await db.executeReport(id), isNotEmpty,
        reason: 'إضافةُ شرطٍ على عمودٍ غيرِ موجودٍ كانت ستُفشل الاستعلامَ كلَّه '
            'فيرجع فارغاً — والفراغُ يُقرأ «لا بيانات»');
  });
}
