import 'package:picpos_rules/picpos_rules.dart' show normalizeBarcode;
import 'package:postgres/postgres.dart';
import 'package:uuid/uuid.dart';

import '../db/database.dart';
import '../security.dart';
import 'errors.dart';
import 'field_expense_documents.dart';
import 'field_geo.dart';

const _uuid = Uuid();

/// Authenticated desktop link (the company's back-office / main PicPos).
class DesktopContext {
  DesktopContext({required this.linkPk, required this.linkId, required this.companyId, this.ip = 'unknown'});
  final int linkPk;
  final String linkId;
  final int companyId;
  final String ip;
}

/// Desktop ↔ cloud sync (I-3, ARCHITECTURE-I §2, §8):
/// * the desktop authenticates with its own link credential (`X-Desktop-Link`
///   + `Authorization: Bearer <secret>`; only the SHA-256 of the secret is
///   stored);
/// * pushes master data (desktop wins; idempotent upsert by `globalId`,
///   references travel as `*GlobalId`);
/// * reads the accepted field documents it has not posted yet and
///   acknowledges each one (`posted` with its desktop number, or `failed`
///   with the reason — a failed document stays pending, never dropped).
///
/// Customer balances and van stock served to the reps are materialized as
/// `desktop value + accepted field documents not yet posted on desktop`.
class DesktopService {
  DesktopService(this.db);
  final CloudDatabase db;

  int get _now => DateTime.now().millisecondsSinceEpoch;

  // ───────────────────────────── credential ─────────────────────────────

  /// Issues a desktop link credential for [companyGlobalId] (test stack:
  /// `POST /admin/desktop-links`). The secret is returned once.
  Future<Map<String, Object?>> issueLink(String companyGlobalId, {String? name}) async {
    final c = await db.query('SELECT id FROM companies WHERE global_id=@g', {'g': companyGlobalId});
    if (c.isEmpty) throw ApiError(404, 'company_not_found');
    final linkId = _uuid.v4();
    final secret = randomToken();
    await db.query('''
      INSERT INTO desktop_links (company_id, link_id, name, key_hash, created_at)
      VALUES (@c, @l, @n, @h, @t)''',
        {'c': c.first[0], 'l': linkId, 'n': name, 'h': sha256Hex(secret), 't': _now});
    return {'linkId': linkId, 'linkSecret': secret, 'companyGlobalId': companyGlobalId};
  }

  Future<void> revokeLink(String linkId) async {
    final r = await db.query('UPDATE desktop_links SET revoked_at=@n WHERE link_id=@l RETURNING id',
        {'n': _now, 'l': linkId});
    if (r.isEmpty) throw ApiError(404, 'unknown_desktop_link');
  }

  Future<DesktopContext> authenticate(String? bearer, String? linkId, {String ip = 'unknown'}) async {
    if (bearer == null || bearer.isEmpty || linkId == null || linkId.isEmpty) {
      throw ApiError(401, 'missing_desktop_credential');
    }
    final rows = await db.query(
        'SELECT id, company_id, key_hash, revoked_at FROM desktop_links WHERE link_id=@l', {'l': linkId});
    if (rows.isEmpty) throw ApiError(401, 'unknown_desktop_link');
    final r = rows.first.toColumnMap();
    if (!constantTimeEquals(r['key_hash'] as String, sha256Hex(bearer))) {
      throw ApiError(401, 'invalid_desktop_credential');
    }
    if (r['revoked_at'] != null) throw ApiError(401, 'desktop_link_revoked');
    await db.query('UPDATE desktop_links SET last_seen_at=@n, last_seen_ip=@ip WHERE id=@id',
        {'n': _now, 'ip': ip, 'id': r['id']});
    return DesktopContext(linkPk: r['id'] as int, linkId: linkId, companyId: r['company_id'] as int, ip: ip);
  }

  Future<Map<String, Object?>> ping(DesktopContext d) async {
    final c = (await db.query('SELECT global_id, name FROM companies WHERE id=@c', {'c': d.companyId})).first;
    final p = await pendingCounts(d);
    return {
      'company': {'globalId': c[0], 'name': c[1]},
      'serverTime': _now,
      'pending': p,
    };
  }

  Future<Map<String, int>> pendingCounts(DesktopContext d) async {
    final c = {'c': d.companyId};
    Future<int> n(String sql) async => (await db.query(sql, c)).first[0] as int;
    return {
      'sales_invoice': await n(
          'SELECT COUNT(*)::INT FROM sales_invoices WHERE company_id=@c AND posted_on_desktop_at IS NULL'),
      'sales_return': await n(
          'SELECT COUNT(*)::INT FROM sales_returns WHERE company_id=@c AND posted_on_desktop_at IS NULL'),
      'collection': await n("SELECT COUNT(*)::INT FROM safe_transactions WHERE company_id=@c "
          "AND category='customer_collection' AND posted_on_desktop_at IS NULL"),
      'visit': await n(
          'SELECT COUNT(*)::INT FROM customer_visits WHERE company_id=@c AND posted_on_desktop_at IS NULL'),
      'customer': await n(
          'SELECT COUNT(*)::INT FROM field_customers WHERE company_id=@c AND posted_on_desktop_at IS NULL'),
      'expense': await n("SELECT COUNT(*)::INT FROM safe_transactions WHERE company_id=@c "
          "AND category='rep_expense' AND posted_on_desktop_at IS NULL"),
    };
  }

  /// Desktop admin pairing: issues a pairing code for a rep and (optionally)
  /// sets the rep's app PIN (PBKDF2) in the same call.
  Future<Map<String, Object?>> setRepPin(DesktopContext d, String employeeGlobalId, String pin,
      {int iterations = 120000}) async {
    if (!RegExp(r'^\d{4,8}$').hasMatch(pin)) throw ApiError(400, 'invalid_pin_format');
    final r = await db.query(
        'UPDATE employees SET pin_hash=@h WHERE company_id=@c AND global_id=@g RETURNING id',
        {'h': hashPin(pin, iterations: iterations), 'c': d.companyId, 'g': employeeGlobalId});
    if (r.isEmpty) throw ApiError(404, 'employee_not_found');
    return {'employeeGlobalId': employeeGlobalId, 'pinSet': true};
  }

