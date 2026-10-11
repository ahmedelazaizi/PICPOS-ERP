part of 'database.dart';

// Notes moved verbatim from the `customStatement` / `customSelect` overrides in
// `AppDatabase` (database.dart): why the PG translation is also applied at the source.
  // ───────────────────────────────────────────────────────────────────────
  // 🔴 توافقُ PostgreSQL في مسار الإقلاع — `beforeOpen` يتخطّى المُعترِض
  // ───────────────────────────────────────────────────────────────────────
  //
  // الاتصالُ بـPostgreSQL يُلفّ بـ`_PgCompatInterceptor`
  // (`connection_io.dart`: ‏`PgDatabase(...).interceptWith(...)`) وهو يترجم
  // كلَّ SQL خامّ: ‏`strftime` و`julianday` و`GROUP_CONCAT` و**علامةَ
  // الاستفهام** `? → $1, $2, …` (‏`PgCompatSql.fixSql` خطوة ١٠).
  //
  // ⚠️ **لكنّ ما يعمل داخلَ `beforeOpen` لا يمرُّ بالمُعترِض.** مقيسٌ في سياق
  // الإقلاع نفسِه على PostgreSQL حيّة:
  //
  //     SELECT ?  AS a   ⇒ 42601: syntax error at or near "AS"
  //     SELECT $1 AS a   ⇒ يعمل
  //
  // ونفسُ الجملتين خارجَ الإقلاع تعملان — فالفارقُ السياقُ لا الجملة.
  //
  // والأثرُ المقيس: `syncAllPermissions` تموت عند **أوّل** إدراج، ومعها
  // `grantMissingDefaults` (أوّلُ سطرٍ فيها ينادي الأولى). وكلاهما مبتلَعٌ في
  // `catch` يطبع سطراً ويمضي. فعلى خادم PostgreSQL: التنصيبُ الأوّلُ سليمٌ
  // (معالجُ البدء خارجَ `beforeOpen`)، لكنّ **أيَّ صلاحيّةٍ تضيفها نسخةٌ لاحقةٌ
  // لا تصل القاعدةَ أبداً** ولا تُمنَح لمدير النظام.
  //
  // فالترجمةُ تُطبَّق هنا كذلك — عند المصدر لا عند المُعترِض وحدَه. والدالّتان
  // **مُتحايدتان**: `fixSql` محروسةٌ بـ`contains('?')` ولا تلمس شيئاً بعد
  // الترجمة، و`fixArgs` لا تمسّ إلّا `DateTime`. فمرورُهما ثانيةً عبر
  // المُعترِض بلا أثرٍ ولا كلفةٍ تُذكر.
  //
  // ⚠️ وسابقةٌ مسجَّلةٌ في `pg_compat_sql.dart` نفسِه (2026-04-28): عطبٌ بنفس
  // رمز `42601` سببُه أنّ الترجمةَ لم تقع. فهذه هي الطبقةُ الصحيحة.

// PostgreSQL first-boot creation path: portable index SQL, per-entity
// CREATE with raw-SQL fallback, initial seed and the pg compat layer
// (strftime/julianday/CAST helpers). Members moved verbatim from the
// `AppDatabase` class body.

