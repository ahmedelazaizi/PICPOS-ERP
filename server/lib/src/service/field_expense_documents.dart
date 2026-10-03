import 'dart:convert';
import 'dart:typed_data';

import '../db/database.dart';
import 'errors.dart';
import 'field_geo.dart';

/// K-1 — accepted rep expenses not yet posted on the desktop (payload of
/// `/desktop/documents/pending`, kind `expense`).
Future<List<Map<String, Object?>>> pendingExpenseDocuments(CloudDatabase db, int companyId, int limit) async {
  final rows = await db.query('''
    SELECT st.global_id, st.voucher_number, st.doc_date, st.created_at, e.global_id AS eg, r.global_id AS rg,
           sf.global_id AS sg, st.amount, b.global_id AS bg, st.book_number, ec.global_id AS cg, ec.name AS cn,
           st.note, st.over_custody, st.field_geo, st.desktop_error,
           EXISTS (SELECT 1 FROM field_attachments fa WHERE fa.document_global_id = st.global_id) AS has_photo
    FROM safe_transactions st
    JOIN employees e ON e.id = st.rep_employee_id
    LEFT JOIN sales_routes r ON r.id = st.route_id
    LEFT JOIN safes sf ON sf.id = st.safe_id
    LEFT JOIN voucher_books b ON b.id = st.book_id
    LEFT JOIN expense_categories ec ON ec.id = st.expense_category_id
    WHERE st.company_id=@c AND st.category='rep_expense' AND st.posted_on_desktop_at IS NULL
    ORDER BY st.created_at, st.id LIMIT @l''', {'c': companyId, 'l': limit});
  return [
    for (final row in rows)
      () {
        final m = row.toColumnMap();
        return <String, Object?>{
          'kind': 'expense',
          'globalId': m['global_id'],
          'number': m['voucher_number'],
          'date': m['doc_date'] ??
              DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int, isUtc: true).toIso8601String(),
          'createdAt': m['created_at'],
          'repEmployeeGlobalId': m['eg'],
          'routeGlobalId': m['rg'],
          'safeGlobalId': m['sg'],
          'amount': num0(m['amount']),
          'bookGlobalId': m['bg'],
          'bookNumber': m['book_number'],
          'categoryGlobalId': m['cg'],
          'categoryName': m['cn'],
          'note': m['note'],
          'overCustody': m['over_custody'] == true,
          'hasPhoto': m['has_photo'] == true,
          'geo': decodeFieldGeo(m['field_geo']),
          'lastDesktopError': m['desktop_error'],
        };
      }(),
  ];
}

/// The receipt photo of field document [globalId] (`GET
/// /desktop/documents/attachment`), base64 — bounded to 1 MB at the gate.
Future<Map<String, Object?>> fieldAttachment(CloudDatabase db, int companyId, String globalId) async {
  final r = await db.query(
      'SELECT mime, data FROM field_attachments WHERE company_id=@c AND document_global_id=@g', {'c': companyId, 'g': globalId});
  if (r.isEmpty) throw ApiError(404, 'attachment_not_found');
  final data = r.first[1];
  return {
    'globalId': globalId,
    'mime': r.first[0],
    'data': base64.encode(data is Uint8List ? data : Uint8List.fromList((data as List).cast<int>())),
  };
}