  /// Rep-app devices paired on this company (Settings › Linked devices on the
  /// desktop). Active devices first, most recently seen first.
  Future<List<Map<String, Object?>>> listDevices(DesktopContext d) async {
    final rows = await db.query('''
      SELECT dv.device_id, dv.name, e.global_id, e.name, dv.paired_at, dv.last_seen_at, dv.revoked_at
      FROM devices dv JOIN employees e ON e.id = dv.employee_id
      WHERE dv.company_id=@c
      ORDER BY (dv.revoked_at IS NOT NULL), dv.last_seen_at DESC NULLS LAST, dv.id DESC''', {'c': d.companyId});
    return [
      for (final r in rows)
        {
          'deviceId': r[0],
          'deviceName': r[1],
          'employeeGlobalId': r[2],
          'employeeName': r[3],
          'pairedAt': r[4],
          'lastSeenAt': r[5],
          'revokedAt': r[6],
          'revoked': r[6] != null,
        },
    ];
  }

  // ───────────────────────────── master data ─────────────────────────────

  /// Applies one master-data batch in one transaction. Rows whose references
  /// are unknown are skipped (reported), never half-applied.
  Future<Map<String, Object?>> upsertMaster(DesktopContext d, Map<String, Object?> body) async {
    final applied = <String, int>{};
    final skipped = <Map<String, Object?>>[];
    await db.tx((s) async {
      final ctx = _Upsert(db, s, d.companyId, applied, skipped);
      final company = body['company'];
      if (company is Map) await ctx.company(company.cast<String, Object?>());
      for (final (key, fn) in <(String, Future<void> Function(Map<String, Object?>))>[
        ('employees', ctx.employee),
        ('warehouses', ctx.warehouse),
        ('safes', ctx.safe),
        ('parties', ctx.party),
        ('products', ctx.product),
        ('priceLists', ctx.priceList),
        ('distributionAreas', ctx.area),
        ('salesRoutes', ctx.route),
        ('routeCustomers', ctx.routeCustomer),
        ('repResources', ctx.repResource),
        ('voucherBooks', ctx.voucherBook),
        ('vanStock', ctx.vanStock),
        ('expenseCategories', ctx.expenseCategory),
      ]) {
        final rows = body[key];
        if (rows == null) continue;
        if (rows is! List) throw ApiError(400, 'invalid_entity_list', key);
        for (final row in rows) {
          if (row is! Map) {
            skipped.add({'entity': key, 'reason': 'invalid_row'});
            continue;
          }
          await fn(row.cast<String, Object?>());
        }
      }
    });
    await db.query('''
      INSERT INTO audit_log (company_id, action, entity, ip, detail, at)
      VALUES (@c, 'desktop_master_upsert', 'desktop', @ip, @dt, now_ms())''',
        {'c': d.companyId, 'ip': d.ip, 'dt': '${applied.entries.map((e) => '${e.key}=${e.value}').join(',')}'});
    return {'applied': applied, 'skipped': skipped};
  }

  // ───────────────────────────── field documents ─────────────────────────────

