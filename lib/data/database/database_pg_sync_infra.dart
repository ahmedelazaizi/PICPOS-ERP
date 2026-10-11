part of 'database.dart';

// Rationale of `AppDatabase._syncHardenedTables` (list stays on the class), moved
// verbatim from its doc comment:
  //
  // 🔴 **v173 (2026-09-02) — القائمةُ كانت متأخّرةً ٣٢ جدولاً عن `pullTables`.**
  //
  // المرحلتان ٢ و٣ (v166 · v167) و`purchase_returns` (v172) أضافت
  // أعمدةَ المزامنة إلى كيانات drift وأدرجت الجداولَ في مساري السحب —
  // **ولم تُضِفها هنا**. وهذه القائمةُ هي ما يعلّق عليه PostgreSQL مُشغِّلَ
  // `fn_bump_row_version`، وهو **الوحيدُ** الذي يختم `last_modified_at`
  // عند الإدراج. فعلى خادم PostgreSQL كان كلُّ صفٍّ جديدٍ في تلك الجداول
  // يُولَد بـ`last_modified_at = NULL`، ومسارُ السحب يرشّح بـ
  // `last_modified_at IS NOT NULL AND > since` — أي أنّ **أوّلَ سحبٍ وحدَه**
  // يراها، وما يُدرَج بعده لا يصل أيَّ عميلٍ أبداً. ولا يظهر ذلك في اختبارِ
  // وحدةٍ: SQLite لا مُشغِّلَ إدراجٍ فيه أصلاً والفحوصُ تقيس الأعمدةَ لا الختم.
  //
  // فالعقدُ الآن: **كلُّ جدولٍ في `DeltaPullService.pullTables` هنا** —
  // و`pg_sync_hardened_tables_guard_test` يثبّته. و`printers` تبقى (خارجَ
  // السحب بقرار مالك، والمُشغِّلُ عليها بلا ضرر).

// PostgreSQL sync-hardening infrastructure (sync columns, fn_bump_row_version,
// per-table triggers, remote_id_mappings). The table list
// `_syncHardenedTables` itself stays on the class (see database.dart).

