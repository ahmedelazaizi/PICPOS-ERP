// ═══════════════════════════════════════════════════════════════════════════
// تقريبُ الإجماليّ — قياسُ **الوصول** لا العرض (‏المسارُ الحقيقيُّ كاملاً)
// ═══════════════════════════════════════════════════════════════════════════
//
// ⚠️ الفرقُ عن `quick_sale_rounding_autopost_test`: ذاك يُمرّر
// `roundingAdjustment` بيده إلى `db.createSalesInvoice` بـ`deferAutoPost`
// **مطفأً**، فيقيس `autoPostCashSale` في `accounting_autopost_dao` — وهو
// مسارُ الخادم (‏`api_sales_handler`) لا مسارُ الكاشير.
//
// وهذا الملفُّ لا يمرّر الحقلَ إطلاقاً: يكتب `pos_total_rounding` في جدول
// `settings` كما تكتبه شاشةُ السياسة، ثمّ يمرّ بـ
// `SalesTransactionOrchestrator.completeSalesTransaction` — أي بالمسار الذي
// يسلكه زرُّ «دفع» فعلاً — ويقرأ الصفَّ والأستاذَ والدرجَ بعده.
//
// ⚠️⚠️ **والمساران يُنتجان قيدَين مختلفَين.** المنسّقُ يمرّر
// `deferAutoPost: true` للبيعة المستقلّة، فيقع الترحيلُ على
// `JournalEntryFactory.generateSalesAccountingEntry` بـ`referenceType`
// = `sales_invoice`، لا على `autoPostCashSale` بـ`sale`. وهذا الفرقُ هو
// عينُ ما تكشفه الاختباراتُ الموسومةُ `skip` أدناه — اقرأ سببَ كلٍّ منها.

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/data/database/sync_interceptor.dart';
import 'package:picpos_erp/data/repositories/drift_accounting_repository.dart';
import 'package:picpos_erp/data/repositories/returns_repository_impl.dart';
import 'package:picpos_erp/data/repositories/sales_transaction_orchestrator.dart';
import 'package:picpos_erp/domain/entities/cart_item_entity.dart';
import 'package:picpos_erp/domain/entities/product_entity.dart';
import 'package:picpos_erp/domain/models/quick_sale_policy.dart';
import 'package:picpos_erp/domain/repositories/audit_repository_interface.dart';
import 'package:picpos_erp/domain/repositories/i_products_repository.dart';
import 'package:picpos_erp/domain/repositories/inventory_repository.dart';
import 'package:picpos_erp/domain/repositories/parties_repository.dart';
import 'package:picpos_erp/domain/repositories/sales_repository.dart';
import 'package:picpos_erp/domain/repositories/settings_repository.dart';
import 'package:picpos_erp/domain/repositories/treasury_repository.dart';
import 'package:picpos_erp/services/accounting_service.dart';