  /// Accepted field documents not yet posted on the desktop, oldest first
  /// (an invoice always precedes its returns).
  Future<Map<String, Object?>> pendingDocuments(DesktopContext d, {int limit = 100}) async {
    final lim = limit.clamp(1, 500);
    final c = {'c': d.companyId, 'l': lim};
    final docs = <Map<String, Object?>>[];

    final invoices = await db.query('''
      SELECT si.id, si.global_id, si.invoice_number, si.invoice_date, si.created_at, p.global_id AS cg,
             e.global_id AS eg, r.global_id AS rg, w.global_id AS wg, sf.global_id AS sg, si.subtotal,
             si.discount, si.tax, si.total, si.paid, si.payment_method, si.prices_include_tax,
             si.integrity_hash, si.origin_client_id, si.desktop_error, si.adhoc_customer_name,
             si.adhoc_customer_phone, si.field_geo
      FROM sales_invoices si
      JOIN parties p ON p.id = si.customer_id
      JOIN employees e ON e.id = si.rep_employee_id
      JOIN warehouses w ON w.id = si.warehouse_id
      LEFT JOIN sales_routes r ON r.id = si.route_id
      LEFT JOIN safes sf ON sf.id = si.safe_id
      WHERE si.company_id=@c AND si.posted_on_desktop_at IS NULL
      ORDER BY si.created_at, si.id LIMIT @l''', c);
    for (final row in invoices) {
      final m = row.toColumnMap();
      final lines = await db.query('''
        SELECT pr.global_id, i.quantity, i.unit_price, i.discount, i.tax_rate, i.tax_amount, i.total
        FROM sales_invoice_items i JOIN products pr ON pr.id = i.product_id
        WHERE i.invoice_id=@i ORDER BY i.id''', {'i': m['id']});
      docs.add({
        'kind': 'sales_invoice',
        'globalId': m['global_id'],
        'number': m['invoice_number'],
        'date': m['invoice_date'],
        'createdAt': m['created_at'],
        'customerGlobalId': m['cg'],
        // J3 — one-time name/phone of a cash-customer sale (printed instead).
        if (m['adhoc_customer_name'] != null) 'customerName': m['adhoc_customer_name'],
        if (m['adhoc_customer_phone'] != null) 'customerPhone': m['adhoc_customer_phone'],
        'repEmployeeGlobalId': m['eg'],
        'routeGlobalId': m['rg'],
        'warehouseGlobalId': m['wg'],
        'safeGlobalId': m['sg'],
        'subtotal': num0(m['subtotal']),
        'discount': num0(m['discount']),
        'tax': num0(m['tax']),
        'total': num0(m['total']),
        'paid': num0(m['paid']),
        'paymentMethod': m['payment_method'],
        'pricesIncludeTax': m['prices_include_tax'] == true,
        'integrityHash': m['integrity_hash'],
        'deviceId': m['origin_client_id'],
        'geo': decodeFieldGeo(m['field_geo']),
        'lastDesktopError': m['desktop_error'],
        'lines': [
          for (final l in lines)
            {
              'productGlobalId': l[0],
              'quantity': num0(l[1]),
              'unitPrice': num0(l[2]),
              'discount': num0(l[3]),
              'taxRate': num0(l[4]),
              'taxAmount': num0(l[5]),
              'total': num0(l[6]),
            },
        ],
      });
    }

    final returns = await db.query('''
      SELECT sr.id, sr.global_id, sr.return_number, sr.return_date, sr.created_at, si.global_id AS ig,
             p.global_id AS cg, e.global_id AS eg, r.global_id AS rg, w.global_id AS wg, sf.global_id AS sg,
             sr.subtotal, sr.tax, sr.total, sr.ar_offset, sr.cash_refund, sr.reason, sr.desktop_error,
             sr.field_geo
      FROM sales_returns sr
      JOIN sales_invoices si ON si.id = sr.original_invoice_id
      JOIN parties p ON p.id = sr.customer_id
      JOIN employees e ON e.id = sr.rep_employee_id
      JOIN warehouses w ON w.id = sr.warehouse_id
      LEFT JOIN sales_routes r ON r.id = sr.route_id
      LEFT JOIN safes sf ON sf.id = sr.safe_id
      WHERE sr.company_id=@c AND sr.posted_on_desktop_at IS NULL
      ORDER BY sr.created_at, sr.id LIMIT @l''', c);
    for (final row in returns) {
      final m = row.toColumnMap();
      final lines = await db.query('''
        SELECT pr.global_id, i.quantity, i.unit_price, i.tax_amount, i.total
        FROM sales_return_items i JOIN products pr ON pr.id = i.product_id
        WHERE i.return_id=@i ORDER BY i.id''', {'i': m['id']});
      docs.add({
        'kind': 'sales_return',
        'globalId': m['global_id'],
        'number': m['return_number'],
        'date': m['return_date'],
        'createdAt': m['created_at'],
        'originalInvoiceGlobalId': m['ig'],
        'customerGlobalId': m['cg'],
        'repEmployeeGlobalId': m['eg'],
        'routeGlobalId': m['rg'],
        'warehouseGlobalId': m['wg'],
        'safeGlobalId': m['sg'],
        'subtotal': num0(m['subtotal']),
        'tax': num0(m['tax']),
        'total': num0(m['total']),
        'arOffset': num0(m['ar_offset']),
        'cashRefund': num0(m['cash_refund']),
        'reason': m['reason'],
        'geo': decodeFieldGeo(m['field_geo']),
        'lastDesktopError': m['desktop_error'],
        'lines': [
          for (final l in lines)
            {
              'productGlobalId': l[0],
              'quantity': num0(l[1]),
              'unitPrice': num0(l[2]),
              'taxAmount': num0(l[3]),
              'total': num0(l[4]),
            },
        ],
      });
    }

    final collections = await db.query('''
      SELECT st.global_id, st.voucher_number, st.created_at, p.global_id AS cg, e.global_id AS eg,
             r.global_id AS rg, sf.global_id AS sg, st.amount, b.global_id AS bg, st.book_number,
             st.desktop_error, st.field_geo
      FROM safe_transactions st
      JOIN parties p ON p.id = st.party_id
      JOIN employees e ON e.id = st.rep_employee_id
      LEFT JOIN sales_routes r ON r.id = st.route_id
      LEFT JOIN safes sf ON sf.id = st.safe_id
      LEFT JOIN voucher_books b ON b.id = st.book_id
      WHERE st.company_id=@c AND st.category='customer_collection' AND st.posted_on_desktop_at IS NULL
      ORDER BY st.created_at, st.id LIMIT @l''', c);
    for (final row in collections) {
      final m = row.toColumnMap();
      docs.add({
        'kind': 'collection',
        'globalId': m['global_id'],
        'number': m['voucher_number'],
        'date': DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int, isUtc: true).toIso8601String(),
        'createdAt': m['created_at'],
        'customerGlobalId': m['cg'],
        'repEmployeeGlobalId': m['eg'],
        'routeGlobalId': m['rg'],
        'safeGlobalId': m['sg'],
        'amount': num0(m['amount']),
        'bookGlobalId': m['bg'],
        'bookNumber': m['book_number'],
        'geo': decodeFieldGeo(m['field_geo']),
        'lastDesktopError': m['desktop_error'],
      });
    }

    docs.addAll(await pendingExpenseDocuments(db, d.companyId, lim));

    final visits = await db.query('''
      SELECT v.global_id, v.visit_date, v.created_at, p.global_id AS cg, e.global_id AS eg,
             r.global_id AS rg, v.outcome, v.no_sale_reason, v.note, v.latitude, v.longitude, v.sequence,
             v.desktop_error, v.field_geo
      FROM customer_visits v
      JOIN parties p ON p.id = v.customer_id
      JOIN employees e ON e.id = v.rep_employee_id
      LEFT JOIN sales_routes r ON r.id = v.route_id
      WHERE v.company_id=@c AND v.posted_on_desktop_at IS NULL
      ORDER BY v.created_at, v.id LIMIT @l''', c);
    for (final row in visits) {
      final m = row.toColumnMap();
      docs.add({
        'kind': 'visit',
        'globalId': m['global_id'],
        'date': m['visit_date'],
        'createdAt': m['created_at'],
        'customerGlobalId': m['cg'],
        'repEmployeeGlobalId': m['eg'],
        'routeGlobalId': m['rg'],
        'outcome': m['outcome'],
        'noSaleReason': m['no_sale_reason'],
        'note': m['note'],
        'latitude': m['latitude'],
        'longitude': m['longitude'],
        'sequence': m['sequence'],
        'geo': decodeFieldGeo(m['field_geo']),
        'lastDesktopError': m['desktop_error'],
      });
    }

