import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../data/cloud_api.dart';
import '../data/local_store.dart';
import '../domain/sale_math.dart';
import '../geo/geo_capture.dart';

part 'field_customers.dart';
part 'field_expenses.dart';

class AppFailure implements Exception {
  AppFailure(this.code, [this.detail]);

  /// Key into `S` strings (e.g. `insufficientStock`).
  final String code;
  final String? detail;
  @override
  String toString() => 'AppFailure($code, $detail)';
}

/// Today's visit state of a route customer.
enum VisitState { planned, visited, noSale }

/// A sales return computed on the device (same math as the server gate).
class ReturnPreview {
  ReturnPreview(this.lines, this.total, this.tax, this.arOffset, this.cashRefund);

  /// productGlobalId → (qty, amounts).
  final Map<String, ({double quantity, ReturnLineAmounts amounts})> lines;
  final double total, tax, arOffset, cashRefund;
}

/// App state + offline business rules. Rules here mirror the server gate so
/// the rep sees a block offline; the server re-checks on push and wins.
class AppController extends ChangeNotifier {
  AppController({
    required this.store,
    required this.api,
    DateTime Function()? clock,
    this.geo,
    Future<List<int>?> Function(String path)? readPhoto,
  })  : _clock = clock ?? DateTime.now,
        readPhoto = readPhoto ?? _readFile;

  final LocalStore store;
  final CloudApi api;
  final DateTime Function() _clock;

  /// K-3: GPS stamp of documents and visits (null = no location support,
  /// e.g. unit tests: payloads then carry no `geo`).
  GeoCapture? geo;

  /// K-1: reads a stored receipt photo when its expense is pushed.
  final Future<List<int>?> Function(String path) readPhoto;

  static Future<List<int>?> _readFile(String path) async {
    final f = File(path);
    return await f.exists() ? f.readAsBytes() : null;
  }
  static const _uuid = Uuid();

  /// Device token rotation period (ARCHITECTURE-I §4).
  static const tokenRotationPeriod = Duration(days: 30);
  static const defaultNoSaleReasons = ['closed', 'owner_absent', 'has_stock', 'no_cash', 'refused', 'other'];

  DeviceCredentials? creds;
  String? session;
  bool loggedIn = false;
  bool syncing = false;
  String? lastSyncError;
  DateTime? lastSync;
  String repName = '';
  double companyTaxRate = 0;
  bool pricesIncludeTax = false;
  int decimals = 2;
  bool canOverridePrice = false;
  List<String> noSaleReasons = defaultNoSaleReasons;

  /// Set by the background sync scheduler (shown on the sync tab).
  bool online = true;
  DateTime? nextAutoSync;

  /// Called after a document is queued (the scheduler pushes it soon).
  VoidCallback? onOutboxChanged;

  /// Called synchronously after a document is saved (print-on-save, I-4).
  /// Listeners must not block: the sale is already stored when this runs.
  void Function(OutboxEntry entry)? onDocumentSaved;

  /// Last-synced company settings (pricing and printed identity, I-4).
  Map<String, Object?> company = const {};

  /// Route globalId → name (bootstrap), printed on receipts.
  Map<String, String> routeNames = const {};

  bool get isPaired => creds != null;

  void setAutoSyncStatus(bool isOnline, DateTime? next) {
    online = isOnline;
    nextAutoSync = next;
    notifyListeners();
  }

  double _r(double v) => roundDp(v, decimals);

  Future<void> init() async {
    final raw = await store.getKv('creds');
    if (raw != null) {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      creds = DeviceCredentials(
          baseUrl: m['baseUrl'] as String, deviceId: m['deviceId'] as String, deviceToken: m['deviceToken'] as String);
    }
    final ls = await store.getKv('lastSync');
    lastSync = ls == null ? null : DateTime.fromMillisecondsSinceEpoch(int.parse(ls));
    repName = await store.getKv('repName') ?? '';
    final company = await store.getKv('company');
    if (company != null) _applyCompany((jsonDecode(company) as Map).cast<String, Object?>());
    final routes = await store.getKv('routes');
    if (routes != null) routeNames = (jsonDecode(routes) as Map).cast<String, String>();
    final emp = await store.getKv('employee');
    if (emp != null) _applyEmployee((jsonDecode(emp) as Map).cast<String, Object?>());
    final reasons = await store.getKv('noSaleReasons');
    if (reasons != null) noSaleReasons = (jsonDecode(reasons) as List).cast<String>();
    // K-2: the last server session (kept in the encrypted DB) lets the
    // background worker push/pull while it is valid; the UI still asks for
    // the PIN (loggedIn stays false).
    session = await store.getKv('session');
    notifyListeners();
  }

