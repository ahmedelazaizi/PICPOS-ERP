import 'dart:convert';

import 'package:postgres/postgres.dart';
import 'package:uuid/uuid.dart';

import '../db/database.dart';
import '../domain/integrity.dart';
import '../domain/pricing.dart';
import '../domain/tax.dart';
import 'errors.dart';

const _uuid = Uuid();

/// Visit outcomes and no-sale reason codes accepted from the device.
const kVisitOutcomes = {'visited', 'no_sale'};
const kNoSaleReasons = {'closed', 'owner_absent', 'has_stock', 'no_cash', 'refused', 'other'};

/// Invoices offered to the device for returns (by `created_at`).
const kReturnWindowDays = 90;

class _Company {
  _Company(this.defaultTaxRate, this.secret, this.pricesIncludeTax, this.decimals);
  final double defaultTaxRate;
  final String secret;
  final bool pricesIncludeTax;
  final int decimals;
}

/// Mobile bootstrap / pull (scoped to the rep) and push (idempotent by
/// globalId, validated: route scoping, van stock, credit limit, number lease,
/// voucher-book leaf, prices, return quantities). See
/// docs/mobile/ARCHITECTURE-I.md §3, §5–§7.
class SyncService {
  SyncService(this.db, {this.pullOverlapMs = 2000});
  final CloudDatabase db;

  /// The watermark handed to clients is `now - overlap` so rows committed
  /// slightly late are re-sent (upsert by globalId on the client is idempotent).
  final int pullOverlapMs;

  Future<_Company> _company(Session s, int companyId) async {
    final r = (await db.q(s, '''
      SELECT default_tax_rate, integrity_secret, prices_include_tax, decimal_places
      FROM companies WHERE id=@c''', {'c': companyId}))
        .first;
    return _Company(num0(r[0]), r[1] as String, r[2] == true, r[3] as int);
  }

  // ───────────────────────────── leases ─────────────────────────────

  Future<void> ensureLeases(Session s, DeviceContext d) async {
    final series = await db.q(s,
        'SELECT doc_type, block_size FROM number_series WHERE company_id=@c', {'c': d.companyId});
    for (final row in series) {
      final docType = row[0] as String;
      final block = row[1] as int;
      final rem = await db.q(s, '''
        SELECT COALESCE(SUM(range_to - next_number + 1), 0)::BIGINT FROM device_number_leases
        WHERE device_pk=@d AND doc_type=@t AND status='active' ''', {'d': d.devicePk, 't': docType});
      if ((rem.first[0] as int) >= (block * 0.2)) continue;
      final alloc = await db.q(s, '''
        UPDATE number_series SET next_block_start = next_block_start + block_size
        WHERE company_id=@c AND doc_type=@t
        RETURNING next_block_start - block_size, block_size, prefix''', {'c': d.companyId, 't': docType});
      final start = alloc.first[0] as int;
      await db.q(s, '''
        INSERT INTO device_number_leases
          (company_id, device_pk, doc_type, prefix, range_from, range_to, next_number, leased_at, global_id)
        VALUES (@c, @d, @t, @p, @f, @to, @f, now_ms(), @g)''', {
        'c': d.companyId,
        'd': d.devicePk,
        't': docType,
        'p': alloc.first[2],
        'f': start,
        'to': start + (alloc.first[1] as int) - 1,
        'g': _uuid.v4(),
      });
    }
  }

  /// Finds this device's lease containing [number] (locked) for [docType].
  Future<({int leaseId, int n, String number})> _leaseFor(Session s, DeviceContext d, String docType, Object? number) async {
    if (number is! String || number.isEmpty) throw DocRejected('invalid_number');
    final leases = await db.q(s, '''
      SELECT id, prefix, range_from, range_to FROM device_number_leases
      WHERE device_pk=@d AND doc_type=@t AND status IN ('active','exhausted')
      FOR UPDATE''', {'d': d.devicePk, 't': docType});
    for (final l in leases) {
      final m = l.toColumnMap();
      final prefix = m['prefix'] as String;
      if (!number.startsWith(prefix)) continue;
      final v = int.tryParse(number.substring(prefix.length));
      if (v != null && v >= (m['range_from'] as int) && v <= (m['range_to'] as int)) {
        return (leaseId: m['id'] as int, n: v, number: number);
      }
    }
    throw DocRejected('number_out_of_range', number);
  }

  Future<void> _advanceLease(Session s, int leaseId, int n) => db.q(s, '''
      UPDATE device_number_leases SET next_number = GREATEST(next_number, @nx),
        status = CASE WHEN GREATEST(next_number, @nx) > range_to THEN 'exhausted' ELSE status END
      WHERE id=@id''', {'nx': n + 1, 'id': leaseId});

  // ─────────────────────────── bootstrap / pull ───────────────────────────

  Future<Map<String, Object?>> bootstrap(DeviceContext d) async {
    final delta = await pull(d, since: 0);
    final profile = await db.tx((s) async {
      final company = (await db.q(s, '''
              SELECT name, tax_number, currency, default_tax_rate, prices_include_tax, decimal_places
              FROM companies WHERE id=@c''', {'c': d.companyId}))
          .first
          .toColumnMap();
      final emp = (await db.q(s, 'SELECT global_id, name, can_override_price FROM employees WHERE id=@e',
              {'e': d.employeeId}))
          .first
          .toColumnMap();
      final res = await db.q(s, '''
        SELECT w.global_id AS wg, w.name AS wn, sf.global_id AS sg, sf.name AS sn
        FROM rep_resources rr
        LEFT JOIN warehouses w ON w.id = rr.van_warehouse_id
        LEFT JOIN safes sf ON sf.id = rr.custody_safe_id
        WHERE rr.employee_id=@e AND rr.deleted_at IS NULL''', {'e': d.employeeId});
      final routes = await db.q(s, '''
        SELECT global_id, name, visit_days FROM sales_routes
        WHERE company_id=@c AND sales_rep_id=@e AND is_active AND deleted_at IS NULL ORDER BY id''',
          {'c': d.companyId, 'e': d.employeeId});
      final r = res.isEmpty ? null : res.first.toColumnMap();
      return {
        'company': {
          'name': company['name'],
          'taxNumber': company['tax_number'],
          'currency': company['currency'],
          'defaultTaxRate': num0(company['default_tax_rate']),
          'pricesIncludeTax': company['prices_include_tax'] == true,
          'decimalPlaces': company['decimal_places'],
        },
        'employee': {
          'globalId': emp['global_id'],
          'name': emp['name'],
          'canOverridePrice': emp['can_override_price'] == true,
        },
        'vanWarehouse': r?['wg'] == null ? null : {'globalId': r!['wg'], 'name': r['wn']},
        'custodySafe': r?['sg'] == null ? null : {'globalId': r!['sg'], 'name': r['sn']},
        'routes': [
          for (final x in routes)
            {'globalId': x[0], 'name': x[1], 'visitDays': x[2]},
        ],
        'noSaleReasons': kNoSaleReasons.toList(),
      };
    });
    return {...profile, ...delta};
  }