    // J3 — customers created in the field («حفظ كعميل دائم»): posted before
    // the documents that reference them.
    final customers = await db.query('''
      SELECT fc.global_id, fc.created_at, p.name, p.phone, p.address, e.global_id AS eg,
             r.global_id AS rg, rc.global_id AS rcg, rc.sequence, fc.desktop_error
      FROM field_customers fc
      JOIN parties p ON p.id = fc.party_id
      JOIN employees e ON e.id = fc.rep_employee_id
      LEFT JOIN route_customers rc ON rc.id = fc.route_customer_id
      LEFT JOIN sales_routes r ON r.id = rc.route_id
      WHERE fc.company_id=@c AND fc.posted_on_desktop_at IS NULL
      ORDER BY fc.created_at, fc.id LIMIT @l''', c);
    for (final row in customers) {
      final m = row.toColumnMap();
      docs.add({
        'kind': 'customer',
        'globalId': m['global_id'],
        'createdAt': m['created_at'],
        'name': m['name'],
        'phone': m['phone'],
        'address': m['address'],
        'repEmployeeGlobalId': m['eg'],
        'routeGlobalId': m['rg'],
        'routeCustomerGlobalId': m['rcg'],
        'sequence': m['sequence'],
        'lastDesktopError': m['desktop_error'],
      });
    }

    // Creation order across kinds; an invoice sorts before its returns, a
    // field customer before anything sold to it.
    const rank = {'customer': -1, 'sales_invoice': 0, 'collection': 1, 'sales_return': 2, 'expense': 3, 'visit': 4};
    docs.sort((a, b) {
      final t = (a['createdAt'] as int).compareTo(b['createdAt'] as int);
      return t != 0 ? t : rank[a['kind']]!.compareTo(rank[b['kind']]!);
    });
    return {'documents': docs, 'serverTime': _now};
  }

  static const _ackTables = {
    'sales_invoice': ('sales_invoices', ''),
    'sales_return': ('sales_returns', ''),
    'collection': ('safe_transactions', " AND category='customer_collection'"),
    'visit': ('customer_visits', ''),
    'customer': ('field_customers', ''),
    'expense': ('safe_transactions', " AND category='rep_expense'"),
  };

  /// Records the desktop outcome per document. `posted` is final (a second
  /// ack keeps the first desktop number); `failed` keeps the doc pending.
  Future<List<Map<String, Object?>>> ack(DesktopContext d, List<Object?> results) async {
    final out = <Map<String, Object?>>[];
    for (final raw in results) {
      if (raw is! Map) {
        out.add({'status': 'invalid'});
        continue;
      }
      final m = raw.cast<String, Object?>();
      final t = _ackTables[m['kind']];
      final gid = m['globalId'];
      if (t == null || gid is! String) {
        out.add({'globalId': gid, 'status': 'invalid'});
        continue;
      }
      final (table, extra) = t;
      final hasNumber = table != 'customer_visits';
      final Result r;
      if (m['status'] == 'posted') {
        r = await db.query('''
          UPDATE $table SET posted_on_desktop_at = now_ms(), desktop_id = @id,
            ${hasNumber ? 'desktop_number = @n,' : ''} desktop_error = NULL
          WHERE company_id=@c AND global_id=@g AND posted_on_desktop_at IS NULL$extra
          RETURNING id''', {
          'id': m['desktopId']?.toString(),
          if (hasNumber) 'n': m['desktopNumber']?.toString(),
          'c': d.companyId,
          'g': gid,
        });
        if (r.isEmpty) {
          final exists = await db.query(
              'SELECT 1 FROM $table WHERE company_id=@c AND global_id=@g$extra', {'c': d.companyId, 'g': gid});
          out.add({'globalId': gid, 'status': exists.isEmpty ? 'unknown' : 'already_posted'});
          continue;
        }
      } else if (m['status'] == 'failed') {
        r = await db.query('''
          UPDATE $table SET desktop_error = @e
          WHERE company_id=@c AND global_id=@g AND posted_on_desktop_at IS NULL$extra RETURNING id''',
            {'e': '${m['reason'] ?? 'failed'}', 'c': d.companyId, 'g': gid});
        if (r.isEmpty) {
          out.add({'globalId': gid, 'status': 'unknown'});
          continue;
        }
      } else {
        out.add({'globalId': gid, 'status': 'invalid'});
        continue;
      }
      await db.query('''
        INSERT INTO audit_log (company_id, action, entity, global_id, ip, detail, at)
        VALUES (@c, @a, @k, @g, @ip, @dt, now_ms())''', {
        'c': d.companyId,
        'a': m['status'] == 'posted' ? 'desktop_posted' : 'desktop_failed',
        'k': m['kind'],
        'g': gid,
        'ip': d.ip,
        'dt': m['status'] == 'posted' ? m['desktopNumber']?.toString() : m['reason']?.toString(),
      });
      out.add({'globalId': gid, 'status': m['status'] == 'posted' ? 'posted' : 'failed_recorded'});
    }
    return out;
  }
}

/// One master-data batch inside a transaction.
class _Upsert {
  _Upsert(this.db, this.s, this.companyId, this.applied, this.skipped);
  final CloudDatabase db;
  final Session s;
  final int companyId;
  final Map<String, int> applied;
  final List<Map<String, Object?>> skipped;

  Future<Result> q(String sql, Map<String, Object?> p) => db.q(s, sql, {'c': companyId, ...p});

  void _ok(String entity) => applied[entity] = (applied[entity] ?? 0) + 1;
  void _skip(String entity, Object? gid, String reason) =>
      skipped.add({'entity': entity, 'globalId': gid, 'reason': reason});

  static final _uuidRe = RegExp(r'^[0-9a-fA-F-]{8,64}$');

  String? _gid(String entity, Map<String, Object?> m, [String key = 'globalId']) {
    final g = m[key];
    if (g is String && _uuidRe.hasMatch(g)) return g;
    _skip(entity, g, 'invalid_global_id');
    return null;
  }

