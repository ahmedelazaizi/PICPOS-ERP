part of 'database.dart';

// ═══════════════════════════════════════════════════════════════════════════
// DATABASE STARTUP — `beforeOpen` lifecycle extracted for maintainability
// ═══════════════════════════════════════════════════════════════════════════
//
// PIR P2.6: Extracted from database.dart to reduce main file complexity.
// Groups startup operations into logical phases:
//   Phase 1: Schema safety (ensure columns exist)
//   Phase 2: Seeding (initial data + admin user)
//   Phase 3: Permissions & accounts sync
//   Phase 4: One-time data patches (gated)
//   Phase 5: Deferred background tasks (backup)
// ═══════════════════════════════════════════════════════════════════════════

extension DatabaseStartup on AppDatabase {
  /// Entry point called from `MigrationStrategy.beforeOpen`.
  /// Orchestrates all startup phases in the correct dependency order.
  Future<void> runBeforeOpen(OpeningDetails details) async {
    // Phase 1: Ensure PostgreSQL compat layer exists
    if (_isPostgres) {
      try {
        await _createPostgresCompatLayer();
      } catch (e) {
        debugPrint('[Startup] strftime compat: $e');
      }
    }

    // Phase 2: Schema safety — ensure v110 columns exist (BLOCKING)
    await ensureSchemaDefaults();

    // Phase 2b: Database integrity — ensure critical PK/UNIQUE constraints
    // exist on PG installs whose schema was created by an older or crashed
    // migration. This MUST run before any seeder that relies on ON CONFLICT.
    if (_isPostgres) {
      await _ensureDatabaseIntegrity();
    }

    // Phase 2c: Postgres-only sync hardening (v129/v130 equivalents).
    // The SQLite `onUpgrade` path added sync columns + auto-bump triggers
    // using SQLite-only DDL. Postgres skips onUpgrade entirely, so we install
    // the PG equivalents here. Idempotent no-op when already in place.
    if (_isPostgres) {
      try {
        await _ensurePostgresSyncInfrastructure();
      } catch (e) {
        debugPrint('[Startup] PG sync infra: $e');
      }
    }

    // Phase 2d: PG generic schema parity (Spec 130).
    // Defense-in-depth safety net that compares every Drift schema entity
    // against the live PG `information_schema` and closes gaps with
    // idempotent DDL (CREATE TABLE / ALTER ADD COLUMN / CREATE INDEX /
    // ALTER ADD CONSTRAINT FK).
    //
    // Runs AFTER _createAllForPostgres (first-boot creator) and
    // _ensurePostgresSyncInfrastructure (targeted sync columns/triggers).
    // Catches any gap left by those — including the field-confirmed
    // 2026-05-25 bug where `category_station_mappings` was missing on
    // a PG install, causing every POS sale to fail with 42P01.
    //
    // Throws [PgSchemaParityException] on unrecoverable failure
    // (e.g. DDL permission denied). main_desktop.dart catches and routes
    // to the Spec 125 Fatal screen with a "retry self-heal" button.
    if (_isPostgres) {
      try {
        await _ensurePostgresSchemaParity();
      } on PgSchemaParityException {
        rethrow; // bubble to main_desktop.dart → Fatal screen (Block-all)
      } catch (e, st) {
        // Unexpected non-parity errors are bugs in the parity pass itself,
        // NOT schema gaps. Log loud and continue — Phase 3 seeders will
        // surface any actual missing-table consequences shortly.
        debugPrint('[Startup] PG schema parity unexpected: $e\n$st');
      }
    }

    // Phase 3: Seed initial data — roles, admin, units (BLOCKING)
    await _ensureSeedData(details.wasCreated);

    // Phase 3b: PostgreSQL baseline self-heal.
    // If the DB was created by an older or crashed seeder it may be missing
    // branches / warehouses / safes / accounts / fiscal year even though
    // roles and admin exist. Running the atomic seeder again is safe — each
    // helper is idempotent — and it fills in only what's missing.
    if (_isPostgres) {
      await _verifyAndHealPostgresBaseline();
    }

    // Phase 4: Permissions + default accounts sync — MOVED to synchronous
    // path (was deferred in a `Future.microtask`). The microtask raced with
    // the Setup Wizard's atomic seeder, causing 23505 duplicate-key errors
    // when both paths inserted the same permission codes concurrently.
    // `syncAllPermissions()` is idempotent and cheap when everything is
    // already seeded (pre-checks + ON CONFLICT), so running it here costs
    // nothing on a healthy DB but eliminates the race entirely.
    await _syncPermissionsAndAccounts();

    // Phase 5: One-time data patches (CRITICAL: Must block queries to prevent FormatExceptions)
    await _runStartupPatches();

    // Phase 6: Deferred background tasks (non-blocking) — ONLY truly
    // long-running / non-critical work (backup scheduling) stays in the
    // microtask. Anything that mutates schema or seed data now runs on the
    // synchronous path above.
    Future.microtask(() async {
      await _scheduleDeferredTasks();
      debugPrint('[Startup] ✅ Deferred phase 6 complete');
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Phase 2: Schema safety
  // ─────────────────────────────────────────────────────────────────────────

  /// Defensive: ensure v110 columns exist on older databases.
  /// Only for SQLite — PostgreSQL creates tables via m.createAll() with
  /// proper dialect and already includes these columns.
  Future<void> ensureSchemaDefaults() async {
    if (_isPostgres) return;
    for (final stmt in [
      "ALTER TABLE accounts ADD COLUMN account_nature TEXT NOT NULL DEFAULT 'detail'",
      "ALTER TABLE accounts ADD COLUMN normal_balance TEXT NOT NULL DEFAULT 'debit'",
      "ALTER TABLE accounts ADD COLUMN level INTEGER NOT NULL DEFAULT 1",
      // B-MIG-1: the v103 parties.account_id add lived in _migrateEpoch2, which
      // runOnUpgrade skips for from>=81, so DBs upgraded from v81-v102 never got
      // the column. Guarantee it here on every boot (defense-in-depth).
      'ALTER TABLE parties ADD COLUMN account_id INTEGER REFERENCES accounts(id)',
      // Spec 151: every-boot self-heal for the return-exempt auto-post dedup
      // index. IF NOT EXISTS makes this a no-op once the v150 migration (or the
      // fresh-install onCreate path) has already created it; it is here purely
      // as defense-in-depth so a DB that somehow lost the index re-acquires the
      // correct exempted shape. SQLite-only (this method returns early on PG).
      kCreateJeAutopostDedupIndexSql,
      // B1/B2: نفس منطق الشفاء الذاتي — IF NOT EXISTS بيخلّيهم no-op بعد ما
      // هجرة v152 (أو مسار التنصيب الجديد) ركّبهم. وبيفشلوا بصمت هنا لو
      // البيانات لسه فيها تكرار، وده مقصود: الحارسان في التطبيق شغالين،
      // والتسوية اليدوية شغل محاسب مش شغل إقلاع.
      kCreateSalaryPaymentDedupIndexSql,
      kCreateAttendanceDayDedupIndexSql,
      // v159: نفسُ الشفاء الذاتي لفهرس المسار الساخن في محرِّك الحجز. تمريرةُ
      // `allSchemaEntities` تحت بتغطّي **الجداول** بس، والفهارس الخامّة مش
      // كيانات drift فما بتوصلهاش — فلو جدولٌ وصل من هناك بقي بلا فهرسه.
      kCreateBookingResourceSlotIndexSql,
      // ٦‑٣: تسويةُ ربطِ الحسابات المزدوجِ ثمّ تركيبُ قيدِ التفرّد — **بهذا
      // الترتيب**. الفهرسُ تعبيريٌّ لأنّ الربطَ العامَّ `cost_center_id IS
      // NULL` هو عينُ الصفِّ الذي يفلت من `UNIQUE` العاديّ.
      //
      // وبخلاف فهرسَي B1/B2 فوق، التسويةُ هنا **آليّةٌ** بقرار المالك
      // 2026-08-31 (يبقى الأحدثُ بـ`updated_at`): الصفُّ الزائدُ هناك حركةٌ
      // ذاتُ قيمةٍ ماليّة، وهنا **إعدادٌ** مكرَّرٌ بقاؤه هو الضرر — يجعل
      // `getAccountByPurpose` يختار الحسابَ عشوائيّاً.
      kDedupAccountMappingsSql,
      kCreateAccountMappingsPurposeCcIndexSql,
      // §٣‑٦: قيدُ تفرّدِ المطابقة البنكيّة — **بلا تسويةٍ آليّةٍ قبله**،
      // كفهرسَي B1/B2 لا كربطِ الحسابات: الصفُّ المزدوجُ هنا حركةٌ ذاتُ قيمةٍ
      // ماليّة، وتسويتُها شغلُ محاسبٍ لا شغلُ إقلاع. وعلى بياناتٍ مزدوجةٍ
      // يفشل بصمتٍ ويبقى حارسُ `manualMatchStatement` قائماً.
      kCreateBankStatementMatchDedupIndexSql,
      // المرحلة ٨: تفرّدُ وسمِ الاستيراد — صفٌّ واحدٌ لكلّ فاتورة.
      // `onCreate` يبني كياناتِ drift وحدَها والفهارسُ الخامّةُ ليست منها،
      // فتنصيبةٌ جديدةٌ كانت تخرج بلا الفهرس. والجدولُ فارغٌ في كلّ تنصيبةٍ
      // قائمة (شُحن في v174 بلا كاتب) فلا تسويةَ تسبقه.
      kCreateImportPurchaseDetailsUniqueIndexSql,
      // ٦‑١: `e_invoice_status_log` جدولٌ خامٌّ لا كيانُ drift، فتمريرةُ
      // `allSchemaEntities` أدناه لا تصله كذلك. وهو هنا شفاءٌ ذاتيٌّ لقاعدةٍ
      // نُصِّبت قبل هذا الإصلاح: تُنشئه بلا هجرةٍ وبلا فقدِ بيانات.
      kCreateEInvoiceStatusLogSql,
      kCreateEInvoiceStatusLogIndexSql,
      // ⚠️ v82 (‏«Maker-Checker») أضاف هذه الثلاثةَ بـ`ALTER TABLE` في
      //    `epoch_3`، ولم تُعلَن قطُّ في صنف جدول `JournalEntries`. و
      //    `onCreate` يبني من كيانات drift لا من الهجرات — فالتنصيبُ
      //    **الجديدُ** لا يملكها.
      //
      //    والأثرُ مقيسٌ 2026-08-27: `approveJournalEntry` و
      //    `rejectJournalEntry` يكتبان `approved_by` بـ`customStatement`،
      //    فينهاران بـ«no such column: approved_by» على كلِّ قاعدةٍ جديدة.
      //    وPicPos بلا تنصيباتٍ قديمةٍ أصلاً ⇒ **كلُّ** قاعدةٍ جديدة.
      //
      //    ولم يظهر العطبُ قبل اليوم لأنّ الاعتمادَ كان طريقاً ميتاً: لا
      //    أحدَ في المستودع كان يكتب `needs_approval = true`، فلم يُعرَض
      //    زرُّ الاعتماد ولم يُستدعَ المسار. وقد أحياه «حفظ كمسودة».
      "ALTER TABLE journal_entries ADD COLUMN status TEXT NOT NULL DEFAULT 'posted'",
      'ALTER TABLE journal_entries ADD COLUMN approved_by INTEGER REFERENCES users(id)',
      'ALTER TABLE journal_entries ADD COLUMN approved_at INTEGER',
      // ⚠️ **مَن أنشأ.** بلا هذا العمود لا ضابطَ «لا يعتمد القيدَ منشئُه»
      //    أصلاً — فمَن يُنشئ يستطيع أن يعتمد، ويصير الترحيلُ خطوتَين بيدٍ
      //    واحدة: تأخيرٌ لا رقابة. وهو غيرُ مُعلَنٍ في صنف الجدول كإخوته
      //    الثلاثة، فيُضاف هنا لا بـ`build_runner`.
      'ALTER TABLE journal_entries ADD COLUMN created_by INTEGER REFERENCES users(id)',
      // ⚠️ §٦‑٣ — **أثرُ تدقيقِ إعادة فتح الفترة.** نفسُ علّة إخوته أعلاه
      //    حرفاً بحرف: v82 أضافها بـ`ALTER TABLE` في `epoch_3` ولم تُعلَن قطُّ
      //    في صنف `AccountingPeriods`، فهي غائبةٌ عن كلّ قاعدةٍ جديدة.
      //
      //    و`reopenAccountingPeriodWithAudit` يكتب الثلاثةَ بـ`customStatement`
      //    فينهار بـ«no such column: reopen_reason». ولم يظهر العطبُ لأنّه
      //    طريقٌ لم يُوصَل بعد — كامنٌ لا نازف. ووصلُه لاحقاً بلا هذه الأسطر
      //    يُسقط إعادةَ الفتح على **كلّ** تنصيبة، ويترك الفترةَ مغلقةً بلا
      //    بلاغٍ للمستخدم.
      "ALTER TABLE accounting_periods ADD COLUMN reopen_reason TEXT",
      'ALTER TABLE accounting_periods ADD COLUMN reopened_by INTEGER REFERENCES users(id)',
      'ALTER TABLE accounting_periods ADD COLUMN reopened_at INTEGER',
    ]) {
      try {
        await customStatement(stmt);
      } catch (_) {
        // Column/index already exists — safe to ignore
      }
    }

    // ── تمريرة تطابق الجداول — نظير SQLite لـ_ensurePostgresSchemaParity ────
    //
    // جداول مسجّلة في `@DriftDatabase` بس مالهاش `createTable` في أي مايجريشن
    // بتوصل للتركيبة النضيفة عبر `createAll()` وبس — التركيبة المرقّاة عمرها
    // ما بتشوفها. `category_station_mappings` الحالة المؤكَّدة: بيتقري بـSQL
    // خام في `kitchen_dao.dart:364`، وغيابه بيدي `no such table` متبلع في
    // `catch { debugPrint }` فأوامر المطبخ ما بتتطبعش والكاشير مش شايف خطأ.
    //
    // نفس العطل حصل ميدانياً على PostgreSQL في 2026-05-25 (42P01 على كل بيعة)
    // واتقفل بـSpec 130 — بس الإصلاح ده جوه `if (_isPostgres)`، فـSQLite
    // فضلت بلا نظير. التمريرة دي هي النظير.
    //
    // عامة عن قصد مش لجدول بالاسم: أي جدول ينضم لـ`@DriftDatabase` في إصدار
    // جاي من غير مايجريشن بيتغطّى تلقائياً. drift بيولّد
    // `CREATE TABLE IF NOT EXISTS` فالتمريرة no-op على قاعدة سليمة ولا
    // بتلمس صف واحد. كل جدول في try لوحده عشان جدول واحد فاشل ما يوقّفش
    // الباقي.
    final migrator = createMigrator();
    for (final table in allSchemaEntities.whereType<TableInfo>()) {
      try {
        await migrator.createTable(table);
      } catch (e) {
        debugPrint('[SchemaHeal] ${table.actualTableName}: $e');
      }
    }

    // §٦‑٤ — البلاغُ عن قيدٍ ماليٍّ لم يُركَّب. انظر [findBlockedDedupIndexes].
    for (final finding in await findBlockedDedupIndexes()) {
      debugPrint('[DedupGuard] 🔴 $finding');
      unawaited(DiagnosticLogger.log('DEDUP-GUARD', finding));
    }
  }

  /// §٦‑٤ — أيُّ قيدِ تفرّدٍ **ماليٍّ** لم يُركَّب لأنّ البيانات ما زالت مكرّرة.
  ///
  /// فهرسا B1 (دفعاتُ الرواتب) وB2 (يومُ الحضور) يُنشآن في حلقة الشفاء أعلاه
  /// بـ`CREATE UNIQUE INDEX IF NOT EXISTS`، والحلقةُ **تبتلع الفشلَ بصمت**.
  /// فقاعدةٌ فيها تكرارٌ قائمٌ تخرج بلا حماية، ولا أحدَ يعلم.
  ///
  /// ⚠️ **والابتلاعُ مقصودٌ ويبقى** — بقرار المالك 2026-09-02، وبخلاف
  /// `account_mappings` التي تُسوَّى آليّاً: الصفُّ الزائدُ هناك **إعدادٌ**
  /// مكرَّرٌ لا قيمةَ له، وهنا **حركةٌ ماليّة** (دفعةُ راتبٍ أو يومُ حضورٍ
  /// يتحوّل إلى أجر). فحذفُها آليّاً عند الإقلاع يُتلف مالاً بلا مراجعة.
  ///
  /// فالمتغيّرُ هو **الظهور** لا السياسة: الفشلُ الصامتُ صار بلاغاً يحمل
  /// المفاتيحَ المكرّرةَ وعددَها، فيعرف المحاسبُ ما يسوّيه بيده.
  ///
  /// يعيد سطرَ بلاغٍ لكلّ قيدٍ غائب، وقائمةً فارغةً على قاعدةٍ سليمة.
  @visibleForTesting
  Future<List<String>> findBlockedDedupIndexes() async {
    if (_isPostgres) return const [];

    const checks = <({String index, String table, String keys, String what})>[
      (
        index: kSalaryPaymentDedupIndexName,
        table: 'salary_payments',
        keys: 'employee_id, period, type',
        what: 'دفعاتُ الرواتب',
      ),
      (
        index: kAttendanceDayDedupIndexName,
        table: 'employee_attendance',
        keys: 'employee_id, date',
        what: 'أيّامُ الحضور',
      ),
    ];

    final findings = <String>[];
    for (final c in checks) {
      try {
        final exists = await customSelect(
          "SELECT 1 AS x FROM sqlite_master "
          "WHERE type = 'index' AND name = '${c.index}'",
        ).get();
        if (exists.isNotEmpty) continue;

        final dups = await customSelect(
          'SELECT ${c.keys}, COUNT(*) AS n FROM ${c.table} '
          'GROUP BY ${c.keys} HAVING COUNT(*) > 1',
        ).get();

        if (dups.isEmpty) {
          // غائبٌ بلا تكرار — علّةٌ أخرى (جدولٌ ناقصٌ مثلاً)، وتستحقّ بلاغاً
          // كذلك كي لا يُظنَّ القيدُ قائماً.
          findings.add(
            'قيدُ التفرّد "${c.index}" غائبٌ عن ${c.table} بلا تكرارٍ ظاهر — '
            'راجع المخطَّط: ${c.what} بلا حماية.',
          );
          continue;
        }

        final sample = dups.take(5).map((r) {
          final parts = c.keys
              .split(',')
              .map((k) => '${k.trim()}=${r.data[k.trim()]}')
              .join(' · ');
          return '$parts ×${r.data['n']}';
        }).join('  |  ');

        findings.add(
          'قيدُ التفرّد "${c.index}" لم يُركَّب: ${dups.length} مفتاحاً مكرَّراً '
          'في ${c.table} (${c.what}). التسويةُ يدويّةٌ بقرار المالك — '
          'أمثلة: $sample',
        );
      } catch (e) {
        // جدولٌ غيرُ موجودٍ بعد أو خطأُ استعلام — لا يُسقط الإقلاع.
        debugPrint('[DedupGuard] فحصُ ${c.index} تعذّر: $e');
      }
    }
    return findings;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Phase 2b: Database integrity self-heal (PostgreSQL only)
  // ─────────────────────────────────────────────────────────────────────────

  /// Verifies and repairs critical PK / UNIQUE constraints on PostgreSQL.
  ///
  /// Rationale: on some installs the Drift / `drift_postgres` path did not
  /// emit composite primary keys correctly (e.g. `role_permissions` table
  /// without its `(role_id, permission_id)` PK). That broke every
  /// `ON CONFLICT DO NOTHING` statement with PG error 42P10 and silently
  /// allowed duplicate rows. This method:
  ///   1. Dedups any existing rows that would block the constraint.
  ///   2. Adds the expected constraint if missing.
  ///   3. Logs clearly but never throws — missing constraints are repairable,
  ///      not fatal.
  ///
  /// Safe on a healthy schema: every check is a no-op when the constraint
  /// already exists.
  Future<void> _ensureDatabaseIntegrity() async {
    if (!_isPostgres) return;

    Future<bool> hasConstraint(String table, String type) async {
      try {
        final rows = await customSelect(
          "SELECT 1 AS x FROM information_schema.table_constraints "
          "WHERE table_name = '$table' AND constraint_type = '$type' "
          "LIMIT 1",
        ).get();
        return rows.isNotEmpty;
      } catch (e) {
        debugPrint('[Integrity] hasConstraint($table, $type) failed: $e');
        return true; // fail-open: don't attempt to re-add on error
      }
    }

    Future<void> dedupAndAdd(
      String desc,
      String dedupSql,
      String alterSql,
      Future<bool> Function() alreadyExists,
    ) async {
      try {
        if (await alreadyExists()) {
          debugPrint('[Integrity] ✓ $desc already present');
          return;
        }
        // Remove any rows that would violate the constraint before adding it.
        if (dedupSql.isNotEmpty) {
          await customStatement(dedupSql);
        }
        await customStatement(alterSql);
        debugPrint('[Integrity] ✅ $desc added');
      } catch (e) {
        // Never throw — log and move on. Seeder uses bare ON CONFLICT and
        // WHERE NOT EXISTS guards that tolerate a missing constraint.
        debugPrint('[Integrity] ⚠ $desc skipped: $e');
      }
    }

    // 1. role_permissions: composite PK (role_id, permission_id)
    await dedupAndAdd(
      'role_permissions PK (role_id, permission_id)',
      'DELETE FROM role_permissions a USING role_permissions b '
          'WHERE a.ctid < b.ctid '
          'AND a.role_id = b.role_id '
          'AND a.permission_id = b.permission_id',
      'ALTER TABLE role_permissions ADD CONSTRAINT role_permissions_pkey '
          'PRIMARY KEY (role_id, permission_id)',
      () => hasConstraint('role_permissions', 'PRIMARY KEY'),
    );

    // 2. settings: PK (key)
    await dedupAndAdd(
      'settings PK (key)',
      'DELETE FROM settings a USING settings b '
          'WHERE a.ctid < b.ctid AND a.key = b.key',
      'ALTER TABLE settings ADD CONSTRAINT settings_pkey PRIMARY KEY (key)',
      () => hasConstraint('settings', 'PRIMARY KEY'),
    );

    // 3. permissions.code: UNIQUE
    await dedupAndAdd(
      'permissions.code UNIQUE',
      'DELETE FROM permissions a USING permissions b '
          'WHERE a.ctid < b.ctid AND a.code = b.code',
      'ALTER TABLE permissions ADD CONSTRAINT permissions_code_unique '
          'UNIQUE (code)',
      () async {
        // Any UNIQUE or PK on `code` satisfies our needs. drift emits the
        // `.unique()` modifier as a constraint whose name is typically
        // `permissions_code_key`. Detect either form.
        try {
          final rows = await customSelect(
            "SELECT 1 AS x FROM information_schema.table_constraints tc "
            "JOIN information_schema.key_column_usage kcu "
            "  ON tc.constraint_name = kcu.constraint_name "
            " AND tc.table_name = kcu.table_name "
            "WHERE tc.table_name = 'permissions' "
            "  AND kcu.column_name = 'code' "
            "  AND tc.constraint_type IN ('UNIQUE','PRIMARY KEY') "
            "LIMIT 1",
          ).get();
          return rows.isNotEmpty;
        } catch (_) {
          return true;
        }
      },
    );

    // 4. accounts.code: UNIQUE
    // The Dart schema does NOT declare `.unique()` on accounts.code — only a
    // non-unique index. Adding the constraint here prevents duplicate account
    // codes from any source (UI, import, sync). If existing data already has
    // duplicates we log them and leave the constraint off so we don't break
    // the app at startup. Operators can resolve duplicates and restart.
    try {
      final alreadyOnCode = await customSelect(
        "SELECT 1 AS x FROM information_schema.table_constraints tc "
        "JOIN information_schema.key_column_usage kcu "
        "  ON tc.constraint_name = kcu.constraint_name "
        " AND tc.table_name = kcu.table_name "
        "WHERE tc.table_name = 'accounts' "
        "  AND kcu.column_name = 'code' "
        "  AND tc.constraint_type IN ('UNIQUE','PRIMARY KEY') "
        "LIMIT 1",
      ).get();
      if (alreadyOnCode.isNotEmpty) {
        debugPrint('[Integrity] ✓ accounts.code UNIQUE already present');
      } else {
        final dups = await customSelect(
          "SELECT code, COUNT(*) AS n FROM accounts "
          "GROUP BY code HAVING COUNT(*) > 1",
        ).get();
        if (dups.isNotEmpty) {
          debugPrint(
            '[Integrity] ⚠ accounts has ${dups.length} duplicate code(s) — '
            'UNIQUE constraint NOT added. Operator must resolve:',
          );
          for (final d in dups) {
            debugPrint(
              '[Integrity]   code="${d.data['code']}" count=${d.data['n']}',
            );
          }
        } else {
          await customStatement(
            'ALTER TABLE accounts ADD CONSTRAINT accounts_code_unique '
            'UNIQUE (code)',
          );
          debugPrint('[Integrity] ✅ accounts.code UNIQUE added');
        }
      }
    } catch (e) {
      debugPrint('[Integrity] ⚠ accounts.code UNIQUE check skipped: $e');
    }

    // 5. account_mappings: فهرسٌ فريدٌ تعبيريٌّ على (‏purpose، coalesce(cc,0)).
    //
    // ٦‑٣: PG لا يمرُّ بـ`ensureSchemaDefaults` إطلاقاً (تعود مبكّراً على PG)،
    // ولا بهجرات SQLite التي تكتب هذا الفهرس — فبلا هذه الكتلة تبقى **كلُّ**
    // قاعدةِ PostgreSQL بلا القيد. وهو نظيرُ الكتلةِ المضافةِ هناك حرفاً بحرف
    // كي لا تفترق الخلفيّتان.
    //
    // والصيغتان مشتركتان مع مسار SQLite ([kDedupAccountMappingsSql] و
    // [kCreateAccountMappingsPurposeCcIndexSql]) — مصدرٌ واحدٌ لا نسخةٌ ثانية.
    await dedupAndAdd(
      'account_mappings UNIQUE (purpose, coalesce(cost_center_id,0))',
      kDedupAccountMappingsSql,
      kCreateAccountMappingsPurposeCcIndexSql,
      () async {
        // فهرسٌ لا قيدٌ، فلا يظهر في `table_constraints` — والفحصُ على
        // `pg_indexes`.
        try {
          final rows = await customSelect(
            "SELECT 1 AS x FROM pg_indexes "
            "WHERE tablename = 'account_mappings' "
            "  AND indexname = '$kAccountMappingsPurposeCcIndexName' "
            "LIMIT 1",
          ).get();
          return rows.isNotEmpty;
        } catch (_) {
          return true; // fail-open كنظائره أعلاه
        }
      },
    );

    // 6. bank_statement_lines: فهرسٌ فريدٌ على `matched_journal_line_id`.
    //
    // §٣‑٦: نظيرُ السطر المضافِ في `ensureSchemaDefaults` — وPG لا يمرُّ بها
    // إطلاقاً (تعود مبكّراً عليه) ولا بهجرات SQLite، فبلا هذه الكتلة تبقى
    // **كلُّ** قاعدةِ PostgreSQL بلا القيد. والصيغةُ مشتركةٌ من
    // [kCreateBankStatementMatchDedupIndexSql] — مصدرٌ واحدٌ لا نسخةٌ ثانية.
    //
    // ⚠️ **وتسويةٌ فارغة** عن قصد: الصفُّ المزدوجُ حركةٌ ذاتُ قيمةٍ ماليّة،
    // فحذفُه قرارُ محاسبٍ لا قرارُ إقلاع — نفسُ سياسة B1/B2.
    await dedupAndAdd(
      'bank_statement_lines UNIQUE (matched_journal_line_id)',
      '',
      kCreateBankStatementMatchDedupIndexSql,
      () async {
        try {
          final rows = await customSelect(
            "SELECT 1 AS x FROM pg_indexes "
            "WHERE tablename = 'bank_statement_lines' "
            "  AND indexname = '$kBankStatementMatchDedupIndexName' "
            "LIMIT 1",
          ).get();
          return rows.isNotEmpty;
        } catch (_) {
          return true; // fail-open كنظائره أعلاه
        }
      },
    );

    // 7. import_purchase_details: صفٌّ واحدٌ لكلّ فاتورةِ استيراد.
    //
    // المرحلة ٨ — نظيرُ السطر المضافِ في `ensureSchemaDefaults`، وPG لا
    // يمرُّ بها إطلاقاً. والتسويةُ فارغةٌ لأنّ الجدولَ فارغٌ أصلاً: شُحن في
    // v174 وأوّلُ كاتبٍ له هو هذه المرحلة.
    await dedupAndAdd(
      'import_purchase_details UNIQUE (purchase_invoice_id)',
      '',
      kCreateImportPurchaseDetailsUniqueIndexSql,
      () async {
        try {
          final rows = await customSelect(
            "SELECT 1 AS x FROM pg_indexes "
            "WHERE tablename = 'import_purchase_details' "
            "  AND indexname = '$kImportPurchaseDetailsUniqueIndexName' "
            "LIMIT 1",
          ).get();
          return rows.isNotEmpty;
        } catch (_) {
          return true; // fail-open كنظائره أعلاه
        }
      },
    );

    debugPrint('[Integrity] ✅ Phase 2b complete');
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Phase 3: Seed initial data
  // ─────────────────────────────────────────────────────────────────────────

  /// Consolidated seeding: ensures roles, admin user, and initial data exist.
  /// Merges the previous 3 redundant user-checks into a single pass.
  Future<void> _ensureSeedData(bool wasCreated) async {
    // L4 (2026-04-28): In client mode, skip master-data seeding (branches,
    // warehouses, safes, units, categories, accounts, parties) so the first
    // DeltaPull doesn't create duplicates next to the locally-seeded rows.
    // The server is the authoritative source for this data on a paired
    // client. Roles + admin user are still seeded so the cashier can log in
    // before the first sync completes.
    final isClient = await _isClientMode();

    // Step 1: Run full seeder on fresh databases
    if (wasCreated) {
      try {
        if (_isPostgres) {
          await _seedInitialDataPostgres();
        } else {
          await seedInitialData(isClientMode: isClient);
        }
      } catch (e) {
        debugPrint('[Startup] seedInitialData (onCreate): $e');
      }
    }

    // Step 2: Single user-existence check (covers both fresh + repaired DBs)
    bool justSeeded = wasCreated;
    try {
      final allUsers = await select(users).get();
      if (allUsers.isEmpty) {
        debugPrint('[Startup] No users found — running seeder...');
        justSeeded = true;
        try {
          if (_isPostgres) {
            await _seedInitialDataPostgres();
          } else {
            await seedInitialData(isClientMode: isClient);
          }
        } catch (e) {
          // Seeder failed — create admin user as final fallback
          debugPrint('[Startup] Seeder failed, creating admin fallback: $e');
          await _createFallbackAdmin();
        }
      }
    } catch (e) {
      debugPrint('[Startup] user check: $e');
    }

    // Step 2b: Post-seed verification — on a freshly-seeded DB the default
    // 'admin' password MUST work. If it doesn't, the seed wrote a broken
    // row (salt mismatch, silent drift_postgres quirk, partial commit,
    // etc.). Force a raw-SQL reset immediately so the operator is never
    // locked out of a brand-new install. This runs only when we actually
    // seeded in this boot — so a later custom password change is safe.
    if (justSeeded) {
      try {
        final rows = await customSelect(
          "SELECT password_hash, password_salt FROM users WHERE username = 'admin' "
          "ORDER BY id LIMIT 1",
        ).get();
        if (rows.isNotEmpty) {
          final salt = rows.first.data['password_salt']?.toString() ?? '';
          final hash = rows.first.data['password_hash']?.toString() ?? '';
          // Argon2-aware verify. New users get Argon2id hashes (passwordSalt
          // empty, salt embedded in PHC string), so the legacy
          // verifyPassword(...) which assumes PBKDF2 would always report a
          // freshly-seeded admin as "broken" — triggering a reset that
          // undoes the seeder. Use the unified verifier instead.
          final verifyResult = await SecurityService.verifyPasswordFull(
              'admin', salt, hash);
          final ok = verifyResult.verified;
          if (!ok) {
            debugPrint('[Startup] ⚠️ Post-seed verify FAILED — forcing admin/admin reset');
            final newSalt = SecurityService.generateSalt();
            final newHash = await SecurityService.hashPasswordArgon2('admin');
            final boolTrue = sqlBool(true);
            final boolFalse = sqlBool(false);
            await customStatement(
              'UPDATE users SET password_hash = ?, password_salt = ?, '
              'is_active = $boolTrue, is_locked = $boolFalse WHERE username = ?',
              [newHash, newSalt, 'admin'],
            );
            debugPrint('[Startup] ✅ Post-seed admin password reset applied');
          } else {
            debugPrint('[Startup] ✅ Post-seed verify OK — admin/admin works');
          }
        }
      } catch (e) {
        debugPrint('[Startup] post-seed verify failed: $e');
      }
    }

    // Step 3: Ensure all default roles exist (self-healing for older DBs that only
    // have 'مدير النظام' and missed migration v121, or installations where the seeder
    // ran an older version that only inserted the admin role).
    //
    // IMPORTANT: On PostgreSQL we call the atomic seeder (idempotent, ON CONFLICT
    // hardened) instead of the shared `seedRolesAndPermissions()` — the latter
    // uses `InsertMode.insertOrIgnore` which `drift_postgres` does not reliably
    // translate to `ON CONFLICT DO NOTHING` for every case.
    try {
      final roleCount = (await select(roles).get()).length;
      if (roleCount < 5) {
        debugPrint('[Startup] Only $roleCount role(s) found — backfilling default roles via seeder...');
        if (_isPostgres) {
          await seedInitialDataPostgresAtomic();
        } else {
          await seedRolesAndPermissions();
        }
        debugPrint('[Startup] ✅ Default roles backfilled (${(await select(roles).get()).length} total)');
      }
    } catch (e) {
      debugPrint('[Startup] role self-healing: $e');
    }

    // Step 3b: Spec 139 — ensure the rounding-difference account (4319 «فروق
    // تقريب») exists on already-seeded installs. The seeder only runs on a
    // fresh/empty DB, so existing databases would otherwise lack 4319 and the
    // JE writer would fail-closed on the first rounding remainder. `_acct` is
    // idempotent (WHERE NOT EXISTS) and dialect-safe (SQLite + PG), so this is a
    // cheap no-op once present. Skipped in CLIENT mode — accounts are
    // server-authoritative there and arrive via account sync (R8); locally
    // seeding would risk a first-sync duplicate.
    if (!isClient) {
      try {
        await _acct('4319', 'فروق تقريب', 'Rounding Differences', 'revenue',
            'detail', 'credit', 3, '43');
      } catch (e) {
        debugPrint('[Startup] rounding-account (4319) self-heal: $e');
      }
    }

    // Step 3c: Spec 146 (S-MFG-GL) — ensure the applied-overhead account
    // (5138 «تحميل صناعي مطبّق») exists on already-seeded installs, for the same
    // reason as 4319 above: the seeder only runs on a fresh DB, so an existing
    // database would lack 5138 and completing a manufacturing order that carries
    // indirect cost would fail-closed (no credit party). `_acct` is idempotent +
    // dialect-safe; skipped in CLIENT mode (accounts are server-authoritative, R8).
    if (!isClient) {
      try {
        await _acct('5138', 'تحميل صناعي مطبّق', 'Applied Manufacturing Overhead',
            'expense', 'detail', 'credit', 4, '513');
      } catch (e) {
        debugPrint('[Startup] applied-overhead account (5138) self-heal: $e');
      }
    }

    // Step 3d: محطّةُ مطبخٍ افتراضيّةٌ — بلا واحدةٍ لا يعمل KDS إطلاقاً.
    //
    // `kitchen_stations` لا يُبذَر في أيِّ مسار: لا في `seedInitialData` ولا
    // في ترقية. فالسبيلُ الوحيدُ لوجود محطّةٍ هو أن يُنشئها المستخدمُ بيده من
    // شاشة الإعدادات. ومقيسٌ على قاعدةٍ حيّة: صفرُ محطّاتٍ وصفرُ روابط.
    //
    // ويترتّب على ذلك عطلان يبدوان منفصلَين وأصلُهما واحد:
    //   • قسمُ «ربطُ التصنيف بالمحطة» يعرض «أضف محطات أولاً» ولا يرسم قائمةً
    //     منسدلةً أصلاً — فيبدو للمستخدم أن الربط «لا يُحفظ» وهو لم يُعرَض له.
    //   • `getStationForCategory` تسقط دائماً على قيمة الارتداد `'kitchen'`،
    //     فكلُّ أمر تحضيرٍ يُوسَم «مطبخ» — مقيسٌ: ٥ من ٥ على القاعدة الحيّة.
    //     وهي قيمةٌ نصّيّةٌ لا تقابل صفّاً حقيقيّاً، فالنظامُ يشير إلى محطّةٍ
    //     لا وجودَ لها.
    //
    // الشرطُ **خلوُّ الجدول تماماً** لا غيابُ `'kitchen'` بعينها: مَن عرّف
    // محطّاتِه وحذف المطبخَ عمداً لا يُصارَع في قراره. والرمزُ `kitchen`
    // يطابق قيمةَ الارتداد بالضبط فيصير الوسمُ صادقاً بدل أن يكون تخميناً.
    //
    // في الإقلاع لا في ترقية: لا رقمَ مخطّطٍ يُحجَز (وفرعٌ موازٍ يحتاج التالي)،
    // والقواعدُ القائمةُ تُشفى كما تُشفى الجديدة.
    if (!isClient) {
      try {
        final anyStation =
            await (select(kitchenStations)..limit(1)).getSingleOrNull();
        if (anyStation == null) {
          await into(kitchenStations).insert(
            KitchenStationsCompanion.insert(name: 'المطبخ', code: 'kitchen'),
          );
          debugPrint('[Startup] ✅ محطّةُ المطبخ الافتراضيّة أُنشئت');
        }
      } catch (e) {
        debugPrint('[Startup] default kitchen station self-heal: $e');
      }
    }

    // Step 4: Ensure admin has correct roleId (repair broken PG seeds)
    try {
      // limit(1): `roles.name` carries no unique constraint, so duplicate names
      // are a legal state on both dialects. Bare getSingleOrNull is
      // `list.single` → StateError, and the catch below swallows it, so the
      // admin roleId repair would silently never run. Ordered by id so the row
      // we settle on is deterministically the original.
      final adminRole = await (select(roles)
            ..where((r) => r.name.equals('مدير النظام'))
            ..orderBy([(r) => OrderingTerm.asc(r.id)])
            ..limit(1))
          .getSingleOrNull();
      if (adminRole != null) {
        final adminUser = await (select(users)
              ..where((u) => u.username.equals('admin')))
            .getSingleOrNull();
        if (adminUser != null &&
            (adminUser.roleId == null ||
                adminUser.roleId == 0 ||
                adminUser.roleId != adminRole.id)) {
          await (update(users)..where((u) => u.username.equals('admin')))
              .write(UsersCompanion(roleId: Value(adminRole.id)));
          debugPrint(
            '[Startup] ✅ Fixed admin roleId: ${adminUser.roleId} → ${adminRole.id}',
          );
        }
      }
    } catch (e) {
      debugPrint('[Startup] admin roleId fix: $e');
    }

    // Step 4: Self-healing admin password — handles both a broken seed
    // (empty salt/hash) AND a legacy row left by an old buggy seeder that
    // populated salt/hash but with values that don't verify against
    // 'admin'. A sentinel setting `admin_password_customized=true` is
    // written whenever the admin's password is changed through the UI,
    // so that a real customer-chosen password is never overwritten.
    //
    // Writes diagnostic log to Documents/${Brand.dbPrefix}_startup_log.txt AND to
    // a file next to UralCash.exe so the operator can always find it.
    // Uses `customSelect` (not `getSingleOrNull`) so that duplicate admin
    // rows — which *can* happen after a client↔server fullSync with id
    // divergence — don't throw and skip the healing.
    try {
      final adminRows = await customSelect(
        "SELECT id, password_hash, password_salt FROM users WHERE username = 'admin' "
        "ORDER BY id LIMIT 1",
      ).get();
      if (adminRows.isNotEmpty) {
        final row = adminRows.first;
        final storedSalt = row.data['password_salt']?.toString() ?? '';
        final storedHash = row.data['password_hash']?.toString() ?? '';

        // Did the user ever change the admin password from the UI? If yes,
        // the sentinel is 'true' and we MUST NOT overwrite the hash even
        // if 'admin' no longer verifies against it.
        final sentinelRows = await customSelect(
          "SELECT value FROM settings WHERE key = 'admin_password_customized' LIMIT 1",
        ).get();
        final adminPasswordCustomized = sentinelRows.isNotEmpty &&
            sentinelRows.first.data['value']?.toString() == 'true';

        // Does 'admin' still work? If yes, no heal needed.
        final defaultVerifies = storedSalt.isNotEmpty &&
            SecurityService.verifyPassword('admin', storedSalt, storedHash);

        final saltBroken = storedSalt.isEmpty;
        final hashBroken = storedHash.isEmpty;
        // Heal when either the row is obviously broken (empty salt/hash),
        // OR 'admin' fails to verify AND the operator has never set a
        // custom password (sentinel not set). The second branch is what
        // rescues installs stuck behind a buggy old seeder without
        // clobbering real customer-chosen passwords.
        final shouldHeal = saltBroken ||
            hashBroken ||
            (!defaultVerifies && !adminPasswordCustomized);

        final logLines = <String>[
          '--- Admin Password Integrity Check: ${DateTime.now()} ---',
          'salt.length=${storedSalt.length}',
          'hash.length=${storedHash.length}',
          'salt.isEmpty=${storedSalt.isEmpty}',
          'defaultVerifies(admin/admin)=$defaultVerifies',
          'admin_password_customized=$adminPasswordCustomized',
          'shouldHeal=$shouldHeal '
              '(saltBroken=$saltBroken hashBroken=$hashBroken '
              'defaultFail_and_notCustom=${!defaultVerifies && !adminPasswordCustomized})',
        ];

        if (shouldHeal) {
          logLines.add('⚠️ Broken salt/hash — resetting to "admin"...');
          final salt = SecurityService.generateSalt();
          final hash = await SecurityService.hashPasswordArgon2('admin');

          // Use RAW SQL to bypass any Drift companion issues.
          // IMPORTANT: `is_active = 1` is SQLite syntax — on PostgreSQL the
          // column is BOOLEAN and rejects integer literals, which used to
          // silently abort the self-heal and leave the password broken.
          // Use sqlBool() so the same statement works on both backends.
          final boolTrue = sqlBool(true);
          await customStatement(
            'UPDATE users SET password_hash = ?, password_salt = ?, is_active = $boolTrue WHERE username = ?',
            [hash, salt, 'admin'],
          );
          logLines.add('Wrote via raw SQL: hash.len=${hash.length}, salt.len=${salt.length}');

          // READ BACK and verify — customSelect keeps this duplicate-safe.
          final readBackRows = await customSelect(
            "SELECT password_hash, password_salt FROM users WHERE username = 'admin' "
            "ORDER BY id LIMIT 1",
          ).get();
          if (readBackRows.isNotEmpty) {
            final rb = readBackRows.first;
            final rbSalt = rb.data['password_salt']?.toString() ?? '';
            final rbHash = rb.data['password_hash']?.toString() ?? '';
            final readBackOk = rbSalt.isNotEmpty &&
                SecurityService.verifyPassword('admin', rbSalt, rbHash);
            logLines.add('READ-BACK: salt.len=${rbSalt.length}, hash.len=${rbHash.length}');
            logLines.add('READ-BACK verify=$readBackOk');
            if (!readBackOk) {
              logLines.add('❌ CRITICAL: Write succeeded but read-back verification FAILED!');
              logLines.add('READ-BACK salt="${rbSalt.substring(0, rbSalt.length.clamp(0, 8))}..."');
              logLines.add('EXPECTED salt="${salt.substring(0, salt.length.clamp(0, 8))}..."');
            }
          } else {
            logLines.add('❌ CRITICAL: Could not read back admin user after update!');
          }
        } else {
          logLines.add(defaultVerifies
              ? '✅ admin/admin works — no action needed'
              : 'ℹ️ admin_password_customized=true — preserving custom password');
        }

        // Write log to TWO locations so the operator can always find it:
        //   1. %USERPROFILE%\Documents\${Brand.dbPrefix}_startup_log.txt  (standard)
        //   2. <exe dir>\${Brand.dbPrefix}_startup_log.txt  (fallback — always writable)
        final logBody = '${logLines.join('\n')}\n\n';
        try {
          final logDir = await getApplicationDocumentsDirectory();
          final logFile = File('${logDir.path}/${Brand.dbPrefix}_startup_log.txt');
          await logFile.writeAsString(logBody, mode: FileMode.append);
        } catch (e) { debugPrint('[Startup] Documents log write failed: $e'); }
        try {
          final exeDir = File(Platform.resolvedExecutable).parent.path;
          final sep = Platform.pathSeparator;
          final logFile2 = File('$exeDir$sep${Brand.dbPrefix}_startup_log.txt');
          await logFile2.writeAsString(logBody, mode: FileMode.append);
        } catch (e) { debugPrint('[Startup] exe-dir log write failed: $e'); }
        for (final line in logLines) {
          debugPrint('[Startup] $line');
        }
      }
    } catch (e) {
      debugPrint('[Startup] admin password integrity check: $e');
    }

    // Step 5: Ensure an open fiscal year covering today exists.
    // createJournalEntry() calls validateFinancialPeriod() which throws if no
    // open year covers DateTime.now() — silently killing every auto-post.
    // This is a self-healing measure; operators should create FY via the UI.
    try {
      final today = DateTime.now();
      final existingFY = await getFiscalYearByDate(today);
      if (existingFY == null) {
        debugPrint('[Startup] No fiscal year covering $today — auto-creating...');
        final fyStart = DateTime(today.year, 1, 1);
        final fyEnd   = DateTime(today.year, 12, 31, 23, 59, 59);
        final fyId = await createFiscalYear(
          name: 'السنة المالية ${today.year}',
          startDate: fyStart,
          endDate: fyEnd,
        );
        try {
          await generatePeriodsForYear(fyId, fyStart, fyEnd);
        } catch (e) {
          // Periods may partially exist ({month, year} unique constraint) — safe
          debugPrint('[Startup] generatePeriodsForYear partial: $e');
        }
        debugPrint('[Startup] ✅ Fiscal year ${today.year} auto-created (id=$fyId)');
      } else {
        debugPrint('[Startup] Fiscal year OK: "${existingFY.name}" (closed=${existingFY.isClosed})');
      }
    } catch (e) {
      debugPrint('[Startup] ensureOpenFiscalYear: $e');
    }

    // Step 6: Repair delivered invoices that are missing their GL journal entry.
    // Handles power-loss / crash scenarios where stock was moved but JE was not posted.
    try {
      final repaired = await repairFailedDeliveryAutoposts();
      if (repaired > 0) {
        debugPrint('[Startup] ✅ Autopost repair completed — $repaired orphaned JE(s) recovered');
      }
    } catch (e) {
      debugPrint('[Startup] repairFailedDeliveryAutoposts: $e');
    }

    // Step 6b: والمسحُ الأعمّ — كلُّ فاتورةِ بيعٍ أو شراءٍ بلا قيدٍ آليّ،
    // لا المُسلَّمةَ وحدَها.
    //
    // الإصلاحُ أعلاه يغطّي مسارَ التسليم فقط، بينما الفاتورةُ قد تفقد
    // قيدَها لأسبابٍ أخرى (انقطاعُ تيّارٍ أثناء الحفظ، فشلُ ترحيلٍ صامت،
    // استيرادٌ قديم). و`repairAllMissingInvoiceJEs` كان موجوداً ومختبَراً
    // لكنّ **لا شيءَ يناديه** إلا زرٌّ في حوار إعدادات المشرف — فمن لا
    // يعرف الزرَّ تبقى دفاترُه ناقصةً بلا أن ينطق شيء، والميزانيةُ لا
    // تتزن ولا سببَ ظاهر.
    //
    // آمنٌ كلَّ إقلاع: العمليّةُ **متعادلة** (`hasAutoPostEntry` يقصّر
    // الطريقَ لأيّ فاتورةٍ لها قيدٌ فعلاً)، وهي في الطورِ المؤجَّل بعد
    // ظهور الواجهة فلا تؤخّر الإقلاع.
    try {
      final c = await repairAllMissingInvoiceJEs();
      final repaired =
          (c['salesRepaired'] ?? 0) + (c['purchasesRepaired'] ?? 0);
      final failed = (c['salesFailed'] ?? 0) + (c['purchasesFailed'] ?? 0);
      if (repaired > 0 || failed > 0) {
        debugPrint('[Startup] ✅ Invoice-JE repair — أُصلح $repaired · '
            'فشل $failed · مُسح ${c['totalScanned'] ?? 0}');
      }
    } catch (e) {
      debugPrint('[Startup] repairAllMissingInvoiceJEs: $e');
    }

    // §٥-٢ ذيلٌ (‏بلاغٌ ميدانيّ 2026-08-12): قالبُ `shift_closing` الأقدمُ
    // من الإصلاح لا يعرف قناةَ «كليك»، والبذرةُ تتخطّى ما هو موجود
    // (`!existingTypes.contains(...)`). فالمطبوعُ يعرض قناتَين ويطبع
    // إجمالياً يجمع الثلاث — القارئُ يجمع ٤٠ ويرى ٥٥ فيتّهم الحساب.
    //
    // ومكانُه هنا لا في `seedDefaultTemplates`: منادِيها الوحيدُ شاشةُ
    // مصمّم الفواتير، فمن لا يفتحها لا يصله الإصلاح — نفسُ فئة العطب التي
    // كُتب لها `startup_repairs_wired_test`.
    //
    // متعادلٌ: ما وُجد يُترك، وقالبٌ كاملٌ لا يُمَسّ.
    try {
      // إعادةُ البناء أوّلاً: قالبٌ أُعيد بناؤه صار مطابقاً للبذرة، فلا يجد
      // الإصلاحُ التالي فيه ما يُصلح. والعكسُ كان سيرقّع ثم يهدم.
      final reset = await resetShiftClosingTemplateToSeed();
      if (reset) {
        await DiagnosticLogger.log('TEMPLATE',
            'shift_closing أُعيد بناؤه بالترتيب المبذور (مرّة واحدة)');
      }
      final n = await backfillShiftClosingChannelElements();
      if (n > 0) {
        await DiagnosticLogger.log(
            'TEMPLATE', 'shift_closing — أُصلح $n عنصرَ تسوية');
      }
    } catch (e) {
      debugPrint('[Startup] shift_closing template repair: $e');
    }

    // الخيار (ب) 2026-08-12: المطبوعُ يحترم تخطيطَ القالب، وجدولُ الأصناف كان
    // الوحيدَ بلا موضعٍ فيه — يُقحمه المُصيِّرُ استدلالاً. فالمالكُ يحرّكه في
    // المصمّم ولا يُحفَظ له أثر.
    //
    // ومكانُه هنا لا في `seedDefaultTemplates`: مناديها الوحيدُ شاشةُ المصمّم،
    // ثم هي مشروطةٌ بـ`!existingTypes.contains(...)` فلا ترى قاعدةً قائمة.
    //
    // ولا ينقلب مطبوع: العنصرُ يُولد حيث كان الاستدلالُ يُقحم الجدولَ بالضبط.
    try {
      final n = await backfillItemsTableElements();
      if (n > 0) {
        await DiagnosticLogger.log(
            'TEMPLATE', 'أُلحق عنصرُ جدول الأصناف بـ$n قالباً');
      }
    } catch (e) {
      debugPrint('[Startup] items_table element backfill: $e');
    }

    // بلاغُ المالك 2026-08-12: «تصميمي مش بيوصل للورقة» على A4.
    // `getDefaultTemplateByCategory` يشترط تطابقَ النوع **والفئة**، والبذرةُ
    // القديمةُ لم تكتب فئةً فأخذت `'receipt'` بينما المنادي يسأل `'invoice'`.
    // فيسقط التنفيذُ صامتاً إلى المولّد المكتوب في الكود.
    //
    // ونظيرُه في المشتريات، وفي المطبخ حيث يفتح المصمّمُ التذكرةَ بأقسام
    // الإيصال لأنه يتفرّع على الفئة لا النوع.
    try {
      final n = await repairTemplateCategories();
      if (n > 0) {
        await DiagnosticLogger.log(
            'TEMPLATE', 'صُحّحت فئةُ $n قالباً — التصميمُ يصل الورقةَ الآن');
      }
    } catch (e) {
      debugPrint('[Startup] template category repair: $e');
    }

    // §٤‑٦ — نسبةُ الضريبة كانت مخبوزةً نصّاً في تسمية سطر الإجمالي بسبعةِ
    // قوالب. أُصلحت الأصولُ، لكنّها تُقرأ عند الاستيراد لا عند كلِّ إقلاع —
    // فنسخةٌ استُوردت قبل الإصلاح تبقى تطبع نسبةً كاذبة (‏`١٤٪` تصل الورقةَ
    // `٤١٪` فعلاً — الأرقامُ الهنديّةُ تنعكس عند الرسم).
    try {
      final n = await repairHardcodedTaxRateLabels();
      if (n > 0) {
        await DiagnosticLogger.log('TEMPLATE',
            'نُزعت نسبةُ الضريبة المخبوزةُ من $n تسميةً — النسبةُ من الصنف');
      }
    } catch (e) {
      debugPrint('[Startup] tax rate label repair: $e');
    }

    // Step 7: Spec 136 ISS-2 — backfill deterministic globalIds on seeded
    // master-data defaults that still carry a NULL globalId (pre-globalId
    // upgraded installs, e.g. fiscal_years created before createFiscalYear
    // set a gid). Idempotent + NULL-only; runs every boot on BOTH SQLite and
    // PostgreSQL (onUpgrade is skipped on PG, so this can't live in a
    // migration). See _backfillDeterministicMasterGids.
    try {
      await _backfillDeterministicMasterGids();
    } catch (e) {
      debugPrint('[Startup] backfillDeterministicMasterGids: $e');
    }
  }

  /// Spec 136 ISS-2 — idempotent, NULL-only backfill of deterministic
  /// globalIds on seeded master-data defaults.
  ///
  /// Pre-fix, master rows created by an older build (before the seeders minted
  /// gids) carry `global_id = NULL` on BOTH the server and the client, so the
  /// sync layer's Tier-1 globalId match can never fire and it falls back to
  /// name matching forever (the field SYNC-WARN lines). This backfill makes
  /// both sides derive the SAME deterministic gid from a stable identity, so
  /// the next sync converges on Tier-1.
  ///
  /// Safety contract:
  ///  - **NULL-only**: never overwrites an existing gid (Spec 132 FR-011
  ///    immutability). Rows with a gid — even a divergent one — are untouched;
  ///    those converge via the sync push-down + the postBranch dedup fix.
  ///  - **Canonical-identity-scoped**: only rows flagged `is_system_default`
  ///    (or, for fiscal_years, matched by the same natural key the sync uses)
  ///    are eligible. A renamed default keeps NULL and the existing name
  ///    fallback (no regression).
  ///  - **Collision-guarded**: if the target gid is already held by another
  ///    row (e.g. two NULL rows for one identity), the second is skipped so
  ///    the UNIQUE(global_id) constraint is never violated.
  ///  - Runs on every boot; once a row is healed the NULL filter makes it a
  ///    no-op, so the steady-state cost is one cheap scan per master table.
  Future<void> _backfillDeterministicMasterGids() async {
    var healed = 0;

    // Assign [gid] to row [id] in [table] iff that gid is free. Returns true
    // when a row was actually updated. `?` placeholders work on both SQLite
    // and drift_postgres (see the admin-reset UPDATE above).
    Future<bool> assign(String table, int id, String gid) async {
      final taken = await customSelect(
        'SELECT 1 FROM $table WHERE global_id = ? LIMIT 1',
        variables: [Variable<String>(gid)],
      ).getSingleOrNull();
      if (taken != null) {
        await DiagnosticLogger.log(
          'GID-BACKFILL',
          'skip $table id=$id — target gid already claimed by another row',
        );
        return false;
      }
      await customStatement(
        'UPDATE $table SET global_id = ? WHERE id = ? AND global_id IS NULL',
        [gid, id],
      );
      return true;
    }

    // fiscal_years — the concrete NULL/NULL field win. Keyed by the
    // (name + start + end) natural key the FiscalYearSyncStrategy matches on.
    final fyNull =
        await (select(fiscalYears)..where((f) => f.globalId.isNull())).get();
    for (final fy in fyNull) {
      final gid = UuidV7.deriveFiscalYearGlobalId(
          name: fy.name, startDate: fy.startDate, endDate: fy.endDate);
      if (await assign('fiscal_years', fy.id, gid)) healed++;
    }

    // branches — seeded main branch (is_system_default), keyed by seed name.
    final brNull = await (select(branches)
          ..where((b) => b.globalId.isNull() & b.isSystemDefault.equals(true)))
        .get();
    for (final b in brNull) {
      final gid =
          UuidV7.deriveSeedGlobalId(table: 'branches', seedKey: b.name);
      if (await assign('branches', b.id, gid)) healed++;
    }

    // warehouses — seeded main warehouse, keyed by seed name.
    final whNull = await (select(warehouses)
          ..where((w) => w.globalId.isNull() & w.isSystemDefault.equals(true)))
        .get();
    for (final w in whNull) {
      final gid =
          UuidV7.deriveSeedGlobalId(table: 'warehouses', seedKey: w.name);
      if (await assign('warehouses', w.id, gid)) healed++;
    }

    // categories — seeded default category, keyed by seed name.
    final catNull = await (select(categories)
          ..where((c) => c.globalId.isNull() & c.isSystemDefault.equals(true)))
        .get();
    for (final c in catNull) {
      final gid =
          UuidV7.deriveSeedGlobalId(table: 'categories', seedKey: c.name);
      if (await assign('categories', c.id, gid)) healed++;
    }

    // units — seeded default units, keyed by seed name.
    final unitNull = await (select(units)
          ..where((u) => u.globalId.isNull() & u.isSystemDefault.equals(true)))
        .get();
    for (final u in unitNull) {
      final gid = UuidV7.deriveSeedGlobalId(table: 'units', seedKey: u.name);
      if (await assign('units', u.id, gid)) healed++;
    }

    // safes — seeded default safes, keyed by stable safeType.
    final safeNull = await (select(safes)
          ..where((s) => s.globalId.isNull() & s.isSystemDefault.equals(true)))
        .get();
    for (final s in safeNull) {
      final gid =
          UuidV7.deriveSeedGlobalId(table: 'safes', seedKey: s.safeType);
      if (await assign('safes', s.id, gid)) healed++;
    }

    // parties — seeded delivery companies, keyed by stable priceLevel.
    final partyNull = await (select(parties)
          ..where((p) =>
              p.globalId.isNull() & p.isSystemDefault.equals(true)))
        .get();
    for (final p in partyNull) {
      final gid = UuidV7.deriveSeedGlobalId(
          table: 'parties', seedKey: 'delivery:${p.priceLevel}');
      if (await assign('parties', p.id, gid)) healed++;
    }

    if (healed > 0) {
      await DiagnosticLogger.log(
        'GID-BACKFILL',
        'healed=$healed deterministic master globalId(s) on NULL rows',
      );
      debugPrint('[Startup] ✅ GID-BACKFILL healed=$healed master gid(s)');
    }
  }

  /// Verify and heal the PostgreSQL baseline.
  ///
  /// The atomic seeder in `database_seeder_postgres.dart` is idempotent —
  /// every helper checks for existence first and only inserts what's
  /// missing. This method calls `verifyPostgresBaseline()` and, if anything
  /// is below the required minimums, re-runs the seeder to backfill.
  ///
  /// This is the rescue path for users who installed an earlier build where
  /// seeding failed silently and ended up with only `roles` + `users`.
  Future<void> _verifyAndHealPostgresBaseline() async {
    try {
      final check = await verifyPostgresBaseline();
      if (check.ok) {
        debugPrint('[Startup] ✅ PG baseline OK: ${check.counts}');
        return;
      }

      debugPrint(
        '[Startup] ⚠ PG baseline incomplete — missing: ${check.missing}. '
        'Running idempotent seeder to backfill...',
      );
      final result = await seedInitialDataPostgresAtomic();
      debugPrint('[Startup] ✅ PG baseline backfilled: ${result.toMap()}');

      // Re-verify so the log makes it clear whether healing actually worked.
      final recheck = await verifyPostgresBaseline();
      if (recheck.ok) {
        debugPrint('[Startup] ✅ PG baseline now complete');
      } else {
        debugPrint(
          '[Startup] ❌ PG baseline STILL incomplete after heal — missing: '
          '${recheck.missing}. Manual intervention required.',
        );
      }
    } catch (e, st) {
      debugPrint('[Startup] _verifyAndHealPostgresBaseline failed: $e\n$st');
    }
  }

  /// Last-resort admin creation when all seeders fail.
  Future<void> _createFallbackAdmin() async {
    try {
      // limit(1): same class as Step 4 above — `roles.name` is not unique, and
      // this is the last-resort admin path, so a StateError here leaves the
      // install with no usable admin at all.
      final adminRole = await (select(roles)
            ..where((r) => r.name.equals('مدير النظام'))
            ..orderBy([(r) => OrderingTerm.asc(r.id)])
            ..limit(1))
          .getSingleOrNull();
      final salt = SecurityService.generateSalt();
      final hash = await SecurityService.hashPasswordArgon2('admin');
      await into(users).insert(
        UsersCompanion.insert(
          username: 'admin',
          passwordHash: hash,
          displayName: 'مدير النظام',
        ).copyWith(
          passwordSalt: Value(salt),
          createdAt: Value(DateTime.now()),
          roleId: Value(adminRole?.id ?? 1),
          // UUID-First (Phase 1): stable cross-install identity for sync.
          globalId: Value(UuidV7.generate()),
        ),
      );
      debugPrint(
        '[Startup] ✅ Admin user created via fallback with roleId=${adminRole?.id}',
      );
    } catch (e) {
      debugPrint('[Startup] admin fallback creation failed: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Phase 4: Permissions & accounts sync
  // ─────────────────────────────────────────────────────────────────────────

  /// Sync all code-defined permissions to the database and ensure
  /// default chart of accounts entries exist with correct Arabic names.
  ///
  /// CRITICAL: Skip local permission seeding in CLIENT mode.
  ///
  /// Why this matters:
  ///   - `syncAllPermissions()` inserts every code from `PermissionCodes.masterList`
  ///     into the local `permissions` table with auto-increment IDs.
  ///   - The `permissions.code` column has a UNIQUE constraint.
  ///   - Later, when `PermissionSyncStrategy` pulls from the server, it tries
  ///     to INSERT each permission with the SERVER's id. The UNIQUE on `code`
  ///     blocks that insert (the code is already locked to a local id), so
  ///     the row is silently skipped — leaving the client with permissions
  ///     that have DIFFERENT IDs than the server.
  ///   - `RolePermissionSyncStrategy` then receives `{role_id, permission_id}`
  ///     mappings using the server's IDs and can't match them locally —
  ///     dropping critical permissions like pos_save from the cashier's role.
  ///
  /// Solution: in client mode, the server is the single source of truth.
  /// We rely entirely on `PermissionSyncStrategy.syncFromJson` to populate
  /// the permissions table with the server's authoritative IDs.
  Future<void> _syncPermissionsAndAccounts() async {
    // Detect client mode without importing NetworkService here (which would
    // create a layering violation: data layer importing services). Instead,
    // we read the persisted network mode setting directly.
    final isClient = await _isClientMode();

    if (isClient) {
      debugPrint('[Startup] Client mode — SKIPPING local permission seeding. '
          'Permissions will be pulled from the server with authoritative IDs '
          'via PermissionSyncStrategy on first login.');
    } else {
      try {
        await syncAllPermissions();
      } catch (e) {
        debugPrint('[Startup] syncAllPermissions: $e');
      }

      // Spec 084b — self-heal startup grant.
      //
      // Matrix updates (Spec 077/078/084 onward) only land for existing
      // installs when the operator clicks "منح الصلاحيات الافتراضية" in
      // Settings. Field smoke 2026-05-17 confirmed operators don't know
      // to click after every upgrade — Spec 084 added `sales_create` to
      // the cashier role but the cashier kept hitting 403 until the
      // operator manually toggled it.
      //
      // `grantMissingDefaults()` is INSERT-OR-IGNORE on top of the
      // matrix, so running it on every server-mode boot is safe and
      // idempotent. First boot post-upgrade applies the missing grants;
      // subsequent boots find nothing to do and return 0. The whole
      // call is wrapped in try/catch — a failure here MUST NOT block
      // app startup (matches the pattern around syncAllPermissions/
      // syncDefaultAccounts above).
      //
      // Skipped in client mode because the server is authoritative for
      // role_permissions — the mirror pulls them and any client-side
      // grant would diverge.
      // ⚠️ `…Once` لا `grantMissingDefaults` العارية: العاريةُ تُدرج كلَّ ما
      // تمنحه المصفوفةُ وينقص الدور، فكانت تُعيد في كلّ إقلاعٍ ما نزعه
      // المشغّلُ من شاشة الصلاحيات — «حدّدتُ صلاحيات الكاشير، خرجتُ ودخلتُ،
      // فوجدتُها كما كانت» (بلاغٌ ميدانيّ 2026-08-11). والتسييجُ ببصمة
      // المصفوفة لا بعلَمٍ أعمى، كي تبقى ترقياتُ المصفوفة تصل تلقائياً.
      //
      // (‏والتعليقُ فوق `try` قصداً: حارسُ `spec_084b_self_heal_startup_test`
      // يشترط `try {` في نافذةٍ قصيرةٍ قبل النداء، ويقيس بذلك أن الإصلاحَ
      // غيرُ قاتلٍ للإقلاع.)
      try {
        final inserted =
            await RoleGrantPreflightService(this).grantMissingDefaultsOnce();
        if (inserted > 0) {
          await DiagnosticLogger.log(
            'GRANT-SELFHEAL',
            'applied $inserted missing matrix grants on startup '
                '(spec 084b)',
          );
        }
      } catch (e) {
        debugPrint('[Startup] grantMissingDefaults self-heal failed: $e');
      }
    }

    // L4 (2026-04-28): same logic as permissions — in client mode the server
    // is authoritative for the chart of accounts. Local seeding would create
    // duplicates against the server's accounts after the first DeltaPull.
    if (isClient) {
      debugPrint('[Startup] Client mode — SKIPPING local accounts seeding '
          '(server is authoritative).');
    } else {
      try {
        await accountingDao.syncDefaultAccounts();
      } catch (e) {
        debugPrint('[Startup] syncDefaultAccounts: $e');
      }

      // حسابٌ فرعيٌّ لكلّ خزنة تحت أب الخزائن (`1110` أو `111`).
      //
      // خزنةٌ بلا `linkedAccountId` تسقط بحسب **نوعها** على حسابٍ مشترك
      // (`kSafeTypeAccountCode`: cash→1111)، فدرجُ الكاشير والصندوقُ
      // المركزيُّ يترحّلان على رقمٍ واحدٍ لا ينفصل في الأستاذ، ولا سبيلَ
      // لمطابقة رصيد خزنةٍ بعينها مع الدفاتر.
      //
      // و`createSafeWithLinkedAccount` تفعل الصوابَ منذ v142، لكنّ **البذرة**
      // لا تمرّ بها: `database_seeder.dart` يُدرج الخزائنَ الافتراضية بإدراجٍ
      // عارٍ بلا ربط — فكلُّ تنصيبٍ جديدٍ يولد بالعطب كاملاً.
      //
      // ⚠️ **بعد** `syncDefaultAccounts` قصداً: الإصلاحُ ينصرف صامتاً حين لا
      // يجد أبَ الخزائن، فوضعُه قبل بذر الدليل كان يجعله لا يفعل شيئاً على
      // أوّل إقلاعٍ — وهو الإقلاعُ الوحيدُ الذي يحتاجه تنصيبٌ جديد.
      //
      // وداخلَ فرع «لا عميل» قصداً كذلك: في وضع العميل السيرفرُ صاحبُ
      // الدليل، وإنشاءُ حساباتٍ محليةٍ هنا يزدوج مع نسخته بعد أوّل سحب —
      // نفسُ سبب تخطّي بذر الحسابات فوق.
      //
      // 🔴 و`…Once` لا الإصلاحُ العاري (‏قرارُ المالك 2026-08-11): شاشةُ إدارة
      // الصناديق فيها منتقي «الحساب المرتبط» **اختيارياً** يسمح بـ«بدون»، فهي
      // صاحبةُ القرار بعد أوّل إقلاع. وإصلاحٌ يعمل كلَّ إقلاعٍ كان يدوس فكَّ
      // الربط ويخلّف حساباً يتيماً في الدليل مع كلّ مسح. التفصيلُ عند الغلاف.
      try {
        final linked = await linkUnlinkedSafesToSubAccountsOnce();
        if (linked > 0) {
          debugPrint('[Startup] ✅ ربطُ الخزائن بالحسابات — $linked خزنة');
        }
      } catch (e) {
        debugPrint('[Startup] linkUnlinkedSafesToSubAccountsOnce: $e');
      }
    }
  }

  /// Read the persisted network mode without importing services layer.
  /// Returns true if the app was previously configured as a client OR
  /// mirror node — both pull master data from an authoritative server,
  /// so neither should run the local seeder for branches / warehouses
  /// / safes / units / categories / accounts / parties.
  ///
  /// Cluster 029 / Mirror branch dup: the previous version returned
  /// `true` only for `'client'`, so a mirror device ran the seeder at
  /// boot and inserted a default "الفرع الرئيسي" id=1. After the
  /// admin renamed the server's branch to "الإدارة", the mirror's
  /// first sync couldn't deduplicate — Tier 1 (globalId) missed
  /// because the local seed had a locally-minted globalId, Tier 2
  /// (name) missed because the names differed, leaving two rows in
  /// the branches list (the local seed AND the renamed server branch
  /// pulled fresh). Mirror now skips the seed exactly the same way
  /// client does (ENGINEERING_GUIDELINES.md R8 — server is the source of truth).
  Future<bool> _isClientMode() async {
    try {
      final v = await getSettingValue('network_mode');
      return v == 'client' || v == 'mirror';
    } catch (_) {
      return false;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Phase 5: One-time data patches
  // ─────────────────────────────────────────────────────────────────────────

  /// Run retroactive data fixes. These are idempotent operations that
  /// correct historical data issues.
  Future<void> _runStartupPatches() async {
    // SECURITY/STABILITY: Clean up invalid Date/Time strings injected by legacy
    // sync logic or manual backend DB edits. Drift crashes when it tries to cast
    // a text string as an integer unix epoch. C-PERF-1: one-shot — see method.
    await fixLegacyDateTimeStrings();

    // FIX: Retroactively post unposted auto-generated entries
    try {
      await accountingDao.fixUnpostedAutoEntries();
    } catch (e) {
      debugPrint('[Startup] fixUnpostedAutoEntries: $e');
    }

    // FIX: Backfill cost center IDs from journal entry headers to lines.
    // Ensures financial report filters by cost center/branch show all data.
    try {
      await accountingDao.remediateHistoricalCostCenters();
    } catch (e) {
      debugPrint('[Startup] remediateHistoricalCostCenters: $e');
    }

    // PIR-09: Force-migrate all legacy plaintext PINs to secure hash
    try {
      await migrateLegacyPlaintextPins();
    } catch (e) {
      debugPrint('[Startup] migrateLegacyPlaintextPins: $e');
    }

    // FIX: Retroactively patch old stock movements with zero unit_cost.
    // C-PERF-2: one-shot — see method.
    await backfillStockMovementUnitCost();

    // EXP-1: re-point expense categories still on the legacy (never-seeded)
    // '5299' account code to '6214' so their expenses reach the GL/P&L.
    // One-shot, server/standalone-only — see method.
    try {
      await backfillLegacyExpenseCategoryAccountCode();
    } catch (e) {
      debugPrint('[Startup] backfillLegacyExpenseCategoryAccountCode: $e');
    }

    // FIX: Settings table may have duplicate rows for the same key (legacy
    // sync conflict or pre-PK data), causing getSingleOrNull() to throw
    // "Bad state: Too many elements". Collapse duplicates, keeping the row
    // with the non-null / longest value as the winner.
    if (!_isPostgres) {
      try {
        await customStatement('''
          DELETE FROM settings
          WHERE rowid NOT IN (
            SELECT MIN(rowid) FROM settings GROUP BY key
          )
        ''');
        debugPrint('[Startup] Settings duplicates removed (SQLite)');
      } catch (e) {
        debugPrint('[Startup] settingsDedup: $e');
      }
    } else {
      try {
        await customStatement('''
          DELETE FROM settings a
          USING settings b
          WHERE a.ctid < b.ctid AND a.key = b.key
        ''');
        debugPrint('[Startup] Settings duplicates removed (PostgreSQL)');
      } catch (e) {
        debugPrint('[Startup] settingsDedup PG: $e');
      }
    }

    // PERF: Index to speed up `getReturnedQuantitiesForInvoice` — the sales
    // returns invoice picker was doing a full-table scan on stock_movements
    // for each item of the selected invoice (N+1 × O(table-size)) which
    // froze the UI for 5-100+ seconds on medium/large databases. This
    // composite index makes the query O(log n).
    try {
      await customStatement('''
        CREATE INDEX IF NOT EXISTS idx_stock_movements_returns_lookup
        ON stock_movements (reference_type, reference_id, movement_type, product_id)
      ''');
      debugPrint('[Startup] Returns-lookup index ensured on stock_movements');
    } catch (e) {
      debugPrint('[Startup] stockMovementsIndex: $e');
    }
  }

  /// C-PERF-1 + F-DB-1: repair text-typed date columns so Drift's int cast can't
  /// crash the boot. Originally 8×6 = 48 full-table UPDATEs on EVERY boot. The
  /// maintenance made it a permanent one-shot flag, which disabled the guard
  /// forever after the first clean boot — a text date injected later (e.g. a
  /// manual backend DB edit) then re-crashed boot with no self-heal. Now: a
  /// cheap per-table detection probe runs every boot (one LIMIT-1 scan per
  /// table, ~6× cheaper than the old per-column UPDATEs), and the expensive
  /// per-column repair only fires for a table that actually holds a text date.
  /// Keeps the fast clean common case AND restores the corruption self-heal.
  /// Returns rows fixed. Table/column names are hardcoded constants (no user
  /// input) so the string-built SQL is injection-safe.
  Future<int> fixLegacyDateTimeStrings() async {
    if (_isPostgres) return -1;
    const tables = [
      'products', 'categories', 'parties', 'sales_invoices',
      'purchase_invoices', 'stock_movements', 'table_orders', 'users'
    ];
    const candidateCols = [
      'created_at', 'updated_at', 'deleted_at',
      'invoice_date', 'order_date', 'payment_date'
    ];
    int fixed = 0;
    for (final t in tables) {
      // Which candidate date columns actually exist on this table.
      List<String> cols;
      try {
        final info =
            await customSelect("SELECT name FROM pragma_table_info('$t')").get();
        final present = info.map((r) => r.data['name'] as String).toSet();
        cols = candidateCols.where(present.contains).toList();
      } catch (e) {
        debugPrint('[Startup] fixDateTime pragma $t (safe-skip): $e');
        continue;
      }
      if (cols.isEmpty) continue;
      // Cheap probe: does ANY of this table's date columns hold a text value?
      final orClause = cols.map((c) => "typeof($c) = 'text'").join(' OR ');
      bool hasText;
      try {
        final hit =
            await customSelect('SELECT 1 FROM $t WHERE $orClause LIMIT 1').get();
        hasText = hit.isNotEmpty;
      } catch (e) {
        debugPrint('[Startup] fixDateTime probe $t (safe-skip): $e');
        continue;
      }
      if (!hasText) continue; // fast path — clean table, no repair scan needed
      // Repair only the tripped table's columns.
      for (final col in cols) {
        try {
          fixed += await customUpdate(
            "UPDATE $t SET $col = CAST(strftime('%s','now') AS INTEGER) "
            "WHERE typeof($col) = 'text'",
            updates: {},
          );
        } catch (e) {
          debugPrint('[Startup] fixDateTime $t.$col (safe-skip): $e');
        }
      }
    }
    return fixed;
  }

  /// C-PERF-2: backfill historical `stock_movements.unit_cost = 0/null` from
  /// `products.cost_price`. One-shot: the WHERE only matches rows that can
  /// actually be improved (product has a positive cost), so once none remain
  /// the `startup_unit_cost_backfill_done` flag is set and later boots skip it.
  /// Returns rows fixed, or -1 when skipped.
  Future<int> backfillStockMovementUnitCost() async {
    if (_isPostgres) return -1;
    const flag = 'startup_unit_cost_backfill_done';
    if (await getSettingValue(flag) == 'true') return -1;
    int fixed = 0;
    try {
      fixed = await customUpdate(
        'UPDATE stock_movements SET unit_cost = '
        '(SELECT p.cost_price FROM products p WHERE p.id = stock_movements.product_id) '
        'WHERE (unit_cost = 0 OR unit_cost IS NULL) '
        'AND EXISTS (SELECT 1 FROM products p WHERE p.id = stock_movements.product_id '
        'AND COALESCE(p.cost_price, 0) > 0)',
        updates: {},
      );
    } catch (e) {
      debugPrint('[Startup] fixStockMovementsCost: $e');
      return 0;
    }
    // F-ACCT-2: arm the one-shot flag only once NO zero/null-cost movement
    // remains whose product still EXISTS. `fixed == 0` also occurs when the
    // remaining rows point at currently-uncosted products (cost_price = 0);
    // those gain a WAC on a later purchase and must still be backfilled, or the
    // period's COGS/inventory valuation stays understated. Orphan rows (product
    // deleted) can never be improved, so they must not pin the scan on forever.
    // Consistent with the sales-COGS backfill (F-ACCT-1). The expensive UPDATE
    // still only runs while candidates exist, preserving the C-PERF-2 win.
    int remaining = 0;
    try {
      final rows = await customSelect(
        'SELECT COUNT(*) AS c FROM stock_movements sm '
        'WHERE (sm.unit_cost = 0 OR sm.unit_cost IS NULL) '
        'AND EXISTS (SELECT 1 FROM products p WHERE p.id = sm.product_id)',
      ).get();
      remaining = (rows.first.data['c'] as int?) ?? 0;
    } catch (e) {
      debugPrint('[Startup] fixStockMovementsCost probe: $e');
      remaining = 1; // on probe failure, do NOT arm the flag — retry next boot
    }
    if (remaining == 0) await setSetting(flag, 'true');
    return fixed;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Phase 6: Deferred background tasks
  // ─────────────────────────────────────────────────────────────────────────

  /// Background tasks that don't block the user from logging in.
  Future<void> _scheduleDeferredTasks() async {
    // Auto-backup on startup — only for SQLite (file-based)
    if (!_isPostgres) {
      try {
        // تفريغ الـ WAL قبل النسخ — من غيره النسخة بتعكس آخر تفريغ تلقائي
        // مش الحالة دلوقتي. مش إجباري هنا: التطبيق بيفتح والقراء الآخرين
        // واردين، ونسخة ناقصة أحسن من ولا نسخة.
        await autoBackupOnStartup(
          checkpoint: () => walCheckpointTruncate(this),
        );
      } catch (e) {
        debugPrint('[Startup] autoBackup: $e');
      }
    }
  }
}
