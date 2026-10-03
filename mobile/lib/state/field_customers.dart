part of 'app_controller.dart';

/// J3 — the system cash customer, the one-time customer name and
/// «حفظ كعميل دائم» (a customer created offline on the van).
///
/// * The cloud serves the company's cash customer to EVERY rep
///   (`systemRole: 'cash_customer'`, no route) — the explicit exception to
///   one route per customer.
/// * A sale to it may carry a free-text `customerName`/`customerPhone`
///   (stored on the invoice, printed instead of «عميل نقدي»).
/// * «حفظ كعميل دائم» creates the customer locally right away (pending, cash
///   only) and queues a `customer` document (its `globalId` is the new
///   party's) pushed BEFORE the sale; the cloud puts it at the end of the
///   rep's route and the desktop posts it.
const kFieldCustomerKind = 'customer';
const kCashCustomerRole = 'cash_customer';

bool isCashCustomer(Map<String, Object?>? customer) => customer?['systemRole'] == kCashCustomerRole;

/// Cash customer, a pending field customer, or one the cloud flags `cashOnly`
/// (field-created, no credit limit yet).
bool isCashOnlyCustomer(Map<String, Object?>? customer) =>
    isCashCustomer(customer) || customer?['cashOnly'] == true || customer?['_pending'] == true;

String? _clean(String? v) => v == null || v.trim().isEmpty ? null : v.trim();

extension FieldCustomers on AppController {
  /// The rep's route a field customer joins: the first route of the profile.
  String? get _currentRouteGlobalId => routeNames.keys.firstOrNull;

  /// «حفظ كعميل دائم»: creates the customer offline and queues it; returns
  /// the new customer's `globalId` (the sale switches to it).
  Future<String> createFieldCustomer({required String name, String? phone, String? address}) async {
    final n = _clean(name);
    if (n == null) throw AppFailure('nameRequired');
    final route = _currentRouteGlobalId;
    if (route == null) throw AppFailure('noRoute');
    var lastSequence = 0;
    for (final c in await store.all(Kinds.customers)) {
      final s = (c['sequence'] as int?) ?? 0;
      if (c['routeGlobalId'] == route && s > lastSequence) lastSequence = s;
    }
    final gid = AppController._uuid.v4();
    await store.upsert(Kinds.customers, [
      {
        'globalId': gid,
        'name': n,
        'phone': _clean(phone),
        'address': _clean(address),
        'balance': 0.0,
        'creditLimit': 0.0,
        'sequence': lastSequence + 1,
        'routeGlobalId': route,
        'cashOnly': true,
        '_pending': true,
      },
    ]);
    await _queue(OutboxEntry(
      globalId: gid,
      kind: kFieldCustomerKind,
      createdAt: _clock(),
      payload: {
        'kind': kFieldCustomerKind,
        'globalId': gid,
        'name': n,
        'phone': ?_clean(phone),
        'address': ?_clean(address),
        'routeGlobalId': route,
      },
    ));
    return gid;
  }
}