  Future<int?> _ref(String table, Object? gid) async {
    if (gid is! String) return null;
    final r = await q('SELECT id FROM $table WHERE company_id=@c AND global_id=@g', {'g': gid});
    return r.isEmpty ? null : r.first[0] as int;
  }

  double _n(Object? v, [double fallback = 0]) => v is num ? v.toDouble() : fallback;
  bool _b(Object? v, [bool fallback = false]) => v is bool ? v : fallback;
  String? _str(Object? v) => v is String && v.trim().isNotEmpty ? v.trim() : null;

  /// Runs [sql] (an `INSERT … ON CONFLICT (global_id) DO UPDATE … WHERE
  /// <table>.company_id = @c RETURNING id`); a row of another company → skip.
  Future<int?> _write(String entity, String gid, String sql, Map<String, Object?> p) async {
    final r = await q(sql, {'g': gid, ...p});
    if (r.isEmpty) {
      _skip(entity, gid, 'global_id_conflict');
      return null;
    }
    _ok(entity);
    return r.first[0] as int;
  }

  Future<void> company(Map<String, Object?> m) async {
    await q('''
      UPDATE companies SET name = COALESCE(@n, name), tax_number = @tn, currency = COALESCE(@cur, currency),
        default_tax_rate = @tr, prices_include_tax = @pit, decimal_places = @dp,
        name_en = CASE WHEN CAST(@hasNe AS BOOLEAN) THEN CAST(@ne AS TEXT) ELSE name_en END,
        commercial_register = CASE WHEN CAST(@hasCr AS BOOLEAN) THEN CAST(@cr AS TEXT) ELSE commercial_register END,
        address = CASE WHEN CAST(@hasAd AS BOOLEAN) THEN CAST(@ad AS TEXT) ELSE address END,
        phone = CASE WHEN CAST(@hasPh AS BOOLEAN) THEN CAST(@ph AS TEXT) ELSE phone END,
        einvoice_enabled = CASE WHEN CAST(@hasEi AS BOOLEAN) THEN CAST(@ei AS BOOLEAN) ELSE einvoice_enabled END,
        expense_over_custody = COALESCE(CAST(@eoc AS TEXT), expense_over_custody)
      WHERE id=@c''', {
      // K-1: 'flag' (default) or 'reject' an expense beyond the custody balance.
      'eoc': m['expenseOverCustody'] == 'reject' || m['expenseOverCustody'] == 'flag' ? m['expenseOverCustody'] : null,
      'n': _str(m['name']),
      'tn': _str(m['taxNumber']),
      // Printed identity (I-4): only overwritten when the desktop sends the key.
      'hasNe': m.containsKey('nameEn'),
      'ne': _str(m['nameEn']),
      'hasCr': m.containsKey('commercialRegister'),
      'cr': _str(m['commercialRegister']),
      'hasAd': m.containsKey('address'),
      'ad': _str(m['address']),
      'hasPh': m.containsKey('phone'),
      'ph': _str(m['phone']),
      'hasEi': m.containsKey('eInvoiceEnabled'),
      'ei': _b(m['eInvoiceEnabled']),
      'cur': _str(m['currency']),
      'tr': _n(m['defaultTaxRate']),
      'pit': _b(m['pricesIncludeTax']),
      'dp': (m['decimalPlaces'] is int) ? m['decimalPlaces'] : 2,
    });
    _ok('company');
  }

  Future<void> employee(Map<String, Object?> m) async {
    final g = _gid('employees', m);
    if (g == null) return;
    final name = _str(m['name']);
    if (name == null) return _skip('employees', g, 'name_required');
    await _write('employees', g, '''
      INSERT INTO employees (company_id, global_id, name, phone, is_active, deleted_at)
      VALUES (@c, @g, @n, @ph, @a, @del)
      ON CONFLICT (global_id) DO UPDATE SET name=EXCLUDED.name, phone=EXCLUDED.phone,
        is_active=EXCLUDED.is_active, deleted_at=EXCLUDED.deleted_at
      WHERE employees.company_id = EXCLUDED.company_id RETURNING id''', {
      'n': name,
      'ph': _str(m['phone']),
      'a': _b(m['isActive'], true) && m['deleted'] != true,
      'del': m['deleted'] == true ? DateTime.now().millisecondsSinceEpoch : null,
    });
  }

  Future<void> warehouse(Map<String, Object?> m) async {
    final g = _gid('warehouses', m);
    if (g == null) return;
    await _write('warehouses', g, '''
      INSERT INTO warehouses (company_id, global_id, name, type, deleted_at) VALUES (@c, @g, @n, @t, @del)
      ON CONFLICT (global_id) DO UPDATE SET name=EXCLUDED.name, type=EXCLUDED.type, deleted_at=EXCLUDED.deleted_at
      WHERE warehouses.company_id = EXCLUDED.company_id RETURNING id''', {
      'n': _str(m['name']) ?? '-',
      't': _str(m['type']) ?? 'main',
      'del': m['deleted'] == true ? DateTime.now().millisecondsSinceEpoch : null,
    });
  }

  Future<void> safe(Map<String, Object?> m) async {
    final g = _gid('safes', m);
    if (g == null) return;
    // K-1: `balance` = the desktop ledger balance of the safe (custody check);
    // kept when the desktop does not send it.
    await _write('safes', g, '''
      INSERT INTO safes (company_id, global_id, name, deleted_at, desktop_balance) VALUES (@c, @g, @n, @del, @bal)
      ON CONFLICT (global_id) DO UPDATE SET name=EXCLUDED.name, deleted_at=EXCLUDED.deleted_at,
        desktop_balance=COALESCE(EXCLUDED.desktop_balance, safes.desktop_balance)
      WHERE safes.company_id = EXCLUDED.company_id RETURNING id''', {
      'n': _str(m['name']) ?? '-',
      'del': m['deleted'] == true ? DateTime.now().millisecondsSinceEpoch : null,
      'bal': m['balance'] is num ? (m['balance'] as num).toDouble() : null,
    });
  }

