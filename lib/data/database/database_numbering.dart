part of 'database.dart';

// Voucher / invoice numbering: generateInvoiceNumber, counter peek, gap audit
// and prefix validation. The prefix constants/maps stay on the class
// (public API `AppDatabase.default*Prefix`).

extension AppDatabaseNumbering on AppDatabase {
  /// Generate a unique, thread-safe invoice number based on DocumentSequences.
  ///
  /// Takes either a canonical prefix (`POS`, `SINV`, `SRET`, `PINV`, `PRET`,
  /// `RCPT`, `PMT`, `QUOT`) or a legacy alias (`R-`, `INV`, `RET-`, `PUR`,
  /// `RV`, `PV`, `QUO`, ...). All aliases are normalised to their canonical
  /// form up-front, so legacy call-sites keep working without changes.
  ///
  /// User overrides from the "إعدادات ترقيم المستندات" screen (settings
  /// keyed by [_prefixSettingKeys]) are honoured verbatim as the DISPLAY
  /// prefix. The SEQUENCE counter stays locked to the canonical prefix
  /// so renaming the display prefix never restarts the counter.
  ///
  /// Output format: `<DISPLAY>-<counter>` (e.g. `POS-1`, `SINV-42`) since the
  /// 2026-04 product change. Unified across every document type so the printed
  /// invoices look consistent.
  ///
  /// On PostgreSQL the counter row is locked with `FOR UPDATE` before it is
  /// read — without that, concurrent callers on separate connections issue
  /// duplicate numbers, and there is no UNIQUE index on `invoice_number` to
  /// catch them.
  Future<String> generateInvoiceNumber(String prefix) async {
    // 066 (D5-001) — defensive guard. The counter advance and the dependent
    // voucher insert MUST be atomic; Drift makes a nested transaction() into
    // a SAVEPOINT only when the caller is already in a transaction. Calling
    // bare → the inner txn commits independently → if the caller's insert
    // fails the counter is permanently advanced → Egyptian-VAT-illegal gap.
    // See specs/066-voucher-numbering-atomicity/contracts/numbering-atomicity.md C-1.
    // ignore: invalid_use_of_internal_member
    if (identical(resolvedEngine, this)) {
      throw StateError(
        'generateInvoiceNumber must be called inside a db.transaction(). '
        'See specs/066-voucher-numbering-atomicity/contracts/numbering-atomicity.md',
      );
    }
    return transaction(() async {
      debugPrint(
        '[GEN_INV_DEBUG] generateInvoiceNumber called with prefix: "$prefix"',
      );

      // Normalise any legacy alias onto its canonical prefix. Unknown
      // prefixes (e.g. `VD` / `ADV` used by ad-hoc helpers) pass through
      // unchanged — they still follow the same counter + format pipeline.
      final normalizedPrefix = AppDatabase._prefixAliases[prefix] ?? prefix;

      // Check for user-configured custom prefix for this document type.
      String displayPrefix = normalizedPrefix;
      final settingKey = AppDatabase._prefixSettingKeys[normalizedPrefix];
      if (settingKey != null) {
        final customPrefix = await getSettingValue(settingKey);
        if (customPrefix != null && customPrefix.isNotEmpty) {
          displayPrefix = customPrefix;
        } else {
          // Legacy fallback: the old single `invoice_code_prefix` setting
          // still applies to all three sales-side types if nobody set a
          // per-type override.
          final isSalesPrefix = normalizedPrefix == AppDatabase.defaultSalesPosPrefix ||
              normalizedPrefix == AppDatabase.defaultSalesManualPrefix ||
              normalizedPrefix == AppDatabase.defaultSalesReturnPrefix;
          if (isSalesPrefix) {
            final legacyPrefix = await getSettingValue('invoice_code_prefix');
            if (legacyPrefix != null && legacyPrefix.isNotEmpty) {
              displayPrefix = legacyPrefix;
            }
          }
        }
      }

      // PostgreSQL: take the row lock BEFORE reading the counter.
      //
      // The read-modify-write below is only atomic if nobody else can read the
      // same `next_value` in between. On SQLite that is free — the global write
      // lock serialises the whole transaction. On PostgreSQL under READ
      // COMMITTED it is not: two connections both read N, both compute N, and
      // the second UPDATE simply blocks until the first commits and then writes
      // the same N+1. Both callers walk away holding document number N.
      //
      // Measured on a live PG with two connections: 16 allocations produced 8
      // distinct numbers — a 100% collision rate on every concurrent pair, not
      // an intermittent race. And nothing catches it downstream: there is no
      // UNIQUE index on `invoice_number` (see the note where the number is
      // returned).
      //
      // `FOR UPDATE` makes the second reader wait for the first to commit, so
      // it reads N+1 and the sequence advances correctly.
      if (_isPostgres) {
        await customStatement(
          'SELECT 1 FROM document_sequences WHERE prefix = ? FOR UPDATE',
          [normalizedPrefix],
        );
      }

      // Counter lives on the canonical prefix so a display-prefix change
      // from the settings screen never rewinds the sequence.
      final existing = await (select(
        documentSequences,
      )..where((s) => s.prefix.equals(normalizedPrefix))..limit(1))
          .getSingleOrNull();

      if (existing == null) {
        // First-time backfill: count rows that already share the same
        // canonical prefix or any of its aliases so we don't re-use an
        // existing number. Bounded query (`LIKE prefix%`) and also a
        // scan over aliases so legacy `INV...` rows don't collide with
        // fresh `SINV...` ones.
        final aliasesForThis = AppDatabase._prefixAliases.entries
            .where((e) => e.value == normalizedPrefix)
            .map((e) => e.key)
            .toList()
          ..add(normalizedPrefix);

        int maxExisting = 0;
        for (final alias in aliasesForThis) {
          final count = await (selectOnly(salesInvoices)
                ..addColumns([salesInvoices.id.count()])
                ..where(salesInvoices.invoiceNumber.like('$alias%')))
              .map((row) => row.read(salesInvoices.id.count()))
              .getSingle();
          if ((count ?? 0) > maxExisting) maxExisting = count!;
        }

        // Seed the row at the FIRST number to hand out and let the shared
        // allocation below consume it. The insert must be idempotent: the
        // `FOR UPDATE` above locks nothing when the row does not exist yet, so
        // two connections racing the very first use of a prefix both land here
        // and both try to INSERT. A plain insert makes the loser die on
        // `23505 document_sequences_pkey`, which aborts the whole caller
        // transaction — i.e. the first sale on a newly configured prefix fails.
        // Losing the race is not an error: the winner seeded the identical
        // value, so DO NOTHING and read it back under the lock.
        final seed = maxExisting + 1;
        if (_isPostgres) {
          await customStatement(
            'INSERT INTO document_sequences (prefix, next_value) '
            'VALUES (?, ?) ON CONFLICT (prefix) DO NOTHING',
            [normalizedPrefix, seed],
          );
          // The seed insert above is what the earlier FOR UPDATE could not
          // lock. Take the lock now that the row is guaranteed to exist.
          await customStatement(
            'SELECT 1 FROM document_sequences WHERE prefix = ? FOR UPDATE',
            [normalizedPrefix],
          );
        } else {
          await into(documentSequences).insert(
            DocumentSequencesCompanion.insert(
              prefix: normalizedPrefix,
              nextValue: Value(seed),
            ),
            mode: InsertMode.insertOrIgnore,
          );
        }
      }

      // Single allocation path for both the freshly seeded and the existing
      // row, so the counter advances in exactly one place under exactly one
      // lock. Re-read rather than reusing `existing`: when this call lost the
      // seed race, or waited on another transaction's FOR UPDATE, the
      // committed value has moved on.
      final seq = await (select(
        documentSequences,
      )..where((s) => s.prefix.equals(normalizedPrefix))..limit(1))
          .getSingleOrNull();

      final nextNumber = seq?.nextValue ?? 1;
      await (update(
        documentSequences,
      )..where((s) => s.prefix.equals(normalizedPrefix))).write(
        DocumentSequencesCompanion(nextValue: Value(nextNumber + 1)),
      );

      // Simplified format: `<DISPLAY>-<counter>` (e.g. `POS-1`, `SINV-42`).
      // Per product request 2026-04: drop the year + 6-digit zero-pad. Counter
      // is unbounded and human-readable.
      //
      // NOTE: this used to claim uniqueness was "guaranteed by the sequence
      // plus the UNIQUE index on invoice_number". There is no such index, on
      // either backend — `SalesInvoices.invoiceNumber` and
      // `PurchaseInvoices.invoiceNumber` are plain `text().withLength(max: 50)`
      // and the partial unique index was deliberately deferred because customer
      // databases may already hold duplicates (see
      // client_issue_m4_duplicate_invoice_no_test.dart). The sequence is the
      // ONLY guarantee, which is why the `FOR UPDATE` lock above is load-bearing
      // rather than defensive.
      return '$displayPrefix-$nextNumber';
    });
  }

