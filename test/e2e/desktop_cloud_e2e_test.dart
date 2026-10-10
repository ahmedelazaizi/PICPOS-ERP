// E2E سطح المكتب ↔ السحابة: خدمة المزامنة الحقيقية (CloudSyncService + CloudLinkApi)
// على قاعدة drift في الذاكرة ↔ خادم السحابة الحقيقي (عملية فرعية + Postgres)،
// وجهاز مندوب يتحدث مع الخادم عبر HTTP كما يفعل تطبيق المندوب.
// (الـ fixture _Fx والـ stubs في آخر الملف منسوخة من
// test/integration/cloud_sync_i3_test.dart دون تعديل ذلك الملف.)
//
// يُشغَّل: flutter test test/e2e من الجذر (يحتاج Docker Postgres على 55432 وdart في PATH).
import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:ural_erp/core/constants/app_constants.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/data/database/sync_interceptor.dart';
import 'package:ural_erp/data/mappers/product_mapper.dart';
import 'package:ural_erp/data/repositories/drift_accounting_repository.dart';
import 'package:ural_erp/data/repositories/returns_repository_impl.dart';
import 'package:ural_erp/data/repositories/sales_transaction_orchestrator.dart';
import 'package:ural_erp/domain/entities/cart_item_entity.dart';
import 'package:ural_erp/domain/entities/product_entity.dart';
import 'package:ural_erp/domain/repositories/audit_repository_interface.dart';
import 'package:ural_erp/domain/repositories/i_products_repository.dart';
import 'package:ural_erp/domain/repositories/inventory_repository.dart';
import 'package:ural_erp/domain/repositories/parties_repository.dart';
import 'package:ural_erp/domain/repositories/sales_repository.dart';
import 'package:ural_erp/domain/repositories/settings_repository.dart';
import 'package:ural_erp/domain/repositories/treasury_repository.dart';
import 'package:ural_erp/services/accounting_service.dart';
import 'package:ural_erp/services/cloud_sync/cloud_document_poster.dart';
import 'package:ural_erp/services/cloud_sync/cloud_link_api.dart';
import 'package:ural_erp/services/cloud_sync/cloud_sync_service.dart';
import 'package:ural_erp/services/invoice_integrity_service.dart';
import 'package:uuid/uuid.dart';
import 'support/e2e_cloud.dart';

const _uuid = Uuid();

/// يلفّ http.Client لعدّ الطلبات (للتأكد أن المزامنة تتحدث فعلًا مع الخادم).
class _CountingClient extends http.BaseClient {
  _CountingClient(this._inner);
  final http.Client _inner;
  final List<String> calls = [];
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    calls.add('${request.method} ${request.url.path}');
    return _inner.send(request);
  }
}

