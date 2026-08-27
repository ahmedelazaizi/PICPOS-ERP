// المرحلة ٤ — المصالحةُ الكاملة عند تاريخِ قطعٍ **واحد**، على قاعدةٍ حقيقيّة.
//
// ═══ لماذا هذا الملفّ موجود ═══
//
// الوحداتُ تُختبَر كلٌّ على حدة، فيمرّ كلُّ اختبارٍ أخضرَ بينما الدفاترُ
// متخالفة: مخزنٌ يقول قيمةً والأستاذُ يقول أخرى، وخزنةٌ فيها نقدٌ لا يعرفه
// حسابُ النقديّة. المصالحةُ هي الفحصُ الوحيدُ الذي يمسك ذلك.
//
// و**دفترٌ واحدٌ لا خمسةُ دفاتر**: الخمسُ مصالحاتٍ تقرأ نفسَ القاعدةِ التي
// وقع فيها نشاطُ الوحدات الخمسِ كلِّه. هذا هو الفرقُ بين مصالحةٍ واختبارِ
// وحدةٍ مكرَّر: اقتناءُ أصلٍ يمسّ الذمم، وبيعٌ يمسّ المخزونَ والخزينةَ
// والضريبةَ معاً، والتلوّثُ المتبادلُ هو بالضبط ما يجب أن تصمد له.
//
// ولا `_Fake` فيه: التفاوتُ يولد من تفاعلِ الـDAO الحقيقيّةِ مع المخطَّط
// الحقيقيّ، ومزيَّفٌ يُعيد ما لُقِّن.
//
// ═══ 🔴 حدُّ هذه المصالحات — اقرأه قبل أن تثق بخضرتها ═══
//
// طرفا كلِّ مصالحةٍ **غيرُ متماثلَين في الزمن**:
//
//   • طرفُ الأستاذ **يُقصّ بالتاريخ** — `entry_date <= cutoff`.
//   • وطرفُ البطاقة **حالةٌ راهنةٌ لا تاريخيّة**: `products.current_stock`
//     و`safes.balance` و`parties.balance` و`fixed_assets.
//     accumulated_depreciation` تحمل قيمةَ **اللحظة**. لا عمودَ فيها
//     يُقصّ به.
//
// فالمساواةُ أدناه صحيحةٌ لأنّ نشاطَ التجهيزة **كلَّه قبلَ تاريخ القطع**،
// أي أنّ «الراهن» و«عند القطع» شيءٌ واحد. ومجموعةُ «حدودُ تاريخ القطع» في
// آخر الملفّ تثبّت الشرطَ صراحةً بدل أن تتركه افتراضاً.
//
// ⚠️ **ومصالحةٌ تاريخيّةٌ حقيقيّةٌ تحتاج إعادةَ تشغيلِ حركةٍ مؤرَّخة**
//    (`stock_movements` · `safe_transactions`) لا قراءةَ بطاقة. ما هنا
//    يمسك التفاوتَ الهيكليَّ لا التاريخيّ.
//
// ⚠️ **وتاريخُ القطع في المستقبل عمداً** — نهايةُ السنة الماليّة. السببُ
//    مقيسٌ لا مُفترَض: `createReceiptVoucher` و`createPaymentVoucher`
//    **لا تقبلان تاريخاً** وتختمان بـ`DateTime.now()`. فسندٌ مؤرَّخٌ في
//    الماضي غيرُ ممكنٍ عبر المسار الحقيقيّ، وقطعٌ ماضٍ كان سيُخرج كلَّ
//    حركةِ خزينةٍ من النطاق فتصير المصالحةُ صفراً=صفراً.
//
// ═══ وكلُّ مصالحةٍ بمرساةٍ موجبة ═══
//
// صفرٌ = صفرٌ مساواةٌ صحيحةٌ وفارغةُ المعنى. فقبلَ كلِّ حكمٍ تثبت المرساةُ
// أنّ الطرفين تحرّكا فعلاً — بلا ذلك تمرّ تجهيزةٌ لا تُرحّل أصلاً خضراء.

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';

/// تاريخُ القطع — نهايةُ السنة الماليّة، وهو **بعد** لحظةِ التشغيل.
final kCutoff = DateTime(2026, 12, 31, 23, 59, 59);

