import 'dart:convert';

import 'package:postgres/postgres.dart';
import 'package:uuid/uuid.dart';

import '../db/database.dart';
import '../domain/integrity.dart';
import '../domain/tax.dart';
import 'errors.dart';

const _uuid = Uuid();

/// Mobile bootstrap / pull (scoped to the rep) and push (idempotent by
/// globalId, validated: route scoping, van stock, credit limit, number lease,
/// voucher-book leaf). See docs/mobile/ARCHITECTURE-I.md §3, §5–§7.
class SyncService {
  SyncService(this.db, {this.pullOverlapMs = 2000});
  final CloudDatabase db;

  /// The watermark handed to clients is `now - overlap` so rows committed
  /// slightly late are re-sent (upsert by globalId on the client is idempotent).
  final int pullOverlapMs;

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

  // ─────────────────────────── bootstrap / pull ───────────────────────────

  Future<Map<String, Object?>> bootstrap(DeviceContext d) async {
    final delta = await pull(d, since: 0);
    final profile = await db.tx((s) async {
      final company = (await db.q(s,
              'SELECT name, tax_number, currency, default_tax_rate FROM companies WHERE id=@c',
              {'c': d.companyId}))
          .first
          .toColumnMap();
      final emp = (await db.q(s, 'SELECT global_id, name FROM employees WHERE id=@e',
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
        },
        'employee': {'globalId': emp['global_id'], 'name': emp['name']},
        'vanWarehouse': r?['wg'] == null ? null : {'globalId': r!['wg'], 'name': r['wn']},
        'custodySafe': r?['sg'] == null ? null : {'globalId': r!['sg'], 'name': r['sn']},
        'routes': [
          for (final x in routes)
            {'globalId': x[0], 'name': x[1], 'visitDays': x[2]},
        ],
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

  Future<int?> _vanWarehouse(Session s, int employeeId) async {
    final r = await db.q(s,
        'SELECT van_warehouse_id FROM rep_resources WHERE employee_id=@e AND deleted_at IS NULL',
        {'e': employeeId});
    return r.isEmpty ? null : r.first[0] as int?;
  }

  /// Delta since [since] (epoch ms). Scope lists (`customerScope`,
  /// `voucherBookScope`) are always complete so the device can drop rows that
  /// left its scope.
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
               is_active, deleted_at
        FROM products WHERE company_id=@c AND last_modified_at > @s ORDER BY id''',
          {'c': d.companyId, 's': since});

      final van = await _vanWarehouse(s, d.employeeId);
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

      final invoices = await db.q(s, '''
        SELECT global_id, invoice_number, status FROM sales_invoices
        WHERE device_pk=@d AND last_modified_at > @s''', {'d': d.devicePk, 's': since});
      final collections = await db.q(s, '''
        SELECT global_id, voucher_number FROM safe_transactions
        WHERE device_pk=@d AND category='customer_collection' AND last_modified_at > @s''',
          {'d': d.devicePk, 's': since});

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
          for (final r in invoices)
            {'globalId': r[0], 'kind': 'sales_invoice', 'number': r[1], 'status': r[2]},
          for (final r in collections)
            {'globalId': r[0], 'kind': 'collection', 'number': r[1], 'status': 'accepted'},
        ],
      };
    });
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
      default:
        throw DocRejected('unsupported_kind', 'kind "$kind" is not accepted in I-1');
    }
    await db.q(s, '''
      INSERT INTO sync_idempotency (company_id, global_id, kind, device_pk, result, created_at)
      VALUES (@c, @g, @k, @d, @r, now_ms())''',
        {'c': d.companyId, 'g': gid, 'k': kind, 'd': d.devicePk, 'r': jsonEncode(result)});
    await db.q(s, '''
      INSERT INTO audit_log (company_id, device_pk, employee_id, action, entity, global_id, at)
      VALUES (@c, @d, @e, 'push_accepted', @k, @g, now_ms())''',
        {'c': d.companyId, 'd': d.devicePk, 'e': d.employeeId, 'k': kind, 'g': gid});
    return result;
  }

  Future<Map<String, dynamic>> _customerOnRoute(Session s, DeviceContext d, Object? customerGid) async {
    if (customerGid is! String) throw DocRejected('invalid_customer');
    final rows = await db.q(s, '$_scopedCustomersSql AND p.global_id=@g LIMIT 1',
        {'c': d.companyId, 'e': d.employeeId, 'g': customerGid});
    if (rows.isEmpty) throw DocRejected('customer_not_on_route');
    // Lock the party row for the balance update.
    final locked = await db.q(s,
        'SELECT id, balance, credit_limit, whatsapp_phone, whatsapp_opt_in, name FROM parties WHERE id=@id FOR UPDATE',
        {'id': rows.first.toColumnMap()['id']});
    return {...locked.first.toColumnMap(), 'route_id': rows.first.toColumnMap()['route_id']};
  }

  double _num(Object? v, String field) {
    if (v is num) return v.toDouble();
    throw DocRejected('invalid_field', field);
  }

  Future<Map<String, Object?>> _acceptInvoice(
      Session s, DeviceContext d, String gid, Map<String, Object?> doc) async {
    // 1. Number must come from this device's lease.
    final number = doc['number'];
    if (number is! String || number.isEmpty) throw DocRejected('invalid_number');
    final leases = await db.q(s, '''
      SELECT id, prefix, range_from, range_to, next_number FROM device_number_leases
      WHERE device_pk=@d AND doc_type='sales_invoice' AND status IN ('active','exhausted')
      FOR UPDATE''', {'d': d.devicePk});
    Map<String, dynamic>? lease;
    int? n;
    for (final l in leases) {
      final m = l.toColumnMap();
      final prefix = m['prefix'] as String;
      if (!number.startsWith(prefix)) continue;
      final v = int.tryParse(number.substring(prefix.length));
      if (v != null && v >= (m['range_from'] as int) && v <= (m['range_to'] as int)) {
        lease = m;
        n = v;
        break;
      }
    }
    if (lease == null || n == null) throw DocRejected('number_out_of_range', number);
    final dup = await db.q(s,
        'SELECT 1 FROM sales_invoices WHERE company_id=@c AND invoice_number=@n',
        {'c': d.companyId, 'n': number});
    if (dup.isNotEmpty) throw DocRejected('number_already_used', number);

    // 2. Customer must be on the rep's route today.
    final cust = await _customerOnRoute(s, d, doc['customerGlobalId']);

    // 3. Van warehouse (stock rule: only the rep's van).
    final van = await _vanWarehouse(s, d.employeeId);
    if (van == null) throw DocRejected('no_van_warehouse');
    final res = await db.q(s,
        'SELECT custody_safe_id FROM rep_resources WHERE employee_id=@e', {'e': d.employeeId});
    final safeId = res.first[0] as int?;

    // 4. Lines + server-side totals (same tax rule as desktop).
    final company = await db.q(s,
        'SELECT default_tax_rate, integrity_secret FROM companies WHERE id=@c', {'c': d.companyId});
    final defaultRate = num0(company.first[0]);
    final rawLines = doc['lines'];
    if (rawLines is! List || rawLines.isEmpty) throw DocRejected('no_lines');
    final lines = <({int productId, LineInput input})>[];
    final qtyByProduct = <int, double>{};
    for (final rl in rawLines) {
      if (rl is! Map) throw DocRejected('invalid_line');
      final pg = rl['productGlobalId'];
      final prod = await db.q(s, '''
        SELECT id, tax_rate, tax_exempt FROM products
        WHERE company_id=@c AND global_id=@g AND is_active AND deleted_at IS NULL''',
          {'c': d.companyId, 'g': pg});
      if (prod.isEmpty) throw DocRejected('unknown_product', '$pg');
      final qty = _num(rl['quantity'], 'quantity');
      final price = _num(rl['unitPrice'], 'unitPrice');
      final disc = rl['discount'] == null ? 0.0 : _num(rl['discount'], 'discount');
      if (qty <= 0 || price < 0 || disc < 0) throw DocRejected('invalid_line');
      final pid = prod.first[0] as int;
      lines.add((
        productId: pid,
        input: LineInput(
          quantity: qty,
          unitPrice: price,
          discount: disc,
          taxRate: effectiveItemTaxRate(
              rate: num0(prod.first[1]), exempt: prod.first[2] == true, companyDefault: defaultRate),
        ),
      ));
      qtyByProduct[pid] = (qtyByProduct[pid] ?? 0) + qty;
    }
    final totals = computeTotals([for (final l in lines) l.input]);
    final clientTotal = doc['total'];
    if (clientTotal is num && (clientTotal - totals.total).abs() > 0.01) {
      throw DocRejected('totals_mismatch', 'server total ${totals.total}', {'serverTotal': totals.total});
    }
    final paid = doc['paid'] == null ? 0.0 : _num(doc['paid'], 'paid');
    if (paid < 0 || paid > totals.total + 0.01) throw DocRejected('invalid_payment');
    final remaining = round2(totals.total - paid);

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
    final date = DateTime.tryParse('${doc['date']}') ?? DateTime.now().toUtc();
    final paymentMethod = remaining <= 0.01 ? 'cash' : (paid > 0 ? 'mixed' : 'credit');
    final secret = company.first[1] as String;
    final hash = signV2(
        secret,
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
        payment_method, integrity_hash, origin_client_id, created_at)
      VALUES (@c, @g, @n, @cu, @w, @sf, @e, @r, @d, @dt, @sub, @disc, @tax, @tot, @paid, @pm, @h, @o, now_ms())
      RETURNING id''', {
      'c': d.companyId,
      'g': gid,
      'n': number,
      'cu': cust['id'],
      'w': van,
      'sf': safeId,
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
        'dc': l.input.discount,
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
    final newBalance = round2(balance + remaining);
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
        'sf': safeId,
        'a': paid,
        'p': cust['id'],
        'e': d.employeeId,
        'r': cust['route_id'],
        'inv': gid,
        'd': d.devicePk,
      });
    }
    final next = n + 1;
    await db.q(s, '''
      UPDATE device_number_leases SET next_number = GREATEST(next_number, @nx),
        status = CASE WHEN GREATEST(next_number, @nx) > range_to THEN 'exhausted' ELSE status END
      WHERE id=@id''', {'nx': next, 'id': lease['id']});

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

    final rr = await db.q(s,
        'SELECT custody_safe_id FROM rep_resources WHERE employee_id=@e', {'e': d.employeeId});
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
      'sf': rr.isEmpty ? null : rr.first[0],
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
