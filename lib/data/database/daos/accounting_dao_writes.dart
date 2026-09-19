// ignore_for_file: library_private_types_in_public_api
part of '../database.dart';

extension AccountingDaoWritesExt on AppDatabase {

  /// Create a journal entry
  ///
  /// [globalId] lets callers inject a deterministic UUID so client/server
  /// converge to a single row after sync (used by reversal flows that derive
  /// a stable `<sourceGid>-rev` id from the originating safe_transaction).
  /// If null, a fresh UuidV7 is generated.
  Future<int> createJournalEntry({
    required String description,
    required DateTime date,
    required List<JournalLine> lines,
    String? referenceType,
    int? referenceId,
    bool isAutoPosted = false,
    int? costCenterId,
    int? branchId,
    String? globalId,

    /// «حفظ كمسودة» — يُحفَظ غيرَ مرحَّلٍ وبانتظار الاعتماد، ولا يحرّك
    /// رصيداً حتى [approveJournalEntry].
    bool asDraft = false,

    /// مَن أنشأ القيد — يُكتَب بـ لأنّ  عمودٌ
    /// أضافته الإضافةُ الدفاعيّة ولا تعرفه كيانات drift.
    int? createdBy,

    /// «المرجع» الذي يكتبه المستخدمُ في سند القيد — نصٌّ حرٌّ اختياريّ
    /// (رقمُ عقدٍ، رقمُ إشعارِ بنكٍ، رقمُ مستندٍ ورقيّ).
    ///
    /// 🔴 **والعمودُ `journal_entries.reference` مزروعٌ منذ v174 بلا كاتبٍ
    /// ولا قارئ** — `grep` على المستودع كلِّه لا يجد إلّا تعريفَه والهجرة.
    /// وهو عينُ ما وقع لـ`custodian_user_id` و`source_voucher_id`: عمودٌ
    /// يُشحَن ويبقى فارغاً إلى الأبد لأنّ أحداً لم يصله.
    ///
    /// ⚠️ **وليس [referenceType]**: ذاك مفرداتٌ مغلقةٌ يكتبها المحرّك
    /// (`sale` · `purchase` · `daily`…) ويُرشَّح بها، وهذا نصٌّ يقرؤه
    /// إنسان. وخلطُهما كان يُفسد كلَّ ترشيحٍ على المصدر.
    String? reference,
  }) async {
    // Spec 007 / FR-007: mint the JE's globalId BEFORE the transaction opens
    // so the same UUID is used for (a) the local insert below, and
    // (b) the post-commit submitJournalEntry call. Without this, the local
    // row carried one UUID and the server minted a different one, making
    // the next DeltaPull insert the server's row as a *new* local row —
    // duplicates everywhere on mirror. Reversal flows that need a
    // deterministic id (`<sourceGid>-rev`) still pass globalId through.
    final mintedGlobalId = globalId ?? UuidV7.generate();

    // Cluster 025 / Issue 1 — reset the per-call diagnostic so callers
    // (POS save, voucher save) can read it after the await returns to
    // decide whether to surface a "rounding absorbed" toast.
    JournalEntryDiagnostics.lastRoundingAdjustment = 0;

    // Capture sync payload OUTSIDE the db.transaction() so no SQLite write-lock
    // is held while making an HTTP request (audit item 2 — Long Transactions).
    // These are written by the transaction body below and consumed after commit.
    String? syncDesc;
    List<Map<String, dynamic>>? syncLines;
    int? syncResolvedCostCenterId;
    int? syncBranchId;

    final entryId = await transaction(() async {
      // DEDUP-FIX: Prevent duplicate auto-posted JEs for the same reference.
      // This catches ALL double-posting paths (concurrent calls, edit+create,
      // factory + direct DAO, etc.) atomically inside the write transaction.
      //
      // EXEMPTION: Reference types that legitimately produce MULTIPLE auto-posted
      // JEs per reference ID are listed here.  Commercial papers, for example,
      // create one JE per status transition (pending → deposited → cashed), so
      // blocking them would silently swallow every status-change entry after the
      // first one.
      //
      // ⚠️ والقائمةُ **واحدةٌ لا اثنتان**: [kMultiJeReferenceTypes] في
      // `database.dart`، وهي نفسُها التي يُبنى منها `NOT IN` في
      // [kCreateJeAutopostDedupIndexSql]. كانتا مكتوبتَين مرّتين، فأُضيف
      // `asset_depreciation` هنا وحدَه 2026-08-27 ⇒ مرّ الحارسُ واصطدم
      // القيدُ بـ`UNIQUE constraint failed` في الفهرس، فتوقّف الإهلاكُ
      // بعد شهره الأوّل بدل أن يُرحَّل.
      const multiJeReferenceTypes = kMultiJeReferenceTypes;
      if (isAutoPosted && referenceType != null && referenceId != null &&
          !multiJeReferenceTypes.contains(referenceType)) {
        // Build the full set of reference type aliases to check:
        //   'sale' ↔ 'sales_invoice'  |  'purchase' ↔ 'purchase_invoice'
        final refTypesToCheck = <String>[referenceType];
        if (referenceType == 'sale') refTypesToCheck.add('sales_invoice');
        if (referenceType == 'sales_invoice') refTypesToCheck.add('sale');
        if (referenceType == 'purchase') refTypesToCheck.add('purchase_invoice');
        if (referenceType == 'purchase_invoice') refTypesToCheck.add('purchase');

        for (final rt in refTypesToCheck) {
          final dup = await (select(journalEntries)
                ..where((e) =>
                    e.referenceType.equals(rt) &
                    e.referenceId.equals(referenceId) &
                    e.isAutoPosted.equals(true))
                ..limit(1))
              .getSingleOrNull();
          if (dup != null) {
            debugPrint('[JE-DEDUP] Skipping duplicate autopost: '
                '$referenceType #$referenceId — already posted as JE #${dup.id} ($rt)');
            return dup.id; // Return existing JE id (idempotent)
          }
        }
      }

      // 0. Fiscal Period Gating — Reject entries in closed periods/years.
      //    System-generated closing/opening entries are exempt: closeFiscalYear
      //    closes all monthly periods first and then needs to post the
      //    Dec-31 closing JE + next-year opening JE, which would otherwise be
      //    blocked by their own precondition.
      const systemReferenceTypes = {
        'fiscal_close',
        'fiscal_open',
        'opening_balance',
      };
      if (!systemReferenceTypes.contains(referenceType)) {
        await validateFinancialPeriod(date, operation: 'قيد يومية');
      }

      // Standardize decimal rounding (3 digits per AppConstants.decimalPlaces)
      // to prevent floating-point mismatch.
      // Inherit header costCenterId if line does not explicitly specify one.
      final roundedLines = lines.map((line) => JournalLine(
        accountId: line.accountId,
        debit: double.parse(line.debit.toStringAsFixed(AppConstants.decimalPlaces)),
        credit: double.parse(line.credit.toStringAsFixed(AppConstants.decimalPlaces)),
        description: line.description,
        costCenterId: line.costCenterId ?? costCenterId,
      )).toList();

      // Spec 139 — deterministic & honest balancing. Compute the debit/credit
      // residual in INTEGER MINOR UNITS (no float drift). A legitimate sub-cap
      // remainder is booked to the dedicated «فروق تقريب» (rounding_difference)
      // account — NEVER absorbed into a business leg. Anything beyond the cap is
      // a real error and is hard-failed (dead-lettered by offline_sync_worker via
      // the Arabic substrings below). Replaces the old ×10 absorb-into-largest-leg
      // plug (Cluster 025 / Issue 1) now that Spec 136 fixed the leg-derivation source.
      final debitMinor = roundedLines.fold<int>(
          0, (sum, line) => sum + FinancialUtils.toMinorUnits(line.debit));
      final creditMinor = roundedLines.fold<int>(
          0, (sum, line) => sum + FinancialUtils.toMinorUnits(line.credit));
      final residualMinor = debitMinor - creditMinor;
      double absorbedRounding = 0;
      if (residualMinor != 0) {
        if (residualMinor.abs() <= FinancialUtils.balanceToleranceMinorUnits) {
          // Legitimate sub-cap rounding remainder.
          final amount = FinancialUtils.fromMinorUnits(residualMinor.abs());
          final roundingAccount =
              await getLeafAccountByPurpose('rounding_difference');
          if (roundingAccount != null) {
            // Honest path — book the remainder to the dedicated account.
            roundedLines.add(JournalLine(
              accountId: roundingAccount.id,
              // credit-short (residual>0) → rounding GAIN (credit);
              // debit-short  (residual<0) → rounding LOSS (debit).
              debit: residualMinor < 0 ? amount : 0,
              credit: residualMinor > 0 ? amount : 0,
              description: 'فرق تقريب',
            ));
            DiagnosticLogger.log(
              'SYNC-WARN',
              'JE rounding residual '
              '${FinancialUtils.fromMinorUnits(residualMinor).toStringAsFixed(4)} '
              'posted to rounding-difference account ${roundingAccount.code}. Spec 139.',
            );
          } else if (SyncInterceptor.isClientMode) {
            // Spec 139 H1 — on a client/mirror the rounding account may not have
            // synced yet (or the server is a pre-139 build). The SERVER is
            // authoritative and re-posts this JE honestly, so NEVER block the
            // local foreground operation (a sale would roll back at the till):
            // absorb the ≤cap remainder into the largest leg of the SHORT side
            // (bounded, cache-only) and warn. This is a deliberate, scoped
            // exception to the fail-closed rule for the client-missing-account
            // window only.
            final shortIsCredit = residualMinor > 0;
            int targetIdx = -1;
            double targetMax = -1;
            for (var i = 0; i < roundedLines.length; i++) {
              final legAmt =
                  shortIsCredit ? roundedLines[i].credit : roundedLines[i].debit;
              if (legAmt > targetMax) {
                targetMax = legAmt;
                targetIdx = i;
              }
            }
            if (targetIdx >= 0) {
              final old = roundedLines[targetIdx];
              roundedLines[targetIdx] = JournalLine(
                accountId: old.accountId,
                debit: shortIsCredit
                    ? old.debit
                    : FinancialUtils.round(old.debit + amount),
                credit: shortIsCredit
                    ? FinancialUtils.round(old.credit + amount)
                    : old.credit,
                description: old.description,
                costCenterId: old.costCenterId,
              );
            }
            DiagnosticLogger.log(
              'SYNC-WARN',
              'client-mode: rounding account (rounding_difference) unavailable '
              'locally; absorbed sub-cap residual '
              '${FinancialUtils.fromMinorUnits(residualMinor).toStringAsFixed(4)} '
              'into the largest leg — the server re-posts honestly. Spec 139 H1.',
            );
          } else {
            // Server/standalone: 4319 is guaranteed by the boot self-heal. If it
            // is still missing that is a fixable/transient config error, so throw
            // a RETRYABLE message that does NOT contain the sync dead-letter
            // substrings ('خطأ في قيد اليومية' / 'لا يساوي الدائن') — the entry
            // retries once the account exists rather than being dead-lettered.
            throw Exception(
              'تعذّر ترحيل فرق التقريب: حساب فروق التقريب (rounding_difference) '
              'غير معرّف — سيُعاد المحاولة بعد تهيئة/مزامنة الحسابات.',
            );
          }
          absorbedRounding = FinancialUtils.fromMinorUnits(residualMinor);
          // Defensive re-assert: the entry now balances exactly.
          final d2 = roundedLines.fold<int>(
              0, (sum, line) => sum + FinancialUtils.toMinorUnits(line.debit));
          final c2 = roundedLines.fold<int>(
              0, (sum, line) => sum + FinancialUtils.toMinorUnits(line.credit));
          if (d2 != c2) {
            throw Exception(
              'خطأ في قيد اليومية: تعذّر موازنة القيد بعد ترحيل فرق التقريب — '
              'المدين لا يساوي الدائن',
            );
          }
        } else {
          // Genuine imbalance beyond the cap → refuse loudly. KEEP BOTH Arabic
          // substrings 'خطأ في قيد اليومية' and 'لا يساوي الدائن' verbatim — the
          // sync dead-letter classifier (offline_sync_worker.dart) matches them.
          final totalDebit = FinancialUtils.fromMinorUnits(debitMinor);
          final totalCredit = FinancialUtils.fromMinorUnits(creditMinor);
          throw Exception(
            'خطأ في قيد اليومية: المدين ($totalDebit) لا يساوي الدائن ($totalCredit)',
          );
        }
      }
      JournalEntryDiagnostics.lastRoundingAdjustment = absorbedRounding;
      // Spec 139 — final balanced debit total (major units) for the audit-hash
      // payload below. The old method-scoped `totalDebit` was removed with the
      // absorb plug; recompute it from the now-balanced `roundedLines`.
      final totalDebit = FinancialUtils.fromMinorUnits(roundedLines.fold<int>(
          0, (sum, line) => sum + FinancialUtils.toMinorUnits(line.debit)));

      // Bulk load affected accounts to eliminate N+1 queries
      final accountIds = roundedLines.map((l) => l.accountId).toSet();
      final affectedAccounts = await (select(accounts)..where((a) => a.id.isIn(accountIds))).get();
      final accountMap = {for (var a in affectedAccounts) a.id: a};

      // v110: Guard — Prevent posting to 'view' accounts (parent-only accounts)
      for (final line in roundedLines) {
        final acctRow = accountMap[line.accountId];
        if (acctRow != null && acctRow.accountNature == 'view') {
          throw Exception(
            'لا يمكن الترحيل على حساب رئيسي (${acctRow.code} - ${acctRow.name}) — يجب اختيار حساب تفصيلي',
          );
        }
      }

      // IAS 1.99: P&L lines (revenue/expense/contra_revenue) must carry a cost
      // center. We only DETECT that need here and defer the fallback until AFTER
      // the branch/region resolution below, so a branch's own cost center wins
      // over the global GEN centre. Final priority: explicit -> branch -> region
      // -> GEN. (Previously the GEN fallback ran right here, which made the
      // branch/region resolution below dead code for every P&L entry — so every
      // branch sale/purchase landed on GEN instead of the branch's own centre.)
      int? resolvedCostCenterId = costCenterId;
      bool needsCostCenter = false;
      if (resolvedCostCenterId == null && referenceType != 'fiscal_close') {
        for (final line in roundedLines) {
          if (line.costCenterId != null) continue;
          final account = accountMap[line.accountId];
          if (account != null &&
              (account.accountType == 'revenue' ||
                  account.accountType == 'expense' ||
                  account.accountType == 'contra_revenue')) {
            needsCostCenter = true;
            break;
          }
        }
      }

      // Resolve a safe branchId fallback if missing, preventing isolated
      // un-reportable transactions.
      //
      // Spec 108 (H — FK 787): the previous `branchId ?? 1` blindly assumed
      // a branch with id=1 always exists. That assumption breaks on mirror
      // devices where master-data sync remaps branch ids (the field-observed
      // "الفرع الرئيسي" sits at local id=10 because earlier ids were
      // claimed by other rows during dedup). The fallback to 1 produced an
      // FK constraint failure on EVERY auto-posted JE (cheque save, voucher
      // save, …) on those installs. Switch to a deterministic lookup of the
      // lowest-id ACTIVE branch — and accept `null` if there is genuinely
      // no branch (column itself is nullable in the schema).
      int? finalBranchId = branchId;
      if (finalBranchId == null) {
        final fallbackBranch = await (select(branches)
              ..where((b) => b.isActive.equals(true))
              ..orderBy([(b) => OrderingTerm.asc(b.id)])
              ..limit(1))
            .getSingleOrNull();
        finalBranchId = fallbackBranch?.id;
      } else {
        // Defensive: caller-supplied id might not exist locally (e.g.
        // stale dropdown selection on a mirror with partial sync). Verify
        // and fall back if missing.
        final exists = await (select(branches)
              ..where((b) => b.id.equals(finalBranchId!))
              ..limit(1))
            .getSingleOrNull();
        if (exists == null) {
          debugPrint('[ACCOUNTING] branchId=$finalBranchId not found locally '
              '— falling back to lowest active branch (Spec 108 FK guard)');
          final fallbackBranch = await (select(branches)
                ..where((b) => b.isActive.equals(true))
                ..orderBy([(b) => OrderingTerm.asc(b.id)])
                ..limit(1))
              .getSingleOrNull();
          finalBranchId = fallbackBranch?.id;
        }
      }

      // Same defensive verification for costCenterId — a stale id from a
      // mirror's dropdown can otherwise blow up the JE insert with FK 787.
      if (resolvedCostCenterId != null) {
        final ccExists = await (select(costCenters)
              ..where((c) => c.id.equals(resolvedCostCenterId!))
              ..limit(1))
            .getSingleOrNull();
        if (ccExists == null) {
          debugPrint('[ACCOUNTING] costCenterId=$resolvedCostCenterId not '
              'found locally — clearing to null (Spec 108 FK guard)');
          resolvedCostCenterId = null;
        }
      }

      // COST-CENTER RESOLUTION (step 2 of 2): no explicit costCenterId, so
      // resolve the branch's own cost center — then its region's — BEFORE the
      // global GEN fallback below. Priority: explicit -> branch -> region -> GEN.
      if (resolvedCostCenterId == null && finalBranchId != null) {
        final branchRow = await (select(branches)..where((b) => b.id.equals(finalBranchId!))..limit(1)).getSingleOrNull();
        if (branchRow?.costCenterId != null) {
          resolvedCostCenterId = branchRow!.costCenterId;
          debugPrint('[ACCOUNTING] costCenter auto-resolved from branch #$finalBranchId → cc=${branchRow.costCenterId}');
        } else if (branchRow?.regionId != null) {
          final regionRow = await (select(regions)..where((r) => r.id.equals(branchRow!.regionId!))..limit(1)).getSingleOrNull();
          if (regionRow?.costCenterId != null) {
            resolvedCostCenterId = regionRow!.costCenterId;
            debugPrint('[ACCOUNTING] costCenter auto-resolved from region #${branchRow!.regionId} → cc=${regionRow.costCenterId}');
          }
        }
      }

      // COST-CENTER RESOLUTION (final fallback): a P&L entry with no explicit,
      // branch, or region cost center lands on the global «عام» (GEN), which is
      // auto-created once so entries are never lost. Reached ONLY after branch +
      // region both came back empty — never ahead of the branch's own centre.
      if (resolvedCostCenterId == null && needsCostCenter) {
        final defaultCC = await (select(costCenters)
              ..where((c) => c.code.equals('GEN'))
              ..limit(1))
            .getSingleOrNull();
        if (defaultCC != null) {
          resolvedCostCenterId = defaultCC.id;
        } else {
          // Auto-create a General cost center so entries are never lost
          resolvedCostCenterId = await into(costCenters).insert(
            CostCentersCompanion.insert(
              code: 'GEN',
              name: 'عام',
              globalId: Value(UuidV7.generate()),
            ),
          );
          debugPrint('[ACCOUNTING] Auto-created default cost center GEN (id=$resolvedCostCenterId)');
        }
      }

      // Generate entry number
      final entryNumber = await _generateEntryNumber();

      // Get current fiscal year
      final currentFY = await getCurrentFiscalYear();

      // كلُّ قيدٍ متوازنٍ يُرحَّل فوراً — إلّا ما طُلب حفظُه مسودّةً.
      //
      // ⚠️ وقبل 2026-08-27 كان الثابتان `true`/`false` بلا مدخل، فلم يكن
      //    **أحدٌ في المستودع كلِّه** يكتب `needsApproval = true` — فشارةُ
      //    «بانتظار الاعتماد» وزرُّ الاعتماد في الشاشة كانا مسيَّجَين
      //    بقيمةٍ لا تُكتَب أبداً، أي ميتَين. وحارسُ الأرصدة تحت مكتوبٌ
      //    لهذه الحالة منذ ICR-01 وينتظر مدخلَه.
      final shouldPost = !asDraft;
      final shouldNeedApproval = asDraft;

      final entryId = await into(journalEntries).insert(
        JournalEntriesCompanion.insert(
          entryNumber: entryNumber,
          entryDate: date,
          description: Value(description),
          referenceType: Value(referenceType),
          referenceId: Value(referenceId),
          isPosted: Value(shouldPost),
          isAutoPosted: Value(isAutoPosted),
          needsApproval: Value(shouldNeedApproval),
          fiscalYearId: Value(currentFY?.id),
          costCenterId: Value(resolvedCostCenterId),
          branchId: Value(finalBranchId),
          reference: Value(reference),
          // UUID-First (Phase 1): stable cross-install identity for sync.
          // Deterministic globalId can be injected by reversal flows so both
          // sides of the sync loop converge to one row. Spec 007 / FR-007:
          // use the mintedGlobalId captured outside the transaction so the
          // post-commit submitJournalEntry call can re-use the same UUID.
          globalId: Value(mintedGlobalId),
        ),
      );

      // مَن أنشأ — عمودٌ دفاعيٌّ لا يعرفه drift، فيُكتَب بعبارةٍ خام.
      if (createdBy != null) {
        await customStatement(
          'UPDATE journal_entries SET created_by = ? WHERE id = ?',
          [createdBy, entryId],
        );
      }

      // Collect affected accounts for batch balance update (PERF-01)
      final affectedAccountIds = <int>{};

      for (final line in roundedLines) {
        await into(journalEntryLines).insert(
          JournalEntryLinesCompanion.insert(
            entryId: entryId,
            accountId: line.accountId,
            debit: Value(line.debit),
            credit: Value(line.credit),
            description: Value(line.description),
            costCenterId: Value(line.costCenterId ?? resolvedCostCenterId),
          ),
        );
        affectedAccountIds.add(line.accountId);
      }

      // Batch balance update: single SELECT + single batch-UPDATE instead of
      // the previous N × (SELECT SUM + UPDATE) loop (audit perf-01 fix).
      // ICR-01: Only update balances for POSTED entries (drafts wait for approval)
      if (shouldPost && affectedAccountIds.isNotEmpty) {
        // 1. Compute all affected account balances in a single aggregation query.
        final placeholders = affectedAccountIds.map((_) => '?').join(', ');
        final balanceRows = await customSelect(
          'SELECT jel.account_id, '
          'COALESCE(SUM(jel.debit), 0.0) - COALESCE(SUM(jel.credit), 0.0) '
          '  AS computed_balance '
          'FROM journal_entry_lines jel '
          'INNER JOIN journal_entries je ON je.id = jel.entry_id '
          'WHERE jel.account_id IN ($placeholders) AND je.is_posted = 1 '
          'GROUP BY jel.account_id',
          variables: affectedAccountIds.map((id) => Variable.withInt(id)).toList(),
          readsFrom: {journalEntryLines, journalEntries, accounts},
        ).get();

        final balanceMap = <int, double>{
          for (final row in balanceRows)
            row.read<int>('account_id'): row.read<double>('computed_balance'),
        };

        // 2. Write all account balances in a single Drift batch statement.
        await batch((b) {
          for (final accountId in affectedAccountIds) {
            b.update(
              accounts,
              AccountsCompanion(balance: Value(balanceMap[accountId] ?? 0.0)),
              where: (a) => a.id.equals(accountId),
            );
          }
        });
      }

      // PHASE-12 (SEC2): Hash Chain — compute SHA-256 of entry data + previous hash
      // Enables immutable audit trail verification.
      //
      // NO outer try/catch swallow here. Any SQL failure inside this block
      // (the SELECT-previous-hash or the UPDATE-description) would poison
      // the pg transaction; swallowing the Dart exception then lets COMMIT
      // fire on an aborted tx and produce the opaque 25P02 on return.
      // Let any such error propagate so the transaction rolls back cleanly
      // and the real cause surfaces at the API boundary.
      final previousEntry = await (select(journalEntries)
            ..where((e) => e.id.isSmallerThanValue(entryId))
            ..orderBy([(e) => OrderingTerm.desc(e.id)])
            ..limit(1))
          .getSingleOrNull();

      String previousHash = '0' * 64; // Genesis hash
      if (previousEntry != null) {
        final desc = previousEntry.description ?? '';
        final hashMatch = RegExp(r'\[HASH:([a-f0-9]{64})\]').firstMatch(desc);
        if (hashMatch != null) previousHash = hashMatch.group(1)!;
      }

      // Build hash payload: prevHash + entryId + date + totalDebit + description
      final payload = '$previousHash|$entryId|${date.toIso8601String()}|$totalDebit|$description';
      final digest = sha256.convert(utf8.encode(payload));
      final hashStr = digest.toString();

      // Append hash to description (non-destructive — preserves original text)
      final updatedDesc = '${description ?? ''} [HASH:$hashStr]';
      await (update(journalEntries)..where((e) => e.id.equals(entryId)))
          .write(JournalEntriesCompanion(description: Value(updatedDesc)));

      // Capture sync payload so it can be used after the transaction commits
      // (the HTTP call below must NOT hold the SQLite write-lock — audit fix #2).
      if (SyncInterceptor.isClientMode) {
        syncDesc = updatedDesc;
        syncLines = roundedLines.map((l) => <String, dynamic>{
          'accountId': l.accountId,
          'debit': l.debit,
          'credit': l.credit,
          'description': l.description,
          'costCenterId': l.costCenterId ?? resolvedCostCenterId,
        }).toList();
        syncResolvedCostCenterId = resolvedCostCenterId;
        syncBranchId = finalBranchId;
      }

      return entryId;
    }); // ← transaction commits here; SQLite write-lock released

    // Phase 1.5: Sync OUTSIDE transaction — lock already released above.
    // HTTP latency no longer blocks other writers (fixes SqliteException 517
    // under concurrent cashier sessions on slow networks).
    // ⚠️ **والمسودّةُ لا تُدفَع.** `submitJournalEntry` لا يحمل حقلَ ترحيلٍ
    //    أصلاً، و`journal_sync_strategy` يفرض على كلِّ قيدٍ قادمٍ من الخادم
    //    `isPosted: true` و`needsApproval: false` صراحةً. فدفعُ مسودّةٍ
    //    كان يجعلها تُرحَّل على الخادم وعلى كلِّ جهازٍ آخر — أي ترحيلٌ بلا
    //    اعتماد، وهو عينُ ما تمنعه المسودّة. فتُحتجَز محلّيّاً حتّى
    //    `approveJournalEntry`، وهو الذي يدفعها.
    if (SyncInterceptor.isClientMode && syncDesc != null && !asDraft) {
      try {
        await SyncInterceptor.instance?.submitJournalEntry(
          description: syncDesc!,
          date: date,
          lines: syncLines!,
          referenceType: referenceType,
          referenceId: referenceId,
          isAutoPosted: isAutoPosted,
          costCenterId: costCenterId ?? syncResolvedCostCenterId,
          branchId: syncBranchId,
          // Spec 007 / FR-007: thread the locally-minted globalId so the
          // server stores the JE under the SAME UUID as the local row.
          // Without this, DeltaPull would re-insert the server's row as a
          // duplicate because its globalId differed from the local one.
          globalId: mintedGlobalId,
        );
      } catch (e) {
        debugPrint('[ACCOUNTING_SYNC] Sync trigger failed for JE #$entryId: $e');
      }
    }

    return entryId;
  }


