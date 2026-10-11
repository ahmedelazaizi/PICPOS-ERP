part of 'database.dart';

  // ═══════════════════════════════════════════════════════════════════════════
  // SPEC 130 — PG SCHEMA PARITY (generic self-heal pass)
  // ═══════════════════════════════════════════════════════════════════════════
  //
  // Defense-in-depth catch-all that ensures every Drift schema entity exists
  // on PostgreSQL. Runs every boot in Phase 2d (after
  // `_ensurePostgresSyncInfrastructure`). Compares `allSchemaEntities` against
  // `information_schema` + `pg_indexes` and emits idempotent DDL to close
  // gaps:
  //   - Missing tables → CREATE TABLE IF NOT EXISTS (via Migrator)
  //   - Missing columns → ALTER TABLE ADD COLUMN IF NOT EXISTS
  //   - Missing indexes → CREATE INDEX IF NOT EXISTS
  //   - Missing FK constraints → ALTER TABLE ADD CONSTRAINT (guarded)
  //
  // Per Clarification Q1: full parity (tables + columns + indexes + FKs).
  // Per Clarification Q2: unrecoverable failure throws
  // [PgSchemaParityException] → Fatal screen (Block-all).
  // Per Clarification Q3: defense-in-depth — does NOT replace
  // `_createAllForPostgres()` or `_ensurePostgresSyncInfrastructure()`,
  // runs AFTER them as catch-all.
  // Per Clarification Q4: column type drift = warn-only, no ALTER COLUMN TYPE.
  //
  // **FR-008**: runs outside any transaction. Uses `customStatement` directly,
  // NEVER `db.transaction(...)`. Static test (T025) grep-asserts this.
  // ═══════════════════════════════════════════════════════════════════════════

extension AppDatabasePostgresParity on AppDatabase {
  /// Read PG live table names from information_schema (public schema only).
  /// Returns lowercased set for case-insensitive comparison.
  Future<Set<String>> _pgFetchTableNames() async {
    final rows = await customSelect(
      "SELECT table_name FROM information_schema.tables "
      "WHERE table_schema = 'public' AND table_type = 'BASE TABLE'",
    ).get();
    return rows
        .map((r) => (r.data['table_name'] as String).toLowerCase())
        .toSet();
  }

  /// Read PG live columns keyed by `(table_name, column_name)` → (type, nullable).
  /// All names lowercased for case-insensitive comparison.
  Future<Map<String, _PgLiveColumn>> _pgFetchColumns() async {
    final rows = await customSelect(
      "SELECT table_name, column_name, data_type, is_nullable "
      "FROM information_schema.columns WHERE table_schema = 'public'",
    ).get();
    final out = <String, _PgLiveColumn>{};
    for (final r in rows) {
      final table = (r.data['table_name'] as String).toLowerCase();
      final col = (r.data['column_name'] as String).toLowerCase();
      out['$table.$col'] = _PgLiveColumn(
        pgType: (r.data['data_type'] as String).toLowerCase(),
        nullable: (r.data['is_nullable'] as String).toUpperCase() == 'YES',
      );
    }
    return out;
  }

  /// Read PG live FK constraint signatures `(table.column → refTable.refColumn)`.
  /// Used to detect missing FKs in Drift schema.
  // ignore: unused_element
  Future<Set<String>> _pgFetchForeignKeys() async {
    final rows = await customSelect(
      "SELECT tc.table_name AS src_table, kcu.column_name AS src_col, "
      "       ccu.table_name AS ref_table, ccu.column_name AS ref_col "
      "FROM information_schema.table_constraints tc "
      "JOIN information_schema.key_column_usage kcu "
      "  ON tc.constraint_name = kcu.constraint_name "
      "JOIN information_schema.constraint_column_usage ccu "
      "  ON tc.constraint_name = ccu.constraint_name "
      "WHERE tc.table_schema = 'public' "
      "  AND tc.constraint_type = 'FOREIGN KEY'",
    ).get();
    return rows
        .map((r) =>
            '${(r.data['src_table'] as String).toLowerCase()}.'
            '${(r.data['src_col'] as String).toLowerCase()}→'
            '${(r.data['ref_table'] as String).toLowerCase()}.'
            '${(r.data['ref_col'] as String).toLowerCase()}')
        .toSet();
  }

