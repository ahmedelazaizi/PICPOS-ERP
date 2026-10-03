import 'package:drift/drift.dart';

import '../../core/constants/app_constants.dart';
import '../../core/utils/uuid_v7.dart';
import '../../data/database/database.dart';
import 'cloud_expense_categories_export.dart';

/// Builds the master-data batch the desktop pushes to the cloud
/// (`POST /desktop/master`, I-3). References travel as global ids; rows
/// without one get a fresh UUID first (the desktop owns master data).
///
/// * Incremental by `last_modified_at` ([since]; `null` = full push):
///   products and price lists (with their full item set), route-customer
///   history rows.
/// * Always sent (small, and their values change without a reliable
///   timestamp): the reps' scope — employees, rep resources, van warehouses
///   and custody safes, areas, routes, open route customers with their
///   current **balance** and credit limit, receipt voucher books held by
///   reps, and the **van stock** (with its products).
class CloudMasterExporter {
  CloudMasterExporter(this.db);
  final AppDatabase db;

  Future<String> _ensureGid(String table, int id, String? gid) async {
    if (gid != null && gid.isNotEmpty) return gid;
    final fresh = UuidV7.generate();
    await db.customUpdate(
      'UPDATE $table SET global_id = ? WHERE id = ? AND global_id IS NULL',
      variables: [Variable<String>(fresh), Variable<int>(id)],
    );
    final row = await db.customSelect(
      'SELECT global_id FROM $table WHERE id = ?',
      variables: [Variable<int>(id)],
    ).getSingle();
    return row.data['global_id'] as String;
  }

  static int? _int(Object? v) => v is num ? v.toInt() : null;