  Future<void> _setSession(String? s) async {
    session = s;
    await store.setKv('session', s);
  }

  void _applyCompany(Map<String, Object?> m) {
    company = Map.unmodifiable(m);
    companyTaxRate = (m['defaultTaxRate'] as num?)?.toDouble() ?? 0;
    pricesIncludeTax = m['pricesIncludeTax'] == true;
    decimals = (m['decimalPlaces'] as int?) ?? 2;
  }

  void _applyEmployee(Map<String, Object?> m) {
    repName = '${m['name'] ?? ''}';
    canOverridePrice = m['canOverridePrice'] == true;
  }

  // ───────────── pairing & login ─────────────

  Future<void> pair(String baseUrl, String code) async {
    final url = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    final deviceId = _uuid.v4();
    late final ({String deviceToken, String employeeGlobalId}) r;
    try {
      r = await api.pair(url, code.trim().toUpperCase(), deviceId, 'Android van');
    } on CloudApiException catch (e) {
      final key = switch (e.code) {
        'invalid_code' => 'invalidPairingCode',
        'code_expired' => 'pairingCodeExpired',
        'too_many_attempts' => 'pairingTooManyAttempts',
        'invalid_request' => 'invalidPairingRequest',
        _ => 'pairingRejected',
      };
      throw AppFailure(key, e.code);
    }
    await _saveCreds(DeviceCredentials(baseUrl: url, deviceId: deviceId, deviceToken: r.deviceToken));
    notifyListeners();
  }

  Future<void> _saveCreds(DeviceCredentials c) async {
    creds = c;
    await store.setKv('creds', jsonEncode({'baseUrl': c.baseUrl, 'deviceId': c.deviceId, 'deviceToken': c.deviceToken}));
    await store.setKv('tokenRotatedAt', '${_clock().millisecondsSinceEpoch}');
  }

  static String _pinHash(String pin, String salt) {
    List<int> h = utf8.encode('$salt:$pin');
    for (var i = 0; i < 20000; i++) {
      h = sha256.convert(h).bytes;
    }
    return base64.encode(h);
  }

  /// Online login when reachable; otherwise the PIN verified at the last
  /// online login opens the app offline (push still needs a server session).
  Future<void> login(String pin) async {
    final c = creds!;
    try {
      await _setSession(await api.login(c, pin));
      final salt = base64.encode(List<int>.generate(16, (_) => Random.secure().nextInt(256)));
      await store.setKv('pin', '$salt:${_pinHash(pin, salt)}');
    } on CloudApiException catch (e) {
      if (e.code == 'device_revoked') await wipe();
      throw AppFailure(e.code == 'invalid_pin' ? 'invalidPin' : 'error', e.code);
    } catch (_) {
      final saved = await store.getKv('pin');
      final parts = saved?.split(':');
      if (parts == null || parts.length != 2 || _pinHash(pin, parts[0]) != parts[1]) {
        throw AppFailure('invalidPin');
      }
    }
    loggedIn = true;
    notifyListeners();
    if (session != null) await syncNow();
  }

  /// Back to the PIN screen (e.g. to get a fresh server session).
  void signOut() {
    _setSession(null);
    loggedIn = false;
    notifyListeners();
  }

  /// Device revoked: local data is erased (ARCHITECTURE-I §4.5).
  Future<void> wipe() async {
    await store.clear();
    creds = null;
    session = null;
    loggedIn = false;
    lastSync = null;
    notifyListeners();
  }

  // ───────────── sync ─────────────

