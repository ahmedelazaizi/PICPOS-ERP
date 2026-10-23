// قراءاتُ منتقي العميل وتبويبِ «الحجوزات» في ملف العميل (P3).
// مكتبةٌ مستقلّة (امتدادٌ على AppDatabase) — تُستورَد من مزوّدات
// `data/providers/customer_picker_providers.dart` لا من الشاشات.
import 'package:drift/drift.dart';

import '../../../core/utils/phone_normalizer.dart';
import '../../../domain/models/party_reservation_entry.dart';
import '../database.dart';

extension CustomerPickerDao on AppDatabase {
  /// بحثٌ بالاسم/الهاتف/الكود في عملاء **نطاق الفرع** (null = كل الفروع).
  ///
  /// الهاتفُ يُطابَق بعد التطبيع (`0101…` = `+20 101…`): لاستعلامٍ رقميٍّ طويل
  /// يُجلَب المرشّحون بآخر 4 خاناتٍ ثم يُرشَّحون في Dart بـ[normalizePhone].
  /// العملاءُ المحذوفون/غيرُ النشطين لا يظهرون (لا اختيارَ لمحذوفٍ).
  Future<List<Party>> searchCustomersForPicker(
    String query, {
    Set<int>? allowedBranchIds,
    int limit = 20,
  }) async {
    if (allowedBranchIds != null && allowedBranchIds.isEmpty) return const [];
    final q = query.trim();
    final vars = <Variable>[];
    final where = StringBuffer(
      'is_active = ${sqlBool(true)} AND is_customer = ${sqlBool(true)} '
      'AND deleted_at IS NULL AND system_role IS NULL',
    );
    if (allowedBranchIds != null) {
      final ids = allowedBranchIds.toList();
      final or = ids
          .map((_) => "(',' || COALESCE(branch_ids, '') || ',') LIKE ?")
          .join(' OR ');
      where.write(' AND (is_global = ${sqlBool(true)} OR $or)');
      vars.addAll([for (final id in ids) Variable.withString('%,$id,%')]);
    }
    final digits = normalizePhone(q);
    final phoneMode = digits.isNotEmpty && RegExp(r'^[\d\s+\-()٠-٩]+$').hasMatch(q);
    if (q.isNotEmpty) {
      if (phoneMode) {
        final tail = digits.substring(digits.length - 4);
        where.write(" AND COALESCE(phone, '') LIKE ?");
        vars.add(Variable.withString('%$tail%'));
      } else {
        where.write(
          " AND (name LIKE ? OR COALESCE(phone, '') LIKE ? OR COALESCE(code, '') LIKE ?)",
        );
        for (var i = 0; i < 3; i++) {
          vars.add(Variable.withString('%$q%'));
        }
      }
    }
    final rows = await customSelect(
      'SELECT * FROM parties WHERE $where ORDER BY name ASC LIMIT ${phoneMode ? 200 : limit}',
      variables: vars,
      readsFrom: {parties},
    ).get();
    var out = rows.map((r) => parties.map(r.data)).toList();
    if (phoneMode) {
      out = out
          .where((p) => normalizePhone(p.phone).endsWith(digits))
          .take(limit)
          .toList();
    }
    return out;
  }

  /// عملاءُ بهذا الهاتف (مطابقةٌ مطبَّعة) داخل نطاق الفرع — لمنع التكرار عند
  /// الإضافة السريعة. أكثرُ من واحدٍ ممكن (هاتفٌ مكرَّر) فيُعرضون كلُّهم.
  Future<List<Party>> findCustomersByPhone(
    String phone, {
    Set<int>? allowedBranchIds,
  }) async {
    final n = normalizePhone(phone);
    if (n.isEmpty) return const [];
    final hits = await searchCustomersForPicker(n,
        allowedBranchIds: allowedBranchIds, limit: 50);
    return hits.where((p) => samePhone(p.phone, phone)).toList();
  }

  /// حجوزاتُ عميلٍ (خدماتٌ + طاولات) — الأحدثُ أولاً.
  Future<List<PartyReservationEntry>> partyReservations(
    int partyId, {
    int limit = 200,
  }) async {
    final rows = await customSelect(
      '''
      SELECT 'table' AS kind, r.id AS id, r.reservation_time AS at,
             r.status AS status, COALESCE(t.name, '') AS place,
             r.party_size AS party_size, 0.0 AS amount,
             NULL AS invoice_number, r.customer_name AS customer_name
        FROM table_reservations r
        LEFT JOIN restaurant_tables t ON t.id = r.table_id
       WHERE r.party_id = ? AND r.deleted_at IS NULL
      UNION ALL
      SELECT 'booking', b.id, b.starts_at, b.status, COALESCE(s.name, ''),
             NULL, b.deposit_amount, si.invoice_number, b.customer_name
        FROM bookings b
        LEFT JOIN booking_services s ON s.id = b.service_id
        LEFT JOIN sales_invoices si ON si.id = b.invoice_id
       WHERE b.party_id = ? AND b.deleted_at IS NULL
      ORDER BY at DESC
      LIMIT ?
      ''',
      variables: [
        Variable.withInt(partyId),
        Variable.withInt(partyId),
        Variable.withInt(limit),
      ],
      readsFrom: {tableReservations, bookings},
    ).get();
    return [
      for (final r in rows)
        PartyReservationEntry(
          kind: r.data['kind'] as String,
          id: (r.data['id'] as num).toInt(),
          at: DateTime.fromMillisecondsSinceEpoch(
              (r.data['at'] as num).toInt() * 1000),
          status: r.data['status'] as String? ?? '',
          place: r.data['place'] as String? ?? '',
          partySize: (r.data['party_size'] as num?)?.toInt(),
          amount: (r.data['amount'] as num?)?.toDouble() ?? 0,
          invoiceNumber: r.data['invoice_number'] as String?,
          customerName: r.data['customer_name'] as String? ?? '',
        ),
    ];
  }

  /// عددُ حجوزات العميل (كلّها) — لبطاقة المنتقي.
  Future<int> partyReservationCount(int partyId) async {
    final row = await customSelect(
      'SELECT (SELECT COUNT(*) FROM table_reservations '
      'WHERE party_id = ? AND deleted_at IS NULL) + '
      '(SELECT COUNT(*) FROM bookings WHERE party_id = ? AND deleted_at IS NULL) '
      'AS c',
      variables: [Variable.withInt(partyId), Variable.withInt(partyId)],
    ).getSingle();
    return (row.data['c'] as num).toInt();
  }

  /// طرفٌ بمعرّفه (حتى لو محذوفاً) — لبطاقة «عميل محذوف».
  Future<Party?> partyByIdAny(int id) =>
      (select(parties)..where((p) => p.id.equals(id))).getSingleOrNull();
}
