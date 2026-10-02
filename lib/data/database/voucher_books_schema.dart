part of 'database.dart';

/// v184 — دفاترُ سندات القبض والصرف («دفاتر السندات»، المرحلة هـ / E3).
///
/// Raw SQL outside Drift's table model (no codegen run), following the
/// `sales_invoice_revenue_account_schema.dart` pattern:
///
/// • `voucher_books` — a numbered paper book of receipt OR payment leaves
///   (`range_from..range_to`) held by one employee/user in one branch.
/// • `voucher_book_leaves_cancelled` — a damaged / voided leaf: the number is
///   burnt, never suggested again, and never accepted on a voucher.
/// • `safe_transactions.book_id` + `book_number` — the leaf a voucher used.
///   `treasury_account_id` — the treasury-side account of an accounting
///   transfer voucher (no safe movement, see [createAccountTransferVoucher]).
///
/// ⚠️ **No UNIQUE index on (book_id, book_number).** Delta pull writes with
///    `INSERT OR REPLACE`; a unique conflict there would silently DELETE the
///    local voucher row. Uniqueness is enforced in [validateVoucherBookLeaf]
///    inside the voucher's own transaction instead.
///
/// Travels by the generic `SELECT *` delta pull (both tables are in
/// `DeltaPullService.pullTables`; the columns ride `safe_transactions`).
extension VoucherBooksSchema on AppDatabase {
  Future<void> ensureVoucherBooksSchema() async {
    final creates =
        _isPostgres ? _voucherBooksPostgresCreate : _voucherBooksSqliteCreate;
    for (final statement in creates) {
      await customStatement(statement);
    }
    for (final column in const [
      'book_id INTEGER',
      'book_number INTEGER',
      'treasury_account_id INTEGER',
    ]) {
      final name = column.split(' ').first;
      if (_isPostgres) {
        await customStatement(
            'ALTER TABLE safe_transactions ADD COLUMN IF NOT EXISTS $column');
        continue;
      }
      final columns =
          await customSelect('PRAGMA table_info(safe_transactions)').get();
      if (columns.any((c) => c.data['name'] == name)) continue;
      try {
        await customStatement('ALTER TABLE safe_transactions ADD COLUMN $column');
      } catch (error) {
        if (!isIdempotentMigrationError(error.toString())) rethrow;
      }
    }
    for (final statement in _voucherBooksIndexes) {
      await customStatement(statement);
    }
  }

  int _voucherBookStamp() => DateTime.now().millisecondsSinceEpoch ~/ 1000;

  /// Every book, newest first; [type] = `receipt` | `payment` filters.
  Future<List<VoucherBook>> listVoucherBooks({
    String? type,
    bool activeOnly = false,
  }) async {
    final where = <String>['deleted_at IS NULL'];
    final vars = <Variable<Object>>[];
    if (type != null) {
      where.add('book_type = ?');
      vars.add(Variable<String>(type));
    }
    if (activeOnly) where.add("status = 'active'");
    final rows = await customSelect(
      'SELECT * FROM voucher_books WHERE ${where.join(' AND ')} '
      'ORDER BY id DESC',
      variables: vars,
    ).get();
    final books = <VoucherBook>[];
    for (final r in rows) {
      books.add(_voucherBookFromRow(r.data,
          usedCount: await _voucherBookUsedCount(r.data['id'] as int)));
    }
    return books;
  }

  Future<VoucherBook?> getVoucherBook(int id) async {
    final row = await customSelect(
      'SELECT * FROM voucher_books WHERE id = ? AND deleted_at IS NULL',
      variables: [Variable<int>(id)],
    ).getSingleOrNull();
    if (row == null) return null;
    return _voucherBookFromRow(row.data,
        usedCount: await _voucherBookUsedCount(id));
  }

  Future<int> _voucherBookUsedCount(int bookId) async {
    final used = await customSelect(
      'SELECT COUNT(*) AS c FROM safe_transactions WHERE book_id = ?',
      variables: [Variable<int>(bookId)],
    ).getSingle();
    final cancelled = await customSelect(
      'SELECT COUNT(*) AS c FROM voucher_book_leaves_cancelled '
      'WHERE book_id = ? AND deleted_at IS NULL',
      variables: [Variable<int>(bookId)],
    ).getSingle();
    return ((used.data['c'] as num?) ?? 0).toInt() +
        ((cancelled.data['c'] as num?) ?? 0).toInt();
  }

