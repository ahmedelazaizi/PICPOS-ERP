// K — owner decisions for the van app, desktop side:
//  * a cloud `expense` document (rep expense paid from his custody safe with a
//    leaf of his PAYMENT voucher book) posts through the existing payment
//    voucher path: JE Dr the category's expense account / Cr the custody
//    safe's account, the book leaf consumed, the rep/route stamp, idempotent;
//  * a refused expense becomes a conflict with its reason;
//  * the van GPS stamp lands on route_visits (lat/lng + JSON) and on the
//    voucher row (`field_geo`);
//  * the master push carries the expense categories, the payment book, the
//    custody balance and the over-custody policy.

import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/data/database/sync_interceptor.dart';
import 'package:picpos_erp/data/repositories/drift_accounting_repository.dart';
import 'package:picpos_erp/domain/repositories/audit_repository_interface.dart';
import 'package:picpos_erp/domain/repositories/i_products_repository.dart';
import 'package:picpos_erp/domain/repositories/inventory_repository.dart';
import 'package:picpos_erp/domain/repositories/parties_repository.dart';
import 'package:picpos_erp/domain/repositories/settings_repository.dart';
import 'package:picpos_erp/domain/repositories/treasury_repository.dart';
import 'package:picpos_erp/services/accounting_service.dart';
import 'package:picpos_erp/services/cloud_sync/cloud_document_poster.dart';
import 'package:picpos_erp/services/cloud_sync/cloud_link_api.dart';
import 'package:picpos_erp/services/cloud_sync/cloud_master_exporter.dart';
import 'package:picpos_erp/services/cloud_sync/cloud_sync_service.dart';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

