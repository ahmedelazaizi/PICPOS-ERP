part of '../database.dart';

/// Atomic safe + chart-of-accounts sub-account linkage.
extension TreasurySafeLinkingDao on AppDatabase {
  // ═══════════════════════════════════════════════════════════════════════
  // Feature 004 (Multi-Branch Governance, US1) — Atomic Safe + CoA linkage
  // ═══════════════════════════════════════════════════════════════════════

  /// Returns the next zero-padded 5-digit suffix to compose a deterministic
  /// sub-account code under [parentId]. Mirrors the convention used by the
  /// `party_dao.insertParty` path: e.g., parent code `1110` plus the
  /// returned `42` becomes `'1110-00042'`. Transaction-safe — call this
  /// inside an open `transaction(() async { ... })`.
  ///
  /// Suffix uniqueness is local-only at create-time. After sync, `serverWins`
  /// resolves any divergence between client and server codes; FK linkage is
  /// always carried by `globalId`, so divergent codes never break referential
  /// integrity.
  ///
  /// **Portability (2026-05-03)** — the previous implementation used a
  /// `customSelect` with `INSTR()` and `SUBSTR()` to extract the suffix in
  /// SQL. `INSTR` is SQLite-only; PostgreSQL rejects it with
  /// `function instr(text, unknown) does not exist`, breaking safe creation
  /// on any deployment that runs the engine against Postgres (server mode
  /// + Supabase). The portable fix is to read the candidate codes through
  /// Drift's typed query API and parse the suffix in Dart — no
  /// dialect-specific functions, identical behaviour on SQLite and Postgres.
  Future<int> _nextAccountSuffix(int parentId) async {
    final children = await (select(accounts)
          ..where((a) => a.parentId.equals(parentId)))
        .get();
    var maxSuffix = 0;
    for (final account in children) {
      final dashIdx = account.code.indexOf('-');
      if (dashIdx <= 0) continue; // not a suffixed sub-account
      final suffixStr = account.code.substring(dashIdx + 1);
      final suffix = int.tryParse(suffixStr);
      if (suffix != null && suffix > maxSuffix) {
        maxSuffix = suffix;
      }
    }
    return maxSuffix + 1;
  }

  /// الأبُ الذي تُعلَّق تحته حساباتُ الخزائن الفرعية.
  ///
  /// Compatibility (2026-05-03) — `'1110'` أولاً (استيرادُ دليلٍ مخصَّصٍ قد
  /// يحمله) ثم `'111'` وهو ما يبذره `database_seeder_accounts.dart` فعلاً
  /// («النقدية وما فى حكمها»)، فلا يُجبَر المشغّلُ على إنشاء `1110` يدوياً.
  ///
  /// مستخرَجٌ كي يشترك فيه مسارُ الإنشاء ومسارُ الإصلاح: لو افترق النصّان
  /// لأمكن أن يُنشئ أحدُهما تحت `1110` والآخرُ تحت `111` في نفس التنصيب،
  /// فتتشتّت حساباتُ الخزائن على أبوين ولا يجمعها تقرير.
  Future<Account?> _resolveSafesParentAccount() async {
    for (final code in const ['1110', '111']) {
      final found =
          await (select(accounts)..where((a) => a.code.equals(code)))
              .getSingleOrNull();
      if (found != null) return found;
    }
    return null;
  }

