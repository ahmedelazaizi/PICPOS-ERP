part of '../database.dart';

/// Safe-transaction watchers and closeSafe.
extension TreasuryTransactionsDao on AppDatabase {
  // ═══════════════════════════════════════════════════════════════════════
  // TRANSACTION OPERATIONS
  // ═══════════════════════════════════════════════════════════════════════

  /// Watch transactions for a date range
  Stream<List<SafeTransactionData>> watchTransactions({
    DateTime? from,
    DateTime? to,
  }) {
    from ??= DateTime.now().subtract(const Duration(days: 30));
    to ??= DateTime.now().add(const Duration(days: 1));

    return (select(safeTransactions)
          ..where((t) => t.createdAt.isBetween(Variable(from!), Variable(to!)))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .watch();
  }

  /// سجلُّ السندات لاتّجاهٍ واحد — ما تعرضه شاشةُ السجلّ (خ‑٩).
  ///
  /// ═══ 🔴 سندُ الشيك ليس نوعَه، فلا يكفي `transaction_type` ═══
  ///
  /// السندُ النقديُّ يكتب `'receipt'`/`'payment'`. أمّا سندُ الشيك فيكتب
  /// [kChequeVoucherTxnType] لأنّ `treasury_repository_impl` يمرّر
  /// `skipSafeTransaction: true` للشيك — فالصفُّ الوحيدُ الخارجُ هو صفُّ
  /// المستند. وترشيحٌ بالنوع وحدَه **يُخفي كلَّ سندات الشيكات** من سجلّها.
  ///
  /// والفاصلُ بين اتّجاهَي سند الشيك **بادئةُ رقمه** (`RV`/`PV`): يكتبها
  /// [_writeChequeVoucherRow] بيده، بخلاف `category` الذي يمرّره كلُّ منادٍ
  /// كما يشاء.
  ///
  /// ⚠️ **ولا تُبنى على [watchTransactions]**: تلك لا ترشّح `deleted_at`
  ///    إطلاقاً (بخلاف [watchRecentTransactions] بجوارها) ولا تعرف الفروع،
  ///    فسجلٌّ عليها يعرض سنداً محذوفاً وسنداتِ فروعٍ أخرى.
  ///
  /// و`branchIds` هي مجموعةُ `branchScopeProvider`: `null` = وصولٌ كامل.
  /// وخزنةٌ بلا فرعٍ تبقى ظاهرةً — نفسُ عقد
  /// [watchRecentTransactionsForBranches]: صفوفُ ما قبل ١٣٣ بلا فرع.
  Stream<List<VoucherRecord>> watchVoucherRecords({
    required VoucherDirection direction,
    DateTime? from,
    DateTime? to,
    Set<int>? branchIds,
    String? search,
    int limit = 500,
  }) {
    final party = alias(parties, 'p');
    final query = select(safeTransactions).join([
      innerJoin(safes, safes.id.equalsExp(safeTransactions.safeId)),
      leftOuterJoin(party, party.id.equalsExp(safeTransactions.partyId)),
    ]);

    // 🔴 النقديُّ بنوعه، وسندُ الشيك بنوعه الثالث **وبادئةِ رقمه**.
    // E2 — سندُ التحويل المحاسبيّ بنوعه المستقلّ (لا حركةَ خزنة).
    final isCash = safeTransactions.transactionType
        .isIn([direction.txnType, direction.transferTxnType]);
    final isCheque =
        safeTransactions.transactionType.equals(kChequeVoucherTxnType) &
            safeTransactions.voucherNumber.like('${direction.chequePrefix}%');
    var where = safeTransactions.deletedAt.isNull() & (isCash | isCheque);

    if (from != null && to != null) {
      where = where &
          safeTransactions.createdAt.isBetweenValues(from, to);
    } else if (from != null) {
      where = where & safeTransactions.createdAt.isBiggerOrEqualValue(from);
    } else if (to != null) {
      where = where & safeTransactions.createdAt.isSmallerOrEqualValue(to);
    }

    if (branchIds != null) {
      where = where & (safes.branchId.isIn(branchIds) | safes.branchId.isNull());
    }

    final needle = search?.trim() ?? '';
    if (needle.isNotEmpty) {
      final like = '%$needle%';
      where = where &
          (safeTransactions.voucherNumber.like(like) |
              safeTransactions.description.like(like) |
              party.name.like(like));
    }

    query
      ..where(where)
      // ⚠️ و`id` فاصلٌ حاسمٌ بعد اللحظة: ساعةُ ويندوز ~١٥ms، فصفّان في
      //    نفس الثانية يتقافزان بين إعادتَي بناءٍ بلا هذا.
      ..orderBy([
        OrderingTerm.desc(safeTransactions.createdAt),
        OrderingTerm.desc(safeTransactions.id),
      ])
      ..limit(limit);

    return query.watch().map((rows) => [
          for (final row in rows)
            () {
              final t = row.readTable(safeTransactions);
              return VoucherRecord(
                id: t.id,
                voucherNumber: t.voucherNumber,
                date: t.createdAt,
                amount: t.amount,
                discount: t.discount,
                category: t.category,
                isCheque: t.transactionType == kChequeVoucherTxnType,
                isAccountTransfer:
                    t.transactionType == direction.transferTxnType,
                safeId: t.safeId,
                safeName: row.readTableOrNull(safes)?.name,
                partyId: t.partyId,
                partyName: row.readTableOrNull(party)?.name,
                description: t.description,
              );
            }(),
        ]);
  }

  /// Watch recent transactions (limited to 50)
  Stream<List<SafeTransactionData>> watchRecentTransactions() {
    return (select(safeTransactions)
          ..where((t) => t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
          ..limit(50))
        .watch();
  }

  /// Issue 14 — branch-scoped variant of [watchRecentTransactions].
  ///
  /// `branchIds` is the set returned by `branchScopeProvider`:
  ///   • `null` → full access (admin / financial manager) — same behaviour
  ///     as [watchRecentTransactions], no branch filter.
  ///   • non-null → restrict rows to safe_transactions whose `safeId`
  ///     belongs to a safe linked to one of those branches. Safes with a
  ///     null `branchId` are intentionally included so legacy unscoped
  ///     vouchers (e.g. seed data, pre-v133 rows) don't disappear from
  ///     restricted users' lists.
  ///
  /// Implementation note: a JOIN-based stream keeps the watcher tied to
  /// both tables so the list updates when either a transaction or a
  /// safe's branch changes (e.g. admin moves a safe between branches).
  Stream<List<SafeTransactionData>> watchRecentTransactionsForBranches(
    Set<int>? branchIds,
  ) {
    if (branchIds == null) return watchRecentTransactions();

    final query = select(safeTransactions).join([
      innerJoin(safes, safes.id.equalsExp(safeTransactions.safeId)),
    ])
      ..where(safeTransactions.deletedAt.isNull() &
          (safes.branchId.isIn(branchIds) | safes.branchId.isNull()))
      ..orderBy([OrderingTerm.desc(safeTransactions.createdAt)])
      ..limit(50);
    return query
        .watch()
        .map((rows) => rows.map((r) => r.readTable(safeTransactions)).toList());
  }

  Future<void> closeSafe(int safeId, {int? userId, double? cashAmount, double? bankAmount, String? notes, String? closeEventGid}) async {
    await transaction(() async {
      final safe = await (select(
        safes,
      )..where((s) => s.id.equals(safeId))).getSingleOrNull();
      if (safe == null) throw Exception('Safe not found');

      // Spec 135 — close-safe idempotency guard. The close is a dual-write
      // (local DAO + server postCloseSafe) and can be re-delivered (outbox
      // retry). When the caller minted a closeEventGid, skip if a closing
      // safe_transaction already carries it — this one logical close has
      // already been processed on this instance. (The currentBalance<=0
      // early-return below is the same-instance safety net; this guard also
      // covers the rare case where new activity pushed the balance back up
      // between a partial delivery and its retry.)
      if (closeEventGid != null && closeEventGid.isNotEmpty) {
        final already = await (select(safeTransactions)
              ..where((t) => t.globalId.equals(closeEventGid))
              ..limit(1))
            .getSingleOrNull();
        if (already != null) {
          debugPrint('[CLOSE-SAFE] event $closeEventGid already processed '
              '(txn #${already.id}) — skipping duplicate close for safe #$safeId');
          return;
        }
      }

      final currentBalance = safe.balance;
      if (currentBalance <= 0) return; // Already zeroed

      // ── الطرفُ المستقبِل ومرجعُ الحساب: يُحسمان **قبل** أيّ تعديل ──────────
      //
      // كان الإقفالُ اليوميّ يصفّي الدرجَ بلا خزينةٍ مستقبِلة، تماماً كالعطب
      // الذي أُصلح في `_closeShiftSafes` (اقرأ التعليق عند `:923`) — والإصلاح
      // لم يُنقَل إلى هنا. النتيجةُ مقيسة: قبل الإقفال Σالخزائن=١٠٠ والأستاذ
      // ١٠٠، وبعده Σالخزائن=**صفر** والأستاذ ١٠٠ ⇒ فجوةٌ دائمةٌ تتراكم كلَّ يوم.
      //
      // وكان `if (sourceAccount == null …) return;` أسفلَه **داخل** الـ`try`
      // وبعد التصفير، فيخرج من ردّ النداء كلِّه ويثبّت التصفيرَ **بلا أيّ قيد**.
      // لذلك يُحسم كلُّ شيءٍ هنا قبل أن يُمَسّ رصيد.
      final central = await getCentralSafe();
      if (central == null) {
        throw StateError(
            'الإقفال اليومي متوقّف: الصندوق الرئيسي غيرُ موجود، فلا خزينةَ '
            'تستقبل رصيدَ «${safe.name}». صفَّرَ الإقفالُ الدرجَ قبل هذا '
            'الإصلاح بلا طرفٍ مقابل، فتختفي النقديةُ من الخزائن ويبقى الأستاذُ '
            'كما هو. اِزرع الصندوقَ الرئيسي ثم أعِد الإقفال.');
      }
      if (central.id == safeId) {
        throw StateError(
            'الإقفال اليومي متوقّف: «${safe.name}» هو الصندوقُ الرئيسي نفسُه، '
            'والتحويلُ إلى الذات سطرُ استلامٍ وهميٌّ ورصيدٌ لا يتصفّى.');
      }

      // نفسُ الترتيب السابق حرفاً بحرف، لكن عبر الدالّة المشتركة — ومعها
      // حارسُ «الحسابُ المرتبطُ يجب أن يكون أصلاً» وحلُّ الحساب الورقيِّ
      // إلى ورقةٍ قابلةٍ للترحيل.
      final Account? sourceAccount = await resolveSafeGlAccount(safe);
      if (sourceAccount == null) {
        throw StateError(
            'الإقفال اليومي متوقّف: لا حسابَ دفتريّاً لـ«${safe.name}» ولا '
            'حسابَ غرضٍ (${safe.safeType == 'bank' ? 'bank' : 'cash'}). '
            'الإقفالُ بلا قيدٍ يترك النقديةَ خارجَ الأستاذ.');
      }

      final voucherNumber = await generateInvoiceNumber('CLO');
      final description = 'إقفال يومي — كاش: ${cashAmount ?? 0} | بنك: ${bankAmount ?? 0} | ملاحظات: ${notes ?? ''}';

      // Create a 'withdrawal' type transaction to zero out the balance.
      // Spec 135: stamp the caller-minted event gid so a re-delivered close
      // is caught by the idempotency guard above, and so the closing txn has
      // a stable cross-instance identity.
      final closingTxnId = await into(safeTransactions).insert(
        SafeTransactionsCompanion.insert(
          voucherNumber: voucherNumber,
          safeId: safeId,
          transactionType: 'withdrawal',
          category: 'closing',
          amount: currentBalance,
          balanceAfter: 0,
          description: Value(description),
          userId: Value(userId),
          createdAt: Value(DateTime.now()),
          globalId: Value(closeEventGid),
        ),
      );

      // تصفيرٌ **نسبيّ** لا مطلق: `updateSafeBalance(safeId, 0)` كتابةٌ مطلقة
      // تمحو أيَّ حركةٍ دخلت بين قراءتنا وكتابتنا (سباقُ read-then-write الذي
      // يوثّقه هذا الملفُّ نفسُه عند `:1277`).
      await adjustSafeBalance(safeId, -currentBalance);

      // ── الطرفُ المستقبِل — الصندوقُ الرئيسي ────────────────────────────────
      // بلا هذا السطر تنقص Σ أرصدة الخزائن بمقدار الإقفال كلَّ يوم بينما يبقى
      // حسابُ النقدية في الأستاذ صحيحاً. مطابقٌ لـ`_closeShiftSafes:944-961`.
      await into(safeTransactions).insert(
        SafeTransactionsCompanion.insert(
          voucherNumber: voucherNumber,
          safeId: central.id,
          transactionType: 'receipt',
          category: 'closing',
          amount: currentBalance,
          balanceAfter: central.balance + currentBalance,
          description: Value('إقفال يومي — استلام رصيد ${safe.name}'),
          userId: Value(userId),
          createdAt: Value(DateTime.now()),
          referenceType: const Value('daily_closing'),
          referenceId: Value(closingTxnId),
          globalId: Value(
              (closeEventGid != null && closeEventGid.isNotEmpty)
                  ? '$closeEventGid-central'
                  : null),
        ),
      );
      await adjustSafeBalance(central.id, currentBalance);

      final branchId = safe.branchId; // Standardized branch resolution

      // Post accounting JE for the closing transfer.
      // Credit: the safe's own linked GL account (safe.linkedAccountId).
      //         Fallback to purpose-based account by safe type.
      // Debit:  split between cash and bank destinations based on
      //         the amounts entered by the user; if neither provided,
      //         route to the generic opposite-type purpose account.
      // ⚠️ **بلا `try/catch` هنا عن قصد.** كان القيدُ كلُّه ملفوفاً في
      // `catch (e) { debugPrint(...) }`، فأيُّ فشلٍ في الترحيل يُبتلَع **بعد**
      // أن صُفِّي الدرجُ فعلاً ⇒ نقديةٌ خرجت من الخزائن بلا أثرٍ في الأستاذ ولا
      // رسالةٍ لأحد. ونحن داخلَ `transaction()`، فتركُ الاستثناء يصعد يُرجِع
      // التصفيرَ والاستلامَ معاً — وهو التصرّفُ الصحيح: إقفالٌ بلا قيدٍ لا
      // يُحفَظ أصلاً. (‏نفسُ نمطِ `operational_expenses_dao.dart:395`.)
      {
        // ── Destination accounts (Debit side): where the money goes ──
        final effectiveCash = (cashAmount ?? 0).clamp(0, currentBalance).toDouble();
        final effectiveBank = (bankAmount ?? 0).clamp(0, currentBalance).toDouble();
        // If both are 0 (no amounts specified), route everything to the
        // same-type account (cash safe → cash, bank safe → bank).
        final useSplit = effectiveCash + effectiveBank > 0.001;

        final lines = <JournalLine>[];

        if (useSplit) {
          if (effectiveBank > 0.001) {
            final bankAccount = await accountingDao.getAccountByPurpose('bank');
            if (bankAccount != null) {
              lines.add(JournalLine(
                accountId: bankAccount.id,
                debit: effectiveBank,
                description: 'إقفال — تحويل إلى البنك',
              ));
            }
          }
          if (effectiveCash > 0.001) {
            // الشقُّ النقديُّ يذهب إلى **الخزنة المركزيّة** فعلاً
            // (`adjustSafeBalance(central.id, currentBalance)` أعلاه)، فحسابُه
            // حسابُها لا حسابُ الغرض العامّ.
            //
            // ⚠️ أمّا الشقُّ **البنكيُّ** أعلاه فيبقى على حساب الغرض عمداً:
            // هو إيداعٌ في بنكٍ لا صفَّ خزنةٍ له، فتوجيهُه إلى حسابٍ فرعيٍّ
            // يخترع دفتراً مساعداً لا وجودَ له. يتغيّر يومَ تختار الشاشةُ
            // خزنةَ بنكٍ بعينها.
            final cashAccount = await resolveSafeGlAccount(central);
            if (cashAccount != null) {
              lines.add(JournalLine(
                accountId: cashAccount.id,
                debit: effectiveCash,
                description: 'إقفال — تحويل نقدي',
              ));
            }
          }
          // If split amounts don't add up exactly to balance, absorb remainder
          // in the larger destination to keep the JE balanced.
          final splitTotal = effectiveCash + effectiveBank;
          if ((splitTotal - currentBalance).abs() > 0.001 && lines.isNotEmpty) {
            final diff = currentBalance - splitTotal;
            lines[0] = JournalLine(
              accountId: lines[0].accountId,
              debit: lines[0].debit + diff,
              description: lines[0].description,
            );
          }
        } else {
          // بلا تقسيمٍ: الرصيدُ كلُّه انتقل إلى **الخزنة المركزيّة**، فالمدينُ
          // حسابُها. كان حسابَ الغرض العامّ، فيبقى حسابُ المركزيّة صفراً
          // ويحمل `1111` مديناً لا خزنةَ تملكه.
          final destAccount = await resolveSafeGlAccount(central);
          if (destAccount != null) {
            lines.add(JournalLine(
              accountId: destAccount.id,
              debit: currentBalance,
              description: safe.safeType == 'bank'
                  ? 'إقفال بنك — ترحيل إلى البنك'
                  : 'إقفال صندوق — ترحيل إلى الصندوق الرئيسي',
            ));
          }
        }

        // Credit: this safe's GL account
        lines.add(JournalLine(
          accountId: sourceAccount.id,
          credit: currentBalance,
          description: 'إقفال يومي — ${safe.name}',
        ));

        // ── قيدٌ يلغي نفسَه = لا قيد ────────────────────────────────────────
        // الخزنتان تقعان على نفس حساب النقدية حين لا يكون للخزنة حسابٌ مرتبط،
        // فيخرج القيدُ `١١١١ مدين ١٠٠ / ١١١١ دائن ١٠٠` — صافيه صفرٌ على نفس
        // الحساب. مقيسٌ في الإقفال اليومي. وهو ليس عبثاً فحسب: يقرأه المدقّقُ
        // ترحيلاً حدث ولم يحدث. والحركةُ الحقيقيةُ هنا بين خزنتين لا بين
        // حسابين — سطرا الخزائن أعلاه هما الأثرُ الصحيح.
        final netByAccount = <int, double>{};
        for (final l in lines) {
          netByAccount.update(l.accountId, (v) => v + l.debit - l.credit,
              ifAbsent: () => l.debit - l.credit);
        }
        final isSelfCancelling =
            netByAccount.values.every((v) => v.abs() < 0.001);

        if (lines.length >= 2 && !isSelfCancelling) {
          // Spec 135 — deterministic JE globalId for the daily-closing JE.
          // referenceId is closingTxnId, a LOCAL autoincrement that differs
          // client vs server, so the (referenceType, referenceId) dedup never
          // matched across instances → the client-posted closing JE and the
          // server-posted one both survived DeltaPull as duplicates. Keyed on
          // the shared closeEventGid both sides converge; the
          // journal_entries.globalId UNIQUE index dedups on next pull. Null
          // (legacy random gid) when the caller didn't mint one.
          final closeJeGid = (closeEventGid != null && closeEventGid.isNotEmpty)
              ? JournalEntryGid.compute(
                  sourceType: JournalEntryGid.sourceSafeClose,
                  sourceGid: closeEventGid,
                  verb: 'close',
                )
              : null;
          if (closeJeGid != null) {
            final gidShort = closeEventGid!.length >= 8
                ? closeEventGid.substring(0, 8)
                : closeEventGid;
            unawaited(DiagnosticLogger.log(
              DiagnosticLogger.gidAutopost,
              'sourceType=safeclose sourceGid=$gidShort verb=close safe=$safeId',
            ));
          }
          await accountingDao.createJournalEntry(
            description: 'إقفال يومي — ${safe.name} ($voucherNumber)',
            date: DateTime.now(),
            lines: lines,
            referenceType: 'daily_closing',
            referenceId: closingTxnId, // unique per closing event (safe txn ID)
            isAutoPosted: true,
            branchId: branchId,
            globalId: closeJeGid,
          );
        }
      }
    });
  }

}