  /// Cascade-reverse every auto-posted journal entry matching
  /// (referenceType, referenceId). For each match, a NEW journal entry is
  /// inserted with every line's debit/credit swapped — the canonical
  /// mirror-reversal pattern used by [voidSalesInvoice]. The original JE
  /// stays intact so the audit trail is preserved.
  ///
  /// The reversal JE is given a deterministic `globalId` of
  /// `'<sourceGlobalId>-rev'` so the client and the server converge to one
  /// row after sync: both sides compute the identical UUID from the same
  /// originating [sourceGlobalId] (the safe_transaction's globalId, which is
  /// already shared across client/server).
  ///
  /// Idempotent — if a reversal with the deterministic globalId already
  /// exists, that original JE is skipped. Safe to run on both sides of the
  /// sync loop.
  ///
  /// [requireAutoPosted] (default true) gates the match on
  /// `is_auto_posted = 1`. Spec 151 A04-1 — INTERACTIVE receipt/payment
  /// vouchers post their JE through `_createVoucherJournalEntry`
  /// (treasury_dao) which calls `createJournalEntry` WITHOUT `isAutoPosted`
  /// → it defaults to FALSE, persisted under referenceType
  /// 'receipt_voucher'/'payment_voucher'. With the default filter those JEs
  /// are invisible to this reverser, so deleting the voucher reversed
  /// nothing and left the original expense/income JE live → GL/P&L drifted
  /// from `safes.balance`. The voucher-delete caller passes
  /// `requireAutoPosted: false` so BOTH the auto-posted ('receipt'/'payment')
  /// and the interactive ('receipt_voucher'/'payment_voucher') JEs are
  /// reversible. This is safe because the match is still keyed on
  /// (referenceType, referenceId) and referenceId is the safe_transaction id,
  /// which is UNIQUE per voucher — relaxing the flag cannot sweep an
  /// unrelated JE.
  ///
  /// Returns the number of reversal JEs actually inserted.
  Future<int> reverseAutoPostedJournalEntriesFor({
    required String referenceType,
    required int referenceId,
    required String voidReferenceType,
    required String sourceGlobalId,
    required String description,
    int? costCenterId,
    int? branchId,
    bool requireAutoPosted = true,
  }) async {
    final originals = await (select(journalEntries)
          ..where((e) {
            var predicate = e.referenceType.equals(referenceType) &
                e.referenceId.equalsNullable(referenceId) &
                e.isDeleted.equals(false);
            if (requireAutoPosted) {
              predicate = predicate & e.isAutoPosted.equals(true);
            }
            return predicate;
          }))
        .get();

    if (originals.isEmpty) {
      debugPrint('[JE-REVERSE] No auto-posted JE to reverse for '
          '$referenceType #$referenceId');
      return 0;
    }

    int inserted = 0;
    for (int i = 0; i < originals.length; i++) {
      final originalJE = originals[i];
      // Suffix per-original so multiple auto-posted JEs against the same
      // reference (rare, but possible) each get a unique deterministic gid.
      final reversalGid = originals.length == 1
          ? '$sourceGlobalId-rev'
          : '$sourceGlobalId-rev-$i';

      // Idempotency check — if the reversal already exists (e.g. pulled from
      // server after a local reversal, or re-entry after crash) skip.
      final existing = await (select(journalEntries)
            ..where((e) => e.globalId.equals(reversalGid))
            ..limit(1))
          .getSingleOrNull();
      if (existing != null) {
        debugPrint('[JE-REVERSE] Reversal already exists for '
            '$referenceType #$referenceId (gid=$reversalGid) — skipping');
        continue;
      }

      final originalLines = await (select(journalEntryLines)
            ..where((l) => l.entryId.equals(originalJE.id)))
          .get();

      if (originalLines.isEmpty) continue;

      final reversalLines = originalLines
          .map((line) => JournalLine(
                accountId: line.accountId,
                debit: line.credit, // swap
                credit: line.debit,
                description: 'عكس: ${line.description ?? ""}',
                costCenterId: line.costCenterId,
              ))
          .toList();

      await createJournalEntry(
        description: description,
        date: DateTime.now(),
        lines: reversalLines,
        referenceType: voidReferenceType,
        referenceId: referenceId,
        isAutoPosted: true,
        costCenterId: costCenterId ?? originalJE.costCenterId,
        branchId: branchId ?? originalJE.branchId,
        globalId: reversalGid,
      );
      inserted++;
      debugPrint('[JE-REVERSE] Reversed JE #${originalJE.id} '
          '($referenceType #$referenceId) → gid=$reversalGid');
    }
    return inserted;
  }