void main() {
  late E2eCloud cloud;
  late _Fx fx;
  late CloudSyncService sync;
  late CloudLinkApi api;
  late Map<String, String> link;
  late _CountingClient http0;

  setUpAll(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    cloud = await E2eCloud.start(pairLimit: 100);
  });
  tearDownAll(() => cloud.stop());

  setUp(() async {
    SyncInterceptor.instance = null;
    fx = await _Fx.seed();
    // ربط مكتب جديد لكل اختبار (الشركة التجريبية نفسها؛ المندوب/العميل بمعرّفات هذا المكتب).
    link = await cloud.desktopLink(cloud.companyA, name: 'desktop-e2e');
    http0 = _CountingClient(http.Client());
    api = CloudLinkApi(
        CloudLinkCredentials(
            baseUrl: cloud.url, linkId: link['x-desktop-link']!, secret: link['authorization']!.substring(7)),
        client: http0);
    sync = CloudSyncService(db: fx.db, api: api, accounting: fx.accounting, postingUserId: fx.userId);
  });
  tearDown(() => SyncInterceptor.instance = null);

  /// جهاز مندوب المكتب (المندوب المزروع في _Fx) مقترن بـ PIN ومسجّل الدخول.
  Future<({Map<String, String> h, String deviceId, Map<String, dynamic> boot})> repDevice() async {
    final repGid = (await (fx.db.select(fx.db.employees)).getSingle()).globalId!;
    final pairing = await api.pairingCode(repGid, pin: '2468');
    final deviceId = _uuid.v4();
    final pair = await cloud.call('POST', '/mobile/pair',
        body: {'code': pairing['code'], 'deviceId': deviceId, 'deviceName': 'desk-e2e'});
    expect(pair.status, 200, reason: '$pair');
    final dh = {'authorization': 'Bearer ${pair.json['deviceToken']}', 'x-device-id': deviceId};
    final login = await cloud.call('POST', '/mobile/login', headers: dh, body: {'pin': '2468'});
    expect(login.status, 200, reason: '$login');
    final h = {...dh, 'x-session-token': login.json['sessionToken'] as String};
    final boot = await cloud.call('GET', '/mobile/bootstrap', headers: h);
    expect(boot.status, 200, reason: '$boot');
    return (h: h, deviceId: deviceId, boot: boot.json);
  }

  String lease(Map<String, dynamic> boot, String t) {
    final x = (boot['leases'] as List).firstWhere((l) => l['docType'] == t);
    return '${x['prefix']}${x['nextNumber']}';
  }

  test('ربط الشركة ← دفع البيانات الرئيسية ← الجوال يرى بيانات المكتب ← مستندات الجوال تُرحَّل ← الرصيد يعود', () async {
    final first = await sync.runOnce(fullPush: true);
    expect(first.ok, isTrue, reason: first.error);
    expect(first.masterSkipped, isEmpty);
    expect(http0.calls, containsAll(['GET /desktop/documents/pending', 'POST /desktop/master']));

    final dev = await repDevice();
    final cust = ((dev.boot['customers'] as List).cast<Map>()).firstWhere((c) => c['name'] == 'Cust A');
    expect(cust['creditLimit'], 500.0);
    // الشركة تراكم منتجات اختبارات سابقة بنفس الاسم؛ نختار بمعرّف هذا المكتب.
    final waterGid = (await fx.db.getProductById(fx.waterId))!.globalId;
    final breadGid = (await fx.db.getProductById(fx.breadId))!.globalId;
    final prods = {for (final p in (dev.boot['products'] as List).cast<Map>()) if (p['globalId'] == waterGid) 'Water': p else if (p['globalId'] == breadGid) 'Bread': p};
    expect(prods.keys, containsAll(['Water', 'Bread']));
    expect(prods['Bread']!['taxExempt'], isTrue);
    expect(dev.boot['vanStock'], containsAll([
      {'productGlobalId': prods['Water']!['globalId'], 'quantity': 50.0},
      {'productGlobalId': prods['Bread']!['globalId'], 'quantity': 20.0},
    ]));
    final book = ((dev.boot['voucherBooks'] as List).single as Map);

    final saleGid = _uuid.v4();
    final collGid = _uuid.v4();
    final push = await cloud.call('POST', '/mobile/sync/push', headers: dev.h, body: {
      'documents': [
        {
          'kind': 'sales_invoice',
          'globalId': saleGid,
          'number': lease(dev.boot, 'sales_invoice'),
          'date': DateTime.now().toUtc().toIso8601String(),
          'customerGlobalId': cust['globalId'],
          'lines': [
            {'productGlobalId': prods['Water']!['globalId'], 'quantity': 4, 'unitPrice': 2.5},
            {'productGlobalId': prods['Bread']!['globalId'], 'quantity': 1, 'unitPrice': 1},
          ],
          'paid': 5,
        },
        {
          'kind': 'collection',
          'globalId': collGid,
          'customerGlobalId': cust['globalId'],
          'amount': 3,
          'bookGlobalId': book['globalId'],
          'bookNumber': 7,
        },
      ],
    });
    expect([for (final r in push.json['results'] as List) (r as Map)['status']], ['accepted', 'accepted'], reason: '$push');

    // المكتب يسحب ويرحّل: فاتورة مرحّلة بمعرّفها السحابي، قيود، مخزون، رصيد.
    final run = await sync.runOnce();
    expect(run.ok, isTrue, reason: run.error);
    expect(run.posted, 2);
    expect(run.conflicts, 0);
    for (final g in [saleGid, collGid]) {
      expect((await fx.db.cloudSyncDocument(g))?.status, 'posted', reason: g);
    }
    final inv = await (fx.db.select(fx.db.salesInvoices)..where((s) => s.globalId.equals(saleGid))).getSingle();
    expect(inv.total, 12.6);
    expect(inv.warehouseId, fx.vanId);
    expect((await fx.db.select(fx.db.journalEntries).get()), isNotEmpty);
    expect((await fx.db.getProductById(fx.waterId))!.currentStock, 46.0);
    expect((await fx.db.getPartyById(fx.customerId))!.balance, closeTo(12.6 - 5 - 3, 1e-9));

    // الخادم لم يعد يرى مستندات معلّقة، والرصيد المخدوم لا يُحتسب مرتين.
    expect(((await cloud.call('GET', '/desktop/documents/pending', headers: link)).json['documents'] as List), isEmpty);
    final boot2 = await cloud.call('GET', '/mobile/bootstrap', headers: dev.h);
    final c2 = ((boot2.json['customers'] as List).cast<Map>()).firstWhere((c) => c['name'] == 'Cust A');
    expect(c2['balance'], closeTo(12.6 - 5 - 3, 1e-9));

    // إعادة التشغيل لا ترحّل شيئًا مرتين.
    final again = await sync.runOnce();
    expect(again.posted, 0);
    expect(again.conflicts, 0);
    expect(await fx.db.select(fx.db.salesInvoices).get(), hasLength(1));
  });

  test('تعارض حقيقي: المكتب يرفض مستندًا قبله الخادم ← يظهر بسبب ويبقى معلّقًا ثم يُحلّ بإعادة المحاولة', () async {
    await sync.runOnce(fullPush: true);
    final dev = await repDevice();
    final cust = ((dev.boot['customers'] as List).cast<Map>()).firstWhere((c) => c['name'] == 'Cust A');
    final waterGid = (await fx.db.getProductById(fx.waterId))!.globalId;
    final water = ((dev.boot['products'] as List).cast<Map>()).firstWhere((p) => p['globalId'] == waterGid);

    // فاتورة ثم مرتجعها يصلان معًا: يُرحَّلان بالترتيب الصحيح في جولة واحدة.
    final saleGid = _uuid.v4();
    final sale = {
      'kind': 'sales_invoice',
      'globalId': saleGid,
      'number': lease(dev.boot, 'sales_invoice'),
      'date': DateTime.now().toUtc().toIso8601String(),
      'customerGlobalId': cust['globalId'],
      'lines': [
        {'productGlobalId': water['globalId'], 'quantity': 2, 'unitPrice': 2.5},
      ],
      'paid': 0,
    };
    final r1 = await cloud.call('POST', '/mobile/sync/push', headers: dev.h, body: {
      'documents': [sale],
    });
    expect(((r1.json['results'] as List).single as Map)['status'], 'accepted', reason: '$r1');
    final retGid = _uuid.v4();
    final r2 = await cloud.call('POST', '/mobile/sync/push', headers: dev.h, body: {
      'documents': [
        {
          'kind': 'sales_return',
          'globalId': retGid,
          'number': lease(dev.boot, 'sales_return'),
          'date': DateTime.now().toUtc().toIso8601String(),
          'originalInvoiceGlobalId': saleGid,
          'lines': [
            {'productGlobalId': water['globalId'], 'quantity': 1},
          ],
        },
      ],
    });
    expect(((r2.json['results'] as List).single as Map)['status'], 'accepted', reason: '$r2');

    // المكتب: الفاتورة تُرحَّل ثم المرتجع (نفس الجولة) — لا تعارض.
    final run = await sync.runOnce();
    expect(run.ok, isTrue, reason: run.error);
    expect(run.posted, 2, reason: '${run.toJson()}');
    expect(run.conflicts, 0);

    // مستند ثالث يُقبل في السحابة لكن المكتب يرفضه: بيع بتاريخ في سنة مالية غير موجودة.
    final oldGid = _uuid.v4();
    final old = {
      ...sale,
      'globalId': oldGid,
      'number': '${lease(dev.boot, 'sales_invoice').replaceAll(RegExp(r'\d+$'), '')}${int.parse(RegExp(r'\d+$').firstMatch(lease(dev.boot, 'sales_invoice'))!.group(0)!) + 1}',
      'date': '2001-03-01T09:00:00.000Z',
    };
    final r3 = await cloud.call('POST', '/mobile/sync/push', headers: dev.h, body: {
      'documents': [old],
    });
    expect(((r3.json['results'] as List).single as Map)['status'], 'accepted', reason: '$r3');
    final run2 = await sync.runOnce();
    expect(run2.ok, isTrue, reason: run2.error);
    expect(run2.conflicts, 1, reason: '${run2.toJson()}');
    final conflict = (await fx.db.cloudSyncDocument(oldGid))!;
    expect(conflict.status, 'conflict');
    expect(conflict.reason, contains('سنة مالية'), reason: 'السبب الحقيقي من المكتب (لا سنة مالية لتاريخ 2001)');
    expect(await fx.db.cloudSyncCounts(), (posted: 2, conflicts: 1));
    var pend = await cloud.call('GET', '/desktop/documents/pending', headers: link);
    var item = (pend.json['documents'] as List).cast<Map>().firstWhere((d) => d['globalId'] == oldGid);
    expect(item['lastDesktopError'], contains('سنة مالية'), reason: 'السبب يصل للسحابة ويبقى المستند معلّقًا');

    // إعادة التشغيل لا تُغيّر شيئًا (يتخطى التعارض المعروف).
    final run3 = await sync.runOnce();
    expect(run3.posted, 0);
    expect(run3.skippedConflicts, 1);

    // الحل: إنشاء السنة المالية ثم طلب إعادة المحاولة ← يُرحَّل ويخرج من الطابور.
    await fx.db.into(fx.db.fiscalYears).insert(FiscalYearsCompanion.insert(
          name: '2001',
          startDate: DateTime(2001, 1, 1),
          endDate: DateTime(2001, 12, 31),
          isClosed: const Value(false),
        ));
    await fx.db.requestCloudSyncRetry(oldGid);
    final run4 = await sync.runOnce();
    expect(run4.ok, isTrue, reason: run4.error);
    expect(run4.posted, 1, reason: '${run4.toJson()}');
    expect((await fx.db.cloudSyncDocument(oldGid))!.status, 'posted');
    expect(await fx.db.cloudSyncCounts(), (posted: 3, conflicts: 0));
    pend = await cloud.call('GET', '/desktop/documents/pending', headers: link);
    expect((pend.json['documents'] as List).where((d) => (d as Map)['globalId'] == oldGid), isEmpty);
  });
  test('إبطال جهاز المندوب من المكتب (CloudLinkApi) ← 401 device_revoked على الجوال', () async {
    await sync.runOnce(fullPush: true);
    final dev = await repDevice();
    final listed = await api.devices();
    expect(listed.map((d) => d['deviceId']), contains(dev.deviceId));
    await api.revokeDevice(dev.deviceId);
    final r = await cloud.call('GET', '/mobile/bootstrap', headers: dev.h);
    expect(r.status, 401);
    expect(r.error, 'device_revoked');
  });

  test('رابط مكتب مبطَل من الخادم ← runOnce يعيد خطأ نظيفًا (لا استثناء) ولا يمسّ بيانات المكتب المحلية', () async {
    final first = await sync.runOnce(fullPush: true);
    expect(first.ok, isTrue, reason: first.error);
    final revoke = await cloud.call('POST', '/admin/desktop-links/${link['x-desktop-link']}/revoke',
        headers: cloud.adminHeaders);
    expect(revoke.status, 200);
    final before = (await fx.db.select(fx.db.parties).get()).length;
    final r = await sync.runOnce();
    expect(r.ok, isFalse);
    expect(r.error, contains('desktop_link_revoked'));
    expect((await fx.db.select(fx.db.parties).get()).length, before);
  });

  test('رمز ربط مكتب خاطئ ← خطأ 401 واضح من runOnce', () async {
    final bad = CloudSyncService(
      db: fx.db,
      api: CloudLinkApi(CloudLinkCredentials(baseUrl: cloud.url, linkId: link['x-desktop-link']!, secret: 'nope')),
      accounting: fx.accounting,
      postingUserId: fx.userId,
    );
    final r = await bad.runOnce();
    expect(r.ok, isFalse);
    expect(r.error, isNotEmpty);
  });
}


