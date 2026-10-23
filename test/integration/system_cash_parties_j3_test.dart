// J3 — «عميل نقدي» / «مورد نقدي» النظاميّان (قرارُ المالك).
//
// Proves on a real database:
//  * both system parties are seeded on startup, flagged, unique, linked to a
//    sub-account under the AR (1121) / AP (2111) control account, and an
//    existing cash party is ADOPTED (never one that is both customer and
//    supplier) instead of a duplicate being created;
//  * they cannot be deleted / deactivated / flipped; the name stays editable
//    and `trData` shows the English name while it is untouched;
//  * the cash customer is the explicit exception to one route per customer:
//    it is never put on a route and is pushed to the cloud for every rep;
//  * the one-time customer name is stored on the invoice and PRINTED instead
//    of «عميل نقدي» (text runs of the rendered PDF);
//  * «حفظ كعميل دائم» creates a cash-only customer at the END of the route;
//  * the I-3 poster posts a cloud `customer` document idempotently, and a
//    cloud cash-customer sale keeps its one-time name and rep/route stamp.

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/core/i18n/locale_provider.dart';
import 'package:picpos_erp/core/i18n/tr.dart';
import 'package:picpos_erp/data/database/daos/parties_dao_ext.dart' as ext;
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/data/database/sync_interceptor.dart';
import 'package:picpos_erp/data/repositories/drift_accounting_repository.dart';
import 'package:picpos_erp/data/repositories/sales_repository_impl.dart';
import 'package:picpos_erp/data/repositories/sales_transaction_orchestrator.dart';
import 'package:picpos_erp/domain/entities/cart_item_entity.dart';
import 'package:picpos_erp/domain/models/distribution_model.dart';
import 'package:picpos_erp/domain/repositories/audit_repository_interface.dart';
import 'package:picpos_erp/domain/repositories/i_products_repository.dart';
import 'package:picpos_erp/domain/repositories/inventory_repository.dart';
import 'package:picpos_erp/domain/repositories/parties_repository.dart';
import 'package:picpos_erp/domain/repositories/sales_repository.dart';
import 'package:picpos_erp/domain/repositories/settings_repository.dart';
import 'package:picpos_erp/domain/repositories/treasury_repository.dart';
import 'package:picpos_erp/services/accounting_service.dart';
import 'package:picpos_erp/services/cloud_sync/cloud_document_poster.dart';
import 'package:picpos_erp/services/templated_invoice_service.dart';
import 'package:uuid/uuid.dart';

import '../helpers/arabic_pdf_text.dart';
import '../helpers/pdf_probe.dart';

