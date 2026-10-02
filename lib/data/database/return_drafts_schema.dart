part of 'database.dart';

/// v189 — مسوّداتُ المرتجعات (J2، قرارُ المالك).
///
/// Raw SQL outside Drift's table model (no codegen run), following the
/// `voucher_books_schema.dart` pattern. One table for both kinds:
///
/// • `return_drafts` — a sales (`kind='sales'`) or purchase
///   (`kind='purchase'`) return saved by «حفظ مسودة». A draft moves NO stock,
///   posts NO journal entry, touches NO safe and burns NO voucher-book leaf;
///   it is plain document state. «مراجعة واعتماد» posts it through the
///   EXISTING `processReturn` path and then stamps the row `posted` with the
///   document number that path generated inside its own transaction.
///
/// ⚠️ **Numbering stays gap-free by construction**: a draft never takes a
///    number from `document_sequences`. The SRET-/PRET- number is drawn by
///    `generateInvoiceNumber` inside the posting transaction (it rolls back
///    with it), so a deleted or abandoned draft leaves no hole. Drafts are
///    identified by their row id (`D-12`).
///
/// Travels by the generic `SELECT *` delta pull (in
/// `DeltaPullService.pullTables`, `_syncHardenedTables`, the server's pull
/// set and the id-namespace floor list — same lists as `voucher_books`).
extension ReturnDraftsSchema on AppDatabase {
  Future<void> ensureReturnDraftsSchema() async {
    await customStatement(
        _isPostgres ? _returnDraftsPostgresCreate : _returnDraftsSqliteCreate);
    for (final statement in _returnDraftsIndexes) {
      await customStatement(statement);
    }
  }

  int _returnDraftStamp() => DateTime.now().millisecondsSinceEpoch ~/ 1000;

  /// Inserts a new draft ([input.id] == null) or rewrites an existing one.
  /// Only a row still in `draft` may be rewritten — a posted/cancelled
  /// return is a document, not a draft.
  Future<int> saveReturnDraft(ReturnDraftInput input) async {
    final lines = jsonEncode({
      for (final e in input.quantities.entries)
        if (e.value > 0) '${e.key}': e.value,
    });
    final now = _returnDraftStamp();
    final values = <Variable<Object>>[
      Variable<int>(input.originalInvoiceId),
      Variable<int>(input.partyId),
      Variable<int>(input.branchId),
      Variable<int>(input.warehouseId),
      Variable<String>(input.reason),
      Variable<String>(input.reasonCategory),
      Variable<String>(lines),
      Variable<int>(input.isFullReturn ? 1 : 0),
      Variable<int>(input.isDamaged ? 1 : 0),
      Variable<double>(input.subtotal),
      Variable<double>(input.tax),
      Variable<double>(input.total),
      Variable<String>(input.settlement),
    ];
    if (input.id != null) {
      final current = await getReturnDraft(input.id!);
      if (current == null) {
        throw ReturnDraftException('المسودة غير موجودة.');
      }
      if (!current.isDraft) {
        throw ReturnDraftException('لا تُعدَّل مسودةٌ اعتُمدت أو أُلغيت.');
      }
      await customUpdate(
        'UPDATE return_drafts SET original_invoice_id = ?, party_id = ?, '
        'branch_id = ?, warehouse_id = ?, reason = ?, reason_category = ?, '
        'lines_json = ?, is_full_return = ?, is_damaged = ?, subtotal = ?, '
        'tax = ?, total = ?, settlement = ?, updated_at = ?, '
        'last_modified_at = ? WHERE id = ?',
        variables: [
          ...values,
          Variable<int>(now),
          Variable<int>(now),
          Variable<int>(input.id!),
        ],
      );
      return input.id!;
    }
    final gid = UuidV7.generate();
    await customInsert(
      'INSERT INTO return_drafts (kind, status, original_invoice_id, party_id, '
      'branch_id, warehouse_id, reason, reason_category, lines_json, '
      'is_full_return, is_damaged, subtotal, tax, total, settlement, user_id, '
      'created_at, updated_at, global_id, last_modified_at) '
      "VALUES (?, 'draft', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
      variables: [
        Variable<String>(input.kind.code),
        ...values,
        Variable<int>(input.userId),
        Variable<int>(now),
        Variable<int>(now),
        Variable<String>(gid),
        Variable<int>(now),
      ],
    );
    final row = await customSelect(
      'SELECT id FROM return_drafts WHERE global_id = ?',
      variables: [Variable<String>(gid)],
    ).getSingle();
    return row.data['id'] as int;
  }

