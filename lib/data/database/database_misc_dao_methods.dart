part of 'database.dart';

// Small DAO-style helpers that lived directly on AppDatabase: modifier table
// ensure, safe maintenance, stock map and lookups.

extension AppDatabaseMiscDaoMethods on AppDatabase {
  // ═══════════════════════════════════════════════════════════════════════════
  // S01: DAO methods — extracted from UI layer (security hardening)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Ensure modifier tables exist (fallback for pre-v70 DBs).
  Future<void> ensureModifierTables() async {
    // Cluster 030 / Bug C: PostgreSQL doesn't accept SQLite's
    // `INTEGER PRIMARY KEY AUTOINCREMENT` syntax. The previous version
    // passed the SQLite DDL verbatim to PG which crashed every time the
    // server's modifier-management dialog was opened. Branch on
    // `_isPostgres` and emit `SERIAL PRIMARY KEY` (PG) or
    // `INTEGER PRIMARY KEY AUTOINCREMENT` (SQLite). Add a defensive
    // `ALTER TABLE … ADD COLUMN IF NOT EXISTS sort_order` so legacy
    // installs whose table predates the column also self-heal.
    final pkClause = _isPostgres
        ? 'id SERIAL PRIMARY KEY'
        : 'id INTEGER PRIMARY KEY AUTOINCREMENT';
    final boolType = _isPostgres ? 'BOOLEAN' : 'INTEGER';
    final boolFalse = _isPostgres ? 'false' : '0';
    final boolTrue = _isPostgres ? 'true' : '1';

    await customStatement('''
      CREATE TABLE IF NOT EXISTS modifier_groups (
        $pkClause,
        name TEXT NOT NULL,
        type TEXT NOT NULL DEFAULT 'addon',
        min_select INTEGER NOT NULL DEFAULT 0,
        max_select INTEGER NOT NULL DEFAULT 1,
        is_required $boolType NOT NULL DEFAULT $boolFalse,
        is_active $boolType NOT NULL DEFAULT $boolTrue,
        sort_order INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await customStatement('''
      CREATE TABLE IF NOT EXISTS modifier_items (
        $pkClause,
        group_id INTEGER NOT NULL REFERENCES modifier_groups(id) ON DELETE CASCADE,
        name TEXT NOT NULL,
        extra_price REAL NOT NULL DEFAULT 0,
        is_default $boolType NOT NULL DEFAULT $boolFalse,
        is_active $boolType NOT NULL DEFAULT $boolTrue,
        sort_order INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await customStatement('''
      CREATE TABLE IF NOT EXISTS product_modifier_groups (
        $pkClause,
        product_id INTEGER NOT NULL REFERENCES products(id) ON DELETE CASCADE,
        modifier_group_id INTEGER NOT NULL REFERENCES modifier_groups(id) ON DELETE CASCADE,
        sort_order INTEGER NOT NULL DEFAULT 0,
        UNIQUE(product_id, modifier_group_id)
      )
    ''');

    // Defensive ADD COLUMN — older installs whose modifier_groups was
    // created before sort_order was added still work after the schema
    // is reconciled.
    if (_isPostgres) {
      // ٦‑٢: خادمٌ نُصِّب قبل هذا الإصلاح يحمل شكلَ الخطوة 4.5 القديم —
      //   (id, name, min_selection, max_selection, is_active)
      // وينقصه **أربعةٌ** يكتبها `createModifierGroup` لا واحد، فكانت كلُّ
      // محاولةِ إنشاءِ مجموعةٍ تنهار على PG والميزةُ معطَّلةً بالكامل.
      //
      // ⚠️ و`min_selection`/`max_selection` القديمان يبقيان بلا ضرر: لهما
      // `DEFAULT` فالإدراجُ الذي يتجاهلهما يمرّ. وإعادةُ تسميتهما كانت ستحتاج
      // `RENAME COLUMN` بلا `IF EXISTS` — أثقلَ وأخطرَ من إضافةِ الصحيح.
      for (final stmt in [
        "ALTER TABLE modifier_groups ADD COLUMN IF NOT EXISTS type TEXT NOT NULL DEFAULT 'addon'",
        'ALTER TABLE modifier_groups ADD COLUMN IF NOT EXISTS min_select INTEGER NOT NULL DEFAULT 0',
        'ALTER TABLE modifier_groups ADD COLUMN IF NOT EXISTS max_select INTEGER NOT NULL DEFAULT 1',
        'ALTER TABLE modifier_groups ADD COLUMN IF NOT EXISTS is_required BOOLEAN NOT NULL DEFAULT FALSE',
        'ALTER TABLE modifier_groups ADD COLUMN IF NOT EXISTS sort_order INTEGER NOT NULL DEFAULT 0',
        'ALTER TABLE modifier_items ADD COLUMN IF NOT EXISTS sort_order INTEGER NOT NULL DEFAULT 0',
      ]) {
        try {
          await customStatement(stmt);
        } catch (_) {/* already exists */}
      }
    }

    await _ensureModifierSyncColumns();
  }

  /// أعمدةُ المزامنة الخمسةُ على جداول المعدِّلات — 2026-09-21.
  ///
  /// ═══ 🔴 لماذا ═══
  ///
  /// الإضافاتُ والخيارات ميزةٌ مشحونةٌ يستعملها ثمانيةُ ملفّاتٍ في نقطة البيع،
  /// وجداولُها الثلاثةُ كانت **خارجَ قوائم المزامنة الثماني كلِّها**. فمجموعةُ
  /// إضافاتٍ يعرّفها المديرُ لا تصل جهازَ الكاشير أبداً، وسعرُ الخيار — وهو
  /// **يزيد قيمةَ الصنف في الفاتورة** — يختلف من جهازٍ لآخرَ في فاتورتَين.
  ///
  /// وقرارُ المالك 2026-09-21: **بياناتٌ رئيسةٌ عامّةٌ** كالأصناف والفئات —
  /// تعريفٌ واحدٌ يصل كلَّ الأجهزة في كلّ الفروع.
  ///
  /// ⚠️ **ولا `build_runner` في هذا**: الجداولُ الثلاثةُ **SQL خامٌّ** بلا
  ///    صنفِ drift (‏أُنشئت في هجرة v70)، و`_upsertRow` في مسار السحب
  ///    **اسميٌّ وعامّ** — يبني قائمةَ الأعمدة من الصفّ ولا يحتاج بياناتِ
  ///    المحرّك. فالأعمدةُ تُضاف بنفس نمط الـDDL القائم.
  ///
  /// ⚠️ **و`ADD COLUMN IF NOT EXISTS` لا تعرفها SQLite** — ولهذا الكتلةُ
  ///    أعلاه محصورةٌ بـPG. فهنا يُفرَّع: الشرطُ على PG، ومحاولةٌ مبتلَعةُ
  ///    الفشلِ على SQLite (تُخفق حين يوجد العمودُ وهو المطلوب).
  Future<void> _ensureModifierSyncColumns() async {
    const tables = ['modifier_groups', 'modifier_items',
        'product_modifier_groups'];
    final stampType = _isPostgres ? 'BIGINT' : 'INTEGER';
    for (final t in tables) {
      for (final col in [
        'global_id TEXT',
        'last_modified_at $stampType',
        'deleted_at $stampType',
        'origin_client_id TEXT',
        'row_version INTEGER NOT NULL DEFAULT 0',
      ]) {
        final ine = _isPostgres ? 'IF NOT EXISTS ' : '';
        try {
          await customStatement('ALTER TABLE $t ADD COLUMN $ine$col');
        } catch (_) {/* العمودُ موجودٌ — وهو الحالُ الغالب */}
      }
      // ⚠️ **فريدٌ لا عاديّ**: `_upsertRow` يحلّ الصفَّ بالمعرّف العالميّ،
      //    وتكرارُه يعني صفَّين لمجموعةٍ واحدةٍ بعد أوّل سحب.
      try {
        await customStatement(
          'CREATE UNIQUE INDEX IF NOT EXISTS idx_${t}_global_id '
          'ON $t(global_id)',
        );
      } catch (_) {/* موجودٌ */}
    }
  }

  /// Update safe name, bank info.
  /// Update safe details. PostgreSQL-compatible.
  Future<void> updateSafeDetails({
    required int safeId,
    required String name,
    String? bankName,
    String? accountNumber,
  }) async {
    await (update(safes)..where((s) => s.id.equals(safeId))).write(
      SafesCompanion(
        name: Value(name),
        bankName: Value(bankName),
        accountNumber: Value(accountNumber),
      ),
    );
  }

  /// Set a safe as the default for its branch (scoped per-branch).
  /// PostgreSQL-compatible: uses raw SQL with sqlBool().
  Future<void> setDefaultSafe(int safeId) async {
    final falseVal = sqlBool(false);
    final trueVal = sqlBool(true);

    // Look up the target safe's branch
    final targetSafe = await (select(safes)..where((s) => s.id.equals(safeId))).getSingleOrNull();
    final branchId = targetSafe?.branchId;

    // Clear defaults only within the same branch scope
    if (branchId != null) {
      await customStatement(
        'UPDATE safes SET is_default = $falseVal WHERE branch_id = ?',
        [branchId],
      );
    } else {
      // No branch — clear defaults only among safes with no branch
      await customStatement(
        'UPDATE safes SET is_default = $falseVal WHERE branch_id IS NULL',
      );
    }

    await customStatement(
      'UPDATE safes SET is_default = $trueVal, is_active = $trueVal WHERE id = ?',
      [safeId],
    );
  }

  /// Toggle safe active/inactive. PostgreSQL-compatible.
  Future<void> toggleSafeActive(int safeId, bool isActive) async {
    final boolVal = sqlBool(isActive);
    await customStatement(
      'UPDATE safes SET is_active = $boolVal WHERE id = ?',
      [safeId],
    );
  }

  /// Delete a non-default safe. PostgreSQL-compatible.
  ///
  /// Feature 004 (US1, FR-007): rejects deletion when the safe's linked
  /// CoA sub-account has any journal-entry lines. Mirrors the rule already
  /// applied to parties — preserves audit trail integrity.
  Future<void> deleteSafeById(int safeId) async {
    await transaction(() async {
      // Look up the linked account before mutating anything.
      final safe = await (select(safes)
            ..where((s) => s.id.equals(safeId))
            ..limit(1))
          .getSingleOrNull();
      if (safe == null) return;

      if (safe.linkedAccountId != null) {
        final movementCountRow = await customSelect(
          'SELECT COUNT(*) AS c FROM journal_entry_lines WHERE account_id = ?',
          variables: [Variable.withInt(safe.linkedAccountId!)],
        ).getSingle();
        final count = movementCountRow.read<int>('c');
        if (count > 0) {
          throw Exception(
            'لا يمكن حذف الصندوق "${safe.name}" لأن الحساب المرتبط به '
            'يحتوى على قيود محاسبية ($count قيد). يرجى تصفية الحركات أولاً.',
          );
        }
      }

      await (delete(safes)..where((s) => s.id.equals(safeId) & s.isDefault.equals(false))).go();
    });
  }

  /// Get per-product stock for a specific warehouse. PostgreSQL-compatible.
  Future<Map<int, double>> getWarehouseStockMap(int warehouseId) async {
    final rows = await (select(inventoryBalances)
      ..where((ib) => ib.warehouseId.equals(warehouseId))
    ).get();
    final map = <int, double>{};
    for (final row in rows) {
      map[row.productId] = row.quantity;
    }
    return map;
  }

  /// Get journal entry lines with account info (code + name) for display.
  /// PostgreSQL-compatible: uses Drift selectOnly + join.
  Future<List<Map<String, dynamic>>> getJournalEntryLinesWithAccounts(int entryId) async {
    final query = selectOnly(journalEntryLines).join([
      innerJoin(accounts, accounts.id.equalsExp(journalEntryLines.accountId)),
    ]);
    query.addColumns([
      journalEntryLines.debit,
      journalEntryLines.credit,
      journalEntryLines.description,
      accounts.code,
      accounts.name,
    ]);
    query.where(journalEntryLines.entryId.equals(entryId));
    query.orderBy([OrderingTerm.asc(journalEntryLines.id)]);
    
    final rows = await query.get();
    return rows.map((row) => {
      'debit': row.read(journalEntryLines.debit) ?? 0.0,
      'credit': row.read(journalEntryLines.credit) ?? 0.0,
      'description': row.read(journalEntryLines.description),
      'account_code': row.read(accounts.code),
      'account_name': row.read(accounts.name),
    }).toList();
  }

  /// مَن أنشأ القيدَ — اسمُه المعروض، أو `null` حين لا يُعرَف.
  ///
  /// ═══ ولماذا `created_by` لا سجلُّ النشاط ═══
  ///
  /// `created_by` عمودٌ **دفاعيٌّ** (يُكتَب بعبارةٍ خامّ لأنّ drift لا يعرفه)،
  /// يكتبه المسارُ اليدويُّ ويقرؤه ضابطُ «لا يعتمد القيدَ منشئُه». فهو
  /// الحقيقةُ المخزَّنةُ على الصفّ نفسِه.
  ///
  /// ⚠️ **و`null` ثلاثُ حالاتٍ لا واحدة**، وكلُّها تُعرَض «—» لا اسماً
  /// مخمَّناً:
  ///   ‏• قيدٌ **آليّ**: لا منشئَ بشريّاً أصلاً — مصدرُه مستندُه.
  ///   ‏• وقيدٌ **أقدمُ من العمود** (قبل إضافته).
  ///   ‏• ومستخدمٌ حُذف صفُّه — والربطُ `JOIN` فيُسقطه، وهو الصواب:
  ///     «لا يُعرَف» أصدقُ من رقمٍ بلا اسم.
  Future<String?> getJournalEntryCreator(int entryId) async {
    final row = await customSelect(
      'SELECT u.display_name AS creator '
      'FROM journal_entries e '
      'JOIN users u ON u.id = e.created_by '
      'WHERE e.id = ?',
      variables: [Variable.withInt(entryId)],
      readsFrom: {journalEntries, users},
    ).getSingleOrNull();
    final name = row?.read<String?>('creator');
    return (name == null || name.isEmpty) ? null : name;
  }

  /// Search sales invoices by invoice number (LIKE). PostgreSQL-compatible.
  Future<List<SalesInvoiceData>> searchInvoicesByNumber(String query) async {
    return (select(salesInvoices)
      ..where((s) => s.invoiceNumber.like('%$query%') & s.isDeleted.equals(false))
      ..orderBy([(s) => OrderingTerm.desc(s.invoiceDate)])
      ..limit(20)
    ).get();
  }

  /// Search customers / parties by phone (LIKE). PostgreSQL-compatible.
  Future<List<Party>> searchCustomerByPhone(String phone) async {
    return (select(parties)
      ..where((p) => p.phone.like('%$phone%') & p.isCustomer.equals(true))
      ..limit(1)
    ).get();
  }
}