  static const _scopedCustomersSql = '''
    SELECT p.id, p.global_id, p.name, p.phone, p.balance, p.credit_limit, p.price_level,
           p.whatsapp_opt_in, rc.sequence, r.global_id AS route_global_id, r.id AS route_id,
           GREATEST(p.last_modified_at, rc.last_modified_at, r.last_modified_at) AS lm
    FROM route_customers rc
    JOIN sales_routes r ON r.id = rc.route_id
    JOIN parties p ON p.id = rc.customer_id
    WHERE r.company_id = @c AND r.sales_rep_id = @e AND r.is_active
      AND r.deleted_at IS NULL AND rc.deleted_at IS NULL AND p.deleted_at IS NULL
      AND rc.effective_from <= CURRENT_DATE
      AND (rc.effective_to IS NULL OR rc.effective_to >= CURRENT_DATE)''';

  Future<({int? van, int? safe})> _repResources(Session s, int employeeId) async {
    final r = await db.q(s,
        'SELECT van_warehouse_id, custody_safe_id FROM rep_resources WHERE employee_id=@e AND deleted_at IS NULL',
        {'e': employeeId});
    return r.isEmpty ? (van: null, safe: null) : (van: r.first[0] as int?, safe: r.first[1] as int?);
  }

  /// Delta since [since] (epoch ms). Scope lists (`customerScope`,
  /// `voucherBookScope`, `priceListScope`) are always complete so the device
  /// can drop rows that left its scope.
  Future<Map<String, Object?>> pull(DeviceContext d, {required int since}) {
    return db.tx((s) async {
      await ensureLeases(s, d);
      final now = (await db.q(s, 'SELECT now_ms()')).first[0] as int;
      final ce = {'c': d.companyId, 'e': d.employeeId};

      final allCustomers = await db.q(s, '$_scopedCustomersSql ORDER BY r.id, rc.sequence', ce);
      final customers = [
        for (final row in allCustomers)
          if ((row.toColumnMap()['lm'] as int) > since) _customerJson(row.toColumnMap()),
      ];

      final products = await db.q(s, '''
        SELECT global_id, name, name_en, barcode, unit_name, sale_price, tax_rate, tax_exempt,
               is_active, deleted_at, wholesale_price
        FROM products WHERE company_id=@c AND last_modified_at > @s ORDER BY id''',
          {'c': d.companyId, 's': since});

      final van = (await _repResources(s, d.employeeId)).van;
      final stock = van == null
          ? <ResultRow>[]
          : await db.q(s, '''
              SELECT pr.global_id, ib.quantity FROM inventory_balances ib
              JOIN products pr ON pr.id = ib.product_id
              WHERE ib.warehouse_id=@w AND ib.last_modified_at > @s''', {'w': van, 's': since});

      final books = await db.q(s, '''
        SELECT id, global_id, prefix, label, range_from, range_to, next_number, status, last_modified_at
        FROM voucher_books WHERE company_id=@c AND holder_employee_id=@e AND book_type='receipt'
          AND deleted_at IS NULL ORDER BY id''', ce);
      final bookJson = <Map<String, Object?>>[];
      for (final b in books) {
        final m = b.toColumnMap();
        if ((m['last_modified_at'] as int) <= since) continue;
        final used = await db.q(s,
            'SELECT book_number FROM safe_transactions WHERE book_id=@b ORDER BY 1', {'b': m['id']});
        final cancelled = await db.q(s,
            'SELECT number FROM voucher_book_leaves_cancelled WHERE book_id=@b ORDER BY 1',
            {'b': m['id']});
        bookJson.add({
          'globalId': m['global_id'],
          'prefix': m['prefix'],
          'label': m['label'],
          'rangeFrom': m['range_from'],
          'rangeTo': m['range_to'],
          'nextNumber': m['next_number'],
          'status': m['status'],
          'usedNumbers': [for (final u in used) u[0]],
          'cancelledNumbers': [for (final c in cancelled) c[0]],
        });
      }

      final leases = await db.q(s, '''
        SELECT global_id, doc_type, prefix, range_from, range_to, next_number, status
        FROM device_number_leases WHERE device_pk=@d AND last_modified_at > @s ORDER BY id''',
          {'d': d.devicePk, 's': since});

      final priceLists = await _priceLists(s, d.companyId, since);
      final allLists = await db.q(s,
          'SELECT global_id FROM price_lists WHERE company_id=@c AND deleted_at IS NULL ORDER BY id',
          {'c': d.companyId});

      final invoices = await _returnableInvoices(s, d, since, now);

      final docs = await db.q(s, '''
        SELECT global_id, 'sales_invoice', invoice_number, status FROM sales_invoices
          WHERE device_pk=@d AND last_modified_at > @s
        UNION ALL SELECT global_id, 'collection', voucher_number, 'accepted' FROM safe_transactions
          WHERE device_pk=@d AND category='customer_collection' AND last_modified_at > @s
        UNION ALL SELECT global_id, 'sales_return', return_number, status FROM sales_returns
          WHERE device_pk=@d AND last_modified_at > @s
        UNION ALL SELECT global_id, 'visit', outcome, 'accepted' FROM customer_visits
          WHERE device_pk=@d AND last_modified_at > @s''', {'d': d.devicePk, 's': since});

      return {
        'serverTime': now - pullOverlapMs,
        'customers': customers,
        'customerScope': [for (final r in allCustomers) r.toColumnMap()['global_id']],
        'products': [
          for (final r in products)
            {
              'globalId': r[0],
              'name': r[1],
              'nameEn': r[2],
              'barcode': r[3],
              'unitName': r[4],
              'salePrice': num0(r[5]),
              'wholesalePrice': r[10] == null ? null : num0(r[10]),
              'taxRate': num0(r[6]),
              'taxExempt': r[7],
              'active': r[8] == true && r[9] == null,
            },
        ],
        'vanStock': [
          for (final r in stock) {'productGlobalId': r[0], 'quantity': num0(r[1])},
        ],
        'voucherBooks': bookJson,
        'voucherBookScope': [for (final b in books) b.toColumnMap()['global_id']],
        'priceLists': priceLists,
        'priceListScope': [for (final r in allLists) r[0]],
        'invoices': invoices,
        'leases': [
          for (final r in leases)
            {
              'globalId': r[0],
              'docType': r[1],
              'prefix': r[2],
              'rangeFrom': r[3],
              'rangeTo': r[4],
              'nextNumber': r[5],
              'status': r[6],
            },
        ],
        'documents': [
          for (final r in docs)
            {'globalId': r[0], 'kind': r[1], 'number': r[2], 'status': r[3]},
        ],
      };
    });
  }

