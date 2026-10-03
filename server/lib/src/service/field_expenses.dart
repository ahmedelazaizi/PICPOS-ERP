import 'dart:convert';
import 'dart:typed_data';

import 'package:picpos_rules/picpos_rules.dart' show round2;
import 'package:postgres/postgres.dart';

import '../db/database.dart';
import 'errors.dart';

/// Largest receipt photo accepted with an expense (decoded JPEG bytes).
const kMaxExpensePhotoBytes = 1024 * 1024;

/// `companies.expense_over_custody`: what the gate does when an expense would
/// take the rep's custody below zero (owner decision K-1: default «flag»).
const kOverCustodyPolicies = {'flag', 'reject'};

/// A voucher-book leaf claimed for a field document (phase E rules, same as
/// desktop `validateVoucherBookLeaf` / `_advanceVoucherBook`).
typedef ClaimedLeaf = ({int bookId, int leaf, String voucherNumber});

/// Validates leaf [leaf] of book [bookGid] (type [bookType], held by the
/// session rep, active, in range, not cancelled, not used) and advances the
/// book's `next_number` (closing it when exhausted). The caller inserts the
/// `safe_transactions` row in the same transaction (unique `(book_id,
/// book_number)` backs the "not used" rule against concurrent pushes).
Future<ClaimedLeaf> claimBookLeaf(CloudDatabase db, Session s, DeviceContext d, Object? bookGid, Object? leaf,
    {required String bookType}) async {
  if (bookGid is! String || leaf is! int) throw DocRejected('book_number_required');
  final books = await db.q(s, '''
    SELECT id, prefix, range_from, range_to, next_number, status, holder_employee_id
    FROM voucher_books WHERE company_id=@c AND global_id=@g AND book_type=@t
      AND deleted_at IS NULL FOR UPDATE''', {'c': d.companyId, 'g': bookGid, 't': bookType});
  if (books.isEmpty) throw DocRejected('book_not_found');
  final b = books.first.toColumnMap();
  if (b['status'] != 'active') throw DocRejected('book_not_active');
  if (b['holder_employee_id'] != d.employeeId) throw DocRejected('book_not_held_by_rep');
  final from = b['range_from'] as int, to = b['range_to'] as int;
  if (leaf < from || leaf > to) throw DocRejected('book_number_out_of_range', '$leaf');
  final cancelled = (await db.q(s, 'SELECT number FROM voucher_book_leaves_cancelled WHERE book_id=@b', {'b': b['id']}))
      .map((r) => r[0] as int)
      .toSet();
  if (cancelled.contains(leaf)) throw DocRejected('book_leaf_cancelled', '$leaf');
  final used = (await db.q(s, 'SELECT book_number FROM safe_transactions WHERE book_id=@b', {'b': b['id']}))
      .map((r) => r[0] as int)
      .toSet();
  if (used.contains(leaf)) throw DocRejected('book_leaf_used', '$leaf');

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
  return (bookId: b['id'] as int, leaf: leaf, voucherNumber: '${b['prefix'] ?? ''}$leaf');
}

/// Served custody balance of safe [safeId]: the last balance pushed by the
/// desktop ledger plus the accepted field cash movements the desktop has not
/// posted yet (sales cash and collections in, cash refunds and expenses
/// out). Null while the desktop never sent a balance (no check possible).
Future<double?> custodyBalance(CloudDatabase db, Session s, int safeId) async {
  final r = await db.q(s, '''
    SELECT sf.desktop_balance
      + COALESCE((SELECT SUM(paid) FROM sales_invoices WHERE safe_id=@s AND posted_on_desktop_at IS NULL), 0)
      - COALESCE((SELECT SUM(cash_refund) FROM sales_returns WHERE safe_id=@s AND posted_on_desktop_at IS NULL), 0)
      + COALESCE((SELECT SUM(amount) FROM safe_transactions WHERE safe_id=@s AND category='customer_collection'
                  AND posted_on_desktop_at IS NULL), 0)
      - COALESCE((SELECT SUM(amount) FROM safe_transactions WHERE safe_id=@s AND category='rep_expense'
                  AND posted_on_desktop_at IS NULL), 0)
    FROM safes sf WHERE sf.id=@s''', {'s': safeId});
  if (r.isEmpty || r.first[0] == null) return null;
  return round2(num0(r.first[0]));
}