void main() {
  setUp(() => SyncInterceptor.instance = null);
  tearDown(() => SyncInterceptor.instance = null);

  test('expense posts a payment voucher: Dr expense / Cr custody, leaf consumed, '
      'rep stamp, geo; re-post is idempotent', () async {
    final f = await _Fx.seed();
    final poster = CloudDocumentPoster(f.db, f.accounting, postingUserId: f.userId);
    final doc = f.expense(12.5, leaf: 1, geo: {
      'status': 'ok',
      'lat': 31.95,
      'lng': 35.91,
      'accuracy': 9.0,
      'at': '2026-05-01T08:00:00.000Z',
    });
    final safeBefore = (await f.db.getSafeById(f.safeId))!.balance;

    final ref = await poster.post(doc);
    final again = await poster.post(doc);
    expect(again.desktopRef, ref.desktopRef);

    final rows = await (f.db.select(f.db.safeTransactions)
          ..where((t) => t.globalId.equals(doc['globalId'] as String)))
        .get();
    expect(rows, hasLength(1));
    final row = rows.single;
    expect(row.transactionType, 'payment');
    expect(row.safeId, f.safeId);
    expect(row.amount, 12.5);
    expect(row.voucherNumber, ref.desktopNumber);
    expect((await f.db.getSafeById(f.safeId))!.balance, closeTo(safeBefore - 12.5, 1e-9));

    final raw = (await f.db.customSelect(
      'SELECT book_id, book_number, rep_employee_id, route_id, field_geo '
      'FROM safe_transactions WHERE id = ?',
      variables: [Variable<int>(row.id)],
    ).getSingle())
        .data;
    expect(raw['book_id'], f.payBookId);
    expect(raw['book_number'], 1);
    expect(raw['rep_employee_id'], f.repId);
    expect(raw['route_id'], f.routeId);
    expect((jsonDecode(raw['field_geo'] as String) as Map)['lat'], 31.95);
    expect(fieldGeoMapsUrl(raw['field_geo']),
        'https://www.google.com/maps/search/?api=1&query=31.95,35.91');
    expect((await f.db.getVoucherBook(f.payBookId))!.nextNumber, 2);

    // Journal entry: Dr the category account (614) / Cr the custody safe.
    final tb = await _trialBalance(f.db);
    expect(tb['614'], closeTo(12.5, 1e-9));
    final safe = (await f.db.getSafeById(f.safeId))!;
    final safeCode = safe.linkedAccountId == null
        ? '1111'
        : (await f.db.getAccountById(safe.linkedAccountId!))!.code;
    expect(tb[safeCode], closeTo(-12.5, 1e-9));
    expect(tb.values.fold<double>(0, (a, b) => a + b), closeTo(0, 1e-9));
  });

  test('refused expense is a conflict with its reason; visit GPS is stored', () async {
    final f = await _Fx.seed();
    final cloud = _FakeCloud();
    final ok = f.expense(5, leaf: 1);
    final used = f.expense(6, leaf: 1); // same leaf → refused by the book rule
    final unknownCategory = {...f.expense(4, leaf: 2), 'categoryGlobalId': _uuid.v4()};
    final visit = {
      'kind': 'visit',
      'globalId': _uuid.v4(),
      'date': DateTime.now().toUtc().toIso8601String(),
      'customerGlobalId': f.customerGid,
      'repEmployeeGlobalId': f.repGid,
      'routeGlobalId': f.routeGid,
      'outcome': 'visited',
      'latitude': 30.1,
      'longitude': 31.2,
      'geo': {'status': 'ok', 'lat': 30.1, 'lng': 31.2, 'accuracy': 5.0},
    };
    final noFix = {
      ...visit,
      'globalId': _uuid.v4(),
      'latitude': null,
      'longitude': null,
      'geo': {'status': 'denied'},
    };
    cloud.pending.addAll([ok, used, unknownCategory, visit, noFix]);
    final sync = f.service(cloud.client);

    final r = await sync.runOnce();
    expect(r.posted, 3);
    expect(r.conflicts, 2);
    expect(cloud.failedAcks[used['globalId']], startsWith('voucher_book_leaf_rejected'));
    expect(cloud.failedAcks[unknownCategory['globalId']], startsWith('expense_category_not_found'));
    final conflicts = await f.db.listCloudSyncConflicts();
    expect(conflicts.map((c) => c.globalId).toSet(),
        {used['globalId'], unknownCategory['globalId']});

    // Second run: posted docs are re-acknowledged, never re-posted.
    cloud.postedAcks.clear();
    final r2 = await sync.runOnce();
    expect(r2.posted, 0);
    expect(r2.reAcked, 3);
    expect(
        (await (f.db.select(f.db.safeTransactions)
                  ..where((t) => t.globalId.equals(ok['globalId'] as String)))
                .get())
            .length,
        1);

    final v = (await f.db.customSelect(
      'SELECT latitude, longitude, field_geo, status FROM route_visits WHERE global_id = ?',
      variables: [Variable<String>(visit['globalId'] as String)],
    ).getSingle())
        .data;
    expect(v['latitude'], 30.1);
    expect(v['longitude'], 31.2);
    expect((jsonDecode(v['field_geo'] as String) as Map)['accuracy'], 5.0);
    expect(v['status'], 'completed');
    final nf = (await f.db.customSelect(
      'SELECT latitude, field_geo FROM route_visits WHERE global_id = ?',
      variables: [Variable<String>(noFix['globalId'] as String)],
    ).getSingle())
        .data;
    expect(nf['latitude'], isNull);
    expect(jsonDecode(nf['field_geo'] as String), {'status': 'denied'});
  });

  test('master push carries expense categories, payment book, custody balance, policy',
      () async {
    final f = await _Fx.seed();
    await f.db.setSetting(kCloudExpenseOverCustodySetting, 'reject');
    final master = await CloudMasterExporter(f.db).build();
    final cats = (master['expenseCategories'] as List).cast<Map>();
    expect(cats.map((c) => c['name']), containsAll(['وقود', 'أخرى']));
    expect(cats.every((c) => c['globalId'] is String), isTrue);
    expect(cats.first.containsKey('accountCode'), isFalse);
    final books = (master['voucherBooks'] as List).cast<Map>();
    expect(books.map((b) => b['bookType']).toSet(), {'receipt', 'payment'});
    final safes = (master['safes'] as List).cast<Map>();
    expect(safes.single['balance'], (await f.db.getSafeById(f.safeId))!.balance);
    expect((master['company'] as Map)['expenseOverCustody'], 'reject');
  });
}

Future<Map<String, double>> _trialBalance(AppDatabase db) async {
  final codes = {for (final x in await db.select(db.accounts).get()) x.id: x.code};
  final out = <String, double>{};
  for (final l in await db.select(db.journalEntryLines).get()) {
    final k = codes[l.accountId]!;
    out[k] = double.parse(((out[k] ?? 0) + l.debit - l.credit).toStringAsFixed(4));
  }
  out.removeWhere((_, v) => v.abs() < 1e-9);
  return out;
}