  /// Push the outbox, then pull. Returns true when the server was reached and
  /// everything was exchanged (the scheduler backs off on false).
  Future<bool> syncNow() async {
    final c = creds;
    final s = session;
    if (c == null || syncing) return false;
    if (s == null) {
      lastSyncError = 'sessionRequired';
      notifyListeners();
      return false;
    }
    syncing = true;
    lastSyncError = null;
    notifyListeners();
    try {
      final cc = await _maybeRotateToken(c);
      // J3 — a field-created customer is pushed before the sales made to it.
      final queued = await pendingDocs();
      final pending = [
        ...queued.where((e) => e.kind == kFieldCustomerKind),
        ...queued.where((e) => e.kind != kFieldCustomerKind),
      ];
      // ≤ 50 documents and ≈ 3 MB per request (K-1 receipt photos ride along).
      var batch = <OutboxEntry>[];
      var wire = <Map<String, Object?>>[];
      var bytes = 0;
      Future<void> flush() async {
        if (batch.isEmpty) return;
        await applyPushResults(batch, await api.push(cc, s, wire));
        batch = [];
        wire = [];
        bytes = 0;
      }

      for (final e in pending) {
        final w = await _wireDocument(e);
        final size = jsonEncode(w).length;
        if (batch.length == 50 || (batch.isNotEmpty && bytes + size > kMaxPushBytes)) await flush();
        batch.add(e);
        wire.add(w);
        bytes += size;
      }
      await flush();
      final since = int.tryParse(await store.getKv('watermark') ?? '');
      final payload = since == null ? await api.bootstrap(cc, s) : await api.pull(cc, s, since);
      await applyServerPayload(payload);
      lastSync = _clock();
      await store.setKv('lastSync', '${lastSync!.millisecondsSinceEpoch}');
      return true;
    } on CloudApiException catch (e) {
      if (e.code == 'device_revoked') {
        await wipe();
      } else if (e.code == 'invalid_session' || e.code == 'session_device_mismatch') {
        await _setSession(null);
        lastSyncError = 'sessionRequired';
      } else {
        lastSyncError = e.code;
      }
      return false;
    } catch (e) {
      lastSyncError = '$e';
      return false;
    } finally {
      syncing = false;
      notifyListeners();
    }
  }

  /// Upper bound of one push request body (photos make documents large).
  static const kMaxPushBytes = 3 * 1024 * 1024;

  /// Keys starting with `_` are device-local bookkeeping, never sent.
  static Map<String, Object?> _wire(Map<String, Object?> p) => {
        for (final e in p.entries)
          if (!e.key.startsWith('_'))
            e.key: e.value is List
                ? [
                    for (final x in e.value as List)
                      x is Map ? {for (final f in x.entries) if (!'${f.key}'.startsWith('_')) f.key: f.value} : x,
                  ]
                : e.value,
      };

  Future<DeviceCredentials> _maybeRotateToken(DeviceCredentials c) async {
    final at = int.tryParse(await store.getKv('tokenRotatedAt') ?? '');
    final now = _clock();
    if (at != null && now.difference(DateTime.fromMillisecondsSinceEpoch(at)) < tokenRotationPeriod) return c;
    final token = await api.rotateToken(c);
    final next = DeviceCredentials(baseUrl: c.baseUrl, deviceId: c.deviceId, deviceToken: token);
    await _saveCreds(next);
    return next;
  }

  Future<void> applyPushResults(List<OutboxEntry> batch, List<Map<String, dynamic>> results) async {
    final byId = {for (final r in results) r['globalId']: r};
    for (final e in batch) {
      final r = byId[e.globalId];
      if (r == null) continue;
      e.attempts++;
      final st = r['status'];
      if (st == 'accepted' || st == 'duplicate') {
        e.status = OutboxStatus.accepted;
        e.error = null;
        // Cloud signature, printed (short form) on reprints.
        if (r['integrityHash'] is String) e.payload['_integrityHash'] = r['integrityHash'];
      } else {
        e.status = OutboxStatus.rejected;
        e.error = '${r['code']}';
      }
      await store.updateOutbox(e);
    }
  }