String? _text(Object? v, int max) {
  if (v is! String || v.trim().isEmpty) return null;
  final t = v.trim();
  return t.length > max ? t.substring(0, max) : t;
}

/// Decoded receipt photo (`{mime: 'image/jpeg', data: <base64>}`), or null.
Uint8List? _photo(Object? raw) {
  if (raw == null) return null;
  if (raw is! Map || raw['mime'] != 'image/jpeg' || raw['data'] is! String) throw DocRejected('invalid_photo');
  final data = raw['data'] as String;
  // base64 length bound first: never decode an oversized string.
  if (data.length > (kMaxExpensePhotoBytes * 4 / 3).ceil() + 4) throw DocRejected('photo_too_large');
  final Uint8List bytes;
  try {
    bytes = base64.decode(data);
  } on FormatException {
    throw DocRejected('invalid_photo');
  }
  if (bytes.length > kMaxExpensePhotoBytes) throw DocRejected('photo_too_large');
  if (bytes.length < 3 || bytes[0] != 0xFF || bytes[1] != 0xD8) throw DocRejected('invalid_photo');
  return bytes;
}

/// K-1 — `expense` document: the rep pays an expense (fuel, porters, parking,
/// …) from his custody safe with a leaf of his PAYMENT voucher book. Stored as
/// a `safe_transactions` payment (`category='rep_expense'`); the desktop
/// poster later posts it through its payment-voucher path (Dr the category's
/// expense account / Cr the custody safe) and acknowledges it.
///
/// Idempotency is the generic `sync_idempotency` replay of `_pushOne`.
Future<Map<String, Object?>> acceptExpense(
    CloudDatabase db, Session s, DeviceContext d, String gid, Map<String, Object?> doc) async {
  final amount = doc['amount'];
  if (amount is! num) throw DocRejected('invalid_field', 'amount');
  if (amount <= 0) throw DocRejected('invalid_amount');
  final catGid = doc['categoryGlobalId'];
  final cat = await db.q(s, '''
    SELECT id, name FROM expense_categories
    WHERE company_id=@c AND global_id=@g AND is_active AND deleted_at IS NULL''',
      {'c': d.companyId, 'g': catGid is String ? catGid : ''});
  if (cat.isEmpty) throw DocRejected('unknown_expense_category');
  final photo = _photo(doc['photo']);

  final res = await db.q(s, 'SELECT custody_safe_id FROM rep_resources WHERE employee_id=@e AND deleted_at IS NULL',
      {'e': d.employeeId});
  final safeId = res.isEmpty ? null : res.first[0] as int?;
  if (safeId == null) throw DocRejected('no_custody_safe');
  // Lock the custody safe: concurrent expenses of the rep see each other.
  await db.q(s, 'SELECT id FROM safes WHERE id=@s FOR UPDATE', {'s': safeId});

  final leaf = await claimBookLeaf(db, s, d, doc['bookGlobalId'], doc['bookNumber'], bookType: 'payment');

  final value = round2(amount.toDouble());
  final before = await custodyBalance(db, s, safeId);
  final over = before != null && before - value < -0.005;
  final policy = (await db.q(s, 'SELECT expense_over_custody FROM companies WHERE id=@c', {'c': d.companyId}))
      .first[0] as String;
  if (over && policy == 'reject') {
    throw DocRejected('custody_exceeded', null, {'custodyBalance': before, 'amount': value});
  }

  final routeGid = doc['routeGlobalId'];
  final route = await db.q(s, '''
    SELECT id FROM sales_routes WHERE company_id=@c AND sales_rep_id=@e AND is_active AND deleted_at IS NULL
    ORDER BY (global_id = @g) DESC, id LIMIT 1''',
      {'c': d.companyId, 'e': d.employeeId, 'g': routeGid is String ? routeGid : ''});
  final date = DateTime.tryParse('${doc['date']}')?.toUtc() ?? DateTime.now().toUtc();

  await db.q(s, '''
    INSERT INTO safe_transactions (company_id, global_id, voucher_number, safe_id, transaction_type, category,
      amount, employee_id, rep_employee_id, route_id, book_id, book_number, reference_type, device_pk,
      origin_client_id, expense_category_id, note, doc_date, over_custody, created_at)
    VALUES (@c, @g, @vn, @sf, 'payment', 'rep_expense', @a, @e, @e, @r, @b, @n, 'mobile_expense', @d, @o,
      @cat, @nt, @dt, @ov, now_ms())''', {
    'c': d.companyId,
    'g': gid,
    'vn': leaf.voucherNumber,
    'sf': safeId,
    'a': value,
    'e': d.employeeId,
    'r': route.isEmpty ? null : route.first[0],
    'b': leaf.bookId,
    'n': leaf.leaf,
    'd': d.devicePk,
    'o': d.deviceId,
    'cat': cat.first[0],
    'nt': _text(doc['note'], 500),
    'dt': date.toIso8601String(),
    'ov': over,
  });
  if (photo != null) {
    await db.q(s, '''
      INSERT INTO field_attachments (company_id, document_global_id, mime, size_bytes, data, created_at)
      VALUES (@c, @g, 'image/jpeg', @sz, @data, now_ms())''', {
      'c': d.companyId,
      'g': gid,
      'sz': photo.length,
      'data': TypedValue(Type.byteArray, photo),
    });
  }
  return {
    'globalId': gid,
    'status': 'accepted',
    'kind': 'expense',
    'number': leaf.voucherNumber,
    'custodyBalance': before == null ? null : round2(before - value),
    'overCustody': over,
    if (over) 'flags': ['over_custody'],
  };
}