/// One rep with a route customer, custody safe (opening cash 100) and a
/// receipt + a payment voucher book.
class _Fx {
  _Fx(this.db, this.accounting, this.userId, this.repId, this.routeId, this.safeId,
      this.payBookId, this.repGid, this.routeGid, this.safeGid, this.payBookGid,
      this.customerGid, this.fuelGid);
  final AppDatabase db;
  final AccountingService accounting;
  final int userId, repId, routeId, safeId, payBookId;
  final String repGid, routeGid, safeGid, payBookGid, customerGid, fuelGid;

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
    final accounting = AccountingService(DriftAccountingRepository(db), _StubParties(),
        _StubTreasury(), _StubProducts(), _StubInventory(), _StubSettings(), _StubAudit());
    final roleId = await db.into(db.roles).insert(
        RolesCompanion.insert(name: 'k_poster', isSystemRole: const Value(false)));
    final userId = await db.createUser(
        username: 'k_poster', password: 'pw123456', displayName: 'K poster', roleId: roleId);
    final repGid = _uuid.v4(), safeGid = _uuid.v4(), customerGid = _uuid.v4();
    final repId = await db.into(db.employees).insert(
        EmployeesCompanion.insert(name: 'Rep K', globalId: Value(repGid)));
    final vanId = await db.into(db.warehouses).insert(WarehousesCompanion.insert(name: 'Van K'));
    final safeId = await db.into(db.safes).insert(SafesCompanion.insert(
        name: 'Custody K', balance: const Value(100), globalId: Value(safeGid)));
    final customerId = await db.into(db.parties).insert(PartiesCompanion.insert(
        name: 'Cust K', isCustomer: const Value(true), globalId: Value(customerGid)));
    final routeId =
        await db.saveDistributionRoute(name: 'Route K', repEmployeeId: repId, visitDays: const [1]);
    await db.assignCustomerToRoute(customerId: customerId, routeId: routeId, at: DateTime(2020));
    await db.saveRepResources(employeeId: repId, vanWarehouseId: vanId, custodySafeId: safeId);
    await db.createVoucherBook(
        type: 'receipt', rangeFrom: 1, rangeTo: 50, prefix: 'Q-', holderEmployeeId: repId);
    final payBookId = await db.createVoucherBook(
        type: 'payment', rangeFrom: 1, rangeTo: 50, prefix: 'P-', holderEmployeeId: repId);
    Future<String> gidOf(String table, int id) async => (await db.customSelect(
          'SELECT global_id FROM $table WHERE id = ?',
          variables: [Variable<int>(id)],
        ).getSingle())
            .data['global_id'] as String;
    final fuel = (await db.listFieldExpenseCategories()).firstWhere((c) => c.name == 'وقود');
    expect(fuel.accountCode, '614');
    return _Fx(db, accounting, userId, repId, routeId, safeId, payBookId, repGid,
        await gidOf('sales_routes', routeId), safeGid, await gidOf('voucher_books', payBookId),
        customerGid, fuel.globalId!);
  }

  Map<String, Object?> expense(double amount, {required int leaf, Map<String, Object?>? geo}) => {
        'kind': 'expense',
        'globalId': _uuid.v4(),
        'number': 'P-$leaf',
        'date': DateTime.now().toUtc().toIso8601String(),
        'repEmployeeGlobalId': repGid,
        'routeGlobalId': routeGid,
        'safeGlobalId': safeGid,
        'amount': amount,
        'bookGlobalId': payBookGid,
        'bookNumber': leaf,
        'categoryGlobalId': fuelGid,
        'categoryName': 'وقود',
        'note': 'محطة',
        'overCustody': false,
        'geo': ?geo,
      };

  CloudSyncService service(http.Client client) => CloudSyncService(
        db: db,
        api: CloudLinkApi(
            const CloudLinkCredentials(baseUrl: 'http://fake', linkId: 'l', secret: 's'),
            client: client),
        accounting: accounting,
        postingUserId: userId,
      );
}

/// In-memory cloud speaking the `/desktop/*` contract.
class _FakeCloud {
  final List<Map<String, Object?>> pending = [];
  final Map<String, String?> postedAcks = {};
  final Map<String, String> failedAcks = {};

  http.Client get client => MockClient((req) async {
        http.Response json(Object o) =>
            http.Response(jsonEncode(o), 200, headers: {'content-type': 'application/json'});
        switch ('${req.method} ${req.url.path}') {
          case 'GET /desktop/ping':
            return json({'company': {'globalId': 'c', 'name': 'Fake'}, 'pending': {}});
          case 'GET /desktop/documents/pending':
            return json({
              'documents': [
                for (final d in pending)
                  if (!postedAcks.containsKey(d['globalId'])) d,
              ],
            });
          case 'POST /desktop/documents/ack':
            final results = ((jsonDecode(req.body) as Map)['results'] as List).cast<Map>();
            for (final r in results) {
              if (r['status'] == 'posted') {
                postedAcks[r['globalId'] as String] = r['desktopNumber'] as String?;
              } else {
                failedAcks[r['globalId'] as String] = r['reason'] as String;
              }
            }
            return json({'results': [for (final r in results) {'globalId': r['globalId'], 'status': 'ok'}]});
          case 'POST /desktop/master':
            return json({'applied': {}, 'skipped': []});
        }
        return http.Response('{"error":"not_found"}', 404);
      });
}

class _StubParties implements IPartiesRepository {
  @override
  dynamic noSuchMethod(Invocation inv) => throw UnsupportedError('parties not used here');
}

class _StubTreasury implements ITreasuryRepository {
  @override
  dynamic noSuchMethod(Invocation inv) => throw UnsupportedError('treasury not used here');
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