  /// One-time migration: retroactively post unposted sales/return journal entries
  /// that were created before the isAutoPosted fix was applied.
  /// Also recalculates all affected account balances.
  Future<void> fixUnpostedAutoEntries() async {
    // Find all unposted journal entries for sales_invoice and sales_return
    final unposted = await (select(journalEntries)
          ..where((e) =>
              e.isPosted.equals(false) &
              (e.referenceType.equals('sales_invoice') |
               e.referenceType.equals('sales_return'))))
        .get();

    if (unposted.isEmpty) return;

    debugPrint('[ACCOUNTING_FIX] Found ${unposted.length} unposted sales/return entries. Posting now...');

    final affectedAccountIds = <int>{};
    final unpostedIds = unposted.map((e) => e.id).toSet();

    if (unpostedIds.isNotEmpty) {
      final lines = await (select(journalEntryLines)
            ..where((l) => l.entryId.isIn(unpostedIds)))
          .get();
      for (final line in lines) {
        affectedAccountIds.add(line.accountId);
      }
    }

    for (final entry in unposted) {
      // Mark as posted and autoPosted
      await (update(journalEntries)..where((e) => e.id.equals(entry.id))).write(
        const JournalEntriesCompanion(
          isPosted: Value(true),
          isAutoPosted: Value(true),
          needsApproval: Value(false),
        ),
      );
    }

    // Batch recalculate balances: 1 SELECT + 1 batch-UPDATE (perf-01)
    if (affectedAccountIds.isNotEmpty) {
      final ph = affectedAccountIds.map((_) => '?').join(', ');
      final bRows = await customSelect(
        'SELECT jel.account_id, '
        'COALESCE(SUM(jel.debit), 0.0) - COALESCE(SUM(jel.credit), 0.0) AS computed_balance '
        'FROM journal_entry_lines jel '
        'INNER JOIN journal_entries je ON je.id = jel.entry_id '
        'WHERE jel.account_id IN ($ph) AND je.is_posted = 1 '
        'GROUP BY jel.account_id',
        variables: affectedAccountIds.map((id) => Variable.withInt(id)).toList(),
        readsFrom: {journalEntryLines, journalEntries, accounts},
      ).get();
      final bm = <int, double>{
        for (final r in bRows) r.read<int>('account_id'): r.read<double>('computed_balance'),
      };
      await batch((b) {
        for (final accountId in affectedAccountIds) {
          b.update(accounts, AccountsCompanion(balance: Value(bm[accountId] ?? 0.0)),
              where: (a) => a.id.equals(accountId));
        }
      });
    }

    debugPrint('[ACCOUNTING_FIX] Posted ${unposted.length} entries, recalculated ${affectedAccountIds.length} account balances.');
  }