  /// K-1: rep expense category (desktop list mapped to expense accounts; the
  /// account itself stays on the desktop).
  Future<void> expenseCategory(Map<String, Object?> m) async {
    final g = _gid('expenseCategories', m);
    if (g == null) return;
    final name = _str(m['name']);
    if (name == null) return _skip('expenseCategories', g, 'name_required');
    await _write('expenseCategories', g, '''
      INSERT INTO expense_categories (company_id, global_id, name, name_en, sort_order, is_active, deleted_at)
      VALUES (@c, @g, @n, @ne, @so, @a, @del)
      ON CONFLICT (global_id) DO UPDATE SET name=EXCLUDED.name, name_en=EXCLUDED.name_en,
        sort_order=EXCLUDED.sort_order, is_active=EXCLUDED.is_active, deleted_at=EXCLUDED.deleted_at
      WHERE expense_categories.company_id = EXCLUDED.company_id RETURNING id''', {
      'n': name,
      'ne': _str(m['nameEn']),
      'so': m['sortOrder'] is int ? m['sortOrder'] : 0,
      'a': _b(m['isActive'], true),
      'del': m['deleted'] == true ? DateTime.now().millisecondsSinceEpoch : null,
    });
  }

  /// Customer: the pushed balance is the desktop ledger balance; the served
  /// balance adds this customer's accepted field docs not yet posted.
  Future<void> party(Map<String, Object?> m) async {
    final g = _gid('parties', m);
    if (g == null) return;
    final name = _str(m['name']);
    if (name == null) return _skip('parties', g, 'name_required');
    // J3 — the system cash customer: one row per company holds the role.
    final systemRole = _str(m['systemRole']);
    if (systemRole != null) {
      await q('UPDATE parties SET system_role = NULL WHERE company_id=@c AND system_role=@sr AND global_id<>@g',
          {'sr': systemRole, 'g': g});
    }
    final id = await _write('parties', g, '''
      INSERT INTO parties (company_id, global_id, name, phone, whatsapp_phone, whatsapp_opt_in, credit_limit,
        price_level, is_customer, desktop_balance, balance, deleted_at, system_role)
      VALUES (@c, @g, @n, @ph, @wa, @opt, @cl, @pl, @isc, @bal, @bal, @del, @sr)
      ON CONFLICT (global_id) DO UPDATE SET name=EXCLUDED.name, phone=EXCLUDED.phone,
        whatsapp_phone=EXCLUDED.whatsapp_phone, whatsapp_opt_in=EXCLUDED.whatsapp_opt_in,
        credit_limit=EXCLUDED.credit_limit, price_level=EXCLUDED.price_level, is_customer=EXCLUDED.is_customer,
        desktop_balance=EXCLUDED.desktop_balance, deleted_at=EXCLUDED.deleted_at,
        system_role=EXCLUDED.system_role
      WHERE parties.company_id = EXCLUDED.company_id RETURNING id''', {
      'sr': systemRole,
      'n': name,
      'ph': _str(m['phone']),
      'wa': _str(m['whatsappPhone']),
      'opt': _b(m['whatsappOptIn']),
      'cl': _n(m['creditLimit']),
      'pl': _str(m['priceLevel']),
      'isc': _b(m['isCustomer'], true),
      'bal': _n(m['balance']),
      'del': m['deleted'] == true ? DateTime.now().millisecondsSinceEpoch : null,
    });
    if (id == null) return;
    await q('''
      UPDATE parties SET balance = desktop_balance
        + COALESCE((SELECT SUM(total - paid) FROM sales_invoices
                    WHERE customer_id=@id AND posted_on_desktop_at IS NULL), 0)
        - COALESCE((SELECT SUM(ar_offset) FROM sales_returns
                    WHERE customer_id=@id AND posted_on_desktop_at IS NULL), 0)
        - COALESCE((SELECT SUM(amount) FROM safe_transactions WHERE party_id=@id
                    AND category='customer_collection' AND posted_on_desktop_at IS NULL), 0)
      WHERE id=@id AND company_id=@c''', {'id': id});
  }

  Future<void> product(Map<String, Object?> m) async {
    final g = _gid('products', m);
    if (g == null) return;
    final name = _str(m['name']);
    if (name == null) return _skip('products', g, 'name_required');
    await _write('products', g, '''
      INSERT INTO products (company_id, global_id, name, name_en, barcode, unit_name, sale_price, wholesale_price,
        tax_rate, tax_exempt, is_active, deleted_at)
      VALUES (@c, @g, @n, @ne, @bc, @u, @sp, @wp, @tr, @te, @a, @del)
      ON CONFLICT (global_id) DO UPDATE SET name=EXCLUDED.name, name_en=EXCLUDED.name_en, barcode=EXCLUDED.barcode,
        unit_name=EXCLUDED.unit_name, sale_price=EXCLUDED.sale_price, wholesale_price=EXCLUDED.wholesale_price,
        tax_rate=EXCLUDED.tax_rate, tax_exempt=EXCLUDED.tax_exempt, is_active=EXCLUDED.is_active,
        deleted_at=EXCLUDED.deleted_at
      WHERE products.company_id = EXCLUDED.company_id RETURNING id''', {
      'n': name,
      'ne': _str(m['nameEn']),
      'bc': _str(m['barcode'] is String ? normalizeBarcode(m['barcode'] as String) : null),
      'u': _str(m['unitName']),
      'sp': _n(m['salePrice']),
      'wp': m['wholesalePrice'] is num && (m['wholesalePrice'] as num) > 0 ? _n(m['wholesalePrice']) : null,
      'tr': _n(m['taxRate']),
      'te': _b(m['taxExempt']),
      'a': _b(m['isActive'], true),
      'del': m['deleted'] == true ? DateTime.now().millisecondsSinceEpoch : null,
    });
  }

