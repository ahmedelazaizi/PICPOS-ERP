// ═══════════════════════════════════════════════════════════════════════════
// §٣‑٤(ب) — «تجميعٌ حسب» كان يعطي قيمةً عشوائيّةً تُقرأ مجموعاً فرعيّاً.
// ═══════════════════════════════════════════════════════════════════════════
//
// `_buildReportQuery` كان يركّب `GROUP BY` بينما `SELECT` يبقى أعمدةً عاريةً.
// وSQLite تُرجع حينئذٍ قيمةَ **صفٍّ عشوائيٍّ** من داخل المجموعة. فمن يبني
// «تجميعاً حسب العميل» بعمودِ «الإجمالي» يرى رقماً واحداً لكلّ عميلٍ يظنّه
// مجموعَ فواتيره — وهو إجماليُّ **فاتورةٍ واحدةٍ** منها.
//
// ومعه: عمودُ `aggregates` كان يُحفَظ من الواجهة **ولا يُقرأ في المحرّك
// إطلاقاً** — لوحةٌ كاملةٌ إعدادُها ميّت.
//
// ── السياسة (قرارُ مالكٍ 2026-08-31) ──────────────────────────────────────
//   • حقلٌ في `GROUP BY`             → عارياً
//   • حقلٌ له دالّةٌ معلَنة           → `FN(expr)`
//   • حقلٌ **رقميٌّ** بلا دالّة       → `SUM(expr)`
//   • حقلٌ نصّيٌّ/تاريخيٌّ بلا دالّة   → عارياً
//   • **بلا `GROUP BY`** لا تُطبَّق دالّةٌ إطلاقاً — سردُ صفوف
//
// ⚠️ **والقياسُ على رقمٍ لا يمكن أن يخرج مصادفةً**: الفاتورتان ١٠٠ و٣٠٠،
// فالمجموعُ ٤٠٠ لا يساوي أيّاً منهما ولا المتوسّطَ (٢٠٠) ولا العدَّ (٢).
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';