/// تاريخٌ يقع يقيناً بعد القطع — لفحصِ حدودِه.
final kAfterCutoff = DateTime(2027, 2, 15);

const _tolerance = 0.005;

void main() {
  late AppDatabase db;
  late int warehouseId;
  late int safeId;
  late int cashAccountId;
  late int payablesAccountId;
  late int customerId;
  late int supplierId;
  late int productId;
  late int accumDeprAccountId;

  // ── أدواتُ القياس ────────────────────────────────────────────────────────

  /// رصيدُ حسابٍ في الأستاذ **عند تاريخ القطع** = Σ(مدين − دائن) على قيودٍ
  /// مُرحَّلةٍ غيرِ محذوفة.
  ///
  /// الشرطُ `is_posted AND NOT is_deleted` هو نفسُه المستعمَلُ في
  /// `getCostCenterBalance` — وأيُّ انحرافٍ عنه يجعل هذا الملفَّ يصالح
  /// شيئاً لا يراه باقي النظام.
  Future<double> glAsOf(int accountId, DateTime asOf) async {
    final r = await db.customSelect(
      'SELECT COALESCE(SUM(l.debit), 0) AS dr, COALESCE(SUM(l.credit), 0) AS cr '
      'FROM journal_entry_lines l '
      'JOIN journal_entries e ON l.entry_id = e.id '
      'WHERE l.account_id = ? AND e.is_posted = 1 AND e.is_deleted = 0 '
      '  AND e.entry_date <= ?',
      variables: [Variable.withInt(accountId), Variable.withDateTime(asOf)],
    ).getSingle();
    return ((r.data['dr'] as num).toDouble()) -
        ((r.data['cr'] as num).toDouble());
  }

  Future<double> glByCode(String code, DateTime asOf) async {
    final acc = await db.getAccountByCode(code);
    expect(acc, isNotNull,
        reason: 'الحسابُ $code غيرُ مزروع — المصالحةُ تقيس فراغاً');
    return glAsOf(acc!.id, asOf);
  }

  Future<Party> partyOf(int id) async =>
      (db.select(db.parties)..where((p) => p.id.equals(id))).getSingle();

  // ── الدفترُ الواحد ───────────────────────────────────────────────────────

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.syncDefaultAccounts();

    await db.into(db.fiscalYears).insert(
          FiscalYearsCompanion.insert(
            name: '2026',
            startDate: DateTime(2026, 1, 1),
            endDate: DateTime(2026, 12, 31),
          ),
        );

    warehouseId = await db
        .into(db.warehouses)
        .insert(WarehousesCompanion.insert(name: 'المخزنُ الرئيسيّ'));

    cashAccountId = (await db.getAccountByCode('1111'))!.id;
    payablesAccountId = (await db.getAccountByCode('2111'))!.id;
    accumDeprAccountId = (await db.getAccountByCode('1219'))!.id;

    safeId = await db.into(db.safes).insert(
          SafesCompanion.insert(
            name: 'الخزنةُ الرئيسيّة',
            linkedAccountId: Value(cashAccountId),
            isDefault: const Value(true),
          ),
        );

    // ⚠️ `insertParty` لا `into(parties).insert`: الأولى وحدَها تُنشئ الحسابَ
    //    الفرعيَّ وتربطه. طرفٌ بلا حسابٍ يجعل مصالحةَ الذمم صفراً=صفراً.
    customerId = await db.insertParty(
      PartiesCompanion.insert(name: 'عميلٌ', isCustomer: const Value(true)),
    );
    supplierId = await db.insertParty(
      PartiesCompanion.insert(
        name: 'موردٌ',
        isCustomer: const Value(false),
        isSupplier: const Value(true),
      ),
    );

    productId = await db.into(db.products).insert(
          ProductsCompanion.insert(
            code: 'P-1',
            name: 'صنفٌ',
            salePrice: const Value(100),
            costPrice: const Value(60),
            currentStock: const Value(0),
          ),
        );

    // ── ١. شراءٌ آجل: يُدخل بضاعةً ويُنشئ ذمّةَ مورّد ──────────────────────
    await db.createPurchaseInvoice(
      supplierId: supplierId,
      warehouseId: warehouseId,
      userId: 1,
      paid: 0,
      paymentMethod: 'credit',
      invoiceDate: DateTime(2026, 3, 10),
      items: [
        PurchaseInvoiceItemsCompanion.insert(
          invoiceId: 0,
          productId: productId,
          quantity: 200,
          unitCost: 60,
          total: 12000,
        ),
      ],
    );

    // ── ٢. سدادٌ جزئيٌّ للمورد من الخزنة ──────────────────────────────────
    await db.createPaymentVoucher(
      amount: 5000,
      category: 'supplier_payment',
      description: 'سدادٌ جزئيّ',
      partyId: supplierId,
      safeId: safeId,
      userId: 1,
    );

    // ── ٣. إيداعٌ نقديٌّ في الخزنة ────────────────────────────────────────
    await db.createReceiptVoucher(
      amount: 20000,
      category: 'other',
      description: 'إيداعٌ افتتاحيّ',
      safeId: safeId,
      userId: 1,
    );

    // ── ٤. أصلٌ ثابتٌ **على الذمّة** وثلاثةُ أشهرِ إهلاك ──────────────────
    // `contraAccountId` = الموردون عمداً: الافتراضيُّ يُرحّل دائنَ نقديّةٍ
    // بلا حركةِ خزنةٍ تقابله، فتنكسر مصالحةُ الخزينة لسببٍ لا علاقةَ له
    // بما نقيسه هنا.
    final assetAcc = (await db.getAccountByCode('1213'))!;
    final categoryId = await db.createAssetCategory(
      name: 'آلاتٌ',
      accountId: assetAcc.id,
      depreciationAccountId: accumDeprAccountId,
    );
    await db.createFixedAsset(
      code: 'FA-1',
      name: 'آلةٌ',
      categoryId: categoryId,
      purchasePrice: 12000,
      purchaseDate: DateTime(2026, 1, 1),
      usefulLifeYears: 5,
      contraAccountId: payablesAccountId,
    );
    for (final m in [3, 4, 5]) {
      await db.runMonthlyDepreciation(DateTime(2026, m, 28));
    }

    // ── ٥. بيعٌ **جزئيُّ السداد** بضريبة ──────────────────────────────────
    // جزئيٌّ عمداً لا نقديٌّ كامل: بيعٌ مسدَّدٌ بالكامل يترك رصيدَ العميل
    // صفراً، فتصير مصالحةُ ذمّته «صفرٌ = صفر» — مساواةٌ صحيحةٌ لا تقيس
    // شيئاً وتمرّ خضراءَ ولو كان الترحيلُ على العميل معطَّلاً تماماً.
    final saleId = await db.createSalesInvoice(
      customerId: customerId,
      warehouseId: warehouseId,
      userId: 1,
      subtotal: 1000,
      discount: 0,
      tax: 140,
      total: 1140,
      paid: 640,
      paymentMethod: 'cash',
      cashSafeId: safeId,
      invoiceDate: DateTime(2026, 6, 1),
      items: [
        SalesInvoiceItemsCompanion.insert(
          invoiceId: 0,
          productId: productId,
          quantity: 10,
          unitPrice: 100,
          total: 1000,
        ),
      ],
    );

    await db.into(db.eInvoiceSubmissions).insert(
          EInvoiceSubmissionsCompanion.insert(
            saleId: saleId,
            platform: 'eta',
            status: const Value('accepted'),
            submittedAt: Value(DateTime(2026, 6, 2)),
          ),
        );
  });

  tearDown(() => db.close());

  // ═══════════════════════════════════════════════════════════════════════
  // ٠ — مرساةُ الدفتر: بلا هذه لا معنى لأيّ مساواةٍ بعدها
  // ═══════════════════════════════════════════════════════════════════════

  group('٠ — مرساةُ الدفتر', () {
    test('⚓ التجهيزةُ رحّلت قيوداً فعلاً', () async {
      final n = await db.select(db.journalEntries).get();
      expect(n.length, greaterThan(3),
          reason: 'دفترٌ شبهُ فارغٍ ⇒ كلُّ مصالحةٍ أدناه صفرٌ=صفر، وتمرّ '
              'خضراءَ ولو كان النظامُ لا يُرحّل شيئاً.');
    });

    test('⚓ وكلُّ قيدٍ متوازنٌ في نفسه', () async {
      // مصالحةٌ فوق دفترٍ غيرِ متوازنٍ بلا معنى.
      final rows = await db.customSelect(
        'SELECT e.id, SUM(l.debit) AS dr, SUM(l.credit) AS cr '
        'FROM journal_entries e JOIN journal_entry_lines l ON l.entry_id = e.id '
        'WHERE e.is_posted = 1 AND e.is_deleted = 0 '
        'GROUP BY e.id',
      ).get();
      expect(rows, isNotEmpty);
      for (final r in rows) {
        expect((r.data['dr'] as num).toDouble(),
            closeTo((r.data['cr'] as num).toDouble(), _tolerance),
            reason: 'القيدُ #${r.data['id']} غيرُ متوازن');
      }
    });

    test('⚓ ونشاطُ التجهيزة كلُّه قبلَ القطع', () async {
      // الشرطُ الذي تقوم عليه مساواةُ «البطاقةِ الراهنة» بـ«أستاذِ القطع».
      final late_ = await db.customSelect(
        'SELECT COUNT(*) AS n FROM journal_entries WHERE entry_date > ?',
        variables: [Variable.withDateTime(kCutoff)],
      ).getSingle();
      expect(late_.data['n'], 0,
          reason: 'قيدٌ بعد القطع في التجهيزة ⇒ البطاقةُ الراهنةُ تشمل ما '
              'لا يشمله أستاذُ القطع، وكلُّ مساواةٍ أدناه تكذب.');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // ١ — الخزينة: حسابُ النقديّة ↔ أرصدةُ الخزن
  // ═══════════════════════════════════════════════════════════════════════

  group('١ — الخزينة', () {
    Future<double> safesTotal(int accountId) async {
      final rows = await (db.select(db.safes)
            ..where((s) => s.linkedAccountId.equals(accountId)))
          .get();
      return rows.fold<double>(0, (a, s) => a + s.balance);
    }

    test('⚓ مرساة: الطرفان تحرّكا', () async {
      expect((await glAsOf(cashAccountId, kCutoff)).abs(), greaterThan(0),
          reason: 'أستاذُ النقديّة ساكنٌ ⇒ المساواةُ صفرٌ=صفر');
      expect((await safesTotal(cashAccountId)).abs(), greaterThan(0),
          reason: 'رصيدُ الخزن ساكنٌ ⇒ السنداتُ لا تحرّك الخزنة');
    });

    test('🔴 رصيدُ الخزن = رصيدُ حساب النقديّة عند القطع', () async {
      final gl = await glAsOf(cashAccountId, kCutoff);
      final card = await safesTotal(cashAccountId);
      expect(card, closeTo(gl, _tolerance),
          reason: 'نقدٌ في الدرج لا يعرفه الأستاذ (‏أو العكس). الفرقُ '
              '${(card - gl).toStringAsFixed(2)} — مالٌ بلا تفسير.');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // ٢ — المخزون: حسابُ المخزون ↔ تقييمُ المخزون
  // ═══════════════════════════════════════════════════════════════════════

  group('٢ — المخزون', () {
    /// القيمةُ الدفتريّةُ **القابلةُ للمقارنة بحساب `1136` وحدَه**.
    ///
    /// ⚠️ الترشيحان ليسا تجميلاً:
    ///   • `track_inventory = 0` صنفٌ لا يُرحَّل للمخزون أصلاً (خدمةٌ مثلاً)،
    ///     فإدخالُه يُنتج فرقاً وهميّاً دائماً.
    ///   • و`raw_material` يُرحَّل إلى **`1131`** لا `1136` — انظر
    ///     `inventoryAccountPurposeForProduct`. فخلطُهما يقارن حسابين بواحد.
    Future<double> perpetualValue() async {
      final r = await db.customSelect(
        'SELECT COALESCE(SUM(current_stock * cost_price), 0) AS v '
        'FROM products '
        "WHERE track_inventory = 1 AND product_type != 'raw_material'",
      ).getSingle();
      return (r.data['v'] as num).toDouble();
    }

    test('⚓ مرساة: الشراءُ والبيعُ حرّكا الطرفين', () async {
      expect(await perpetualValue(), greaterThan(0),
          reason: 'لا بضاعةَ في المخزن ⇒ المصالحةُ تقيس فراغاً');
      expect((await glByCode('1136', kCutoff)).abs(), greaterThan(0),
          reason: 'حسابُ المخزون ساكنٌ ⇒ الشراءُ لم يُرحّل');
    });

    test('🔴 قيمةُ المخزون = رصيدُ حساب المخزون عند القطع', () async {
      final gl = await glByCode('1136', kCutoff);
      final perpetual = await perpetualValue();
      expect(perpetual, closeTo(gl, _tolerance),
          reason: 'المخزنُ يقول ${perpetual.toStringAsFixed(2)} والأستاذُ '
              '${gl.toStringAsFixed(2)}. الفرقُ يظهر في الميزانيّة أصلاً '
              'وهميّاً أو ناقصاً، ولا يُصحَّح إلّا بجرد.');
    });

    test('ودفترُ الأرصدة يوافق عمودَ الرصيد', () async {
      // الطرفُ الثالث: `inventory_balances` مقابلَ `products.current_stock`.
      // انفرادُ أحدهما يحدّد أينَ العطب — في الترحيل أم في العمود.
      final r = await db.customSelect(
        'SELECT COALESCE(SUM(b.quantity * p.cost_price), 0) AS v '
        'FROM inventory_balances b JOIN products p ON p.id = b.product_id '
        "WHERE p.track_inventory = 1 AND p.product_type != 'raw_material'",
      ).getSingle();
      expect((r.data['v'] as num).toDouble(),
          closeTo(await perpetualValue(), _tolerance),
          reason: 'دفترُ الأرصدة يخالف عمودَ `current_stock` ⇒ أحدهما لا '
              'يُحدَّث في مسارٍ ما.');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // ٣ — الموردون: ذمّةُ الموردين ↔ أرصدةُ بطاقاتهم
  // ═══════════════════════════════════════════════════════════════════════

  group('٣ — الموردون', () {
    test('⚓ مرساة: للمورد حسابٌ فرعيٌّ وبطاقتُه تحرّكت', () async {
      final p = await partyOf(supplierId);
      expect(p.accountId, isNotNull,
          reason: 'موردٌ بلا حسابٍ فرعيٍّ لا يُصالَح');
      expect(p.balance.abs(), greaterThan(0),
          reason: 'بطاقةُ المورد ساكنة ⇒ الشراءُ الآجلُ لم يُقيَّد عليه');
    });

    test('🔴 بطاقةُ المورد = رصيدُ حسابه الفرعيّ عند القطع', () async {
      final p = await partyOf(supplierId);
      final gl = await glAsOf(p.accountId!, kCutoff);
      // الموردُ حسابٌ **دائنُ** الطبيعة: البطاقةُ موجبةٌ لما نحن مدينون به،
      // ورصيدُ الأستاذ (مدين−دائن) سالبٌ بنفس المقدار.
      expect(p.balance, closeTo(-gl, _tolerance),
          reason: 'ذمّةُ المورد في البطاقة ${p.balance.toStringAsFixed(2)} '
              'وفي الأستاذ ${(-gl).toStringAsFixed(2)}. الفرقُ يعني دفعةً '
              'لمن لا يستحقّ أو دَيناً منسيّاً.');
    });

    test('🔴 وذمّةُ العميل كذلك', () async {
      final p = await partyOf(customerId);
      final gl = await glAsOf(p.accountId!, kCutoff);
      // مرساةٌ في موضعها: البيعُ جزئيُّ السداد عمداً، فرصيدٌ صفريٌّ هنا
      // يعني أنّ الترحيلَ على العميل لم يقع لا أنّ الدفاترَ متّفقة.
      expect(p.balance.abs(), greaterThan(0),
          reason: 'رصيدُ العميل صفرٌ رغم بيعٍ جزئيِّ السداد ⇒ المساواةُ '
              'أدناه صفرٌ=صفر ولا تقيس شيئاً.');
      // العميلُ حسابٌ **مدينُ** الطبيعة — الإشارةُ معه لا عليه.
      expect(p.balance, closeTo(gl, _tolerance),
          reason: 'ذمّةُ العميل في البطاقة تخالف الأستاذ — مطالبةٌ بمالٍ '
              'مدفوعٍ أو إسقاطُ دَينٍ قائم.');
    });

    test('وأوراقُ التحميل المسوَّدةُ لا تُقيَّد بعد', () async {
      // ورقةٌ `draft` عملٌ ورقيٌّ لا التزام. قيدُها يقع عند التطبيق.
      final sheets = await (db.select(db.landedCostSheets)
            ..where((s) => s.status.equals('draft')))
          .get();
      for (final s in sheets) {
        final entries = await (db.select(db.journalEntries)
              ..where((e) =>
                  e.referenceType.equals('landed_cost') &
                  e.referenceId.equals(s.id)))
            .get();
        expect(entries, isEmpty,
            reason: 'ورقةُ تحميلٍ مسوَّدةٌ رحّلت قيداً ⇒ التزامٌ بلا مستندٍ '
                'مطبَّق.');
      }
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // ٤ — الأصول: مجمعُ الإهلاك في الأستاذ ↔ مجموعُ بطاقات الأصول
  // ═══════════════════════════════════════════════════════════════════════

  group('٤ — الأصول', () {
    Future<double> cardsAccumulated() async {
      final rows = await db.select(db.fixedAssets).get();
      return rows.fold<double>(0, (a, x) => a + x.accumulatedDepreciation);
    }

    test('⚓ مرساة: الإهلاكُ رُحِّل فعلاً', () async {
      expect(await cardsAccumulated(), greaterThan(0),
          reason: 'بطاقاتُ الأصول بلا مجمَّعٍ ⇒ الترحيلُ لم يقع');
      expect((await glAsOf(accumDeprAccountId, kCutoff)).abs(), greaterThan(0),
          reason: 'حسابُ مجمّع الإهلاك ساكنٌ ⇒ الترحيلُ لم يصل الأستاذ');
    });

    test('🔴 مجموعُ البطاقات = رصيدُ مجمّع الإهلاك عند القطع', () async {
      final gl = await glAsOf(accumDeprAccountId, kCutoff);
      final cards = await cardsAccumulated();
      // مجمّعُ الإهلاك حسابٌ **مقابلٌ** دائنُ الطبيعة.
      expect(cards, closeTo(-gl, _tolerance),
          reason: 'البطاقاتُ تقول ${cards.toStringAsFixed(2)} والأستاذُ '
              '${(-gl).toStringAsFixed(2)}. الفرقُ يعني قيمةً دفتريّةً '
              'كاذبةً في الميزانيّة.');
    });

    test('وصفوفُ الإهلاك تساوي مجمَّعَ البطاقة', () async {
      // الطرفُ الثالث: جدولُ `asset_depreciations`. ثلاثةُ أطرافٍ تتّفق
      // أقوى من طرفين — وانفرادُ أحدها يحدّد أينَ العطب.
      final rows = await (db.select(db.assetDepreciations)
            ..where((d) => d.periodDate.isSmallerOrEqualValue(kCutoff)))
          .get();
      final sum = rows.fold<double>(0, (a, d) => a + d.depreciationAmount);
      expect(sum, closeTo(await cardsAccumulated(), _tolerance),
          reason: 'صفوفُ الإهلاك تخالف مجمَّعَ البطاقة ⇒ شهرٌ رُحِّل مرّتين '
              'أو بطاقةٌ لم تُحدَّث.');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // ٥ — الضريبة: ضريبةٌ مستحقّة ↔ مستنداتُ الفوترة الإلكترونيّة
  // ═══════════════════════════════════════════════════════════════════════

  group('٥ — الضريبة', () {
    Future<double> invoicedTax(DateTime asOf) async {
      final r = await db.customSelect(
        'SELECT COALESCE(SUM(tax), 0) AS t FROM sales_invoices '
        "WHERE status != 'returned' AND invoice_date <= ?",
        variables: [Variable.withDateTime(asOf)],
      ).getSingle();
      return (r.data['t'] as num).toDouble();
    }

    test('⚓ مرساة: البيعُ رحّل ضريبةً فعلاً', () async {
      expect(await invoicedTax(kCutoff), greaterThan(0),
          reason: 'لا ضريبةَ على أيّ فاتورة ⇒ المصالحةُ تقيس فراغاً');
      expect((await glByCode('2121', kCutoff)).abs(), greaterThan(0),
          reason: 'حسابُ الضريبة المحصَّلة ساكنٌ ⇒ ضريبةٌ محصَّلةٌ من العميل '
              'وغيرُ مسجَّلةٍ للمصلحة.');
    });

    test('🔴 ضريبةُ الفواتير = رصيدُ الضريبة المستحقّة عند القطع', () async {
      final gl = await glByCode('2121', kCutoff);
      final invoiced = await invoicedTax(kCutoff);
      // `2121` التزامٌ دائنُ الطبيعة.
      expect(invoiced, closeTo(-gl, _tolerance),
          reason: 'الفواتيرُ تقول ${invoiced.toStringAsFixed(2)} والأستاذُ '
              '${(-gl).toStringAsFixed(2)} — إقرارٌ خاطئٌ في الاتّجاهين: '
              'نقصٌ يُعرّض لغرامة، وزيادةٌ تدفع ما لا يُستحقّ.');
    });

    test('🔴 وكلُّ فاتورةٍ ذاتِ ضريبةٍ لها مستندٌ إلكترونيٌّ مقبول', () async {
      final uncovered = await db.customSelect(
        'SELECT i.invoice_number FROM sales_invoices i '
        'LEFT JOIN e_invoice_submissions s '
        "  ON s.sale_id = i.id AND s.status = 'accepted' "
        "WHERE i.tax > 0 AND i.status != 'returned' "
        '  AND i.invoice_date <= ? AND s.id IS NULL',
        variables: [Variable.withDateTime(kCutoff)],
      ).get();

      expect(
        uncovered.map((r) => r.data['invoice_number']).toList(),
        isEmpty,
        reason: 'فواتيرُ محمَّلةٌ بضريبةٍ بلا مستندٍ إلكترونيٍّ مقبول: '
            'الضريبةُ في الدفاتر ولا إقرارَ يقابلها عند المصلحة.',
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // حدودُ تاريخ القطع — الشرطُ الذي تقوم عليه كلُّ مساواةٍ أعلاه
  // ═══════════════════════════════════════════════════════════════════════

  group('حدودُ تاريخ القطع', () {
    /// قيدٌ مؤرَّخٌ بعدَ القطع، يُكتَب مباشرةً: المسارُ الحقيقيُّ للسندات لا
    /// يقبل تاريخاً (‏`DateTime.now()`)، والمقصودُ هنا فحصُ **القصِّ** نفسِه
    /// لا فحصُ السند.
    Future<void> postAfterCutoff(double amount) async {
      final id = await db.into(db.journalEntries).insert(
            JournalEntriesCompanion.insert(
              entryNumber: 'JE-LATE',
              entryDate: kAfterCutoff,
            ),
          );
      await db.into(db.journalEntryLines).insert(
            JournalEntryLinesCompanion.insert(
              entryId: id,
              accountId: cashAccountId,
              debit: Value(amount),
            ),
          );
    }

    test('🔴 قيدٌ بعد القطع لا يدخل أستاذَ القطع', () async {
      final before = await glAsOf(cashAccountId, kCutoff);
      await postAfterCutoff(777);
      expect(await glAsOf(cashAccountId, kCutoff), closeTo(before, _tolerance),
          reason: 'قيدٌ مؤرَّخٌ بعد القطع دخل أستاذَ القطع ⇒ القصُّ بالتاريخ '
              'معطَّل، وكلُّ رقمٍ في هذا الملفِّ مشكوكٌ فيه.');
    });

    test('ويدخل أستاذاً لاحقاً — فالقصُّ يقصّ ولا يحذف', () async {
      final atCutoff = await glAsOf(cashAccountId, kCutoff);
      await postAfterCutoff(777);
      final later = await glAsOf(cashAccountId, DateTime(2027, 12, 31));
      expect(later - atCutoff, closeTo(777, _tolerance),
          reason: 'الفرقُ بين الأستاذَين ليس ما وقع بينهما ⇒ القصُّ يقصّ '
              'خطأً — وهو أسوأُ من ألّا يقصّ، لأنّه يبدو عاملاً.');
    });
  });
}