  /// Changed price lists, each with its complete current item set.
  Future<List<Map<String, Object?>>> _priceLists(Session s, int companyId, int since) async {
    final lists = await db.q(s, '''
      SELECT pl.id, pl.global_id, pl.name, pl.code, pl.is_default, pl.start_date::TEXT, pl.end_date::TEXT,
             pl.is_active
      FROM price_lists pl
      WHERE pl.company_id=@c AND pl.deleted_at IS NULL AND (pl.last_modified_at > @s OR EXISTS (
        SELECT 1 FROM price_list_items i WHERE i.price_list_id = pl.id AND i.last_modified_at > @s))
      ORDER BY pl.id''', {'c': companyId, 's': since});
    final out = <Map<String, Object?>>[];
    for (final l in lists) {
      final items = await db.q(s, '''
        SELECT i.global_id, p.global_id, i.price, i.min_quantity, i.max_discount
        FROM price_list_items i JOIN products p ON p.id = i.product_id
        WHERE i.price_list_id=@l AND i.deleted_at IS NULL ORDER BY i.id''', {'l': l[0]});
      out.add({
        'globalId': l[1],
        'name': l[2],
        'code': l[3],
        'isDefault': l[4],
        'startDate': l[5],
        'endDate': l[6],
        'isActive': l[7],
        'order': l[0],
        'items': [
          for (final i in items)
            {
              'globalId': i[0],
              'productGlobalId': i[1],
              'price': num0(i[2]),
              'minQuantity': num0(i[3]),
              'maxDiscount': num0(i[4]),
            },
        ],
      });
    }
    return out;
  }

  /// Recent accepted invoices of the rep's customers with per-product sold and
  /// already-returned amounts (what the device needs to build a return).
  Future<List<Map<String, Object?>>> _returnableInvoices(
      Session s, DeviceContext d, int since, int now) async {
    final rows = await db.q(s, '''
      SELECT si.id, si.global_id, si.invoice_number, si.invoice_date, p.global_id, si.total, si.paid,
             si.return_ar_offset, si.returned_total
      FROM sales_invoices si JOIN parties p ON p.id = si.customer_id
      WHERE si.company_id=@c AND si.status='accepted' AND si.last_modified_at > @s AND si.created_at >= @from
        AND si.customer_id IN (SELECT q.id FROM ($_scopedCustomersSql) q)
      ORDER BY si.id''', {
      'c': d.companyId,
      'e': d.employeeId,
      's': since,
      'from': now - kReturnWindowDays * 86400000,
    });
    final out = <Map<String, Object?>>[];
    for (final r in rows) {
      final sold = await _soldByProduct(s, r[0] as int);
      out.add({
        'globalId': r[1],
        'number': r[2],
        'date': r[3],
        'customerGlobalId': r[4],
        'total': num0(r[5]),
        'paid': num0(r[6]),
        'returnArOffset': num0(r[7]),
        'returnedTotal': num0(r[8]),
        'lines': [
          for (final e in sold.entries)
            {
              'productGlobalId': e.key,
              'quantity': e.value.soldQty,
              'total': e.value.soldTotal,
              'tax': e.value.soldTax,
              'returnedQuantity': e.value.returnedQty,
              'returnedTotal': e.value.returnedTotal,
              'returnedTax': e.value.returnedTax,
            },
        ],
      });
    }
    return out;
  }

  /// productGlobalId → sold/returned on [invoiceId] (lines aggregated per product).
  Future<Map<String, SoldProduct>> _soldByProduct(Session s, int invoiceId) async {
    final sold = await db.q(s, '''
      SELECT p.global_id, SUM(i.quantity), SUM(i.total), SUM(i.tax_amount)
      FROM sales_invoice_items i JOIN products p ON p.id = i.product_id
      WHERE i.invoice_id=@i GROUP BY p.global_id, p.id ORDER BY p.id''', {'i': invoiceId});
    final returned = {
      for (final r in await db.q(s, '''
        SELECT p.global_id, SUM(ri.quantity), SUM(ri.total), SUM(ri.tax_amount)
        FROM sales_return_items ri JOIN sales_returns sr ON sr.id = ri.return_id
        JOIN products p ON p.id = ri.product_id
        WHERE sr.original_invoice_id=@i AND sr.status='accepted' GROUP BY p.global_id''', {'i': invoiceId}))
        r[0] as String: r,
    };
    return {
      for (final r in sold)
        r[0] as String: SoldProduct(
          soldQty: num0(r[1]),
          soldTotal: num0(r[2]),
          soldTax: num0(r[3]),
          returnedQty: num0(returned[r[0]]?[1]),
          returnedTotal: num0(returned[r[0]]?[2]),
          returnedTax: num0(returned[r[0]]?[3]),
        ),
    };
  }

  Map<String, Object?> _customerJson(Map<String, dynamic> m) => {
        'globalId': m['global_id'],
        'name': m['name'],
        'phone': m['phone'],
        'balance': num0(m['balance']),
        'creditLimit': num0(m['credit_limit']),
        'priceLevel': m['price_level'],
        'whatsappOptIn': m['whatsapp_opt_in'],
        'sequence': m['sequence'],
        'routeGlobalId': m['route_global_id'],
      };