  /// Opens a new book. Rejects an empty/inverted range and a range that
  /// overlaps another live book of the same type and prefix.
  Future<int> createVoucherBook({
    required String type,
    required int rangeFrom,
    required int rangeTo,
    String? prefix,
    String? label,
    int? holderEmployeeId,
    int? holderUserId,
    int? branchId,
    String? notes,
  }) async {
    if (type != 'receipt' && type != 'payment') {
      throw VoucherBookException('نوع الدفتر غير صالح.');
    }
    if (rangeFrom <= 0 || rangeTo < rangeFrom) {
      throw VoucherBookException('مدى الأرقام غير صالح.');
    }
    final normalizedPrefix = (prefix ?? '').trim();
    return transaction(() async {
      final overlap = await customSelect(
        'SELECT id FROM voucher_books WHERE deleted_at IS NULL '
        "AND status <> 'cancelled' AND book_type = ? "
        "AND COALESCE(prefix, '') = ? AND range_from <= ? AND range_to >= ? "
        'LIMIT 1',
        variables: [
          Variable<String>(type),
          Variable<String>(normalizedPrefix),
          Variable<int>(rangeTo),
          Variable<int>(rangeFrom),
        ],
      ).getSingleOrNull();
      if (overlap != null) {
        throw VoucherBookException('المدى يتداخل مع دفترٍ قائم.');
      }
      final gid = UuidV7.generate();
      final now = _voucherBookStamp();
      await customInsert(
        'INSERT INTO voucher_books (book_type, prefix, label, range_from, '
        'range_to, next_number, holder_employee_id, holder_user_id, '
        "branch_id, status, notes, created_at, global_id, last_modified_at) "
        "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 'active', ?, ?, ?, ?)",
        variables: [
          Variable<String>(type),
          Variable<String>(normalizedPrefix.isEmpty ? null : normalizedPrefix),
          Variable<String>(label),
          Variable<int>(rangeFrom),
          Variable<int>(rangeTo),
          Variable<int>(rangeFrom),
          Variable<int>(holderEmployeeId),
          Variable<int>(holderUserId),
          Variable<int>(branchId),
          Variable<String>(notes),
          Variable<int>(now),
          Variable<String>(gid),
          Variable<int>(now),
        ],
      );
      final row = await customSelect(
        'SELECT id FROM voucher_books WHERE global_id = ?',
        variables: [Variable<String>(gid)],
      ).getSingle();
      return row.data['id'] as int;
    });
  }

  /// The book the voucher form opens on: the user's own active book of
  /// [type] that still has a free leaf, else the first such book of the
  /// branch, else `null`.
  Future<VoucherBook?> defaultVoucherBookFor({
    required String type,
    int? userId,
    int? branchId,
  }) async {
    final books = await listVoucherBooks(type: type, activeOnly: true);
    final open = books.where((b) => b.remaining > 0).toList();
    return open.where((b) => userId != null && b.holderUserId == userId).firstOrNull ??
        open.where((b) => branchId == null || b.branchId == null || b.branchId == branchId).firstOrNull;
  }

  /// The smallest free leaf at or after the book's `next_number` — skipping
  /// leaves already used by a voucher or cancelled. `null` = book exhausted.
  Future<int?> suggestNextVoucherBookNumber(int bookId) async {
    final book = await getVoucherBook(bookId);
    if (book == null) return null;
    final taken = await _takenVoucherBookLeaves(bookId);
    for (var n = book.nextNumber; n <= book.rangeTo; n++) {
      if (!taken.contains(n)) return n;
    }
    // A leaf skipped earlier (typed out of order) may still be free.
    for (var n = book.rangeFrom; n < book.nextNumber; n++) {
      if (!taken.contains(n)) return n;
    }
    return null;
  }

  Future<Set<int>> _takenVoucherBookLeaves(int bookId) async {
    final used = await customSelect(
      'SELECT book_number AS n FROM safe_transactions '
      'WHERE book_id = ? AND book_number IS NOT NULL',
      variables: [Variable<int>(bookId)],
    ).get();
    final cancelled = await customSelect(
      'SELECT number AS n FROM voucher_book_leaves_cancelled '
      'WHERE book_id = ? AND deleted_at IS NULL',
      variables: [Variable<int>(bookId)],
    ).get();
    return {
      for (final r in [...used, ...cancelled]) (r.data['n'] as num).toInt(),
    };
  }