  /// Applies a bootstrap or pull payload (cloud contract, server/README.md).
  Future<void> applyServerPayload(Map<String, dynamic> p) async {
    List<Map<String, Object?>> list(String k) =>
        [for (final x in (p[k] as List? ?? const [])) (x as Map).cast<String, Object?>()];
    if (p['employee'] is Map) {
      final m = (p['employee'] as Map).cast<String, Object?>();
      _applyEmployee(m);
      await store.setKv('employee', jsonEncode(m));
      await store.setKv('repName', repName);
    }
    if (p['company'] is Map) {
      final m = (p['company'] as Map).cast<String, Object?>();
      _applyCompany(m);
      await store.setKv('company', jsonEncode(m));
    }
    if (p['routes'] is List) {
      routeNames = {
        for (final r in list('routes'))
          if (r['globalId'] is String) r['globalId'] as String: '${r['name'] ?? ''}',
      };
      await store.setKv('routes', jsonEncode(routeNames));
    }
    if (p['noSaleReasons'] is List) {
      noSaleReasons = (p['noSaleReasons'] as List).cast<String>();
      await store.setKv('noSaleReasons', jsonEncode(noSaleReasons));
    }
    await store.upsert(Kinds.customers, list('customers'));
    if (p['customerScope'] is List) {
      // J3 — a customer created offline stays until the server has it.
      final pendingCustomers = {
        for (final e in await pendingDocs())
          if (e.kind == kFieldCustomerKind) e.globalId,
      };
      await store.retainOnly(
          Kinds.customers, {...(p['customerScope'] as List).cast<String>(), ...pendingCustomers});
    }
    await store.upsert(Kinds.products, list('products'));
    await store.upsert(Kinds.vanStock, list('vanStock'), idField: 'productGlobalId');
    await store.upsert(Kinds.voucherBooks, list('voucherBooks'));
    if (p['voucherBookScope'] is List) {
      await store.retainOnly(Kinds.voucherBooks, (p['voucherBookScope'] as List).cast<String>().toSet());
    }
    await store.upsert(Kinds.priceLists, list('priceLists'));
    if (p['priceListScope'] is List) {
      await store.retainOnly(Kinds.priceLists, (p['priceListScope'] as List).cast<String>().toSet());
    }
    await store.upsert(Kinds.invoices, list('invoices'));
    // Keep the local next number when it is ahead (numbers used offline).
    final leases = <Map<String, Object?>>[];
    for (final l in list('leases')) {
      final local = await store.get(Kinds.leases, l['globalId'] as String);
      final localNext = (local?['nextNumber'] as int?) ?? 0;
      leases.add({...l, 'nextNumber': max(localNext, l['nextNumber'] as int)});
    }
    await store.upsert(Kinds.leases, leases);
    // A push whose response was lost (app killed mid-push): the server
    // already holds the document, so the local copy is accepted too.
    await _applyExpensePayload(p);
    final known = {for (final d in list('documents')) d['globalId']};
    if (known.isNotEmpty) {
      for (final e in await pendingDocs()) {
        if (known.contains(e.globalId)) {
          e.status = OutboxStatus.accepted;
          await store.updateOutbox(e);
        }
      }
    }
    if (p['serverTime'] is int) await store.setKv('watermark', '${p['serverTime']}');
    notifyListeners();
  }

  // ───────────── queries (server state + pending outbox) ─────────────

  Future<List<OutboxEntry>> pendingDocs() async =>
      (await store.outbox()).where((e) => e.status == OutboxStatus.pending).toList();

  Future<List<Map<String, Object?>>> routeCustomers() async {
    final c = await store.all(Kinds.customers);
    c.sort((a, b) => ((a['sequence'] as int?) ?? 0).compareTo((b['sequence'] as int?) ?? 0));
    return c;
  }

  Future<List<Map<String, Object?>>> products() async => store.all(Kinds.products);

  Future<Map<String, Object?>?> product(String globalId) => store.get(Kinds.products, globalId);

  Future<double> availableStock(String productGlobalId) async {
    final s = await store.get(Kinds.vanStock, productGlobalId);
    var q = ((s?['quantity'] as num?) ?? 0).toDouble();
    for (final e in await pendingDocs()) {
      if (e.kind != 'sales_invoice' && e.kind != 'sales_return') continue;
      final sign = e.kind == 'sales_invoice' ? -1 : 1;
      for (final l in (e.payload['lines'] as List)) {
        final m = l as Map;
        if (m['productGlobalId'] == productGlobalId) q += sign * (m['quantity'] as num).toDouble();
      }
    }
    return q;
  }