  // ───────────────────────────── push ─────────────────────────────

  Future<List<Map<String, Object?>>> push(DeviceContext d, List<Object?> documents) async {
    final results = <Map<String, Object?>>[];
    for (final raw in documents) {
      if (raw is! Map) {
        results.add({'status': 'rejected', 'code': 'invalid_document'});
        continue;
      }
      final doc = raw.cast<String, Object?>();
      final gid = doc['globalId'];
      if (gid is! String || !_uuidRe.hasMatch(gid)) {
        results.add({'globalId': gid, 'status': 'rejected', 'code': 'invalid_global_id'});
        continue;
      }
      try {
        final r = await db.tx((s) => _pushOne(s, d, gid, doc));
        results.add(r);
      } on DocRejected catch (e) {
        results.add({
          'globalId': gid,
          'status': 'rejected',
          'code': e.code,
          if (e.message != null) 'message': e.message,
          if (e.details != null) 'details': e.details,
        });
        await _audit(d, 'push_rejected', '${doc['kind']}', gid, e.code);
      } on ServerException catch (e) {
        // Unique violation from a concurrent duplicate push → treat as replay.
        if (e.code == '23505') {
          final again = await db.tx((s) => _replay(s, d, gid));
          results.add(again ??
              {'globalId': gid, 'status': 'rejected', 'code': 'conflict', 'message': e.message});
        } else {
          rethrow;
        }
      }
    }
    return results;
  }

  Future<void> _audit(DeviceContext d, String action, String entity, String? gid, String? detail) =>
      db.query('''
        INSERT INTO audit_log (company_id, device_pk, employee_id, action, entity, global_id, ip, detail, at)
        VALUES (@c, @d, @e, @a, @en, @g, @ip, @dt, now_ms())''', {
        'c': d.companyId,
        'd': d.devicePk,
        'e': d.employeeId,
        'a': action,
        'en': entity,
        'g': gid,
        'ip': d.ip,
        'dt': detail,
      });

  static final _uuidRe =
      RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');

  Future<Map<String, Object?>?> _replay(Session s, DeviceContext d, String gid) async {
    final prior = await db.q(s,
        'SELECT device_pk, result FROM sync_idempotency WHERE company_id=@c AND global_id=@g',
        {'c': d.companyId, 'g': gid});
    if (prior.isEmpty) return null;
    if (prior.first[0] != d.devicePk) throw DocRejected('global_id_conflict');
    final res = (jsonDecode(prior.first[1] as String) as Map).cast<String, Object?>();
    return {...res, 'status': 'duplicate'};
  }

  Future<Map<String, Object?>> _pushOne(
      Session s, DeviceContext d, String gid, Map<String, Object?> doc) async {
    final replay = await _replay(s, d, gid);
    if (replay != null) return replay;
    final kind = doc['kind'];
    final Map<String, Object?> result;
    switch (kind) {
      case 'sales_invoice':
        result = await _acceptInvoice(s, d, gid, doc);
      case 'collection':
        result = await _acceptCollection(s, d, gid, doc);
      case 'sales_return':
        result = await _acceptReturn(s, d, gid, doc);
      case 'visit':
        result = await _acceptVisit(s, d, gid, doc);
      default:
        throw DocRejected('unsupported_kind', 'kind "$kind" is not accepted');
    }
    await db.q(s, '''
      INSERT INTO sync_idempotency (company_id, global_id, kind, device_pk, result, created_at)
      VALUES (@c, @g, @k, @d, @r, now_ms())''',
        {'c': d.companyId, 'g': gid, 'k': kind, 'd': d.devicePk, 'r': jsonEncode(result)});
    await db.q(s, '''
      INSERT INTO audit_log (company_id, device_pk, employee_id, action, entity, global_id, ip, at)
      VALUES (@c, @d, @e, 'push_accepted', @k, @g, @ip, now_ms())''',
        {'c': d.companyId, 'd': d.devicePk, 'e': d.employeeId, 'k': kind, 'g': gid, 'ip': d.ip});
    return result;
  }

  Future<Map<String, dynamic>> _customerOnRoute(Session s, DeviceContext d, Object? customerGid) async {
    if (customerGid is! String) throw DocRejected('invalid_customer');
    final rows = await db.q(s, '$_scopedCustomersSql AND p.global_id=@g LIMIT 1',
        {'c': d.companyId, 'e': d.employeeId, 'g': customerGid});
    if (rows.isEmpty) throw DocRejected('customer_not_on_route');
    final scoped = rows.first.toColumnMap();
    // Lock the party row for the balance update.
    final locked = await db.q(s,
        'SELECT id, balance, credit_limit, whatsapp_phone, whatsapp_opt_in, name, price_level, global_id '
        'FROM parties WHERE id=@id FOR UPDATE',
        {'id': scoped['id']});
    return {...locked.first.toColumnMap(), 'route_id': scoped['route_id'], 'sequence': scoped['sequence']};
  }

  double _num(Object? v, String field) {
    if (v is num) return v.toDouble();
    throw DocRejected('invalid_field', field);
  }

  DateTime _docDate(Map<String, Object?> doc) =>
      DateTime.tryParse('${doc['date']}')?.toUtc() ?? DateTime.now().toUtc();

  Future<List<PriceListEntry>> _priceEntries(Session s, int companyId, int productId) async => [
        for (final r in await db.q(s, '''
          SELECT pl.global_id, pl.is_default, pl.is_active, pl.start_date::TEXT, pl.end_date::TEXT, pl.id,
                 i.price, i.min_quantity
          FROM price_list_items i JOIN price_lists pl ON pl.id = i.price_list_id
          WHERE pl.company_id=@c AND i.product_id=@p AND i.deleted_at IS NULL AND pl.deleted_at IS NULL''',
            {'c': companyId, 'p': productId}))
          PriceListEntry(
            listGlobalId: r[0] as String,
            isDefault: r[1] == true,
            isActive: r[2] == true,
            startDate: r[3] as String?,
            endDate: r[4] as String?,
            listOrder: r[5] as int,
            price: num0(r[6]),
            minQuantity: num0(r[7]),
          ),
      ];

