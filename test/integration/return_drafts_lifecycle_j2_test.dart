// J2 (قرارُ المالك) — دورةُ حياة مسوّدة المرتجع على قاعدةٍ حقيقيّة.
//
// ما يُقاس:
//   • «حفظ مسودة» لا يحرّك مخزوناً ولا يكتب قيداً ولا حركةَ خزينةٍ ولا يأخذ
//     رقماً من `document_sequences` — للمبيعات والمشتريات معاً؛
//   • المسوّدةُ تُعدَّل وتُحذَف، والمعتمدُ لا يُعدَّل ولا يُحذَف؛
//   • «مراجعة واعتماد» يرحّل بالمسار القائم نفسِه — أثرُه على المخزون والقيود
//     والخزينة مطابقٌ لمرتجعٍ مباشرٍ بنفس الكمّيّات — ثمّ يُختَم الصفُّ «معتمد»
//     برقم السند الذي وُلِّد في معاملة الترحيل؛
//   • الترقيمُ بلا فجوات: مسوّدةٌ محذوفةٌ لا تستهلك رقماً؛
//   • السجلُّ يجمع المسوّدةَ والمعتمدَ والملغى؛
//   • الجدولُ في قوائم المزامنة كلِّها، وصلاحيةُ الاعتماد تُمنَح مرّةً لمن
//     كان ينشئ المرتجعات.
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/core/permissions/permission_codes.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/data/repositories/drift_accounting_repository.dart';
import 'package:picpos_erp/data/repositories/return_drafts_repository.dart';
import 'package:picpos_erp/data/repositories/returns_repository_impl.dart';
import 'package:picpos_erp/domain/entities/product_entity.dart';
import 'package:picpos_erp/domain/models/return_draft.dart';
import 'package:picpos_erp/domain/repositories/audit_repository_interface.dart';
import 'package:picpos_erp/domain/repositories/i_products_repository.dart';
import 'package:picpos_erp/domain/repositories/inventory_repository.dart';
import 'package:picpos_erp/domain/repositories/parties_repository.dart';
import 'package:picpos_erp/domain/repositories/settings_repository.dart';
import 'package:picpos_erp/domain/repositories/treasury_repository.dart';
import 'package:picpos_erp/services/accounting_service.dart';
import 'package:picpos_erp/services/delta_pull_service.dart';
import 'package:picpos_erp/services/id_namespace_service.dart';

