// تدقيق القوائم المالية (2026-10-31) — عالَم اختبار مشترك لدورة أعمال كاملة.
//
// يبني على ScenarioWorld (test/scenarios) نفس الخدمات التي تستعملها الشاشات،
// ويضيف: مبيعات بخصم وضريبة، مرتجع، مصروف تشغيلي، سند قبض/صرف بخصم تسوية،
// شيك وارد مُحصَّل، أصل ثابت وإهلاك، مسير رواتب مرحَّل ومصروف.
// SQL هنا للقراءة والتحقق فقط. لا يُعدَّل أي كود إنتاجي.
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/core/permissions/permission_codes.dart';
import 'package:picpos_erp/data/providers/providers.dart';
import 'package:picpos_erp/domain/entities/cart_item_entity.dart';
import 'package:picpos_erp/domain/models/hr_employee_file.dart';
import 'package:picpos_erp/domain/repositories/purchases_repository.dart';
import 'package:picpos_erp/domain/repositories/sales_repository.dart';

import '../../scenarios/scenario_world.dart';

export '../../scenarios/scenario_world.dart';

const auditSkip = 'audit repro — pending owner approval';

/// نافذة التقارير: تغطي تاريخ المستندات (أمس 10:00) وتاريخ السندات (الآن).
DateTime get winFrom => DateTime.now().subtract(const Duration(days: 20));
DateTime get winTo => DateTime.now().add(const Duration(days: 1));

/// تاريخ المستندات المؤرَّخة صراحةً (يتجنّب عبور منتصف الليل أثناء التشغيل).
DateTime get docDate {
  final y = DateTime.now().subtract(const Duration(days: 1));
  return DateTime(y.year, y.month, y.day, 10);
}

class FsCycle {
  FsCycle(this.w);
  final ScenarioWorld w;
  late int product;
  late int customer;
  late int supplier;
  late int cashInvoice;
  late int creditInvoice;
  final Map<String, Object?> log = {};

  Future<void> ensureAccount(String code, String name, String type) async {
    if (await w.db.getAccountByCode(code) != null) return;
    await w.db.into(w.db.accounts).insert(
        AccountsCompanion.insert(code: code, name: name, accountType: type));
  }

  Future<SaleResult> sale(List<CartItemEntity> items,
      {int? customerId,
      required String method,
      required double paid,
      double? discountAmount}) async {
    final r = await w.sales.completeSalesTransaction(SaleRequest(
      items: items,
      customerId: customerId,
      warehouseId: w.warehouseId,
      userId: w.userId,
      paymentMethod: method,
      paidAmount: paid,
      taxEnabled: true,
      taxPercent: 14,
      invoiceDiscountAmount: discountAmount,
      cashSafeId: w.cashSafeId,
      invoiceDate: docDate,
    ));
    expect(r.isSuccess, isTrue, reason: r.errorMessage);
    return r;
  }