  /// Last-synced balance plus the effect of documents not yet sent.
  Future<double> effectiveBalance(String customerGlobalId) async {
    final c = await store.get(Kinds.customers, customerGlobalId);
    var b = ((c?['balance'] as num?) ?? 0).toDouble();
    for (final e in await pendingDocs()) {
      if (e.payload['customerGlobalId'] != customerGlobalId) continue;
      if (e.kind == 'sales_invoice') b += (e.payload['_remaining'] as num).toDouble();
      if (e.kind == 'collection') b -= (e.payload['amount'] as num).toDouble();
      if (e.kind == 'sales_return') b -= (e.payload['_arOffset'] as num).toDouble();
    }
    return _r(b);
  }

  bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  /// Planned → visited (any document or a «visited» record today) or no sale
  /// (a no-sale visit and nothing sold/collected).
  Future<(VisitState, String?)> visitState(String customerGlobalId) async {
    final now = _clock();
    var state = VisitState.planned;
    String? reason;
    for (final e in await store.outbox()) {
      if (e.status == OutboxStatus.rejected ||
          e.payload['customerGlobalId'] != customerGlobalId ||
          !_sameDay(e.createdAt, now)) {
        continue;
      }
      if (e.kind == 'visit' && e.payload['outcome'] == 'no_sale') {
        if (state == VisitState.planned) {
          state = VisitState.noSale;
          reason = e.payload['noSaleReason'] as String?;
        }
      } else {
        return (VisitState.visited, null);
      }
    }
    return (state, reason);
  }

  Future<bool> visitedToday(String customerGlobalId) async =>
      (await visitState(customerGlobalId)).$1 != VisitState.planned;

  Future<Map<String, Object?>?> productByBarcode(String code) async {
    final c = normalizeBarcode(code);
    for (final p in await products()) {
      if (p['barcode'] == c) return p;
    }
    return null;
  }

  double taxRateOf(Map<String, Object?> product) => effectiveItemTaxRate(
      rate: ((product['taxRate'] as num?) ?? 0).toDouble(),
      exempt: product['taxExempt'] == true,
      companyDefault: companyTaxRate);

  /// Price for this customer and quantity — the same resolution the server
  /// enforces (price level, price-list tiers, sale price).
  Future<ResolvedPrice> unitPriceFor(Map<String, Object?> product, String customerGlobalId, double quantity) async {
    final customer = await store.get(Kinds.customers, customerGlobalId);
    final pg = product['globalId'];
    final entries = <PriceListEntry>[
      for (final l in await store.all(Kinds.priceLists))
        for (final i in (l['items'] as List? ?? const []))
          if ((i as Map)['productGlobalId'] == pg)
            PriceListEntry(
              listGlobalId: l['globalId'] as String,
              isDefault: l['isDefault'] == true,
              isActive: l['isActive'] == true,
              startDate: l['startDate'] as String?,
              endDate: l['endDate'] as String?,
              listOrder: (l['order'] as int?) ?? 0,
              price: (i['price'] as num).toDouble(),
              minQuantity: ((i['minQuantity'] as num?) ?? 0).toDouble(),
            ),
    ];
    return resolveUnitPrice(
      salePrice: ((product['salePrice'] as num?) ?? 0).toDouble(),
      wholesalePrice: (product['wholesalePrice'] as num?)?.toDouble(),
      priceLevel: customer?['priceLevel'] as String?,
      quantity: quantity,
      today: _clock(),
      entries: entries,
    );
  }

  DocTotals totalsOf(Iterable<CartLine> lines) =>
      cartTotals(lines, pricesIncludeTax: pricesIncludeTax, decimals: decimals);

  // ───────────── documents ─────────────

  Future<void> _queue(OutboxEntry e) async {
    await store.addOutbox(e);
    notifyListeners();
    onOutboxChanged?.call();
    try {
      onDocumentSaved?.call(e);
    } catch (err) {
      // Printing (or any listener) must never fail a saved document.
      debugPrint('onDocumentSaved: $err');
    }
  }

  /// Name of a stored entity (customer / product), for receipts.
  Future<String> nameOf(String kind, Object? globalId) async =>
      globalId is String ? '${(await store.get(kind, globalId))?['name'] ?? ''}' : '';