  /// Throws [VoucherBookException] when [number] may not be written on a
  /// voucher from [bookId]: unknown/closed book, out of range, already used
  /// by another voucher, or cancelled.
  Future<VoucherBook> validateVoucherBookLeaf(int bookId, int number) async {
    final book = await getVoucherBook(bookId);
    if (book == null) throw VoucherBookException('دفتر السندات غير موجود.');
    if (book.status != 'active') {
      throw VoucherBookException('دفتر السندات غير نشط.');
    }
    if (number < book.rangeFrom || number > book.rangeTo) {
      throw VoucherBookException('الرقم {p0} خارج مدى الدفتر ({p1}–{p2}).',
          {'p0': number, 'p1': book.rangeFrom, 'p2': book.rangeTo});
    }
    final used = await customSelect(
      'SELECT id FROM safe_transactions WHERE book_id = ? AND book_number = ? '
      'LIMIT 1',
      variables: [Variable<int>(bookId), Variable<int>(number)],
    ).getSingleOrNull();
    if (used != null) {
      throw VoucherBookException(
          'الرقم {p0} مستخدمٌ في سندٍ آخر.', {'p0': number});
    }
    final cancelled = await customSelect(
      'SELECT id FROM voucher_book_leaves_cancelled WHERE book_id = ? '
      'AND number = ? AND deleted_at IS NULL LIMIT 1',
      variables: [Variable<int>(bookId), Variable<int>(number)],
    ).getSingleOrNull();
    if (cancelled != null) {
      throw VoucherBookException(
          'الورقة {p0} ملغاة (تالفة).', {'p0': number});
    }
    return book;
  }

  /// Stamps voucher row [txnId] with leaf [number] of [bookId] and advances
  /// the book. Validation and stamp share one transaction, so two vouchers
  /// can't take the same leaf on this store.
  Future<void> assignVoucherBookLeaf({
    required int txnId,
    required int bookId,
    required int number,
  }) {
    return transaction(() async {
      await validateVoucherBookLeaf(bookId, number);
      await customUpdate(
        'UPDATE safe_transactions SET book_id = ?, book_number = ? WHERE id = ?',
        variables: [
          Variable<int>(bookId),
          Variable<int>(number),
          Variable<int>(txnId),
        ],
        updates: {safeTransactions},
      );
      await _advanceVoucherBook(bookId);
    });
  }

  /// Burns leaf [number] (damaged / void). It is never suggested again.
  Future<void> cancelVoucherBookLeaf({
    required int bookId,
    required int number,
    required String reason,
    int? userId,
  }) {
    return transaction(() async {
      await validateVoucherBookLeaf(bookId, number);
      final now = _voucherBookStamp();
      await customInsert(
        'INSERT INTO voucher_book_leaves_cancelled (book_id, number, reason, '
        'cancelled_at, user_id, global_id, last_modified_at) '
        'VALUES (?, ?, ?, ?, ?, ?, ?)',
        variables: [
          Variable<int>(bookId),
          Variable<int>(number),
          Variable<String>(reason.trim()),
          Variable<int>(now),
          Variable<int>(userId),
          Variable<String>(UuidV7.generate()),
          Variable<int>(now),
        ],
      );
      await _advanceVoucherBook(bookId);
    });
  }

  Future<List<VoucherBookCancelledLeaf>> listCancelledVoucherLeaves(
      int bookId) async {
    final rows = await customSelect(
      'SELECT number, reason, cancelled_at FROM voucher_book_leaves_cancelled '
      'WHERE book_id = ? AND deleted_at IS NULL ORDER BY number',
      variables: [Variable<int>(bookId)],
    ).get();
    return [
      for (final r in rows)
        VoucherBookCancelledLeaf(
          number: (r.data['number'] as num).toInt(),
          reason: r.data['reason'] as String? ?? '',
          cancelledAt: DateTime.fromMillisecondsSinceEpoch(
              ((r.data['cancelled_at'] as num?) ?? 0).toInt() * 1000),
        ),
    ];
  }

  /// `active` → `closed` | `cancelled` (manual). A closed/cancelled book
  /// offers no leaf to the voucher form.
  Future<void> setVoucherBookStatus(int bookId, String status) async {
    if (!const {'active', 'closed', 'cancelled'}.contains(status)) {
      throw VoucherBookException('حالة الدفتر غير صالحة.');
    }
    await customUpdate(
      'UPDATE voucher_books SET status = ?, last_modified_at = ? WHERE id = ?',
      variables: [
        Variable<String>(status),
        Variable<int>(_voucherBookStamp()),
        Variable<int>(bookId),
      ],
      updates: {safeTransactions},
    );
  }

  /// Who may hold a book — active users (reps / accountants), by name.
  Future<List<({int id, String name})>> listVoucherBookHolders() async {
    final rows = await (select(users)
          ..where((u) => u.isActive.equals(true))
          ..orderBy([(u) => OrderingTerm.asc(u.displayName)]))
        .get();
    return [for (final u in rows) (id: u.id, name: u.displayName)];
  }

  /// The leaf a voucher row was written on — `null` when not from a book.
  Future<({int bookId, int number})?> getVoucherBookLeafOf(int txnId) async {
    final row = await customSelect(
      'SELECT book_id, book_number FROM safe_transactions WHERE id = ?',
      variables: [Variable<int>(txnId)],
    ).getSingleOrNull();
    final b = row?.data['book_id'];
    final n = row?.data['book_number'];
    if (b is! num || n is! num) return null;
    return (bookId: b.toInt(), number: n.toInt());
  }