void main() {
  late AppDatabase db;
  late int customerA;
  late int customerB;

  Future<int> report({
    required String columns,
    String? groupBy,
    String? aggregates,
  }) =>
      db.into(db.customReports).insert(CustomReportsCompanion.insert(
            name: 'ت',
            sourceEntity: 'sales_invoices',
            columns: columns,
            groupBy: Value(groupBy),
            aggregates: Value(aggregates),
          ));

  Future<void> invoice(String no, int customer, double total) =>
      db.into(db.salesInvoices).insert(SalesInvoicesCompanion.insert(
            invoiceNumber: no,
            warehouseId: 1,
            userId: 1,
            invoiceDate: DateTime(2026, 3, 5),
            customerId: Value(customer),
            total: Value(total),
            tax: Value(total / 10),
          ));

  setUp(() async {
    db = AppDatabase.forTesting();
    customerA = await db
        .into(db.parties)
        .insert(PartiesCompanion.insert(name: 'عميل أ'));
    customerB = await db
        .into(db.parties)
        .insert(PartiesCompanion.insert(name: 'عميل ب'));

    // عميلُ أ: فاتورتان ١٠٠ و٣٠٠ ⇒ المجموعُ ٤٠٠ · المتوسّطُ ٢٠٠ · العدُّ ٢.
    await invoice('A-1', customerA, 100);
    await invoice('A-2', customerA, 300);
    // عميلُ ب: فاتورةٌ واحدةٌ ٥٠ — حارسٌ أنّ المجموعةَ ذاتَ الصفّ الواحد سليمة.
    await invoice('B-1', customerB, 50);
  });

  tearDown(() => db.close());

  Future<Map<String, Object?>> rowFor(int reportId, String name) async {
    final res = await db.executeReport(reportId);
    return res.firstWhere((r) => r['party_name'] == name);
  }

  test('مرساة: بلا تجميعٍ تُسرَد الفواتيرُ الثلاثُ كما هي', () async {
    final id = await report(columns: 'party_name,total');
    final res = await db.executeReport(id);

    expect(res.length, 3, reason: 'السردُ العاديُّ يجب ألّا يتأثّر');
    expect(
        res.map((r) => (r['total'] as num).toDouble()).toList()..sort(),
        [50.0, 100.0, 300.0]);
  });

  test('🔴 التجميعُ حسب العميل يجمع الإجماليَّ — ٤٠٠ لا ١٠٠ ولا ٣٠٠', () async {
    final id = await report(columns: 'party_name,total', groupBy: 'party_name');

    expect((await rowFor(id, 'عميل أ'))['total'], 400.0,
        reason: 'كان يُرجَع إجماليُّ فاتورةٍ عشوائيّةٍ (١٠٠ أو ٣٠٠) '
            'ويُقرأ مجموعاً فرعيّاً');
  });

  test('مجموعةٌ بصفٍّ واحدٍ تبقى صحيحة', () async {
    final id = await report(columns: 'party_name,total', groupBy: 'party_name');
    expect((await rowFor(id, 'عميل ب'))['total'], 50.0);
  });

  test('🔴 الدالّةُ المعلَنةُ تُطبَّق — AVG يعطي ٢٠٠ لا ٤٠٠', () async {
    final id = await report(
      columns: 'party_name,total',
      groupBy: 'party_name',
      aggregates: jsonEncode({'total': 'AVG'}),
    );

    expect((await rowFor(id, 'عميل أ'))['total'], 200.0,
        reason: 'عمودُ `aggregates` كان يُحفَظ ولا يُقرأ إطلاقاً');
  });

  test('الدالّةُ المعلَنةُ تغلب الافتراضَ على حقلٍ وتترك أخاه له', () async {
    final id = await report(
      columns: 'party_name,total,tax',
      groupBy: 'party_name',
      aggregates: jsonEncode({'tax': 'MAX'}),
    );
    final row = await rowFor(id, 'عميل أ');

    expect(row['total'], 400.0, reason: '`total` بلا دالّةٍ ⇒ SUM افتراضاً');
    expect(row['tax'], 30.0, reason: '`tax` معلَنةٌ MAX ⇒ أكبرُ الضريبتَين');
  });

  test('COUNT على حقلٍ يعطي عددَ صفوف المجموعة', () async {
    final id = await report(
      columns: 'party_name,total',
      groupBy: 'party_name',
      aggregates: jsonEncode({'total': 'COUNT'}),
    );

    expect((await rowFor(id, 'عميل أ'))['total'], 2);
  });

  test('حقلُ التجميع نفسُه لا يُجمَع', () async {
    final id = await report(columns: 'party_name', groupBy: 'party_name');
    final res = await db.executeReport(id);

    expect(res.map((r) => r['party_name']).toList()..sort(),
        ['عميل أ', 'عميل ب']);
  });

  test('🔴 دالّةٌ خارج القائمة المغلقة ⇒ يُرفَض التقريرُ كلُّه', () async {
    final id = await report(
      columns: 'party_name,total',
      groupBy: 'party_name',
      // ‏`GROUP_CONCAT` دالّةٌ حقيقيّةٌ في SQLite لكنّها ليست في القائمة —
      // فالرفضُ على السجلّ المغلق لا على «هل تعرفها المحرّك».
      aggregates: jsonEncode({'total': 'GROUP_CONCAT'}),
    );

    expect(await db.executeReport(id), isEmpty);
  });

  test('🔴 حقلُ دالّةٍ ليس من حقول الكيان ⇒ يُرفَض التقريرُ كلُّه', () async {
    final id = await report(
      columns: 'party_name,total',
      groupBy: 'party_name',
      aggregates: jsonEncode({'salary': 'SUM'}),
    );

    expect(await db.executeReport(id), isEmpty);
  });

  test('`aggregates` ليست JSON ⇒ يُرفَض ولا يُبتلَع', () async {
    final id = await report(
      columns: 'party_name,total',
      groupBy: 'party_name',
      aggregates: 'SUM(total)',
    );

    expect(await db.executeReport(id), isEmpty);
  });

  test('دالّةٌ معلَنةٌ بلا تجميعٍ لا تُطبَّق — سردُ صفوفٍ كما هو', () async {
    final id = await report(
      columns: 'party_name,total',
      aggregates: jsonEncode({'total': 'SUM'}),
    );

    expect((await db.executeReport(id)).length, 3,
        reason: 'بلا مجموعاتٍ ينهار الناتجُ إلى صفٍّ واحدٍ لم يطلبه أحد');
  });
}
