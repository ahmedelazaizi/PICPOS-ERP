// Spec 114 repairs: parties without COA sub-account, and rewiring historical JE lines.
part of '../database.dart';

extension PartyCoaRepairDao on AppDatabase {
  /// Spec 114 — Repair parties that exist without a linked COA sub-account.
  ///
  /// Historical gap: `api_handler_base.resolvePartyId` used to mint placeholder
  /// parties via a direct `insert(parties)` call, bypassing the atomic
  /// party+sub-account creation that `insertParty` runs. The placeholder ended
  /// up with `accountId = null`, so every JE that referenced it tried to post
  /// against the parent control account (2111 / 1121) and got rejected by the
  /// "حساب رئيسي" guard — silently dropping every transaction from the GL
  /// while still showing it in the party's statement (which reads invoices
  /// directly, not JE lines).
  ///
  /// This routine walks every party with `accountId IS NULL` whose role
  /// warrants a COA presence (customer / supplier / delivery company), mints
  /// the matching sub-account using the same suffix-mirroring convention as
  /// `insertParty`, and links it back. Idempotent — running twice is a no-op
  /// for already-repaired rows.
  ///
  /// Returns a small map with counters so the UI can show "X parties
  /// repaired, Y skipped, Z failed".
  Future<Map<String, int>> repairMissingPartySubAccounts({
    int Function()? logTick,
  }) async {
    return transaction(() async {
      await ensurePartyParentAccounts();
      // Re-fetch parent IDs inside the transaction so we always read the
      // freshly-ensured rows.
      final arParent = await (select(accounts)
            ..where((a) => a.code.equals(PartyDao._arParentCode))
            ..limit(1))
          .getSingleOrNull();
      final apParent = await (select(accounts)
            ..where((a) => a.code.equals(PartyDao._apParentCode))
            ..limit(1))
          .getSingleOrNull();

      int repaired = 0;
      int skipped = 0;
      int failed = 0;

      final orphans = await (select(parties)
            ..where((p) =>
                p.accountId.isNull() &
                (p.isCustomer.equals(true) |
                    p.isSupplier.equals(true) |
                    p.isDeliveryCompany.equals(true))))
          .get();

      for (final p in orphans) {
        try {
          // Pick parent: AR for customers (or customer-supplier), AP for
          // pure suppliers and delivery companies. Matches insertParty.
          int? parentAccountId;
          String parentType;
          String namePrefix;
          String parentCode;
          if (p.isCustomer) {
            parentAccountId = arParent?.id;
            parentType = 'asset';
            namePrefix = p.isSupplier ? 'عميل/مورد' : 'عميل';
            parentCode = PartyDao._arParentCode;
          } else if (p.isSupplier) {
            parentAccountId = apParent?.id;
            parentType = 'liability';
            namePrefix = 'مورد';
            parentCode = PartyDao._apParentCode;
          } else if (p.isDeliveryCompany) {
            parentAccountId = apParent?.id;
            parentType = 'liability';
            namePrefix = 'شركة توصيل';
            parentCode = PartyDao._apParentCode;
          } else {
            skipped++;
            continue;
          }

          if (parentAccountId == null) {
            skipped++;
            continue;
          }

          // Use the party's code suffix to keep CUST-00042 ↔ 1121-00042
          // visually aligned. Parties created before code auto-generation
          // may have a free-form code or no code; in that case fall back
          // to the party id as the suffix so the new account code is still
          // unique and deterministic.
          String suffix;
          final code = p.code ?? '';
          if (code.isNotEmpty) {
            final dashIdx = code.indexOf('-');
            suffix = (dashIdx >= 0 && dashIdx < code.length - 1)
                ? code.substring(dashIdx + 1)
                : code;
          } else {
            suffix = p.id.toString().padLeft(5, '0');
          }

          var accountCode = '$parentCode-$suffix';

          // Collision guard — if the deterministic code is already taken
          // (very rare; legacy data), append the party id to disambiguate.
          var existing = await (select(accounts)
                ..where((a) => a.code.equals(accountCode))
                ..limit(1))
              .getSingleOrNull();
          if (existing != null) {
            accountCode = '$parentCode-${suffix}_${p.id}';
            existing = await (select(accounts)
                  ..where((a) => a.code.equals(accountCode))
                  ..limit(1))
                .getSingleOrNull();
            if (existing != null) {
              skipped++;
              continue;
            }
          }

          final displayCode = code.isNotEmpty ? code : 'PID-${p.id}';
          final accountName = '$namePrefix: ${p.name} ($displayCode)';
          final accId = await into(accounts).insert(
            AccountsCompanion.insert(
              code: accountCode,
              name: accountName,
              accountType: parentType,
              parentId: Value(parentAccountId),
              isSystem: const Value(false),
              globalId: Value(UuidV7.generate()),
            ),
          );

          await (update(parties)..where((row) => row.id.equals(p.id))).write(
            PartiesCompanion(accountId: Value(accId)),
          );

          repaired++;
          if (logTick != null) logTick();
        } catch (e) {
          debugPrint('[REPAIR-PARTY-SUBACCOUNT] partyId=${p.id} '
              'name="${p.name}" failed: $e');
          failed++;
        }
      }

      debugPrint('[REPAIR-PARTY-SUBACCOUNT] done: '
          'repaired=$repaired skipped=$skipped failed=$failed '
          'total-orphans=${orphans.length}');

      return {
        'repaired': repaired,
        'skipped': skipped,
        'failed': failed,
        'total': orphans.length,
      };
    });
  }