extension AppDatabasePostgresSyncInfra on AppDatabase {
  /// Ensures PostgreSQL has the full sync-hardening infrastructure.
  ///
  /// The SQLite migration path (epoch_3.dart v129/v130) uses SQLite-only DDL
  /// (`strftime`, `CREATE TRIGGER ... WHEN ... BEGIN ... END`, `AUTOINCREMENT`)
  /// which is incompatible with Postgres. The Drift `onUpgrade` hook is
  /// skipped entirely on PG (see [migration]), so those v129/v130 changes
  /// never land on server-mode installs. This method installs the Postgres
  /// equivalents directly, and runs idempotently on every startup so both
  /// fresh installs (where `_createAllForPostgres` already created the base
  /// tables) and older PG databases (pre-v129) converge to the same state.
  ///
  /// Steps:
  ///   1. `ALTER TABLE ... ADD COLUMN IF NOT EXISTS` for the 4 sync columns
  ///      (`last_modified_at`, `deleted_at`, `origin_client_id`, `row_version`)
  ///      on every table in [_syncHardenedTables].
  ///   2. `CREATE TABLE IF NOT EXISTS remote_id_mappings` with Postgres DDL
  ///      (`SERIAL` instead of `AUTOINCREMENT`, `BIGINT` with
  ///      `EXTRACT(EPOCH FROM NOW())::bigint` default instead of `strftime`).
  ///   3. `CREATE OR REPLACE FUNCTION fn_bump_row_version()` in PL/pgSQL —
  ///      the Postgres equivalent of the SQLite auto-bump trigger body.
  ///      Runs as a BEFORE UPDATE trigger and mutates NEW directly (cheaper
  ///      than the SQLite approach of firing a follow-up UPDATE).
  ///   4. DROP + CREATE TRIGGER for each sync table (Postgres `CREATE OR
  ///      REPLACE TRIGGER` requires v14+; DROP IF EXISTS + CREATE is portable
  ///      back to v10).
  Future<void> _ensurePostgresSyncInfrastructure() async {
    if (!_isPostgres) return;

    // ── Step 0.5: Modifier tables. Migration v70 creates these via raw
    //    SQLite DDL (AUTOINCREMENT, INTEGER booleans), and Drift's
    //    onUpgrade is skipped on PG, so a Postgres server installed
    //    before v70 — or any PG server, since these tables have no
    //    Drift Table class — never gets the schema. The DAO query
    //      SELECT mg.* FROM modifier_groups ...
    //    then fails with "relation modifier_groups does not exist"
    //    every time a cashier opens the modifier panel for a product.
    //    Idempotent CREATE IF NOT EXISTS keeps this safe across restarts.
    //
    // 🔴 ٦‑٢: هذه الكتلةُ كانت تحمل **نسخةً ثانيةً** من تعريف
    //    `modifier_groups` تخالف ما يكتبه [ensureModifierTables]:
    //      هنا:      (id, name, min_selection, max_selection, is_active)
    //      الصحيح:   (id, name, type, min_select, max_select, is_required,
    //                 is_active, sort_order)
    //    و`CREATE TABLE IF NOT EXISTS` تجعل الأسبقَ يفوز، والأسبقُ على PG هو
    //    الإقلاعُ لا الشاشة — فـ`ensureTables()` التي تناديها شاشةُ الإعدادات
    //    تصير بلا أثر، و`createModifierGroup` (تكتب الخمسةَ الناقصة) تنهار على
    //    **كلِّ** قاعدةِ PostgreSQL. أي الميزةُ معطَّلةٌ بالكامل لا «تقرأ خطأً».
    //
    //    فالتعريفُ صار مصدراً واحداً: تُستدعى [ensureModifierTables] نفسُها،
    //    وهي تُفرّع على الخلفيّة داخليّاً وتحمل شفاءَ الأعمدة الناقصة لخادمٍ
    //    نُصِّب على الشكل القديم. والفهرسان يبقيان هنا لأنّها لا تُنشئهما.
    try {
      await ensureModifierTables();
      await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_modifier_items_group ON modifier_items(group_id)',
      );
      await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_product_modifier_groups_product ON product_modifier_groups(product_id)',
      );
    } catch (e) {
      debugPrint('[PG-SYNC] modifier tables ensure failed: $e');
    }

    // ⚠️ **ونُقلت من الخطوة ٤٫٥ إلى ما قبلَ الخطوة ١ (2026-09-21).**
    //    صارت جداولُ المعدِّلات في `_syncHardenedTables`، والخطوتان ١
    //    (‏أعمدةُ المزامنة) و٤ (‏المُشغِّلات) تمرّان على تلك القائمة —
    //    فكانتا تسبقان إنشاءَ الجداول على قاعدةٍ جديدة، **ويُبتلَع
    //    إخفاقُهما في `catch` يطبع سطراً ويمضي**.
    //
    // 🔴 والأثرُ: صفٌّ يُنشأ على الخادم بختمٍ فارغٍ فلا يصل عميلاً بعد أوّل
    //    سحب — وكلُّ شيءٍ يبدو موصولاً. أمسكته المرساةُ السالبةُ في
    //    `pg_phase4_sync_columns_pg_test` بعدِّ المُشغِّلات، وهو حرفيّاً ما
    //    يحذّر منه نصُّها: «جدولٌ في القائمة فشل تركيبُه وابتُلع في catch».

    // ── Step 1: backfill sync columns (Postgres 9.6+ supports IF NOT EXISTS).
    for (final t in AppDatabase._syncHardenedTables) {
      for (final ddl in [
        // v173 — دفاعيٌّ للقواعد التي سبقت إعلانَ كيانٍ ما (الكيانُ يحمله
        // على القواعد الجديدة، و`IF NOT EXISTS` يجعله عديمَ الأثر هناك).
        'ALTER TABLE $t ADD COLUMN IF NOT EXISTS global_id TEXT',
        'ALTER TABLE $t ADD COLUMN IF NOT EXISTS last_modified_at BIGINT',
        'ALTER TABLE $t ADD COLUMN IF NOT EXISTS deleted_at BIGINT',
        'ALTER TABLE $t ADD COLUMN IF NOT EXISTS origin_client_id TEXT',
        'ALTER TABLE $t ADD COLUMN IF NOT EXISTS row_version INTEGER NOT NULL DEFAULT 0',
      ]) {
        try {
          await customStatement(ddl);
        } catch (e) {
          // Table might not exist yet on a partially-provisioned DB; log and
          // continue so one missing table doesn't block the rest.
          debugPrint('[PG-SYNC] $t: $ddl failed: $e');
        }
      }
    }

    // ── Step 1b (v133): direct branch_id on invoice tables for multi-branch
    // reports + filters. PG-side ALTER + backfill from warehouses.branch_id
    // for any rows created before this schema bump.
    for (final t in const ['sales_invoices', 'purchase_invoices']) {
      try {
        await customStatement('ALTER TABLE $t ADD COLUMN IF NOT EXISTS branch_id INTEGER REFERENCES branches(id)');
        await customStatement(
          'UPDATE $t SET branch_id = '
          '(SELECT branch_id FROM warehouses WHERE warehouses.id = $t.warehouse_id) '
          'WHERE branch_id IS NULL',
        );
        await customStatement('CREATE INDEX IF NOT EXISTS idx_${t}_branch ON $t(branch_id)');
      } catch (e) {
        debugPrint('[PG-SYNC] $t.branch_id: $e');
      }
    }

    // ── Step 1c (v134): branch code for invoice number prefixing.
    // PG-side ALTER + backfill from name (first 3 chars uppercased).
    try {
      await customStatement('ALTER TABLE branches ADD COLUMN IF NOT EXISTS code TEXT');
      await customStatement(
        "UPDATE branches SET code = UPPER(SUBSTRING(REPLACE(name,' ',''), 1, 3)) "
        "WHERE code IS NULL OR code = ''",
      );
    } catch (e) {
      debugPrint('[PG-SYNC] branches.code: $e');
    }

    // ── Step 1d (v142, Feature 004 US1): per-asset CoA sub-account linkage
    // + UUIDv7 sync identity on fixed_assets. Idempotent on PG.
    try {
      await customStatement(
          'ALTER TABLE fixed_assets ADD COLUMN IF NOT EXISTS linked_account_id INTEGER REFERENCES accounts(id)');
      await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_fixed_assets_linked_account ON fixed_assets(linked_account_id)');
      await customStatement(
          'ALTER TABLE fixed_assets ADD COLUMN IF NOT EXISTS global_id TEXT');
      await customStatement(
          'CREATE UNIQUE INDEX IF NOT EXISTS idx_fixed_assets_global_id '
          'ON fixed_assets(global_id) WHERE global_id IS NOT NULL');
    } catch (e) {
      debugPrint('[PG-SYNC] fixed_assets v142 columns: $e');
    }

    // ── Step 2: ensure remote_id_mappings (idempotent; Drift schema already
    //    creates it on fresh installs via _createAllForPostgres, but older PG
    //    databases from before v130 won't have it).
    try {
      await customStatement('''
        CREATE TABLE IF NOT EXISTS remote_id_mappings (
          id SERIAL PRIMARY KEY,
          table_name TEXT NOT NULL,
          local_id INTEGER NOT NULL,
          remote_id INTEGER NOT NULL,
          global_id TEXT,
          created_at BIGINT NOT NULL DEFAULT EXTRACT(EPOCH FROM NOW())::bigint
        )
      ''');
      await customStatement(
        'CREATE UNIQUE INDEX IF NOT EXISTS idx_remote_id_local '
        'ON remote_id_mappings(table_name, local_id)',
      );
      await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_remote_id_remote '
        'ON remote_id_mappings(table_name, remote_id)',
      );
      await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_remote_id_global '
        'ON remote_id_mappings(table_name, global_id)',
      );
    } catch (e) {
      debugPrint('[PG-SYNC] remote_id_mappings: $e');
    }

    // ── Step 2b (B-MIG-3): e_invoice_status_log has a Drift class but is NOT
    //    registered in @DriftDatabase, so _createAllForPostgres (which iterates
    //    allSchemaEntities) never creates it, and PG skips the SQLite onUpgrade
    //    that would. On a fresh PG install e_invoicing_dao's status-log
    //    INSERT/SELECT then failed with 42P01. Create it here idempotently.
    //    (The other raw-SQL-only tables the audit listed — sync_logs,
    //    warehouse_transfers/_items, pricing_rules — have zero call sites and
    //    are dead/id-only stubs, so they are intentionally NOT provisioned.)
    try {
      await customStatement('''
        CREATE TABLE IF NOT EXISTS e_invoice_status_log (
          id SERIAL PRIMARY KEY,
          submission_id INTEGER NOT NULL REFERENCES e_invoice_submissions(id),
          old_status TEXT,
          new_status TEXT NOT NULL,
          changed_by TEXT,
          notes TEXT,
          changed_at BIGINT NOT NULL DEFAULT EXTRACT(EPOCH FROM NOW())::bigint,
          global_id TEXT UNIQUE,
          last_modified_at BIGINT,
          deleted_at BIGINT,
          origin_client_id TEXT,
          row_version INTEGER NOT NULL DEFAULT 0
        )
      ''');
      await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_einv_status_log_submission '
        'ON e_invoice_status_log(submission_id)',
      );
    } catch (e) {
      debugPrint('[PG-SYNC] e_invoice_status_log: $e');
    }

    // ── Step 3: auto-bump trigger function. Handles BOTH INSERT and UPDATE:
    //    * INSERT → stamps last_modified_at with server time so delta pull
    //      queries `WHERE last_modified_at > since` can find new rows. Server
    //      time is always authoritative here (avoids client clock skew).
    //    * UPDATE → if the application didn't advance row_version, bump it
    //      and refresh last_modified_at. The guard respects explicit client
    //      writes (e.g. a sync pull replaying a specific version).
    try {
      await customStatement(r'''
        CREATE OR REPLACE FUNCTION fn_bump_row_version()
        RETURNS trigger AS $fn$
        BEGIN
          IF TG_OP = 'INSERT' THEN
            NEW.last_modified_at := EXTRACT(EPOCH FROM NOW())::bigint;
            IF NEW.row_version IS NULL THEN
              NEW.row_version := 0;
            END IF;
          ELSIF TG_OP = 'UPDATE' THEN
            IF NEW.row_version IS NULL OR OLD.row_version IS NULL
               OR NEW.row_version = OLD.row_version THEN
              NEW.row_version := COALESCE(OLD.row_version, 0) + 1;
              NEW.last_modified_at := EXTRACT(EPOCH FROM NOW())::bigint;
            END IF;
          END IF;
          RETURN NEW;
        END;
        $fn$ LANGUAGE plpgsql
      ''');
    } catch (e) {
      debugPrint('[PG-SYNC] fn_bump_row_version: $e');
    }

    // ── Step 4: attach/refresh trigger on each sync table. Skip the whole
    //    loop when the expected trigger count is already installed — this
    //    keeps the common-case startup near zero-cost.
    var shouldInstallTriggers = true;
    try {
      final existing = await customSelect(
        "SELECT COUNT(*)::integer AS c FROM pg_trigger "
        "WHERE tgname LIKE '%_bump_version' AND NOT tgisinternal",
      ).get();
      final count = (existing.first.data['c'] as num).toInt();
      if (count >= AppDatabase._syncHardenedTables.length) {
        shouldInstallTriggers = false;
        debugPrint(
          '[PG-SYNC] triggers already installed ($count ≥ '
          '${AppDatabase._syncHardenedTables.length}) — skipping install',
        );
      }
    } catch (e) {
      debugPrint('[PG-SYNC] trigger count check failed, will reinstall: $e');
    }

    if (shouldInstallTriggers) {
      for (final t in AppDatabase._syncHardenedTables) {
        try {
          await customStatement(
            'DROP TRIGGER IF EXISTS ${t}_bump_version ON $t',
          );
          await customStatement('''
            CREATE TRIGGER ${t}_bump_version
            BEFORE INSERT OR UPDATE ON $t
            FOR EACH ROW
            EXECUTE FUNCTION fn_bump_row_version()
          ''');
        } catch (e) {
          debugPrint('[PG-SYNC] trigger $t: $e');
        }
      }
    }

    // ── Step 5: activity_logs sync columns. activity_logs is NOT in
    //    _syncHardenedTables (it has no deleted_at / row_version because the
    //    audit trail is append-only and never modified once written), but it
    //    DOES need global_id + last_modified_at + origin_client_id so that
    //    multi-client activity logs can be pushed and pulled by globalId.
    //
    //    Without this block, ActivityLogger.log() throws on every call:
    //      Severity.error 42703: column "global_id" of relation
    //      "activity_logs" does not exist
    //    on Postgres servers that were created before the schema added these
    //    columns (Drift's onUpgrade is skipped on PG).
    try {
      for (final ddl in [
        'ALTER TABLE activity_logs ADD COLUMN IF NOT EXISTS global_id TEXT',
        'ALTER TABLE activity_logs ADD COLUMN IF NOT EXISTS origin_client_id TEXT',
        'ALTER TABLE activity_logs ADD COLUMN IF NOT EXISTS last_modified_at BIGINT',
        // Unique constraint on global_id matches the SQLite schema
        // (auth_tables.dart: globalId.unique()). IF NOT EXISTS keeps this
        // idempotent across restarts.
        'CREATE UNIQUE INDEX IF NOT EXISTS idx_activity_logs_global_id '
            'ON activity_logs(global_id) WHERE global_id IS NOT NULL',
        'CREATE INDEX IF NOT EXISTS idx_activity_logs_modified '
            'ON activity_logs(last_modified_at)',
        // ── نظيرُ PG لأعمدة «Maker-Checker» الثلاثة ──
        //
        // ⚠️ نفسُ علّة `activity_logs` أعلاه بالضبط: v82 أضافها بـ`ALTER
        //    TABLE` في هجرة SQLite، و`onUpgrade` **متجاوَزٌ على PG**،
        //    و`_createAllForPostgres` يبني من كيانات drift وهي غيرُ مُعلَنةٍ
        //    في صنف الجدول. فخادمُ PostgreSQL بلا هذه الأعمدة، و
        //    `approveJournalEntry` ينهار عليه بـ42703.
        'ALTER TABLE journal_entries ADD COLUMN IF NOT EXISTS status TEXT '
            "NOT NULL DEFAULT 'posted'",
        'ALTER TABLE journal_entries ADD COLUMN IF NOT EXISTS approved_by INTEGER',
        'ALTER TABLE journal_entries ADD COLUMN IF NOT EXISTS approved_at BIGINT',
        'ALTER TABLE journal_entries ADD COLUMN IF NOT EXISTS created_by INTEGER',
        // ── §٦‑٣: نظيرُ PG لأعمدة تدقيقِ إعادة فتح الفترة ──
        //
        // نفسُ العلّة حرفاً: v82 أضافها بـALTER في هجرة SQLite، وهي غيرُ
        // مُعلَنةٍ في صنف `AccountingPeriods`، و`onUpgrade` متجاوَزٌ على PG.
        // فبلا هذه الأسطر ينهار `reopenAccountingPeriodWithAudit` على الخادم
        // بـ42703 متى وُصِل.
        'ALTER TABLE accounting_periods ADD COLUMN IF NOT EXISTS reopen_reason TEXT',
        'ALTER TABLE accounting_periods ADD COLUMN IF NOT EXISTS reopened_by INTEGER',
        'ALTER TABLE accounting_periods ADD COLUMN IF NOT EXISTS reopened_at BIGINT',
      ]) {
        try {
          await customStatement(ddl);
        } catch (e) {
          debugPrint('[PG-SYNC] activity_logs DDL failed: $e');
        }
      }
    } catch (e) {
      debugPrint('[PG-SYNC] activity_logs ensure failed: $e');
    }

    debugPrint('[PG-SYNC] ✅ Postgres sync infrastructure ensured');
  }
}