  Future<ReturnDraft?> getReturnDraft(int id) async {
    final row = await customSelect(
      'SELECT * FROM return_drafts WHERE id = ? AND deleted_at IS NULL',
      variables: [Variable<int>(id)],
    ).getSingleOrNull();
    return row == null ? null : _returnDraftFromRow(row.data);
  }

  /// Soft-deletes a draft. A posted/cancelled row is a document and stays.
  Future<void> deleteReturnDraft(int id) async {
    final current = await getReturnDraft(id);
    if (current == null) return;
    if (!current.isDraft) {
      throw ReturnDraftException('لا يُحذَف مرتجعٌ معتمد — ألغِه بدلاً من ذلك.');
    }
    final now = _returnDraftStamp();
    await customUpdate(
      'UPDATE return_drafts SET deleted_at = ?, last_modified_at = ? '
      'WHERE id = ?',
      variables: [Variable<int>(now), Variable<int>(now), Variable<int>(id)],
    );
  }

  /// Stamps a draft `posted` after the existing return path committed it.
  Future<void> markReturnDraftPosted(int id, {String? postedNumber}) async {
    final now = _returnDraftStamp();
    await customUpdate(
      "UPDATE return_drafts SET status = 'posted', posted_number = ?, "
      'posted_at = ?, last_modified_at = ? WHERE id = ? '
      "AND status = 'draft'",
      variables: [
        Variable<String>(postedNumber),
        Variable<int>(now),
        Variable<int>(now),
        Variable<int>(id),
      ],
    );
  }

  /// After `cancelSalesReturn` (which voids EVERY return on the invoice), the
  /// posted drafts of that invoice become `cancelled` — the record keeps them.
  Future<void> markSalesReturnDraftsCancelled(int originalInvoiceId) async {
    final now = _returnDraftStamp();
    await customUpdate(
      "UPDATE return_drafts SET status = 'cancelled', last_modified_at = ? "
      "WHERE kind = 'sales' AND status = 'posted' AND original_invoice_id = ? "
      'AND deleted_at IS NULL',
      variables: [Variable<int>(now), Variable<int>(originalInvoiceId)],
    );
  }

  /// Draft (and, for [statuses], posted/cancelled) rows of [kind] in the
  /// window, newest first, with the original invoice number and party name.
  Future<List<ReturnRecordRow>> listReturnDraftRecords({
    required ReturnDraftKind kind,
    Set<ReturnRecordStatus> statuses = const {ReturnRecordStatus.draft},
    DateTime? from,
    DateTime? to,
    Set<int>? branchIds,
  }) async {
    final invoices =
        kind == ReturnDraftKind.sales ? 'sales_invoices' : 'purchase_invoices';
    final where = <String>[
      'd.deleted_at IS NULL',
      'd.kind = ?',
      'd.status IN (${List.filled(statuses.length, '?').join(', ')})',
    ];
    final vars = <Variable<Object>>[
      Variable<String>(kind.code),
      for (final s in statuses) Variable<String>(s.code),
    ];
    if (from != null) {
      where.add('d.created_at >= ?');
      vars.add(Variable<int>(from.millisecondsSinceEpoch ~/ 1000));
    }
    if (to != null) {
      where.add('d.created_at <= ?');
      vars.add(Variable<int>(to.millisecondsSinceEpoch ~/ 1000));
    }
    if (branchIds != null) {
      where.add(branchIds.isEmpty
          ? 'd.branch_id IS NULL'
          : '(d.branch_id IS NULL OR d.branch_id IN '
              '(${branchIds.join(', ')}))');
    }
    final rows = await customSelect(
      'SELECT d.*, inv.invoice_number AS inv_number, p.name AS party_name '
      'FROM return_drafts d '
      'LEFT JOIN $invoices inv ON inv.id = d.original_invoice_id '
      'LEFT JOIN parties p ON p.id = d.party_id '
      'WHERE ${where.join(' AND ')} ORDER BY d.created_at DESC, d.id DESC '
      'LIMIT 500',
      variables: vars,
    ).get();
    return [
      for (final r in rows)
        () {
          final d = _returnDraftFromRow(r.data);
          return ReturnRecordRow(
            key: 'd${d.id}',
            status: d.status,
            number: d.status == ReturnRecordStatus.draft
                ? d.draftLabel
                : (d.postedNumber ?? d.draftLabel),
            date: d.createdAt,
            originalInvoiceId: d.originalInvoiceId,
            originalInvoiceNumber: r.data['inv_number'] as String?,
            partyName: r.data['party_name'] as String?,
            reason: d.reason,
            settlement: d.settlement,
            tax: d.tax,
            total: d.total,
            isFullReturn: d.isFullReturn,
            draftId: d.id,
          );
        }(),
    ];
  }

