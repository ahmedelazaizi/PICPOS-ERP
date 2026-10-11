part of '../database.dart';

/// Shift settlement: expected-vs-actual cash and variance posting.
extension TreasuryShiftSettlementDao on AppDatabase {
   /// PIR-06 Step 1: Calculate expected cash and record shift settlement
  /// FIX: Own transaction wrapper to keep settlement atomic without nesting.
  Future<_ShiftSettlementResult> _settleShift({
    required Shift shift,
    required double actualCash,
    required DateTime endTime,
    String? notes,
    String closingMethod = 'normal',
    String? closingSnapshot,
  }) async {
    return transaction(() async {
      // ⚠️ نطاقان مختلفان عن قصد، وخلطُهما كان أصلَ عطبٍ ماليّ:
      //
      // [txs] — مفلترةٌ بـ`shift.userId` — تخصّ **التصريف** وحدَه
      //   (`_closeShiftSafes`, Spec 136 ISS-8): الإقفال يرحّل صافيَ ما حرّكته
      //   هذه الوردية فقط، ويترك فلوسَ الورديات الأخرى في الدرج.
      //
      // [drawerTxs] — بلا فلترِ مستخدم — تخصّ **التوقّع**: `expectedCash`
      //   يوصف ما ينبغي أن يكون في الدرج **فعلاً**، والدرجُ واحدٌ يشترك فيه
      //   كلُّ من مسّه. والكاشير يعدّه كلَّه.
      //
      // قبل الفصل كان الاثنان نطاقاً واحداً، فأيُّ إيصالٍ على نفس الدرج
      // بمستخدمٍ آخر يسقط من التوقّع بينما فلوسُه في الدرج:
      //   * بيعةُ مديرٍ بلا وردية (الفورك يتخطّى `_ensureShiftOpen` له)
      //     ⇒ **فائضٌ** بحجمها بالضبط، فيُقيَّد «فائض نقدية» مدين نقدية /
      //     دائن إيراد — والمبلغُ نفسُه كان قد قُيِّد بقيد البيعة. النتيجة:
      //     النقديةُ في الأستاذ مرّتين وإيرادٌ وهميّ. مقيس: فرقُ +٢٠٠.
      //   * سندُ صرفٍ يوقّعه مشرفٌ على درج الكاشير ⇒ **عجزٌ وهميّ** بحجمه.
      final txs =
          await (select(safeTransactions)..where(
                (t) =>
                    t.userId.equals(shift.userId) &
                    t.createdAt.isBetween(
                      Variable(shift.startTime),
                      Variable(endTime),
                    ),
              ))
              .get();

      // Only count transactions that belong to cash-type safes.
      // Bank/visa and click collections are settled electronically — including
      // them in expectedCash inflates it relative to actualCash (physical drawer)
      // and produces a phantom deficit equal to the non-cash collections.
      final cashSafes = await (select(safes)
              ..where((s) => s.safeType.equals('cash')))
          .get();
      final cashSafeIds = {for (final s in cashSafes) s.id};

      // الدرجُ (أو الأدراج) التي تخصّ هذه الوردية: ما لمسَته فعلاً. وإن لم
      // تلمس شيئاً فأدراجُ فرعِها النقدية — وإلا بقيت وردية «بلا حركةٍ خاصة»
      // عمياءَ عن بيعةٍ حصلت على درجها.
      var drawerSafeIds = txs
          .map((t) => t.safeId)
          .where(cashSafeIds.contains)
          .toSet();
      if (drawerSafeIds.isEmpty) {
        drawerSafeIds = {
          for (final s in cashSafes)
            if (shift.branchId == null || s.branchId == shift.branchId) s.id,
        };
      }

      final drawerTxs = drawerSafeIds.isEmpty
          ? <SafeTransactionData>[]
          : await (select(safeTransactions)..where(
                (t) =>
                    t.safeId.isIn(drawerSafeIds) &
                    t.createdAt.isBetween(
                      Variable(shift.startTime),
                      Variable(endTime),
                    ),
              ))
              .get();

      double totalReceipts = 0;
      double totalPayments = 0;

      for (final t in drawerTxs) {
        // صفُّ تسوية الفرق (‏[_postVarianceSafeTransaction]) **تصحيحٌ لعدٍّ
        // سابق** لا حركةَ درجٍ حقيقية، فلا يدخل توقّعَ أيّ وردية. وبدون
        // استثنائه يتسرّب إلى الوردية التالية حين يتلامس وقتُ الإقفال مع وقت
        // الفتح (‏`isBetween` شاملُ الطرفين) فيتضاعف الفرقُ المقيس: مقيس
        // ٢٠ بدل ١٠ في `atomicity_variance_test`.
        if (t.category == 'shift_variance') continue;
        if (t.transactionType == 'receipt') {
          totalReceipts += t.amount;
        } else if (t.transactionType == 'payment') {
          totalPayments += t.amount;
        }
      }

      final expectedCash = shift.openingBalance + totalReceipts - totalPayments;
      final variance = actualCash - expectedCash;

      await (update(shifts)..where((s) => s.id.equals(shift.id))).write(
        ShiftsCompanion(
          endTime: Value(endTime),
          expectedCash: Value(expectedCash),
          actualCash: Value(actualCash),
          variance: Value(variance),
          status: const Value('closing'),
          notes: Value(notes),
          closingMethod: Value(closingMethod),
          // Absent(), not Value(null): a close path that doesn't supply a
          // snapshot must leave any existing one alone rather than erase it.
          closingSnapshot: closingSnapshot == null
              ? const Value.absent()
              : Value(closingSnapshot),
        ),
      );

      // موضعٌ واحدٌ لتعريف الدرج — راجع `domain/models/shift_drawer_resolver.dart`.
      final moved = <int, double>{};
      for (final t in drawerTxs) {
        moved[t.safeId] = (moved[t.safeId] ?? 0) + t.amount.abs();
      }
      final primaryDrawer = resolveShiftDrawer(
        cashSafeIdsInBranch: drawerSafeIds,
        movedBySafeId: moved,
      );

      return _ShiftSettlementResult(
        variance: variance,
        transactions: txs,
        drawerSafeId: primaryDrawer,
      );
    });
  }

