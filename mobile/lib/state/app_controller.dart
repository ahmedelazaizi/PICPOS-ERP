import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../data/cloud_api.dart';
import '../data/local_store.dart';
import '../domain/sale_math.dart';

class AppFailure implements Exception {
  AppFailure(this.code, [this.detail]);

  /// Key into `S` strings (e.g. `insufficientStock`).
  final String code;
  final String? detail;
  @override
  String toString() => 'AppFailure($code, $detail)';
}

/// App state + offline business rules. Rules here mirror the server gate so
/// the rep sees a block offline; the server re-checks on push and wins.
class AppController extends ChangeNotifier {
  AppController({required this.store, required this.api, DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  final LocalStore store;
  final CloudApi api;
  final DateTime Function() _clock;
  static const _uuid = Uuid();

  DeviceCredentials? creds;
  String? session;
  bool loggedIn = false;
  bool syncing = false;
  String? lastSyncError;
  DateTime? lastSync;
  String repName = '';
  double companyTaxRate = 0;

  bool get isPaired => creds != null;

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
    companyTaxRate = double.tryParse(await store.getKv('companyTaxRate') ?? '') ?? 0;
    notifyListeners();
  }

  // ───────────── pairing & login ─────────────

  Future<void> pair(String baseUrl, String code) async {
    final url = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    final deviceId = _uuid.v4();
    final r = await api.pair(url, code.trim().toUpperCase(), deviceId, 'Android van');
    creds = DeviceCredentials(baseUrl: url, deviceId: deviceId, deviceToken: r.deviceToken);
    await store.setKv('creds', jsonEncode({'baseUrl': url, 'deviceId': deviceId, 'deviceToken': r.deviceToken}));
    notifyListeners();
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
      session = await api.login(c, pin);
      final salt = base64.encode(List<int>.generate(16, (_) => Random.secure().nextInt(256)));
      await store.setKv('pin', '$salt:${_pinHash(pin, salt)}');
    } on CloudApiException catch (e) {
      if (e.code == 'device_revoked') {
        await store.clear();
        creds = null;
        notifyListeners();
      }
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

  // ───────────── sync ─────────────

  Future<void> syncNow() async {
    final c = creds;
    final s = session;
    if (c == null || s == null || syncing) return;
    syncing = true;
    lastSyncError = null;
    notifyListeners();
    try {
      final pending = (await store.outbox()).where((e) => e.status == OutboxStatus.pending).toList();
      for (var i = 0; i < pending.length; i += 50) {
        final batch = pending.sublist(i, min(i + 50, pending.length));
        final results = await api.push(c, s, [for (final e in batch) e.payload]);
        await applyPushResults(batch, results);
      }
      final since = int.tryParse(await store.getKv('watermark') ?? '');
      final payload = since == null ? await api.bootstrap(c, s) : await api.pull(c, s, since);
      await applyServerPayload(payload);
      lastSync = _clock();
      await store.setKv('lastSync', '${lastSync!.millisecondsSinceEpoch}');
    } catch (e) {
      lastSyncError = '$e';
    } finally {
      syncing = false;
      notifyListeners();
    }
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
      repName = '${(p['employee'] as Map)['name']}';
      await store.setKv('repName', repName);
    }
    if (p['company'] is Map) {
      companyTaxRate = ((p['company'] as Map)['defaultTaxRate'] as num?)?.toDouble() ?? 0;
      await store.setKv('companyTaxRate', '$companyTaxRate');
    }
    await store.upsert(Kinds.customers, list('customers'));
    if (p['customerScope'] is List) {
      await store.retainOnly(Kinds.customers, (p['customerScope'] as List).cast<String>().toSet());
    }
    await store.upsert(Kinds.products, list('products'));
    await store.upsert(Kinds.vanStock, list('vanStock'), idField: 'productGlobalId');
    await store.upsert(Kinds.voucherBooks, list('voucherBooks'));
    if (p['voucherBookScope'] is List) {
      await store.retainOnly(Kinds.voucherBooks, (p['voucherBookScope'] as List).cast<String>().toSet());
    }
    // Keep the local next number when it is ahead (numbers used offline).
    final leases = <Map<String, Object?>>[];
    for (final l in list('leases')) {
      final local = await store.get(Kinds.leases, l['globalId'] as String);
      final localNext = (local?['nextNumber'] as int?) ?? 0;
      leases.add({...l, 'nextNumber': max(localNext, l['nextNumber'] as int)});
    }
    await store.upsert(Kinds.leases, leases);
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

  Future<double> availableStock(String productGlobalId) async {
    final s = await store.get(Kinds.vanStock, productGlobalId);
    var q = ((s?['quantity'] as num?) ?? 0).toDouble();
    for (final e in await pendingDocs()) {
      if (e.kind != 'sales_invoice') continue;
      for (final l in (e.payload['lines'] as List)) {
        final m = l as Map;
        if (m['productGlobalId'] == productGlobalId) q -= (m['quantity'] as num).toDouble();
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
    }
    return round2(b);
  }

  Future<bool> visitedToday(String customerGlobalId) async {
    final now = _clock();
    return (await store.outbox()).any((e) =>
        e.payload['customerGlobalId'] == customerGlobalId &&
        e.createdAt.year == now.year &&
        e.createdAt.month == now.month &&
        e.createdAt.day == now.day);
  }

  Future<Map<String, Object?>?> productByBarcode(String code) async {
    for (final p in await products()) {
      if (p['barcode'] == code.trim()) return p;
    }
    return null;
  }

  double taxRateOf(Map<String, Object?> product) => effectiveItemTaxRate(
      rate: ((product['taxRate'] as num?) ?? 0).toDouble(),
      exempt: product['taxExempt'] == true,
      companyDefault: companyTaxRate);

  // ───────────── documents ─────────────

  Future<OutboxEntry> createSale({
    required String customerGlobalId,
    required List<CartLine> lines,
    required double paid,
  }) async {
    if (lines.isEmpty) throw AppFailure('emptyCart');
    final qty = <String, double>{};
    for (final l in lines) {
      qty[l.productGlobalId] = (qty[l.productGlobalId] ?? 0) + l.quantity;
    }
    for (final e in qty.entries) {
      if (await availableStock(e.key) + 1e-9 < e.value) throw AppFailure('insufficientStock', e.key);
    }
    final totals = computeTotals(lines);
    final paidClamped = paid.clamp(0, totals.total).toDouble();
    final remaining = round2(totals.total - paidClamped);
    final customer = await store.get(Kinds.customers, customerGlobalId);
    if (exceedsCreditLimit(
        balance: await effectiveBalance(customerGlobalId),
        creditLimit: ((customer?['creditLimit'] as num?) ?? 0).toDouble(),
        remaining: remaining)) {
      throw AppFailure('creditExceeded');
    }
    final number = await _takeInvoiceNumber();
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
        'lines': [
          for (final l in lines)
            {'productGlobalId': l.productGlobalId, 'quantity': l.quantity, 'unitPrice': l.unitPrice},
        ],
        'paid': paidClamped,
        'total': totals.total,
        '_remaining': remaining, // local only; ignored by the server
      },
    );
    await store.addOutbox(entry);
    notifyListeners();
    return entry;
  }

  Future<String> _takeInvoiceNumber() async {
    final leases = (await store.all(Kinds.leases))
        .where((l) => l['docType'] == 'sales_invoice' && l['status'] == 'active')
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

  Future<List<Map<String, Object?>>> voucherBooks() async =>
      (await store.all(Kinds.voucherBooks)).where((b) => b['status'] == 'active').toList();

  Future<Set<int>> _usedLeaves(Map<String, Object?> book) async => {
        ...((book['usedNumbers'] as List?) ?? const []).cast<int>(),
        ...((book['cancelledNumbers'] as List?) ?? const []).cast<int>(),
        for (final e in await store.outbox())
          if (e.kind == 'collection' && e.status != OutboxStatus.rejected && e.payload['bookGlobalId'] == book['globalId'])
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
      },
    );
    await store.addOutbox(entry);
    notifyListeners();
    return entry;
  }
}