  Future<void> _advanceVoucherBook(int bookId) async {
    final next = await suggestNextVoucherBookNumber(bookId);
    final book = await getVoucherBook(bookId);
    if (book == null) return;
    await customUpdate(
      'UPDATE voucher_books SET next_number = ?, status = ?, '
      'last_modified_at = ? WHERE id = ?',
      variables: [
        Variable<int>(next ?? book.rangeTo + 1),
        Variable<String>(next == null ? 'closed' : book.status),
        Variable<int>(_voucherBookStamp()),
        Variable<int>(bookId),
      ],
      updates: {safeTransactions},
    );
  }
}

VoucherBook _voucherBookFromRow(Map<String, dynamic> d, {int usedCount = 0}) {
  int? i(Object? v) => v is num ? v.toInt() : null;
  return VoucherBook(
    id: d['id'] as int,
    type: d['book_type'] as String,
    rangeFrom: i(d['range_from'])!,
    rangeTo: i(d['range_to'])!,
    nextNumber: i(d['next_number'])!,
    status: d['status'] as String? ?? 'active',
    prefix: d['prefix'] as String?,
    label: d['label'] as String?,
    holderEmployeeId: i(d['holder_employee_id']),
    holderUserId: i(d['holder_user_id']),
    branchId: i(d['branch_id']),
    notes: d['notes'] as String?,
    usedCount: usedCount,
  );
}

const _voucherBooksSqliteCreate = <String>[
  '''CREATE TABLE IF NOT EXISTS voucher_books (
       id INTEGER PRIMARY KEY AUTOINCREMENT,
       book_type TEXT NOT NULL,
       prefix TEXT,
       label TEXT,
       range_from INTEGER NOT NULL,
       range_to INTEGER NOT NULL,
       next_number INTEGER NOT NULL,
       holder_employee_id INTEGER,
       holder_user_id INTEGER,
       branch_id INTEGER,
       status TEXT NOT NULL DEFAULT 'active',
       notes TEXT,
       created_at INTEGER NOT NULL DEFAULT (strftime('%s','now')),
       global_id TEXT UNIQUE,
       last_modified_at INTEGER,
       deleted_at INTEGER,
       origin_client_id TEXT,
       row_version INTEGER NOT NULL DEFAULT 0
     )''',
  '''CREATE TABLE IF NOT EXISTS voucher_book_leaves_cancelled (
       id INTEGER PRIMARY KEY AUTOINCREMENT,
       book_id INTEGER NOT NULL REFERENCES voucher_books(id),
       number INTEGER NOT NULL,
       reason TEXT,
       cancelled_at INTEGER NOT NULL,
       user_id INTEGER,
       global_id TEXT UNIQUE,
       last_modified_at INTEGER,
       deleted_at INTEGER,
       origin_client_id TEXT,
       row_version INTEGER NOT NULL DEFAULT 0
     )''',
];

const _voucherBooksPostgresCreate = <String>[
  '''CREATE TABLE IF NOT EXISTS voucher_books (
       id SERIAL PRIMARY KEY,
       book_type TEXT NOT NULL,
       prefix TEXT,
       label TEXT,
       range_from INTEGER NOT NULL,
       range_to INTEGER NOT NULL,
       next_number INTEGER NOT NULL,
       holder_employee_id INTEGER,
       holder_user_id INTEGER,
       branch_id INTEGER,
       status TEXT NOT NULL DEFAULT 'active',
       notes TEXT,
       created_at BIGINT NOT NULL DEFAULT EXTRACT(EPOCH FROM NOW())::bigint,
       global_id TEXT UNIQUE,
       last_modified_at BIGINT,
       deleted_at BIGINT,
       origin_client_id TEXT,
       row_version INTEGER NOT NULL DEFAULT 0
     )''',
  '''CREATE TABLE IF NOT EXISTS voucher_book_leaves_cancelled (
       id SERIAL PRIMARY KEY,
       book_id INTEGER NOT NULL REFERENCES voucher_books(id),
       number INTEGER NOT NULL,
       reason TEXT,
       cancelled_at BIGINT NOT NULL,
       user_id INTEGER,
       global_id TEXT UNIQUE,
       last_modified_at BIGINT,
       deleted_at BIGINT,
       origin_client_id TEXT,
       row_version INTEGER NOT NULL DEFAULT 0
     )''',
];

const _voucherBooksIndexes = <String>[
  'CREATE INDEX IF NOT EXISTS idx_voucher_books_type_status '
      'ON voucher_books(book_type, status)',
  'CREATE INDEX IF NOT EXISTS idx_voucher_book_leaves_cancelled_book '
      'ON voucher_book_leaves_cancelled(book_id, number)',
  'CREATE INDEX IF NOT EXISTS idx_safe_transactions_book_leaf '
      'ON safe_transactions(book_id, book_number)',
];
