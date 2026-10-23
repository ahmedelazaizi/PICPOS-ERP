// ═══════════════════════════════════════════════════════════════════════════
// البند ٣‑٥ — تسويةُ ض.ق.م تُنتج تفاوتاً زائفاً
// ═══════════════════════════════════════════════════════════════════════════
//
// ── الجذرُ عطبان، لا واحد ─────────────────────────────────────────────────
//
// (أ) صفُّ المرتجع (`sale_type='return'`) يحمل ضريبةً **موجبةً** وكان
//     يُجمَع كأيِّ بيع، بينما الأستاذُ **يَدين** ضريبةَ المخرجات عند المرتجع.
// (ب) `status NOT IN ('returned','cancelled')` كانت تُسقط الفاتورةَ
//     **الأصليّة**. و`status` حالةٌ **راهنةٌ لا مؤرَّخة** ⇒ مرتجعُ فبراير
//     يبدّل رقمَ يناير بأثرٍ رجعيّ، على شهرٍ قد يكون أُقفل وقُدّم إقرارُه.
//
// ── لماذا لا تكفي صيغةُ الاستبعاد المستعملةُ في تسعةِ مواضع ───────────────
//
// `sale_type != 'return'` صحيحةٌ حيث يُقارَن **إجماليٌّ بإجماليّ**. وهنا
// يُقارَن **صافٍ بصافٍ** والأستاذُ يطرح المرتجع — فالإخفاءُ يُصلح الحالةَ
// الشائعةَ ويترك حالةَ الشهرين مكسورةً إلى الأبد. لذلك: **طرحٌ لا إخفاء**.
//
// ── ولماذا يجب أن ينزل النصفان معاً ───────────────────────────────────────
//
// اختبارُ «المرتجع الكامل» أدناه هو الضابط: بإصلاح (ب) وحدَه يصير طرفُ
// الفواتير `100 + 100 = 200` مقابل `0` — أي الخطأُ يقفز من ١٠٠ إلى ٢٠٠.
//
// وكلُّ توكيدٍ هنا **قيمةٌ محسوبةٌ يدويّاً** لا `> صفر`: نصفُ إصلاحٍ يُنتج
// رقماً موجباً خاطئاً فيمرُّ على توكيدٍ رخو.

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/domain/entities/accounting_entities.dart';