  static String? _isoDay(Object? epochSeconds) {
    final s = _int(epochSeconds);
    if (s == null) return null;
    final d = DateTime.fromMillisecondsSinceEpoch(s * 1000);
    return '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  static const _weekdays = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];

  static String? _visitDays(Object? csv) {
    if (csv is! String || csv.trim().isEmpty) return null;
    final days = [
      for (final p in csv.split(','))
        if (int.tryParse(p.trim()) case final d? when d >= 1 && d <= 7)
          _weekdays[d - 1],
    ];
    return days.isEmpty ? null : days.join(',');
  }

  Future<Map<String, Object?>> build({DateTime? since}) async {
    final sinceSec =
        since == null ? null : since.millisecondsSinceEpoch ~/ 1000;

    // ── distribution scope (raw tables, v185) ──
    final repRes = (await db.customSelect(
      'SELECT * FROM rep_resources WHERE deleted_at IS NULL ORDER BY id',
    ).get())
        .map((r) => r.data)
        .toList();
    final routes = await db.select(db.salesRoutes).get();
    final routeExtra = {
      for (final r in await db
          .customSelect('SELECT id, area_id, visit_days FROM sales_routes')
          .get())
        (r.data['id'] as num).toInt(): r.data,
    };
    final todaySec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final routeCustomers = (await db.customSelect(
      'SELECT * FROM route_customers WHERE deleted_at IS NULL AND '
      '(effective_to IS NULL OR effective_to >= ?'
      '${sinceSec == null ? ' OR 1 = 1' : ' OR last_modified_at > ?'}) ORDER BY id',
      variables: [
        Variable<int>(todaySec - 86400),
        if (sinceSec != null) Variable<int>(sinceSec),
      ],
    ).get())
        .map((r) => r.data)
        .toList();
    final books = (await db.customSelect(
      // K-1: payment books too (rep expense vouchers from the custody safe).
      "SELECT * FROM voucher_books WHERE deleted_at IS NULL AND book_type IN ('receipt', 'payment') "
      'AND holder_employee_id IS NOT NULL ORDER BY id',
    ).get())
        .map((r) => r.data)
        .toList();
    final areas = (await db.customSelect(
      'SELECT * FROM distribution_areas ORDER BY id',
    ).get())
        .map((r) => r.data)
        .toList();

    // ── employees in the reps' scope ──
    final repIds = <int>{
      for (final r in routes)
        if (r.salesRepId != null) r.salesRepId!,
      for (final r in repRes) (r['employee_id'] as num).toInt(),
      for (final b in books)
        if (_int(b['holder_employee_id']) != null) _int(b['holder_employee_id'])!,
    };
    final employees = repIds.isEmpty
        ? <Employee>[]
        : await (db.select(db.employees)..where((e) => e.id.isIn(repIds))).get();
    final employeeGid = <int, String>{};
    final employeesJson = <Map<String, Object?>>[];
    for (final e in employees) {
      final g = await _ensureGid('employees', e.id, e.globalId);
      employeeGid[e.id] = g;
      employeesJson.add({
        'globalId': g,
        'name': e.name,
        'phone': e.phone,
        'isActive': e.isActive,
        'deleted': e.deletedAt != null,
      });
    }

    // ── van warehouses / custody safes ──
    final vanIds = {
      for (final r in repRes)
        if (_int(r['van_warehouse_id']) != null) _int(r['van_warehouse_id'])!,
    };
    final safeIds = {
      for (final r in repRes)
        if (_int(r['custody_safe_id']) != null) _int(r['custody_safe_id'])!,
    };
    final warehouseGid = <int, String>{};
    final warehousesJson = <Map<String, Object?>>[];
    if (vanIds.isNotEmpty) {
      for (final w in await (db.select(db.warehouses)
            ..where((w) => w.id.isIn(vanIds)))
          .get()) {
        final g = await _ensureGid('warehouses', w.id, w.globalId);
        warehouseGid[w.id] = g;
        warehousesJson.add({'globalId': g, 'name': w.name, 'type': 'van'});
      }
    }
    final safeGid = <int, String>{};
    final safesJson = <Map<String, Object?>>[];
    if (safeIds.isNotEmpty) {
      for (final s
          in await (db.select(db.safes)..where((s) => s.id.isIn(safeIds))).get()) {
        final g = await _ensureGid('safes', s.id, s.globalId);
        safeGid[s.id] = g;
        // K-1: the ledger balance feeds the cloud's over-custody check.
        safesJson.add({'globalId': g, 'name': s.name, 'balance': s.balance});
      }
    }

    // ── customers on routes (balance + credit limit, every push) ──
    final customerIds = {
      for (final rc in routeCustomers) (rc['customer_id'] as num).toInt(),
    };
    // J3 — the system cash customer is on EVERY route: always pushed, with
    // its role, so the cloud serves it to every rep.
    final cashCustomerId = await db.systemPartyId(kSystemRoleCashCustomer);
    if (cashCustomerId != null) customerIds.add(cashCustomerId);
    final partyGid = <int, String>{};
    final partiesJson = <Map<String, Object?>>[];
    if (customerIds.isNotEmpty) {
      for (final p in await (db.select(db.parties)
            ..where((p) => p.id.isIn(customerIds)))
          .get()) {
        final g = await _ensureGid('parties', p.id, p.globalId);
        partyGid[p.id] = g;
        partiesJson.add({
          'globalId': g,
          'name': p.name,
          'phone': p.phone,
          'balance': p.balance,
          'creditLimit': p.creditLimit,
          'priceLevel': p.priceLevel == 'default' ? null : p.priceLevel,
          'isCustomer': p.isCustomer,
          'deleted': p.deletedAt != null || !p.isActive,
          'systemRole': p.id == cashCustomerId ? kSystemRoleCashCustomer : null,
        });
      }
    }

    // ── van stock (+ the products it references) ──
    final stock = vanIds.isEmpty
        ? <InventoryBalance>[]
        : await (db.select(db.inventoryBalances)
              ..where((b) => b.warehouseId.isIn(vanIds)))
            .get();
    final productQuery = db.select(db.products)
      ..where((p) {
        final stockIds = stock.map((b) => b.productId).toSet();
        final changed = since == null
            ? const Constant(true)
            : p.lastModifiedAt.isBiggerThanValue(since);
        return stockIds.isEmpty ? changed : (changed | p.id.isIn(stockIds));
      });
    final products = await productQuery.get();
    final exempt =
        await db.getTaxExemptProductIds(products.map((p) => p.id).toList());
    final units = {
      for (final u in await db.select(db.units).get()) u.id: u.name,
    };
    final productGid = <int, String>{};
    final productsJson = <Map<String, Object?>>[];
    for (final p in products) {
      final g = await _ensureGid('products', p.id, p.globalId);
      productGid[p.id] = g;
      productsJson.add({
        'globalId': g,
        'name': p.name,
        'barcode': p.barcode,
        'unitName': p.unitId == null ? null : units[p.unitId],
        'salePrice': p.salePrice,
        'wholesalePrice': p.wholesalePrice,
        'taxRate': p.taxRate,
        'taxExempt': exempt.contains(p.id),
        'isActive': p.isActive,
        'deleted': p.deletedAt != null,
      });
    }
    final vanStockJson = [
      for (final b in stock)
        if (productGid[b.productId] != null && warehouseGid[b.warehouseId] != null)
          {
            'warehouseGlobalId': warehouseGid[b.warehouseId],
            'productGlobalId': productGid[b.productId],
            'quantity': b.quantity,
          },
    ];

    // ── price lists (list or any item changed → whole list) ──
    final lists = await db.select(db.priceLists).get();
    final allItems = await db.select(db.priceListItems).get();
    final priceListsJson = <Map<String, Object?>>[];
    for (final l in lists) {
      final items = allItems.where((i) => i.priceListId == l.id).toList();
      bool changedAfter(DateTime? t) =>
          since == null || (t != null && t.isAfter(since));
      if (!changedAfter(l.lastModifiedAt) &&
          !items.any((i) => changedAfter(i.lastModifiedAt))) {
        continue;
      }
      final itemsJson = <Map<String, Object?>>[];
      for (final i in items.where((i) => i.deletedAt == null)) {
        final pg = productGid[i.productId] ??
            await _productGid(i.productId);
        if (pg == null) continue;
        itemsJson.add({
          'globalId': await _ensureGid('price_list_items', i.id, i.globalId),
          'productGlobalId': pg,
          'price': i.price,
          'minQuantity': i.minQuantity,
          'maxDiscount': i.maxDiscount,
        });
      }
      priceListsJson.add({
        'globalId': await _ensureGid('price_lists', l.id, l.globalId),
        'name': l.name,
        'code': l.code,
        'isDefault': l.isDefault,
        'startDate': l.startDate?.toIso8601String(),
        'endDate': l.endDate?.toIso8601String(),
        'isActive': l.isActive,
        'deleted': l.deletedAt != null,
        'items': itemsJson,
      });
    }

    // ── areas, routes, route customers, rep resources, books ──
    final areaGid = <int, String>{};
    final areasJson = <Map<String, Object?>>[];
    for (final a in areas) {
      final id = (a['id'] as num).toInt();
      final g = await _ensureGid('distribution_areas', id, a['global_id'] as String?);
      areaGid[id] = g;
      areasJson.add({
        'globalId': g,
        'name': a['name'],
        'isActive': a['is_active'] == true || a['is_active'] == 1,
        'deleted': a['deleted_at'] != null,
      });
    }
    final routeGid = <int, String>{};
    final routesJson = <Map<String, Object?>>[];
    for (final r in routes) {
      final g = await _ensureGid('sales_routes', r.id, r.globalId);
      routeGid[r.id] = g;
      final extra = routeExtra[r.id];
      routesJson.add({
        'globalId': g,
        'name': r.name,
        'salesRepGlobalId': r.salesRepId == null ? null : employeeGid[r.salesRepId],
        'areaGlobalId': areaGid[_int(extra?['area_id'])],
        'visitDays': _visitDays(extra?['visit_days']),
        'isActive': r.isActive,
        'deleted': r.deletedAt != null,
      });
    }
    final routeCustomersJson = <Map<String, Object?>>[];
    for (final rc in routeCustomers) {
      final cg = partyGid[(rc['customer_id'] as num).toInt()];
      final rg = routeGid[(rc['route_id'] as num).toInt()];
      if (cg == null || rg == null) continue;
      routeCustomersJson.add({
        'globalId': await _ensureGid(
            'route_customers', (rc['id'] as num).toInt(), rc['global_id'] as String?),
        'routeGlobalId': rg,
        'customerGlobalId': cg,
        'sequence': _int(rc['sequence']) ?? 0,
        'effectiveFrom': _isoDay(rc['effective_from']),
        'effectiveTo': _isoDay(rc['effective_to']),
      });
    }
    final repResJson = <Map<String, Object?>>[];
    for (final r in repRes) {
      final eg = employeeGid[(r['employee_id'] as num).toInt()];
      if (eg == null) continue;
      repResJson.add({
        'globalId': await _ensureGid(
            'rep_resources', (r['id'] as num).toInt(), r['global_id'] as String?),
        'employeeGlobalId': eg,
        'vanWarehouseGlobalId': warehouseGid[_int(r['van_warehouse_id'])],
        'custodySafeGlobalId': safeGid[_int(r['custody_safe_id'])],
      });
    }
    final booksJson = <Map<String, Object?>>[];
    for (final b in books) {
      final id = (b['id'] as num).toInt();
      final cancelled = await db.customSelect(
        'SELECT number FROM voucher_book_leaves_cancelled '
        'WHERE book_id = ? AND deleted_at IS NULL ORDER BY number',
        variables: [Variable<int>(id)],
      ).get();
      booksJson.add({
        'globalId': await _ensureGid('voucher_books', id, b['global_id'] as String?),
        'bookType': b['book_type'],
        'prefix': b['prefix'],
        'label': b['label'],
        'rangeFrom': _int(b['range_from']),
        'rangeTo': _int(b['range_to']),
        'nextNumber': _int(b['next_number']),
        'holderEmployeeGlobalId': employeeGid[_int(b['holder_employee_id'])],
        'status': b['status'],
        'cancelledNumbers': [for (final c in cancelled) _int(c.data['number'])],
      });
    }

    return {
      'company': await _company(),
      'employees': employeesJson,
      'warehouses': warehousesJson,
      'safes': safesJson,
      'parties': partiesJson,
      'products': productsJson,
      'priceLists': priceListsJson,
      'distributionAreas': areasJson,
      'salesRoutes': routesJson,
      'routeCustomers': routeCustomersJson,
      'repResources': repResJson,
      'voucherBooks': booksJson,
      'vanStock': vanStockJson,
      'expenseCategories': await cloudExpenseCategoriesJson(db),
    };
  }

  Future<String?> _productGid(int productId) async {
    final p = await db.getProductById(productId);
    if (p == null) return null;
    return _ensureGid('products', p.id, p.globalId);
  }

  Future<Map<String, Object?>> _company() async {
    final name = await db.getSettingValue('company_name');
    String? read(String? v) {
      final t = v?.trim();
      return (t == null || t.isEmpty) ? null : t;
    }

    // Company info screen saves the tax number as `company_tax_id`; the legacy
    // `tax_number` key is the fallback.
    final taxNumber = read(await db.getSettingValue('company_tax_id')) ??
        read(await db.getSettingValue('tax_number'));
    final eInvoice =
        await db.getSettingValue('show_jofotara_einvoice') == 'true' ||
            await db.getSettingValue('show_eta_einvoice') == 'true';
    return {
      if (name != null && name.trim().isNotEmpty) 'name': name.trim(),
      'taxNumber': taxNumber,
      // Printed identity for van receipts (I-4).
      'nameEn': read(await db.getSettingValue('company_name_en')),
      'commercialRegister':
          read(await db.getSettingValue('company_cr_number')),
      'address': read(await db.getSettingValue('company_address')),
      'phone': read(await db.getSettingValue('company_phone')),
      'eInvoiceEnabled': eInvoice,
      'defaultTaxRate':
          double.tryParse(await db.getSettingValue('tax_rate') ?? '') ?? 0,
      'pricesIncludeTax':
          await db.getSettingValue('prices_include_tax') == 'true',
      'decimalPlaces': AppConstants.decimalPlaces,
      'expenseOverCustody':
          await db.getSettingValue(kCloudExpenseOverCustodySetting) == 'reject'
              ? 'reject'
              : 'flag',
    };
  }
}