/// A fresh desktop with one rep, van, custody safe, route customer, receipt
/// book and two products — identical in every database it is seeded into.
class _Fx {
  _Fx(this.db, this.accounting, this.userId, this.repId, this.vanId, this.safeId,
      this.customerId, this.waterId, this.breadId, this.bookId);
  final AppDatabase db;
  final AccountingService accounting;
  final int userId, repId, vanId, safeId, customerId, waterId, breadId, bookId;

  static Future<_Fx> seed() async {
    final db = AppDatabase.forTesting();
    await db.syncDefaultAccounts();
    if ((await db.select(db.fiscalYears).get()).isEmpty) {
      final now = DateTime.now();
      await db.into(db.fiscalYears).insert(FiscalYearsCompanion.insert(
            name: '${now.year}',
            startDate: DateTime(now.year, 1, 1),
            endDate: DateTime(now.year, 12, 31),
            isClosed: const Value(false),
          ));
    }
    await db.setSetting('tax_rate', '16');
    final accounting = AccountingService(DriftAccountingRepository(db), _StubParties(),
        _RealisticTreasury(db), _StubProducts(), _StubInventory(), _StubSettings(),
        _StubAudit());
    final roleId = await db.into(db.roles).insert(
        RolesCompanion.insert(name: 'i3_poster', isSystemRole: const Value(false)));
    final userId = await db.createUser(
        username: 'i3_poster', password: 'pw123456', displayName: 'I3 poster', roleId: roleId);
    final repId = await db.into(db.employees).insert(EmployeesCompanion.insert(name: 'Rep A'));
    final vanId = await db.into(db.warehouses).insert(WarehousesCompanion.insert(name: 'Van A'));
    final safeId = await db.into(db.safes).insert(SafesCompanion.insert(name: 'Custody A'));
    final customerId = await db.into(db.parties).insert(PartiesCompanion.insert(
        name: 'Cust A', isCustomer: const Value(true), creditLimit: const Value(500)));
    final routeId = await db.saveDistributionRoute(
        name: 'Route A', repEmployeeId: repId, visitDays: const [1, 3]);
    await db.assignCustomerToRoute(
        customerId: customerId, routeId: routeId, at: DateTime(2020));
    await db.saveRepResources(employeeId: repId, vanWarehouseId: vanId, custodySafeId: safeId);
    final bookId = await db.createVoucherBook(
        type: 'receipt', rangeFrom: 1, rangeTo: 50, prefix: 'Q-', holderEmployeeId: repId);
    final waterId = await db.insertProduct(ProductsCompanion.insert(
      code: 'W-1',
      name: 'Water',
      salePrice: const Value(2.5),
      costPrice: const Value(1.0),
      taxRate: const Value(16),
      trackInventory: const Value(true),
    ));
    final breadId = await db.insertProduct(ProductsCompanion.insert(
      code: 'B-1',
      name: 'Bread',
      salePrice: const Value(1.0),
      costPrice: const Value(0.4),
      trackInventory: const Value(true),
    ));
    await db.setProductTaxExempt(breadId, true);
    await db.adjustStock(
        productId: waterId, warehouseId: vanId, quantity: 50, type: 'purchase', unitCost: 1);
    await db.adjustStock(
        productId: breadId, warehouseId: vanId, quantity: 20, type: 'purchase', unitCost: 0.4);
    return _Fx(db, accounting, userId, repId, vanId, safeId, customerId, waterId, breadId, bookId);
  }