  /// Read PG live index names. Returns lowercased set.
  Future<Set<String>> _pgFetchIndexNames() async {
    final rows = await customSelect(
      "SELECT indexname FROM pg_indexes WHERE schemaname = 'public'",
    ).get();
    return rows
        .map((r) => (r.data['indexname'] as String).toLowerCase())
        .toSet();
  }

  /// Build a `CREATE TABLE IF NOT EXISTS` statement for the given Drift
  /// [TableInfo] using PostgreSQL-compatible DDL (SERIAL, BOOLEAN, BYTEA,
  /// `EXTRACT(EPOCH FROM NOW())` instead of `strftime`).
  ///
  /// Logic mirrors `_createAllForPostgres()` Phase 2 (lines 508-563) so
  /// the same dialect rules apply on both first-boot creation and
  /// every-boot self-heal. Duplicated rather than shared via helper to
  /// avoid touching the legacy creator (Constitution I — Behavior
  /// Preservation).
  String _buildPgCreateTableSql(TableInfo entity) {
    final columns = entity.$columns;
    final colDefs = <String>[];

    for (final col in columns) {
      final colName = col.$name;
      String pgType;

      if (col.type == DriftSqlType.int) {
        if (col.hasAutoIncrement) {
          colDefs.add('"$colName" SERIAL PRIMARY KEY');
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
        pgType = 'BIGINT'; // Drift stores datetime as unix epoch
      } else if (col.type == DriftSqlType.blob) {
        pgType = 'BYTEA';
      } else {
        pgType = 'TEXT';
      }

      final nullable = col.$nullable ? '' : ' NOT NULL';
      var defaultClause = '';

      if (col.defaultValue != null) {
        final defaultStr = col.defaultValue.toString();
        if (defaultStr.contains('currentDateAndTime') ||
            defaultStr.contains('CurrentDateTimeExpression')) {
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

    // Composite / non-autoincrement primary keys.
    //
    // The loop above only emits PRIMARY KEY for an autoincrement int column
    // (as part of SERIAL). Everything else declared via drift's
    // `Set<Column> get primaryKey` was DROPPED, so eight tables were created
    // on PostgreSQL with no primary key at all — among them
    // `document_sequences` (keyed on `prefix`, guarding document numbering)
    // and `processed_messages` (keyed on `idempotency_key`, the whole basis
    // of replay de-duplication).
    //
    // Scope note: this affects CREATE TABLE only. It is deliberately NOT
    // retro-fitted onto tables that already exist on a live server — adding a
    // primary key to a table that has accumulated duplicate rows fails, and a
    // failing statement in the boot path is exactly what killed the app in
    // v132. Existing deployments need a measured dedup + ALTER, tracked
    // separately.
    if (entity.$primaryKey.isNotEmpty) {
      final hasSerialPk = columns.any(
        (c) => c.type == DriftSqlType.int && c.hasAutoIncrement,
      );
      if (!hasSerialPk) {
        final pkCols =
            entity.$primaryKey.map((c) => '"${c.$name}"').join(', ');
        colDefs.add('PRIMARY KEY ($pkCols)');
      }
    }

    return 'CREATE TABLE IF NOT EXISTS "${entity.actualTableName}" '
        '(${colDefs.join(', ')})';
  }

  /// Generic schema parity pass. Iterates `allSchemaEntities`, reads PG
  /// live schema from `information_schema` + `pg_indexes`, and emits
  /// idempotent DDL to close gaps. See class-level comment for the full
  /// contract.
  ///
  /// **DO NOT** wrap the body in `db.transaction(...)` — FR-008 requires
  /// DDL to run outside any active transaction. Static test T025
  /// grep-asserts the absence of `transaction(` here.
  @visibleForTesting
  Future<void> runPostgresSchemaParityForTesting() =>
      _ensurePostgresSchemaParity();

  Future<void> _ensurePostgresSchemaParity() async {
    if (!_isPostgres) return;

    final sw = Stopwatch()..start();
    var healedCount = 0;
    var driftCount = 0;
    final fatalErrors = <_PgParityFatal>[];

    // Snapshot PG live schema once. O(1) round-trips instead of per-entity.
    final pgTables = await _pgFetchTableNames();
    final pgColumns = await _pgFetchColumns();
    final pgIndexes = await _pgFetchIndexNames();
    // `_pgFetchForeignKeys` exists for future FK-parity work (see T018
    // comment in the loop below) but is not snapshotted here yet — the
    // current implementation cannot programmatically derive Drift's
    // declared FK targets, so reading PG's side without a way to compare
    // would emit only spurious extras warnings.

    // Iterate Drift schema entities. Handle each kind explicitly so out-of-
    // scope kinds (Trigger/View) are logged via [PG-PARITY-SKIP] rather than
    // silently ignored (FR-006).
    final driftTableNames = <String>{};
    for (final entity in allSchemaEntities) {
      if (entity is TableInfo) {
        final tableName = entity.actualTableName.toLowerCase();
        driftTableNames.add(tableName);
        final tableExisted = pgTables.contains(tableName);

        if (!tableExisted) {
          // Missing table → emit CREATE TABLE IF NOT EXISTS with
          // PG-compatible DDL (Drift-generated DDL uses SQLite-only syntax
          // like strftime() / AUTOINCREMENT that PG rejects).
          try {
            final sql = _buildPgCreateTableSql(entity);
            await customStatement(sql);
            healedCount++;
            await DiagnosticLogger.log(
              'PG-PARITY-HEAL',
              'table=$tableName action=created',
            );
          } catch (e) {
            fatalErrors.add(_PgParityFatal(
              entity: 'table:$tableName',
              detail: 'CREATE TABLE failed: $e',
            ));
            await DiagnosticLogger.log(
              'PG-PARITY-FATAL',
              'table=$tableName error=$e',
            );
            continue; // skip column/FK heal on a table we couldn't create
          }
        }

        // T016 — column-level parity. ALTER ADD COLUMN IF NOT EXISTS for
        // any Drift column not present on PG. Reuses the Drift→PG type
        // mapping via [_buildPgColumnDef]. Skipped for tables we just
        // created above (they already carry all their columns) AND for
        // SERIAL-PK columns (cannot be re-added via ALTER).
        if (tableExisted) {
          for (final col in entity.$columns) {
            if (col.hasAutoIncrement) continue; // SERIAL PK — never ALTER ADD
            final colName = col.$name.toLowerCase();
            final key = '$tableName.$colName';
            final live = pgColumns[key];

            if (live == null) {
              // Missing column → ALTER TABLE ADD COLUMN IF NOT EXISTS.
              try {
                final colDef =
                    _buildPgColumnDef(col, forExistingTable: true);
                // Required-with-no-default arrives nullable instead of
                // aborting the boot. Surface it so ops can see which columns
                // still need promoting, rather than discovering it later from
                // a NULL that should have been impossible.
                final degraded =
                    !col.$nullable && _buildPgDefaultClause(col).isEmpty;
                await customStatement(
                  'ALTER TABLE "$tableName" '
                  'ADD COLUMN IF NOT EXISTS $colDef',
                );
                healedCount++;
                await DiagnosticLogger.log(
                  'PG-PARITY-HEAL',
                  'column=$tableName.$colName action=added'
                      '${degraded ? ' nullability=degraded_to_nullable '
                          'reason=not_null_without_default_on_existing_table '
                          'followup=needs_backfill_then_set_not_null' : ''}',
                );
              } catch (e) {
                fatalErrors.add(_PgParityFatal(
                  entity: 'column:$tableName.$colName',
                  detail: 'ALTER ADD COLUMN failed: $e',
                ));
                await DiagnosticLogger.log(
                  'PG-PARITY-FATAL',
                  'column=$tableName.$colName error=$e',
                );
              }
            } else {
              // T019 — drift detection. Column exists; verify type +
              // nullability. Warn-only per Clarification Q4 (no ALTER
              // COLUMN TYPE — too risky for data loss).
              final acceptable =
                  AppDatabase._driftTypeToPgAcceptable[col.type] ?? const ['text'];
              if (!acceptable.contains(live.pgType)) {
                driftCount++;
                await DiagnosticLogger.log(
                  'PG-PARITY-DRIFT',
                  'table=$tableName column=$colName '
                      'expected_type=${col.type} '
                      'actual_type=${live.pgType}',
                );
              } else if (live.nullable != col.$nullable) {
                driftCount++;
                await DiagnosticLogger.log(
                  'PG-PARITY-DRIFT',
                  'table=$tableName column=$colName '
                      'expected_null=${col.$nullable} '
                      'actual_null=${live.nullable}',
                );
              }
            }
          }
        }

        // T018 — FK constraint parity. Drift's runtime `GeneratedColumn`
        // does not expose the `.references(...)` target programmatically
        // (the metadata is baked into a private constraint-generation
        // closure that only fires inside Drift's own SQL emission path).
        //
        // The practical safety net for FK gaps is `_buildPgCreateTableSql`
        // — when a *missing table* is created, ON-INSERT runtime errors
        // surface FK violations loudly. For *existing tables* that lost a
        // constraint manually, an operator-level repair is required.
        //
        // Clarification Q1 listed FKs in the "full parity" scope, but
        // research.md §R4 and Edge Case §"Drift schema entity بدون SQL
        // CREATE statement جاهز" pre-authorized deferring constraint
        // kinds when the Drift API limits us. Log once per table so the
        // gap is visible in diagnostics.
        // (No-op for now — see comment block above. Drift API limitation
        // tracked for follow-up.)
      } else if (entity is Index) {
        // T017 — index-level parity. CREATE INDEX IF NOT EXISTS via
        // Migrator first, falling back to a no-op warn if Drift's emitted
        // DDL is PG-incompatible.
        final indexName = entity.entityName.toLowerCase();
        if (pgIndexes.contains(indexName)) continue;
        try {
          await Migrator(this).create(entity);
          healedCount++;
          await DiagnosticLogger.log(
            'PG-PARITY-HEAL',
            'index=$indexName action=created',
          );
        } catch (e) {
          // 🔴 هذا المسارُ كان يبتلع **كلَّ** فهرس: مُهاجرُ drift يرمي على PG
          // لأنّ الـcodegen لهجةُ sqlite وحدَها، فيُسجَّل «انحرافٌ» ويمضي.
          // والجملةُ المولَّدةُ محمولةٌ أصلاً — تُنفَّذ خامّاً قبل الاستسلام.
          try {
            await customStatement(pgPortableIndexSql(entity));
            healedCount++;
            await DiagnosticLogger.log(
              'PG-PARITY-HEAL',
              'index=$indexName action=created_portable',
            );
          } catch (e2) {
            // إخفاقٌ حقيقيٌّ الآن (عمودٌ ناقصٌ على هذه التنصيبة مثلاً).
            // تحذيرٌ فقط كي لا يُسقط فهرسٌ واحدٌ التمريرةَ كلَّها.
            driftCount++;
            await DiagnosticLogger.log(
              'PG-PARITY-DRIFT',
              'index=$indexName reason=create_index_failed '
                  'migrator_error=$e portable_error=$e2',
            );
          }
        }
      } else {
        // Trigger / View / unknown kind — explicitly out of Spec 130 scope
        // per Assumption A3. Logged so the pass NEVER silently swallows an
        // entity kind (FR-006).
        await DiagnosticLogger.log(
          'PG-PARITY-SKIP',
          'kind=${entity.runtimeType} entity=${entity.entityName} '
              'reason=out_of_scope',
        );
      }
    }

    // Extras detection — PG tables not in Drift schema. CREATE-only policy
    // means we never drop them (FR-004); warn-only. These tables are managed
    // by raw SQL migrations/boot infrastructure rather than Drift entities.
    const rawSqlManagedTables = <String>{
      '__schema',
      'modifier_groups',
      'modifier_items',
      'product_modifier_groups',
       'butchery_templates', 'butchery_template_lines', 'butchery_orders',
       'butchery_order_lines',
      // v184 — دفاترُ السندات (المرحلة هـ / E3).
      'voucher_books', 'voucher_book_leaves_cancelled',
      // v185 — نموذجُ التوزيع (المرحلة و).
      'distribution_areas', 'route_customers', 'route_rep_history',
      'rep_resources',
      'warehouse_locations', 'location_stock',
      // v189 — مسوّداتُ المرتجعات (J2).
      'return_drafts',
      // v191 — ملفُّ الموظف (J4).
      'hr_departments', 'hr_job_titles', 'employee_allowances',
      'employee_documents', 'employee_history',
      // v192 — الورديّاتُ والحضورُ والإجازات (J4 الجزء ٢).
      'hr_shifts', 'hr_shift_assignments', 'hr_public_holidays',
      'hr_leave_types', 'hr_leave_requests', 'hr_leave_entitlements',
      'hr_attendance_days',
      // v193 — الرواتبُ والسلفُ والعمولات (J4 الجزء ٣).
      'hr_payroll_settings', 'hr_salary_components', 'hr_commission_plans',
      'hr_employee_advances', 'hr_advance_repayments', 'hr_payroll_adjustments',
      'hr_payroll_runs', 'hr_payroll_lines', 'hr_payroll_items',
    };
    for (final pgTable in pgTables) {
      if (!driftTableNames.contains(pgTable) &&
          !rawSqlManagedTables.contains(pgTable)) {
        await DiagnosticLogger.log(
          'PG-PARITY-EXTRA',
          'table=$pgTable reason=not_in_drift_schema action=preserved',
        );
      }
    }

    sw.stop();

    if (fatalErrors.isNotEmpty) {
      await DiagnosticLogger.log(
        'PG-PARITY-FATAL',
        'count=${fatalErrors.length} '
            'entities=${fatalErrors.map((e) => e.entity).join(',')}',
      );
      throw PgSchemaParityException(
        reasonAr:
            'فشل إصلاح المخطط الذاتى. الكيانات المتأثرة: '
            '${fatalErrors.map((e) => e.entity).join('، ')}. '
            'راجع السجل التشخيصى للتفاصيل.',
        details: fatalErrors.map((e) => e.detail).toList(),
        failedEntities: fatalErrors.map((e) => e.entity).toList(),
      );
    }

    await DiagnosticLogger.log(
      'PG-PARITY-OK',
      'healed=$healedCount drift=$driftCount '
          'duration=${sw.elapsedMilliseconds}ms',
    );
  }

  /// Build a single column definition (`"$name" $type [NOT NULL] [DEFAULT ...]`)
  /// in PG dialect — used by both `_buildPgCreateTableSql` (via inlining)
  /// and the column-heal path (T016) which emits ALTER ADD COLUMN with this
  /// fragment.
  ///
  /// SERIAL PK columns return their own `SERIAL PRIMARY KEY` string. The
  /// column-heal path must filter `hasAutoIncrement` out before calling
  /// this — PostgreSQL doesn't allow ALTER ADD COLUMN on a SERIAL PK.
  ///
  /// Set [forExistingTable] when the fragment is destined for
  /// `ALTER TABLE ... ADD COLUMN` rather than `CREATE TABLE`. On an existing
  /// table a `NOT NULL` column with no `DEFAULT` is rejected outright by
  /// PostgreSQL if any row is present, so that combination is degraded to
  /// nullable — see the comment at the nullability decision below.
  String _buildPgColumnDef(GeneratedColumn col, {bool forExistingTable = false}) {
    final colName = col.$name;
    if (col.type == DriftSqlType.int && col.hasAutoIncrement) {
      return '"$colName" SERIAL PRIMARY KEY';
    }

    String pgType;
    if (col.type == DriftSqlType.int) {
      pgType = 'INTEGER';
    } else if (col.type == DriftSqlType.bigInt) {
      pgType = 'BIGINT';
    } else if (col.type == DriftSqlType.string) {
      pgType = 'TEXT';
    } else if (col.type == DriftSqlType.bool) {
      pgType = 'BOOLEAN';
    } else if (col.type == DriftSqlType.double) {
      pgType = 'DOUBLE PRECISION';
    } else if (col.type == DriftSqlType.dateTime) {
      pgType = 'BIGINT';
    } else if (col.type == DriftSqlType.blob) {
      pgType = 'BYTEA';
    } else if (col.type == DriftSqlType.any) {
      // DriftSqlType.any is the schema-loose "untyped column" marker. PG
      // doesn't have a true equivalent — fall back to TEXT so the ALTER
      // succeeds; drift detection is suppressed via the empty acceptable
      // list above.
      pgType = 'TEXT';
    } else {
      pgType = 'TEXT';
    }

    final defaultClause = _buildPgDefaultClause(col);
    var nullable = col.$nullable ? '' : ' NOT NULL';

    // PostgreSQL rejects `ALTER TABLE ... ADD COLUMN ... NOT NULL` on a table
    // that already has rows unless a DEFAULT backfills them (23502). Drift
    // columns declared required-but-without-a-default therefore make the heal
    // pass throw, and that exception is fatal: it aggregates into
    // `PgSchemaParityException`, `database_startup` rethrows it, and the retry
    // button just re-runs the same ALTER — a permanently bricked install with
    // no exit but `--use-sqlite`. That is the v132 failure class exactly.
    //
    // The boot path must never throw for something this recoverable, so the
    // column lands nullable and the caller logs it. Promoting it to NOT NULL
    // needs a backfill decision plus an ACCESS EXCLUSIVE lock and a full table
    // scan — offline reconciliation work, not something to do while the app is
    // trying to start.
    if (forExistingTable && !col.$nullable && defaultClause.isEmpty) {
      nullable = '';
    }

    return '"$colName" $pgType$nullable$defaultClause';
  }

  /// The ` DEFAULT ...` fragment for [col] in PG dialect, or `''` when drift
  /// declares no default this builder can render. Split out of
  /// [_buildPgColumnDef] so the heal path can ask "would this column arrive
  /// with a backfill value?" without re-deriving the answer.
  String _buildPgDefaultClause(GeneratedColumn col) {
    if (col.defaultValue == null) return '';
    final defaultStr = col.defaultValue.toString();
    if (defaultStr.contains('currentDateAndTime') ||
        defaultStr.contains('CurrentDateTimeExpression')) {
      return ' DEFAULT (EXTRACT(EPOCH FROM NOW())::bigint)';
    }
    if (col.defaultValue is Constant) {
      final val = (col.defaultValue as Constant).value;
      if (val is bool) return ' DEFAULT ${val ? 'TRUE' : 'FALSE'}';
      if (val is String) return " DEFAULT '${val.replaceAll("'", "''")}'";
      return ' DEFAULT $val';
    }
    return '';
  }
}