  /// [customerName]/[customerPhone]: J3 one-time name on a cash-customer sale
  /// (kept only for the system cash customer, printed instead of its name).
  Future<OutboxEntry> createSale({
    required String customerGlobalId,
    required List<CartLine> lines,
    required double paid,
    String? customerName,
    String? customerPhone,
  }) async {
    if (lines.isEmpty) throw AppFailure('emptyCart');
    final qty = <String, double>{};
    for (final l in lines) {
      qty[l.productGlobalId] = (qty[l.productGlobalId] ?? 0) + l.quantity;
    }
    for (final e in qty.entries) {
      if (await availableStock(e.key) + 1e-9 < e.value) throw AppFailure('insufficientStock', e.key);
    }
    if (!canOverridePrice) {
      for (final l in lines) {
        final p = await product(l.productGlobalId);
        if (p == null) throw AppFailure('error', l.productGlobalId);
        final expected = await unitPriceFor(p, customerGlobalId, l.quantity);
        if ((expected.price - l.unitPrice).abs() > 0.00005) throw AppFailure('priceNotAllowed', l.name);
      }
    }
    final totals = totalsOf(lines);
    final paidClamped = paid.clamp(0, totals.total).toDouble();
    final remaining = _r(totals.total - paidClamped);
    final customer = await store.get(Kinds.customers, customerGlobalId);
    if (exceedsCreditLimit(
        balance: await effectiveBalance(customerGlobalId),
        creditLimit: ((customer?['creditLimit'] as num?) ?? 0).toDouble(),
        remaining: remaining)) {
      throw AppFailure('creditExceeded');
    }
    if (violatesCashOnly(cashOnly: isCashOnlyCustomer(customer), remaining: remaining)) {
      throw AppFailure('cashOnly');
    }
    final oneTime = isCashCustomer(customer)
        ? (name: _clean(customerName), phone: _clean(customerPhone))
        : (name: null, phone: null);
    final balanceBefore = await effectiveBalance(customerGlobalId);
    final geoStamp = await _geoStamp();
    final number = await _takeNumber('sales_invoice');
    final gid = _uuid.v4();
    final entry = OutboxEntry(
      globalId: gid,
      kind: 'sales_invoice',
      createdAt: _clock(),
      payload: {
        'kind': 'sales_invoice',
        'globalId': gid,
        'number': number,
        'date': _clock().toUtc().toIso8601String(),
        'customerGlobalId': customerGlobalId,
        'customerName': ?oneTime.name,
        'customerPhone': ?oneTime.phone,
        'lines': [
          for (var i = 0; i < lines.length; i++)
            {
              'productGlobalId': lines[i].productGlobalId,
              'quantity': lines[i].quantity,
              'unitPrice': lines[i].unitPrice,
              // Device-local (stripped before push): receipt lines.
              '_name': lines[i].name,
              '_total': totals.lines[i].total,
            },
        ],
        'paid': paidClamped,
        'total': totals.total,
        'geo': ?geoStamp,
        '_remaining': remaining,
        '_net': totals.net,
        '_tax': totals.tax,
        '_balanceAfter': _r(balanceBefore + remaining),
      },
    );
    await _queue(entry);
    return entry;
  }

  Future<String> _takeNumber(String docType) async {
    final leases = (await store.all(Kinds.leases))
        .where((l) => l['docType'] == docType && l['status'] == 'active')
        .toList()
      ..sort((a, b) => (a['rangeFrom'] as int).compareTo(b['rangeFrom'] as int));
    for (final l in leases) {
      final next = l['nextNumber'] as int;
      if (next <= (l['rangeTo'] as int)) {
        await store.upsert(Kinds.leases, [
          {...l, 'nextNumber': next + 1},
        ]);
        return '${l['prefix']}$next';
      }
    }
    throw AppFailure('noNumbers');
  }

  // ── returns ──

  /// Server-known invoices of [customerGlobalId] that still have something
  /// returnable (pending returns included), newest first.
  Future<List<Map<String, Object?>>> returnableInvoices(String customerGlobalId) async {
    final out = <Map<String, Object?>>[];
    for (final inv in await store.all(Kinds.invoices)) {
      if (inv['customerGlobalId'] != customerGlobalId) continue;
      final sold = await soldProducts(inv['globalId'] as String);
      if (sold.values.any((p) => p.returnableQty > 1e-9)) out.add(inv);
    }
    out.sort((a, b) => '${b['date']}'.compareTo('${a['date']}'));
    return out;
  }