  /// Spec 114c — Rewire historical JE lines from the parent control
  /// account to the party's sub-account.
  ///
  /// When the system creates a JE for an invoice involving a party WITHOUT
  /// a sub-account (legacy data, the old placeholder-creation gap, etc.),
  /// the AR/AP leg lands on the PARENT account (1121 / 2111). The
  /// `_resolvePartySubAccount` helper that we use today falls back to the
  /// parent control when `parties.accountId IS NULL`. Spec 114 now creates
  /// sub-accounts for those parties — but the existing JE lines keep
  /// pointing at the parent. Result: the party's sub-account ledger looks
  /// empty even though the transactions exist in the GL (they just sit
  /// against the wrong account).
  ///
  /// This routine walks every party that DOES have a linked sub-account
  /// (parties.accountId set) and migrates the JE lines belonging to its
  /// invoices / safe transactions / commercial papers FROM the parent
  /// control account TO the sub-account. Idempotent — running twice is a
  /// no-op for already-rewired lines.
  ///
  /// Returns counters: `linesMoved`, `partiesScanned`, `failed`.
  Future<Map<String, int>> rewireJELinesToPartySubAccounts() async {
    return transaction(() async {
      await ensurePartyParentAccounts();
      final arParent = await (select(accounts)
            ..where((a) => a.code.equals(PartyDao._arParentCode))
            ..limit(1))
          .getSingleOrNull();
      final apParent = await (select(accounts)
            ..where((a) => a.code.equals(PartyDao._apParentCode))
            ..limit(1))
          .getSingleOrNull();

      int linesMoved = 0;
      int partiesScanned = 0;
      int failed = 0;

      final wired = await (select(parties)
            ..where((p) => p.accountId.isNotNull()))
          .get();

      for (final p in wired) {
        partiesScanned++;
        try {
          // Determine the parent control account this party's sub-account
          // descends from. Customers/customer-suppliers → AR (1121),
          // pure suppliers / delivery companies → AP (2111).
          int? parentAccountId;
          if (p.isCustomer) {
            parentAccountId = arParent?.id;
          } else if (p.isSupplier || p.isDeliveryCompany) {
            parentAccountId = apParent?.id;
          }
          if (parentAccountId == null) continue;
          final subAccountId = p.accountId!;
          if (subAccountId == parentAccountId) continue;

          // JEs tied to sales invoices for this customer
          final salesEntryIds = await customSelect(
            'SELECT je.id FROM journal_entries je '
            'JOIN sales_invoices si ON si.id = je.reference_id '
            'WHERE je.reference_type IN (\'sale\', \'sales_invoice\', \'sales_return\') '
            '  AND si.customer_id = ?',
            variables: [Variable<int>(p.id)],
            readsFrom: {journalEntries, salesInvoices},
          ).get();

          // JEs tied to purchase invoices for this supplier
          final purchaseEntryIds = await customSelect(
            'SELECT je.id FROM journal_entries je '
            'JOIN purchase_invoices pi ON pi.id = je.reference_id '
            'WHERE je.reference_type IN (\'purchase\', \'purchase_invoice\', \'purchase_return\') '
            '  AND pi.supplier_id = ?',
            variables: [Variable<int>(p.id)],
            readsFrom: {journalEntries, purchaseInvoices},
          ).get();

          // JEs tied to safe transactions (receipts / payments / refunds)
          // attributed to this party.
          final safeTxnEntryIds = await customSelect(
            'SELECT je.id FROM journal_entries je '
            'JOIN safe_transactions st ON st.id = je.reference_id '
            'WHERE je.reference_type IN (\'receipt_voucher\', \'payment_voucher\', '
            '   \'safe_transaction\', \'sales_return\') '
            '  AND st.party_id = ?',
            variables: [Variable<int>(p.id)],
            readsFrom: {journalEntries, safeTransactions},
          ).get();

          // JEs tied to commercial papers (cheques) for this party
          final paperEntryIds = await customSelect(
            'SELECT je.id FROM journal_entries je '
            'JOIN commercial_papers cp ON cp.id = je.reference_id '
            'WHERE je.reference_type = \'commercial_paper\' '
            '  AND cp.party_id = ?',
            variables: [Variable<int>(p.id)],
            readsFrom: {journalEntries, commercialPapers},
          ).get();

          final entryIds = <int>{
            for (final row in salesEntryIds) row.data['id'] as int,
            for (final row in purchaseEntryIds) row.data['id'] as int,
            for (final row in safeTxnEntryIds) row.data['id'] as int,
            for (final row in paperEntryIds) row.data['id'] as int,
          };

          if (entryIds.isEmpty) continue;

          // Move every line of these JEs that currently sits on the parent
          // control account onto the party's sub-account. The party-side
          // lines are the AR/AP legs; the other legs (cash / sales /
          // inventory / VAT) live on different accounts and are left alone.
          final updated = await (update(journalEntryLines)
                ..where((line) =>
                    line.entryId.isIn(entryIds) &
                    line.accountId.equals(parentAccountId!)))
              .write(JournalEntryLinesCompanion(
            accountId: Value(subAccountId),
          ));
          linesMoved += updated;
        } catch (e) {
          debugPrint('[REWIRE-JE] partyId=${p.id} name="${p.name}" failed: $e');
          failed++;
        }
      }

      // After moving lines, account balances on both the parent and the
      // sub-account need a recompute so the COA tree displays correctly.
      // Walk every account that received a moved line + the parent rows
      // and recompute their balance from journal_entry_lines.
      if (linesMoved > 0) {
        await customStatement('''
          UPDATE accounts SET balance = (
            SELECT COALESCE(SUM(jel.debit), 0) - COALESCE(SUM(jel.credit), 0)
            FROM journal_entry_lines jel
            INNER JOIN journal_entries je ON je.id = jel.entry_id
            WHERE jel.account_id = accounts.id
               AND je.is_posted = ${sqlBool(true)}
               AND je.is_deleted = ${sqlBool(false)}
          )
          WHERE accounts.id IN (
            SELECT DISTINCT account_id FROM journal_entry_lines
          )
        ''');
      }

      debugPrint('[REWIRE-JE] done — linesMoved=$linesMoved '
          'partiesScanned=$partiesScanned failed=$failed');

      return {
        'linesMoved': linesMoved,
        'partiesScanned': partiesScanned,
        'failed': failed,
      };
    });
  }
}
