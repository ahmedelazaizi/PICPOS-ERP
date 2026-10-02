// المرحلة و — نموذجُ التوزيع (بندا المالك ١٢ و١٨).
//
// • العميلُ على مسارٍ واحدٍ في كلّ لحظة، والانتقالُ يغلق الصفَّ السابق
//   ويُبقي التاريخ.
// • مندوبُ العميل مشتقٌّ من مندوب مساره، وتغييرُ مندوب المسار يُسجَّل.
// • الفاتورةُ والمرتجعُ وسندُ القبض والتحصيلُ تُختَم بالمندوب والمسار لحظةَ
//   الإنشاء، وإعادةُ التوزيع لا تعيد كتابةَ الختم.
// • التحميلُ/التفريغُ تحويلُ مخزونٍ، والتسليمُ تحويلُ خزائنَ بقيده.
// • أرقامُ التقارير تطابق المستندات، والجداولُ تعبر المزامنة.

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/data/database/extensions/distribution_dao.dart';
import 'package:ural_erp/domain/models/distribution_model.dart';
import 'package:ural_erp/services/delta_pull_service.dart';

const _newTables = [
  'distribution_areas',
  'route_customers',
  'route_rep_history',
  'rep_resources',
];

void main() {
  late AppDatabase db;
  late int userId;
  late int warehouseId;
  late int productId;

  setUp(() async {
    db = AppDatabase.forTesting();
    final roleId = await db.into(db.roles).insert(
          RolesCompanion.insert(name: 'مندوب', isSystemRole: const Value(false)),
        );
    userId = await db.createUser(
      username: 'phase_f_user',
      password: 'test',
      displayName: 'Phase F',
      roleId: roleId,
    );
    warehouseId = (await db.getDefaultWarehouse())!.id;
    productId = await db.insertProduct(ProductsCompanion.insert(
      code: 'PF-1',
      name: 'منتج التوزيع',
      salePrice: const Value(100.0),
      costPrice: const Value(60.0),
      currentStock: const Value(0.0),
      trackInventory: const Value(true),
    ));
    await db.adjustStock(
      productId: productId,
      warehouseId: warehouseId,
      quantity: 50,
      type: 'in',
      notes: 'seed',
    );
    if ((await db.select(db.fiscalYears).get()).isEmpty) {
      final now = DateTime.now();
      await db.into(db.fiscalYears).insert(FiscalYearsCompanion.insert(
            name: '${now.year}',
            startDate: DateTime(now.year, 1, 1),
            endDate: DateTime(now.year, 12, 31),
            isClosed: const Value(false),
          ));
    }
  });

  tearDown(() => db.close());

  Future<int> employee(String name) => db
      .into(db.employees)
      .insert(EmployeesCompanion.insert(name: name));

  Future<int> customer(String name) => db.into(db.parties).insert(
      PartiesCompanion.insert(name: name, isCustomer: const Value(true)));

  Future<int> sale(int? customerId,
      {double total = 300, double paid = 0, String saleType = 'default'}) {
    return db.createSalesInvoice(
      invoiceNumber: 'PF-${DateTime.now().microsecondsSinceEpoch}',
      warehouseId: warehouseId,
      userId: userId,
      subtotal: total,
      discount: 0,
      tax: 0,
      total: total,
      paid: paid,
      paymentMethod: paid >= total ? 'cash' : 'credit',
      customerId: customerId,
      saleType: saleType,
      items: [
        SalesInvoiceItemsCompanion.insert(
          invoiceId: 0,
          productId: productId,
          quantity: total / 100,
          unitPrice: 100,
          total: total,
          costPrice: const Value(60.0),
        ),
      ],
    );
  }

  Future<int> cashSafe(String name, {int? accountId}) =>
      db.into(db.safes).insert(SafesCompanion.insert(
            name: name,
            balance: const Value(0),
            safeType: const Value('cash'),
            linkedAccountId: Value(accountId),
          ));

  group('المسار وعملاؤه', () {
    test('العميلُ على مسارٍ واحد: النقلُ يغلق السابقَ ويُبقي التاريخ',
        () async {
      final a = await db.saveDistributionRoute(name: 'مسار أ');
      final b = await db.saveDistributionRoute(name: 'مسار ب');
      final c = await customer('عميل');
      await db.assignCustomerToRoute(customerId: c, routeId: a);
      await db.assignCustomerToRoute(customerId: c, routeId: b);

      final open = await db.customSelect(
        'SELECT route_id FROM route_customers WHERE customer_id = ? '
        'AND effective_to IS NULL',
        variables: [Variable<int>(c)],
      ).get();
      expect(open.single.data['route_id'], b,
          reason: 'صفٌّ مفتوحٌ واحدٌ فقط — على المسار الجديد');
      final history = await db.customerRouteHistory(c);
      expect(history.map((h) => h.routeId), [a, b]);
      expect(history.first.effectiveTo, isNotNull);
      expect(await db.listRouteCustomers(a), isEmpty);
      expect((await db.listRouteCustomers(b)).single.customerId, c);

      // الإسنادُ لنفس المسار لا يفتح صفّاً جديداً.
      await db.assignCustomerToRoute(customerId: c, routeId: b);
      expect(await db.customerRouteHistory(c), hasLength(2));

      await db.removeCustomerFromRoute(c);
      expect(await db.currentRouteOfCustomer(c), isNull);
    });

    test('الترتيبُ اليدويّ يُحفَظ', () async {
      final r = await db.saveDistributionRoute(name: 'مسار');
      final c1 = await customer('١');
      final c2 = await customer('٢');
      final c3 = await customer('٣');
      for (final c in [c1, c2, c3]) {
        await db.assignCustomerToRoute(customerId: c, routeId: r);
      }
      expect((await db.listRouteCustomers(r)).map((x) => x.customerId),
          [c1, c2, c3]);
      await db.reorderRouteCustomers(r, [c3, c1, c2]);
      expect((await db.listRouteCustomers(r)).map((x) => x.customerId),
          [c3, c1, c2]);
    });

    test('مندوبُ العميل مشتقٌّ من مساره، وتغييرُ المندوب يُسجَّل', () async {
      final x = await employee('س');
      final y = await employee('ص');
      final area = await db.saveDistributionArea(name: 'الشرق', code: 'E');
      final r = await db.saveDistributionRoute(
          name: 'مسار', repEmployeeId: x, areaId: area, visitDays: [5, 1, 3]);
      final c = await customer('عميل');
      await db.assignCustomerToRoute(customerId: c, routeId: r);

      var info = (await db.currentRouteOfCustomer(c))!;
      expect(info.repEmployeeId, x);
      expect(info.areaName, 'الشرق');
      final route = (await db.listDistributionRoutes()).single;
      expect(route.visitDays, [1, 3, 5]);
      expect(route.customerCount, 1);

      await db.setRouteRep(r, y);
      info = (await db.currentRouteOfCustomer(c))!;
      expect(info.repEmployeeId, y, reason: 'المندوبُ يتبع المسار');
      final history = await db.routeRepHistory(r);
      expect(history.map((h) => h.repEmployeeId), [x, y]);
      expect(history.first.effectiveTo, isNotNull);
      expect(history.last.effectiveTo, isNull);

      final partyCols = {
        for (final row
            in await db.customSelect('PRAGMA table_info(parties)').get())
          row.data['name'] as String,
      };
      expect(partyCols.where((n) => n.contains('rep')), isEmpty,
          reason: 'المندوبُ لا يُخزَّن على الطرف');
    });

    test('منطقةٌ مستعمَلةٌ لا تُحذَف', () async {
      final area = await db.saveDistributionArea(name: 'الغرب');
      await db.saveDistributionRoute(name: 'مسار', areaId: area);
      await expectLater(db.deleteDistributionArea(area),
          throwsA(isA<DistributionException>()));
      await expectLater(db.saveDistributionArea(name: 'الغرب'),
          throwsA(isA<DistributionException>()));
    });
  });

  group('الختمُ لحظةَ الإنشاء', () {
    test('الفاتورةُ والمرتجعُ وسندُ القبض والتحصيلُ تُختَم — والنقلُ لا يمسّ '
        'الماضي', () async {
      final x = await employee('س');
      final y = await employee('ص');
      final a = await db.saveDistributionRoute(name: 'أ', repEmployeeId: x);
      final b = await db.saveDistributionRoute(name: 'ب', repEmployeeId: y);
      final c = await customer('عميل');
      await db.assignCustomerToRoute(customerId: c, routeId: a);

      final inv = await sale(c);
      final ret = await sale(c, total: 100, saleType: 'return');
      final safe = await cashSafe('الصندوق');
      final rcpt = await db.createReceiptVoucher(
          amount: 50, category: 'customer_payment', partyId: c, safeId: safe);
      final col = await db.createCollection(SalesRepCollectionsCompanion.insert(
          salesRepId: x, customerId: c, amount: 20));

      for (final (table, id) in [
        ('sales_invoices', inv),
        ('sales_invoices', ret),
        ('safe_transactions', rcpt),
        ('sales_rep_collections', col),
      ]) {
        final s = await db.getDocumentRepStamp(table, id);
        expect((s.repEmployeeId, s.routeId), (x, a), reason: '$table#$id');
      }

      // إعادةُ التوزيع: العميلُ إلى ب، ومندوبُ أ يتغيّر.
      await db.assignCustomerToRoute(customerId: c, routeId: b);
      await db.setRouteRep(a, y);
      final old = await db.getDocumentRepStamp('sales_invoices', inv);
      expect((old.repEmployeeId, old.routeId), (x, a),
          reason: 'الختمُ تاريخٌ لا يُعاد حسابُه');
      final fresh = await db.getDocumentRepStamp(
          'sales_invoices', await sale(c));
      expect((fresh.repEmployeeId, fresh.routeId), (y, b));
    });

    test('عميلُ نقطة البيع العابر (بلا عميل) بلا ختم', () async {
      final id = await sale(null, paid: 300);
      final s = await db.getDocumentRepStamp('sales_invoices', id);
      expect(s.isEmpty, isTrue);
    });

    test('ختمُ العميل المرسَل يُحترَم ولا يُستبدَل', () async {
      final x = await employee('س');
      final r = await db.saveDistributionRoute(name: 'أ');
      final c = await customer('عميل');
      final id = await db.createSalesInvoice(
        invoiceNumber: 'PF-CL-1',
        warehouseId: warehouseId,
        userId: userId,
        subtotal: 100,
        discount: 0,
        tax: 0,
        total: 100,
        paid: 0,
        paymentMethod: 'credit',
        customerId: c,
        repStamp: RepStamp(repEmployeeId: x, routeId: r),
        items: [
          SalesInvoiceItemsCompanion.insert(
            invoiceId: 0,
            productId: productId,
            quantity: 1,
            unitPrice: 100,
            total: 100,
          ),
        ],
      );
      final s = await db.getDocumentRepStamp('sales_invoices', id);
      expect((s.repEmployeeId, s.routeId), (x, r));
      // الاستراتيجيّةُ لا تطمس ختماً قائماً.
      await db.applyRepStampJson(
          'sales_invoices', id, {'repEmployeeId': 999, 'routeId': 999});
      final again = await db.getDocumentRepStamp('sales_invoices', id);
      expect(again.repEmployeeId, x);
      expect(await db.repStampJson('sales_invoices', id),
          {'repEmployeeId': x, 'routeId': r});
    });
  });

  group('موارد المندوب', () {
    test('التحميلُ والتفريغُ يحرّكان المخزون', () async {
      final x = await employee('س');
      final van = await db.into(db.warehouses).insert(
          WarehousesCompanion.insert(name: 'سيارة س'));
      await db.saveRepResources(employeeId: x, vanWarehouseId: van);

      Future<double> qty(int wh) async =>
          (await (db.select(db.inventoryBalances)
                    ..where((b) =>
                        b.warehouseId.equals(wh) &
                        b.productId.equals(productId)))
                  .getSingleOrNull())
              ?.quantity ??
          0;

      await db.repLoadVan(
          repEmployeeId: x,
          fromWarehouseId: warehouseId,
          items: [
            {'productId': productId, 'quantity': 8},
          ]);
      expect(await qty(van), 8);
      expect(await qty(warehouseId), 42);
      await db.repUnloadVan(
          repEmployeeId: x,
          toWarehouseId: warehouseId,
          items: [
            {'productId': productId, 'quantity': 3},
          ]);
      expect(await qty(van), 5);
      expect(await qty(warehouseId), 45);
      final van5 = await db.vanStock(repEmployeeId: x);
      expect(van5.single.quantity, 5);

      // مخزنُ سيارةٍ لمندوبٍ واحد.
      final other = await employee('ص');
      await expectLater(
          db.saveRepResources(employeeId: other, vanWarehouseId: van),
          throwsA(isA<DistributionException>()));
    });

    test('التسليمُ ينقل الرصيدَ ويقيّد بين حسابَي الخزنتين', () async {
      final x = await employee('س');
      Future<int> account(String code) =>
          db.into(db.accounts).insert(AccountsCompanion.insert(
                code: code,
                name: 'حساب $code',
                accountType: 'asset',
                accountNature: const Value('detail'),
                isSystem: const Value(false),
              ));
      final custodyAcc = await account('1191');
      final mainAcc = await account('1192');
      final custody = await cashSafe('عهدة س', accountId: custodyAcc);
      final main = await cashSafe('الرئيسة', accountId: mainAcc);
      await db.adjustSafeBalance(custody, 500);
      await db.saveRepResources(employeeId: x, custodySafeId: custody);

      final out = await db.handoverCustodyCash(
          repEmployeeId: x, toSafeId: main, amount: 300);
      Future<double> bal(int id) async =>
          (await (db.select(db.safes)..where((s) => s.id.equals(id)))
                  .getSingle())
              .balance;
      expect(await bal(custody), 200);
      expect(await bal(main), 300);

      final je = await (db.select(db.journalEntries)
            ..where((j) =>
                j.referenceType.equals(kRepHandoverCategory) &
                j.referenceId.equals(out)))
          .getSingle();
      final lines = await (db.select(db.journalEntryLines)
            ..where((l) => l.entryId.equals(je.id)))
          .get();
      expect(lines.firstWhere((l) => l.accountId == mainAcc).debit, 300);
      expect(lines.firstWhere((l) => l.accountId == custodyAcc).credit, 300);

      await expectLater(
          db.handoverCustodyCash(repEmployeeId: x, toSafeId: main, amount: 900),
          throwsA(isA<DistributionException>()),
          reason: 'لا تسليمَ فوق رصيد العهدة');
    });
  });

  group('التقارير', () {
    test('ملخّصُ المندوب وتفصيلُه يطابقان المستندات المختومة', () async {
      final x = await employee('س');
      final r = await db.saveDistributionRoute(name: 'أ', repEmployeeId: x);
      final c = await customer('عميل');
      await db.assignCustomerToRoute(customerId: c, routeId: r);
      final custody = await cashSafe('عهدة');
      final main = await cashSafe('الرئيسة');
      await db.saveRepResources(employeeId: x, custodySafeId: custody);

      await sale(c, total: 300);
      await sale(c, total: 200, paid: 200);
      await sale(c, total: 100, saleType: 'return');
      await db.createReceiptVoucher(
          amount: 150,
          category: 'customer_payment',
          partyId: c,
          safeId: custody);
      await db.createCollection(SalesRepCollectionsCompanion.insert(
          salesRepId: x, customerId: c, amount: 50));
      await db.handoverCustodyCash(
          repEmployeeId: x, toSafeId: main, amount: 80);
      await sale(null, total: 100, paid: 100); // عابرٌ — خارجَ التقرير

      final from = DateTime.now().subtract(const Duration(days: 1));
      final to = DateTime.now().add(const Duration(days: 1));
      final summary = (await db.repSalesSummary(from: from, to: to)).single;
      expect(summary.repEmployeeId, x);
      expect(summary.invoiceCount, 2);
      expect(summary.netSales, 500);
      expect(summary.returns, 100);
      expect(summary.collections, 150);
      expect(summary.fieldCollections, 50);
      expect(summary.handedOver, 80);

      final detail = await db.repTransactionDetail(from: from, to: to);
      final credit = detail.firstWhere(
          (d) => d.kind == 'invoice' && d.amount == 300);
      expect(credit.remaining, 300);
      expect(credit.routeName, 'أ');
      expect(credit.customerName, 'عميل');

      final coverage = await db.routeCoverage(routeId: r);
      expect(coverage.single.customerId, c);
      expect(coverage.single.lastInvoiceDate, isNotNull);
    });

    // E-fix ٤أ — صفّا مرتجعِ جهاز العميل (ذاكرةُ `SRET-<gid>` ونظيرُه من
    // الخادم بلا `globalId`) يُعَدّان مرتجعاً واحداً.
    test('🔴 مرتجعُ جهاز العميل يُعَدّ مرّةً واحدة', () async {
      final x = await employee('ع');
      final r = await db.saveDistributionRoute(name: 'ب', repEmployeeId: x);
      final c = await customer('عميل المرتجع');
      await db.assignCustomerToRoute(customerId: c, routeId: r);
      final originalId = await sale(c, total: 400);
      final original = await (db.select(db.salesInvoices)
            ..where((s) => s.id.equals(originalId)))
          .getSingle();
      final from = DateTime.now().subtract(const Duration(days: 1));
      final to = DateTime.now().add(const Duration(days: 1));
      Future<double> returns() async =>
          (await db.repSalesSummary(from: from, to: to)).single.returns;

      // ‏١) صفُّ الذاكرة كما يكتبه `returns_repository_impl` في وضع العميل.
      Future<void> cacheRow(String gid, double total) async {
        await db.insertSalesInvoiceWithoutStock(
          invoice: SalesInvoicesCompanion.insert(
            invoiceNumber: 'SRET-${gid.substring(0, 8)}',
            warehouseId: warehouseId,
            userId: userId,
            invoiceDate: DateTime.now(),
            customerId: Value(c),
            subtotal: Value(total),
            total: Value(total),
            saleType: const Value('return'),
            globalId: Value(gid),
            notes: Value(localReturnLinkNote(originalId,
                originalGlobalId: original.globalId)),
          ),
          items: const [],
        );
        final row = await (db.select(db.salesInvoices)
              ..where((s) => s.globalId.equals(gid)))
            .getSingle();
        await db.stampDocumentRep('sales_invoices', row.id, c);
      }

      await cacheRow('aaaaaaaa-0001', 150);
      expect(await returns(), 150, reason: 'قبل وصول النظير: الذاكرةُ وحدَها');

      // ‏٢) نظيرُ الخادم كما تُدرجه `SalesSyncStrategy`: رقمُ الخادم، بلا
      //    `globalId`، ورابطُ الأصل نفسُه، ومختومٌ بالمندوب.
      final echo = await db.insertSalesInvoiceWithoutStock(
        invoice: SalesInvoicesCompanion.insert(
          invoiceNumber: 'SRV-RET-77',
          warehouseId: warehouseId,
          userId: userId,
          invoiceDate: DateTime.now(),
          customerId: Value(c),
          subtotal: const Value(150),
          total: const Value(150),
          saleType: const Value('return'),
          notes: Value(localReturnLinkNote(9001,
              originalGlobalId: original.globalId)),
        ),
        items: const [],
      );
      await db.stampDocumentRep('sales_invoices', echo, c);
      expect(await returns(), 150, reason: 'المرتجعُ نفسُه لا يُعَدّ مرّتين');

      // ومرتجعٌ ثانٍ مستقلٌّ (مبلغٌ آخر) يُعَدّ.
      await cacheRow('bbbbbbbb-0002', 60);
      expect(await returns(), 210);
    });
  });

  group('المزامنة', () {
    test('الجداولُ في قوائم السحب، وأعمدةُ الدلتا عليها', () async {
      for (final t in _newTables) {
        expect(DeltaPullService.pullTables, contains(t));
        expect(DeltaPullService.branchScopedPullTables, contains(t));
        expect(DeltaPullService.deltaOnlyTables, contains(t));
        expect(AppDatabase.syncHardenedTablesForTest, contains(t));
        final cols = {
          for (final r in await db.customSelect('PRAGMA table_info($t)').get())
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
            ]),
            reason: '$t بلا أعمدة الدلتا لا يُسحَب');
      }
      const pull = DeltaPullService.pullTables;
      expect(pull.indexOf('distribution_areas'),
          lessThan(pull.indexOf('sales_routes')));
      expect(pull.indexOf('sales_routes'),
          lessThan(pull.indexOf('route_customers')));
      for (final t in kRepStampedTables) {
        final cols = {
          for (final r in await db.customSelect('PRAGMA table_info($t)').get())
            r.data['name'] as String,
        };
        expect(cols, containsAll(const ['rep_employee_id', 'route_id']));
      }
      final routeCols = {
        for (final r
            in await db.customSelect('PRAGMA table_info(sales_routes)').get())
          r.data['name'] as String,
      };
      expect(routeCols, containsAll(const ['area_id', 'visit_days']));
    });

    test('الصفوفُ تعبر بـ`SELECT *` إلى جهازٍ آخر', () async {
      final x = await employee('س');
      final area = await db.saveDistributionArea(name: 'الشرق');
      final r = await db.saveDistributionRoute(
          name: 'أ', repEmployeeId: x, areaId: area, visitDays: [2]);
      final c = await customer('عميل');
      await db.assignCustomerToRoute(customerId: c, routeId: r);
      await db.saveRepResources(employeeId: x, vanWarehouseId: warehouseId);

      final other = AppDatabase.forTesting();
      addTearDown(other.close);
      await other.customSelect('SELECT 1').get();
      for (final table in [
        'employees',
        'parties',
        'distribution_areas',
        'sales_routes',
        'route_customers',
        'route_rep_history',
        'rep_resources',
      ]) {
        final rows = await db.customSelect('SELECT * FROM $table').get();
        for (final row in rows) {
          final cols = row.data.keys.toList();
          await other.customStatement(
            'INSERT OR REPLACE INTO $table (${cols.join(', ')}) '
            'VALUES (${List.filled(cols.length, '?').join(', ')})',
            [for (final col in cols) row.data[col]],
          );
        }
      }
      final info = (await other.currentRouteOfCustomer(c))!;
      expect(info.routeId, r);
      expect(info.repEmployeeId, x);
      expect(info.areaName, 'الشرق');
      expect((await other.listDistributionRoutes()).single.visitDays, [2]);
      expect((await other.routeRepHistory(r)).single.repEmployeeId, x);
      expect((await other.getRepResources(x))!.vanWarehouseId, warehouseId);
    });
  });
}
