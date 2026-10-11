// ═══════════════════════════════════════════════════════════════════════════
// TREASURY DAO - Safes, Transactions, and Financial Operations
// ═══════════════════════════════════════════════════════════════════════════
//
// This file contains all treasury-related database operations.
//
// File map (all `part of database.dart`; extensions on AppDatabase):
//   treasury_dao.dart: constants, central safe/GL account, balance writes, createSafeTransaction, safe CRUD (this file)
//   treasury_shift_models.dart: ShiftClosingAggregates / ShiftReportDto / expense DTOs
//   treasury_shift_dao.dart: open/close shift entry points + paginated shifts report
//   treasury_shift_settlement_dao.dart: _settleShift + variance posting
//   treasury_shift_close_safes_dao.dart: _closeShiftSafes (zero-out safes at shift close)
//   treasury_shift_aggregates_dao.dart: getShiftClosingAggregates
//   treasury_safe_queries_dao.dart: safe reads, watchers, totals, branch-scoped lists
//   treasury_safe_resolution_dao.dart: drawer / operation / refund safe resolution
//   treasury_transactions_dao.dart: safe-transaction watchers + closeSafe
//   treasury_safe_linking_dao.dart: atomic safe + CoA sub-account linkage
// This file contains all treasury-related database operations.


part of '../database.dart';

/// اسم الصندوق الرئيسي (الإدارة المركزية) — وجهة نقدية إقفال الورديات.
const String kCentralSafeName = 'الصندوق الرئيسي';

/// نوعُ صفِّ **سند الشيك** — مستندٌ بلا أثرٍ ماليّ.
///
/// ⚠️ **يُقرأ ولا يُكتَب بيده**: القيمةُ تُستثنى في قرّاء كشف الحساب
/// (`party_dao`)، وكتابتُها سلسلةً في موضعَين تجعل استثناءً واحداً يفلت
/// فيعود السطرُ المكرّر. راجع [AppDatabase._writeChequeVoucherRow].
const String kChequeVoucherTxnType = 'cheque_voucher';

/// مفتاح البذرة الثابت للـ`globalId` — مستقل عن الاسم المعروض عشان إعادة
/// التسمية ما تخلقش خزينة تانية على الأجهزة التانية (نفس نمط Spec 136 ISS-2).
const String kCentralSafeSeedKey = 'central';

/// كود الحساب الافتراضي لكل نوع خزينة — **مطابق لمسار البيع الحي**.
///
/// `_resolveBranchSafeAccount` في `accounting_autopost_dao.dart:58` بيقع على
/// حساب الغرض بحسب نوع الخزينة (`cash`/`bank`/`click`). أي خريطة مختلفة هنا
/// معناها إن سند القبض النقدي بيتقيّد على حساب غير اللي البيع النقدي بيتقيّد
/// عليه — تناقض في نفس الدفتر أسوأ من الباج الأصلي.
const Map<String, String> kSafeTypeAccountCode = {
  'cash': '1111', // الصندوق الرئيسي — نفس ما بيعمله مسار البيع
  'bank': '1113', // البنك الأهلي - حساب جاري
  'click': '1116', // حساب Click
};

/// ختمُ الرقعة المرّة-الواحدة لربط الخزائن بحساباتها الفرعية.
///
/// قرارُ المالك 2026-08-11: الربطُ التلقائيُّ يصلح **تنصيباً جديداً** ثم تصير
/// شاشةُ إدارة الصناديق صاحبةَ القرار. ومنتقي «الحساب المرتبط» فيها اختياريٌّ
/// ويسمح بـ«بدون» (‏`safe_management_dialog.dart` — `showClearButton: true`)،
/// فإصلاحٌ يعمل كلَّ إقلاعٍ كان سيدوس ذلك الاختيار ويخلّف حساباً يتيماً في
/// الدليل مع كلّ مسح.
///
/// ويُكتب هنا لا في `DeploymentSettingsKeys`: تلك محروسةٌ بـ
/// `test/static/no_direct_network_mode_writes_test.dart` الذي يمنع أيَّ
/// `setSetting` على مفاتيحها خارج مُلزِم النشر — نفسُ سبب بقاء مفاتيح رقعة
/// Spec 138 في ملفّ خدمتها.
const String kSafeSubAccountsBackfillV1Applied =
    'safe_sub_accounts_backfill_v1_applied';