void main() {
  late AppDatabase db;
  late ReturnsRepositoryImpl returns;
  late ReturnDraftsRepository drafts;
  late int warehouseId;
  late int userId;
  late int productId;

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.syncDefaultAccounts();
    returns = ReturnsRepositoryImpl(
      db,
      AccountingService(
        DriftAccountingRepository(db),
        _StubParties(),
        _StubTreasury(),
        _StubProducts(),
        _StubInventory(),
        _StubSettings(),
        _StubAudit(),
      ),
    );
    drafts = ReturnDraftsRepository(db);

    final roleId = await db.into(db.roles).insert(
          RolesCompanion.insert(name: 'كاشير J2', isSystemRole: const Value(false)),
        );
    userId = await db.createUser(
      username: 'j2_returns',
      password: 'test123',
      displayName: 'J2 Tester',
      roleId: roleId,
    );
    await db.openShift(userId, 0);
    warehouseId = (await db.getDefaultWarehouse())!.id;
    productId = await db.insertProduct(
      ProductsCompanion.insert(
        code: 'J2-01',
        name: 'منتج',
        salePrice: const Value(100.0),
        costPrice: const Value(60.0),
        currentStock: const Value(0),
        trackInventory: const Value(true),
      ),
    );
    await db.adjustStock(
      productId: productId,
      warehouseId: warehouseId,
      quantity: 100,
      type: 'in',
      notes: 'seed',
    );
  });

  tearDown(() => db.close());

  Future<SalesInvoiceData> seedSale(String number, double qty) async {
    final id = await db.createSalesInvoice(
      invoiceNumber: number,
      warehouseId: warehouseId,
      userId: userId,
      subtotal: qty * 100,
      discount: 0,
      tax: 0,
      total: qty * 100,
      paid: qty * 100,
      paymentMethod: 'cash',
      items: [
        SalesInvoiceItemsCompanion.insert(
          invoiceId: 0,
          productId: productId,
          quantity: qty,
          unitPrice: 100,
          total: qty * 100,
          costPrice: const Value(60),
        ),
      ],
    );
    return (db.select(db.salesInvoices)..where((s) => s.id.equals(id)))
        .getSingle();
  }

  Future<ProductEntity> product() async {
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

  Future<int> count(String table, [String where = '1=1']) async {
    final r = await db
        .customSelect('SELECT COUNT(*) AS c FROM $table WHERE $where')
        .getSingle();
    return (r.data['c'] as num).toInt();
  }

  Future<Map<String, int>> footprint() async => {
        'stock_movements': await count('stock_movements'),
        'journal_entries': await count('journal_entries'),
        'safe_transactions': await count('safe_transactions'),
        'document_sequences': await count('document_sequences'),
      };

  Future<double> stock() async => (await db.getProductById(productId))!.currentStock;

  ReturnDraftInput salesDraft(SalesInvoiceData inv, int itemId, double qty,
          {int? id}) =>
      ReturnDraftInput(
        id: id,
        kind: ReturnDraftKind.sales,
        originalInvoiceId: inv.id,
        quantities: {itemId: qty},
        partyId: inv.customerId,
        branchId: inv.branchId,
        warehouseId: inv.warehouseId,
        reason: 'تالف',
        total: qty * 100,
        settlement: 'cash',
        userId: userId,
      );

  /// «مراجعة واعتماد»: المسارُ القائمُ نفسُه بكمّيّات المسوّدة، ثمّ الختم.
  Future<void> approve(ReturnDraft d, SalesInvoiceData inv) async {
    final ok = await returns.processSalesReturn(
      invoice: inv,
      returnQuantities: d.quantities,
      productCache: {productId: await product()},
      reason: d.reason ?? '',
      userId: userId,
      userName: 'J2 Tester',
      isFullReturn: d.isFullReturn,
      isDamaged: d.isDamaged,
    );
    expect(ok, isTrue);
    await drafts.markPosted(d);
  }

  int trailing(String voucher) =>
      int.parse(RegExp(r'(\d+)$').firstMatch(voucher)!.group(1)!);

  test('saving a sales/purchase draft moves nothing and takes no number',
      () async {
    final inv = await seedSale('INV-J2-1', 10);
    final item = (await db.getSalesInvoiceItems(inv.id)).single;
    final before = await footprint();
    final stockBefore = await stock();

    final id = await drafts.saveDraft(salesDraft(inv, item.id, 4));
    final pid = await drafts.saveDraft(const ReturnDraftInput(
      kind: ReturnDraftKind.purchase,
      originalInvoiceId: 999,
      quantities: {1: 2},
      total: 50,
    ));

    expect(await footprint(), before,
        reason: 'a draft must write no stock, JE, treasury row or number');
    expect(await stock(), stockBefore);
    final d = (await drafts.getDraft(id))!;
    expect(d.status, ReturnRecordStatus.draft);
    expect(d.quantities, {item.id: 4.0});
    expect(d.draftLabel, 'D-$id');
    expect((await drafts.getDraft(pid))!.kind, ReturnDraftKind.purchase);
    expect((await db.customSelect(
                'SELECT global_id FROM return_drafts WHERE id = ?',
                variables: [Variable<int>(id)]).getSingle())
            .data['global_id'],
        isNotNull,
        reason: 'synced rows carry a global id');
  });

  test('a draft is editable and deletable; a posted one is neither', () async {
    final inv = await seedSale('INV-J2-2', 10);
    final item = (await db.getSalesInvoiceItems(inv.id)).single;
    final id = await drafts.saveDraft(salesDraft(inv, item.id, 2));
    await drafts.saveDraft(salesDraft(inv, item.id, 3, id: id));
    expect((await drafts.getDraft(id))!.quantities, {item.id: 3.0});

    final other = await drafts.saveDraft(salesDraft(inv, item.id, 1));
    await drafts.deleteDraft(other);
    expect(await drafts.getDraft(other), isNull);

    await approve((await drafts.getDraft(id))!, inv);
    expect(() => drafts.saveDraft(salesDraft(inv, item.id, 1, id: id)),
        throwsA(isA<ReturnDraftException>()));
    expect(() => drafts.deleteDraft(id), throwsA(isA<ReturnDraftException>()));
  });

  test('approve posts exactly like the direct path and stamps the number',
      () async {
    final a = await seedSale('INV-J2-A', 10);
    final b = await seedSale('INV-J2-B', 10);
    final aItem = (await db.getSalesInvoiceItems(a.id)).single;
    final bItem = (await db.getSalesInvoiceItems(b.id)).single;

    // المباشر (اليوم): بلا مسوّدة.
    final before = await footprint();
    final s0 = await stock();
    expect(
      await returns.processSalesReturn(
        invoice: b,
        returnQuantities: {bItem.id: 4},
        productCache: {productId: await product()},
        reason: 'تالف',
        userId: userId,
        userName: 'J2 Tester',
        isFullReturn: false,
      ),
      isTrue,
    );
    final direct = await footprint();
    final directStock = await stock() - s0;

    // المسوّدةُ ثمّ الاعتماد بنفس الكمّيّات.
    final id = await drafts.saveDraft(salesDraft(a, aItem.id, 4));
    final s1 = await stock();
    await approve((await drafts.getDraft(id))!, a);
    final viaDraft = await footprint();

    for (final t in ['stock_movements', 'journal_entries', 'safe_transactions']) {
      expect(viaDraft[t]! - direct[t]!, direct[t]! - before[t]!,
          reason: '$t: approve must write what the direct path writes');
    }
    expect(await stock() - s1, directStock);

    final posted = (await drafts.getDraft(id))!;
    expect(posted.status, ReturnRecordStatus.posted);
    expect(posted.postedNumber, isNotNull);
    expect(posted.postedNumber, startsWith('SRET-'));
  });

  test('numbering stays gap-free: a deleted draft burns no number', () async {
    final inv1 = await seedSale('INV-J2-N1', 5);
    final inv2 = await seedSale('INV-J2-N2', 5);
    final i1 = (await db.getSalesInvoiceItems(inv1.id)).single;
    final i2 = (await db.getSalesInvoiceItems(inv2.id)).single;

    final dropped = await drafts.saveDraft(salesDraft(inv1, i1.id, 1));
    await drafts.deleteDraft(dropped);
    final first = await drafts.saveDraft(salesDraft(inv1, i1.id, 2));
    final second = await drafts.saveDraft(salesDraft(inv2, i2.id, 1));
    await approve((await drafts.getDraft(first))!, inv1);
    await approve((await drafts.getDraft(second))!, inv2);

    final n1 = (await drafts.getDraft(first))!.postedNumber!;
    final n2 = (await drafts.getDraft(second))!.postedNumber!;
    expect(trailing(n2), trailing(n1) + 1,
        reason: 'consecutive posts take consecutive numbers — drafts take none');
  });

  test('the sales record shows draft, posted and cancelled rows', () async {
    final inv = await seedSale('INV-J2-R', 10);
    final item = (await db.getSalesInvoiceItems(inv.id)).single;
    final from = DateTime.now().subtract(const Duration(days: 1));
    final to = DateTime.now().add(const Duration(days: 1));

    final draftId = await drafts.saveDraft(salesDraft(inv, item.id, 1));
    final postedId = await drafts.saveDraft(salesDraft(inv, item.id, 2));
    await approve((await drafts.getDraft(postedId))!, inv);

    var rows = await drafts.salesRecords(from: from, to: to);
    final draftRow = rows.singleWhere((e) => e.row.draftId == draftId).row;
    expect(draftRow.status, ReturnRecordStatus.draft);
    expect(draftRow.number, 'D-$draftId');
    final postedRow =
        rows.singleWhere((e) => e.row.status == ReturnRecordStatus.posted);
    expect(postedRow.row.number, startsWith('SRET-'));
    expect(postedRow.row.settlement, 'cash');
    expect(postedRow.row.total, closeTo(200, 0.01));
    expect(postedRow.originalInvoice?.id, inv.id);

    await drafts.markSalesCancelled(inv.id);
    rows = await drafts.salesRecords(from: from, to: to);
    expect(
        rows.where((e) => e.row.status == ReturnRecordStatus.cancelled),
        hasLength(1),
        reason: 'the posted draft is kept as «ملغى» after cancellation');
  });

  test('return_drafts carries the five delta-sync columns at runtime',
      () async {
    // دليلُ `sync_column_membership_guard_test` لهذا الجدول الخامّ.
    final cols = {
      for (final r
          in await db.customSelect('PRAGMA table_info(return_drafts)').get())
        r.data['name'] as String,
    };
    expect(
        cols,
        containsAll(const [
          'global_id',
          'last_modified_at',
          'deleted_at',
          'origin_client_id',
          'row_version',
        ]));
  });

  test('return_drafts rides every sync list', () {
    expect(DeltaPullService.pullTables, contains('return_drafts'));
    expect(DeltaPullService.deltaOnlyTables, contains('return_drafts'));
    expect(DeltaPullService.branchScopedPullTables, contains('return_drafts'));
    expect(AppDatabase.syncHardenedTablesForTest, contains('return_drafts'));
    expect(IdNamespaceService.namespacedTables, contains('return_drafts'));
  });

  test('approve permission backfill: roles that could create returns get it',
      () async {
    await db.syncAllPermissions();
    Future<int> permId(String code) async => (await (db.select(db.permissions)
              ..where((p) => p.code.equals(code)))
            .getSingle())
        .id;
    final role = await db.into(db.roles).insert(
          RolesCompanion.insert(name: 'مرتجعات', isSystemRole: const Value(false)),
        );
    final bystander = await db.into(db.roles).insert(
          RolesCompanion.insert(name: 'متفرّج', isSystemRole: const Value(false)),
        );
    await db.into(db.rolePermissions).insert(RolePermissionsCompanion.insert(
        roleId: role, permissionId: await permId(PermissionCodes.salesReturnView)));
    await db.customStatement(
        "DELETE FROM settings WHERE key = 'return_approve_backfill_done'");

    await db.backfillReturnApprovePermissionsOnce();

    Future<bool> has(int roleId, String code) async {
      final wanted = await permId(code);
      final grants = await (db.select(db.rolePermissions)
            ..where((rp) => rp.roleId.equals(roleId)))
          .get();
      return grants.any((rp) => rp.permissionId == wanted);
    }

    expect(await has(role, PermissionCodes.salesReturnApprove), isTrue);
    expect(await has(role, PermissionCodes.purchasesReturnApprove), isFalse);
    expect(await has(bystander, PermissionCodes.salesReturnApprove), isFalse);
  });
}