  /// Recalculate account balance from POSTED journal entry lines only (self-healing)
  /// Per IAS 1: balances derive from journal entries, not incremental adds
  /// ICR-01: excludes unposted (draft) entries from balance calculation
  /// PostgreSQL-compatible: uses Drift expression API instead of raw SQL
  Future<void> _updateAccountBalance(int accountId, double _) async {
    final debitCol = journalEntryLines.debit.sum();
    final creditCol = journalEntryLines.credit.sum();
    final query = selectOnly(journalEntryLines).join([
      innerJoin(journalEntries, journalEntries.id.equalsExp(journalEntryLines.entryId)),
    ]);
    query.addColumns([debitCol, creditCol]);
    query.where(journalEntryLines.accountId.equals(accountId) & journalEntries.isPosted.equals(true));
    final row = await query.getSingleOrNull();
    final totalDebit = row?.read(debitCol) ?? 0.0;
    final totalCredit = row?.read(creditCol) ?? 0.0;
    final computedBalance = totalDebit - totalCredit;
    await (update(accounts)..where((a) => a.id.equals(accountId))).write(
      AccountsCompanion(balance: Value(computedBalance)),
    );
  }


  // D-PERF-1: removed the dead `refreshPeriodSummary` method. It was the ONLY
  // writer of `period_account_summaries`, had ZERO callers, and the table has
  // ZERO read sites — getBalanceSheet/getTrialBalance always full-scan the
  // journal. Wiring a materialized period-summary cache is a future
  // optimization, not a bug fix: it must be refreshed on every posting/void or
  // it silently drifts and reports wrong financials. The empty table is left in
  // place (harmless; not provisioned on PG) as a candidate for a future
  // schema-cleanup migration.

  /// Create a new cost center
  Future<int> createCostCenter({
    required String code,
    required String name,
    int? parentId,
  }) {
    return into(costCenters).insert(
      CostCentersCompanion.insert(
        code: code,
        name: name,
        parentId: Value(parentId),
        // UUID-First (Phase 1): stable cross-install identity for sync.
        globalId: Value(UuidV7.generate()),
      ),
    );
  }


  /// Update cost center
  Future<void> updateCostCenter(int id, {String? code, String? name, int? parentId, bool? isActive}) {
    return (update(costCenters)..where((t) => t.id.equals(id))).write(
      CostCentersCompanion(
        code: code != null ? Value(code) : const Value.absent(),
        name: name != null ? Value(name) : const Value.absent(),
        parentId: parentId != null ? Value(parentId) : const Value.absent(),
        isActive: isActive != null ? Value(isActive) : const Value.absent(),
      ),
    );
  }


  /// Soft-delete cost center (mark inactive)
  Future<void> deactivateCostCenter(int id) {
    return (update(costCenters)..where((t) => t.id.equals(id))).write(
      const CostCentersCompanion(isActive: Value(false)),
    );
  }