/// Extension for Treasury-related database operations (core part).
extension TreasuryDao on AppDatabase {
  /// الصندوق الرئيسي (الإدارة المركزية) — أو `null` لو مش مزروع.
  ///
  /// البحث بالـ`globalId` المشتق مش بالاسم: الاسم قابل للتعديل من المستخدم،
  /// والبحث بيه كان هيخلق خزينة تانية على أول إعادة تسمية. الاسم احتياطي
  /// للتركيبات اللي اتعملت قبل ما البذرة الثابتة تدخل.
  Future<Safe?> getCentralSafe() async {
    final gid = UuidV7.deriveSeedGlobalId(
        table: 'safes', seedKey: kCentralSafeSeedKey);
    final byGid = await (select(safes)
          ..where((s) => s.globalId.equals(gid))
          ..limit(1))
        .getSingleOrNull();
    if (byGid != null) return byGid;
    return (select(safes)
          ..where((s) => s.name.equals(kCentralSafeName))
          ..limit(1))
        .getSingleOrNull();
  }

  /// موضعٌ واحدٌ لحسابِ خزنةٍ في الأستاذ — نظيرُ `resolveShiftDrawer`
  /// للحسابات لا للأدراج.
  ///
  /// الترتيب: حسابُ الخزنة المرتبطُ ← حسابُ الغرض بحسب **نوعها** ← `null`.
  ///
  /// ── لماذا دالّةٌ واحدة ────────────────────────────────────────────────
  /// كانت قيودُ الخزينة تُرحَّل على حسابِ الغرض **العامّ**
  /// (`getAccountByPurpose('cash')` ⇒ `1111` عادةً) بينما المالُ يتحرّك على
  /// خزنةٍ بعينها. و`linkUnlinkedSafesToSubAccounts` تُنشئ لكلِّ خزنةٍ حساباً
  /// فرعيّاً `111-0000N` **شقيقاً** لـ`1111` لا ابناً له. فالنتيجة: رصيدُ
  /// الخزنة يتحرّك في جدولها، وحسابُها في الأستاذ يبقى صفراً، و`1111` يحمل
  /// حركاتٍ لا خزنةَ تملكها. المجموعُ تحت `111` يبقى صحيحاً — ولهذا لم
  /// يكشفه اختبارُ اتّفاقِ الأستاذ — لكنّ نسبةَ كلِّ ريالٍ إلى درجه ضاعت.
  ///
  /// ⚠️ [safe] هي الخزنةُ التي **تحرّك رصيدُها فعلاً** — لا خزنةُ الفرع
  /// الافتراضيّة ولا مفتاحُ إعدادات. ونداءٌ لا يستطيع تسميةَ خزنةٍ بعينها لا
  /// يستعمل هذه الدالّة أصلاً: طرفُه العامُّ صحيحٌ لأن لا حركةَ خزنةٍ خلفه.
  ///
  /// و`getLeafAccountById` لا `getAccountById`: خزنةٌ مربوطةٌ بحسابٍ أبٍ
  /// (`accountNature == 'view'`) يرفضها حارسُ الترحيل، والرفضُ يقع **بعد**
  /// أن يكون النقدُ قد خرج.
  Future<Account?> resolveSafeGlAccount(Safe? safe) async {
    if (safe == null) return null;

    final linkedId = safe.linkedAccountId;
    if (linkedId != null) {
      final linked = await accountingDao.getLeafAccountById(linkedId);
      // ⚠️ **ولا يُوثَق بالرابط بلا فحص.** مسارُ السحب التفاضليّ يكتب
      // `linked_account_id` رقماً خامّاً من الخادم، ودليلُ الحسابات يُزرع
      // على كلِّ طرفٍ مستقلّاً — فالرقمُ قد يقع على حسابٍ **حقيقيٍّ آخر**
      // (‏إيرادٍ أو مصروف). ورابطٌ خاطئٌ هنا يصير رِجْلاً في قيدٍ ماليّ،
      // فيُرحَّل النقدُ على حسابٍ لا علاقةَ له — عطبٌ أصعبُ كشفاً من الذي
      // نُصلحه. فيُشترَط أن يكون أصلاً: خزنةٌ لا تُربَط إلّا بحسابِ أصل.
      if (linked != null && linked.accountType == 'asset') return linked;
      if (linked != null) {
        // ignore: discarded_futures — أثرٌ تشخيصيٌّ لا ننتظره.
        DiagnosticLogger.log(
          'ACCT-WARN',
          'safe "${safe.name}" (id=${safe.id}) مربوطةٌ بحسابٍ ليس أصلاً: '
              '${linked.code} (${linked.accountType}) — يُتجاهَل الرابطُ '
              'ويُستعمل حسابُ الغرض. راجِع ربطَ الخزنة.',
        );
      }
    }

    final purpose = switch (safe.safeType) {
      'bank' => 'bank',
      'click' => 'click',
      _ => 'cash',
    };
    return accountingDao.getLeafAccountByPurpose(purpose);
  }