  /// 066 (D5-001) — read-only peek at the per-prefix counter, used by tests
  /// to verify counter rollback on caller failure (see
  /// `test/unit/voucher_numbering_atomicity_test.dart`). Returns `0` if no
  /// row exists yet for the prefix (first-time-use state).
  @visibleForTesting
  Future<int> peekNumberingCounter(String prefix) async {
    final normalizedPrefix = AppDatabase._prefixAliases[prefix] ?? prefix;
    final seq = await (select(documentSequences)
          ..where((s) => s.prefix.equals(normalizedPrefix))
          ..limit(1))
        .getSingleOrNull();
    return seq?.nextValue ?? 0;
  }

  // READ-ONLY — Egyptian VAT prohibits auto-renumbering.
  // See specs/066-voucher-numbering-atomicity/contracts/numbering-atomicity.md C-2.
  /// 066 (D5-001) — READ-ONLY diagnostic. Egyptian VAT prohibits
  /// auto-renumbering, so this query reports gaps but offers NO write path.
  /// See specs/066-voucher-numbering-atomicity/contracts/numbering-atomicity.md C-2.
  ///
  /// Returns one row per prefix where `(counterNext - 1) > maxUsedNumber`,
  /// scanning `sales_invoices`, `purchase_invoices`, and `safe_transactions`
  /// for the highest numeric tail (`<prefix>-<n>`).
  Future<List<NumberingGapReport>> auditNumberingGaps() async {
    final sequences = await select(documentSequences).get();
    final results = <NumberingGapReport>[];
    for (final seq in sequences) {
      int maxUsed = 0;

      Future<int> maxNumberInTable(String table, String numberCol,
          {bool checkDeleted = true}) async {
        final deletedClause =
            checkDeleted ? 'AND deleted_at IS NULL' : '';
        final rows = await customSelect(
          "SELECT MAX(CAST(SUBSTR($numberCol, INSTR($numberCol, '-') + 1) "
          "AS INTEGER)) AS max_n FROM $table "
          "WHERE $numberCol LIKE '%-%' $deletedClause "
          "AND SUBSTR($numberCol, 1, INSTR($numberCol, '-') - 1) = ?",
          variables: [Variable.withString(seq.prefix)],
        ).getSingleOrNull();
        if (rows == null) return 0;
        final v = rows.data['max_n'];
        if (v is int) return v;
        if (v is num) return v.toInt();
        return 0;
      }

      final n1 = await maxNumberInTable('sales_invoices', 'invoice_number');
      if (n1 > maxUsed) maxUsed = n1;
      final n2 = await maxNumberInTable('purchase_invoices', 'invoice_number');
      if (n2 > maxUsed) maxUsed = n2;
      final n3 = await maxNumberInTable('safe_transactions', 'voucher_number',
          checkDeleted: false);
      if (n3 > maxUsed) maxUsed = n3;

      final gap = (seq.nextValue - 1) - maxUsed;
      if (gap > 0) {
        results.add(NumberingGapReport(
          prefix: seq.prefix,
          counterNext: seq.nextValue,
          maxUsedNumber: maxUsed,
          gapCount: gap,
        ));
      }
    }
    results.sort((a, b) => b.gapCount.compareTo(a.gapCount));
    return results;
  }