  CloudSyncService service(http.Client client) => CloudSyncService(
        db: db,
        api: CloudLinkApi(
            const CloudLinkCredentials(baseUrl: 'http://fake', linkId: 'l', secret: 's'),
            client: client),
        accounting: accounting,
        postingUserId: userId,
      );

  /// The same sale typed into the desktop sales screen.
  Future<int> enterSale({required double paid}) async {
    final r = await SalesTransactionOrchestrator(db, accounting).completeSalesTransaction(
      SaleRequest(
        items: [
          CartItemEntity(
              productId: waterId, productName: 'Water', productCode: 'W-1',
              quantity: 4, unitPrice: 2.5, taxRate: 16),
          CartItemEntity(
              productId: breadId, productName: 'Bread', productCode: 'B-1',
              quantity: 1, unitPrice: 1, taxRate: 0),
        ],
        customerId: customerId,
        warehouseId: vanId,
        userId: userId,
        paymentMethod: 'cash',
        paidAmount: paid,
        cashAmount: paid,
        cashSafeId: safeId,
        taxPercent: 16,
      ),
    );
    expect(r.isSuccess, isTrue, reason: r.errorMessage);
    return r.invoiceId!;
  }

  Future<void> enterReturn(int invoiceId) async {
    final inv =
        await (db.select(db.salesInvoices)..where((s) => s.id.equals(invoiceId))).getSingle();
    final items = await db.getSalesInvoiceItems(invoiceId);
    final water = items.firstWhere((i) => i.productId == waterId);
    final ok = await ReturnsRepositoryImpl(db, accounting).processSalesReturn(
      invoice: inv,
      returnQuantities: {water.id: 1},
      productCache: <int, ProductEntity>{
        for (final i in items) i.productId: (await db.getProductById(i.productId))!.toEntity(),
      },
      userId: userId,
      userName: 'I3 poster',
    );
    expect(ok, isTrue);
  }

