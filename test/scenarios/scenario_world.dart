// عالَم السيناريوهات: قاعدة AppDatabase حقيقية في الذاكرة + نفس الخدمات التي
// تستعملها الشاشات (SalesTransactionOrchestrator · ReturnsRepositoryImpl ·
// PurchasesRepositoryImpl · قسائم الخزينة) مع أدوات قراءة للقيود والأرصدة.
// لا يُنشأ أي مستند بـSQL مباشر؛ SQL هنا للقراءة والتحقق فقط.
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/providers/providers.dart';
import 'package:ural_erp/core/permissions/permission_codes.dart';
import 'package:ural_erp/data/repositories/sales_transaction_orchestrator.dart';
import 'package:ural_erp/data/repositories/treasury_repository_impl.dart';
import 'package:ural_erp/services/accounting_service.dart';
import 'package:ural_erp/domain/entities/cart_item_entity.dart';
import 'package:ural_erp/domain/entities/product_entity.dart';
import 'package:ural_erp/domain/repositories/sales_repository.dart';

export 'package:ural_erp/data/database/database.dart';
export 'package:ural_erp/domain/repositories/sales_repository.dart' show SaleRequest;

/// فرق مقبول عند مقارنة الأرقام العشرية.
const double kEps = 0.005;

class ScenarioWorld {
  ScenarioWorld._(this.db, this.container, this.userId, this.warehouseId,
      this.cashSafeId, this.sales);

  final AppDatabase db;
  final ProviderContainer container;
  final int userId;
  final int warehouseId;
  final int cashSafeId;
  final SalesTransactionOrchestrator sales;