  Future<Map<String, Object?>> _acceptInvoice(
      Session s, DeviceContext d, String gid, Map<String, Object?> doc) async {
    // 1. Number must come from this device's lease.
    final lease = await _leaseFor(s, d, 'sales_invoice', doc['number']);
    final number = lease.number;
    final dup = await db.q(s,
        'SELECT 1 FROM sales_invoices WHERE company_id=@c AND invoice_number=@n',
        {'c': d.companyId, 'n': number});
    if (dup.isNotEmpty) throw DocRejected('number_already_used', number);

    // 2. Customer must be on the rep's route today.
    final cust = await _customerOnRoute(s, d, doc['customerGlobalId']);

    // 3. Van warehouse (stock rule: only the rep's van).
    final rr = await _repResources(s, d.employeeId);
    final van = rr.van;
    if (van == null) throw DocRejected('no_van_warehouse');

    // 4. Lines: price rule + server-side totals (same tax rule as desktop).
    final company = await _company(s, d.companyId);
    final canOverride = (await db.q(s, 'SELECT can_override_price FROM employees WHERE id=@e',
            {'e': d.employeeId}))
        .first[0] ==
        true;
    final date = _docDate(doc);
    final rawLines = doc['lines'];
    if (rawLines is! List || rawLines.isEmpty) throw DocRejected('no_lines');
    final lines = <({int productId, LineInput input})>[];
    final qtyByProduct = <int, double>{};
    for (final rl in rawLines) {
      if (rl is! Map) throw DocRejected('invalid_line');
      final pg = rl['productGlobalId'];
      final prod = await db.q(s, '''
        SELECT id, tax_rate, tax_exempt, sale_price, wholesale_price FROM products
        WHERE company_id=@c AND global_id=@g AND is_active AND deleted_at IS NULL''',
          {'c': d.companyId, 'g': pg});
      if (prod.isEmpty) throw DocRejected('unknown_product', '$pg');
      final qty = _num(rl['quantity'], 'quantity');
      final price = _num(rl['unitPrice'], 'unitPrice');
      final disc = rl['discount'] == null ? 0.0 : _num(rl['discount'], 'discount');
      if (qty <= 0 || price < 0 || disc < 0) throw DocRejected('invalid_line');
      final pid = prod.first[0] as int;
      if (!canOverride) {
        final expected = resolveUnitPrice(
          salePrice: num0(prod.first[3]),
          wholesalePrice: prod.first[4] == null ? null : num0(prod.first[4]),
          priceLevel: cust['price_level'] as String?,
          quantity: qty,
          today: date,
          entries: await _priceEntries(s, d.companyId, pid),
        );
        if ((expected.price - price).abs() > 0.00005 || disc > 0) {
          throw DocRejected('price_not_allowed', null,
              {'productGlobalId': pg, 'expected': expected.price, 'unitPrice': price, 'source': expected.source});
        }
      }
      lines.add((
        productId: pid,
        input: LineInput(
          quantity: qty,
          unitPrice: price,
          discount: disc,
          taxRate: effectiveItemTaxRate(
              rate: num0(prod.first[1]), exempt: prod.first[2] == true, companyDefault: company.defaultTaxRate),
        ),
      ));
      qtyByProduct[pid] = (qtyByProduct[pid] ?? 0) + qty;
    }
    double r(double v) => roundDp(v, company.decimals);
    final totals = computeTotals([for (final l in lines) l.input],
        pricesIncludeTax: company.pricesIncludeTax, decimals: company.decimals);
    final clientTotal = doc['total'];
    if (clientTotal is num && (clientTotal - totals.total).abs() > 0.01) {
      throw DocRejected('totals_mismatch', 'server total ${totals.total}', {'serverTotal': totals.total});
    }
    final paid = doc['paid'] == null ? 0.0 : _num(doc['paid'], 'paid');
    if (paid < 0 || paid > totals.total + 0.01) throw DocRejected('invalid_payment');
    final remaining = r(totals.total - paid);

    // 5. Credit limit (desktop parity: limit 0 = no limit; remaining > 0.01).
    final balance = num0(cust['balance']);
    final limit = num0(cust['credit_limit']);
    if (remaining > 0.01 && limit > 0 && balance + remaining > limit) {
      throw DocRejected('credit_limit_exceeded', null,
          {'balance': balance, 'creditLimit': limit, 'remaining': remaining});
    }

    // 6. Van stock (row locks), then deduct.
    for (final e in qtyByProduct.entries) {
      final st = await db.q(s,
          'SELECT quantity FROM inventory_balances WHERE product_id=@p AND warehouse_id=@w FOR UPDATE',
          {'p': e.key, 'w': van});
      final have = st.isEmpty ? 0.0 : num0(st.first[0]);
      if (have + 1e-9 < e.value) {
        final pg = await db.q(s, 'SELECT global_id FROM products WHERE id=@p', {'p': e.key});
        throw DocRejected('insufficient_van_stock', null,
            {'productGlobalId': pg.first[0], 'available': have, 'requested': e.value});
      }
    }

    // 7. Persist.
    final paymentMethod = remaining <= 0.01 ? 'cash' : (paid > 0 ? 'mixed' : 'credit');
    final hash = signV2(
        company.secret,
        salesIntegrityPayload(
          number: number,
          date: date,
          total: totals.total,
          subtotal: totals.subtotal,
          discount: totals.discount,
          tax: totals.tax,
          paid: paid,
          customerId: cust['id'] as int,
          userId: d.employeeId,
          paymentMethod: paymentMethod,
        ));
    final inv = await db.q(s, '''
      INSERT INTO sales_invoices (company_id, global_id, invoice_number, customer_id, warehouse_id, safe_id,
        rep_employee_id, route_id, device_pk, invoice_date, subtotal, discount, tax, total, paid,
        payment_method, integrity_hash, origin_client_id, prices_include_tax, created_at)
      VALUES (@c, @g, @n, @cu, @w, @sf, @e, @r, @d, @dt, @sub, @disc, @tax, @tot, @paid, @pm, @h, @o, @pit, now_ms())
      RETURNING id''', {
      'c': d.companyId,
      'g': gid,
      'n': number,
      'cu': cust['id'],
      'w': van,
      'sf': rr.safe,
      'e': d.employeeId,
      'r': cust['route_id'],
      'd': d.devicePk,
      'dt': date.toIso8601String(),
      'sub': totals.subtotal,
      'disc': totals.discount,
      'tax': totals.tax,
      'tot': totals.total,
      'paid': paid,
      'pm': paymentMethod,
      'h': hash,
      'o': d.deviceId,
      'pit': company.pricesIncludeTax,
    });
    final invId = inv.first[0] as int;
    for (var i = 0; i < lines.length; i++) {
      final l = lines[i];
      await db.q(s, '''
        INSERT INTO sales_invoice_items (invoice_id, product_id, quantity, unit_price, discount, tax_rate, tax_amount, total)
        VALUES (@i, @p, @q, @u, @dc, @tr, @ta, @t)''', {
        'i': invId,
        'p': l.productId,
        'q': l.input.quantity,
        'u': l.input.unitPrice,
        'dc': totals.lines[i].discount,
        'tr': l.input.taxRate,
        'ta': totals.lines[i].tax,
        't': totals.lines[i].total,
      });
    }
    for (final e in qtyByProduct.entries) {
      final upd = await db.q(s, '''
        UPDATE inventory_balances SET quantity = quantity - @q
        WHERE product_id=@p AND warehouse_id=@w RETURNING quantity''', {'q': e.value, 'p': e.key, 'w': van});
      await db.q(s, '''
        INSERT INTO stock_movements (company_id, product_id, warehouse_id, movement_type, quantity,
          balance_after, reference_type, reference_global_id, created_at)
        VALUES (@c, @p, @w, 'sale', @q, @b, 'mobile_sales_invoice', @g, now_ms())''',
          {'c': d.companyId, 'p': e.key, 'w': van, 'q': -e.value, 'b': upd.first[0], 'g': gid});
    }
    final newBalance = r(balance + remaining);
    if (remaining.abs() > 0.0001) {
      await db.q(s, 'UPDATE parties SET balance = balance + @r WHERE id=@id',
          {'r': remaining, 'id': cust['id']});
    }
    if (paid > 0) {
      await db.q(s, '''
        INSERT INTO safe_transactions (company_id, global_id, voucher_number, safe_id, transaction_type,
          category, amount, party_id, employee_id, rep_employee_id, route_id, reference_type,
          reference_global_id, device_pk, created_at)
        VALUES (@c, @g, @n, @sf, 'receipt', 'sales_receipt', @a, @p, @e, @e, @r, 'mobile_sales_invoice',
          @inv, @d, now_ms())''', {
        'c': d.companyId,
        'g': _uuid.v4(),
        'n': number,
        'sf': rr.safe,
        'a': paid,
        'p': cust['id'],
        'e': d.employeeId,
        'r': cust['route_id'],
        'inv': gid,
        'd': d.devicePk,
      });
    }
    await _advanceLease(s, lease.leaseId, lease.n);

    await _enqueueWhatsApp(s, d, cust, gid, 'invoice_issued', [
      cust['name'] as String,
      number,
      totals.total.toStringAsFixed(2),
      paid.toStringAsFixed(2),
      remaining.toStringAsFixed(2),
      newBalance.toStringAsFixed(2),
    ]);

    return {
      'globalId': gid,
      'status': 'accepted',
      'kind': 'sales_invoice',
      'number': number,
      'total': totals.total,
      'tax': totals.tax,
      'remaining': remaining,
      'customerBalance': newBalance,
      'integrityHash': hash,
    };
  }