  Future<void> enterCollection(double amount, {required int leaf}) async {
    await db.validateVoucherBookLeaf(bookId, leaf);
    final id = await db.createReceiptVoucher(
        amount: amount, category: 'customer_payment', partyId: customerId, safeId: safeId,
        userId: userId);
    await db.assignVoucherBookLeaf(txnId: id, bookId: bookId, number: leaf);
  }
}

class _StubParties implements IPartiesRepository {
  @override
  dynamic noSuchMethod(Invocation inv) {
    if (inv.memberName == #getPartyById) return Future<Null>.value(null);
    throw UnsupportedError('parties repo not used here');
  }
}

/// Behavioural copy of `TreasuryRepositoryImpl.getSafeAccountsForReference`
/// (same as `sales_revenue_account_c2_test.dart`).
class _RealisticTreasury implements ITreasuryRepository {
  _RealisticTreasury(this.db);
  final AppDatabase db;

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
      final safe = await (db.select(db.safes)..where((s) => s.id.equals(r.safeId))).getSingle();
      final accountId = safe.linkedAccountId ??
          (await db.getAccountByCode(safe.safeType == 'bank' ? '1112' : '1111'))?.id;
      if (accountId != null) {
        out.add({'accountId': accountId, 'amount': r.amount, 'safeName': safe.name});
      }
    }
    return out;
  }

  @override
  dynamic noSuchMethod(Invocation inv) => throw UnsupportedError('treasury repo: ${inv.memberName}');
}

class _StubProducts implements IProductRepository {
  @override
  dynamic noSuchMethod(Invocation inv) => throw UnsupportedError('products not used here');
}

class _StubInventory implements InventoryRepository {
  @override
  dynamic noSuchMethod(Invocation inv) => throw UnsupportedError('inventory not used here');
}

class _StubSettings implements ISettingsRepository {
  @override
  dynamic noSuchMethod(Invocation inv) => throw UnsupportedError('settings not used here');
}

class _StubAudit implements IAuditRepository {
  @override
  dynamic noSuchMethod(Invocation inv) => throw UnsupportedError('audit not used here');
}