  /// يبني عالَماً جديداً: مستخدم بدور يملك صلاحية إلغاء الفاتورة المدفوعة،
  /// ورديّة مفتوحة (اختياري)، ومخزن/خزنة افتراضيان من البذر.
  static Future<ScenarioWorld> create({bool openShift = true}) async {
    final db = AppDatabase.forTesting();
    await db.syncDefaultAccounts();
    // ??????? ????? ???? ????? ??? accountingService ?TreasuryRepositoryImpl? ???
    // ????? test/unit/security_phase1_gates_test.dart: ????? ?????? ???? ??????.
    final container = ProviderContainer(overrides: [
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
    final roleId = await db.into(db.roles).insert(
        RolesCompanion.insert(name: 'مدير سيناريو', isSystemRole: const Value(false)));
    final perm = await (db.select(db.permissions)
          ..where((p) => p.code.equals(PermissionCodes.voidPaidInvoice))
          ..limit(1))
        .getSingle();
    await db.addPermissionToRole(roleId, perm.id);
    final userId = await db.createUser(
        username: 'scenario_user',
        password: 'scenario-pw-1',
        displayName: 'مستخدم السيناريو',
        roleId: roleId);
    final wh = (await db.getDefaultWarehouse())!.id;
    final safe = (await db.getDefaultSafeByType('cash'))!.id;
    if (openShift) await db.openShift(userId, 0);
    final w = ScenarioWorld._(db, container, userId, wh, safe,
        SalesTransactionOrchestrator(db, container.read(accountingServiceProvider)));
    return w;
  }

  /// ???? ??? ?????? ????????? ?????? ?????? (???? ??????? �?????? ????� ?? ???????? ??????).
  Future<void> grant(String code, {int? forUser}) async {
    final u = await (db.select(db.users)..where((x) => x.id.equals(forUser ?? userId))).getSingle();
    final p = await (db.select(db.permissions)..where((x) => x.code.equals(code))..limit(1)).getSingle();
    await db.addPermissionToRole(u.roleId!, p.id);
  }

  Future<void> dispose() async {
    container.dispose();
    await db.close();
  }

  // ───────────────────────── بيانات أساسية ─────────────────────────
  Future<int> addProduct(String code,
      {double price = 100, double cost = 60, double stock = 0, int? warehouse}) async {
    final id = await db.insertProduct(ProductsCompanion.insert(
        code: code,
        name: 'صنف $code',
        salePrice: Value(price),
        costPrice: Value(cost),
        trackInventory: const Value(true)));
    if (stock > 0) {
      await db.adjustStock(
          productId: id,
          warehouseId: warehouse ?? warehouseId,
          quantity: stock,
          type: 'in',
          unitCost: cost,
          notes: 'رصيد افتتاحي');
    }
    return id;
  }

  Future<int> addCustomer(String name) => db.insertParty(
      PartiesCompanion.insert(name: name, isCustomer: const Value(true)));

  Future<int> addSupplier(String name) => db.insertParty(
      PartiesCompanion.insert(
          name: name,
          isCustomer: const Value(false),
          isSupplier: const Value(true)));

  Future<int> addWarehouse(String name) => db.into(db.warehouses).insert(
      WarehousesCompanion.insert(name: name));

  // ───────────────────────── مبيعات ─────────────────────────
  CartItemEntity line(int productId, double qty, double price) => CartItemEntity(
      productId: productId,
      productName: 'p$productId',
      productCode: 'c$productId',
      quantity: qty,
      unitPrice: price);

  /// فاتورة بيع عبر الـorchestrator (بلا ضريبة ما لم يُطلب غير ذلك).
  Future<SaleResult> sell(List<CartItemEntity> items,
      {int? customerId,
      String method = 'cash',
      double? paid,
      bool tax = false,
      DateTime? date}) async {
    final r = await sellRaw(items,
        customerId: customerId, method: method, paid: paid, tax: tax, date: date);
    expect(r.isSuccess, isTrue, reason: r.errorMessage);
    return r;
  }

  /// كـ[sell] بلا افتراض النجاح: يعيد SaleResult.failure أو يرمي الاستثناء كما هو.
  Future<SaleResult> sellRaw(List<CartItemEntity> items,
      {int? customerId,
      String method = 'cash',
      double? paid,
      bool tax = false,
      DateTime? date}) async {
    final total = items.fold<double>(0, (s, i) => s + i.quantity * i.unitPrice);
    return sales.completeSalesTransaction(SaleRequest(
        items: items,
        customerId: customerId,
        warehouseId: warehouseId,
        userId: userId,
        paymentMethod: method,
        paidAmount: paid ?? (method == 'cash' ? total : 0),
        taxEnabled: tax,
        cashSafeId: cashSafeId,
        invoiceDate: date));
  }

  /// مرتجع بالمسار الحي الذي تنادِيه شاشة المردودات.
  Future<bool> returnItems(int invoiceId, int productId, double qty) async {
    final items = await db.getSalesInvoiceItems(invoiceId);
    final it = items.firstWhere((i) => i.productId == productId);
    final p = (await db.getProductById(productId))!;
    return container.read(returnsRepositoryProvider).processSalesReturn(
          invoice: (await db.getSalesInvoiceById(invoiceId))!,
          returnQuantities: {it.id: qty},
          productCache: {
            productId: ProductEntity(
                id: p.id,
                name: p.name,
                code: p.code,
                salePrice: p.salePrice,
                costPrice: p.costPrice,
                currentStock: p.currentStock,
                minStock: p.minStock,
                trackInventory: p.trackInventory)
          },
          reason: 'سيناريو',
          userId: userId,
          userName: 'مستخدم السيناريو',
          isFullReturn: false,
        );
  }

  /// البيع المرفوض: الـorchestrator يحوّل الاستثناء إلى SaleFailure برسالة؛ نقبل
  /// الشكلين (فشل بالرسالة أو استثناء) ونتحقق من نص السبب.
  Future<void> expectSaleRejected(Future<SaleResult> attempt, String reasonContains) async {
    try {
      final r = await attempt;
      expect(r.isFailure, isTrue, reason: 'كان يجب رفض البيع');
      expect(r.errorMessage, contains(reasonContains));
    } on Exception catch (e) {
      expect(e.toString(), contains(reasonContains));
    }
  }

  // ───────────────────────── قراءة وتحقق ─────────────────────────
  Future<double> stock(int productId) async =>
      (await db.getProductById(productId))!.currentStock;

  Future<double> whQty(int productId, int warehouse) async {
    final r = await (db.select(db.inventoryBalances)
          ..where((t) =>
              t.productId.equals(productId) & t.warehouseId.equals(warehouse)))
        .getSingleOrNull();
    return r?.quantity ?? 0;
  }

  Future<double> safeBalance([int? id]) async =>
      (await db.getSafeById(id ?? cashSafeId))!.balance;

  Future<double> partyBalance(int id) async =>
      (await db.getPartyById(id))!.balance;

  /// مجموع (مدين، دائن) لكل القيود غير المحذوفة.
  Future<({double debit, double credit})> journalTotals() async {
    final r = await db.customSelect(
        'select coalesce(sum(l.debit),0) d, coalesce(sum(l.credit),0) c '
        'from journal_entry_lines l join journal_entries e on e.id = l.entry_id '
        'where e.is_deleted = 0').getSingle();
    return (
      debit: (r.data['d'] as num).toDouble(),
      credit: (r.data['c'] as num).toDouble()
    );
  }

  /// كل قيد على حدة متوازن؟ يعيد القيود غير المتوازنة (يجب أن تكون فارغة).
  Future<List<int>> unbalancedEntries() async {
    final r = await db.customSelect(
        'select e.id id from journal_entries e join journal_entry_lines l on l.entry_id = e.id '
        'where e.is_deleted = 0 group by e.id '
        'having abs(sum(l.debit) - sum(l.credit)) > 0.005').get();
    return r.map((x) => x.data['id'] as int).toList();
  }

  /// صافي (مدين − دائن) لحساب ولكل أبنائه (حسب شجرة الأكواد: يبدأ بالكود).
  Future<double> accountNet(String code) async {
    final r = await db.customSelect(
        'select coalesce(sum(l.debit - l.credit),0) n '
        'from journal_entry_lines l '
        'join journal_entries e on e.id = l.entry_id '
        'join accounts a on a.id = l.account_id '
        'where e.is_deleted = 0 and a.code like ?',
        variables: [Variable<String>('$code%')]).getSingle();
    return (r.data['n'] as num).toDouble();
  }

  /// أسطر القيود المرتبطة بمرجع (نوع/معرّف) للفحص التفصيلي.
  Future<List<Map<String, Object?>>> linesOf(String refType, int refId) async {
    final r = await db.customSelect(
        'select a.code code, l.debit debit, l.credit credit '
        'from journal_entry_lines l join journal_entries e on e.id = l.entry_id '
        'join accounts a on a.id = l.account_id '
        'where e.is_deleted = 0 and e.reference_type = ? and e.reference_id = ? '
        'order by l.id',
        variables: [Variable<String>(refType), Variable<int>(refId)]).get();
    return r.map((x) => x.data).toList();
  }

  /// ميزان المراجعة عن كل المدى: يتحقق أن إجمالي الحركة مدين = دائن ويعيده.
  Future<({double debit, double credit})> trialBalanceTotals() async {
    final rows = await db.getTrialBalance(DateTime(2000), DateTime(2100));
    final total = rows.lastWhere((r) => r['type'] == 'total');
    return (
      debit: (total['movementDebit'] as num).toDouble(),
      credit: (total['movementCredit'] as num).toDouble()
    );
  }
}