  /// Ensure default accounts exist (comprehensive chart of accounts)
  /// v110: Updated to match the new hierarchical code system
  Future<void> syncDefaultAccounts() async {
    final defaults = [
      // --- الأصول ---
      {'code': '1111', 'name': 'الصندوق الرئيسي', 'type': 'asset'},
      {'code': '1112', 'name': 'صندوق العهد والمصروفات', 'type': 'asset'},
      {'code': '1113', 'name': 'البنك الأهلي - حساب جاري', 'type': 'asset'},
      {'code': '1114', 'name': 'بنك القاهرة - حساب جاري', 'type': 'asset'},
      {'code': '1116', 'name': 'حساب Click', 'type': 'asset'},
      {'code': '1121', 'name': 'ذمم عملاء محليون', 'type': 'asset'},
      {'code': '1123', 'name': 'أوراق القبض', 'type': 'asset'},
      {'code': '1131', 'name': 'مخزون المواد الخام', 'type': 'asset'},
      {'code': '1133', 'name': 'مخزون تحت التشغيل', 'type': 'asset'},
      {'code': '1134', 'name': 'مخزون البضاعة التامة الصنع', 'type': 'asset'},
      {'code': '1136', 'name': 'مخزون البضاعة للبيع', 'type': 'asset'},
      {'code': '1141', 'name': 'ضريبة القيمة المضافة - مدفوعة', 'type': 'asset'},
      {'code': '1143', 'name': 'المصروفات المدفوعة مقدماً', 'type': 'asset'},
      {'code': '1146', 'name': 'سلف الموظفين', 'type': 'asset'},
      {'code': '1211', 'name': 'الأراضي', 'type': 'asset'},
      {'code': '1212', 'name': 'مباني وإنشاءات', 'type': 'asset'},
      {'code': '1213', 'name': 'مركبات وسيارات', 'type': 'asset'},
      {'code': '1214', 'name': 'أثاث ومفروشات', 'type': 'asset'},
      {'code': '1215', 'name': 'آلات ومعدات', 'type': 'asset'},
      {'code': '1216', 'name': 'أجهزة حاسوب ومعدات مكتبية', 'type': 'asset'},
      {'code': '1217', 'name': 'أصول ثابتة أخرى', 'type': 'asset'},
      {'code': '1218', 'name': 'مجمع إهلاك المباني', 'type': 'asset'},
      {'code': '1219', 'name': 'مجمع إهلاك الأصول الأخرى', 'type': 'asset'},
      // --- الالتزامات ---
      {'code': '2111', 'name': 'ذمم موردون محليون', 'type': 'liability'},
      {'code': '2113', 'name': 'أوراق الدفع', 'type': 'liability'},
      {'code': '2121', 'name': 'ضريبة القيمة المضافة - محصلة', 'type': 'liability'},
      {'code': '2122', 'name': 'ضريبة الدخل المستحقة', 'type': 'liability'},
      {'code': '2131', 'name': 'رواتب ومزايا مستحقة', 'type': 'liability'},
      {'code': '2133', 'name': 'إيرادات مقدمة', 'type': 'liability'},
      {'code': '2141', 'name': 'قروض بنكية قصيرة الأجل', 'type': 'liability'},
      // --- حقوق الملكية ---
      {'code': '311', 'name': 'رأس المال', 'type': 'equity'},
      {'code': '313', 'name': 'الأرباح المبقاة', 'type': 'equity'},
      {'code': '314', 'name': 'الأرباح والخسائر السنة الحالية', 'type': 'equity'},
      {'code': '315', 'name': 'حقوق الشريك / المالك', 'type': 'equity'},
      // --- الإيرادات ---
      {'code': '4121', 'name': 'مبيعات محلية - تجاري', 'type': 'revenue'},
      {'code': '414', 'name': 'إيرادات التوصيل', 'type': 'revenue'},
      {'code': '4131', 'name': 'خدمات ما بعد البيع', 'type': 'revenue'},
      {'code': '4211', 'name': 'مردودات المبيعات', 'type': 'contra_revenue'},
      {'code': '4212', 'name': 'خصم المبيعات', 'type': 'contra_revenue'},
      {'code': '4316', 'name': 'خصم المشتريات المكتسب', 'type': 'revenue'},
      {'code': '4315', 'name': 'إيرادات متنوعة أخرى', 'type': 'revenue'},
      {'code': '4317', 'name': 'فائض مخزون', 'type': 'revenue'},
      {'code': '4318', 'name': 'فائض نقدي', 'type': 'revenue'},
      // --- تكلفة البضاعة المباعة ---
      {'code': '5211', 'name': 'تكلفة بضاعة تجارية محلية', 'type': 'expense'},
      {'code': '5213', 'name': 'تكاليف الاستيراد والجمارك', 'type': 'expense'},
      {'code': '5214', 'name': 'مردودات المشتريات', 'type': 'expense'},
      // --- مصروفات التشغيل ---
      {'code': '621', 'name': 'رواتب وأجور - إدارة', 'type': 'expense'},
      {'code': '623', 'name': 'مصروف الإيجارات', 'type': 'expense'},
      {'code': '6213', 'name': 'مصروفات الإهلاك - إداري', 'type': 'expense'},
      {'code': '6214', 'name': 'مصروفات متنوعة - إدارة', 'type': 'expense'},
      {'code': '6215', 'name': 'خصم مسموح به', 'type': 'expense'},
      {'code': '6216', 'name': 'عجز مخزون', 'type': 'expense'},
      {'code': '6217', 'name': 'عجز نقدي', 'type': 'expense'},
    ];

    for (var def in defaults) {
      final existing = await getAccountByCode(def['code'] as String);
      if (existing == null) {
        await into(accounts).insert(
          AccountsCompanion.insert(
            code: def['code'] as String,
            name: def['name'] as String,
            accountType: def['type'] as String,
            isSystem: const Value(true),
            // UUID-First (Phase 1): stable cross-install identity for sync.
            globalId: Value(UuidV7.generate()),
          ),
        );
      }
    }
    // NEW: Sync mappings after accounts are ensured to exist
    await syncAccountMappings();
  }


  /// Create a new account
  Future<int> createAccount({
    required String code,
    required String name,
    required String accountType,
    int? parentId,

    /// أبٌ لا يُرحَّل عليه (`view`) أم تفصيليٌّ يُرحَّل — اختيارُ مستخدمٍ لا
    /// اشتقاق. راجع [kAccountNatureView].
    String accountNature = kAccountNatureDetail,
  }) async {
    // Validate code uniqueness
    final existing = await getAccountByCode(code);
    if (existing != null) {
      throw Exception('رمز الحساب $code مستخدم بالفعل');
    }
    // ═══ 🔴 حقولٌ يعرف النظامُ اشتقاقَها ولم يكن يشتقّها ═══════════════
    //
    // هجرةُ v110 تملأ `normal_balance` من `account_type` و`level` من عمق
    // الأب بقاعدةٍ صريحة، **وهذا الكاتبُ كان يتركهما لافتراضات العمود**
    // (`'debit'` و`1`). فحسابُ إيراداتٍ جديدٌ يخرج «مديناً» — يناقض قاعدةَ
    // الهجرة نفسِها — وابنٌ في العمق الثالث يخرج بمستوى ١.
    //
    // ⚠️ والقاعدةُ من [normalBalanceFor]/[accountLevelUnder] لا مكتوبةً هنا:
    // نسختان تفترقان بأوّل نوعٍ يُضاف.
    final parentLevel = parentId == null
        ? null
        : (await (select(accounts)..where((a) => a.id.equals(parentId)))
                .getSingleOrNull())
            ?.level;

    return into(accounts).insert(
      AccountsCompanion.insert(
        code: code,
        name: name,
        accountType: accountType,
        parentId: Value(parentId),
        accountNature: Value(accountNature),
        normalBalance: Value(normalBalanceFor(accountType)),
        level: Value(accountLevelUnder(parentLevel)),
        // UUID-First (Phase 1): stable cross-install identity for sync.
        globalId: Value(UuidV7.generate()),
      ),
    );
  }


  /// Update an existing account
  Future<int> updateAccount(int id, {String? name, String? code, bool? isActive, bool? isHiddenFromEntries, String? accountNature}) async {
    // 🔴 **وحسابٌ مُرحَّلٌ عليه لا يصير رئيسيّاً**: حارسُ v110 يرفض الترحيلَ
    // على `view`، فتبديلُ الطبيعة بعد الترحيل يترك سطوراً قائمةً على حسابٍ
    // يقول النظامُ إنّه لا يقبلها — لا تُعكَس ولا تُعدَّل، والدفترُ يحمل ما
    // يمنعه. والفحصُ **قبل** الكتابة فلا يترك نصفَ تبديل.
    if (accountNature == kAccountNatureView) {
      final posted = await (selectOnly(journalEntryLines)
            ..addColumns([journalEntryLines.id.count()])
            ..where(journalEntryLines.accountId.equals(id)))
          .map((r) => r.read(journalEntryLines.id.count()) ?? 0)
          .getSingle();
      if (posted > 0) {
        throw Exception(
            'لا يمكن جعل الحساب رئيسيّاً — عليه $posted سطرَ قيدٍ مُرحَّل');
      }
    }

    return (update(accounts)..where((a) => a.id.equals(id))).write(
      AccountsCompanion(
        name: name != null ? Value(name) : const Value.absent(),
        code: code != null ? Value(code) : const Value.absent(),
        isActive: isActive != null ? Value(isActive) : const Value.absent(),
        isHiddenFromEntries: isHiddenFromEntries != null ? Value(isHiddenFromEntries) : const Value.absent(),
        accountNature: accountNature != null ? Value(accountNature) : const Value.absent(),
      ),
    );
  }


  /// Delete a non-system account with zero balance.
  ///
  /// Spec 067 (D5-002 P0): wrapped in a transaction with pre-flight
  /// child-reference checks. The SQLite FK enforcer (`PRAGMA foreign_keys=ON`)
  /// would catch orphan attempts mid-DELETE, but the raised
  /// `SqliteException(19)` is opaque English; the new Arabic guards surface
  /// the specific blocker (which child table, how many rows) BEFORE the
  /// DELETE runs.
  ///
  /// The 3 audit-named child tables (`journal_entry_lines.accountId`,
  /// `parties.accountId`, `safes.linkedAccountId`) cover the operator-facing
  /// references. Other low-volume references (journal templates, manufacturing
  /// assets, etc.) still rely on SQLite's FK enforcement for safety.
  Future<void> deleteAccount(int id) async {
    final account = await getAccountById(id);
    if (account == null) throw Exception('الحساب غير موجود');
    if (account.isSystem) throw Exception('لا يمكن حذف حساب نظام');
    if (account.balance.abs() > 0.001) {
      throw Exception('لا يمكن حذف حساب برصيد غير صفري');
    }

    await transaction(() async {
      // Pre-flight FK checks — surface Arabic guidance before the DELETE
      // hits SQLite's foreign-key enforcer.
      final jelCount = await (selectOnly(journalEntryLines)
            ..addColumns([journalEntryLines.id.count()])
            ..where(journalEntryLines.accountId.equals(id)))
          .map((row) => row.read(journalEntryLines.id.count())!)
          .getSingle();
      if (jelCount > 0) {
        throw Exception(
          'لا يمكن حذف الحساب — مرتبط بـ $jelCount قيد محاسبي. '
          'احذف القيود المرتبطة أولاً أو استخدم التعطيل بدلاً من الحذف.',
        );
      }

      final partyCount = await (selectOnly(parties)
            ..addColumns([parties.id.count()])
            ..where(parties.accountId.equals(id)))
          .map((row) => row.read(parties.id.count())!)
          .getSingle();
      if (partyCount > 0) {
        throw Exception(
          'لا يمكن حذف الحساب — مرتبط بـ $partyCount عميل/مورد. '
          'افصل الربط من شاشة العملاء/الموردين أولاً.',
        );
      }

      final safeCount = await (selectOnly(safes)
            ..addColumns([safes.id.count()])
            ..where(safes.linkedAccountId.equals(id)))
          .map((row) => row.read(safes.id.count())!)
          .getSingle();
      if (safeCount > 0) {
        throw Exception(
          'لا يمكن حذف الحساب — مرتبط بـ $safeCount خزنة. '
          'افصل الربط من إعدادات الخزائن أولاً.',
        );
      }

      // Safe to delete: zero balance + zero child references in the audit-
      // named tables.
      await (delete(accounts)..where((a) => a.id.equals(id))).go();
    });
  }


