import 'package:postgres/postgres.dart';
import 'package:uuid/uuid.dart';

import '../db/database.dart';
import 'errors.dart';

const _uuid = Uuid();

String? _text(Object? v, int max) {
  if (v is! String || v.trim().isEmpty) return null;
  final t = v.trim();
  return t.length > max ? t.substring(0, max) : t;
}

/// J3 — `customer` document: «حفظ كعميل دائم» on a cash-customer sale, made
/// offline on the van. The party (document `globalId`, credit limit 0 ⇒
/// cash only until management sets a limit) is put at the END of the rep's
/// route sequence effective today, so the rep can sell to it right away;
/// the desktop I-3 poster later creates the same customer (same `globalId`,
/// same `route_customers` identity) and acknowledges it.
///
/// Idempotency is the generic `sync_idempotency` replay of `_pushOne`.
Future<Map<String, Object?>> acceptFieldCustomer(
    CloudDatabase db, Session s, DeviceContext d, String gid, Map<String, Object?> doc) async {
  final name = _text(doc['name'], 120);
  if (name == null) throw DocRejected('name_required');
  final routeGid = doc['routeGlobalId'];
  final routes = await db.q(s, '''
    SELECT id, global_id FROM sales_routes
    WHERE company_id=@c AND sales_rep_id=@e AND is_active AND deleted_at IS NULL
    ORDER BY (global_id = @g) DESC, id LIMIT 1''',
      {'c': d.companyId, 'e': d.employeeId, 'g': routeGid is String ? routeGid : ''});
  if (routes.isEmpty) throw DocRejected('no_route');
  final routeId = routes.first[0] as int;
  final routeGlobalId = routes.first[1] as String;
  if (routeGid is String && routeGid.isNotEmpty && routeGid != routeGlobalId) {
    throw DocRejected('route_not_held_by_rep', routeGid);
  }
  final taken = await db.q(s, 'SELECT 1 FROM parties WHERE global_id=@g', {'g': gid});
  if (taken.isNotEmpty) throw DocRejected('global_id_conflict');

  final party = await db.q(s, '''
    INSERT INTO parties (company_id, global_id, name, phone, address, credit_limit, is_customer, balance,
      desktop_balance, origin_client_id)
    VALUES (@c, @g, @n, @ph, @ad, 0, TRUE, 0, 0, @o) RETURNING id''', {
    'c': d.companyId,
    'g': gid,
    'n': name,
    'ph': _text(doc['phone'], 40),
    'ad': _text(doc['address'], 250),
    'o': d.deviceId,
  });
  final partyId = party.first[0] as int;
  final seq = (await db.q(s, '''
    SELECT COALESCE(MAX(sequence), 0) + 1 FROM route_customers
    WHERE route_id=@r AND deleted_at IS NULL AND (effective_to IS NULL OR effective_to >= CURRENT_DATE)''',
          {'r': routeId}))
      .first[0] as int;
  final rcGid = _uuid.v4();
  final rc = await db.q(s, '''
    INSERT INTO route_customers (company_id, global_id, route_id, customer_id, sequence, effective_from,
      origin_client_id)
    VALUES (@c, @g, @r, @p, @sq, CURRENT_DATE, @o) RETURNING id''', {
    'c': d.companyId,
    'g': rcGid,
    'r': routeId,
    'p': partyId,
    'sq': seq,
    'o': d.deviceId,
  });
  await db.q(s, '''
    INSERT INTO field_customers (company_id, global_id, party_id, route_customer_id, rep_employee_id, device_pk,
      origin_client_id, created_at)
    VALUES (@c, @g, @p, @rc, @e, @d, @o, now_ms())''', {
    'c': d.companyId,
    'g': gid,
    'p': partyId,
    'rc': rc.first[0],
    'e': d.employeeId,
    'd': d.devicePk,
    'o': d.deviceId,
  });
  return {
    'globalId': gid,
    'status': 'accepted',
    'kind': 'customer',
    'routeGlobalId': routeGlobalId,
    'routeCustomerGlobalId': rcGid,
    'sequence': seq,
  };
}
