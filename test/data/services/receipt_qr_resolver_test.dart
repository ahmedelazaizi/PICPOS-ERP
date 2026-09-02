// ═══════════════════════════════════════════════════════════════════════════
// حلُّ رمز الإيصال من القاعدة — الرايةُ وصفُّ التقديم يُقرآن من مكانهما.
// ═══════════════════════════════════════════════════════════════════════════
//
// `receipt_qr_decision_test` يقيس القرارَ دالّةً خالصة. وهذا الملفُّ يقيس
// الطبقةَ التي تُطعمها: أنّ الرايةَ تُقرأ من `Settings` بمفتاحها الصحيح،
// وأنّ صفَّ التقديم يُقرأ من `e_invoice_submissions` بـ`saleId` الصحيح —
// فلا يسقط القرارُ الصحيحُ في الطريق بمفتاحٍ مغلوطٍ أو معرِّفٍ مغلوط.
//
// ── الغيابُ = غيرُ مُفعَّل ─────────────────────────────────────────────────
// منشأةٌ لم تفتح الفاتورةَ الإلكترونيّةَ قطُّ لا تكتب الرايةَ أبداً. فلو
// كان الغيابُ «لا رمز» لفقد كلُّ من لا يستعملها الرمزَ البديلَ عن الورق.
// والنافذةُ بين تفعيلِ الخادم ووصولِ الراية بالسحب الأوّل نافذةُ تصميم
// المزامنة نفسِها لا نافذةُ هذا الملفّ.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/data/services/receipt_qr_resolver.dart';
import 'package:ural_erp/domain/models/receipt_qr_decision.dart';

void main() {
  late AppDatabase db;

  const sale = ReceiptSaleSummary(
    invoiceNumber: 'INV-7',
    issuedAt: '2026-09-02 10:00',
    total: '99.00',
    companyName: 'شركة',
  );

  setUp(() {
    db = AppDatabase.forTesting();
  });

  tearDown(() => db.close());

  Future<ReceiptQr> resolve({int saleId = 42}) =>
      resolveReceiptQrForSale(db, saleId: saleId, sale: sale);

  /// يزرع فاتورةَ بيعٍ حقيقيّةً — `e_invoice_submissions.sale_id` مفتاحٌ
  /// أجنبيٌّ مُنفَّذٌ على SQLite الاختبار، فلا يُقبل معرِّفٌ عائم.
  Future<int> seedSale(String number) async {
    final branchId = await db.into(db.branches).insert(
        BranchesCompanion.insert(name: 'فرع', globalId: Value('br-$number')));
    final whId = await db.into(db.warehouses).insert(WarehousesCompanion.insert(
        name: 'مخزن', branchId: Value(branchId), globalId: Value('wh-$number')));
    return db.into(db.salesInvoices).insert(SalesInvoicesCompanion.insert(
      invoiceNumber: number,
      warehouseId: whId,
      userId: 1,
      invoiceDate: DateTime(2026, 9, 2),
      total: const Value(99),
    ));
  }

  /// يزرع تقديماً بلغ حالةً معيّنة، ويعيد معرِّفه.
  Future<int> seedSubmission({
    required int saleId,
    required String status,
    String? qr,
  }) async {
    final id = await db.createSubmission(saleId: saleId, platform: 'eta');
    await db.markSubmissionSuccess(
      submissionId: id,
      submissionUuid: 'SUB-$saleId',
      qrCode: qr,
    );
    await db.updateSubmissionStatus(id, status);
    return id;
  }

  test('لا رايةَ مكتوبةً ⇒ غيرُ مُفعَّل ⇒ رمزٌ غيرُ ضريبيّ', () async {
    final qr = await resolve();

    expect(qr.kind, ReceiptQrKind.nonFiscal);
  });

  test("الرايةُ 'false' ⇒ رمزٌ غيرُ ضريبيّ", () async {
    await db.setSetting(kEInvoiceEnabledSettingKey, 'false');

    expect((await resolve()).kind, ReceiptQrKind.nonFiscal);
  });

  test("الرايةُ 'true' ولا تقديمَ ⇒ لا رمز", () async {
    await db.setSetting(kEInvoiceEnabledSettingKey, 'true');

    expect((await resolve()).kind, ReceiptQrKind.none);
  });

  test("الرايةُ 'true' وتقديمٌ معتمَدٌ بحمولة ⇒ الرمزُ الضريبيُّ كما ورد",
      () async {
    await db.setSetting(kEInvoiceEnabledSettingKey, 'true');
    final saleId = await seedSale('INV-7');
    await seedSubmission(saleId: saleId, status: 'valid', qr: 'AQ1RUUE=');

    final qr = await resolve(saleId: saleId);

    expect(qr.kind, ReceiptQrKind.fiscal);
    expect(qr.payload, 'AQ1RUUE=');
  });

  // 🔴 مرساةُ المعرِّف: التقديمُ لبيعةٍ **أخرى** لا يُقرأ لهذه. وإلّا طُبع
  //    رمزُ فاتورةٍ على إيصال غيرها — وهو أسوأُ من غياب الرمز.
  test('تقديمُ بيعةٍ أخرى لا يُحسَب لهذه البيعة', () async {
    await db.setSetting(kEInvoiceEnabledSettingKey, 'true');
    final mine = await seedSale('INV-7');
    final other = await seedSale('INV-8');
    await seedSubmission(saleId: other, status: 'valid', qr: 'OTHER=');

    final qr = await resolve(saleId: mine);

    expect(qr.kind, ReceiptQrKind.none,
        reason: 'بيعتي لا تقديمَ لها — فلا رمزَ، لا رمزُ البيعة الأخرى');
  });

  test("تقديمٌ مُرسَلٌ لم يُعتمَد بعد ⇒ لا رمزَ رغم وجود الحمولة", () async {
    await db.setSetting(kEInvoiceEnabledSettingKey, 'true');
    final saleId = await seedSale('INV-7');
    await seedSubmission(saleId: saleId, status: 'submitted', qr: 'AQ1RUUE=');

    expect((await resolve(saleId: saleId)).kind, ReceiptQrKind.none);
  });
}