  Future<List<OutboxEntry>> _pendingReturns(String invoiceGlobalId) async => [
        for (final e in await pendingDocs())
          if (e.kind == 'sales_return' && e.payload['originalInvoiceGlobalId'] == invoiceGlobalId) e,
      ];

  /// productGlobalId → sold and already returned (server + pending returns).
  Future<Map<String, SoldProduct>> soldProducts(String invoiceGlobalId) async {
    final inv = await store.get(Kinds.invoices, invoiceGlobalId);
    if (inv == null) return {};
    final pend = <String, (double, double, double)>{};
    for (final e in await _pendingReturns(invoiceGlobalId)) {
      for (final l in e.payload['lines'] as List) {
        final m = l as Map;
        final p = pend[m['productGlobalId']] ?? (0, 0, 0);
        pend[m['productGlobalId'] as String] = (
          p.$1 + (m['quantity'] as num).toDouble(),
          p.$2 + (m['_total'] as num).toDouble(),
          p.$3 + (m['_tax'] as num).toDouble(),
        );
      }
    }
    double d(Object? v) => ((v as num?) ?? 0).toDouble();
    return {
      for (final l in (inv['lines'] as List).cast<Map>())
        l['productGlobalId'] as String: SoldProduct(
          soldQty: d(l['quantity']),
          soldTotal: d(l['total']),
          soldTax: d(l['tax']),
          returnedQty: d(l['returnedQuantity']) + (pend[l['productGlobalId']]?.$1 ?? 0),
          returnedTotal: d(l['returnedTotal']) + (pend[l['productGlobalId']]?.$2 ?? 0),
          returnedTax: d(l['returnedTax']) + (pend[l['productGlobalId']]?.$3 ?? 0),
        ),
    };
  }

  /// Amounts and settlement of a return of [quantities] against an invoice;
  /// throws `returnQtyExceeds` like the server's `return_qty_exceeds_sold`.
  Future<ReturnPreview> previewReturn(String invoiceGlobalId, Map<String, double> quantities) async {
    final inv = await store.get(Kinds.invoices, invoiceGlobalId);
    if (inv == null) throw AppFailure('noInvoice');
    final sold = await soldProducts(invoiceGlobalId);
    final lines = <String, ({double quantity, ReturnLineAmounts amounts})>{};
    for (final e in quantities.entries) {
      if (e.value <= 0) continue;
      final sp = sold[e.key];
      final a = sp == null ? null : returnLineAmounts(sp, e.value, decimals: decimals);
      if (a == null) throw AppFailure('returnQtyExceeds', e.key);
      lines[e.key] = (quantity: e.value, amounts: a);
    }
    final total = _r(lines.values.fold(0.0, (t, l) => t + l.amounts.total));
    final tax = _r(lines.values.fold(0.0, (t, l) => t + l.amounts.tax));
    var prevAr = ((inv['returnArOffset'] as num?) ?? 0).toDouble();
    for (final e in await _pendingReturns(invoiceGlobalId)) {
      prevAr += (e.payload['_arOffset'] as num).toDouble();
    }
    final split = returnSettlement(
      invoiceTotal: (inv['total'] as num).toDouble(),
      invoicePaid: (inv['paid'] as num).toDouble(),
      previousArOffset: prevAr,
      returnTotal: total,
      decimals: decimals,
    );
    return ReturnPreview(lines, total, tax, split.arOffset, split.cashRefund);
  }

  Future<OutboxEntry> createReturn({
    required String invoiceGlobalId,
    required Map<String, double> quantities,
    String? reason,
  }) async {
    final preview = await previewReturn(invoiceGlobalId, quantities);
    if (preview.lines.isEmpty) throw AppFailure('emptyReturn');
    final inv = (await store.get(Kinds.invoices, invoiceGlobalId))!;
    final geoStamp = await _geoStamp();
    final number = await _takeNumber('sales_return');
    final gid = _uuid.v4();
    final entry = OutboxEntry(
      globalId: gid,
      kind: 'sales_return',
      createdAt: _clock(),
      payload: {
        'kind': 'sales_return',
        'globalId': gid,
        'number': number,
        'date': _clock().toUtc().toIso8601String(),
        'originalInvoiceGlobalId': invoiceGlobalId,
        'customerGlobalId': inv['customerGlobalId'],
        'lines': [
          for (final e in preview.lines.entries)
            {
              'productGlobalId': e.key,
              'quantity': e.value.quantity,
              '_total': e.value.amounts.total,
              '_tax': e.value.amounts.tax,
            },
        ],
        'total': preview.total,
        'cashRefund': preview.cashRefund,
        'reason': ?reason,
        'geo': ?geoStamp,
        '_arOffset': preview.arOffset,
        '_tax': preview.tax,
        '_originalNumber': inv['number'],
        '_balanceAfter': _r(await effectiveBalance(inv['customerGlobalId'] as String) - preview.arOffset),
      },
    );
    await _queue(entry);
    return entry;
  }