  /// الدورة كاملة. كل خطوة تسجّل ما حدث في [log].
  Future<void> run({bool payroll = true, bool assets = true}) async {
    final db = w.db;
    for (final c in [
      PermissionCodes.treasuryReceiptsCreate,
      PermissionCodes.treasuryPaymentsCreate,
      PermissionCodes.accountingJournal,
      PermissionCodes.hrPayrollPost,
    ]) {
      try {
        await w.grant(c);
      } catch (_) {}
    }
    product = await w.addProduct('FS1', price: 100, cost: 60);
    customer = await w.addCustomer('عميل التدقيق');
    supplier = await w.addSupplier('مورد التدقيق');

    // 1) رصيد افتتاحي للمخزون: 10 × 60 = 600 (مدين مخزون / دائن حقوق ملكية افتتاحية)
    await db.adjustStock(
        productId: product,
        warehouseId: w.warehouseId,
        quantity: 10,
        type: 'opening_stock',
        unitCost: 60,
        notes: 'رصيد افتتاحي — تدقيق');

    // 2) شراء آجل 10 × 60 = 600 + ض.ق.م 14% = 84 ⇒ 684
    final purchases = w.container.read(purchasesRepositoryProvider);
    await purchases.createInvoice(CreatePurchaseInvoiceParams(
        supplierId: supplier,
        warehouseId: w.warehouseId,
        paid: 0,
        paymentMethod: 'credit',
        userId: w.userId,
        items: [
          PurchaseItemParams(
              productId: product,
              quantity: 10,
              unitCost: 60,
              salePrice: 100,
              taxRate: 14,
              taxAmount: 84)
        ]));

    // 3) بيع نقدي 3 × 100 = 300، خصم فاتورة 20 ⇒ 280 + ض.ق.م
    const cashTotalGuess = (300 - 20) * 1.14;
    final c = await sale([w.line(product, 3, 100)],
        method: 'cash', paid: cashTotalGuess, discountAmount: 20);
    cashInvoice = c.invoiceId!;
    // 4) بيع آجل لعميل 2 × 100 = 200، خصم 10 ⇒ 190 + ض.ق.م
    final cr = await sale([w.line(product, 2, 100)],
        customerId: customer, method: 'credit', paid: 0, discountAmount: 10);
    creditInvoice = cr.invoiceId!;

    // 5) مرتجع مبيعات: 1 من البيع النقدي
    log['returnOk'] = await w.returnItems(cashInvoice, product, 1);

    // 6) مصروف تشغيلي نقدي 50
    final cat = await db.createExpenseCategory(name: 'كهرباء — تدقيق');
    await db.recordAndPostOperationalExpense(
        categoryId: cat,
        amount: 50,
        expenseDate: docDate,
        description: 'فاتورة كهرباء',
        expenseAccountCode: '6214',
        userId: w.userId,
        paymentMethod: 'cash',
        safeId: w.cashSafeId);

    // 7) سند قبض من العميل 100 + خصم تسوية 5
    await db.createReceiptVoucher(
        amount: 100,
        discount: 5,
        category: 'customers',
        partyId: customer,
        safeId: w.cashSafeId,
        userId: w.userId,
        description: 'قبض — تدقيق');
    // 8) سند صرف للمورد 200 + خصم مكتسب 10
    await db.createPaymentVoucher(
        amount: 200,
        discount: 10,
        category: 'suppliers',
        partyId: supplier,
        safeId: w.cashSafeId,
        userId: w.userId,
        description: 'صرف — تدقيق');

    // 9) شيك وارد من العميل 40 ثم تحصيل نقدي
    final paper = await db.createCommercialPaper(
        paperNumber: 'AUD-CHQ-1',
        type: 'cheque',
        direction: 'received',
        partyId: customer,
        amount: 40,
        issueDate: DateTime.now(),
        dueDate: DateTime.now());
    await db.changePaperStatus(
        paperId: paper, newStatus: 'cashed', changedBy: w.userId);

    if (assets) {
      // 10) أصل ثابت 1200 (عمر سنة) + إهلاك شهر = 100
      final assetAcc = (await db.getAccountByCode('1213'))!;
      final accDep = (await db.getAccountByCode('1219'))!;
      final catId = await db.createAssetCategory(
          name: 'آلات — تدقيق',
          defaultUsefulLife: 1,
          accountId: assetAcc.id,
          depreciationAccountId: accDep.id);
      await db.createFixedAsset(
          code: 'AUD-A1',
          name: 'ماكينة تدقيق',
          categoryId: catId,
          purchasePrice: 1200,
          purchaseDate: DateTime.now().subtract(const Duration(days: 40)),
          usefulLifeYears: 1);
      final failures = <String>[];
      log['depCount'] =
          await db.runMonthlyDepreciation(DateTime.now(), failures: failures);
      log['depFailures'] = failures;
    }

    if (payroll) {
      // 11) مسير رواتب: موظف 1000 — مراجعة/اعتماد/ترحيل/صرف
      for (final (code, name, type) in [
        ('621', 'رواتب وأجور', 'expense'),
        ('2131', 'رواتب مستحقة', 'liability'),
        ('2132', 'تأمينات مستحقة', 'liability'),
        ('2123', 'ضريبة رواتب', 'liability'),
        ('1146', 'سلف الموظفين', 'asset'),
      ]) {
        await ensureAccount(code, name, type);
      }
      try {
        await db.saveEmployeeProfile(
          EmployeeProfile(
              name: 'موظف تدقيق',
              basicSalary: 1000,
              hireDate: DateTime(2020),
              status: EmployeeStatus.active,
              hoursPerDay: 8),
        );
        final now = DateTime.now();
        final run = await db.createPayrollRun(year: now.year, month: now.month);
        await db.reviewPayrollRun(run);
        await db.approvePayrollRun(run);
        log['payrollEntry'] = await db.postPayrollRun(run, date: now);
        await db.payPayrollRun(run, safeId: w.cashSafeId);
        log['payrollOk'] = true;
      } catch (e) {
        log['payrollError'] = e.toString();
      }
    }
  }

  // ─────────────────────────── قراءات ───────────────────────────
  Future<Map<String, dynamic>> income() =>
      w.db.getIncomeStatement(winFrom, winTo);
  Future<Map<String, dynamic>> balanceSheet() =>
      w.db.getBalanceSheet(winTo);

  /// الحسابات التي يختلف رصيدها المخزَّن accounts.balance عن مجموع القيود
  /// المرحَّلة غير المحذوفة (لنفس الحساب، بلا أبناء).
  Future<List<Map<String, Object?>>> cachedBalanceDrift() async {
    final rows = await w.db.customSelect('''
      SELECT a.code code, a.name name, a.balance cached,
        COALESCE((SELECT SUM(l.debit - l.credit) FROM journal_entry_lines l
          JOIN journal_entries e ON e.id = l.entry_id
          WHERE l.account_id = a.id AND e.is_posted = 1 AND e.is_deleted = 0),0) gl
      FROM accounts a''').get();
    return [
      for (final r in rows)
        if (((r.data['cached'] as num).toDouble() -
                    (r.data['gl'] as num).toDouble())
                .abs() >
            0.005)
          r.data
    ];
  }

  Future<double> sumSafes() async {
    final r = await w.db
        .customSelect('SELECT COALESCE(SUM(balance),0) s FROM safes')
        .getSingle();
    return (r.data['s'] as num).toDouble();
  }

  Future<List<Map<String, Object?>>> accountMovements() async {
    final r = await w.db.customSelect('''
      SELECT a.code code, a.name name, a.account_type t,
        SUM(l.debit) d, SUM(l.credit) c
      FROM journal_entry_lines l JOIN journal_entries e ON e.id = l.entry_id
      JOIN accounts a ON a.id = l.account_id
      WHERE e.is_posted = 1 AND e.is_deleted = 0
      GROUP BY a.id ORDER BY a.code''').get();
    return r.map((x) => x.data).toList();
  }

  Future<List<Map<String, Object?>>> entries() async {
    final r = await w.db.customSelect('''
      SELECT e.id id, e.reference_type rt, e.reference_id rid, e.entry_date dt,
        e.is_posted p, e.is_deleted del,
        GROUP_CONCAT(a.code || ':' || l.debit || '/' || l.credit, ' ') lines
      FROM journal_entries e JOIN journal_entry_lines l ON l.entry_id = e.id
      JOIN accounts a ON a.id = l.account_id
      GROUP BY e.id ORDER BY e.id''').get();
    return r.map((x) => x.data).toList();
  }
}
