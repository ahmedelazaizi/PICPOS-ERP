import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import '../../data/database/database.dart';
import '../../domain/models/distribution_model.dart';
import '../../domain/models/voucher_book.dart';
import 'cloud_document_poster.dart';

/// K-1 — posts an accepted cloud `expense` (a rep's expense paid from his
/// custody safe with a leaf of his PAYMENT voucher book) through the
/// **existing** payment-voucher path: `createPaymentVoucher` (Dr the
/// category's expense account via `linkedAccountId` / Cr the custody safe's
/// account), then `assignVoucherBookLeaf` and the explicit rep/route stamp.
///
/// Idempotent by the cloud `globalId` kept on the voucher row; any unknown
/// reference or desktop refusal raises [CloudPostingException] and nothing is
/// written (the caller records a conflict).
Future<CloudPostedRef> postCloudExpense(AppDatabase db, Map<String, dynamic> doc,
    {required int postingUserId}) async {
  final gid = doc['globalId'] as String;
  final existing = await (db.select(db.safeTransactions)
        ..where((t) => t.globalId.equals(gid)))
      .getSingleOrNull();
  if (existing != null) {
    return CloudPostedRef('${existing.id}', existing.voucherNumber);
  }
  Future<int?> idOf(String table, Object? g) async {
    if (g is! String || g.isEmpty) return null;
    final row = await db.customSelect(
      'SELECT id FROM $table WHERE global_id = ? LIMIT 1',
      variables: [Variable<String>(g)],
    ).getSingleOrNull();
    return (row?.data['id'] as num?)?.toInt();
  }

  final safeId = await idOf('safes', doc['safeGlobalId']);
  if (safeId == null) {
    throw CloudPostingException('custody_safe_not_found', '${doc['safeGlobalId']}');
  }
  final repId = await idOf('employees', doc['repEmployeeGlobalId']);
  if (repId == null) {
    throw CloudPostingException('rep_not_found', '${doc['repEmployeeGlobalId']}');
  }
  final routeId = await idOf('sales_routes', doc['routeGlobalId']);
  final bookId = await idOf('voucher_books', doc['bookGlobalId']);
  if (bookId == null) {
    throw CloudPostingException('voucher_book_not_found', '${doc['bookGlobalId']}');
  }
  final leaf = doc['bookNumber'];
  if (leaf is! int) throw CloudPostingException('book_number_required');
  final amount = doc['amount'] is num ? (doc['amount'] as num).toDouble() : 0.0;
  if (amount <= 0) throw CloudPostingException('invalid_amount');
  final category = doc['categoryGlobalId'] is String
      ? await db.fieldExpenseCategoryByGlobalId(doc['categoryGlobalId'] as String)
      : null;
  if (category == null) {
    throw CloudPostingException(
        'expense_category_not_found', '${doc['categoryGlobalId']}');
  }
  final account = await db.accountingDao.getAccountByCode(category.accountCode);
  if (account == null) {
    throw CloudPostingException('expense_account_not_found', category.accountCode);
  }
  final note = doc['note'] is String && (doc['note'] as String).trim().isNotEmpty
      ? (doc['note'] as String).trim()
      : null;
  final description = [
    'Cloud ${doc['number'] ?? ''}'.trim(),
    category.name,
    ?note,
    if (doc['overCustody'] == true) 'تجاوز العهدة',
  ].join(' — ');

  return db.transaction(() async {
    try {
      await db.validateVoucherBookLeaf(bookId, leaf);
    } on VoucherBookException catch (e) {
      throw CloudPostingException('voucher_book_leaf_rejected', e.message);
    }
    final txnId = await db.createPaymentVoucher(
      amount: amount,
      category: 'expense',
      safeId: safeId,
      userId: postingUserId,
      globalId: gid,
      linkedAccountId: account.id,
      description: description,
    );
    await db.assignVoucherBookLeaf(txnId: txnId, bookId: bookId, number: leaf);
    await db.stampDocumentRep('safe_transactions', txnId, null,
        explicit: RepStamp(repEmployeeId: repId, routeId: routeId));
    final row = await (db.select(db.safeTransactions)
          ..where((t) => t.id.equals(txnId)))
        .getSingle();
    return CloudPostedRef('$txnId', row.voucherNumber);
  });
}

/// K-3 — stores the van GPS stamp (`doc['geo']`) on the desktop row the
/// document became: `route_visits` (lat/lng + JSON), `sales_invoices` and
/// `safe_transactions` (JSON). Never fails the posting: a missing column or
/// row only logs. Returns are not stamped (no raw column on their rows).
Future<void> stampCloudFieldGeo(AppDatabase db, Map<String, dynamic> doc) async {
  final geo = doc['geo'];
  final gid = doc['globalId'];
  if (geo is! Map || gid is! String) return;
  final json = jsonEncode(geo);
  final ok = geo['status'] == 'ok' && geo['lat'] is num && geo['lng'] is num;
  try {
    switch (doc['kind']) {
      case 'visit':
        await db.customUpdate(
          'UPDATE route_visits SET field_geo = ?, latitude = ?, longitude = ? '
          'WHERE global_id = ?',
          variables: [
            Variable<String>(json),
            Variable<double>(ok ? (geo['lat'] as num).toDouble() : null),
            Variable<double>(ok ? (geo['lng'] as num).toDouble() : null),
            Variable<String>(gid),
          ],
          updates: {db.routeVisits},
        );
      case 'sales_invoice':
        await db.customUpdate(
          'UPDATE sales_invoices SET field_geo = ? WHERE global_id = ?',
          variables: [Variable<String>(json), Variable<String>(gid)],
          updates: {db.salesInvoices},
        );
      case 'collection' || 'expense':
        await db.customUpdate(
          'UPDATE safe_transactions SET field_geo = ? WHERE global_id = ?',
          variables: [Variable<String>(json), Variable<String>(gid)],
          updates: {db.safeTransactions},
        );
    }
  } catch (e) {
    debugPrint('[CLOUD-SYNC] geo stamp skipped for $gid: $e');
  }
}