  /// نفسُها ورميٌ صريح — لكلِّ مسارٍ حرّك رصيدَ خزنةٍ **قبل** أن يُرحّل.
  /// الصمتُ هناك يعني نقداً خرج بلا أثرٍ في الأستاذ.
  Future<Account> requireSafeGlAccount(Safe safe, {required String op}) async {
    final acc = await resolveSafeGlAccount(safe);
    if (acc == null) {
      throw StateError(
        'تعذّر تحديد حساب «${safe.name}» في الأستاذ أثناء $op — لا حسابٌ '
        'مرتبطٌ ولا حسابُ غرضٍ لنوع «${safe.safeType}». اربط الخزنةَ من '
        'شاشة إدارة الصناديق قبل إعادة المحاولة.',
      );
    }
    return acc;
  }

  /// Set safe balance to an ABSOLUTE value.
  ///
  /// **Use sparingly** — most call sites should use [adjustSafeBalance]
  /// (delta-based) instead. This setter is appropriate ONLY for:
  ///  - Reconciliation flows that authoritatively re-set the balance to a
  ///    computed total (e.g. `reconciliation_service.dart`).
  ///  - One-off corrections by the accountant via the safes settings UI.
  ///
  /// For ANY routine "balance went up/down by N" path (sale, return,
  /// receipt voucher, payment voucher, transfer), use [adjustSafeBalance]
  /// — it is immune to the read-then-write lost-update race that bites
  /// under PostgreSQL's default Read-Committed isolation. (Spec 069 / D5-003.)
  Future<void> updateSafeBalance(int safeId, double newBalance) async {
    // T-01: SECURITY — Audit trail: log old vs new balance
    // NOTE: Activity log insert REMOVED from inside transactions to prevent
    // PostgreSQL transaction abort (25P02). On PG, any error in a try-catch
    // still aborts the entire transaction unlike SQLite.
    // The audit log can be added AFTER the transaction completes.

    await (update(safes)..where((s) => s.id.equals(safeId))).write(
      SafesCompanion(balance: Value(newBalance)),
    );
    // الكتابةُ المطلقة مشروعةٌ في مواضعَ معدودة (مصالحة · تصحيحُ محاسب ·
    // فرعُ `else` في `createSafeTransaction`). ظهورُها في التشغيلة اليدوية
    // بجوار حركةِ بيعٍ يعني أن مساراً روتينياً عاد إليها.
    unawaited(DiagnosticLogger.log(DiagnosticLogger.safeMove,
        'safe=$safeId abs=$newBalance via=absolute'));
  }

  /// 069 (D5-003) — Atomically adjust a safe's balance by [delta].
  ///
  /// Issues `UPDATE safes SET balance = balance + ? WHERE id = ?`. The
  /// arithmetic happens at the SQL layer, so two concurrent +100 calls
  /// against the same safe land as +200 (not +100 with one lost) regardless
  /// of isolation level. Required for PostgreSQL Read-Committed safety;
  /// no-cost on SQLite.
  ///
  /// Pass a NEGATIVE delta to decrease the balance (e.g. payment voucher
  /// of 100 → `adjustSafeBalance(safeId, -100)`).
  Future<void> adjustSafeBalance(int safeId, double delta) async {
    await customStatement(
      'UPDATE safes SET balance = balance + ? WHERE id = ?',
      [delta, safeId],
    );
    // أثرُ التشغيلة اليدوية — سطرٌ لكلّ حركة. سطران متطابقان لنفس الخزنة =
    // تطبيقٌ مزدوج. `unawaited` كي لا يدخل زمنُ الملفّ في زمن المعاملة.
    unawaited(DiagnosticLogger.log(
        DiagnosticLogger.safeMove, 'safe=$safeId delta=$delta via=adjust'));
  }