void main() {
  late AppDatabase db;
  late SalesTransactionOrchestrator orch;
  late ReturnsRepositoryImpl returns;
  late int userId;
  late int warehouseId;
  late int productId;
  late int shiftId;

  /// ثمنُ الصنف: ١١٤٫٠٧ ⇒ عند خطوة ٥ قروشٍ يُقرَّب **هبوطاً** إلى ١١٤٫٠٥،
  /// والفرقُ ‎+٠٫٠٢‎.
  const priceDown = 114.07;

  /// ١١٤٫٠٨ ⇒ يُقرَّب **صعوداً** إلى ١١٤٫١٠، والفرقُ ‎−٠٫٠٢‎.
  const priceUp = 114.08;

  setUp(() async {
    SyncInterceptor.instance = null;
    db = AppDatabase.forTesting();
    await db.syncDefaultAccounts();

    final svc = AccountingService(
      DriftAccountingRepository(db),
      _StubParties(),
      _RealisticTreasury(db),
      _StubProducts(),
      _StubInventory(),
      _StubSettings(),
      _StubAudit(),
    );
    orch = SalesTransactionOrchestrator(db, svc);
    returns = ReturnsRepositoryImpl(db, svc);

    final roleId = await db.into(db.roles).insert(
          RolesCompanion.insert(name: 'كاشير', isSystemRole: const Value(false)),
        );
    userId = await db.createUser(
      username: 'round_e2e',
      password: 'pw123456',
      displayName: 'كاشير التقريب',
      roleId: roleId,
    );
    warehouseId = (await db.getDefaultWarehouse())!.id;

    productId = await db.insertProduct(
      ProductsCompanion.insert(
        code: 'RND-E2E',
        name: 'صنفُ التقريب',
        salePrice: const Value(priceDown),
        costPrice: const Value(40.0),
        currentStock: const Value(1000),
        trackInventory: const Value(true),
      ),
    );
    await db.adjustStock(
      productId: productId,
      warehouseId: warehouseId,
      quantity: 1000,
      type: 'purchase',
      unitCost: 40,
      notes: 'رصيدٌ افتتاحيّ',
    );

    // ح‑١: بيعةٌ نقديّةٌ بلا ورديّةٍ مفتوحةٍ تُرفَض كلُّها. فالورديّةُ جزءٌ من
    // التجهيزة لا من المقيس، ومجموعةُ الإقفال تستعملها بدل أن تفتح ثانيةً.
    shiftId = await db.openShift(userId, 0);
  });

  // لا `db.close()`: مؤقّتُ drift ينتظر في المنطقة الوهميّة فيعلّق الاختبار.
  tearDown(() async {
    SyncInterceptor.instance = null;
  });

  // ── ما تفعله شاشةُ الكاشير قبل عدِّ النقد ────────────────────────────────
  //
  // `picpos_pos_operations.dart:1712-1721` — نسخةٌ حرفيّةٌ من حسابها. وضعُها
  // هنا يجعل الاختبارَ يقيس **الاتّفاق** بين طرفَي التماسّ: لو غيّر أحدُهما
  // خطوتَه أو مصدرَه انكسر الحقلُ إلى صفرٍ وسقط الاختبار.
  Future<double> cashierCollects(double cartTotal) async {
    final raw = await db.getSettingValue('pos_total_rounding');
    final step = quickSaleRoundingStep(QuickSalePolicyValues(
      raw == null ? const {} : {'pos_total_rounding': raw},
    ));
    if (step <= 0) return cartTotal;
    return double.parse(
        quickSaleRoundedTotal(total: cartTotal, step: step).toStringAsFixed(2));
  }

  Future<void> setRounding(String index) =>
      db.setSetting('pos_total_rounding', index);

  /// بيعةٌ بالمسار الكامل — بلا ضريبةٍ لتبقى الأرقامُ مقروءة.
  ///
  /// و`cashAmount` يُمرَّر للنقديّ تماماً كما تفعل
  /// `CheckoutController.processPayment` (`cash = total`).
  Future<SaleResult> ringUp({
    double price = priceDown,
    double qty = 1,
    String method = 'cash',
    int? customerId,
    double? overridePaid,
    String? deliveryStatus,
  }) async {
    final cartTotal = double.parse((price * qty).toStringAsFixed(2));
    final collected = overridePaid ??
        (method == 'cash' ? await cashierCollects(cartTotal) : cartTotal);
    return orch.completeSalesTransaction(SaleRequest(
      items: [
        CartItemEntity(
          productId: productId,
          productName: 'صنفُ التقريب',
          productCode: 'RND-E2E',
          quantity: qty,
          unitPrice: price,
        ),
      ],
      customerId: customerId,
      warehouseId: warehouseId,
      userId: userId,
      paymentMethod: method,
      paidAmount: method == 'credit' ? 0 : collected,
      cashAmount: method == 'cash' ? collected : null,
      bankAmount: method == 'card' ? collected : null,
      deliveryStatus: deliveryStatus,
      taxEnabled: false,
    ));
  }

  Future<SalesInvoiceData> invoice(int id) =>
      (db.select(db.salesInvoices)..where((s) => s.id.equals(id))).getSingle();

  /// أسطرُ **كلِّ** قيدٍ يشير إلى الفاتورة — أيّاً كان `referenceType`.
  ///
  /// ⚠️ عمداً لا يُقيَّد بنوعٍ واحد: `sale` هو نوعُ `autoPostCashSale`
  /// و`sales_invoice` نوعُ `JournalEntryFactory`، والمنسّقُ يستعمل الثاني.
  /// توكيدٌ على نوعٍ واحدٍ يقرأ قائمةً فارغةً فيمرُّ كلُّ فحصٍ صامتاً.
  Future<List<JournalEntryLine>> linesForInvoice(int invId,
      {List<String> types = const ['sale', 'sales_invoice', 'deferred_sale']}) async {
    final entries = await (db.select(db.journalEntries)
          ..where((e) =>
              e.referenceType.isIn(types) & e.referenceId.equals(invId)))
        .get();
    final out = <JournalEntryLine>[];
    for (final e in entries) {
      out.addAll(await (db.select(db.journalEntryLines)
            ..where((l) => l.entryId.equals(e.id)))
          .get());
    }
    return out;
  }

  Future<double> netOn(List<JournalEntryLine> lines, String code) async {
    final acc = await db.getAccountByCode(code);
    if (acc == null) return 0;
    return lines
        .where((l) => l.accountId == acc.id)
        .fold<double>(0, (s, l) => s + l.debit - l.credit);
  }

  /// صافي شجرة النقدية `111*` — كلُّ خزنةٍ تُمنَح حساباً فرعيّاً عند الإقلاع،
  /// فتوكيدٌ على `1111` وحدَه يقرأ صفراً ويبدو عطباً وهو سلوكٌ صحيح.
  Future<double> cashNet(List<JournalEntryLine> lines) async {
    final accounts = await db.select(db.accounts).get();
    final ids = accounts
        .where((a) => a.code.startsWith('111'))
        .map((a) => a.id)
        .toSet();
    return lines
        .where((l) => ids.contains(l.accountId))
        .fold<double>(0, (s, l) => s + l.debit - l.credit);
  }

  double balanceOf(List<JournalEntryLine> lines) =>
      lines.fold<double>(0, (s, l) => s + l.debit - l.credit);

  Future<ProductEntity> productEntity() async {
    final p = await db.getProductById(productId);
    return ProductEntity(
      id: p!.id,
      name: p.name,
      code: p.code,
      salePrice: p.salePrice,
      costPrice: p.costPrice,
      currentStock: p.currentStock,
      minStock: p.minStock,
      trackInventory: p.trackInventory,
    );
  }

  // ═════════════════════════════════════════════════════════════════════════
  // ١ — الوصول: الإعدادُ في الجدول ⇒ الحقلُ في الصفّ
  // ═════════════════════════════════════════════════════════════════════════
  group('١ · الوصول — الإعدادُ يصل إلى الصفّ', () {
    test('بلا إعدادٍ إطلاقاً ⇒ لا تقريبَ (‏الافتراضُ صفر)', () async {
      final r = await ringUp();
      expect(r.isSuccess, isTrue, reason: r.errorMessage);
      final inv = await invoice(r.invoiceId!);
      expect(inv.roundingAdjustment, 0,
          reason: 'المفتاحُ غائبٌ ⇒ «بلا تقريب» — وأيُّ افتراضٍ غيرِ الصفر '
              'كان سيبدأ تقريبَ فواتيرِ كلِّ تنصيبةٍ بلا أن يطلبه أحد');
      expect(inv.paid, closeTo(priceDown, 0.001));
      expect(inv.status, 'completed');
      expect(await netOn(await linesForInvoice(inv.id), '4319'),
          closeTo(0, 0.0001),
          reason: 'لا سطرَ تقريبٍ على فاتورةٍ لم تُقرَّب');
    });

    test('«لأقرب ٥ قروش» + بيعةٌ نقديّة ⇒ الحقلُ ‎+٠٫٠٢‎ والفاتورةُ مكتملة',
        () async {
      await setRounding('1');
      final r = await ringUp();
      expect(r.isSuccess, isTrue, reason: r.errorMessage);
      final inv = await invoice(r.invoiceId!);

      expect(inv.total, closeTo(114.07, 0.001),
          reason: 'الإجماليُّ المحفوظُ هو الحقيقيُّ لا المقرَّب');
      expect(inv.paid, closeTo(114.05, 0.001),
          reason: 'والمقبوضُ هو ما دخل الدرجَ فعلاً');
      expect(inv.roundingAdjustment, closeTo(0.02, 0.001),
          reason: '⚠️ صفرٌ هنا = الإعدادُ يُحفَظ ولا يصل — ميزةٌ ميّتةٌ صامتة');
      expect(inv.status, 'completed',
          reason: 'فرقُ التقريب ليس ديناً، فلا تبقى الفاتورةُ معلّقة');
      expect(inv.cashPaid, closeTo(114.05, 0.001));
    });

    test('«لأقرب جنيه» ⇒ الخطوةُ تتغيّر فعلاً (‏١١٤٫٠٧ ⇒ ١١٤٫٠٠)', () async {
      await setRounding('3');
      final r = await ringUp();
      expect(r.isSuccess, isTrue, reason: r.errorMessage);
      final inv = await invoice(r.invoiceId!);
      expect(inv.paid, closeTo(114.0, 0.001));
      expect(inv.roundingAdjustment, closeTo(0.07, 0.001),
          reason: 'الخيارُ الثالثُ خطوتُه جنيهٌ لا ٥ قروش');
      expect(inv.status, 'completed');
    });

    test('بطاقةٌ (`card`) لا تُقرَّب — الشبكةُ تسدّد القرشَ بالضبط', () async {
      await setRounding('1');
      final r = await ringUp(method: 'card');
      expect(r.isSuccess, isTrue, reason: r.errorMessage);
      final inv = await invoice(r.invoiceId!);
      expect(inv.roundingAdjustment, 0,
          reason: 'التقريبُ قيدٌ ماديٌّ في الدرج لا في الحساب');
      expect(inv.paid, closeTo(114.07, 0.001));
    });

    test('آجلٌ (`credit`) لا يُقرَّب — الباقي دَينٌ حقيقيّ', () async {
      await setRounding('1');
      final cust = await db.insertParty(
        PartiesCompanion.insert(
            name: 'عميلُ الآجل', isCustomer: const Value(true)),
      );
      final r = await ringUp(method: 'credit', customerId: cust);
      expect(r.isSuccess, isTrue, reason: r.errorMessage);
      final inv = await invoice(r.invoiceId!);
      expect(inv.roundingAdjustment, 0);
      expect(inv.status, 'pending');
      final p = await (db.select(db.parties)..where((x) => x.id.equals(cust)))
          .getSingle();
      expect(p.balance, closeTo(114.07, 0.001),
          reason: 'الدَّينُ بالإجماليِّ الحقيقيِّ كاملاً');
    });

    test('مسدَّدٌ جزئيّاً ⇒ لا تقريب (‏الباقي دَينٌ لا فرقَ تقريب)', () async {
      await setRounding('1');
      final cust = await db.insertParty(
        PartiesCompanion.insert(
            name: 'عميلٌ جزئيّ', isCustomer: const Value(true)),
      );
      final r = await ringUp(customerId: cust, overridePaid: 50.0);
      expect(r.isSuccess, isTrue, reason: r.errorMessage);
      final inv = await invoice(r.invoiceId!);
      expect(inv.roundingAdjustment, 0,
          reason: 'خلطُ فرقِ التقريب بالدَّين يضيّع الاثنين');
      expect(inv.status, 'pending');
    });

    // ⛔ يفشل اليوم — **BLOCKER**. اقرأ سببَ التخطّي.
    test(
      'تقريبٌ صعوداً (‏١١٤٫٠٨ ⇒ ١١٤٫١٠) ⇒ البيعةُ تنجح والقيدُ يتوازن',
      () async {
        await setRounding('1');
        final r = await ringUp(price: priceUp);
        expect(r.isSuccess, isTrue, reason: r.errorMessage);
        final inv = await invoice(r.invoiceId!);
        expect(inv.paid, closeTo(114.10, 0.001),
            reason: 'التقريبُ لأقرب خطوةٍ — لا هبوطاً دائماً');
        expect(inv.roundingAdjustment, closeTo(-0.02, 0.001));
        final lines = await linesForInvoice(inv.id);
        expect(balanceOf(lines), closeTo(0, 0.0001));
        expect(await netOn(lines, '4319'), closeTo(-0.02, 0.0001),
            reason: 'قُبض أكثرُ ⇒ دائن');
      },
      // FIXED 2026-08-30 — كان: skip: 'عطبٌ مؤكَّد (BLOCKER-R1) — كلُّ بيعةٍ يُقرَّب إجماليُّها **صعوداً** '
      // 'تُرفَض كاملةً. المنسّقُ يمرّر '
      // '`remaining: total - paid` إلى '
      // '`JournalEntryFactory.generateSalesAccountingEntry` '
      // '(sales_transaction_orchestrator.dart:435)، والمصنعُ يبني '
      // '`netSalesCredit = (paid + remaining)` = الإجماليَّ الحقيقيّ بينما '
      // 'يُثبت المدينَ بالمقبوض المقرَّب — فيزيد المدينُ عن الدائن بمقدار '
      // 'الفرق ويُرمى القيدُ بـ`UnbalancedJournalException`، ومعه المعاملةُ '
      // 'كلُّها. مقيسٌ: «مدين 154.1 دائن 154.08». '
      // 'والاقتراح: تمرير `remaining: total - paid - roundingAdjustment` '
      // 'وإضافةُ سطرِ 4319 في المصنع، و'
      // '`netSalesCredit = (paid + remaining + roundingAdjustment) - vat - delivery`.',
    );
  });

  // ═════════════════════════════════════════════════════════════════════════
  // ٢ — الأستاذُ والدرج
  // ═════════════════════════════════════════════════════════════════════════
  group('٢ · الأستاذُ يرى ما يراه الدرج', () {
    test('القيدُ يتوازن، والإيرادُ بالإجماليِّ الحقيقيّ، والنقديةُ بالمقبوض',
        () async {
      await setRounding('1');
      final r = await ringUp();
      expect(r.isSuccess, isTrue, reason: r.errorMessage);
      final lines = await linesForInvoice(r.invoiceId!);

      expect(lines, isNotEmpty, reason: 'لا قيدَ أصلاً = الترحيلُ سقط');
      expect(balanceOf(lines), closeTo(0, 0.0001));
      expect(await netOn(lines, '4121'), closeTo(-114.07, 0.0001),
          reason: 'الإيرادُ لا يبتلع فرقَ التقريب — وهذا ما يميّز النموذجَ '
              'الصحيحَ عن تقريبِ `total` نفسِه');
      expect(await cashNet(lines), closeTo(114.05, 0.0001),
          reason: 'والنقديةُ بما دخل الدرجَ فعلاً');
    });

    test('حركةُ الخزنة بالمقبوضِ المقرَّب — الدفترُ يساوي الدرج', () async {
      await setRounding('1');
      final r = await ringUp();
      final tx = await (db.select(db.safeTransactions)
            ..where((t) =>
                t.referenceType.equals('sales_invoice') &
                t.referenceId.equals(r.invoiceId!)))
          .get();
      expect(tx, hasLength(1));
      expect(tx.first.amount, closeTo(114.05, 0.001),
          reason: '⚠️ ١١٤٫٠٧ هنا = عجزُ ورديّةٍ بقرشين في كلِّ بيعة');
    });

    // ⛔ يفشل اليوم — اقرأ سببَ التخطّي.
    test(
      'الفرقُ على «٤٣١٩ فروق تقريب» لا على «١١٢١ ذمم عملاء»',
      () async {
        await setRounding('1');
        final r = await ringUp();
        final lines = await linesForInvoice(r.invoiceId!);
        expect(await netOn(lines, '4319'), closeTo(0.02, 0.0001),
            reason: 'سطرٌ صريحٌ يقرؤه المدقّق');
        expect(await netOn(lines, '1121'), closeTo(0, 0.0001),
            reason: 'ولا ذمّةَ مدينةً وهميّةً على حساب المراقبة');
      },
      // FIXED 2026-08-30 — كان: skip: 'عطبٌ مؤكَّد (HIGH-R2) — بيعةُ الكاشير المستقلّة تُرحَّل عبر '
      // '`JournalEntryFactory` لا عبر `autoPostCashSale`، والمصنعُ لا يعرف '
      // '`4319` إطلاقاً. مقيسٌ على المسار الحقيقيّ: '
      // '`1121 ذمم عملاء محليون Dr 0.02` وصفرٌ على `4319`. '
      // 'والسببُ `deferAutoPost: true` في '
      // '`sales_transaction_orchestrator.dart:264` — فسطرُ ٤٣١٩ الذي أُضيف '
      // 'في `accounting_autopost_dao.dart:481` لا يُنفَّذ إلّا على الخادم '
      // '(`api_sales_handler`) وفي `quick_sale_rounding_autopost_test`. '
      // 'وأثرُه: فتاتُ التقريب يتراكم على حسابِ **المراقبة** بلا حسابٍ '
      // 'فرعيٍّ يقابله، فتنكسر مطابقةُ المراقبة مع مجموع الفرعيّات — '
      // 'ولا يزيله المرتجعُ الكاملُ (‏اقرأ مجموعةَ ٤).',
    );
  });

  // ═════════════════════════════════════════════════════════════════════════
  // ٣ — مصالحةُ الورديّة: الاختبارُ الحاسم
  // ═════════════════════════════════════════════════════════════════════════
  group('٣ · إقفالُ الورديّة — الدرجُ الماديُّ يساوي الدفتر', () {
    test('عشرُ بيعاتٍ مقرَّبةٍ ⇒ الفرقُ صفرٌ بالضبط', () async {
      await setRounding('1');

      var drawer = 0.0;
      for (var i = 0; i < 10; i++) {
        final r = await ringUp();
        expect(r.isSuccess, isTrue, reason: r.errorMessage);
        drawer += (await invoice(r.invoiceId!)).paid;
      }
      expect(drawer, closeTo(1140.50, 0.001),
          reason: 'الكاشيرُ قبض ١١٤٫٠٥ عشرَ مرّات');

      // الكاشيرُ يعدّ ما في الدرج فعلاً — وهو ما قبضه، لا ما تقوله الفاتورة.
      await db.closeShiftWithAudit(shiftId, drawer);
      final s = await (db.select(db.shifts)..where((x) => x.id.equals(shiftId)))
          .getSingle();

      expect(s.expectedCash, closeTo(1140.50, 0.001));
      expect(s.variance, closeTo(0, 0.001),
          reason: '⚠️ ‎−٠٫٢٠‎ هنا = التصميمُ القديم: التقريبُ بعد عدِّ النقد '
              'يخلق فرقَ ورديّةٍ في كلِّ بيعة — وهو عينُ ما وُجد الإعدادُ '
              'ليمنعه');
    });

    test('وبلا تقريبٍ يبقى الفرقُ صفراً كذلك (‏مرساةٌ للمقارنة)', () async {
      var drawer = 0.0;
      for (var i = 0; i < 3; i++) {
        final r = await ringUp();
        drawer += (await invoice(r.invoiceId!)).paid;
      }
      await db.closeShiftWithAudit(shiftId, drawer);
      final s = await (db.select(db.shifts)..where((x) => x.id.equals(shiftId)))
          .getSingle();
      expect(s.variance, closeTo(0, 0.001));
      expect(s.expectedCash, closeTo(342.21, 0.001));
    });

    test('لا صفَّ تسويةِ فرقٍ يُكتب على الخزنة (‏الفرقُ صفرٌ فلا تسوية)',
        () async {
      await setRounding('1');
      final r = await ringUp();
      await db.closeShiftWithAudit(shiftId, (await invoice(r.invoiceId!)).paid);
      final varianceRows = await (db.select(db.safeTransactions)
            ..where((t) => t.category.equals('shift_variance')))
          .get();
      expect(varianceRows, isEmpty,
          reason: 'تسويةُ فرقٍ = عجزٌ صُنع من لا شيء');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  // ٤ — المرتجعُ الكامل
  // ═════════════════════════════════════════════════════════════════════════
  group('٤ · مرتجعٌ كاملٌ لفاتورةٍ مقرَّبة', () {
    Future<SalesInvoiceData> sellAndReturnAll({bool full = true}) async {
      final r = await ringUp();
      final inv = await invoice(r.invoiceId!);
      final items = await db.getSalesInvoiceItems(inv.id);
      final ok = await returns.processSalesReturn(
        invoice: inv,
        returnQuantities: {items.first.id: items.first.quantity},
        productCache: {productId: await productEntity()},
        userId: userId,
        userName: 'كاشير التقريب',
        isFullReturn: full,
      );
      expect(ok, isTrue, reason: 'المرتجعُ لم يُنفَّذ أصلاً');
      return inv;
    }

    test('يخرج من الدرج ما دخله بالضبط — لا قرشان لم يدخلا قطّ', () async {
      await setRounding('1');
      final inv = await sellAndReturnAll();
      expect(inv.roundingAdjustment, closeTo(0.02, 0.001));

      final refund = await (db.select(db.safeTransactions)
            ..where((t) => t.category.equals('sales_return')))
          .get();
      expect(refund, hasLength(1));
      expect(refund.first.amount, closeTo(114.05, 0.001),
          reason: '⚠️ ١١٤٫٠٧ = قرشان يخرجان من الدرج لم يدخلاه قطّ');
    });

    test('البيعةُ ثمّ مرتجعُها ⇒ إقفالُ الورديّة عند صفرٍ بلا فرق', () async {
      await setRounding('1');
      await sellAndReturnAll();
      await db.closeShiftWithAudit(shiftId, 0);
      final s = await (db.select(db.shifts)..where((x) => x.id.equals(shiftId)))
          .getSingle();
      expect(s.expectedCash, closeTo(0, 0.001));
      expect(s.variance, closeTo(0, 0.001));
    });

    test('قيدُ المرتجع يعكس ٤٣١٩ ويتوازن', () async {
      await setRounding('1');
      await sellAndReturnAll();

      final retEntries = await (db.select(db.journalEntries)
            ..where((e) => e.referenceType.equals('sales_return')))
          .get();
      expect(retEntries, hasLength(1), reason: 'قيدُ المرتجعِ لم يُرحَّل');
      final lines = await (db.select(db.journalEntryLines)
            ..where((l) => l.entryId.equals(retEntries.first.id)))
          .get();
      expect(balanceOf(lines), closeTo(0, 0.0001));
      expect(await netOn(lines, '4319'), closeTo(-0.02, 0.0001),
          reason: 'مسارُ المرتجع يمرّ بـ`autoPostSalesReturn` فيعرف ٤٣١٩ — '
              'بخلاف مسارِ البيع');
    });

    // ⛔ يفشل اليوم — اقرأ سببَ التخطّي.
    test(
      'بعد البيع ومرتجعِه الكامل لا يبقى أثرٌ على أيِّ حسابٍ (‏الأستاذُ نظيف)',
      () async {
        await setRounding('1');
        await sellAndReturnAll();
        final all = await db.select(db.journalEntryLines).get();
        expect(await netOn(all, '1121'), closeTo(0, 0.0001),
            reason: 'ذمّةُ العميل صفرٌ بعد بيعٍ ومرتجعِه');
        expect(await netOn(all, '4319'), closeTo(0, 0.0001),
            reason: 'وفرقُ التقريبِ أُثبت ثمّ عُكس');
      },
      // FIXED 2026-08-30 — كان: skip: 'عطبٌ مؤكَّد (HIGH-R2 · الأثرُ التراكميّ) — الجانبان غيرُ '
      // 'متماثلَين: البيعُ يُثبت `1121 Dr 0.02` (‏المصنع)، والمرتجعُ يعكس '
      // '`4319 Cr 0.02` (‏الـDAO). فبعد بيعٍ ومرتجعِه الكامل يبقى في '
      // 'الأستاذ **مدينٌ ٠٫٠٢ على ذمم العملاء ودائنٌ ٠٫٠٢ على فروق '
      // 'التقريب** إلى الأبد، ولا شيءَ يزيلهما. ‏٤٠٠ فاتورة/يوم تُراكم '
      // 'ذمّةً وهميّةً على حساب المراقبة لا حسابَ فرعيّاً يقابلها.',
    );
  });

  // ═════════════════════════════════════════════════════════════════════════
  // ٥ — المرتجعُ الجزئيّ
  // ═════════════════════════════════════════════════════════════════════════
  group('٥ · مرتجعٌ جزئيٌّ لفاتورةٍ مقرَّبة', () {
    test('لا يُعكَس التقريب، ولا ينكسر شيء', () async {
      await setRounding('1');
      // بيعةُ صنفَين: ٢٢٨٫١٤ ⇒ مقرَّبةً ٢٢٨٫١٥ (‏صعوداً).
      // ولمّا كان التقريبُ صعوداً يُجهض البيعةَ اليوم (BLOCKER-R1) نستعمل
      // كمّيّةً تُبقي الإجماليَّ يقرَّب هبوطاً: ٣×١١٤٫٠٧ = ٣٤٢٫٢١ ⇒ ٣٤٢٫٢٠.
      final r = await ringUp(qty: 3);
      expect(r.isSuccess, isTrue, reason: r.errorMessage);
      final inv = await invoice(r.invoiceId!);
      expect(inv.roundingAdjustment, closeTo(0.01, 0.001));
      final items = await db.getSalesInvoiceItems(inv.id);

      final ok = await returns.processSalesReturn(
        invoice: inv,
        returnQuantities: {items.first.id: 1.0},
        productCache: {productId: await productEntity()},
        userId: userId,
        userName: 'كاشير التقريب',
        isFullReturn: false,
      );
      expect(ok, isTrue, reason: 'المرتجعُ الجزئيُّ يجب ألّا يُجهَض');

      final refund = await (db.select(db.safeTransactions)
            ..where((t) => t.category.equals('sales_return')))
          .get();
      expect(refund, hasLength(1));
      expect(refund.first.amount, closeTo(114.07, 0.001),
          reason: 'نصفُ الأصناف لا يحمل نصفَ قرشِ التقريب — يُردّ سعرُ السطر');

      final retEntries = await (db.select(db.journalEntries)
            ..where((e) => e.referenceType.equals('sales_return')))
          .get();
      final lines = await (db.select(db.journalEntryLines)
            ..where((l) => l.entryId.equals(retEntries.first.id)))
          .get();
      expect(balanceOf(lines), closeTo(0, 0.0001));
      expect(await netOn(lines, '4319'), closeTo(0, 0.0001),
          reason: 'التقريبُ وقع على تسويةِ الفاتورة كلِّها لا على سطرٍ بعينه');

      // والفاتورةُ الأصليّةُ تبقى بتقريبها كما هو.
      expect((await invoice(inv.id)).roundingAdjustment,
          closeTo(inv.roundingAdjustment, 0.0001));
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  // ٦ — الإبطال
  // ═════════════════════════════════════════════════════════════════════════
  group('٦ · إبطالُ فاتورةٍ مقرَّبة', () {
    test('رصيدُ العميلِ يعود صفراً — لا دائناً بفتاتِ التقريب', () async {
      await setRounding('1');
      final cust = await db.insertParty(
        PartiesCompanion.insert(
            name: 'عميلُ الإبطال', isCustomer: const Value(true)),
      );
      final before =
          (await (db.select(db.parties)..where((p) => p.id.equals(cust)))
                  .getSingle())
              .balance;

      final r = await ringUp(customerId: cust);
      final inv = await invoice(r.invoiceId!);
      expect(inv.roundingAdjustment, closeTo(0.02, 0.001));

      await db.voidSalesInvoice(inv.id, deletedBy: userId, reason: 'اختبار');

      final after =
          (await (db.select(db.parties)..where((p) => p.id.equals(cust)))
                  .getSingle())
              .balance;
      expect(after, closeTo(before, 0.0001),
          reason: '⚠️ ‎−٠٫٠٢‎ = الإبطالُ يمنح العميلَ رصيداً لم يوجد قطّ');
      expect((await invoice(inv.id)).status, 'voided');
    });

    test('القيدُ العكسيُّ يُرحَّل ويُصفّر أثرَ البيعة في الأستاذ', () async {
      await setRounding('1');
      final r = await ringUp();
      final inv = await invoice(r.invoiceId!);
      await db.voidSalesInvoice(inv.id, deletedBy: userId, reason: 'اختبار');

      final voidEntry = await (db.select(db.journalEntries)
            ..where((e) =>
                e.referenceType.equals('sales_invoice_void') &
                e.referenceId.equals(inv.id)))
          .getSingleOrNull();
      expect(voidEntry, isNotNull,
          reason: 'الإبطالُ بلا قيدٍ عكسيٍّ يفصل الأستاذ عن الدفاتر الفرعيّة');

      // الأثرُ الصافي على كلِّ الحسابات صفرٌ — أدقُّ من فحصِ سطرٍ بعينه، وهو
      // ما يجعل هذا الاختبارَ صحيحاً قبل إصلاح HIGH-R2 وبعده.
      final all = await db.select(db.journalEntryLines).get();
      for (final code in ['4121', '1121', '4319', '1136', '5211']) {
        expect(await netOn(all, code), closeTo(0, 0.0001),
            reason: 'الحسابُ $code لم يعد لما كان عليه قبل البيعة');
      }
      expect(await cashNet(all), closeTo(0, 0.0001));
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  // ٧ — التوصيلُ المؤجَّل
  // ═════════════════════════════════════════════════════════════════════════
  group('٧ · طلبُ توصيلٍ نقديٌّ غيرُ مسلَّم', () {
    test('لا يُقرَّب، والقيدُ يتوازن، والبيعةُ لا تُجهَض', () async {
      await setRounding('1');
      final r = await ringUp(deliveryStatus: 'pending');
      expect(r.isSuccess, isTrue, reason: r.errorMessage);
      final inv = await invoice(r.invoiceId!);
      expect(inv.roundingAdjustment, 0,
          reason: 'مسارُ الإيراد المؤجَّل لا يعرف سطرَ ٤٣١٩ — فتقريبُه '
              'كان يُنتج قيداً يُرمى أو ذمّةً صامتة');

      final lines = await linesForInvoice(inv.id);
      expect(lines, isNotEmpty, reason: 'قيدُ الطلبِ لم يُرحَّل');
      expect(balanceOf(lines), closeTo(0, 0.0001));
    });

    test('وعلى مسار الـDAO (‏الخادم) القيدُ المؤجَّلُ يتوازن مع فرقِ تقريب',
        () async {
      // منادٍ أدنى (‏`api_sales_handler` · مزامنةٌ · استيراد) يمرّر الحقلَ
      // بلا سياسة. الغرض: ألّا يتحوّل ذلك إلى قيدٍ يُرمى ويصير dead-letter.
      final id = await db.createSalesInvoice(
        invoiceNumber: 'DEF-ROUND-1',
        warehouseId: warehouseId,
        userId: userId,
        subtotal: 114.07,
        discount: 0,
        tax: 0,
        total: 114.07,
        paid: 114.05,
        roundingAdjustment: 0.02,
        paymentMethod: 'cash',
        cashAmount: 114.05,
        deliveryStatus: 'pending',
        items: [
          SalesInvoiceItemsCompanion.insert(
            invoiceId: 0,
            productId: productId,
            quantity: 1,
            unitPrice: 114.07,
            total: 114.07,
            costPrice: const Value(40),
          ),
        ],
      );
      final lines =
          await linesForInvoice(id, types: const ['deferred_sale']);
      expect(lines, isNotEmpty,
          reason: 'قيدٌ غائبٌ = رُمي بـ«المدين لا يساوي الدائن»');
      expect(balanceOf(lines), closeTo(0, 0.0001));
      expect((await invoice(id)).status, 'completed',
          reason: 'فرقُ التقريب ليس ديناً حتّى على طلبٍ مؤجَّل');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  // ٨ — وضعُ العميل / المرآة
  // ═════════════════════════════════════════════════════════════════════════
  group('٨ · وضعُ العميل — الشقُّ المحلّيُّ يُغلق الفاتورة', () {
    test('الفاتورةُ `completed` لا `pending`، والحقلُ محفوظٌ في المخبأ',
        () async {
      await setRounding('1');
      SyncInterceptor.instance = _ClientMode();

      final r = await ringUp();
      expect(r.isSuccess, isTrue, reason: r.errorMessage);
      final inv = await invoice(r.invoiceId!);

      expect(inv.roundingAdjustment, closeTo(0.02, 0.001),
          reason: 'المخبأُ المحلّيُّ يحمل الفرقَ كي يوافقَ صدى الخادم');
      expect(inv.status, 'completed',
          reason: '⚠️ `pending` = الكاشيرُ يرى فاتورةً غيرَ مسدَّدةٍ لبيعةٍ '
              'قُبض ثمنُها كاملاً، ولا تُشفى إلّا حين يصل صدى الخادم');
      expect(inv.paid, closeTo(114.05, 0.001));

      // وضعُ العميل لا يُرحّل قيداً محلّيّاً — الخادمُ هو المرجع.
      final entries = await db.select(db.journalEntries).get();
      expect(entries, isEmpty,
          reason: 'قيدٌ محلّيٌّ في وضع العميل = إيرادٌ مزدوجٌ في أستاذ الخادم');
    });
  });
}

// ─────────────────────────────────────────────────────────────────────────────

class _ClientMode implements SyncInterceptor {
  @override
  bool get isClientModeImpl => true;

  @override
  bool get isMirrorModeImpl => false;

  @override
  dynamic noSuchMethod(Invocation inv) => null;
}

class _StubParties implements IPartiesRepository {
  @override
  dynamic noSuchMethod(Invocation inv) {
    if (inv.memberName == #getPartyById) return Future<Null>.value(null);
    throw UnsupportedError('parties repo not used here');
  }
}

/// نسخةٌ سلوكيّةٌ من `TreasuryRepositoryImpl.getSafeAccountsForReference`.
///
/// ⚠️ ولا تُرجع `[]`: بذلك يسقط شقُّ النقدية على الحساب العامّ `1111` بدل
/// الحساب الفرعيِّ للخزنة، فيقيس الاختبارُ شكلَ قيدٍ لا يقع في الإنتاج.
class _RealisticTreasury implements ITreasuryRepository {
  final AppDatabase db;
  _RealisticTreasury(this.db);

  @override
  Future<List<Map<String, dynamic>>> getSafeAccountsForReference(
      String referenceType, int referenceId) async {
    final rows = await (db.select(db.safeTransactions)
          ..where((t) =>
              t.referenceType.equals(referenceType) &
              t.referenceId.equals(referenceId) &
              t.transactionType.equals('receipt')))
        .get();
    final out = <Map<String, dynamic>>[];
    for (final r in rows) {
      final safe =
          await (db.select(db.safes)..where((s) => s.id.equals(r.safeId)))
              .getSingle();
      var accountId = safe.linkedAccountId;
      accountId ??= (await db.getAccountByCode(
              safe.safeType == 'bank' ? '1112' : '1111'))
          ?.id;
      if (accountId != null) {
        out.add({
          'accountId': accountId,
          'amount': r.amount,
          'safeName': safe.name,
        });
      }
    }
    return out;
  }

  @override
  dynamic noSuchMethod(Invocation inv) =>
      throw UnsupportedError('treasury repo: ${inv.memberName}');
}

class _StubProducts implements IProductRepository {
  @override
  dynamic noSuchMethod(Invocation inv) =>
      throw UnsupportedError('product repo not used here');
}

class _StubInventory implements InventoryRepository {
  @override
  dynamic noSuchMethod(Invocation inv) =>
      throw UnsupportedError('inventory repo not used here');
}

class _StubSettings implements ISettingsRepository {
  @override
  dynamic noSuchMethod(Invocation inv) =>
      throw UnsupportedError('settings repo not used here');
}

class _StubAudit implements IAuditRepository {
  @override
  dynamic noSuchMethod(Invocation inv) =>
      throw UnsupportedError('audit repo not used here');
}
