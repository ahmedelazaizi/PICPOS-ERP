// ═══════════════════════════════════════════════════════════════════════════
// مِكنسةُ الفاتورة الإلكترونيّة — أيُّ فاتورةٍ تنتظر تقديماً؟
// ═══════════════════════════════════════════════════════════════════════════
//
// ═══ لماذا مِكنسةٌ لا خُطّافُ نداء ═══
//
// قرارُ المالك: الخادمُ وحدَه ينشئ التقديمَ ويرسل. والفواتيرُ تصل الخادمَ
// **بالمزامنة** من كلّ كاشير — لا بمعالج الـAPI وحدَه. فخُطّافٌ عند مواضع
// `createSalesInvoice` الخمسة كان سيُغفل **كلَّ فاتورةٍ جاءت من جهاز**، وهي
// الأغلب. والمِكنسةُ تمسح ما وصل أيّاً كان طريقُه، وتعمل بعد إعادة التشغيل،
// وتُعيد المحاولةَ بلا حالةٍ في الذاكرة.
//
// ⚠️ **والاختيارُ لا يشمل المرتجعات**: إشعارُ الائتمان يحتاج ربطاً بالفاتورة
// الأصليّة وسقفاً على مبلغه (‏`createCreditNoteSubmission`)، ولا يُشتقّ من
// صفِّ المرتجع وحدَه. فيُترك لمساره، ويُقال هنا صراحةً بدل مسحٍ يُنتج مستنداً
// بلا أصلٍ يشير إليه.

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';

void main() {
  late AppDatabase db;
  late int whId;

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.saveEInvoiceConfig(
      platform: 'eta',
      clientId: 'id',
      clientSecret: 'secret',
      registrationNumber: '100',
      isEnabled: true,
    );
    final branchId = await db.into(db.branches).insert(
        BranchesCompanion.insert(name: 'ف', globalId: const Value('br-sw')));
    whId = await db.into(db.warehouses).insert(WarehousesCompanion.insert(
        name: 'م',
        branchId: Value(branchId),
        globalId: const Value('wh-sw')));
  });

  tearDown(() => db.close());

  Future<int> sale(
    String number, {
    String status = 'completed',
    String saleType = 'default',
    DateTime? deletedAt,
  }) =>
      db.into(db.salesInvoices).insert(SalesInvoicesCompanion.insert(
            invoiceNumber: number,
            warehouseId: whId,
            userId: 1,
            invoiceDate: DateTime(2026, 9, 1),
            total: const Value(100),
            status: Value(status),
            saleType: Value(saleType),
            deletedAt: Value(deletedAt),
          ));

  test('مرساة: فاتورةٌ مكتملةٌ بلا تقديمٍ تُلتقَط', () async {
    final id = await sale('A-1');

    final due = await db.findSalesNeedingEInvoiceSubmission(limit: 50);

    expect(due, contains(id),
        reason: 'بلا هذا لا تُقدَّم فاتورةٌ إطلاقاً — والمِكنسةُ بلا عمل');
  });

  test('🔴 فاتورةٌ لها تقديمٌ قائمٌ لا تُلتقَط ثانيةً', () async {
    final id = await sale('A-2');
    await db.createSubmission(saleId: id, platform: 'eta');

    expect(await db.findSalesNeedingEInvoiceSubmission(limit: 50),
        isNot(contains(id)),
        reason: 'التقاطُها ثانيةً يُنتج مستندَين ضريبيَّين لفاتورةٍ واحدة');
  });

  test('🔴 المرتجعُ خارجَ المكنسة — إشعارُ الائتمان مسارٌ آخر', () async {
    final id = await sale('R-1', saleType: 'return');

    expect(await db.findSalesNeedingEInvoiceSubmission(limit: 50),
        isNot(contains(id)),
        reason: 'إشعارُ ائتمانٍ بلا فاتورةٍ أصليّةٍ يشير إليها مستندٌ باطل');
  });

  test('🔴 غيرُ المكتملة لا تُقدَّم — لا مستندَ ضريبيَّ لبيعةٍ لم تتمّ', () async {
    final pending = await sale('P-1', status: 'pending');

    expect(await db.findSalesNeedingEInvoiceSubmission(limit: 50),
        isNot(contains(pending)));
  });

  test('🔴 والمحذوفُ ناعماً لا يُقدَّم', () async {
    final gone = await sale('D-1', deletedAt: DateTime(2026, 9, 2));

    expect(await db.findSalesNeedingEInvoiceSubmission(limit: 50),
        isNot(contains(gone)));
  });

  test('الحدُّ يُحترَم — المكنسةُ لا تسحب الطابورَ كلَّه دفعةً', () async {
    for (var i = 0; i < 5; i++) {
      await sale('L-$i');
    }

    expect(await db.findSalesNeedingEInvoiceSubmission(limit: 2), hasLength(2));
  });

  test('والأقدمُ أوّلاً — الترتيبُ بالمعرّف', () async {
    final first = await sale('O-1');
    await sale('O-2');

    final due = await db.findSalesNeedingEInvoiceSubmission(limit: 50);

    expect(due.first, first, reason: 'تقديمُ الأحدث قبل الأقدم يقلب الترتيب '
        'الزمنيَّ للمستندات لدى المصلحة');
  });
}