  /// H2 · الطرفُ الغائب: فرقُ الوردية كان يُقيَّد في الأستاذ وحدَه (‏دائن
  /// نقدية للعجز) بينما `safes.balance` يبقى كما هو ⇒ حسابُ النقدية والخزنةُ
  /// ينفصلان بمقدار الفرق، **وتتراكم الفجوةُ كلَّ وردية**، ولا أثرَ للفرق في
  /// كشف حركة الخزنة يراه مراجع.
  ///
  /// مقيس: عجزُ ٥٠ ⇒ الأستاذ ينزل ٥٠ والخزنةُ لا تنزل شيئاً.
  ///
  /// يُنادى **خارج** `_settleShift` عمداً: `createSafeTransaction` يفتح
  /// معاملتَه، ودمجُها في معاملةِ التسوية هو نفسُ نمط التعشيش الذي سبّب
  /// SqliteException 517 مع `createJournalEntry` (اقرا الخطوة ٢ في
  /// [closeShiftWithAudit]).
  Future<void> _postVarianceSafeTransaction({
    required int shiftId,
    required int safeId,
    required double variance,
    required DateTime endTime,
    required int userId,
  }) async {
    final safe =
        await (select(safes)..where((s) => s.id.equals(safeId))).getSingleOrNull();
    if (safe == null) return;

    final isShortage = variance < 0;
    final amount = variance.abs();
    await createSafeTransaction(SafeTransactionsCompanion.insert(
      voucherNumber: 'SHV-$shiftId-${safe.id}',
      safeId: safe.id,
      transactionType: isShortage ? 'payment' : 'receipt',
      category: 'shift_variance',
      amount: amount,
      balanceAfter: safe.balance + (isShortage ? -amount : amount),
      referenceType: const Value('shift_close'),
      referenceId: Value(shiftId),
      description: Value(isShortage
          ? 'تسوية عجز إقفال وردية #$shiftId'
          : 'تسوية فائض إقفال وردية #$shiftId'),
      userId: Value(userId),
      createdAt: Value(endTime),
    ));
  }