  /// Create activity profile
  Future<int> createActivityProfile({
    required String name,
    required String enabledModules,
  }) {
    return into(activityProfiles).insert(
      ActivityProfilesCompanion.insert(
        name: name,
        enabledModules: enabledModules,
      ),
    );
  }


  /// Seed default activity profiles
  Future<void> seedDefaultActivityProfiles() async {
    final existing = await select(activityProfiles).get();
    if (existing.isNotEmpty) return;

    final defaults = [
      {
        'name': 'تجاري',
        'modules':
            '["accounting","treasury","parties","sales_invoices","purchase_invoices","commercial_papers","reports"]',
      },
      {
        'name': 'صناعي',
        'modules':
            '["accounting","treasury","parties","sales_invoices","purchase_invoices","manufacturing","inventory","fixed_assets","reports"]',
      },
      {
        'name': 'POS',
        'modules':
            '["pos","treasury","parties","products","inventory","delivery","reports"]',
      },
      {
        'name': 'مؤسسات',
        'modules':
            '["accounting","treasury","parties","sales_invoices","purchase_invoices","cost_centers","fixed_assets","hr","reports"]',
      },
    ];

    for (var def in defaults) {
      await into(activityProfiles).insert(
        ActivityProfilesCompanion.insert(
          name: def['name'] as String,
          enabledModules: def['modules'] as String,
        ),
      );
    }
  }


  /// Ensure all default account mappings are seeded into the database
  Future<void> syncAccountMappings() async {
    for (var entry in AccountingDaoReadsExt.accountPurposes.entries) {
      final purpose = entry.key;
      final defaultCode = entry.value;

      // Check if mapping already exists.
      //
      // Feature 042 (Bug 3 — fixed-assets "Bad state: too many elements"):
      // mirror sync replays can leave more than one `account_mappings` row
      // per purpose key on the mirror device (the table has no UNIQUE
      // constraint on `purpose` because (purpose, costCenterId) is the
      // composite key in spirit). Without `.limit(1)` this `.getSingleOrNull()`
      // throws on those mirrors, taking down EVERY caller of
      // `syncDefaultAccounts()` — most visibly the fixed-asset create
      // dialog whose entry path runs the sync. We only need to know
      // whether at least one mapping exists for this purpose; the
      // duplicates are a separate data-drift concern.
      final existing = await (select(accountMappings)
            ..where((m) => m.purpose.equals(purpose))
            ..limit(1))
          .getSingleOrNull();

      if (existing == null) {
        // Find the account by its default code
        final account = await getAccountByCode(defaultCode);
        if (account != null) {
          try {
            await into(accountMappings).insert(
              AccountMappingsCompanion.insert(
                purpose: purpose,
                accountId: account.id,
                description: Value('Default mapping for $purpose'),
              ),
            );
          } catch (e) {
            // Defensive: skip if UNIQUE constraint still fires
            debugPrint('[ACCOUNT_MAPPING] seed skip $purpose: $e');
          }
        }
      }
    }
  }


  /// Force-reset ALL account mappings to defaults from accountPurposes map.
  /// Deletes existing global mappings for each known purpose then re-inserts
  /// the default account. Cost-center-specific overrides are also cleared.
  /// Used by the "استعادة الافتراضي" button in account_mapping_settings_screen.
  Future<void> resetToDefaultMappings() async {
    for (final entry in AccountingDaoReadsExt.accountPurposes.entries) {
      final purpose = entry.key;
      final code = entry.value;
      final account = await getAccountByCode(code);
      if (account == null) {
        debugPrint('[MAPPING] resetDefault skip $purpose: account $code not found');
        continue;
      }
      try {
        await (delete(accountMappings)..where((m) => m.purpose.equals(purpose))).go();
        await into(accountMappings).insert(
          AccountMappingsCompanion.insert(
            purpose: purpose,
            accountId: account.id,
            description: Value('Default mapping for $purpose'),
          ),
        );
      } catch (e) {
        debugPrint('[MAPPING] resetDefault skip $purpose: $e');
      }
    }
  }

  /// Set account mapping for a specific purpose, optionally per cost center.
  /// PostgreSQL-compatible: uses Drift delete+insert instead of raw SQL
  Future<void> setAccountMapping(String purpose, int accountId, {int? costCenterId}) async {
    await transaction(() async {
      // Delete any existing mapping for this purpose+costCenter combo
      if (costCenterId != null) {
        await (delete(accountMappings)
          ..where((m) => m.purpose.equals(purpose) & m.costCenterId.equals(costCenterId))
        ).go();
      } else {
        await (delete(accountMappings)
          ..where((m) => m.purpose.equals(purpose) & m.costCenterId.isNull())
        ).go();
      }
      // Insert the new mapping
      await into(accountMappings).insert(
        AccountMappingsCompanion.insert(
          purpose: purpose,
          accountId: accountId,
          costCenterId: Value(costCenterId),
        ),
      );
    });
  }


  /// Reverse accounting entries when a return is cancelled
  Future<void> reverseReturnAccountingEntry({
    required int invoiceId,
    required String invNumber,
  }) async {
    final entries = await (select(journalEntries)
          ..where((e) =>
              e.referenceType.equals('sales_return') &
              e.referenceId.equalsNullable(invoiceId)))
        .get();

    for (final entry in entries) {
      // Spec 151 (idempotency): give the cancel/reversal JE a deterministic
      // globalId derived from the ORIGINAL return JE's own gid (mirrors
      // reverseJournalEntryById). Without it, a double-cancel (retry, resync,
      // or accidental re-invoke) posts a SECOND contra JE — double-reversing
      // the contra-revenue / COGS / AR legs and corrupting the GL. If a
      // '<origGid>-rev' entry already exists, this original return was already
      // reversed → skip.
      final origGid = entry.globalId;
      final reversalGid = (origGid != null && origGid.isNotEmpty)
          ? '$origGid-rev'
          : 'return-cancel-${entry.id}-rev';
      final alreadyReversed = await (select(journalEntries)
            ..where((e) => e.globalId.equals(reversalGid))
            ..limit(1))
          .getSingleOrNull();
      if (alreadyReversed != null) {
        debugPrint('[RETURN-CANCEL] reversal already exists for return JE '
            '#${entry.id} (gid=$reversalGid) — skipping (idempotent)');
        continue;
      }

      final lines = await (select(journalEntryLines)
            ..where((l) => l.entryId.equals(entry.id)))
          .get();

      final List<JournalLine> reverseLines = [];
      for (final line in lines) {
        reverseLines.add(
          JournalLine(
            accountId: line.accountId,
            debit: line.credit,
            credit: line.debit,
            description: 'إلغاء قيد مرتجع فاتورة #$invNumber',
          ),
        );
      }

      if (reverseLines.isNotEmpty) {
        await createJournalEntry(
          description: 'إلغاء قيد مرتجع - فاتورة #$invNumber',
          date: DateTime.now(),
          lines: reverseLines,
          referenceType: 'return_cancel',
          referenceId: invoiceId,
          globalId: reversalGid,
        );
      }
    }
  }