  /// يمنح كلَّ خزنةٍ بلا `linkedAccountId` حسابَها الفرعيَّ تحت أب الخزائن،
  /// ويعيد عددَ ما رُبط.
  ///
  /// ── فئةُ العطب ────────────────────────────────────────────────────────
  /// خزنةٌ بلا ربطٍ تسقط بحسب **نوعها** على حسابٍ مشترك
  /// ([kSafeTypeAccountCode]: cash→1111 · bank→1113 · click→1116)، فكلُّ
  /// الخزائن النقدية تترحّل على `1111` ولا تُميَّز في الأستاذ: درجُ الكاشير
  /// والصندوقُ المركزيُّ رقمٌ واحدٌ لا ينفصل، ولا سبيلَ لمطابقة رصيد خزنةٍ
  /// بعينها مع الدفاتر.
  ///
  /// و[createSafeWithLinkedAccount] تفعل الصوابَ منذ v142، لكنّ **البذرة**
  /// لا تمرّ بها: `database_seeder.dart` يُدرج «صندوق الكاشير» و«الحساب
  /// البنكي» و«صندوق تحويل كليك» و«الصندوق الرئيسي» بإدراجٍ عارٍ بلا ربط —
  /// فكلُّ تنصيبٍ جديدٍ يولد بالعطب كاملاً. هذا الإصلاحُ هو الطرفُ المكمّل.
  ///
  /// **متعادلٌ** ويعمل كلَّ إقلاع: لا يمسّ إلا `linkedAccountId IS NULL`،
  /// فاختيارُ المستخدم الصريحُ لا يُداس أبداً. والمحذوفةُ ناعماً مستثناةٌ —
  /// لا معنى لحسابٍ جديدٍ لخزنةٍ أُزيلت.
  ///
  /// كلُّ خزنةٍ في معاملةٍ مستقلّة: لاحقةُ الكود متسلسلةٌ لكلّ أب، فمعاملةٌ
  /// واحدةٌ جامعةٌ كانت ستُسقط الجميعَ لتصادمٍ في واحدة.
  Future<int> linkUnlinkedSafesToSubAccounts() async {
    final parent = await _resolveSafesParentAccount();
    // دليلٌ بلا أبٍ للخزائن: لا نُنشئ شجرةً من عندنا — الإنشاءُ اليدويّ
    // يصرّح بذلك للمستخدم، والإصلاحُ الصامتُ يكتفي بالانصراف.
    if (parent == null) return 0;

    final unlinked = await (select(safes)
          ..where((s) => s.linkedAccountId.isNull() & s.deletedAt.isNull()))
        .get();
    if (unlinked.isEmpty) return 0;

    var linked = 0;
    for (final safe in unlinked) {
      final ok = await transaction(() async {
        final suffix = await _nextAccountSuffix(parent.id);
        final code = '${parent.code}-${suffix.toString().padLeft(5, '0')}';

        // تصادمٌ نظريّ (صفٌّ قديمٌ من هجرةٍ جزئية) — نتخطّى هذه الخزنةَ
        // وتُلتقط في الإقلاع التالي بدل إسقاط الدفعة كلّها.
        final dup = await (select(accounts)..where((a) => a.code.equals(code)))
            .getSingleOrNull();
        if (dup != null) return false;

        final accountId = await into(accounts).insert(
          AccountsCompanion.insert(
            code: code,
            name: safe.name,
            accountType: 'asset',
            parentId: Value(parent.id),
            isSystem: const Value(false),
            globalId: Value(UuidV7.generate()),
          ),
        );
        await (update(safes)..where((s) => s.id.equals(safe.id)))
            .write(SafesCompanion(linkedAccountId: Value(accountId)));
        return true;
      });
      if (ok) linked++;
    }
    return linked;
  }

  /// يشغّل [linkUnlinkedSafesToSubAccounts] **مرّةً واحدةً لكلّ تنصيب** — وهو
  /// ما يناديه الإقلاع.
  ///
  /// ── لماذا البوّابةُ هنا لا داخلَ الإصلاح ──────────────────────────────────
  /// شاشةُ إدارة الصناديق فيها منتقي «الحساب المرتبط» من دليل الحسابات، وهو
  /// **اختياريٌّ** في الإنشاء والتعديل معاً (‏`hint: 'بدون'` مع
  /// `showClearButton: true` في `safe_management_dialog.dart`). فـ«بدون»
  /// اختيارٌ صريحٌ للمستخدم لا فراغٌ ينتظر الملء.
  ///
  /// ولأن الإصلاح متعادلٌ على `linkedAccountId IS NULL` فهو لا يدوس ربطاً
  /// قائماً — لكنه كان يدوس **الفكّ**: يمسح المستخدمُ الربطَ فيعيده الإقلاعُ
  /// التالي بحسابٍ **جديدٍ يُنشئه**، وكلُّ مسحٍ يخلّف حساباً يتيماً في الدليل
  /// (‏`111-00005` ثم `111-00006` …) لا يستعمله أحد ولا يحذفه أحد.
  ///
  /// فالبوّابةُ على الغلاف: [linkUnlinkedSafesToSubAccounts] يبقى بلا بوّابةٍ
  /// وقابلاً للنداء المباشر (‏زرٌّ إداريٌّ لاحقاً · اختبار)، والغلافُ وحدَه هو
  /// ما يمرّ به الإقلاع.
  ///
  /// ⚠️ والختمُ **بعد** النجاح لا قبله: الإصلاحُ ينصرف صامتاً حين لا يجد أبَ
  /// الخزائن، فختمُ الرقعة عندها كان يحرق التنصيبَ الجديد — لا يعمل على أوّل
  /// إقلاعٍ ولا على ما بعده. لذلك يُفحص وجودُ الأب قبل الختم.
  Future<int> linkUnlinkedSafesToSubAccountsOnce() async {
    if (await getSettingValue(kSafeSubAccountsBackfillV1Applied) == 'true') {
      return 0;
    }
    // بلا أبٍ لم يعمل الإصلاحُ شيئاً — فلا يُختم، ويُعاد في الإقلاع التالي.
    if (await _resolveSafesParentAccount() == null) return 0;

    final linked = await linkUnlinkedSafesToSubAccounts();
    await setSetting(kSafeSubAccountsBackfillV1Applied, 'true');
    return linked;
  }