// AccountingService is only reached by cancelSalesReturn; the standalone
// processSalesReturn path posts through the DAO directly.
class _StubParties implements IPartiesRepository {
  @override
  dynamic noSuchMethod(Invocation inv) =>
      throw UnsupportedError('Stub: ${inv.memberName}');
}

class _StubProducts implements IProductRepository {
  @override
  dynamic noSuchMethod(Invocation inv) =>
      throw UnsupportedError('Stub: ${inv.memberName}');
}

class _StubInventory implements InventoryRepository {
  @override
  dynamic noSuchMethod(Invocation inv) =>
      throw UnsupportedError('Stub: ${inv.memberName}');
}

class _StubSettings implements ISettingsRepository {
  @override
  dynamic noSuchMethod(Invocation inv) =>
      throw UnsupportedError('Stub: ${inv.memberName}');
}

class _StubAudit implements IAuditRepository {
  @override
  dynamic noSuchMethod(Invocation inv) =>
      throw UnsupportedError('Stub: ${inv.memberName}');
}

class _StubTreasury implements ITreasuryRepository {
  @override
  Future<List<Map<String, dynamic>>> getSafeAccountsForReference(
          String referenceType, int referenceId) async =>
      [];
  @override
  dynamic noSuchMethod(Invocation inv) =>
      throw UnsupportedError('Stub: ${inv.memberName}');
}