  /// F-02 fix (MJE-1 / MJE-2): reverse a single journal entry by its own
  /// primary key instead of by (referenceType, referenceId).
  ///
  /// [reverseTransaction] below matches `WHERE reference_type=? AND
  /// reference_id=?`, but the journal-entries screen was passing the JE's
  /// OWN id as `referenceId`. For a manual JE (reference_id is NULL) that
  /// matches nothing → a silent no-op that still reports success (MJE-1).
  /// For an auto-posted JE whose row id happens to equal some UNRELATED
  /// entry's reference_id, it reverses that unrelated entry instead,
  /// corrupting its GL (MJE-2). Loading by primary key sidesteps both.
  ///
  /// Modelled on [reverseAutoPostedJournalEntriesFor] above: same
  /// deterministic-globalId + idempotency pattern, just keyed by the
  /// entry's own id rather than a reference lookup.
  ///
  /// The reversal globalId is `'<original.globalId>-rev'`, or
  /// `'je-manual-<entryId>-rev'` when the original has no globalId (legacy
  /// rows). If a JE with that globalId already exists, this is a no-op
  /// (idempotent — safe to call twice, e.g. after a crash or a resync).
  ///
  /// Returns the new reversal JE's id, or 0 if nothing was reversed
  /// (entry not found, has no lines, or was already reversed).
  Future<int> reverseJournalEntryById({
    required int entryId,
    String? descriptionPrefix,
  }) async {
    final original = await (select(journalEntries)
          ..where((e) => e.id.equals(entryId) & e.isDeleted.equals(false)))
        .getSingleOrNull();
    if (original == null) {
      debugPrint('[JE-REVERSE-BY-ID] JE #$entryId not found (or soft-deleted) '
          '— nothing to reverse');
      return 0;
    }

    // ═══ 🔴 ولا يُعكَس إلّا ما رُحِّل — قياسُ 2026-09-19 ═══════════════════
    //
    // المسوّدةُ (`isPosted = false`) سطورُها في الجدول لكنّها **مستثناةٌ من
    // حساب الأرصدة** (`WHERE je.is_posted = 1`)، أي لم تمسّ الدليلَ بعد.
    // وعكسُها كان يُنشئ قيداً **مُرحَّلاً** (‏`createJournalEntry` افتراضُه
    // `asDraft: false`) فتتحرّك الأرصدةُ في اتّجاهٍ واحدٍ بلا شيءٍ يلغيه.
    //
    // ⚠️ **والضررُ الأخطرُ لاحق**: المسوّدةُ تبقى تنتظر الاعتماد؛ فإن
    // اعتُمدت صار الطرفان مُرحَّلَين فتلاشى أثرُ القيد — عمليّةٌ تمّت ولا
    // أثرَ لها. (قِيس: الرصيدُ المتوقَّعُ ‎500‎ والمقيسُ ‎0.0‎.)
    //
    // ورميٌ لا `return 0`: الصفرُ يعني «معكوسٌ أصلاً» في هذا العقد، فيقرؤه
    // المستدعي رسالةً كاذبة. والمسوّدةُ **تُعتمَد أو تُعدَّل**، لا تُعكَس.
    if (!original.isPosted) {
      throw Exception('القيد ${original.entryNumber} مسودة لم تُرحَّل — '
          'لا يُعكَس ما لم يدخل الأستاذ؛ اعتمده أو عدّله');
    }

    final sourceGid = original.globalId;
    final reversalGid = (sourceGid != null && sourceGid.isNotEmpty)
        ? '$sourceGid-rev'
        : 'je-manual-$entryId-rev';

    // Idempotency check — mirrors reverseAutoPostedJournalEntriesFor.
    final existing = await (select(journalEntries)
          ..where((e) => e.globalId.equals(reversalGid))
          ..limit(1))
        .getSingleOrNull();
    if (existing != null) {
      debugPrint('[JE-REVERSE-BY-ID] Reversal already exists for JE #$entryId '
          '(gid=$reversalGid) — skipping');
      return 0;
    }

    final originalLines = await (select(journalEntryLines)
          ..where((l) => l.entryId.equals(original.id)))
        .get();
    if (originalLines.isEmpty) {
      debugPrint('[JE-REVERSE-BY-ID] JE #$entryId has no lines — nothing to reverse');
      return 0;
    }

    final reversalLines = originalLines
        .map((line) => JournalLine(
              accountId: line.accountId,
              debit: line.credit, // swap
              credit: line.debit,
              description: 'عكس: ${line.description ?? ""}',
              costCenterId: line.costCenterId,
            ))
        .toList();

    final prefix = descriptionPrefix ?? 'عكس قيد';
    final newId = await createJournalEntry(
      description: '$prefix - ${original.description ?? original.entryNumber}',
      date: DateTime.now(),
      lines: reversalLines,
      referenceType: 'reversal',
      // Use the ORIGINAL JE's own PK (unique) — NOT original.referenceId
      // (a source-doc id that two auto-posted JEs of different types can
      // share, e.g. sale#5 + purchase#5). createJournalEntry's auto-post
      // dedup is keyed on (referenceType, referenceId, isAutoPosted) and an
      // explicit globalId does NOT bypass it; keying on referenceId would
      // collapse both reversals to (reversal, 5, true) and silently drop
      // the second. entry.id makes each reversal's key unique and also
      // gives a correct per-JE in-transaction idempotency backstop.
      // No consumer reads a reversal's referenceId as a source-doc id.
      referenceId: original.id,
      isAutoPosted: true,
      costCenterId: original.costCenterId,
      branchId: original.branchId,
      globalId: reversalGid,
    );
    debugPrint('[JE-REVERSE-BY-ID] Reversed JE #$entryId → new JE #$newId '
        '(gid=$reversalGid)');
    return newId;
  }


  /// Generically reverse any accounting transaction
  Future<void> reverseTransaction({
    required String referenceType,
    required int referenceId,
    required String descriptionPrefix,
    required String newReferenceType,
  }) async {
    final entries = await (select(journalEntries)
          ..where((e) =>
              e.referenceType.equals(referenceType) &
              e.referenceId.equalsNullable(referenceId)))
        .get();

    for (final entry in entries) {
      final lines = await (select(journalEntryLines)
            ..where((l) => l.entryId.equals(entry.id)))
          .get();

      final List<JournalLine> reverseLines = [];
      for (final line in lines) {
        reverseLines.add(
          JournalLine(
            accountId: line.accountId,
            debit: line.credit,
            credit: line.debit,
            description: '$descriptionPrefix - ${line.description}',
          ),
        );
      }

      if (reverseLines.isNotEmpty) {
        await createJournalEntry(
          description: '$descriptionPrefix - ${entry.description}',
          date: DateTime.now(),
          lines: reverseLines,
          referenceType: newReferenceType,
          referenceId: referenceId,
          isAutoPosted: true,
          costCenterId: entry.costCenterId,
        );
      }
    }
  }


  // ─────────────────────────────────────────────────────────────────────────
  // F-15: MAKER-CHECKER — اعتماد القيود اليدوية
  // ─────────────────────────────────────────────────────────────────────────

  /// Create a manual journal entry as draft (requires approval to post)
  Future<int> createDraftJournalEntry({
    required String description,
    required DateTime date,
    required List<JournalLine> lines,
    String? referenceType,
    int? referenceId,
  }) async {
    final entryId = await createJournalEntry(
      description: description,
      date: date,
      lines: lines,
      referenceType: referenceType,
      referenceId: referenceId,
      isAutoPosted: false,
    );

    // Override status to draft — these columns are migration-added, not in Drift schema
    // Must use customStatement but with db.sqlBool() for PG compatibility
    final boolFalse = sqlBool(false);
    await customStatement(
      "UPDATE journal_entries SET status = 'draft', is_posted = $boolFalse WHERE id = ?",
      [entryId],
    );

    return entryId;
  }


  /// Approve a draft journal entry (Maker-Checker: approver != creator)
  /// Uses customStatement for migration-added columns (status, approved_by, approved_at)
  Future<void> approveJournalEntry(int entryId, int approverId) async {
    // ورقةُ الدفع تُجمَع داخلَ المعاملة وتُرسَل بعد إغلاقها — كما في
    // `createJournalEntry` تماماً، كي لا تحبس زمنُ الشبكة قفلَ الكتابة.
    String? pushDesc;
    DateTime? pushDate;
    List<Map<String, dynamic>>? pushLines;
    String? pushGlobalId;
    int? pushCostCenterId;
    int? pushBranchId;

    await transaction(() async {
      final entry = await (select(journalEntries)
            ..where((e) => e.id.equals(entryId)))
          .getSingleOrNull();
      if (entry == null) throw Exception('القيد غير موجود');
      if (entry.isPosted) throw Exception('القيد مرحّل بالفعل');

      // ⚠️ **لا يعتمد القيدَ منشئُه** — قرارُ مالك 2026-08-27.
      //
      //    والفحصُ هنا لا في الواجهة: الواجهةُ تُخفي الزرَّ فتحسّن التجربة،
      //    لكنّ المسارَ يُبلَغ من غيرها (مزامنة · سكربت · شاشةٌ ثانية).
      //    وهو **قبل** أيّ كتابة، فالرفضُ لا يترك رصيداً تحرّك.
      //
      //    و`created_by = NULL` لا يُمنَع: قيدٌ أقدمُ من الضابط أو آليٌّ لا
      //    يمكن إثباتُ منشئه، ومنعُه يُجمّده بلا سبيلٍ لفكِّه.
      final makerRow = await customSelect(
        'SELECT created_by FROM journal_entries WHERE id = ?',
        variables: [Variable.withInt(entryId)],
        readsFrom: {journalEntries},
      ).getSingleOrNull();
      final maker = makerRow?.read<int?>('created_by');
      if (maker != null && maker == approverId) {
        throw Exception('لا يعتمد القيدَ منشئُه — يلزم اعتمادُ مستخدمٍ آخر');
      }

      // Post and record approval — migration-added columns, must use customStatement
      final boolTrue = sqlBool(true);
      final boolFalse = sqlBool(false);
      await customStatement(
        "UPDATE journal_entries SET is_posted = $boolTrue, needs_approval = $boolFalse, approved_by = ?, approved_at = ? WHERE id = ?",
        [approverId, DateTime.now().millisecondsSinceEpoch, entryId],
      );

      // ICR-01: Update account balances now that the entry is posted (perf-01 batch)
      final approvalLines = await (select(journalEntryLines)..where((l) => l.entryId.equals(entryId))).get();
      final approvalAccountIds = approvalLines.map((l) => l.accountId).toSet();
      if (approvalAccountIds.isNotEmpty) {
        final ph = approvalAccountIds.map((_) => '?').join(', ');
        final bRows = await customSelect(
          'SELECT jel.account_id, '
          'COALESCE(SUM(jel.debit), 0.0) - COALESCE(SUM(jel.credit), 0.0) AS computed_balance '
          'FROM journal_entry_lines jel '
          'INNER JOIN journal_entries je ON je.id = jel.entry_id '
          'WHERE jel.account_id IN ($ph) AND je.is_posted = 1 '
          'GROUP BY jel.account_id',
          variables: approvalAccountIds.map((id) => Variable.withInt(id)).toList(),
          readsFrom: {journalEntryLines, journalEntries, accounts},
        ).get();
        final bm = <int, double>{
          for (final r in bRows) r.read<int>('account_id'): r.read<double>('computed_balance'),
        };
        await batch((b) {
          for (final accountId in approvalAccountIds) {
            b.update(accounts, AccountsCompanion(balance: Value(bm[accountId] ?? 0.0)),
                where: (a) => a.id.equals(accountId));
          }
        });
      }

      // ورقةُ الدفع — تُجمَع هنا وتُرسَل بعد إغلاق المعاملة.
      if (SyncInterceptor.isClientMode) {
        pushDesc = entry.description ?? '';
        pushDate = entry.entryDate;
        pushGlobalId = entry.globalId;
        pushCostCenterId = entry.costCenterId;
        pushBranchId = entry.branchId;
        pushLines = approvalLines
            .map((l) => <String, dynamic>{
                  'account_id': l.accountId,
                  'debit': l.debit,
                  'credit': l.credit,
                  'description': l.description,
                  'cost_center_id': l.costCenterId,
                })
            .toList();
      }
    });

    // ⚠️ **الاعتمادُ هو ما يدفع المسودّةَ إلى الخادم.** إنشاؤها لا يدفع
    //    (‏راجع `createJournalEntry`)، فلو لم تُدفَع هنا لبقيت محبوسةً في
    //    الجهاز بعد اعتمادها: رصيدٌ يتحرّك محلّيّاً ولا أثرَ له على الخادم
    //    ولا على بقيّة الأجهزة — وهو افتراقُ أستاذٍ صامت.
    //
    //    والـ`globalId` يُمرَّر كما هو، فالخادمُ يخزّنها تحت نفس الهويّة
    //    ولا تعود بالسحب صفّاً مكرَّراً.
    final desc = pushDesc;
    final lines = pushLines;
    if (desc != null && lines != null) {
      try {
        await SyncInterceptor.instance?.submitJournalEntry(
          description: desc,
          date: pushDate!,
          lines: lines,
          isAutoPosted: false,
          costCenterId: pushCostCenterId,
          branchId: pushBranchId,
          globalId: pushGlobalId,
        );
      } catch (e) {
        debugPrint('[ACCOUNTING_SYNC] Approval push failed for JE #$entryId: $e');
      }
    }
  }