extension AppDatabasePostgresCreate on AppDatabase {
  /// 🔴 جملةُ `CREATE INDEX` صالحةً لـPostgreSQL، مأخوذةً من الجملة التي
  /// ولّدتها drift لـSQLite.
  ///
  /// **العطب**: `Migrator.create(index)` يرمي على PG لأنّ الـcodegen لم يُولّد
  /// إلّا لهجةَ sqlite (‏`dialects` في `build.yaml`)، وdrift يؤكّد على وجود
  /// اللهجة قبل التنفيذ:
  ///   «Tried running SQL optimized for … SqlDialect.sqlite. However, the
  ///    database is running SqlDialect.postgres.»
  /// ومسارا المعالجة كلاهما كانا يعيدان نداءَ `Migrator.create` نفسِه، فيفشلان
  /// بعينِ السبب. مقيسٌ 2026-08-31 على قاعدةٍ حيّة: **١٤٨ من ١٤٨** فهرساً
  /// مُعلَناً بـ`@TableIndex` غائبةٌ عن كلّ قاعدةِ PostgreSQL — وهي خلفيّةُ
  /// الخادم في تنصيبة العميل/المرآة، أي أنّ كلّ استعلامٍ يعتمدها كان يمسح
  /// الجدولَ كاملاً.
  ///
  /// **والعلاجُ بلا codegen**: الجملُ المولَّدةُ محمولةٌ حرفيّاً — نصُّها
  /// `CREATE INDEX idx_accounts_code ON accounts (code)` وهو SQL قياسيٌّ تقبله
  /// PostgreSQL كما هو. فتُؤخَذ من [Index.createStatementsByDialect] وتُنفَّذ
  /// بـ`customStatement` بدل المرور بمُهاجر drift.
  ///
  /// ويُحقَن `IF NOT EXISTS` لأنّ drift لا تولّده، فيصير التنفيذُ آمناً على
  /// قاعدةٍ تحمل الفهرسَ أصلاً — وهذا شرطُ الشفاء كلَّ إقلاع.
  String pgPortableIndexSql(Index index) {
    final byDialect = index.createStatementsByDialect;
    final stmt = (byDialect[SqlDialect.postgres] ??
            byDialect[SqlDialect.sqlite] ??
            byDialect.values.first)
        .trim();
    if (RegExp(r'IF\s+NOT\s+EXISTS', caseSensitive: false).hasMatch(stmt)) {
      return stmt;
    }
    return stmt.replaceFirst(
      RegExp(r'INDEX\s+', caseSensitive: false),
      'INDEX IF NOT EXISTS ',
    );
  }

  /// PostgreSQL-specific table creation: Drift's `currentDateAndTime` generates
  /// `strftime('%s','now')` which doesn't exist in PostgreSQL.
  /// We try normal creation first, and for failures, we create the table using
  /// raw SQL with PostgreSQL-compatible defaults.
  Future<void> _createAllForPostgres(Migrator m) async {
    final failedEntities = <DatabaseSchemaEntity>[];

    // Phase 1: try creating each entity normally
    for (final entity in allSchemaEntities) {
      try {
        await m.create(entity);
      } catch (e) {
        failedEntities.add(entity);
        debugPrint('[PG] Failed to create ${entity.entityName}, will retry with fixed SQL');
      }
    }

    // Phase 2: for failed tables, create using raw PostgreSQL-compatible SQL
    for (final entity in failedEntities) {
      if (entity is TableInfo) {
        try {
          final columns = entity.$columns;
          final colDefs = <String>[];

          for (final col in columns) {
            final colName = col.$name;
            String pgType;

            // Map Drift types to PostgreSQL types
            if (col.type == DriftSqlType.int) {
              if (col.hasAutoIncrement) {
                pgType = 'SERIAL PRIMARY KEY';
                colDefs.add('"$colName" $pgType');
                continue;
              }
              pgType = 'INTEGER';
            } else if (col.type == DriftSqlType.string) {
              pgType = 'TEXT';
            } else if (col.type == DriftSqlType.bool) {
              pgType = 'BOOLEAN';
            } else if (col.type == DriftSqlType.double) {
              pgType = 'DOUBLE PRECISION';
            } else if (col.type == DriftSqlType.dateTime) {
              pgType = 'BIGINT';  // Drift stores datetime as unix epoch
            } else if (col.type == DriftSqlType.blob) {
              pgType = 'BYTEA';
            } else {
              pgType = 'TEXT';
            }

            final nullable = col.$nullable ? '' : ' NOT NULL';
            String defaultClause = '';

            // Handle defaults: replace strftime with PostgreSQL equivalent
            if (col.defaultValue != null) {
              final defaultStr = col.defaultValue.toString();
              if (defaultStr.contains('currentDateAndTime') || defaultStr.contains('CurrentDateTimeExpression')) {
                defaultClause = " DEFAULT (EXTRACT(EPOCH FROM NOW())::bigint)";
              } else if (col.defaultValue is Constant) {
                final val = (col.defaultValue as Constant).value;
                if (val is bool) {
                  defaultClause = ' DEFAULT ${val ? 'TRUE' : 'FALSE'}';
                } else if (val is String) {
                  defaultClause = " DEFAULT '${val.replaceAll("'", "''")}'";
                } else {
                  defaultClause = ' DEFAULT $val';
                }
              }
            }

            colDefs.add('"$colName" $pgType$nullable$defaultClause');
          }

          final sql = 'CREATE TABLE IF NOT EXISTS "${entity.entityName}" (${colDefs.join(', ')})';
          await customStatement(sql);
          debugPrint('[PG] Created ${entity.entityName} with fixed SQL');
        } catch (e2) {
          debugPrint('[PG] Failed to create ${entity.entityName} even with fixed SQL: $e2');
        }
      } else if (entity is Index) {
        // إعادةُ نداء `m.create` كانت تفشل بعينِ السبب (لهجةُ sqlite وحدَها)،
        // فالفهرسُ يُنشأ من جملته المحمولة — انظر [pgPortableIndexSql].
        try {
          await customStatement(pgPortableIndexSql(entity));
          debugPrint('[PG] Created index ${entity.entityName} (portable SQL)');
        } catch (e2) {
          debugPrint('[PG] Failed to create index ${entity.entityName}: $e2');
        }
      } else {
        // For other entities, try again (they might depend on now-created tables)
        try {
          await m.create(entity);
          debugPrint('[PG] Created entity ${entity.entityName} on retry');
        } catch (e2) {
          debugPrint('[PG] Skipped non-table entity ${entity.entityName}: $e2');
        }
      }
    }
  }