  /// Sales return (credit note) against lines of an accepted invoice.
  /// Stock comes back into the rep's van; settlement per desktop
  /// `SalesReturnRefundSplit` (see `returnSettlement`).
  Future<Map<String, Object?>> _acceptReturn(
      Session s, DeviceContext d, String gid, Map<String, Object?> doc) async {
    final lease = await _leaseFor(s, d, 'sales_return', doc['number']);
    final number = lease.number;
    final dup = await db.q(s, 'SELECT 1 FROM sales_returns WHERE company_id=@c AND return_number=@n',
        {'c': d.companyId, 'n': number});
    if (dup.isNotEmpty) throw DocRejected('number_already_used', number);

    final invGid = doc['originalInvoiceGlobalId'];
    if (invGid is! String) throw DocRejected('invoice_required');
    final invRows = await db.q(s, '''
      SELECT si.id, p.global_id, si.total, si.paid, si.return_ar_offset, si.status
      FROM sales_invoices si JOIN parties p ON p.id = si.customer_id
      WHERE si.company_id=@c AND si.global_id=@g FOR UPDATE OF si''', {'c': d.companyId, 'g': invGid});
    if (invRows.isEmpty) throw DocRejected('invoice_not_found', invGid);
    final inv = invRows.first;
    if (inv[5] != 'accepted') throw DocRejected('invoice_not_returnable');
    final custGid = inv[1] as String;
    if (doc['customerGlobalId'] != null && doc['customerGlobalId'] != custGid) {
      throw DocRejected('customer_mismatch');
    }
    final cust = await _customerOnRoute(s, d, custGid);

    final rr = await _repResources(s, d.employeeId);
    final van = rr.van;
    if (van == null) throw DocRejected('no_van_warehouse');
    final company = await _company(s, d.companyId);
    double r(double v) => roundDp(v, company.decimals);

    final rawLines = doc['lines'];
    if (rawLines is! List || rawLines.isEmpty) throw DocRejected('no_lines');
    final qtyByProduct = <String, double>{};
    for (final rl in rawLines) {
      if (rl is! Map || rl['productGlobalId'] is! String) throw DocRejected('invalid_line');
      final q = _num(rl['quantity'], 'quantity');
      if (q <= 0) throw DocRejected('invalid_line');
      final pg = rl['productGlobalId'] as String;
      qtyByProduct[pg] = (qtyByProduct[pg] ?? 0) + q;
    }
    final sold = await _soldByProduct(s, inv[0] as int);
    final lines = <({String productGid, double qty, ReturnLineAmounts a})>[];
    for (final e in qtyByProduct.entries) {
      final sp = sold[e.key];
      if (sp == null) throw DocRejected('product_not_on_invoice', e.key);
      final a = returnLineAmounts(sp, e.value, decimals: company.decimals);
      if (a == null) {
        throw DocRejected('return_qty_exceeds_sold', null, {
          'productGlobalId': e.key,
          'sold': sp.soldQty,
          'returned': sp.returnedQty,
          'requested': e.value,
        });
      }
      lines.add((productGid: e.key, qty: e.value, a: a));
    }
    final total = r(lines.fold(0.0, (t, l) => t + l.a.total));
    final tax = r(lines.fold(0.0, (t, l) => t + l.a.tax));
    final net = r(total - tax);
    final clientTotal = doc['total'];
    if (clientTotal is num && (clientTotal - total).abs() > 0.01) {
      throw DocRejected('totals_mismatch', 'server total $total', {'serverTotal': total});
    }
    final split = returnSettlement(
      invoiceTotal: num0(inv[2]),
      invoicePaid: num0(inv[3]),
      previousArOffset: num0(inv[4]),
      returnTotal: total,
      decimals: company.decimals,
    );
    final clientRefund = doc['cashRefund'];
    if (clientRefund is num && (clientRefund - split.cashRefund).abs() > 0.01) {
      throw DocRejected('refund_mismatch', null, {'cashRefund': split.cashRefund, 'arOffset': split.arOffset});
    }
    if (split.cashRefund > 0 && rr.safe == null) throw DocRejected('no_custody_safe');

    final date = _docDate(doc);
    final hash = signV2(
        company.secret,
        salesIntegrityPayload(
          number: number,
          date: date,
          total: total,
          subtotal: net,
          discount: 0,
          tax: tax,
          paid: split.cashRefund,
          customerId: cust['id'] as int,
          userId: d.employeeId,
          paymentMethod: 'return',
        ));
    final reason = doc['reason'];
    final ret = await db.q(s, '''
      INSERT INTO sales_returns (company_id, global_id, return_number, original_invoice_id, customer_id,
        warehouse_id, safe_id, rep_employee_id, route_id, device_pk, return_date, subtotal, tax, total,
        ar_offset, cash_refund, reason, integrity_hash, origin_client_id, created_at)
      VALUES (@c, @g, @n, @inv, @cu, @w, @sf, @e, @r, @d, @dt, @sub, @tax, @tot, @ar, @cash, @rs, @h, @o, now_ms())
      RETURNING id''', {
      'c': d.companyId,
      'g': gid,
      'n': number,
      'inv': inv[0],
      'cu': cust['id'],
      'w': van,
      'sf': rr.safe,
      'e': d.employeeId,
      'r': cust['route_id'],
      'd': d.devicePk,
      'dt': date.toIso8601String(),
      'sub': net,
      'tax': tax,
      'tot': total,
      'ar': split.arOffset,
      'cash': split.cashRefund,
      'rs': reason is String ? reason : null,
      'h': hash,
      'o': d.deviceId,
    });
    final retId = ret.first[0] as int;
    for (final l in lines) {
      final pid = (await db.q(s, 'SELECT id FROM products WHERE company_id=@c AND global_id=@g',
              {'c': d.companyId, 'g': l.productGid}))
          .first[0] as int;
      await db.q(s, '''
        INSERT INTO sales_return_items (return_id, product_id, quantity, unit_price, tax_amount, total)
        VALUES (@r, @p, @q, @u, @ta, @t)''', {
        'r': retId,
        'p': pid,
        'q': l.qty,
        'u': roundDp(l.a.total / l.qty, 4),
        'ta': l.a.tax,
        't': l.a.total,
      });
      // Van stock back in (row may not exist when another van sold it).
      final upd = await db.q(s, '''
        INSERT INTO inventory_balances (company_id, global_id, product_id, warehouse_id, quantity)
        VALUES (@c, @g, @p, @w, @q)
        ON CONFLICT (product_id, warehouse_id) DO UPDATE SET quantity = inventory_balances.quantity + EXCLUDED.quantity
        RETURNING quantity''', {'c': d.companyId, 'g': _uuid.v4(), 'p': pid, 'w': van, 'q': l.qty});
      await db.q(s, '''
        INSERT INTO stock_movements (company_id, product_id, warehouse_id, movement_type, quantity,
          balance_after, reference_type, reference_global_id, created_at)
        VALUES (@c, @p, @w, 'return', @q, @b, 'mobile_sales_return', @g, now_ms())''',
          {'c': d.companyId, 'p': pid, 'w': van, 'q': l.qty, 'b': upd.first[0], 'g': gid});
    }
    await db.q(s, '''
      UPDATE sales_invoices SET returned_total = returned_total + @t, return_ar_offset = return_ar_offset + @ar
      WHERE id=@id''', {'t': total, 'ar': split.arOffset, 'id': inv[0]});
    if (split.arOffset > 0) {
      await db.q(s, 'UPDATE parties SET balance = balance - @a WHERE id=@id', {'a': split.arOffset, 'id': cust['id']});
    }
    if (split.cashRefund > 0) {
      await db.q(s, '''
        INSERT INTO safe_transactions (company_id, global_id, voucher_number, safe_id, transaction_type,
          category, amount, party_id, employee_id, rep_employee_id, route_id, reference_type,
          reference_global_id, device_pk, created_at)
        VALUES (@c, @g, @n, @sf, 'payment', 'sales_return', @a, @p, @e, @e, @r, 'mobile_sales_return',
          @ret, @d, now_ms())''', {
        'c': d.companyId,
        'g': _uuid.v4(),
        'n': number,
        'sf': rr.safe,
        'a': split.cashRefund,
        'p': cust['id'],
        'e': d.employeeId,
        'r': cust['route_id'],
        'ret': gid,
        'd': d.devicePk,
      });
    }
    await _advanceLease(s, lease.leaseId, lease.n);
    return {
      'globalId': gid,
      'status': 'accepted',
      'kind': 'sales_return',
      'number': number,
      'total': total,
      'tax': tax,
      'arOffset': split.arOffset,
      'cashRefund': split.cashRefund,
      'customerBalance': r(num0(cust['balance']) - split.arOffset),
      'integrityHash': hash,
    };
  }