void main() {
  late AppDatabase db;
  late int warehouseId;
  late int customerId;

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.syncDefaultAccounts();
    warehouseId = await db.into(db.warehouses).insert(
        WarehousesCompanion.insert(
            name: 'مخزن ض.ق.م', globalId: const Value('gid-wh-vat')));
    customerId = await db.into(db.parties).insert(PartiesCompanion.insert(
          name: 'عميل ض.ق.م',
          isCustomer: const Value(true),
          globalId: const Value('gid-cust-vat-recon'),
        ));
  });

  // ⚠️ لا `db.close()`: مؤقّتُ drift ينتظر في المنطقة الوهميّة فتتعلّق السويّة.

  /// فاتورةُ بيعٍ أو مرتجعٍ بضريبةٍ معلومة.
  Future<int> insertInvoice({
    required String number,
    required double tax,
    required DateTime date,
    String saleType = 'default',
    String status = 'completed',
  }) =>
      db.into(db.salesInvoices).insert(SalesInvoicesCompanion.insert(
            invoiceNumber: number,
            customerId: Value(customerId),
            warehouseId: warehouseId,
            userId: 1,
            subtotal: Value(tax * 10),
            tax: Value(tax),
            total: Value(tax * 11),
            invoiceDate: date,
            saleType: Value(saleType),
            status: Value(status),
          ));

  /// قيدٌ يحرّك ضريبةَ المخرجات: `credit` للبيع، `debit` للمرتجع.
  Future<void> postVatEntry({
    required DateTime date,
    required double credit,
    required double debit,
    required String refType,
  }) async {
    final vatAcc = (await db.getAccountByCode('2121'))!;
    final cashAcc = (await db.getAccountByCode('1111'))!;
    await db.createJournalEntry(
      description: 'قيد ض.ق.م',
      date: date,
      referenceType: refType,
      referenceId: 0,
      isAutoPosted: true,
      lines: [
        JournalLine(
            accountId: cashAcc.id, debit: credit, credit: debit),
        JournalLine(accountId: vatAcc.id, debit: debit, credit: credit),
      ],
    );
  }

  test('ضابط: بيعٌ بلا مرتجعٍ يتطابق طرفاه', () async {
    await insertInvoice(
        number: 'VR-CTL', tax: 100, date: DateTime(2026, 7, 10));
    await postVatEntry(
        date: DateTime(2026, 7, 10), credit: 100, debit: 0, refType: 'sale');

    final r = await db.getVatReconciliationData(year: 2026, month: 7);
    expect(r.invoiceOutputVat, closeTo(100, 0.01));
    expect(r.glOutputVat, closeTo(100, 0.01));
  });

  test('🔴 مرتجعٌ جزئيٌّ في نفس الشهر — كان الفرقُ ٢× الضريبة', () async {
    // الحالةُ الأشيع. الأصلُ يصير `partial_return` وهي **ليست** في قائمة
    // الاستبعاد القديمة، فيدخل بـ100؛ وصفُّ المرتجع يدخل بـ+30 بدل −30.
    //     قبل الإصلاح: 100 + 30 = 130   مقابل   70   ⇒ فرقٌ +60
    await insertInvoice(
        number: 'VR-1',
        tax: 100,
        date: DateTime(2026, 7, 10),
        status: 'partial_return');
    await insertInvoice(
        number: 'VR-1-R',
        tax: 30,
        date: DateTime(2026, 7, 12),
        saleType: 'return');
    await postVatEntry(
        date: DateTime(2026, 7, 10), credit: 100, debit: 0, refType: 'sale');
    await postVatEntry(
        date: DateTime(2026, 7, 12),
        credit: 0,
        debit: 30,
        refType: 'sales_return');

    final r = await db.getVatReconciliationData(year: 2026, month: 7);

    expect(r.glOutputVat, closeTo(70, 0.01), reason: 'ضابطُ الأستاذ');
    expect(r.invoiceOutputVat, closeTo(70, 0.01),
        reason: 'كان ١٣٠: الأصلُ يدخل والمرتجعُ يُجمَع بدل أن يُطرَح');
    expect(r.invoiceOutputVat - r.glOutputVat, closeTo(0, 0.01),
        reason: 'التفاوتُ الزائفُ = ٢× ضريبة المرتجع');
  });

  test('🔴 مرتجعٌ كامل — الضابطُ الذي يكشف نصفَ الإصلاح', () async {
    // الأصلُ يصير `returned` فكان **يُسقَط** (‏0)، والمرتجعُ يُجمَع (‏+100)
    //     قبل الإصلاح:   0 + 100 = 100   مقابل   0   ⇒ فرقٌ +100
    // وبإصلاح `status` **وحدَه** بلا تصحيح الإشارة:
    //                  100 + 100 = 200   مقابل   0   ⇒ فرقٌ +200 (أسوأ)
    await insertInvoice(
        number: 'VR-2',
        tax: 100,
        date: DateTime(2026, 7, 5),
        status: 'returned');
    await insertInvoice(
        number: 'VR-2-R',
        tax: 100,
        date: DateTime(2026, 7, 6),
        saleType: 'return');
    await postVatEntry(
        date: DateTime(2026, 7, 5), credit: 100, debit: 0, refType: 'sale');
    await postVatEntry(
        date: DateTime(2026, 7, 6),
        credit: 0,
        debit: 100,
        refType: 'sales_return');

    final r = await db.getVatReconciliationData(year: 2026, month: 7);
    expect(r.glOutputVat, closeTo(0, 0.01));
    expect(r.invoiceOutputVat, closeTo(0, 0.01),
        reason: 'كان ١٠٠؛ وبنصفِ إصلاحٍ يصير ٢٠٠ — أسوأُ من قبله');
  });

  test('🔴 مرتجعٌ في شهرٍ تالٍ لا يبدّل رقمَ الشهر المُقفَل', () async {
    // أخطرُ الحالات: `status` عمودُ حالةٍ راهنةٍ لا مؤرَّخة، فمرتجعُ يوليو
    // كان يُسقط فاتورةَ يونيو من تقرير **يونيو** — شهرٍ قُدّم إقرارُه.
    await insertInvoice(
        number: 'VR-3',
        tax: 100,
        date: DateTime(2026, 6, 10),
        status: 'returned');
    await insertInvoice(
        number: 'VR-3-R',
        tax: 100,
        date: DateTime(2026, 7, 5),
        saleType: 'return');
    await postVatEntry(
        date: DateTime(2026, 6, 10), credit: 100, debit: 0, refType: 'sale');
    await postVatEntry(
        date: DateTime(2026, 7, 5),
        credit: 0,
        debit: 100,
        refType: 'sales_return');

    final june = await db.getVatReconciliationData(year: 2026, month: 6);
    expect(june.glOutputVat, closeTo(100, 0.01), reason: 'ضابطٌ');
    expect(june.invoiceOutputVat, closeTo(100, 0.01),
        reason: 'كان صفراً — إقرارُ يونيو المُقدَّم يتبدّل بأثرٍ رجعيّ');

    final july = await db.getVatReconciliationData(year: 2026, month: 7);
    expect(july.glOutputVat, closeTo(-100, 0.01), reason: 'ضابطٌ');
    expect(july.invoiceOutputVat, closeTo(-100, 0.01),
        reason: 'كان +١٠٠ — بإشارةٍ معكوسةٍ عن الأستاذ');
  });

  // ═════════════════════════════════════════════════════════════════════════
  // طرفُ المشتريات — جذرٌ مختلفٌ ومقدارٌ مختلف
  // ═════════════════════════════════════════════════════════════════════════
  //
  // مرتجعُ الشراء **لا صفَّ له في `purchase_invoices` إطلاقاً**: يعيش قيداً
  // في الأستاذ (`reference_type='purchase_return'`) ومذكرةَ رصيدٍ في
  // `safe_transactions`، ولا مستندَ يحمل ضريبتَه. فالأستاذُ يردُّ ضريبةَ
  // المدخلات والفواتيرُ لا تعرف بذلك ⇒ فرقٌ = ضريبةُ المرتجع **مرّةً
  // واحدة**، لا مرّتين كطرف المبيعات.

  Future<int> insertPurchase({
    required String number,
    required double tax,
    required DateTime date,
  }) async {
    final supplierId = await db.into(db.parties).insert(PartiesCompanion.insert(
          name: 'مورد $number',
          isCustomer: const Value(false),
          isSupplier: const Value(true),
          globalId: Value('gid-supp-$number'),
        ));
    return db.into(db.purchaseInvoices).insert(
        PurchaseInvoicesCompanion.insert(
          invoiceNumber: number,
          supplierId: supplierId,
          warehouseId: warehouseId,
          subtotal: Value(tax * 10),
          tax: Value(tax),
          total: Value(tax * 11),
          invoiceDate: date,
        ));
  }

  /// مستندُ مرتجعِ شراءٍ — §٦‑٢ (v172).
  ///
  /// ⚠️ **أُضيف 2026-09-02 لأنّ مصدرَ ضريبةِ المرتجع تغيّر.** كانت التسويةُ
  /// تشتقُّ المقدارَ **من الأستاذ نفسِه**، فكان قيدُ [postInputVatEntry] وحدَه
  /// يكفي لتغذيتها — وهو بالضبط ما جعل هذا المكوِّنَ لا يُطابَق مطابقةً
  /// مستقلّة: الطرفان يقرآن مصدراً واحداً فيتّفقان بالبناء.
  ///
  /// وصار المرتجعُ يكتب **مستنداً** في `purchase_returns`، فالتجهيزةُ تكتب
  /// الاثنين معاً كما يفعل `autoPostPurchaseReturn` في المسار الحقيقيّ.
  /// وتوكيداتُ هذا الملفّ لم تتغيّر بحرف — تغيّرت التجهيزةُ وحدَها.
  Future<void> postPurchaseReturnDoc({
    required DateTime date,
    required double tax,
    required int invoiceId,
  }) async {
    final inv = await (db.select(db.purchaseInvoices)
          ..where((p) => p.id.equals(invoiceId)))
        .getSingle();
    await db.into(db.purchaseReturns).insert(
          PurchaseReturnsCompanion.insert(
            originalInvoiceId: invoiceId,
            supplierId: inv.supplierId,
            returnDate: date,
            subtotal: Value(tax * 10),
            tax: Value(tax),
            total: Value(tax * 11),
            globalId:
                Value('gid-pret-$invoiceId-${date.millisecondsSinceEpoch}'),
          ),
        );
  }

  /// قيدُ ضريبةِ مدخلات: `debit` للشراء، `credit` لردِّها عند المرتجع.
  Future<void> postInputVatEntry({
    required DateTime date,
    required double debit,
    required double credit,
    required String refType,
    required int refId,
  }) async {
    final vatAcc = (await db.getAccountByCode('1141'))!;
    final cashAcc = (await db.getAccountByCode('1111'))!;
    await db.createJournalEntry(
      description: 'قيد ض.ق.م مدخلات',
      date: date,
      referenceType: refType,
      referenceId: refId,
      isAutoPosted: true,
      lines: [
        JournalLine(accountId: vatAcc.id, debit: debit, credit: credit),
        JournalLine(accountId: cashAcc.id, debit: credit, credit: debit),
      ],
    );
  }

  test('ضابط: شراءٌ بلا مرتجعٍ يتطابق طرفاه', () async {
    final id = await insertPurchase(
        number: 'VP-CTL', tax: 100, date: DateTime(2026, 7, 10));
    await postInputVatEntry(
        date: DateTime(2026, 7, 10),
        debit: 100,
        credit: 0,
        refType: 'purchase',
        refId: id);

    final r = await db.getVatReconciliationData(year: 2026, month: 7);
    expect(r.invoiceInputVat, closeTo(100, 0.01));
    expect(r.glInputVat, closeTo(100, 0.01));
  });

  test('🔴 مرتجعُ شراءٍ — الفرقُ ١× لا ٢×', () async {
    final id = await insertPurchase(
        number: 'VP-1', tax: 100, date: DateTime(2026, 7, 10));
    await postInputVatEntry(
        date: DateTime(2026, 7, 10),
        debit: 100,
        credit: 0,
        refType: 'purchase',
        refId: id);
    // المرتجعُ يردُّ ٣٠ — بلا أيِّ صفٍّ في `purchase_invoices`، ومستندُه في
    // `purchase_returns` كما يكتبه المسارُ الحقيقيّ (§٦‑٢).
    await postInputVatEntry(
        date: DateTime(2026, 7, 15),
        debit: 0,
        credit: 30,
        refType: 'purchase_return',
        refId: id);
    await postPurchaseReturnDoc(
        date: DateTime(2026, 7, 15), tax: 30, invoiceId: id);

    final r = await db.getVatReconciliationData(year: 2026, month: 7);

    expect(r.glInputVat, closeTo(70, 0.01), reason: 'ضابطُ الأستاذ');
    expect(r.invoiceInputVat, closeTo(70, 0.01),
        reason: 'كان ١٠٠: لا صفَّ مرتجعٍ يُطرَح، فالفرقُ ٣٠ دائم');
    // والمقدارُ **يُفصَح عنه** لأنّه مشتقٌّ من الأستاذ لا من مستند.
    expect(r.inputVatReturns, closeTo(30, 0.01),
        reason: 'المقدارُ المطروحُ يجب أن يكون ظاهراً للمحاسب لا مخفيّاً');
  });

  test('مرتجعُ شراءٍ في شهرٍ تالٍ لا يمسّ الشهرَ الأوّل', () async {
    final id = await insertPurchase(
        number: 'VP-2', tax: 100, date: DateTime(2026, 6, 10));
    await postInputVatEntry(
        date: DateTime(2026, 6, 10),
        debit: 100,
        credit: 0,
        refType: 'purchase',
        refId: id);
    await postInputVatEntry(
        date: DateTime(2026, 7, 5),
        debit: 0,
        credit: 100,
        refType: 'purchase_return',
        refId: id);
    await postPurchaseReturnDoc(
        date: DateTime(2026, 7, 5), tax: 100, invoiceId: id);

    final june = await db.getVatReconciliationData(year: 2026, month: 6);
    expect(june.invoiceInputVat, closeTo(100, 0.01));
    expect(june.glInputVat, closeTo(100, 0.01));

    final july = await db.getVatReconciliationData(year: 2026, month: 7);
    expect(july.glInputVat, closeTo(-100, 0.01), reason: 'ضابطٌ');
    expect(july.invoiceInputVat, closeTo(-100, 0.01),
        reason: 'الطرحُ يجب أن يقع في شهر المرتجع لا شهر الشراء');
  });

  test('الملغاةُ تبقى مستبعَدةً — لم يتّسع الترشيحُ خطأً', () async {
    // الإصلاحُ وسّع `status` من ثلاثةٍ إلى اثنين. الضابطُ أنّ `cancelled`
    // ما زالت مستبعَدةً، وإلّا لأدخلنا فواتيرَ ملغاةً في الإقرار.
    await insertInvoice(
        number: 'VR-4',
        tax: 50,
        date: DateTime(2026, 7, 20),
        status: 'cancelled');
    final r = await db.getVatReconciliationData(year: 2026, month: 7);
    expect(r.invoiceOutputVat, closeTo(0, 0.01));
  });
}