  /// Price list with its complete item set (items absent from the set are
  /// soft-deleted).
  Future<void> priceList(Map<String, Object?> m) async {
    final g = _gid('priceLists', m);
    if (g == null) return;
    final id = await _write('priceLists', g, '''
      INSERT INTO price_lists (company_id, global_id, name, code, is_default, start_date, end_date, is_active, deleted_at)
      VALUES (@c, @g, @n, @code, @def, @sd::DATE, @ed::DATE, @a, @del)
      ON CONFLICT (global_id) DO UPDATE SET name=EXCLUDED.name, code=EXCLUDED.code, is_default=EXCLUDED.is_default,
        start_date=EXCLUDED.start_date, end_date=EXCLUDED.end_date, is_active=EXCLUDED.is_active,
        deleted_at=EXCLUDED.deleted_at
      WHERE price_lists.company_id = EXCLUDED.company_id RETURNING id''', {
      'n': _str(m['name']) ?? '-',
      'code': _str(m['code']),
      'def': _b(m['isDefault']),
      'sd': _date(m['startDate']),
      'ed': _date(m['endDate']),
      'a': _b(m['isActive'], true),
      'del': m['deleted'] == true ? DateTime.now().millisecondsSinceEpoch : null,
    });
    if (id == null) return;
    final items = m['items'];
    if (items is! List) return;
    final keep = <String>[];
    for (final raw in items) {
      if (raw is! Map) continue;
      final it = raw.cast<String, Object?>();
      final ig = _gid('priceListItems', it);
      if (ig == null) continue;
      final pid = await _ref('products', it['productGlobalId']);
      if (pid == null) {
        _skip('priceListItems', ig, 'unknown_product');
        continue;
      }
      final w = await _write('priceListItems', ig, '''
        INSERT INTO price_list_items (company_id, global_id, price_list_id, product_id, price, min_quantity, max_discount)
        VALUES (@c, @g, @l, @p, @pr, @mq, @md)
        ON CONFLICT (global_id) DO UPDATE SET price_list_id=EXCLUDED.price_list_id, product_id=EXCLUDED.product_id,
          price=EXCLUDED.price, min_quantity=EXCLUDED.min_quantity, max_discount=EXCLUDED.max_discount,
          deleted_at=NULL
        WHERE price_list_items.company_id = EXCLUDED.company_id RETURNING id''', {
        'l': id,
        'p': pid,
        'pr': _n(it['price']),
        'mq': _n(it['minQuantity'], 1),
        'md': _n(it['maxDiscount']),
      });
      if (w != null) keep.add(ig);
    }
    await q('''
      UPDATE price_list_items SET deleted_at = now_ms()
      WHERE company_id=@c AND price_list_id=@l AND deleted_at IS NULL AND NOT (global_id = ANY(@k::TEXT[]))''',
        {'l': id, 'k': keep});
  }

