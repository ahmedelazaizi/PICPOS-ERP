// إلغاء فاتورة توصيل بإيراد مؤجل ما كانش بيعكس قيدها.
//
// ── العطل ────────────────────────────────────────────────────────────────────
// `voidSalesInvoice` بيعكس القيد بشرطين، والاتنين بيفشلوا لفاتورة التوصيل:
//
// ١. **البوابة `if (inv.isLocked)`** — `_autoPostDeferredRevenue` بيكتب القيد
//    و**مش بيعمل `isLocked = true`**، على عكس `autoPostCashSale` (‏:552)
//    و`autoPostCreditSale` (‏:809) و`autoPostPurchase` (‏:983).
//
// ٢. **فلتر النوع** `referenceType IN ('sale','sales_invoice')` — والقيد
//    المؤجل بيتكتب بـ`'deferred_sale'`، فمش هيتلقى أبداً حتى لو البوابة عدّت.
//
// ── الأثر ───────────────────────────────────────────────────────────────────
// طلب توصيل ٢٠٠٠ حالته `pending` بياخد قيد:
//   مدين ذمم التوصيل ٢٠٠٠ / دائن ٢١٣٣ إيرادات مقدمة ٢٠٠٠
// المستخدم يلغي الطلب → `voidSalesInvoice` بيرجّع المخزون ويعكس الخزينة
// ويخصم رصيد العميل ويعمل `isDeleted = 1` — و**مفيش قيد عكسي**.
// النتيجة: الأستاذ فيه ٢٠٠٠ ذمم + ٢٠٠٠ إيرادات مقدمة على فاتورة **ملغية**
// ومش موجودة في أي وحدة تانية.
//
// ── ليه الشرط بقى «فيه قيد؟» بدل «مقفولة؟» ──────────────────────────────────
// `isLocked` علامة على «اتقفلت بعد ترحيل» — وهي بتتحط في تلات مسارات من
// أربعة. استعمالها كبوابة للعكس بيربط **صحة الدفاتر** بحقل بيتحط في مكان
// تاني خالص، فأي مسار ترحيل جديد ينسى يحطها بيعيد نفس الباج. السؤال الصح
// هو «فيه قيد مرحَّل للفاتورة دي؟» — وده اللي بيتفحص دلوقتي.
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/domain/entities/accounting_entities.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.syncDefaultAccounts();
  });
  tearDown(() => db.close());

  Future<int> makeInvoice({required bool locked}) async {
    return db.into(db.salesInvoices).insert(SalesInvoicesCompanion.insert(
          invoiceNumber: 'INV-${DateTime.now().microsecondsSinceEpoch}',
          userId: 1,
          warehouseId: 1,
          invoiceDate: DateTime.now(),
          subtotal: const Value(2000.0),
          total: const Value(2000.0),
          paid: const Value(0),
          isLocked: Value(locked),
          globalId: Value('gid-inv-${DateTime.now().microsecondsSinceEpoch}'),
        ));
  }

  Future<void> postJe(int invoiceId, String referenceType) async {
    final ar = await db.getAccountByCode('1121');
    final deferred = await db.getAccountByCode('2133') ??
        await db.getAccountByCode('4121');
    await db.createJournalEntry(
      description: 'قيد اختبار',
      date: DateTime.now(),
      lines: [
        JournalLine(accountId: ar!.id, debit: 2000),
        JournalLine(accountId: deferred!.id, credit: 2000),
      ],
      referenceType: referenceType,
      referenceId: invoiceId,
      isAutoPosted: true,
    );
  }

  Future<int> voidReversalCount(int invoiceId) async {
    final rows = await (db.select(db.journalEntries)
          ..where((e) =>
              e.referenceType.equals('sales_invoice_void') &
              e.referenceId.equals(invoiceId)))
        .get();
    return rows.length;
  }

  test('إلغاء فاتورة توصيل مؤجلة بيعكس قيدها', () async {
    // الحالة الحقيقية: القيد بـ`deferred_sale` والفاتورة **مش** مقفولة.
    final invoiceId = await makeInvoice(locked: false);
    await postJe(invoiceId, 'deferred_sale');

    await db.voidSalesInvoice(invoiceId, reason: 'إلغاء طلب');

    expect(await voidReversalCount(invoiceId), 1,
        reason: 'الأستاذ فاضل فيه ذمم وإيراد مقدم على فاتورة ملغية');
  });

  test('القيد العكسي بيصفّي الحسابين', () async {
    final invoiceId = await makeInvoice(locked: false);
    await postJe(invoiceId, 'deferred_sale');
    final ar = await db.getAccountByCode('1121');

    await db.voidSalesInvoice(invoiceId, reason: 'إلغاء');

    final net = await db.customSelect(
      'SELECT COALESCE(SUM(l.debit - l.credit), 0) AS b '
      'FROM journal_entry_lines l JOIN journal_entries e ON e.id = l.entry_id '
      'WHERE l.account_id = ? AND e.is_posted = 1',
      variables: [Variable<int>(ar!.id)],
    ).getSingle();
    expect(net.data['b'] as double, closeTo(0, 0.01));
  });

  test('البيع النقدي المقفول لسه بيتعكس — السلوك القديم ما اتكسرش', () async {
    final invoiceId = await makeInvoice(locked: true);
    await postJe(invoiceId, 'sales_invoice');

    await db.voidSalesInvoice(invoiceId, reason: 'إلغاء');

    expect(await voidReversalCount(invoiceId), 1);
  });

  test('فاتورة بلا أي قيد ما بتعملش قيد عكسي من العدم', () async {
    final invoiceId = await makeInvoice(locked: false);

    await db.voidSalesInvoice(invoiceId, reason: 'إلغاء');

    expect(await voidReversalCount(invoiceId), 0);
  });

  test('الإلغاء مرتين مرفوض بحارس صريح — مش قيدين عكسيين', () async {
    final invoiceId = await makeInvoice(locked: false);
    await postJe(invoiceId, 'deferred_sale');

    await db.voidSalesInvoice(invoiceId, reason: 'إلغاء');

    // الحارس بيرمي بدل ما يعدّي بصمت — أوضح للمستخدم، والمهم إن القيد
    // العكسي ما اتكررش.
    await expectLater(
      db.voidSalesInvoice(invoiceId, reason: 'إلغاء تاني'),
      throwsA(predicate((e) => e.toString().contains('ملغية بالفعل'))),
    );
    expect(await voidReversalCount(invoiceId), 1);
  });
}