  /// Low-level safe transaction with full accounting treatment (Moved from database.dart)
  /// HARDENED: Safe balance now recalculated inside transaction to prevent Lost Update
  Future<int> createSafeTransaction(SafeTransactionsCompanion trans) async {
    return transaction(() async {
      // 0. Soft/Hard Period Closing Gating
      final dateToValidate = trans.createdAt.present ? trans.createdAt.value : DateTime.now();
      await accountingDao.validateFinancialPeriod(dateToValidate, operation: 'حركة خزينة');

      // Insert the transaction record
      final transactionId = await into(safeTransactions).insert(trans);

      // CRITICAL: Atomic balance update to prevent Lost Update race condition.
      // Uses SQL-level arithmetic (balance + amount) instead of read-then-write.
      final safeId = trans.safeId.value;
      final amount = trans.amount.value;
      final transType = trans.transactionType.value;

      // الحركةُ نفسُها قبل أثرِها على الرصيد — تربط سطرَ `SAFE-MOVE` التالي
      // بسببه، فيُقرأ السجلُّ قصّةً لا أرقاماً متناثرة.
      unawaited(DiagnosticLogger.log(
          DiagnosticLogger.safeMove,
          'txn safe=$safeId type=$transType amount=$amount '
          'category=${trans.category.value} ref=${trans.referenceType.present ? trans.referenceType.value : '-'}'));

      if (transType == 'deposit' || transType == 'receipt') {
        // Atomic increment: SET balance = balance + amount
        await customStatement(
          'UPDATE safes SET balance = balance + ? WHERE id = ?',
          [amount, safeId],
        );
      } else if (transType == 'withdrawal' || transType == 'payment') {
        // Atomic decrement: SET balance = balance - amount
        await customStatement(
          'UPDATE safes SET balance = balance - ? WHERE id = ?',
          [amount, safeId],
        );
      } else if (transType == 'closing') {
        // 'closing' is a daily/shift close that empties the safe.
        await customStatement(
          'UPDATE safes SET balance = 0 WHERE id = ?',
          [safeId],
        );
      } else {
        // transfer, adjustment, memo — use the provided balanceAfter
        await updateSafeBalance(safeId, trans.balanceAfter.value);
      }

      // Update party balance if this is a party-related transaction
      if (trans.partyId.present && trans.partyId.value != null) {
        final partyId = trans.partyId.value!;

        // Receipt from customer: reduce their outstanding balance (they owed us, now paying)
        // Payment to supplier: reduce our outstanding balance to them
        if (transType == 'receipt') {
          await adjustPartyBalance(partyId, -amount); // Reduce customer's debt
        } else if (transType == 'payment') {
          await adjustPartyBalance(
            partyId,
            -amount,
          ); // Reduce our debt to supplier
        }
      }

      return transactionId;
    });
  }


  // ═══════════════════════════════════════════════════════════════════════
  // TREASURY REPORTS — See treasury_reports_dao.dart
  // ═══════════════════════════════════════════════════════════════════════


  // ═══════════════════════════════════════════════════════════════════════
  // SAFE CRUD OPERATIONS (ISS-09: migrated from database.dart)
  // ═══════════════════════════════════════════════════════════════════════

  /// Update safe name, bank info. PostgreSQL-compatible: Drift API
  Future<void> updateSafeInfo({
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

  /// Set a safe as the default (clears others first). PostgreSQL-compatible.
  Future<void> markSafeAsDefault(int safeId) async {
    // Use raw SQL with sqlBool() for PG boolean compatibility
    final falseVal = sqlBool(false);
    final trueVal = sqlBool(true);
    await customStatement(
      'UPDATE safes SET is_default = $falseVal',
    );
    await customStatement(
      'UPDATE safes SET is_default = $trueVal, is_active = $trueVal WHERE id = ?',
      [safeId],
    );
  }

  /// Toggle safe active/inactive. PostgreSQL-compatible.
  Future<void> setSafeActiveStatus(int safeId, bool isActive) async {
    final boolVal = sqlBool(isActive);
    await customStatement(
      'UPDATE safes SET is_active = $boolVal WHERE id = ?',
      [safeId],
    );
  }

  /// Delete a non-default safe. PostgreSQL-compatible.
  Future<void> removeSafe(int safeId) async {
    await (delete(safes)..where((s) => s.id.equals(safeId) & s.isDefault.equals(false))).go();
  }
}