  /// Atomically create a Safe and its linked Chart-of-Accounts sub-account.
  ///
  /// This is the canonical entry point for safe creation since v142 (Feature
  /// 004). Both rows (the safe and its sub-account under parent code `1110`
  /// "النقدية فى الصناديق") are inserted inside a single `db.transaction()`,
  /// linked via `safes.linked_account_id`, and both carry a UUIDv7 `globalId`
  /// so cross-device sync resolves them deterministically.
  ///
  /// The sub-account code is computed as `'1110-{NNNNN}'` where NNNNN is the
  /// next sequential suffix produced by [_nextAccountSuffix]. The account's
  /// `name` mirrors the safe's `name` so the user sees the linkage visually.
  ///
  /// Throws [MissingParentAccountException] (rolling back the transaction)
  /// when the `'1110'` parent account is absent from the deployed Chart of
  /// Accounts. The dialog layer surfaces the message verbatim to the user.
  Future<int> createSafeWithLinkedAccount({
    required String name,
    required String safeType,
    String? bankName,
    String? accountNumber,
    int? costCenterId,
    int? branchId,
  }) {
    // Feature 004 (US3, FR-023b) — fail fast before opening the transaction
    // when the elevated-admin session has lost the server connection. The
    // alternative (enqueue or silently no-op) would mislead the user about
    // whether the safe was created.
    final guard = MutationGuard.current;
    if (!guard.canMutate) {
      throw MutationDeniedException(guard.reason);
    }
    return transaction(() async {
      final parent = await _resolveSafesParentAccount();
      final parentCode = parent?.code;
      if (parent == null || parentCode == null) {
        throw const MissingParentAccountException(
          '1110 / 111',
          'لم يتم العثور على حساب أب للصناديق (الكود 1110 أو 111). '
          'يرجى إنشاء الحساب من شاشة دليل الحسابات قبل إعادة المحاولة.',
        );
      }

      // ── Compute the deterministic sub-account code ───────────────────
      final suffix = await _nextAccountSuffix(parent.id);
      final accountCode = '$parentCode-${suffix.toString().padLeft(5, '0')}';

      // Defensive uniqueness check — collisions shouldn't occur because the
      // suffix is monotonic per parent inside this transaction, but a stale
      // PG row from a partial migration could theoretically clash.
      final dup = await (select(accounts)
            ..where((a) => a.code.equals(accountCode)))
          .getSingleOrNull();
      if (dup != null) {
        throw Exception(
          'كود الحساب الفرعى "$accountCode" مستخدم بالفعل — '
          'تحقق من دليل الحسابات.',
        );
      }

      // ── INSERT account ──────────────────────────────────────────────
      final accountId = await into(accounts).insert(
        AccountsCompanion.insert(
          code: accountCode,
          name: name,
          accountType: 'asset',
          parentId: Value(parent.id),
          isSystem: const Value(false),
          globalId: Value(UuidV7.generate()),
        ),
      );

      // ── INSERT safe with linked_account_id ──────────────────────────
      final safeId = await into(safes).insert(
        SafesCompanion.insert(
          name: name,
          safeType: Value(safeType),
          bankName: Value(bankName),
          accountNumber: Value(accountNumber),
          costCenterId: Value(costCenterId),
          branchId: Value(branchId),
          linkedAccountId: Value(accountId),
          globalId: Value(UuidV7.generate()),
        ),
      );

      return safeId;
    });
  }
}