  /// Visit record: visited, or no sale with a reason code (route order kept).
  Future<Map<String, Object?>> _acceptVisit(
      Session s, DeviceContext d, String gid, Map<String, Object?> doc) async {
    final cust = await _customerOnRoute(s, d, doc['customerGlobalId']);
    final outcome = doc['outcome'];
    if (outcome is! String || !kVisitOutcomes.contains(outcome)) throw DocRejected('invalid_outcome');
    final reason = doc['noSaleReason'];
    if (outcome == 'no_sale' && (reason is! String || !kNoSaleReasons.contains(reason))) {
      throw DocRejected('no_sale_reason_required');
    }
    final lat = doc['latitude'], lng = doc['longitude'];
    if ((lat != null && (lat is! num || lat.abs() > 90)) || (lng != null && (lng is! num || lng.abs() > 180))) {
      throw DocRejected('invalid_geo');
    }
    final note = doc['note'];
    await db.q(s, '''
      INSERT INTO customer_visits (company_id, global_id, customer_id, route_id, rep_employee_id, device_pk,
        visit_date, outcome, no_sale_reason, note, latitude, longitude, sequence, origin_client_id, created_at)
      VALUES (@c, @g, @cu, @r, @e, @d, @dt, @o, @rs, @nt, @lat, @lng, @seq, @oc, now_ms())''', {
      'c': d.companyId,
      'g': gid,
      'cu': cust['id'],
      'r': cust['route_id'],
      'e': d.employeeId,
      'd': d.devicePk,
      'dt': _docDate(doc).toIso8601String(),
      'o': outcome,
      'rs': outcome == 'no_sale' ? reason : null,
      'nt': note is String ? note : null,
      'lat': lat is num ? lat.toDouble() : null,
      'lng': lng is num ? lng.toDouble() : null,
      'seq': cust['sequence'],
      'oc': d.deviceId,
    });
    return {'globalId': gid, 'status': 'accepted', 'kind': 'visit', 'outcome': outcome};
  }