const _uuid = Uuid();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SyncInterceptor.instance = null);
  tearDown(() => SyncInterceptor.instance = null);

  Future<Party> party(AppDatabase db, int id) async =>
      (await (db.select(db.parties)..where((p) => p.id.equals(id))).getSingle());

  Future<Account?> parentOf(AppDatabase db, Party p) async {
    final acc = await (db.select(db.accounts)
          ..where((a) => a.id.equals(p.accountId!)))
        .getSingle();
    return (db.select(db.accounts)..where((a) => a.id.equals(acc.parentId!)))
        .getSingleOrNull();
  }

  group('system parties', () {
    late AppDatabase db;
    setUp(() => db = AppDatabase.forTesting());
    tearDown(() => db.close());

    test('seeded on startup: one per role, flagged, linked to 1121 / 2111',
        () async {
      final cashC = await db.systemPartyId(kSystemRoleCashCustomer);
      final cashS = await db.systemPartyId(kSystemRoleCashSupplier);
      expect(cashC, isNotNull);
      expect(cashS, isNotNull);

      final c = await party(db, cashC!);
      expect(c.name, kCashCustomerDefaultName);
      expect(c.code, 'CUST-CASH');
      expect(c.isCustomer && !c.isSupplier, isTrue,
          reason: 'a party that is both is NOT the cash party');
      expect(c.creditLimit, 0);
      expect((await parentOf(db, c))!.code, '1121');

      final s = await party(db, cashS!);
      expect(s.name, kCashSupplierDefaultName);
      expect(s.code, 'SUP-CASH');
      expect(s.isSupplier && !s.isCustomer, isTrue);
      expect((await parentOf(db, s))!.code, '2111');

      // Idempotent: another startup-ensure creates nothing.
      final before = (await db.select(db.parties).get()).length;
      await db.ensureSystemCashParties();
      expect((await db.select(db.parties).get()).length, before);
      expect(await db.systemPartyRoles(),
          {cashC: kSystemRoleCashCustomer, cashS: kSystemRoleCashSupplier});

      // Unique: no second row may hold a role.
      final other = await db.into(db.parties).insert(
          PartiesCompanion.insert(name: 'Other', isCustomer: const Value(true)));
      await expectLater(
        db.customStatement(
            "UPDATE parties SET system_role = 'cash_customer' WHERE id = $other"),
        throwsA(anything),
      );
      // The party code sequence is untouched: the next customer is CUST-00001.
      expect(await db.getNextPartyCode(isCustomer: true, isSupplier: false),
          'CUST-00001');
    });

    test('not deletable, not deactivatable, role kept; name editable', () async {
      final cashC = (await db.systemPartyId(kSystemRoleCashCustomer))!;
      final cashS = (await db.systemPartyId(kSystemRoleCashSupplier))!;
      await expectLater(
          PartyDao(db).deleteParty(cashC), throwsA(isA<Exception>()));
      await expectLater(
          ext.PartiesDao(db).deleteParty(cashS), throwsA(isA<Exception>()));

      final c = await party(db, cashC);
      await PartyDao(db).updateParty(c.copyWith(
          name: 'زبون نقدي', isActive: false, isSupplier: true));
      final after = await party(db, cashC);
      expect(after.name, 'زبون نقدي', reason: 'the name is cosmetic — editable');
      expect(after.isActive, isTrue);
      expect(after.isSupplier, isFalse);
      expect(await db.systemRoleOfParty(cashC), kSystemRoleCashCustomer);
    });

    test('an existing cash party is adopted — never one that is both',
        () async {
      final seeded = (await db.systemPartyId(kSystemRoleCashCustomer))!;
      // Simulate an install from before v190: no flag, an old «نقدي» party.
      await db.customStatement(
          "UPDATE parties SET system_role = NULL, name = 'Old', global_id = NULL "
          'WHERE id = $seeded');
      final both = await db.into(db.parties).insert(PartiesCompanion.insert(
          name: kCashCustomerDefaultName,
          isCustomer: const Value(true),
          isSupplier: const Value(true)));
      final legacy = await db.into(db.parties).insert(PartiesCompanion.insert(
          name: 'نقدي', isCustomer: const Value(true)));
      await db.ensureSystemCashParties();
      final adopted = await db.systemPartyId(kSystemRoleCashCustomer);
      expect(adopted, legacy, reason: 'history keeps its references');
      expect(adopted, isNot(both));
    });

    test('trData shows the English name while untouched', () async {
      final catalog = (jsonDecode(
              File('assets/i18n/en.json').readAsStringSync()) as Map)
          .cast<String, String>();
      I18nCatalog.setCatalog(catalog);
      I18nCatalog.setLocale(englishUserLocale);
      addTearDown(() {
        I18nCatalog.setCatalog(const {});
        I18nCatalog.setLocale(defaultUserLocale);
      });
      expect(trData(kCashCustomerDefaultName), 'Cash Customer');
      expect(trData(kCashSupplierDefaultName), 'Cash Supplier');
      expect(trData('زبون نقدي'), 'زبون نقدي', reason: 'an edited name is data');
    });
  });

  group('route rule exception, one-time name, save as permanent, I-3', () {
    late _Fx f;
    setUp(() async => f = await _Fx.seed());
    tearDown(() => f.db.close());

    test('the cash customer is on every route — never assigned to one',
        () async {
      await expectLater(
        f.db.assignCustomerToRoute(customerId: f.cashId, routeId: f.routeId),
        throwsA(isA<DistributionException>()),
      );
      expect(await f.db.currentRouteOfCustomer(f.cashId), isNull);
      final stamp = await f.db.resolveRepStamp(f.cashId);
      expect(stamp.isEmpty, isTrue,
          reason: 'desktop sales to it carry no route; field sales carry the '
              "rep's stamp (see the I-3 test below)");
    });

    test('one-time name: stored on the invoice and printed instead of «عميل نقدي»',
        () async {
      await f.db.openShift(f.userId, 0);
      final r = await SalesTransactionOrchestrator(f.db, f.accounting)
          .completeSalesTransaction(SaleRequest(
        items: [f.water(2)],
        customerId: f.cashId,
        warehouseId: f.vanId,
        userId: f.userId,
        paymentMethod: 'cash',
        paidAmount: 5.8,
        cashAmount: 5.8,
        cashSafeId: f.safeId,
        taxPercent: 16,
        adhocCustomerName: 'سليمان',
        adhocCustomerPhone: '0791234567',
      ));
      expect(r.isSuccess, isTrue, reason: r.errorMessage);
      final inv = await (f.db.select(f.db.salesInvoices)
            ..where((s) => s.id.equals(r.invoiceId!)))
          .getSingle();
      expect(inv.customerId, f.cashId);
      expect(inv.adhocCustomerName, 'سليمان');
      expect(inv.adhocCustomerPhone, '0791234567');

      final pd = (await SalesRepositoryImpl(f.db, f.accounting)
          .getSalesPrintData(r.invoiceId!))!;
      expect(pd.customerName, 'سليمان');
      expect(pd.customerPhone, '0791234567');

      await f.db.seedDefaultTemplates();
      final out = await TemplatedInvoiceService.printWithTemplate(
        db: f.db,
        debugBuildOnly: true,
        type: 'a4',
        category: 'invoice',
        documentType: 'sales_invoice',
        invoiceNumber: pd.invoiceNumber,
        date: pd.date,
        customerName: pd.customerName ?? pd.adhocCustomerName,
        customerPhone: pd.customerPhone,
        customerAddress: pd.customerAddress,
        items: [
          for (final i in pd.items)
            {'name': i.name, 'quantity': i.quantity, 'price': i.price, 'total': i.total},
        ],
        subtotal: pd.subtotal,
        discount: pd.discount,
        tax: pd.tax,
        deliveryFee: 0.0,
        total: pd.total,
        paid: pd.paid,
        companyName: 'PicPos',
        companyAddress: '',
        companyPhone: '',
        companyTaxId: '',
        locale: 'ar',
      );
      final text = deshapeArabic(
          probePdf(out.bytes).allTexts.map((t) => t.text).join(' '));
      expect(text, contains(deshapeArabic('سليمان')));
      expect(text, contains('0791234567'));
      // («نقدي» alone still prints as the payment method.)
      expect(text, isNot(contains(deshapeArabic(kCashCustomerDefaultName))),
          reason: 'the one-time name replaces «عميل نقدي»');
    });

    test('«حفظ كعميل دائم»: cash-only customer at the END of the route',
        () async {
      final id = await f.db.createPermanentCustomerFromCashSale(
        name: ' بقالة جديدة ',
        phone: '0790000009',
        address: 'شارع ١',
        routeId: f.routeId,
      );
      final p = await party(f.db, id);
      expect(p.name, 'بقالة جديدة');
      expect(p.creditLimit, 0, reason: 'cash only until management sets one');
      expect(p.isCustomer, isTrue);
      expect((await parentOf(f.db, p))!.code, '1121');
      final rows = await f.db.listRouteCustomers(f.routeId);
      expect(rows.last.customerId, id, reason: 'appended at the end');
      expect(rows.last.sequence, rows.length);
      expect(rows.length, 2);
    });

    test('I-3 poster: cloud customer document (idempotent) and a cash sale '
        'with its one-time name', () async {
      final poster = CloudDocumentPoster(f.db, f.accounting,
          postingUserId: f.userId);
      final gid = _uuid.v4();
      final rcGid = _uuid.v4();
      final doc = {
        'kind': 'customer',
        'globalId': gid,
        'name': 'محل الوادي',
        'phone': '0795555555',
        'routeGlobalId': f.routeGid,
        'routeCustomerGlobalId': rcGid,
      };
      final first = await poster.post(doc);
      final again = await poster.post(doc);
      expect(again.desktopRef, first.desktopRef, reason: 'a lost ack never duplicates');
      final created = await (f.db.select(f.db.parties)
            ..where((p) => p.globalId.equals(gid)))
          .get();
      expect(created, hasLength(1));
      expect(created.single.creditLimit, 0);
      final rc = await f.db.customSelect(
        'SELECT route_id, sequence, global_id FROM route_customers '
        'WHERE customer_id = ? AND effective_to IS NULL',
        variables: [Variable<int>(created.single.id)],
      ).getSingle();
      expect(rc.data['route_id'], f.routeId);
      expect(rc.data['global_id'], rcGid, reason: 'same identity as the cloud row');
      expect(rc.data['sequence'], 2);

      final cashGid = (await party(f.db, f.cashId)).globalId!;
      final sale = await poster.post({
        'kind': 'sales_invoice',
        'globalId': _uuid.v4(),
        'number': 'VS-100000',
        'date': DateTime.now().toUtc().toIso8601String(),
        'customerGlobalId': cashGid,
        'customerName': 'أبو خالد',
        'customerPhone': '0797777777',
        'repEmployeeGlobalId': f.repGid,
        'routeGlobalId': f.routeGid,
        'warehouseGlobalId': f.vanGid,
        'safeGlobalId': f.safeGid,
        'lines': [
          {'productGlobalId': f.waterGid, 'quantity': 4, 'unitPrice': 2.5},
        ],
        'total': 11.6,
        'paid': 11.6,
      });
      final inv = await (f.db.select(f.db.salesInvoices)
            ..where((s) => s.id.equals(int.parse(sale.desktopRef))))
          .getSingle();
      expect(inv.customerId, f.cashId);
      expect(inv.adhocCustomerName, 'أبو خالد');
      expect(inv.adhocCustomerPhone, '0797777777');
      final stamp = await f.db.getDocumentRepStamp('sales_invoices', inv.id);
      expect(stamp.repEmployeeId, f.repId,
          reason: 'cash-customer sales group per rep/route via the stamp');
      expect(stamp.routeId, f.routeId);
    });
  });
}