  /// PostgreSQL-specific seeder. Delegates to the atomic, idempotent,
  /// verifiable implementation in `database_seeder_postgres.dart`.
  ///
  /// Kept as a thin wrapper for backward compatibility with
  /// `database_startup.dart` callers. New code should call
  /// `seedInitialDataPostgresAtomic()` directly to get the `SeedResult`.
  Future<void> _seedInitialDataPostgres() async {
    await seedInitialDataPostgresAtomic();
  }

  /// Create PostgreSQL compatibility layer for SQLite-specific SQL that
  /// Drift generates. Covers: strftime(), boolean=integer comparisons.
  ///
  /// CRITICAL: this function runs on EVERY app start via `onCreate` on a
  /// fresh install AND explicitly from `runBeforeOpen` on re-launches.
  /// The previous implementation tried to `DROP ... IF EXISTS` the
  /// operators/casts before re-creating them. On a re-run, every table
  /// that carries a `CHECK (col IN (0, 1))` constraint on a BOOLEAN
  /// column depends on the `=(boolean, integer)` operator — so the
  /// DROP was refused by PostgreSQL with
  ///     "constraint users_force_password_change_check on table users
  ///      depends on operator =(boolean,integer)"
  /// and the follow-up CREATE OPERATOR failed (operator already exists).
  /// That cascade is exactly what left fresh server installs with an
  /// empty `roles` + `users` table and unsolvable login errors.
  ///
  /// New behaviour: functions are idempotent via `CREATE OR REPLACE`;
  /// operators and casts are guarded by catalog lookups so we do NOT
  /// drop them when they already exist (tables legitimately depend on
  /// them). We only `CREATE` on first run, otherwise we no-op silently.
  Future<void> _createPostgresCompatLayer() async {
    // 1. strftime() compatibility — Drift uses strftime('%s', 'now')
    try {
      await customStatement(r'''
        CREATE OR REPLACE FUNCTION strftime(fmt text, ts text)
        RETURNS bigint AS $fn$
          SELECT CASE
            WHEN fmt = '%Y-%m' THEN
              EXTRACT(YEAR FROM COALESCE(NULLIF(lower(ts), 'now')::timestamptz, NOW()))::bigint * 100
              + EXTRACT(MONTH FROM COALESCE(NULLIF(lower(ts), 'now')::timestamptz, NOW()))::bigint
            ELSE EXTRACT(EPOCH FROM NOW())::bigint
          END;
        $fn$ LANGUAGE sql STABLE;
      ''');
    } catch (e) { debugPrint('[PG-COMPAT] strftime(text,text): $e'); }

    try {
      await customStatement(r'''
        CREATE OR REPLACE FUNCTION strftime(fmt text, ts timestamptz)
        RETURNS bigint AS $fn$
          SELECT CASE
            WHEN fmt = '%Y-%m' THEN
              EXTRACT(YEAR FROM ts)::bigint * 100 + EXTRACT(MONTH FROM ts)::bigint
            ELSE EXTRACT(EPOCH FROM ts)::bigint
          END;
        $fn$ LANGUAGE sql STABLE;
      ''');
    } catch (e) { debugPrint('[PG-COMPAT] strftime(text,timestamptz): $e'); }

    // 2. boolean = integer helper function (CREATE OR REPLACE is safe).
    try {
      await customStatement(r'''
        CREATE OR REPLACE FUNCTION bool_eq_int(boolean, integer)
        RETURNS boolean AS $fn$
          SELECT $1 = ($2 != 0);
        $fn$ LANGUAGE sql IMMUTABLE
      ''');
    } catch (e) { debugPrint('[PG-COMPAT] bool_eq_int func: $e'); }

    try {
      await customStatement(r'''
        CREATE OR REPLACE FUNCTION int_eq_bool(integer, boolean)
        RETURNS boolean AS $fn$
          SELECT ($1 != 0) = $2;
        $fn$ LANGUAGE sql IMMUTABLE
      ''');
    } catch (e) { debugPrint('[PG-COMPAT] int_eq_bool func: $e'); }

    try {
      await customStatement(r'''
        CREATE OR REPLACE FUNCTION int_to_bool(integer)
        RETURNS boolean AS $fn$
          SELECT $1 != 0;
        $fn$ LANGUAGE sql IMMUTABLE
      ''');
    } catch (e) { debugPrint('[PG-COMPAT] int_to_bool func: $e'); }

    // 3. Operators and cast — guarded by catalog lookup. CREATE ONLY IF
    //    MISSING. Never drop — table CHECK constraints depend on these.
    await _pgCreateIfMissing(
      checkSql:
          "SELECT 1 FROM pg_operator WHERE oprname = '=' "
          "AND oprleft = 'boolean'::regtype AND oprright = 'integer'::regtype",
      createSql: r'''
        CREATE OPERATOR public.= (
          LEFTARG = boolean, RIGHTARG = integer,
          FUNCTION = bool_eq_int
        )
      ''',
      label: 'OPERATOR =(boolean,integer)',
    );

    await _pgCreateIfMissing(
      checkSql:
          "SELECT 1 FROM pg_operator WHERE oprname = '=' "
          "AND oprleft = 'integer'::regtype AND oprright = 'boolean'::regtype",
      createSql: r'''
        CREATE OPERATOR public.= (
          LEFTARG = integer, RIGHTARG = boolean,
          FUNCTION = int_eq_bool
        )
      ''',
      label: 'OPERATOR =(integer,boolean)',
    );

    await _pgCreateIfMissing(
      checkSql:
          "SELECT 1 FROM pg_cast "
          "WHERE castsource = 'integer'::regtype "
          "AND casttarget = 'boolean'::regtype",
      createSql: r'''
        CREATE CAST (integer AS boolean)
        WITH FUNCTION int_to_bool(integer)
        AS IMPLICIT
      ''',
      label: 'CAST (integer AS boolean)',
    );

    debugPrint('[PG] ✅ Compatibility layer ready (idempotent, re-run safe)');
  }

  /// Runs [createSql] only if [checkSql] returns zero rows. Used for DDL
  /// objects (operators, casts) that have no `CREATE OR REPLACE` form
  /// AND cannot be dropped because live tables depend on them.
  Future<void> _pgCreateIfMissing({
    required String checkSql,
    required String createSql,
    required String label,
  }) async {
    try {
      final rows = await customSelect(checkSql).get();
      if (rows.isNotEmpty) {
        debugPrint('[PG-COMPAT] $label already exists — skipping');
        return;
      }
      await customStatement(createSql);
      debugPrint('[PG-COMPAT] $label created');
    } catch (e) {
      debugPrint('[PG-COMPAT] $label check/create failed: $e');
    }
  }
}
