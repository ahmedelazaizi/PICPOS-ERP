part of '../database.dart';

/// Shift close step 3: zero out all safes touched during the shift.
extension TreasuryShiftCloseSafesDao on AppDatabase {
  /// PIR-06 Step 3: Zero out all safes used during the shift
  /// FIX: Removed duplicate zeroing (previously safes were zeroed BOTH inline AND via closeSafe)
  Future<void> _closeShiftSafes({
    required Shift shift,
    required List<SafeTransactionData> transactions,
    required int shiftId,
    required DateTime endTime,
  }) async {
    // Spec 136 ISS-8 — PER-SHIFT drain (supersedes Spec 107 "Full Drain").
    //
    // Field report: closing one user's shift drained the ENTIRE cumulative
    // safe balance — including cash earned by OTHER users' still-open shifts
    // and residuals from previously-unclosed shifts (the old code swept every
    // active branch safe and zeroed each one). The operator wants the close to
    // settle ONLY the closing user's current shift and leave every other
    // shift's money in the till.
    //
    // `transactions` is already scoped to (userId == shift.userId, createdAt
    // in [shift.startTime, endTime]) by _settleShift, so the NET movement this
    // shift made into each safe is exactly:
    //     sum(receipts) - sum(payments | withdrawals)   per safeId.
    // We transfer only that net to HQ and leave the remaining balance (the
    // opening float — openShift never posts it as a safe txn — plus any other
    // shift's contributions) untouched. Only safes THIS shift actually moved
    // cash in/out of are processed; sister/other-branch safes and untouched
    // tills are never swept.
    final netBySafe = <int, double>{};
    for (final t in transactions) {
      final type = t.transactionType;
      final double delta;
      if (type == 'receipt') {
        delta = t.amount;
      } else if (type == 'payment' || type == 'withdrawal') {
        delta = -t.amount;
      } else {
        // memo / transfer / other — no physical till movement to drain.
        continue;
      }
      netBySafe[t.safeId] = (netBySafe[t.safeId] ?? 0) + delta;
    }

    for (final sId in netBySafe.keys) {
      final safe = await (select(safes)..where((s) => s.id.equals(sId))).getSingleOrNull();
      if (safe == null) continue;

      // Feature 011 / Issue NEG-BAL — idempotency on (safe, shift).
      //
      // Real-world incident from a beta restaurant: every shift close was
      // producing TWO `shift_closing` rows per safe — a `ZRO…` from this
      // method and a `PMT-X` from postSafeTransaction (the client also
      // submits each safe transaction individually via
      // /api/safes/transaction). When `/api/shifts/close` reached the
      // server BEFORE the matching `/api/safes/transaction`, the order
      // on the server was:
      //   1. _closeShiftSafes inserted ZRO and absolute-set balance to 0
      //   2. postSafeTransaction then read balance=0, applied -amount,
      //      and stored the new row with balanceAfter = -amount
      // → safe balances on the server's "إدارة الخزينة" screen showed
      // NEGATIVE amounts even though no real disbursement happened
      // (e.g. صندوق فيزا الإدارة: -12.500, صندوق فيزا مطعم معان: -33.000).
      //
      // Fix: skip this safe entirely if a `shift_closing` transaction
      // for THIS exact (shiftId, safeId) pair already exists. Robust
      // regardless of which API call arrives first; standalone mode is
      // unaffected (no prior row → no skip).
      final alreadyClosed = await (select(safeTransactions)
            ..where((t) =>
                t.safeId.equals(sId) &
                t.referenceType.equals('shift_closing') &
                t.referenceId.equals(shiftId))
            ..limit(1))
          .getSingleOrNull();
      if (alreadyClosed != null) {
        debugPrint('[TreasuryDao] _closeShiftSafes: safe #$sId already has '
            'a shift_closing transaction for shift #$shiftId — skipping '
            '(prevents duplicate ZRO + PMT pair driving balance negative).');
        continue;
      }

      // Spec 107 — Model A (Full Drain): transfer the full safe balance to
      // HQ at every shift close. Branch safes are daily operational tills,
      // NOT inter-shift carry containers; their natural end-of-shift state
      // is zero. Any value sitting in the safe — whether it came from this
      // shift's sales, a manual receipt voucher posted earlier, or leftover
      // from a previously-broken close — belongs in HQ (cash → main safe,
      // bank → checking account, click → click clearing).
      //
      // Variance attribution to the cashier is handled SEPARATELY by
      // `_settleShift` (Spec 104) which scopes its expectation calc to the
      // shift period in cash safes only. So a manual receipt of 50 added
      // before the shift does NOT inflate `expectedCash` (Spec 104 fix)
      // but IS drained at close (this Spec 107 rule) — the two concerns
      // are intentionally decoupled.
      //
      // Supersedes Spec 106 US1 (Model B / shift-delta-only) after model
      // discussion 2026-05-20.
      // Spec 136 ISS-8 — drain only THIS shift's net contribution to the
      // safe, not the full cumulative balance. A net <= 0 (more cash paid out
      // than taken in during the shift, rare for a till) drains nothing — the
      // variance JE handles any discrepancy; we never push another shift's
      // balance out.
      final balanceToZero = netBySafe[sId] ?? 0;
      if (balanceToZero > 0.001) {
        // Spec 136 item 7 — clamp the drain to what's physically in the till
        // so a shift whose tracked net exceeds the actual balance (untracked
        // cash-out / shortage) never pushes the safe negative. The undrained
        // remainder is a shortage the variance settlement (_settleShift,
        // Spec 104) already attributes against expected-vs-actual cash, so we
        // do NOT post a second variance JE here (double-count); we cap the
        // physical transfer and surface the gap via SHIFT-DRAIN-CLAMP.
        // Normal case (net <= balance): actualDrain == balanceToZero →
        // byte-identical behaviour.
        final actualDrain = balanceToZero > safe.balance
            ? (safe.balance > 0 ? safe.balance : 0.0)
            : balanceToZero;
        final drainShortfall = balanceToZero - actualDrain;
        if (drainShortfall > 0.001) {
          unawaited(DiagnosticLogger.log(
              'SHIFT-DRAIN-CLAMP',
              'shift #$shiftId safe #$sId: tracked net '
              '${balanceToZero.toStringAsFixed(3)} exceeds till balance '
              '${safe.balance.toStringAsFixed(3)} — drained '
              '${actualDrain.toStringAsFixed(3)}, shortfall '
              '${drainShortfall.toStringAsFixed(3)} left for variance '
              'settlement (safe not pushed negative).'));
        }
        final voucherNo = 'ZRO${DateTime.now().millisecondsSinceEpoch}$sId';

        // Feature 041 / Route B.1 — deterministic UUIDv5 for the shift_closing
        // row's globalId, keyed on (shift.globalId, safe.globalId). Both the
        // CLIENT's _closeShiftSafes and the SERVER's _closeShiftSafes (now
        // reliably invoked end-to-end after Feature 035) derive THE SAME
        // value without any coordination, so the cross-side race that drove
        // v122 NEG-BAL is resolved at the data layer:
        //   - safe_transactions.globalId is UNIQUE → second cross-instance
        //     insert can never collide via DeltaPull.
        //   - The layered pre-check below catches the duplicate locally so
        //     the safe's balance is not zeroed a second time (which would
        //     otherwise post a withdrawal of -|balance| → negative drift).
        //
        // Legacy shift rows pre-v119 may have null globalId. In that case
        // mint a fresh UuidV7 (current behavior preserved). Same for safes
        // whose globalId was never populated by an earlier migration —
        // both are extremely rare in practice (master-data sync seeds them
        // at first paired connect) but the fallback keeps the close path
        // alive instead of crashing on `!`.
        final shiftGid = shift.globalId;
        // Spec 136 (field 2026-06-14): the per-safe close dedup key MUST be
        // identical on mirror and server. safe.globalId is NOT — safes are
        // created independently per device (the mirror's first sync pulls
        // safes=0 and seeds its own), so each side derived a different
        // zeroOutGlobalId → the globalId dedup below missed → duplicate
        // "إقفال وردية" JEs (field-observed on the supermarket cash safe; the
        // restaurant safe happened to match). Derive the key from the safe's
        // LINKED ACCOUNT CODE (shared, synced chart of accounts) + the safe
        // name — both are cross-device-stable business identifiers. Fall back
        // to safe.globalId only when the safe has no linked account.
        String? safeStableKey;
        if (safe.linkedAccountId != null) {
          final linkedAcc =
              await accountingDao.getAccountById(safe.linkedAccountId!);
          if (linkedAcc != null && linkedAcc.code.isNotEmpty) {
            safeStableKey = 'acct:${linkedAcc.code}:${safe.name}';
          }
        }
        safeStableKey ??= safe.globalId;
        final String zeroOutGlobalId;
        if (shiftGid != null &&
            shiftGid.isNotEmpty &&
            safeStableKey != null &&
            safeStableKey.isNotEmpty) {
          zeroOutGlobalId = UuidV7.deriveShiftClosingGlobalId(
            shiftGlobalId: shiftGid,
            safeGlobalId: safeStableKey,
          );

          // Defense in depth — alongside the (safeId, refType, refId) check
          // above, also dedup by deterministic globalId. This catches the
          // exact field race that v122 surfaced: the "other side" already
          // wrote the row with a different referenceId (its own local
          // shift id), bypassing the legacy check, but the globalId is
          // identical so we skip cleanly without driving balance negative.
          final existingByGlobalId = await (select(safeTransactions)
                ..where((t) => t.globalId.equals(zeroOutGlobalId))
                ..limit(1))
              .getSingleOrNull();
          if (existingByGlobalId != null) {
            debugPrint('[TreasuryDao] _closeShiftSafes: shift_closing '
                'globalId=$zeroOutGlobalId already present for safe #$sId '
                '(refId=${existingByGlobalId.referenceId}); skipping insert '
                'to prevent NEG-BAL drift (Feature 041 layered dedup).');
            // Important — the safe balance has already been zeroed by the
            // "other side"'s parallel run, so do NOT also rewrite it to 0
            // (that would no-op anyway) and do NOT post another JE.
            continue;
          }
        } else {
          // Spec 007 / FR-011 / T019.B legacy path: mint UuidV7 fresh when
          // either side's master globalId is missing. Mirror DeltaPull dedup
          // still falls back to (refType, refId, partyId) tier matching.
          unawaited(DiagnosticLogger.log(
              'SHIFT-CLOSE-WARN',
              'وردية=$shiftId صندوق=$sId مفتاح إقفال غير ثابت '
              '(shiftGid=$shiftGid, safeKey=$safeStableKey) — استُخدم globalId '
              'عشوائي؛ إزالة التكرار عبر الأجهزة قد تفشل (راقب تكرار قيد إقفال '
              'الوردية). اربط هذا الصندوق بحساب في دليل الحسابات لمنع ذلك.'));
          zeroOutGlobalId = UuidV7.generate();
        }

        // ── الطرفُ المستقبِل يُحسم **قبل** السحب ──────────────────────────
        //
        // §٥-١ (بلاغٌ ميدانيّ 2026-08-11): كان السحبُ غيرَ مشروطٍ والاستلامُ
        // بعده «أفضلَ جهد» داخل `try` يكتفي بالتسجيل حين لا يجد مستقبِلاً.
        // فأيُّ حالةٍ بلا مستقبِلٍ تحوّل **التحويلَ** إلى **اختفاء**:
        // `[SHIFT-CLOSE-NO-CENTRAL] safeId=1 amount=140.0` — ٤٦٠ خرجت من ثلاث
        // خزائن ولم تستقبلها خزينة. والحارسُ كان يسجّل ولا يمنع.
        //
        // وثلاثةُ طرقٍ مقيسةٍ تبلغ تلك الحالة، كلُّها بنفس النتيجة:
        //   ١. قاعدةٌ أُنشئت قبل دخول الصندوق المركزي في البذرة —
        //      `seedInitialData` لا تعمل إلا على قاعدةٍ جديدة أو بلا
        //      مستخدمين، ولا إصلاحَ إقلاعٍ يزرعه.
        //   ٢. حذفُه من شاشة إدارة الصناديق على تنصيبٍ **جديد**: حارسُ
        //      `deleteSafeById` يشترط `isDefault == false`، والمركزيُّ
        //      `isDefault: false` قصداً؛ وحارسُ القيود لا يعترض لأن تحويلات
        //      الإقفال لا تُنشئ قيداً، فحسابُه يبقى بلا بنود.
        //   ٣. أن تعمل الورديةُ على المركزيّ نفسِه: سطرُ الاستلام ممنوعٌ عن
        //      النفس (‏صواب) والسحبُ فوقه لم يكن مشروطاً (‏خطأ).
        //
        // فالقاعدةُ الآن واحدة: **تحويلٌ بلا طرفٍ مقابلٍ ليس تحويلاً**. لا
        // يُكتب سطرُ سحبٍ ولا يُخصم رصيدٌ ولا يُرحَّل قيدٌ ما لم يوجد مستقبِلٌ
        // مغايرٌ للمصدر. والمالُ يبقى في الدرج — وهو الصدق: لم يستلمه أحد.
        final central = await getCentralSafe();
        if (central == null) {
          unawaited(DiagnosticLogger.log(
            'SHIFT-CLOSE-NO-CENTRAL',
            'safeId=$sId amount=$actualDrain — الصندوق الرئيسي مش موجود، '
                'التسليم اتوقف والفلوس فضلت في الدرج. اعمل خزينة اسمها '
                '"$kCentralSafeName" من شاشة إدارة الصناديق.',
          ));
          continue;
        }
        if (central.id == sId) {
          // الورديةُ على المركزيّ نفسِه: طرفا التحويل واحدٌ فحركتُه صفر.
          continue;
        }

        // Spec 136 ISS-8 (supersedes Spec 107 Model A): balanceAfter is the
        // safe's REMAINING balance after draining only this shift's net — NOT
        // zero, because other shifts' contributions and the opening float stay
        // in the till.
        final balanceAfterDrain = safe.balance - actualDrain;
        final shiftClosingTxnId = await into(safeTransactions).insert(
          SafeTransactionsCompanion.insert(
            voucherNumber: voucherNo,
            safeId: sId,
            transactionType: 'withdrawal',
            category: 'shift_closing',
            amount: actualDrain,
            balanceAfter: balanceAfterDrain,
            description: Value(
                'إقفال وردية #$shiftId — تحويل حصة الوردية من ${safe.name} إلى الإدارة'),
            createdAt: Value(endTime),
            userId: Value(shift.userId),
            referenceType: const Value('shift_closing'),
            referenceId: Value(shiftId),
            globalId: Value(zeroOutGlobalId),
          ),
        );

        // Spec 107 (Model A): drain the full balance atomically. Uses the
        // Spec 069 atomic helper to avoid the read-then-write race that an
        // absolute `SET balance = 0` would expose if another transaction
        // touched this safe between our read and our write.
        await adjustSafeBalance(sId, -actualDrain);

        // ── الطرف المستقبِل: الصندوق الرئيسي (الإدارة المركزية) ────────────
        //
        // السحب فوق كان بيتم **بلا خزينة مستقبِلة**، فمجموع أرصدة الخزائن
        // بيقلّ كل وردية وينحرف عن حساب النقدية في الأستاذ — واللي بيفضل صح
        // لأن النقدية اتقيّدت على ١١١١ من ساعة البيع. وصف سطر السحب نفسه
        // بيقول «تحويل حصة الوردية إلى الإدارة»: النية كانت موجودة والطرف
        // ده هو اللي كان ناقص.
        //
        // مفيش قيد يومية هنا **عن قصد**: الخزنتين بيقعوا على نفس حساب
        // النقدية، فالحركة داخل نفس الحساب ومفيش حاجة تتحرك في الأستاذ. قيد
        // بصفر كان بيدّي إحساس كاذب إن فيه ترحيل حصل.
        // المستقبِلُ محسومٌ فوق (‏موجودٌ ومغايرٌ للمصدر)، فهذا السطرُ ليس
        // «أفضلَ جهد»: فشلُه يعني سحباً بلا استلام — وهو عينُ العطب. فيُترك
        // بلا `try` كي تُسقط أيُّ إخفاقةٍ معاملةَ الإقفال كلَّها بدل أن
        // تُخلّف مالاً مسحوباً لا يملكه أحد.
        await into(safeTransactions).insert(
          SafeTransactionsCompanion.insert(
            voucherNumber: voucherNo,
            safeId: central.id,
            transactionType: 'receipt',
            category: 'shift_closing',
            amount: actualDrain,
            balanceAfter: central.balance + actualDrain,
            description:
                Value('إقفال وردية #$shiftId — استلام حصة ${safe.name}'),
            createdAt: Value(endTime),
            userId: Value(shift.userId),
            referenceType: const Value('shift_closing'),
            referenceId: Value(shiftId),
            globalId: Value('$zeroOutGlobalId-central'),
          ),
        );
        await adjustSafeBalance(central.id, actualDrain);

        // Post a GL journal entry for this safe's shift-close transfer.
        // Credit: the safe's own linked GL account.
        // Debit:  the CENTRAL safe's GL account — the money's real destination.
        //
        // ── ولا `try/catch` هنا بعد اليوم ────────────────────────────────
        //
        // 🔴 كان الكلُّ ملفوفاً بـ`try { … } catch (e) { debugPrint }`،
        // والسحبُ (`adjustSafeBalance(sId, -actualDrain)`) والاستلامُ
        // (`adjustSafeBalance(central.id, actualDrain)`) قد نُفِّذا **قبله**.
        // فأيُّ رفضٍ للقيد — فترةٌ مقفلة، حسابٌ غيرُ قابلٍ للترحيل، خزنةٌ
        // مربوطةٌ بحسابٍ أبٍ — كان يصير سطرَ تشخيصٍ بينما النقدُ انتقل بلا
        // أيِّ أثرٍ في الأستاذ. و`closeSafe` أزال هذا الابتلاعَ بعينه؛ هذا
        // المسارُ لم يُعالَج معه.
        //
        // والرميُ يُرجع المعاملةَ كلَّها: لا سحبَ ولا استلامَ ولا صفَّ إقفال
        // — الوردية تبقى مفتوحةً برسالةٍ صريحةٍ بدل دفاترَ متضاربة.
        {
          // ── الطرفان خزنتان، فلكلٍّ حسابُه ───────────────────────────────
          //
          // المصدرُ كان صحيحاً منذ البداية (‏حسابُ الخزنة المرتبط)، أمّا
          // **الوجهةُ** فكانت حسابَ الغرض العامّ بينما المالُ يصل إلى
          // **الخزنة المركزيّة** فعلاً (`adjustSafeBalance(central.id, …)`
          // أعلاه). فحسابُ المركزيّة يبقى صفراً إلى الأبد، و`1111` يحمل
          // مديناً لا خزنةَ تملكه.
          //
          // ⚠️ **ولا يُمرَّر نفسُ الوسيط للطرفَين.** لو حُلَّ الاثنان من
          // `safe` لصار القيدُ `Dr X / Cr X` — يتصفّى إلى صفرٍ ويصير
          // السحبُ غيرَ مرئيٍّ في الأستاذ أصلاً. أي أن نحوّل انفصالاً إلى
          // اختفاء.
          final sourceAccount = await requireSafeGlAccount(safe,
              op: 'إقفال وردية #$shiftId');
          final destAccount = await requireSafeGlAccount(central,
              op: 'استلام إقفال وردية #$shiftId');

          // خزنتان تشتركان في نفس الحساب (‏كلتاهما بلا رابطٍ فتسقطان إلى
          // حساب الغرض) تُنتجان قيداً يُلغي نفسَه. لا يُرحَّل — نفسُ الحارس
          // الموجود في `closeSafe`.
          if (sourceAccount.id != destAccount.id) {
            // Spec 135 BUG-F — deterministic globalId for the shift-close
            // transfer JE. Previously this createJournalEntry omitted
            // globalId, so it fell back to a random UuidV7 (see
            // accounting_dao_writes.dart:30), and `referenceId` was the
            // LOCAL autoincrement `shiftClosingTxnId` (different on client
            // vs server). Neither the globalId UNIQUE constraint nor the
            // (referenceType, referenceId) dedup could match across
            // instances → the client JE AND the server JE both survived
            // DeltaPull → duplicate "تحويل رصيد صندوق" entries on the
            // server (field-observed JE-2026-00284/285/286).
            //
            // Fix mirrors the variance JE (this file, ~line 567): derive
            // a canonical `je-shiftclose-<sourceGid>-transfer` from the
            // already-deterministic `zeroOutGlobalId` (itself keyed on the
            // shift+safe globalIds via deriveShiftClosingGlobalId). One
            // transfer JE per (shift, safe); client and server converge on
            // the same id; the UNIQUE constraint catches the duplicate at
            // INSERT. Legacy rows whose shift/safe globalId was missing
            // already fell back to a random zeroOutGlobalId above, so this
            // derives a (still-unique-per-side) value for them — same
            // degraded-dedup behaviour as before for those rare rows.
            final transferJeGid = JournalEntryGid.compute(
              sourceType: JournalEntryGid.sourceShiftClose,
              sourceGid: zeroOutGlobalId,
              verb: 'transfer',
            );
            unawaited(DiagnosticLogger.log(
              DiagnosticLogger.gidAutopost,
              'sourceType=shiftclose sourceGid=${zeroOutGlobalId.length >= 8 ? zeroOutGlobalId.substring(0, 8) : zeroOutGlobalId} '
              'verb=transfer shiftId=$shiftId safeId=$sId',
            ));
            await accountingDao.createJournalEntry(
              description: 'إقفال وردية #$shiftId — ${safe.name} ($voucherNo)',
              date: endTime,
              lines: [
                JournalLine(
                  accountId: destAccount.id,
                  debit: actualDrain,
                  description: 'إقفال وردية — تحويل رصيد ${safe.name}',
                ),
                JournalLine(
                  accountId: sourceAccount.id,
                  credit: actualDrain,
                  description: 'إقفال وردية — ${safe.name}',
                ),
              ],
              referenceType: 'shift_closing',
              referenceId: shiftClosingTxnId, // unique per safe per shift
              isAutoPosted: true,
              branchId: safe.branchId,
              globalId: transferJeGid,
            );
          }
        }

        // 2026-05-12 NEG-BAL hotfix (Feature 035 v123) — DO NOT mirror this
        // shift_closing safe_txn from CLIENT. The server-side `_closeShiftSafes`
        // (now invoked reliably by the v119 globalId fix at /api/shifts/close)
        // already creates the SAME row server-side with `referenceId =
        // SERVER's shift id`. The client mirror used `referenceId = CLIENT's
        // local shift id`, which bypassed the
        // `(safeId, referenceType, referenceId)` idempotency check at
        // line 622, producing TWO `shift_closing` rows per (safe, shift) on
        // the server → safes.balance drifted negative → next shift's close JE
        // emitted negative debit/credit values (field-observed JE-2026-00063).
        //
        // Tactical fix: skip the mirror when running in CLIENT/MIRROR mode.
        // The /api/shifts/close handler is the single source of truth for the
        // server-side shift_closing row (Constitution R4). Standalone-mode
        // calls fall through (SyncInterceptor.isClientMode is false but
        // .instance is null too, so the call no-ops naturally).
        //
        // Permanent fix tracked in `specs/041-shift-closing-globalid-dedup/`
        // (Route B.1 — deterministic UUIDv5 keyed on shift+safe globalIds —
        // makes both paths converge on the same safe-txn globalId so the
        // existing globalId UNIQUE constraint catches the duplicate). Until
        // 041 ships, this skip is the bleeding-edge stop.
        if (!SyncInterceptor.isClientMode) {
          try {
            await SyncInterceptor.instance?.submitSafeTransaction(
              safeId: sId,
              transactionType: 'withdrawal',
              amount: actualDrain,
              category: 'shift_closing',
              description: 'تصفير رصيد الخزينة عند إغلاق الوردية #$shiftId',
              userId: shift.userId,
              referenceType: 'shift_closing',
              referenceId: shiftId,
              // Spec 007 / FR-011 / T019.B: thread the zero-out's locally-minted
              // globalId so server stores the row under the same UUID as the
              // local insert above. Prevents mirror duplicate after DeltaPull.
              globalId: zeroOutGlobalId,
            );
          } catch (e) {
            debugPrint('[TreasuryDao] Failed to sync zero-out: $e');
          }
        } else {
          debugPrint('[TreasuryDao] _closeShiftSafes: skipping client mirror '
              'of shift_closing safe_txn for safe #$sId — server\'s '
              '/api/shifts/close handler is the single source of truth '
              '(NEG-BAL hotfix v123, see specs/041).');
        }
      } else {
        // Spec 136 item 6 — breadcrumb so a no-op shift-close drain is
        // visible instead of silently skipped: this safe carried no net
        // balance from this shift (opening float + other shifts'
        // contributions intentionally stay in the till — Spec 136 ISS-8).
        unawaited(DiagnosticLogger.log(
            'SHIFT-DRAIN-SKIP',
            'shift #$shiftId safe #$sId: net shift balance '
            '${balanceToZero.toStringAsFixed(3)} ≤ 0.001 — no shift-close '
            'drain posted (nothing to transfer to admin).'));
      }
    }
  }
}
