import 'package:drift/drift.dart';

import '../../data/database/database.dart';
import 'cloud_document_poster.dart';

/// J3 — a `customer` cloud field document: a customer the rep created
/// offline with «حفظ كعميل دائم» on a cash-customer sale. Posted through the
/// same path as the desktop button ([AppDatabase.createPermanentCustomerFromCashSale]):
/// a real customer (credit limit 0) with the cloud's `globalId`, at the END
/// of the rep's route with the cloud's `route_customers` identity.
///
/// Idempotent: a re-post (lost ack) returns the party already created.
Future<CloudPostedRef> postCloudCustomer(
    AppDatabase db, Map<String, dynamic> doc) async {
  final gid = doc['globalId'];
  if (gid is! String || gid.isEmpty) {
    throw CloudPostingException('invalid_global_id');
  }
  final name = doc['name'] is String ? (doc['name'] as String).trim() : '';
  if (name.isEmpty) throw CloudPostingException('name_required');
  int? routeId;
  final routeGid = doc['routeGlobalId'];
  if (routeGid is String && routeGid.isNotEmpty) {
    final row = await db.customSelect(
      'SELECT id FROM sales_routes WHERE global_id = ? LIMIT 1',
      variables: [Variable<String>(routeGid)],
    ).getSingleOrNull();
    routeId = (row?.data['id'] as num?)?.toInt();
    if (routeId == null) throw CloudPostingException('route_not_found', routeGid);
  }
  final id = await db.createPermanentCustomerFromCashSale(
    name: name,
    phone: doc['phone'] as String?,
    address: doc['address'] as String?,
    routeId: routeId,
    globalId: gid,
    routeCustomerGlobalId: doc['routeCustomerGlobalId'] as String?,
  );
  final party = await (db.select(db.parties)..where((p) => p.id.equals(id)))
      .getSingleOrNull();
  return CloudPostedRef('$id', party?.code);
}
