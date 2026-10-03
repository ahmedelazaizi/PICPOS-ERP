part of 'app_controller.dart';

/// K-1 — rep expense (payment) vouchers paid from the custody safe.
///
/// * Categories come from the desktop (`expenseCategories`, each mapped to an
///   expense account there); the leaf comes from the rep's PAYMENT voucher
///   book (`paymentBooks`, same leaf rules as receipts).
/// * Offline first: the document is queued with its `globalId`; an optional
///   receipt photo stays on the device (`_photoPath`) and is sent as base64
///   JPEG (≤ [kMaxExpensePhotoBytes]) when the expense is pushed.
/// * Custody: last-synced served balance ± this device's pending cash
///   documents. Beyond it the company policy decides — `flag` (default: saved
///   and marked «تجاوز العهدة») or `reject`. The server re-checks and wins.
const kExpenseKind = 'expense';

/// Largest receipt photo sent with an expense (the server enforces it too).
const kMaxExpensePhotoBytes = 1024 * 1024;

extension FieldExpenses on AppController {
  /// K-3: the GPS stamp of a new document (null without location support).
  Future<Map<String, Object?>?> _geoStamp() async => geo?.stamp();

  Future<void> _applyExpensePayload(Map<String, dynamic> p) async {
    List<Map<String, Object?>> list(String k) =>
        [for (final x in (p[k] as List? ?? const [])) (x as Map).cast<String, Object?>()];
    await store.upsert(Kinds.expenseCategories, list('expenseCategories'));
    if (p['expenseCategoryScope'] is List) {
      await store.retainOnly(Kinds.expenseCategories, (p['expenseCategoryScope'] as List).cast<String>().toSet());
    }
    await store.upsert(Kinds.paymentBooks, list('paymentBooks'));
    if (p['paymentBookScope'] is List) {
      await store.retainOnly(Kinds.paymentBooks, (p['paymentBookScope'] as List).cast<String>().toSet());
    }
    if (p.containsKey('custodyBalance')) {
      final b = p['custodyBalance'];
      await store.setKv('custodyBalance', b is num ? '$b' : null);
    }
    if (p['expenseOverCustody'] is String) await store.setKv('expenseOverCustody', p['expenseOverCustody'] as String);
  }

  /// Active categories in the desktop's order.
  Future<List<Map<String, Object?>>> expenseCategories() async {
    final c = (await store.all(Kinds.expenseCategories)).where((c) => c['active'] != false).toList()
      ..sort((a, b) => ((a['sortOrder'] as int?) ?? 0).compareTo((b['sortOrder'] as int?) ?? 0));
    return c;
  }

  Future<List<Map<String, Object?>>> paymentBooks() async =>
      (await store.all(Kinds.paymentBooks)).where((b) => b['status'] == 'active').toList();

  /// `flag` (default) or `reject`.
  Future<String> overCustodyPolicy() async => await store.getKv('expenseOverCustody') == 'reject' ? 'reject' : 'flag';

  /// Custody cash the rep holds: served balance (desktop ledger + accepted
  /// unposted field docs) ± documents still in the outbox. Null when the
  /// desktop never sent a balance.
  Future<double?> custodyBalance() async {
    final served = double.tryParse(await store.getKv('custodyBalance') ?? '');
    if (served == null) return null;
    var b = served;
    for (final e in await pendingDocs()) {
      final p = e.payload;
      switch (e.kind) {
        case 'sales_invoice':
          b += ((p['paid'] as num?) ?? 0).toDouble();
        case 'collection':
          b += ((p['amount'] as num?) ?? 0).toDouble();
        case 'sales_return':
          b -= ((p['cashRefund'] as num?) ?? 0).toDouble();
        case kExpenseKind:
          b -= ((p['amount'] as num?) ?? 0).toDouble();
      }
    }
    return _r(b);
  }

  /// Queues an expense paid from the custody safe with leaf [leaf] of the
  /// payment [book]. [photoPath]: a JPEG already stored in app storage.
  Future<OutboxEntry> createExpense({
    required String categoryGlobalId,
    required double amount,
    required Map<String, Object?> book,
    required int leaf,
    String? note,
    String? photoPath,
  }) async {
    if (amount <= 0) throw AppFailure('amount');
    final category = await store.get(Kinds.expenseCategories, categoryGlobalId);
    if (category == null || category['active'] == false) throw AppFailure('categoryRequired');
    if (leaf < (book['rangeFrom'] as int) || leaf > (book['rangeTo'] as int) || (await _usedLeaves(book)).contains(leaf)) {
      throw AppFailure('leafInvalid');
    }
    final balance = await custodyBalance();
    final over = balance != null && balance - amount < -0.005;
    if (over && await overCustodyPolicy() == 'reject') throw AppFailure('custodyExceeded', '$balance');
    final geoStamp = await _geoStamp();
    final gid = AppController._uuid.v4();
    final entry = OutboxEntry(
      globalId: gid,
      kind: kExpenseKind,
      createdAt: _clock(),
      payload: {
        'kind': kExpenseKind,
        'globalId': gid,
        'categoryGlobalId': categoryGlobalId,
        'amount': amount,
        'note': ?_clean(note),
        'bookGlobalId': book['globalId'],
        'bookNumber': leaf,
        'date': _clock().toUtc().toIso8601String(),
        'routeGlobalId': ?routeNames.keys.firstOrNull,
        'geo': ?geoStamp,
        '_bookPrefix': book['prefix'],
        '_categoryName': category['name'],
        '_categoryNameEn': category['nameEn'],
        '_photoPath': ?photoPath,
        '_overCustody': over,
        '_custodyAfter': balance == null ? null : _r(balance - amount),
      },
    );
    await _queue(entry);
    return entry;
  }

  /// Wire form of [e]: device-only keys stripped; an expense's stored receipt
  /// photo attached as base64 JPEG (skipped when missing or oversized — the
  /// expense itself must still go through).
  Future<Map<String, Object?>> _wireDocument(OutboxEntry e) async {
    final w = AppController._wire(e.payload);
    final path = e.payload['_photoPath'];
    if (e.kind == kExpenseKind && path is String) {
      final bytes = await readPhoto(path);
      if (bytes != null && bytes.isNotEmpty && bytes.length <= kMaxExpensePhotoBytes) {
        w['photo'] = {'mime': 'image/jpeg', 'data': base64.encode(bytes)};
      }
    }
    return w;
  }
}
