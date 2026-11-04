// تدقيق المبيعات — تطابق PostgreSQL (2026-10-31).
// يعمل فقط مع PG_TEST_DSN على حاوية تدقيق خاصة (لا قواعد المالك):
//   $env:PG_TEST_DSN='postgres://postgres:auditpw@127.0.0.1:55644/postgres'
//   flutter test test/audit_repro/sales_purchases/e_pg_parity_audit_test.dart --run-skipped
@Tags(['pg'])
@Timeout(Duration(minutes: 6))
library;

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/core/permissions/permission_codes.dart';
import 'package:picpos_erp/data/providers/providers.dart';
import 'package:picpos_erp/data/repositories/sales_transaction_orchestrator.dart';
import 'package:picpos_erp/data/repositories/treasury_repository_impl.dart';
import 'package:picpos_erp/domain/entities/cart_item_entity.dart';
import 'package:picpos_erp/domain/entities/product_entity.dart';
import 'package:picpos_erp/domain/repositories/sales_repository.dart';
import 'package:picpos_erp/services/accounting_service.dart';
import 'package:picpos_erp/services/stock_shortage_policy_service.dart';

import '../../integration_pg/_support/pg_fixture.dart';

const kSkip = 'audit repro — pending owner approval';

void _log(String m) {
  // ignore: avoid_print
  print('[AUDIT-PG] $m');
}

class _W {
  _W(this.db, this.c, this.sales);
  final AppDatabase db;
  final ProviderContainer c;
  final SalesTransactionOrchestrator sales;
  void dispose() => c.dispose();
}

_W _wrap(AppDatabase db) {
  final c = ProviderContainer(overrides: [
    databaseProvider.overrideWithValue(db),
    accountingServiceProvider.overrideWith((ref) => AccountingService(
          ref.watch(accountingRepositoryProvider),
          ref.watch(partiesRepositoryProvider),
          TreasuryRepositoryImpl(db, ref),
          ref.watch(productRepositoryProvider),
          ref.watch(inventoryRepositoryProvider),
          ref.watch(settingsRepositoryProvider),
          ref.watch(auditRepositoryProvider),
        )),
  ]);
  return _W(db, c, SalesTransactionOrchestrator(db, c.read(accountingServiceProvider)));
}

