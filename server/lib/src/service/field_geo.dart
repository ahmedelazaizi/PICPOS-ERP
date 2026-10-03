import 'dart:convert';

import 'package:postgres/postgres.dart';

import '../db/database.dart';
import 'errors.dart';

/// GPS capture outcomes the device may report (owner decision K-3): `ok`
/// with a fix, or why there is none.
const kGeoStatuses = {'ok', 'denied', 'timeout', 'unavailable'};

/// Normalized field GPS stamp of a pushed document (`doc['geo']`), or null
/// when the device sent none. Legacy visits send only `latitude`/`longitude`.
/// Throws `invalid_geo` on malformed values (whole document rejected).
Map<String, Object?>? parseFieldGeo(Map<String, Object?> doc) {
  final raw = doc['geo'];
  if (raw == null) {
    final lat = doc['latitude'], lng = doc['longitude'];
    if (lat == null && lng == null) return null;
    return _fix(lat, lng, null, null);
  }
  if (raw is! Map) throw DocRejected('invalid_geo');
  final g = raw.cast<String, Object?>();
  final status = g['status'] ?? (g['lat'] != null ? 'ok' : null);
  if (status is! String || !kGeoStatuses.contains(status)) throw DocRejected('invalid_geo');
  if (status != 'ok') {
    return {'status': status, if (g['at'] is String) 'at': g['at']};
  }
  return _fix(g['lat'], g['lng'], g['accuracy'], g['at']);
}

Map<String, Object?> _fix(Object? lat, Object? lng, Object? accuracy, Object? at) {
  if (lat is! num || lng is! num || lat.abs() > 90 || lng.abs() > 180) throw DocRejected('invalid_geo');
  if (accuracy != null && (accuracy is! num || accuracy < 0)) throw DocRejected('invalid_geo');
  if (at != null && (at is! String || DateTime.tryParse(at) == null)) throw DocRejected('invalid_geo');
  return {
    'status': 'ok',
    'lat': lat.toDouble(),
    'lng': lng.toDouble(),
    if (accuracy is num) 'accuracy': accuracy.toDouble(),
    if (at is String) 'at': at,
  };
}

/// Field-document table (and extra filter) holding the GPS stamp of [kind].
const _geoTables = {
  'sales_invoice': 'sales_invoices',
  'sales_return': 'sales_returns',
  'collection': 'safe_transactions',
  'expense': 'safe_transactions',
  'visit': 'customer_visits',
};

/// Stores [geo] on the accepted document [gid] (same transaction).
Future<void> storeFieldGeo(
    CloudDatabase db, Session s, int companyId, Object? kind, String gid, Map<String, Object?> geo) async {
  final table = _geoTables[kind];
  if (table == null) return;
  final visitCoords = table == 'customer_visits' && geo['status'] == 'ok';
  await db.q(s, '''
    UPDATE $table SET field_geo = @j${visitCoords ? ', latitude = COALESCE(latitude, @lat), longitude = COALESCE(longitude, @lng)' : ''}
    WHERE company_id=@c AND global_id=@g''', {
    'j': jsonEncode(geo),
    'c': companyId,
    'g': gid,
    if (visitCoords) 'lat': geo['lat'],
    if (visitCoords) 'lng': geo['lng'],
  });
}

/// Decoded `field_geo` column for the desktop payloads.
Map<String, Object?>? decodeFieldGeo(Object? v) {
  if (v is! String || v.isEmpty) return null;
  try {
    final d = jsonDecode(v);
    return d is Map ? d.cast<String, Object?>() : null;
  } on FormatException {
    return null;
  }
}