  /// PIR-06 Step 2: Generate journal entry for cash variance (shortage/surplus)
  ///
  /// PHASE-2 FIX: Exceptions here propagate to the parent closeShift transaction.
  /// A failed GL entry must roll back the entire shift-close to prevent
  /// "shift closed but variance unrecorded" silent data corruption.
  ///
  /// EXCEPTION: Accounts that are not yet configured in the Chart of Accounts
  /// produce a safe warning only — the shift close still completes, which is
  /// the correct business behaviour when no variance accounts are mapped.
  Future<void> _postVarianceJournalEntry({
    required int shiftId,
    required double variance,
    required DateTime endTime,
    required int? drawerSafeId,
  }) async {
    // ── الدرجُ الذي حُسم فعلاً، لا مفتاحُ إعدادات ────────────────────────
    //
    // 🔴 كان هنا `getSetting('pos_cash_safe_id')` ثمّ `?? '1'`. و`_settleShift`
    // قد حسم الدرجَ سلفاً بـ`resolveShiftDrawer` — وهي الدالّةُ التي يقول
    // توثيقُها إنّها «موضعٌ واحدٌ لتعريف الدرج» وإنّها «ستحلّ محلَّها في
    // تسوية فرقِ الوردية» — وكتب حركةَ الفرق على **ذلك** الدرج
    // (`_postVarianceSafeTransaction(safeId: settlementResult.drawerSafeId!)`).
    //
    // فعلى فرعٍ متعدّدِ الأدراج كانت حركةُ الخزنة تقع على الدرج الثالث
    // بينما وصفُ القيد يسمّي الدرجَ الأوّل — ومع توجيه الحساب إلى الدرج
    // كان القيدُ نفسُه سيقع على الخزنة الخطأ. فيُمرَّر الدرجُ المحسوم.
    final primarySafe = drawerSafeId == null
        ? null
        : await (select(safes)..where((s) => s.id.equals(drawerSafeId)))
            .getSingleOrNull();
    final resolvedBranchId = primarySafe?.branchId;

    // ── حسابُ **هذا الدرج** لا حسابُ النقديّة العامّ ──────────────────────
    //
    // العجزُ أو الفائضُ وقع في درجٍ بعينه، وحركةُ الخزنة سُجِّلت عليه. وكان
    // القيدُ يُرحَّل على حساب الغرض العامّ ⇒ رصيدُ الدرج يتحرّك في جدوله
    // وحسابُه في الأستاذ لا يتحرّك، و`1111` يحمل فرقاً لا درجَ يملكه.
    final cashAccount = await resolveSafeGlAccount(primarySafe) ??
        await accountingDao.getLeafAccountByPurpose('cash');
    if (cashAccount == null) {
      throw StateError('لا يمكن إغلاق الوردية: حساب النقدية غير مربوط.');
    }

    // Spec 083 — thread the safe name into JE descriptions so multi-safe
    // installs can tell at a glance WHICH till had the shortage/surplus.
    // Pre-spec, every variance JE read "تعديل نقدية — عجز" with no
    // attribution; in branches with several safes the operator couldn't
    // tell which till the entry belonged to without cross-referencing
    // the shift. `primarySafe` may legitimately be null on legacy installs
    // (settings never seeded) — fall back to the unattributed format.
    final safeName = primarySafe?.name;
    final safeSuffix = safeName != null ? ' — $safeName' : '';

    final lines = <JournalLine>[];
    if (variance < 0) {
      // Shortage: Dr Cash Shortage Expense, Cr Cash
      final shortageAccount = await accountingDao.getAccountByCode(
        await accountingDao.getMappedAccountCode('cash_shortage', AccountingDao.accountPurposes['cash_shortage']!),
      );
      if (shortageAccount == null) {
        throw StateError('لا يمكن إغلاق الوردية: حساب عجز النقدية غير مربوط.');
      }
      lines.add(JournalLine(
        accountId: shortageAccount.id,
        debit: variance.abs(),
        description: 'عجز صندوق — إقفال وردية #$shiftId$safeSuffix',
      ));
      lines.add(JournalLine(
        accountId: cashAccount.id,
        credit: variance.abs(),
        description: 'تعديل نقدية — عجز$safeSuffix',
      ));
    } else {
      // Surplus: Dr Cash, Cr Cash Surplus Revenue
      final surplusAccount = await accountingDao.getAccountByCode(
        await accountingDao.getMappedAccountCode('cash_surplus', AccountingDao.accountPurposes['cash_surplus']!),
      );
      if (surplusAccount == null) {
        throw StateError('لا يمكن إغلاق الوردية: حساب فائض النقدية غير مربوط.');
      }
      lines.add(JournalLine(
        accountId: cashAccount.id,
        debit: variance,
        description: 'فائض نقدية — إقفال وردية #$shiftId$safeSuffix',
      ));
      lines.add(JournalLine(
        accountId: surplusAccount.id,
        credit: variance,
        description: 'فائض صندوق — إقفال وردية$safeSuffix',
      ));
    }

    if (lines.isNotEmpty) {
      // Phase 5A.8 (Issue 2) — derive a deterministic globalId for the
      // variance JE from the shift's own globalId. Both client and server
      // run this same DAO during shift close (server when reconstructing
      // the missing shift, client when closing locally). Without a stable
      // globalId, each side wrote a JE with a random UUID, and the sync
      // pull duplicated the variance entry in the General Ledger. With
      // the deterministic globalId, JournalSyncStrategy's Tier 1 dedup
      // recognises the match and updates instead of inserting.
      //
      // Older shifts (created before openShift started auto-minting a
      // globalId in commit 7900XXX) may not have one. In that legacy
      // case we fall back to null and accept random globalId — those
      // shifts predate the multi-device era and won't dedupe, but won't
      // duplicate within a single device either.
      final shiftRow = await (select(shifts)
            ..where((s) => s.id.equals(shiftId))
            ..limit(1))
          .getSingleOrNull();
      // Spec 129 F5 — canonical schema `je-shiftclose-<shiftGid>-close`.
      // The legacy `je-shift-variance-<shiftGid>` format from Phase 5A.8
      // (Issue 2) served the same dedup goal but didn't follow the F5
      // formula. Existing legacy rows stay in the DB; new posts use the
      // canonical helper. Shifts without a globalId (very old rows) fall
      // back to null and accept random UUID (same behaviour as before).
      final detGlobalId = (shiftRow?.globalId != null && shiftRow!.globalId!.isNotEmpty)
          ? JournalEntryGid.compute(
              sourceType: JournalEntryGid.sourceShiftClose,
              sourceGid: shiftRow.globalId!,
              verb: 'close',
            )
          : null;
      if (detGlobalId != null) {
        unawaited(DiagnosticLogger.log(
          DiagnosticLogger.gidAutopost,
          'sourceType=shiftclose sourceGid=${shiftRow!.globalId!.substring(0, 8)} '
          'verb=close shiftId=$shiftId',
        ));
      }
      // Throws on DB failure → propagates to parent transaction → rollback
      await accountingDao.createJournalEntry(
        description: 'قيد فرق إقفال وردية #$shiftId$safeSuffix',
        date: endTime,
        lines: lines,
        referenceType: 'shift_close',
        referenceId: shiftId,
        isAutoPosted: true,
        branchId: resolvedBranchId,
        globalId: detGlobalId,
      );
    }
  }
}