  /// SRET-/PRET- vouchers and settlement legs per original invoice, in
  /// posting order — read from the `safe_transactions` rows every posted
  /// return writes (cash/bank legs and the balance memo share one voucher).
  ///
  /// [salesSide] picks `sales_return` vs `purchase_return` references.
  Future<Map<int, List<ReturnVoucherLegs>>> returnVouchersByInvoice(
    List<int> invoiceIds, {
    required bool salesSide,
  }) async {
    if (invoiceIds.isEmpty) return const {};
    final ref = salesSide ? 'sales_return' : 'purchase_return';
    final cashCat = salesSide ? 'sales_return' : 'purchase_return';
    final balanceCat =
        salesSide ? 'sales_return_balance' : 'purchase_return_balance';
    final result = <int, List<ReturnVoucherLegs>>{};
    // دفعاتٌ من ٤٠٠ معرّف: حدُّ متغيّرات SQLite.
    for (var i = 0; i < invoiceIds.length; i += 400) {
      final chunk = invoiceIds.sublist(
          i, i + 400 > invoiceIds.length ? invoiceIds.length : i + 400);
      final rows = await customSelect(
        'SELECT reference_id, voucher_number, category, created_at FROM '
        'safe_transactions WHERE reference_type = ? AND category IN (?, ?) '
        'AND reference_id IN (${List.filled(chunk.length, '?').join(', ')}) '
        'ORDER BY id',
        variables: [
          Variable<String>(ref),
          Variable<String>(cashCat),
          Variable<String>(balanceCat),
          for (final id in chunk) Variable<int>(id),
        ],
        readsFrom: {safeTransactions},
      ).get();
      for (final r in rows) {
        final inv = (r.data['reference_id'] as num).toInt();
        final voucher = r.data['voucher_number'] as String? ?? '';
        final list = result.putIfAbsent(inv, () => []);
        var legs = list.where((l) => l.voucher == voucher).firstOrNull;
        if (legs == null) {
          final at = r.data['created_at'];
          legs = ReturnVoucherLegs(
            voucher,
            at: at is num
                ? DateTime.fromMillisecondsSinceEpoch(at.toInt() * 1000)
                : null,
          );
          list.add(legs);
        }
        if (r.data['category'] == balanceCat) {
          legs.balance = true;
        } else {
          legs.cash = true;
        }
      }
    }
    return result;
  }