  // ── visits ──

  Future<OutboxEntry> createVisit({
    required String customerGlobalId,
    required String outcome,
    String? noSaleReason,
    String? note,
  }) async {
    if (outcome != 'visited' && outcome != 'no_sale') throw AppFailure('error', outcome);
    if (outcome == 'no_sale' && (noSaleReason == null || !noSaleReasons.contains(noSaleReason))) {
      throw AppFailure('reasonRequired');
    }
    final geoStamp = await _geoStamp();
    final fix = geoStamp?['status'] == 'ok';
    final gid = _uuid.v4();
    final entry = OutboxEntry(
      globalId: gid,
      kind: 'visit',
      createdAt: _clock(),
      payload: {
        'kind': 'visit',
        'globalId': gid,
        'customerGlobalId': customerGlobalId,
        'date': _clock().toUtc().toIso8601String(),
        'outcome': outcome,
        if (outcome == 'no_sale') 'noSaleReason': noSaleReason,
        if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
        // K-3: visit GPS (legacy lat/lng columns + the full stamp).
        if (fix) 'latitude': geoStamp!['lat'],
        if (fix) 'longitude': geoStamp!['lng'],
        'geo': ?geoStamp,
      },
    );
    await _queue(entry);
    return entry;
  }

  // ── collections ──

  Future<List<Map<String, Object?>>> voucherBooks() async =>
      (await store.all(Kinds.voucherBooks)).where((b) => b['status'] == 'active').toList();

  Future<Set<int>> _usedLeaves(Map<String, Object?> book) async => {
        ...((book['usedNumbers'] as List?) ?? const []).cast<int>(),
        ...((book['cancelledNumbers'] as List?) ?? const []).cast<int>(),
        for (final e in await store.outbox())
          if ((e.kind == 'collection' || e.kind == kExpenseKind) &&
              e.status != OutboxStatus.rejected &&
              e.payload['bookGlobalId'] == book['globalId'])
            e.payload['bookNumber'] as int,
      };

  /// Same suggestion rule as desktop `suggestNextVoucherBookNumber`.
  Future<int?> suggestLeaf(Map<String, Object?> book) async {
    final used = await _usedLeaves(book);
    final from = book['rangeFrom'] as int, to = book['rangeTo'] as int;
    for (var i = book['nextNumber'] as int; i <= to; i++) {
      if (i >= from && !used.contains(i)) return i;
    }
    for (var i = from; i <= to; i++) {
      if (!used.contains(i)) return i;
    }
    return null;
  }

  Future<OutboxEntry> createCollection({
    required String customerGlobalId,
    required double amount,
    required Map<String, Object?> book,
    required int leaf,
  }) async {
    if (amount <= 0) throw AppFailure('amount');
    if (leaf < (book['rangeFrom'] as int) || leaf > (book['rangeTo'] as int) || (await _usedLeaves(book)).contains(leaf)) {
      throw AppFailure('leafInvalid');
    }
    final geoStamp = await _geoStamp();
    final gid = _uuid.v4();
    final entry = OutboxEntry(
      globalId: gid,
      kind: 'collection',
      createdAt: _clock(),
      payload: {
        'kind': 'collection',
        'globalId': gid,
        'customerGlobalId': customerGlobalId,
        'amount': amount,
        'bookGlobalId': book['globalId'],
        'bookNumber': leaf,
        'date': _clock().toUtc().toIso8601String(),
        'geo': ?geoStamp,
        '_bookPrefix': book['prefix'],
        '_balanceAfter': _r(await effectiveBalance(customerGlobalId) - amount),
      },
    );
    await _queue(entry);
    return entry;
  }
}
