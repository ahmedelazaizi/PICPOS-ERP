// ═══════════════════════════════════════════════════════════════════════════
// مانعُ Go ٦‑١ — `e_invoice_status_log` غائبٌ عن كلِّ تنصيبةِ SQLite جديدة
// ═══════════════════════════════════════════════════════════════════════════
//
// 🔴 `EInvoiceStatusLog` له صنفُ جدولٍ في `e_invoicing_tables.dart` لكنّه
// **غيرُ مُعلَنٍ في `@DriftDatabase`**. و`onCreate` يبني من كيانات drift
// وحدَها، و`onUpgrade` لا يعمل على تنصيبةٍ جديدة — فهجرةُ v81 التي تُنشئ
// الجدولَ لا تصل إلّا قاعدةً مُرقّاة.
//
// و`e_invoicing_dao` يكتبه ويقرؤه بـSQL خامّ، فينهار بـ«no such table»
// على كلِّ جهازٍ نُصِّب حديثاً — وهذا هو الوضعُ الافتراضيُّ لكلِّ عميلٍ
// جديدٍ في الميدان.
//
// وهو نفسُ العطب الموثَّق في `database_startup` لفهارس v150/v152/v159:
// «‏`createAll()` يبني من كيانات drift، والخامُّ لا يصله».
//
// والقياسُ هنا على **قاعدةٍ جديدةٍ فعلاً** (`AppDatabase.forTesting()` يمرّ
// بنفس `onCreate`)، لا على قراءةِ كودٍ ولا على ترقية.

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting());
  tearDown(() => db.close());

  Future<bool> tableExists(String name) async {
    final rows = await db.customSelect(
      "SELECT name FROM sqlite_master WHERE type='table' AND name = ?",
      variables: [Variable<String>(name)],
    ).get();
    return rows.isNotEmpty;
  }

  test('التجهيزة: جدولٌ معلَنٌ في drift موجودٌ على التنصيبة الجديدة', () async {
    expect(await tableExists('e_invoice_submissions'), isTrue,
        reason: 'مرساةٌ — لو فشلت هنا فالاستعلامُ نفسُه غلط، لا الجدولُ '
            'المقصود');
  });

  test('e_invoice_status_log موجودٌ على تنصيبةٍ جديدة', () async {
    // 🔴 المعطوب: غيرُ موجودٍ إطلاقاً.
    expect(await tableExists('e_invoice_status_log'), isTrue,
        reason: 'الجدولُ يُنشأ في `onCreate` بـSQL خامٍّ لأنّه ليس كيانَ '
            'drift — كما تُنشأ الفهارسُ الخامّةُ بجانبه');
  });

  test('الكتابةُ والقراءةُ تعملان — لا «no such table»', () async {
    // سلسلةُ المفاتيح الأجنبيّة: سجلُّ الحالات → الإرسال → الفاتورة.
    final wh = await db.getDefaultWarehouse();
    final saleId = await db.into(db.salesInvoices).insert(
          SalesInvoicesCompanion.insert(
            invoiceNumber: 'EINV-LOG-1',
            warehouseId: wh!.id,
            userId: 1,
            invoiceDate: DateTime(2026, 8, 30),
          ),
        );
    await db.customStatement(
      'INSERT INTO e_invoice_submissions (sale_id, platform, status) '
      'VALUES (?, ?, ?)',
      [saleId, 'eta', 'draft'],
    );
    final subId = (await db.customSelect(
      'SELECT id FROM e_invoice_submissions LIMIT 1',
    ).getSingle())
        .data['id'] as int;

    // عينُ ما يفعله `e_invoicing_dao` — SQL خامٌّ على جدولٍ خامّ.
    await db.customStatement(
      'INSERT INTO e_invoice_status_log '
      '(submission_id, old_status, new_status, changed_by, notes) '
      'VALUES (?, ?, ?, ?, ?)',
      [subId, 'draft', 'submitted', 'tester', 'اختبار'],
    );

    final rows = await db.customSelect(
      'SELECT * FROM e_invoice_status_log WHERE submission_id = ? '
      'ORDER BY changed_at ASC',
      variables: [Variable<int>(subId)],
    ).get();

    expect(rows, hasLength(1));
    expect(rows.first.data['new_status'], 'submitted');
  });
}