  /// Purchase-return documents VOIDED by the existing edit path
  /// (`voidPurchaseReturnDocs` soft-deletes them before re-posting) — the
  /// record shows them as «ملغى».
  Future<List<PurchaseReturnRecord>> listVoidedPurchaseReturnRecords({
    DateTime? from,
    DateTime? to,
    Set<int>? branchIds,
  }) async {
    final supplier = alias(parties, 'sup');
    final query = select(purchaseReturns).join([
      leftOuterJoin(purchaseInvoices,
          purchaseInvoices.id.equalsExp(purchaseReturns.originalInvoiceId)),
      leftOuterJoin(
          supplier, supplier.id.equalsExp(purchaseReturns.supplierId)),
    ]);
    var where = purchaseReturns.isDeleted.equals(true) |
        purchaseReturns.deletedAt.isNotNull();
    if (from != null) {
      where = where & purchaseReturns.returnDate.isBiggerOrEqualValue(from);
    }
    if (to != null) {
      where = where & purchaseReturns.returnDate.isSmallerOrEqualValue(to);
    }
    if (branchIds != null) {
      where = where &
          (purchaseReturns.branchId.isIn(branchIds) |
              purchaseReturns.branchId.isNull());
    }
    query
      ..where(where)
      ..orderBy([
        OrderingTerm.desc(purchaseReturns.returnDate),
        OrderingTerm.desc(purchaseReturns.id),
      ])
      ..limit(500);
    final rows = await query.get();
    return [
      for (final row in rows)
        () {
          final r = row.readTable(purchaseReturns);
          return PurchaseReturnRecord(
            id: r.id,
            originalInvoiceId: r.originalInvoiceId,
            returnDate: r.returnDate,
            subtotal: r.subtotal,
            tax: r.tax,
            total: r.total,
            refundMethod: r.refundMethod,
            isFullReturn: r.isFullReturn,
            originalInvoiceNumber:
                row.readTableOrNull(purchaseInvoices)?.invoiceNumber,
            supplierId: r.supplierId,
            supplierName: row.readTableOrNull(supplier)?.name,
            reason: r.reason,
          );
        }(),
    ];
  }

  /// J2 — one-time grant: every role that could create a return before the
  /// approve step existed (screen code `*_return_view` or `*_return_create`)
  /// gets the matching `*_return_approve`. Admin is covered by the seeder's
  /// catch-all and the runtime admin bypass.
  Future<void> backfillReturnApprovePermissionsOnce() async {
    const flag = 'return_approve_backfill_done';
    if (await getSettingValue(flag) == 'true') return;
    const pairs = <String, List<String>>{
      PermissionCodes.salesReturnApprove: [
        PermissionCodes.salesReturnView,
        PermissionCodes.salesReturnCreate,
      ],
      PermissionCodes.purchasesReturnApprove: [
        PermissionCodes.purchasesReturnView,
        PermissionCodes.purchasesReturnCreate,
      ],
    };
    for (final pair in pairs.entries) {
      final approve = await (select(permissions)
            ..where((p) => p.code.equals(pair.key)))
          .getSingleOrNull();
      if (approve == null) continue;
      final sources = await (select(permissions)
            ..where((p) => p.code.isIn(pair.value)))
          .get();
      if (sources.isEmpty) continue;
      final grants = await (select(rolePermissions)
            ..where((rp) => rp.permissionId.isIn([for (final s in sources) s.id])))
          .get();
      for (final roleId in {for (final g in grants) g.roleId}) {
        await into(rolePermissions).insert(
          RolePermissionsCompanion.insert(
            roleId: roleId,
            permissionId: approve.id,
          ),
          mode: InsertMode.insertOrIgnore,
        );
      }
    }
    await into(settings).insertOnConflictUpdate(
      SettingsCompanion.insert(key: flag, value: const Value('true')),
    );
  }
}

class ReturnDraftException implements Exception {
  ReturnDraftException(this.message);
  final String message;
  @override
  String toString() => message;
}