  /// Reject a draft journal entry
  /// Uses customStatement for migration-added columns (status, approved_by, approved_at)
  Future<void> rejectJournalEntry(int entryId, int rejectorId) async {
    await customStatement(
      "UPDATE journal_entries SET status = 'rejected', approved_by = ?, approved_at = ? WHERE id = ?",
      [rejectorId, DateTime.now().millisecondsSinceEpoch, entryId],
    );
  }

  /// ONE-TIME REMEDIATION: Backfill missing cost center IDs from parent entries to lines.
  /// This fixes visibility issues in financial reports for historical transactions.
  Future<int> remediateHistoricalCostCenters() async {
    debugPrint('[ACCOUNTING_REMEDIATION] Starting cost center backfill...');
    
    // SQLite/PostgreSQL-agnostic update using a JOIN/Subquery logic
    // We update journal_entry_lines with the cost_center_id of their parent journal_entry
    // only if the line's cost_center_id is currently NULL.
    
    const sql = '''
      UPDATE journal_entry_lines 
      SET cost_center_id = (
        SELECT cost_center_id FROM journal_entries 
        WHERE journal_entries.id = journal_entry_lines.entry_id
      )
      WHERE cost_center_id IS NULL 
      AND EXISTS (
        SELECT 1 FROM journal_entries 
        WHERE journal_entries.id = journal_entry_lines.entry_id 
        AND journal_entries.cost_center_id IS NOT NULL
      )
    ''';
    
    try {
      await customStatement(sql);
      
      // Count how many lines were fixed (for logging)
      final countQuery = await customSelect('SELECT COUNT(*) as cnt FROM journal_entry_lines WHERE cost_center_id IS NOT NULL').getSingle();
      final totalWithCC = countQuery.read<int>('cnt');
      
      debugPrint('[ACCOUNTING_REMEDIATION] Backfill complete. Lines with CC: $totalWithCC');
      return totalWithCC;
    } catch (e) {
      debugPrint('[ACCOUNTING_REMEDIATION] Error: $e');
      return 0;
    }
  }

  /// ONE-OFF REPAIR: re-attribute historical AUTO-POSTED journal entries that
  /// landed on the global «عام» (GEN) cost center back to their branch's OWN
  /// centre — falling back to the branch's region centre — matching the fixed
  /// resolution priority in [createJournalEntry] (explicit → branch → region →
  /// GEN). This repairs pre-fix history where every branch sale/purchase was
  /// attributed to «عام».
  ///
  /// [dryRun] true (default) only COUNTS what would move and writes nothing.
  /// Balance-neutral: only the analytical cost-center dimension changes; no
  /// debit/credit amount, trial balance, or P&L total is touched. Manual
  /// journal entries are left untouched (only `is_auto_posted` rows move).
  ///
  /// Mirror of scripts/repair_branch_cost_centers.sql, run through the app so
  /// it works on both the encrypted local (SQLCipher) and Postgres backends.
  Future<BranchCostCenterRepairReport> repairBranchCostCenterAttribution({
    bool dryRun = true,
  }) async {
    final boolTrue = sqlBool(true);

    // Entries currently on a GEN «عام» centre whose branch (or its region) has
    // its own non-GEN centre — i.e. the ones that should move.
    final entryCountSql = '''
      SELECT COUNT(*) AS cnt
      FROM journal_entries je
      JOIN branches b     ON b.id = je.branch_id
      LEFT JOIN regions r ON r.id = b.region_id
      WHERE je.is_auto_posted = $boolTrue
        AND je.cost_center_id IN (SELECT id FROM cost_centers WHERE code = 'GEN')
        AND COALESCE(b.cost_center_id, r.cost_center_id) IS NOT NULL
        AND COALESCE(b.cost_center_id, r.cost_center_id)
              NOT IN (SELECT id FROM cost_centers WHERE code = 'GEN')
    ''';

    final lineCountSql = '''
      SELECT COUNT(*) AS cnt
      FROM journal_entry_lines jel
      WHERE jel.cost_center_id IN (SELECT id FROM cost_centers WHERE code = 'GEN')
        AND EXISTS (
          SELECT 1
          FROM journal_entries je
          JOIN branches b     ON b.id = je.branch_id
          LEFT JOIN regions r ON r.id = b.region_id
          WHERE je.id = jel.entry_id
            AND je.is_auto_posted = $boolTrue
            AND je.cost_center_id IN (SELECT id FROM cost_centers WHERE code = 'GEN')
            AND COALESCE(b.cost_center_id, r.cost_center_id) IS NOT NULL
            AND COALESCE(b.cost_center_id, r.cost_center_id)
                  NOT IN (SELECT id FROM cost_centers WHERE code = 'GEN')
        )
    ''';

    try {
      final entries = (await customSelect(entryCountSql).getSingle()).read<int>('cnt');
      final lines = (await customSelect(lineCountSql).getSingle()).read<int>('cnt');

      if (dryRun || entries == 0) {
        debugPrint('[CC_REPAIR] dryRun=$dryRun preview: entries=$entries lines=$lines');
        return BranchCostCenterRepairReport(
          affectedEntries: entries,
          affectedLines: lines,
          applied: false,
        );
      }

      // Move LINES first (while headers still point at GEN, so target entries
      // remain identifiable), then the HEADERS. One transaction — all or nothing.
      await transaction(() async {
        await customStatement('''
          UPDATE journal_entry_lines
          SET cost_center_id = (
                SELECT COALESCE(b.cost_center_id, r.cost_center_id)
                FROM journal_entries je
                JOIN branches b     ON b.id = je.branch_id
                LEFT JOIN regions r ON r.id = b.region_id
                WHERE je.id = journal_entry_lines.entry_id
              )
          WHERE journal_entry_lines.cost_center_id IN (SELECT id FROM cost_centers WHERE code = 'GEN')
            AND EXISTS (
              SELECT 1
              FROM journal_entries je
              JOIN branches b     ON b.id = je.branch_id
              LEFT JOIN regions r ON r.id = b.region_id
              WHERE je.id = journal_entry_lines.entry_id
                AND je.is_auto_posted = $boolTrue
                AND je.cost_center_id IN (SELECT id FROM cost_centers WHERE code = 'GEN')
                AND COALESCE(b.cost_center_id, r.cost_center_id) IS NOT NULL
                AND COALESCE(b.cost_center_id, r.cost_center_id)
                      NOT IN (SELECT id FROM cost_centers WHERE code = 'GEN')
            )
        ''');

        await customStatement('''
          UPDATE journal_entries
          SET cost_center_id = (
                SELECT COALESCE(b.cost_center_id, r.cost_center_id)
                FROM branches b
                LEFT JOIN regions r ON r.id = b.region_id
                WHERE b.id = journal_entries.branch_id
              )
          WHERE journal_entries.is_auto_posted = $boolTrue
            AND journal_entries.cost_center_id IN (SELECT id FROM cost_centers WHERE code = 'GEN')
            AND journal_entries.branch_id IS NOT NULL
            AND (SELECT COALESCE(b.cost_center_id, r.cost_center_id)
                 FROM branches b LEFT JOIN regions r ON r.id = b.region_id
                 WHERE b.id = journal_entries.branch_id) IS NOT NULL
            AND (SELECT COALESCE(b.cost_center_id, r.cost_center_id)
                 FROM branches b LEFT JOIN regions r ON r.id = b.region_id
                 WHERE b.id = journal_entries.branch_id)
                  NOT IN (SELECT id FROM cost_centers WHERE code = 'GEN')
        ''');
      });

      debugPrint('[CC_REPAIR] applied: entries=$entries lines=$lines moved to branch centres');
      return BranchCostCenterRepairReport(
        affectedEntries: entries,
        affectedLines: lines,
        applied: true,
      );
    } catch (e) {
      debugPrint('[CC_REPAIR] Error: $e');
      rethrow;
    }
  }
}