  /// Validates the set of user-configured prefix overrides for invoice
  /// numbering. Returns `null` when every configured prefix is unique
  /// (case-insensitive) across document types; otherwise returns a
  /// user-facing error message listing the conflict. Designed to be
  /// called by the "إعدادات ترقيم المستندات" screen before saving.
  Future<String?> validateInvoicePrefixes() async {
    // Collect current effective prefix for each type — user override if
    // set, otherwise the canonical default.
    final effective = <String, String>{}; // canonical → displayPrefix
    for (final entry in AppDatabase._prefixSettingKeys.entries) {
      final canonical = entry.key;
      final key = entry.value;
      final custom = (await getSettingValue(key))?.trim();
      effective[canonical] =
          (custom != null && custom.isNotEmpty) ? custom : canonical;
    }

    // Detect duplicate display prefixes (case-insensitive).
    final Map<String, List<String>> grouped = {};
    effective.forEach((canonical, display) {
      final k = display.toLowerCase();
      grouped.putIfAbsent(k, () => []).add(canonical);
    });
    for (final e in grouped.entries) {
      if (e.value.length > 1) {
        return 'تعارض فى بادئات الترقيم — البادئة "${effective[e.value.first]}" '
            'مكرّرة على الأنواع: ${e.value.join(', ')}. '
            'يجب أن تكون كل بادئة فريدة.';
      }
    }
    return null;
  }
}