ReturnDraft _returnDraftFromRow(Map<String, dynamic> d) {
  int? i(Object? v) => v is num ? v.toInt() : null;
  double n(Object? v) => v is num ? v.toDouble() : 0.0;
  DateTime? t(Object? v) => v is num
      ? DateTime.fromMillisecondsSinceEpoch(v.toInt() * 1000)
      : null;
  final quantities = <int, double>{};
  try {
    final decoded = jsonDecode(d['lines_json'] as String? ?? '{}');
    if (decoded is Map) {
      for (final e in decoded.entries) {
        final id = int.tryParse('${e.key}');
        if (id != null && e.value is num) {
          quantities[id] = (e.value as num).toDouble();
        }
      }
    }
  } catch (_) {
    // مسودةٌ تالفةُ الأسطر تُفتَح فارغةً بدل أن تُسقط السجلّ كلَّه.
  }
  return ReturnDraft(
    id: i(d['id'])!,
    kind: ReturnDraftKind.fromCode(d['kind'] as String? ?? 'sales'),
    status: ReturnRecordStatus.fromCode(d['status'] as String?),
    originalInvoiceId: i(d['original_invoice_id']) ?? 0,
    quantities: quantities,
    createdAt: t(d['created_at']) ?? DateTime.now(),
    partyId: i(d['party_id']),
    branchId: i(d['branch_id']),
    warehouseId: i(d['warehouse_id']),
    reason: d['reason'] as String?,
    reasonCategory: d['reason_category'] as String?,
    isFullReturn: i(d['is_full_return']) == 1 || d['is_full_return'] == true,
    isDamaged: i(d['is_damaged']) == 1 || d['is_damaged'] == true,
    subtotal: n(d['subtotal']),
    tax: n(d['tax']),
    total: n(d['total']),
    settlement: d['settlement'] as String?,
    postedNumber: d['posted_number'] as String?,
    postedAt: t(d['posted_at']),
    userId: i(d['user_id']),
    updatedAt: t(d['updated_at']),
  );
}

const _returnDraftsSqliteCreate = '''CREATE TABLE IF NOT EXISTS return_drafts (
       id INTEGER PRIMARY KEY AUTOINCREMENT,
       kind TEXT NOT NULL,
       status TEXT NOT NULL DEFAULT 'draft',
       original_invoice_id INTEGER NOT NULL,
       party_id INTEGER,
       branch_id INTEGER,
       warehouse_id INTEGER,
       reason TEXT,
       reason_category TEXT,
       lines_json TEXT NOT NULL DEFAULT '{}',
       is_full_return INTEGER NOT NULL DEFAULT 0,
       is_damaged INTEGER NOT NULL DEFAULT 0,
       subtotal REAL NOT NULL DEFAULT 0,
       tax REAL NOT NULL DEFAULT 0,
       total REAL NOT NULL DEFAULT 0,
       settlement TEXT,
       posted_number TEXT,
       posted_at INTEGER,
       user_id INTEGER,
       created_at INTEGER NOT NULL DEFAULT (strftime('%s','now')),
       updated_at INTEGER,
       global_id TEXT UNIQUE,
       last_modified_at INTEGER,
       deleted_at INTEGER,
       origin_client_id TEXT,
       row_version INTEGER NOT NULL DEFAULT 0
     )''';

const _returnDraftsPostgresCreate = '''CREATE TABLE IF NOT EXISTS return_drafts (
       id SERIAL PRIMARY KEY,
       kind TEXT NOT NULL,
       status TEXT NOT NULL DEFAULT 'draft',
       original_invoice_id INTEGER NOT NULL,
       party_id INTEGER,
       branch_id INTEGER,
       warehouse_id INTEGER,
       reason TEXT,
       reason_category TEXT,
       lines_json TEXT NOT NULL DEFAULT '{}',
       is_full_return INTEGER NOT NULL DEFAULT 0,
       is_damaged INTEGER NOT NULL DEFAULT 0,
       subtotal DOUBLE PRECISION NOT NULL DEFAULT 0,
       tax DOUBLE PRECISION NOT NULL DEFAULT 0,
       total DOUBLE PRECISION NOT NULL DEFAULT 0,
       settlement TEXT,
       posted_number TEXT,
       posted_at BIGINT,
       user_id INTEGER,
       created_at BIGINT NOT NULL DEFAULT EXTRACT(EPOCH FROM NOW())::bigint,
       updated_at BIGINT,
       global_id TEXT UNIQUE,
       last_modified_at BIGINT,
       deleted_at BIGINT,
       origin_client_id TEXT,
       row_version INTEGER NOT NULL DEFAULT 0
     )''';

const _returnDraftsIndexes = <String>[
  'CREATE INDEX IF NOT EXISTS idx_return_drafts_kind_status '
      'ON return_drafts(kind, status)',
  'CREATE INDEX IF NOT EXISTS idx_return_drafts_invoice '
      'ON return_drafts(original_invoice_id)',
];