  Future<Map<String, Object?>> _acceptCollection(
      Session s, DeviceContext d, String gid, Map<String, Object?> doc) async {
    final cust = await _customerOnRoute(s, d, doc['customerGlobalId']);
    final amount = _num(doc['amount'], 'amount');
    if (amount <= 0) throw DocRejected('invalid_amount');
    final bookGid = doc['bookGlobalId'];
    final leaf = doc['bookNumber'];
    if (bookGid is! String || leaf is! int) throw DocRejected('book_number_required');
    final books = await db.q(s, '''
      SELECT id, prefix, range_from, range_to, next_number, status, holder_employee_id
      FROM voucher_books WHERE company_id=@c AND global_id=@g AND book_type='receipt'
        AND deleted_at IS NULL FOR UPDATE''', {'c': d.companyId, 'g': bookGid});
    if (books.isEmpty) throw DocRejected('book_not_found');
    final b = books.first.toColumnMap();
    if (b['status'] != 'active') throw DocRejected('book_not_active');
    if (b['holder_employee_id'] != d.employeeId) throw DocRejected('book_not_held_by_rep');
    final from = b['range_from'] as int, to = b['range_to'] as int;
    if (leaf < from || leaf > to) throw DocRejected('book_number_out_of_range', '$leaf');
    final cancelled = (await db.q(s,
            'SELECT number FROM voucher_book_leaves_cancelled WHERE book_id=@b', {'b': b['id']}))
        .map((r) => r[0] as int)
        .toSet();
    if (cancelled.contains(leaf)) throw DocRejected('book_leaf_cancelled', '$leaf');
    final used = (await db.q(s,
            'SELECT book_number FROM safe_transactions WHERE book_id=@b', {'b': b['id']}))
        .map((r) => r[0] as int)
        .toSet();
    if (used.contains(leaf)) throw DocRejected('book_leaf_used', '$leaf');

    final rr = await _repResources(s, d.employeeId);
    final voucherNumber = '${b['prefix'] ?? ''}$leaf';
    await db.q(s, '''
      INSERT INTO safe_transactions (company_id, global_id, voucher_number, safe_id, transaction_type,
        category, amount, party_id, employee_id, rep_employee_id, route_id, book_id, book_number,
        reference_type, device_pk, origin_client_id, created_at)
      VALUES (@c, @g, @vn, @sf, 'receipt', 'customer_collection', @a, @p, @e, @e, @r, @b, @n,
        'mobile_collection', @d, @o, now_ms())''', {
      'c': d.companyId,
      'g': gid,
      'vn': voucherNumber,
      'sf': rr.safe,
      'a': amount,
      'p': cust['id'],
      'e': d.employeeId,
      'r': cust['route_id'],
      'b': b['id'],
      'n': leaf,
      'd': d.devicePk,
      'o': d.deviceId,
    });
    await db.q(s, 'UPDATE parties SET balance = balance - @a WHERE id=@id', {'a': amount, 'id': cust['id']});

    // Advance next_number like desktop `_advanceVoucherBook`.
    used.add(leaf);
    int? next;
    for (var i = b['next_number'] as int; i <= to && next == null; i++) {
      if (i >= from && !used.contains(i) && !cancelled.contains(i)) next = i;
    }
    for (var i = from; i <= to && next == null; i++) {
      if (!used.contains(i) && !cancelled.contains(i)) next = i;
    }
    await db.q(s, 'UPDATE voucher_books SET next_number=@n, status=@st WHERE id=@id', {
      'n': next ?? to + 1,
      'st': next == null ? 'closed' : 'active',
      'id': b['id'],
    });

    final newBalance = round2(num0(cust['balance']) - amount);
    await _enqueueWhatsApp(s, d, cust, gid, 'payment_received', [
      cust['name'] as String,
      voucherNumber,
      amount.toStringAsFixed(2),
      newBalance.toStringAsFixed(2),
    ]);
    return {
      'globalId': gid,
      'status': 'accepted',
      'kind': 'collection',
      'number': voucherNumber,
      'customerBalance': newBalance,
    };
  }

  Future<void> _enqueueWhatsApp(Session s, DeviceContext d, Map<String, dynamic> cust, String docGid,
      String template, List<String> params) async {
    final phone = cust['whatsapp_phone'] as String?;
    if (cust['whatsapp_opt_in'] != true || phone == null || phone.isEmpty) return;
    await db.q(s, '''
      INSERT INTO whatsapp_outbox (company_id, party_id, to_phone, template, language, params,
        document_global_id, next_attempt_at, created_at)
      VALUES (@c, @p, @to, @t, 'ar', @pr, @g, now_ms(), now_ms())
      ON CONFLICT (document_global_id, template) DO NOTHING''', {
      'c': d.companyId,
      'p': cust['id'],
      'to': phone,
      't': template,
      'pr': jsonEncode(params),
      'g': docGid,
    });
  }
}