  static String? _date(Object? v) {
    if (v is! String || v.isEmpty) return null;
    final d = DateTime.tryParse(v);
    if (d == null) return null;
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  Future<void> area(Map<String, Object?> m) async {
    final g = _gid('distributionAreas', m);
    if (g == null) return;
    await _write('distributionAreas', g, '''
      INSERT INTO distribution_areas (company_id, global_id, name, is_active, deleted_at) VALUES (@c, @g, @n, @a, @del)
      ON CONFLICT (global_id) DO UPDATE SET name=EXCLUDED.name, is_active=EXCLUDED.is_active, deleted_at=EXCLUDED.deleted_at
      WHERE distribution_areas.company_id = EXCLUDED.company_id RETURNING id''', {
      'n': _str(m['name']) ?? '-',
      'a': _b(m['isActive'], true),
      'del': m['deleted'] == true ? DateTime.now().millisecondsSinceEpoch : null,
    });
  }

  Future<void> route(Map<String, Object?> m) async {
    final g = _gid('salesRoutes', m);
    if (g == null) return;
    final rep = await _ref('employees', m['salesRepGlobalId']);
    if (m['salesRepGlobalId'] != null && rep == null) return _skip('salesRoutes', g, 'unknown_employee');
    await _write('salesRoutes', g, '''
      INSERT INTO sales_routes (company_id, global_id, name, sales_rep_id, area_id, visit_days, is_active, deleted_at)
      VALUES (@c, @g, @n, @e, @ar, @vd, @a, @del)
      ON CONFLICT (global_id) DO UPDATE SET name=EXCLUDED.name, sales_rep_id=EXCLUDED.sales_rep_id,
        area_id=EXCLUDED.area_id, visit_days=EXCLUDED.visit_days, is_active=EXCLUDED.is_active,
        deleted_at=EXCLUDED.deleted_at
      WHERE sales_routes.company_id = EXCLUDED.company_id RETURNING id''', {
      'n': _str(m['name']) ?? '-',
      'e': rep,
      'ar': await _ref('distribution_areas', m['areaGlobalId']),
      'vd': _str(m['visitDays']),
      'a': _b(m['isActive'], true),
      'del': m['deleted'] == true ? DateTime.now().millisecondsSinceEpoch : null,
    });
  }

  Future<void> routeCustomer(Map<String, Object?> m) async {
    final g = _gid('routeCustomers', m);
    if (g == null) return;
    final route = await _ref('sales_routes', m['routeGlobalId']);
    final cust = await _ref('parties', m['customerGlobalId']);
    if (route == null || cust == null) return _skip('routeCustomers', g, 'unknown_route_or_customer');
    await _write('routeCustomers', g, '''
      INSERT INTO route_customers (company_id, global_id, route_id, customer_id, sequence, effective_from,
        effective_to, deleted_at)
      VALUES (@c, @g, @r, @cu, @sq, COALESCE(@ef::DATE, DATE '2000-01-01'), @et::DATE, @del)
      ON CONFLICT (global_id) DO UPDATE SET route_id=EXCLUDED.route_id, customer_id=EXCLUDED.customer_id,
        sequence=EXCLUDED.sequence, effective_from=EXCLUDED.effective_from, effective_to=EXCLUDED.effective_to,
        deleted_at=EXCLUDED.deleted_at
      WHERE route_customers.company_id = EXCLUDED.company_id RETURNING id''', {
      'r': route,
      'cu': cust,
      'sq': m['sequence'] is int ? m['sequence'] : 0,
      'ef': _date(m['effectiveFrom']),
      'et': _date(m['effectiveTo']),
      'del': m['deleted'] == true ? DateTime.now().millisecondsSinceEpoch : null,
    });
  }

  Future<void> repResource(Map<String, Object?> m) async {
    final g = _gid('repResources', m);
    if (g == null) return;
    final emp = await _ref('employees', m['employeeGlobalId']);
    if (emp == null) return _skip('repResources', g, 'unknown_employee');
    final van = await _ref('warehouses', m['vanWarehouseGlobalId']);
    final safe = await _ref('safes', m['custodySafeGlobalId']);
    // One resource row per employee: a re-keyed desktop row replaces it.
    await q('DELETE FROM rep_resources WHERE company_id=@c AND employee_id=@e AND global_id<>@g',
        {'e': emp, 'g': g});
    await _write('repResources', g, '''
      INSERT INTO rep_resources (company_id, global_id, employee_id, van_warehouse_id, custody_safe_id, deleted_at)
      VALUES (@c, @g, @e, @w, @s, @del)
      ON CONFLICT (global_id) DO UPDATE SET employee_id=EXCLUDED.employee_id,
        van_warehouse_id=EXCLUDED.van_warehouse_id, custody_safe_id=EXCLUDED.custody_safe_id,
        deleted_at=EXCLUDED.deleted_at
      WHERE rep_resources.company_id = EXCLUDED.company_id RETURNING id''', {
      'e': emp,
      'w': van,
      's': safe,
      'del': m['deleted'] == true ? DateTime.now().millisecondsSinceEpoch : null,
    });
  }

  /// Voucher book. `nextNumber` never moves backwards (leaves used in the
  /// field and not yet posted on desktop stay used); cancelled leaves merge.
  Future<void> voucherBook(Map<String, Object?> m) async {
    final g = _gid('voucherBooks', m);
    if (g == null) return;
    final from = m['rangeFrom'], to = m['rangeTo'];
    if (from is! int || to is! int || to < from) return _skip('voucherBooks', g, 'invalid_range');
    final holder = await _ref('employees', m['holderEmployeeGlobalId']);
    final next = m['nextNumber'] is int ? m['nextNumber'] as int : from;
    final status = _str(m['status']) ?? 'active';
    final id = await _write('voucherBooks', g, '''
      INSERT INTO voucher_books (company_id, global_id, book_type, prefix, label, range_from, range_to, next_number,
        holder_employee_id, status, deleted_at)
      VALUES (@c, @g, @bt, @p, @lb, @f, @t, @nx, @h, @st, @del)
      ON CONFLICT (global_id) DO UPDATE SET book_type=EXCLUDED.book_type, prefix=EXCLUDED.prefix,
        label=EXCLUDED.label, range_from=EXCLUDED.range_from, range_to=EXCLUDED.range_to,
        next_number=GREATEST(voucher_books.next_number, EXCLUDED.next_number),
        holder_employee_id=EXCLUDED.holder_employee_id,
        status=CASE WHEN voucher_books.status='closed' AND EXCLUDED.status='active'
                    AND voucher_books.next_number > EXCLUDED.range_to THEN 'closed' ELSE EXCLUDED.status END,
        deleted_at=EXCLUDED.deleted_at
      WHERE voucher_books.company_id = EXCLUDED.company_id RETURNING id''', {
      'bt': _str(m['bookType']) ?? 'receipt',
      'p': _str(m['prefix']),
      'lb': _str(m['label']),
      'f': from,
      't': to,
      'nx': next,
      'h': holder,
      'st': status,
      'del': m['deleted'] == true ? DateTime.now().millisecondsSinceEpoch : null,
    });
    if (id == null) return;
    final cancelled = m['cancelledNumbers'];
    if (cancelled is List) {
      for (final n in cancelled.whereType<int>()) {
        await db.q(s, '''
          INSERT INTO voucher_book_leaves_cancelled (book_id, number, reason, cancelled_at)
          VALUES (@b, @n, 'desktop', now_ms()) ON CONFLICT (book_id, number) DO NOTHING''', {'b': id, 'n': n});
      }
    }
  }

  /// Van stock: desktop quantity minus field sales not yet posted plus field
  /// returns not yet posted.
  Future<void> vanStock(Map<String, Object?> m) async {
    final w = await _ref('warehouses', m['warehouseGlobalId']);
    final p = await _ref('products', m['productGlobalId']);
    if (w == null || p == null) {
      _skip('vanStock', '${m['warehouseGlobalId']}/${m['productGlobalId']}', 'unknown_warehouse_or_product');
      return;
    }
    final qty = _n(m['quantity']);
    await q('''
      INSERT INTO inventory_balances (company_id, global_id, product_id, warehouse_id, quantity, desktop_quantity)
      VALUES (@c, @g, @p, @w, @q, @q)
      ON CONFLICT (product_id, warehouse_id) DO UPDATE SET desktop_quantity = EXCLUDED.desktop_quantity''',
        {'g': _uuid.v4(), 'p': p, 'w': w, 'q': qty});
    await q('''
      UPDATE inventory_balances SET quantity = desktop_quantity
        - COALESCE((SELECT SUM(i.quantity) FROM sales_invoice_items i JOIN sales_invoices si ON si.id = i.invoice_id
                    WHERE si.warehouse_id=@w AND i.product_id=@p AND si.posted_on_desktop_at IS NULL), 0)
        + COALESCE((SELECT SUM(i.quantity) FROM sales_return_items i JOIN sales_returns sr ON sr.id = i.return_id
                    WHERE sr.warehouse_id=@w AND i.product_id=@p AND sr.posted_on_desktop_at IS NULL), 0)
      WHERE product_id=@p AND warehouse_id=@w AND company_id=@c''', {'p': p, 'w': w});
    _ok('vanStock');
  }
}