/// Book rows (held by the session rep, of [bookType]) as served to the device:
/// only rows changed since [since], plus the complete scope.
Future<({List<Map<String, Object?>> rows, List<Object?> scope})> heldBooks(
    CloudDatabase db, Session s, DeviceContext d, int since, String bookType) async {
  final books = await db.q(s, '''
    SELECT id, global_id, prefix, label, range_from, range_to, next_number, status, last_modified_at
    FROM voucher_books WHERE company_id=@c AND holder_employee_id=@e AND book_type=@t
      AND deleted_at IS NULL ORDER BY id''', {'c': d.companyId, 'e': d.employeeId, 't': bookType});
  final out = <Map<String, Object?>>[];
  for (final b in books) {
    final m = b.toColumnMap();
    if ((m['last_modified_at'] as int) <= since) continue;
    final used = await db.q(s, 'SELECT book_number FROM safe_transactions WHERE book_id=@b ORDER BY 1', {'b': m['id']});
    final cancelled =
        await db.q(s, 'SELECT number FROM voucher_book_leaves_cancelled WHERE book_id=@b ORDER BY 1', {'b': m['id']});
    out.add({
      'globalId': m['global_id'],
      'bookType': bookType,
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
  return (rows: out, scope: [for (final b in books) b.toColumnMap()['global_id']]);
}

/// K-1 pull additions: expense categories, the rep's payment books, the
/// served custody balance and the over-custody policy.
Future<Map<String, Object?>> expensePullExtras(CloudDatabase db, Session s, DeviceContext d, int since) async {
  final cats = await db.q(s, '''
    SELECT global_id, name, name_en, sort_order, is_active, deleted_at, last_modified_at
    FROM expense_categories WHERE company_id=@c ORDER BY sort_order, id''', {'c': d.companyId});
  final books = await heldBooks(db, s, d, since, 'payment');
  final res = await db.q(s, 'SELECT custody_safe_id FROM rep_resources WHERE employee_id=@e AND deleted_at IS NULL',
      {'e': d.employeeId});
  final safeId = res.isEmpty ? null : res.first[0] as int?;
  final policy = (await db.q(s, 'SELECT expense_over_custody FROM companies WHERE id=@c', {'c': d.companyId}))
      .first[0];
  return {
    'expenseCategories': [
      for (final r in cats)
        if ((r[6] as int) > since)
          {
            'globalId': r[0],
            'name': r[1],
            'nameEn': r[2],
            'sortOrder': r[3],
            'active': r[4] == true && r[5] == null,
          },
    ],
    'expenseCategoryScope': [
      for (final r in cats)
        if (r[4] == true && r[5] == null) r[0],
    ],
    'paymentBooks': books.rows,
    'paymentBookScope': books.scope,
    'custodyBalance': safeId == null ? null : await custodyBalance(db, s, safeId),
    'expenseOverCustody': policy,
  };
}