/// A desktop with one rep, route (one customer), van, custody safe, product.
class _Fx {
  _Fx(this.db, this.accounting, this.userId, this.repId, this.routeId,
      this.vanId, this.safeId, this.waterId, this.cashId);
  final AppDatabase db;
  final AccountingService accounting;
  final int userId, repId, routeId, vanId, safeId, waterId, cashId;
  late String repGid, routeGid, vanGid, safeGid, waterGid;

  CartItemEntity water(double qty) => CartItemEntity(
      productId: waterId, productName: 'Water', productCode: 'W-1',
      quantity: qty, unitPrice: 2.5, taxRate: 16);

  static Future<_Fx> seed() async {
    final db = AppDatabase.forTesting();
    await db.syncDefaultAccounts();
    await db.setSetting('tax_rate', '16');
    final accounting = AccountingService(DriftAccountingRepository(db),
        _StubParties(), _StubTreasury(), _StubProducts(), _StubInventory(),
        _StubSettings(), _StubAudit());
    final roleId = await db.into(db.roles).insert(
        RolesCompanion.insert(name: 'j3_cashier', isSystemRole: const Value(false)));
    final userId = await db.createUser(
        username: 'j3_cashier', password: 'pw123456', displayName: 'J3 cashier',
        roleId: roleId);
    final repId =
        await db.into(db.employees).insert(EmployeesCompanion.insert(name: 'Rep'));
    final vanId =
        await db.into(db.warehouses).insert(WarehousesCompanion.insert(name: 'Van'));
    final safeId =
        await db.into(db.safes).insert(SafesCompanion.insert(name: 'Custody'));
    final customerId = await db.into(db.parties).insert(PartiesCompanion.insert(
        name: 'Cust A', isCustomer: const Value(true)));
    final routeId = await db.saveDistributionRoute(
        name: 'Route A', repEmployeeId: repId, visitDays: const [1]);
    await db.assignCustomerToRoute(customerId: customerId, routeId: routeId);
    final waterId = await db.insertProduct(ProductsCompanion.insert(
      code: 'W-1',
      name: 'Water',
      salePrice: const Value(2.5),
      costPrice: const Value(1.0),
      taxRate: const Value(16),
      trackInventory: const Value(true),
    ));
    await db.adjustStock(
        productId: waterId, warehouseId: vanId, quantity: 50, type: 'purchase', unitCost: 1);
    final f = _Fx(db, accounting, userId, repId, routeId, vanId, safeId, waterId,
        (await db.systemPartyId(kSystemRoleCashCustomer))!);
    Future<String> gid(String table, int id) async {
      final g = _uuid.v4();
      await db.customStatement(
          "UPDATE $table SET global_id = '$g' WHERE id = $id AND global_id IS NULL");
      final row = await db.customSelect('SELECT global_id FROM $table WHERE id = $id').getSingle();
      return row.data['global_id'] as String;
    }

    f
      ..repGid = await gid('employees', repId)
      ..routeGid = await gid('sales_routes', routeId)
      ..vanGid = await gid('warehouses', vanId)
      ..safeGid = await gid('safes', safeId)
      ..waterGid = await gid('products', waterId);
    return f;
  }
}

class _StubParties implements IPartiesRepository {
  @override
  dynamic noSuchMethod(Invocation inv) {
    if (inv.memberName == #getPartyById) return Future<Null>.value(null);
    throw UnsupportedError('parties repo not used here');
  }
}

class _StubTreasury implements ITreasuryRepository {
  @override
  Future<List<Map<String, dynamic>>> getSafeAccountsForReference(
          String referenceType, int referenceId) async =>
      const [];

  @override
  dynamic noSuchMethod(Invocation inv) =>
      throw UnsupportedError('treasury repo: ${inv.memberName}');
}

class _StubProducts implements IProductRepository {
  @override
  dynamic noSuchMethod(Invocation inv) => throw UnsupportedError('products');
}

class _StubInventory implements InventoryRepository {
  @override
  dynamic noSuchMethod(Invocation inv) => throw UnsupportedError('inventory');
}

class _StubSettings implements ISettingsRepository {
  @override
  dynamic noSuchMethod(Invocation inv) => throw UnsupportedError('settings');
}

class _StubAudit implements IAuditRepository {
  @override
  dynamic noSuchMethod(Invocation inv) => throw UnsupportedError('audit');
}