void main() {
  late PgTestFixture fx;
  late _W w;
  late int userId, wh, safe;

  Future<int> product(String code, {double cost = 60, double stock = 0}) async {
    final id = await w.db.insertProduct(ProductsCompanion.insert(
        code: code, name: 'صنف $code', salePrice: const Value(100), costPrice: Value(cost),
        trackInventory: const Value(true)));
    if (stock > 0) {
      await w.db.adjustStock(
          productId: id, warehouseId: wh, quantity: stock, type: 'in', unitCost: cost, notes: 'افتتاحي');
    }
    return id;
  }

  SaleRequest req(int p, double qty, {String? gid, int? customerId,
      String paymentMethod = 'cash', double? paidAmount}) => SaleRequest(
      items: [CartItemEntity(productId: p, productName: 'p', productCode: 'p', quantity: qty, unitPrice: 100)],
      customerId: customerId,
      warehouseId: wh,
      userId: userId,
      paymentMethod: paymentMethod,
      paidAmount: paidAmount ?? qty * 100,
      taxEnabled: false,
      cashSafeId: safe,
      globalId: gid);

  Future<double> stock(int p) async => (await w.db.getProductById(p))!.currentStock;

  Future<Object> ret(_W ww, int invoiceId, int p, double qty) async {
    try {
      final it = (await ww.db.getSalesInvoiceItems(invoiceId)).firstWhere((i) => i.productId == p);
      final pr = (await ww.db.getProductById(p))!;
      return await ww.c.read(returnsRepositoryProvider).processSalesReturn(
            invoice: (await ww.db.getSalesInvoiceById(invoiceId))!,
            returnQuantities: {it.id: qty},
            productCache: {
              p: ProductEntity(
                  id: pr.id, name: pr.name, code: pr.code, salePrice: pr.salePrice,
                  costPrice: pr.costPrice, currentStock: pr.currentStock, minStock: pr.minStock,
                  trackInventory: pr.trackInventory)
            },
            reason: 'pg',
            userId: userId,
            userName: 'pg',
            isFullReturn: false,
          );
    } catch (e) {
      return 'EXC: $e';
    }
  }

  setUp(() async {
    StockShortagePolicyService.resetCacheForTest();
    fx = await bootPgTestSchema();
    await fx.db.customSelect('SELECT 1').get();
    await fx.db.syncDefaultAccounts();
    w = _wrap(fx.db);
    final roleId = await w.db.into(w.db.roles)
        .insert(RolesCompanion.insert(name: 'pg-audit', isSystemRole: const Value(false)));
    final perm = await (w.db.select(w.db.permissions)
          ..where((p) => p.code.equals(PermissionCodes.voidPaidInvoice))
          ..limit(1))
        .getSingle();
    await w.db.addPermissionToRole(roleId, perm.id);
    userId = await w.db.createUser(
        username: 'pg_audit', password: 'pg-audit-pw-1', displayName: 'pg', roleId: roleId);
    wh = (await w.db.getDefaultWarehouse())!.id;
    safe = (await w.db.getDefaultSafeByType('cash'))!.id;
    await w.db.openShift(userId, 0);
    await w.db.setSetting('enable_negative_sales', 'false');
  });
  tearDown(() async {
    StockShortagePolicyService.resetCacheForTest();
    w.dispose();
    await fx.tearDown();
  });

  test('PG-RCV overpayment rejection has no paid, treasury, party, or GL effects', () async {
    final customerId = await w.db.insertParty(PartiesCompanion.insert(
      name: 'عميل تحصيل PG', isCustomer: const Value(true),
    ));
    final p = await product('RCV-PG', cost: 5, stock: 2);
    final sale = await w.sales.completeSalesTransaction(req(
      p, 2, customerId: customerId, paymentMethod: 'credit', paidAmount: 0,
    ));
    expect(sale.isSuccess, isTrue, reason: sale.errorMessage);
    final invoiceId = sale.invoiceId!;
    final journalsBefore = (await w.db.select(w.db.journalEntries).get()).length;
    final safeBefore = (await w.db.select(w.db.safeTransactions).get()).length;
    final partyBefore = (await w.db.getPartyById(customerId))!.balance;
    Object result = true;
    try {
      await w.db.addSalesPayment(
        invoiceId: invoiceId, amount: 250, safeId: safe, userId: userId,
      );
    } catch (e) {
      result = 'EXC: $e';
    }
    _log('PG-RCV result=$result paid=${(await w.db.getSalesInvoiceById(invoiceId))!.paid}');
    expect(result, isNot(true));
    expect('$result', contains('PAYMENT_EXCEEDS_REMAINING'));
    expect((await w.db.getSalesInvoiceById(invoiceId))!.paid, 0);
    expect((await w.db.select(w.db.journalEntries).get()).length, journalsBefore);
    expect((await w.db.select(w.db.safeTransactions).get()).length, safeBefore);
    expect((await w.db.getPartyById(customerId))!.balance, partyBefore);
  });

  test('PG-NEG-02 stock_shortage_policy=allow_negative يتجاوز enable_negative_sales=false',
      () async {
    final p = await product('N178');
    await w.db.setSetting('stock_shortage_policy', 'allow_negative');
    final r = await w.sales.completeSalesTransaction(req(p, 13));
    _log('PG-NEG-02 success=${r.isSuccess} err=${r.errorMessage} stock=${await stock(p)}');
    expect(r.isSuccess, isTrue);
    expect(await stock(p), closeTo(-13, 0.005));
  });

  test('PG-NEG-01 بلا مفاتيح سياسة: يُرفض', skip: kSkip, () async {
    final p = await product('N179');
    final r = await w.sales.completeSalesTransaction(req(p, 5));
    _log('PG-NEG-01 success=${r.isSuccess} err=${r.errorMessage} stock=${await stock(p)}');
    expect(r.isSuccess, isFalse);
  });

  test('PG-RACE-01 اتصالان حقيقيان يبيعان آخر وحدة ⇒ ينجح واحد', skip: kSkip, () async {
    final p = await product('LAST', cost: 5, stock: 1);
    final w2 = _wrap(openExtraPgConnection());
    try {
      final rs = await Future.wait([
        w.sales.completeSalesTransaction(req(p, 1)),
        w2.sales.completeSalesTransaction(req(p, 1)),
      ]);
      _log('PG-RACE-01 results=${rs.map((r) => '${r.isSuccess}:${r.errorMessage}').toList()} stock=${await stock(p)}');
      expect(rs.where((r) => r.isSuccess).length, 1);
      expect(await stock(p), closeTo(0, 0.005));
    } finally {
      w2.dispose();
      await w2.db.close();
    }
  });

  test('PG-DUP-01 نفس globalId مرتين ⇒ فاتورة واحدة وإعادة الأصل', skip: kSkip, () async {
    final p = await product('DUP', stock: 10);
    const gid = '01900000-0000-7000-8000-00000000b001';
    final r1 = await w.sales.completeSalesTransaction(req(p, 2, gid: gid));
    final r2 = await w.sales.completeSalesTransaction(req(p, 2, gid: gid));
    final n = await w.db.customSelect('SELECT COUNT(*) n FROM sales_invoices').getSingle();
    _log('PG-DUP-01 r1=${r1.isSuccess} r2=${r2.isSuccess} err2=${r2.errorMessage} invoices=${n.data['n']} stock=${await stock(p)}');
    expect(r2.isSuccess, isTrue);
    expect(r2.invoiceId, r1.invoiceId);
  });

  test('PG-RET-02 مرتجع 5 ثم 5 من بيع 5 ⇒ رفض الثاني', skip: kSkip, () async {
    final p = await product('R5', stock: 50);
    final s = await w.sales.completeSalesTransaction(req(p, 5));
    final a = await ret(w, s.invoiceId!, p, 5);
    final b = await ret(w, s.invoiceId!, p, 5);
    _log('PG-RET-02 first=$a second=$b stock=${await stock(p)} safe=${(await w.db.getSafeById(safe))!.balance}');
    expect(b, isNot(true));
  });

  test('PG-RET-08 اتصالان: مرتجعان متزامنان 2+2 من 3 ⇒ ينجح واحد', skip: kSkip, () async {
    final p = await product('R3', stock: 50);
    final s = await w.sales.completeSalesTransaction(req(p, 3));
    final w2 = _wrap(openExtraPgConnection());
    try {
      final rs = await Future.wait([ret(w, s.invoiceId!, p, 2), ret(w2, s.invoiceId!, p, 2)]);
      _log('PG-RET-08 results=$rs stock=${await stock(p)}');
      expect(rs.where((x) => x == true).length, 1);
    } finally {
      w2.dispose();
      await w2.db.close();
    }
  });

  test('PG-ACC-01 accounts.balance = Σ القيود بعد بيع ومرتجع', skip: kSkip, () async {
    final p = await product('ACC', stock: 50);
    final s = await w.sales.completeSalesTransaction(req(p, 3));
    await ret(w, s.invoiceId!, p, 1);
    final rows = await w.db.customSelect(
        'SELECT a.code c, a.balance b, COALESCE((SELECT SUM(l.debit - l.credit) FROM journal_entry_lines l '
        'JOIN journal_entries e ON e.id = l.entry_id WHERE l.account_id = a.id AND e.is_deleted = false),0) n '
        'FROM accounts a').get();
    final drift = rows
        .where((r) => ((r.data['b'] as num) - (r.data['n'] as num)).abs() > 0.005)
        .map((r) => '${r.data['c']}: ${r.data['b']} vs ${r.data['n']}')
        .toList();
    _log('PG-ACC-01 drift=$drift');
    expect(drift, isEmpty);
  });
}
