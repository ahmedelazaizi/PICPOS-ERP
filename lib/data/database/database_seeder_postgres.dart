// ═══════════════════════════════════════════════════════════════════════════
// POSTGRES SEEDER — Atomic, Idempotent, Verifiable
// ═══════════════════════════════════════════════════════════════════════════
//
// Rewritten per `crispy-riding-willow.md` (Session 2):
//
//   • Everything runs inside a single `transaction()`. A failure anywhere
//     rolls back the whole batch — no more half-seeded databases.
//
//   • Every helper is idempotent: it reads the table first and only inserts
//     what's missing. Running the seeder twice on the same DB produces no
//     duplicates and no errors.
//
//   • Every helper returns how many rows it inserted. The caller assembles a
//     `SeedResult` that the Setup Wizard's provisioning screen uses to show
//     per-step progress.
//
//   • A separate `verifyPostgresBaseline()` checks that the minimum baseline
//     is present after seeding. This is what the wizard calls at the end of
//     provisioning and what `beforeOpen` calls for self-healing recovery.
// ═══════════════════════════════════════════════════════════════════════════

part of 'database.dart';

/// Per-table row counts from a seeder run.
///
/// Zero means the table already had the required data and nothing was
/// inserted (still a success). Use [toMap] for UI display.
class SeedResult {
  int roles = 0;
  int rolePermissions = 0;
  int admin = 0;
  int branch = 0;
  int warehouse = 0;
  int units = 0;
  int category = 0;
  int safes = 0;
  int settings = 0;
  int accounts = 0;
  int deliveryParties = 0;
  int invoiceTemplates = 0;
  int fiscalYear = 0;
  int accountingPeriods = 0;

  /// Total rows inserted across all tables.
  int get totalInserted =>
      roles +
      rolePermissions +
      admin +
      branch +
      warehouse +
      units +
      category +
      safes +
      settings +
      accounts +
      deliveryParties +
      invoiceTemplates +
      fiscalYear +
      accountingPeriods;

  Map<String, int> toMap() => {
        'roles': roles,
        'role_permissions': rolePermissions,
        'admin': admin,
        'branch': branch,
        'warehouse': warehouse,
        'units': units,
        'category': category,
        'safes': safes,
        'settings': settings,
        'accounts': accounts,
        'delivery_parties': deliveryParties,
        'invoice_templates': invoiceTemplates,
        'fiscal_year': fiscalYear,
        'accounting_periods': accountingPeriods,
      };

  @override
  String toString() => 'SeedResult(${toMap()})';
}

/// Outcome of a baseline verification check.
class BaselineCheck {
  final Map<String, int> counts;
  final Map<String, int> minimums;
  final List<String> missing;

  const BaselineCheck({
    required this.counts,
    required this.minimums,
    required this.missing,
  });

  bool get ok => missing.isEmpty;

  @override
  String toString() => ok
      ? 'BaselineCheck(ok, counts=$counts)'
      : 'BaselineCheck(MISSING=$missing, counts=$counts)';
}

extension DatabaseSeederPostgres on AppDatabase {
  /// Atomic, idempotent PostgreSQL initial data seeder.
  ///
  /// Wraps every step in a single transaction — if any helper throws the
  /// transaction rolls back and the DB is left exactly as it was.
  ///
  /// Safe to call multiple times: each helper checks for existence first.
  ///
  /// ═══════════════════════════════════════════════════════════════════════
  /// CRITICAL INVARIANT — NO `try/catch` INSIDE THE TRANSACTION BODY
  /// ═══════════════════════════════════════════════════════════════════════
  /// On PostgreSQL a failed statement inside a transaction marks the tx as
  /// "aborted". Any subsequent query then fails with error 25P02 ("current
  /// transaction is aborted"). If we `try { ... } catch (_) {}` a failing
  /// insert, we swallow the REAL error, but the next SELECT/INSERT throws
  /// 25P02 and that cascade is what bubbles up to the UI — making it
  /// impossible to diagnose the root cause.
  ///
  /// Rule: helpers inside `seedInitialDataPostgresAtomic()` must NEVER wrap
  /// PG operations in try/catch. Failures must propagate so Drift rolls
  /// back the transaction cleanly and the real exception reaches the UI.
  /// ═══════════════════════════════════════════════════════════════════════
  Future<SeedResult> seedInitialDataPostgresAtomic() async {
    return await transaction(() async {
      final r = SeedResult();

      // Roles + permissions first — everything else depends on role_id=1.
      debugPrint('[PG Seeder] → roles');
      r.roles = await _seedRolesIfMissing();
      debugPrint('[PG Seeder] → role_permissions');
      r.rolePermissions = await _seedRolePermissionsIfMissing();

      // Admin user (needs roles).
      debugPrint('[PG Seeder] → admin');
      r.admin = await _seedAdminIfMissing();

      // Organizational scaffolding.
      debugPrint('[PG Seeder] → branch');
      r.branch = await _seedBranchIfMissing();
      debugPrint('[PG Seeder] → warehouse');
      r.warehouse = await _seedWarehouseIfMissing();
      debugPrint('[PG Seeder] → units');
      r.units = await _seedUnitsIfMissing();
      debugPrint('[PG Seeder] → category');
      r.category = await _seedCategoryIfMissing();
      debugPrint('[PG Seeder] → safes');
      r.safes = await _seedSafesIfMissing();
      debugPrint('[PG Seeder] → settings');
      r.settings = await _seedSettingsIfMissing();

      // Chart of accounts + fixed customer parties + invoice templates.
      debugPrint('[PG Seeder] → accounts');
      r.accounts = await _seedChartOfAccountsIfMissing();
      debugPrint('[PG Seeder] → delivery parties');
      r.deliveryParties = await _seedDeliveryPartiesIfMissing();
      debugPrint('[PG Seeder] → invoice templates');
      r.invoiceTemplates = await _seedInvoiceTemplatesIfMissing();

      // Fiscal year + 12 monthly periods for the current calendar year.
      debugPrint('[PG Seeder] → fiscal year + periods');
      final fy = await _seedCurrentFiscalYearIfMissing();
      r.fiscalYear = fy.yearInserted;
      r.accountingPeriods = fy.periodsInserted;

      debugPrint('[PG Seeder] ✅ Atomic seed complete: $r');
      return r;
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Table-level idempotent helpers
  // ─────────────────────────────────────────────────────────────────────────

  /// Seeds the 9 default roles using explicit pre-existence checks.
  ///
  /// Does NOT call the shared `seedRolesAndPermissions()` because that helper
  /// uses `InsertMode.insertOrIgnore` on every insert — a pattern the
  /// `drift_postgres` driver does not reliably translate to a valid PG
  /// `ON CONFLICT` clause. A single malformed statement there would abort
  /// the enclosing transaction and produce a 25P02 cascade.
  ///
  /// Returns the number of NEW rows inserted.
  Future<int> _seedRolesIfMissing() async {
    // (name, description, isSystemRole). Order matters only cosmetically.
    const defaults = <List<Object>>[
      ['مدير النظام', 'صلاحيات كاملة للنظام', true],
      ['كاشير', 'نقطة البيع فقط', true],
      ['مخزني', 'إدارة المخزون والمنتجات', true],
      ['محاسب', 'التقارير والخزينة', true],
      ['مدير مالي', 'طبقة وصول غير مقيدة مالياً', true],
      ['كاشير متقدم', 'كاشير مع صلاحيات متقدمة للدفع والخصم والمرتجعات', false],
      ['مدير فرع', 'إدارة فرع كاملة مع صلاحيات مبيعات ومخزون وتقارير', false],
      ['محاسب متقدم', 'صلاحيات محاسبية متقدمة مع تحليلات وتقارير', false],
      ['مدير مخزون', 'إدارة المخزون والتحويلات والمشتريات', false],
    ];
    var inserted = 0;
    for (final r in defaults) {
      final existing = await (select(roles)
            ..where((t) => t.name.equals(r[0] as String)))
          .getSingleOrNull();
      if (existing != null) continue;
      await into(roles).insert(
        RolesCompanion.insert(
          name: r[0] as String,
          description: Value(r[1] as String),
          isSystemRole: Value(r[2] as bool),
          // UUID-First Phase 1 Slice 3: seeded system roles get stable UUID.
          globalId: Value(UuidV7.generate()),
        ),
      );
      inserted++;
    }
    return inserted;
  }

  /// Seeds all permission rows from [PermissionCodes.masterList] and wires the
  /// admin role ("مدير النظام") to every one of them.
  ///
  /// Uses only explicit pre-existence checks (no `InsertMode.insertOrIgnore`
  /// and no `ON CONFLICT`), which is the pattern proven to work reliably on
  /// both SQLite and PostgreSQL via drift_postgres.
  ///
  /// Non-admin role default mappings (cashier / stock-keeper / accountant…)
  /// are INTENTIONALLY not seeded here: an admin account with full access is
  /// the only thing needed to finish the Setup Wizard and start using the
  /// system. Operators can tune non-admin roles via the UI afterwards. This
  /// keeps the atomic seeder small, auditable, and free of the insertOrIgnore
  /// minefield.
  Future<int> _seedRolePermissionsIfMissing() async {
    final masterList = PermissionCodes.masterList;

    // 1. Insert any missing permission codes.
    //
    // IMPORTANT: A pre-check alone is NOT enough on PostgreSQL. Another
    // concurrent path (e.g. the deferred `syncAllPermissions()` microtask
    // scheduled by `beforeOpen` Phase 4) may have inserted some rows between
    // our pre-check and our INSERT. We therefore use raw SQL with
    // `ON CONFLICT (code) DO NOTHING` so the statement is bullet-proof
    // against races AND pre-existing rows. Both PG and SQLite 3.24+ support
    // this exact syntax.
    for (final perm in masterList) {
      await customStatement(
        'INSERT INTO permissions (code, name, category) VALUES (?, ?, ?) '
        'ON CONFLICT (code) DO NOTHING',
        [perm['code']!, perm['name']!, perm['category']!],
      );
    }

    // 2. Wire admin → ALL permissions. Admin is "مدير النظام".
    final adminRole = await (select(roles)
          ..where((r) => r.name.equals('مدير النظام')))
        .getSingleOrNull();
    if (adminRole == null) {
      // Should be impossible — _seedRolesIfMissing ran right before us.
      debugPrint('[PG Seeder] WARNING: مدير النظام role missing, skipping admin wiring');
      return (await select(rolePermissions).get()).length;
    }

    final allPerms = await select(permissions).get();
    final existingAdminMappings = await (select(rolePermissions)
          ..where((rp) => rp.roleId.equals(adminRole.id)))
        .get();
    final wiredPermIds =
        existingAdminMappings.map((rp) => rp.permissionId).toSet();

    // Use raw SQL with `ON CONFLICT DO NOTHING` for the same reason as the
    // permissions INSERT above — the composite PK (role_id, permission_id)
    // is the conflict target. Counting "inserted" via affected rows is not
    // reliable across drivers, so we rely on the pre-check to increment
    // our counter and let PG silently ignore any row that somehow slipped
    // in via a concurrent path.
    var inserted = 0;
    for (final p in allPerms) {
      if (wiredPermIds.contains(p.id)) continue;
      // NOTE: We use bare `ON CONFLICT DO NOTHING` (no target column list)
      // instead of `ON CONFLICT (role_id, permission_id) DO NOTHING` because
      // PG raised 42P10 ("no unique or exclusion constraint matching the
      // ON CONFLICT specification") on databases where the composite
      // primary key was not emitted exactly as expected by
      // drift_postgres — e.g. tables left over from a previous crashed
      // migration. The bare form matches ANY constraint violation and is
      // supported by both PostgreSQL and SQLite 3.24+.
      await customStatement(
        'INSERT INTO role_permissions (role_id, permission_id) VALUES (?, ?) '
        'ON CONFLICT DO NOTHING',
        [adminRole.id, p.id],
      );
      wiredPermIds.add(p.id);
      inserted++;
    }

    // 3. Wire the default non-admin system roles. Each role gets the same
    //    permission set the old `seedRolesAndPermissions()` wired them up
    //    with, but using explicit pre-checks so drift_postgres doesn't need
    //    `InsertMode.insertOrIgnore`.
    inserted += await _wireDefaultNonAdminRoles(allPerms);
    return inserted;
  }

  /// Wires the baseline permission set for every non-admin system role.
  ///
  /// The mapping is a verbatim copy of the defaults in
  /// `seedRolesAndPermissions()` (which is still used on SQLite). Any new
  /// permission codes the user creates via the UI afterwards are per-role and
  /// don't need to be reflected here.
  ///
  /// All inserts are guarded by an in-memory set of `(roleId, permissionId)`
  /// pairs we already observed — zero `InsertMode.insertOrIgnore`, zero
  /// `ON CONFLICT`, so it's safe under drift_postgres.
  Future<int> _wireDefaultNonAdminRoles(List<Permission> allPerms) async {
    final permByCode = {for (final p in allPerms) p.code: p.id};

    Future<int?> roleIdByName(String name) async {
      final r = await (select(roles)..where((t) => t.name.equals(name)))
          .getSingleOrNull();
      return r?.id;
    }

    final cashierId = await roleIdByName('كاشير');
    final stockKeeperId = await roleIdByName('مخزني');
    final accountantId = await roleIdByName('محاسب');
    final financialManagerId = await roleIdByName('مدير مالي');
    final advancedCashierId = await roleIdByName('كاشير متقدم');
    final branchManagerId = await roleIdByName('مدير فرع');
    final advancedAccountantId = await roleIdByName('محاسب متقدم');
    final inventoryManagerId = await roleIdByName('مدير مخزون');

    // Pre-load every existing (role,permission) pair to avoid UNIQUE violations.
    final existingPairs = <String>{};
    for (final rp in await select(rolePermissions).get()) {
      existingPairs.add('${rp.roleId}:${rp.permissionId}');
    }

    Future<int> wire(int? roleId, List<String> codes) async {
      if (roleId == null) return 0;
      var n = 0;
      for (final code in codes) {
        final permId = permByCode[code];
        if (permId == null) continue; // code not in masterList yet
        final key = '$roleId:$permId';
        if (existingPairs.contains(key)) continue;
        // Bare `ON CONFLICT DO NOTHING` — see notes in
        // _seedRolePermissionsIfMissing for why we don't specify a target.
        await customStatement(
          'INSERT INTO role_permissions (role_id, permission_id) VALUES (?, ?) '
          'ON CONFLICT DO NOTHING',
          [roleId, permId],
        );
        existingPairs.add(key);
        n++;
      }
      return n;
    }

    // ── Defaults (mirror of seedRolesAndPermissions in database_seeder_permissions.dart) ──
    const cashierPerms = [
      'pos_access', 'pos_hold_order', 'pos_save', 'pos_print',
      'pos_shift_close',
    ];
    const stockPerms = [
      'inventory_view', 'inventory_edit', 'products_view', 'products_add',
      'products_edit', 'suppliers_view', 'purchases_create', 'categories_view',
    ];
    const accountantPerms = [
      'reports_view', 'reports_export', 'treasury_view', 'customers_view',
      'suppliers_view', 'sales_view', 'purchases_view', 'dashboard_access',
    ];
    const advancedCashierPerms = [
      'pos_access', 'pos_discount', 'pos_return', 'pos_payment_cash',
      'pos_payment_card', 'pos_hold_order', 'customers_view',
      'pos_shift_close',
    ];
    const branchManagerPerms = [
      ...advancedCashierPerms,
      'inventory_view', 'reports_view', 'treasury_view',
      'pos_closing_view_details', 'products_add', 'branches_manage',
      'users_manage', 'sales_view', 'purchases_create', 'settings_view',
    ];
    const advancedAccountantPerms = [
      'treasury_view', 'reports_view', 'settings_view',
      'pos_closing_view_details', 'sales_view', 'purchases_create',
      'inventory_view', 'analytics_view',
    ];
    const inventoryManagerPerms = [
      'inventory_view', 'inventory_transfer', 'products_add',
      'purchases_create', 'reports_view', 'sales_view',
    ];

    var total = 0;
    total += await wire(cashierId, cashierPerms);
    total += await wire(stockKeeperId, stockPerms);
    total += await wire(accountantId, accountantPerms);
    // Financial Manager inherits all Accountant permissions.
    total += await wire(financialManagerId, accountantPerms);
    total += await wire(advancedCashierId, advancedCashierPerms);
    total += await wire(branchManagerId, branchManagerPerms);
    total += await wire(advancedAccountantId, advancedAccountantPerms);
    total += await wire(inventoryManagerId, inventoryManagerPerms);
    return total;
  }

  Future<int> _seedAdminIfMissing() async {
    final existing = await customSelect(
      "SELECT id FROM users WHERE username = 'admin' LIMIT 1",
    ).get();
    if (existing.isNotEmpty) return 0;

    // Find role "مدير النظام" (id=1 on a fresh seed, but don't assume).
    final adminRole = await (select(roles)
          ..where((r) => r.name.equals('مدير النظام')))
        .getSingleOrNull();
    final roleId = adminRole?.id ?? 1;

    final salt = SecurityService.generateSalt();
    final hash = await SecurityService.hashPasswordArgon2('admin');
    final globalId = UuidV7.generate();

    // Raw SQL INSERT: avoids a drift_postgres quirk where `withDefault('')`
    // columns silently replace an explicit companion value with their default
    // on some PG drivers — which was leaving `password_salt=''` after seed
    // and forcing users to run `--reset-admin-password` after every fresh
    // provisioning. Raw SQL eliminates the ambiguity.
    final boolTrue = sqlBool(true);
    final boolFalse = sqlBool(false);
    await customStatement(
      "INSERT INTO users (username, password_hash, password_salt, display_name, "
      "role_id, is_active, is_locked, global_id) "
      "VALUES ('admin', ?, ?, 'مدير النظام', ?, $boolTrue, $boolFalse, ?)",
      [hash, salt, roleId, globalId],
    );
    return 1;
  }

  Future<int> _seedBranchIfMissing() async {
    // Spec 129 F6 / FR-601..606 — gate on is_system_default, NOT on "table
    // is empty" or "row with canonical name exists". A user-renamed default
    // branch keeps its flag, so we skip self-heal and the rename survives
    // restart. Only when zero flagged rows exist (hard-delete or pre-v148
    // install before backfill ran) do we recreate.
    final flagged = await (select(branches)
          ..where((b) => b.isSystemDefault.equals(true))
          ..limit(1))
        .getSingleOrNull();
    if (flagged != null) {
      unawaited(DiagnosticLogger.log(
        DiagnosticLogger.seedSkipSysdefault,
        'table=branches row=${flagged.id} name="${flagged.name}"',
      ));
      return 0;
    }
    await into(branches).insert(
      BranchesCompanion.insert(
        name: 'الفرع الرئيسي',
        // Spec 136 ISS-2 — deterministic seed gid so the PG server and the
        // SQLite client converge on the sync Tier-1 globalId match.
        globalId: Value(UuidV7.deriveSeedGlobalId(
            table: 'branches', seedKey: 'الفرع الرئيسي')),
        isSystemDefault: const Value(true),
      ),
    );
    return 1;
  }

  Future<int> _seedWarehouseIfMissing() async {
    final flagged = await (select(warehouses)
          ..where((w) => w.isSystemDefault.equals(true))
          ..limit(1))
        .getSingleOrNull();
    if (flagged != null) {
      unawaited(DiagnosticLogger.log(
        DiagnosticLogger.seedSkipSysdefault,
        'table=warehouses row=${flagged.id} name="${flagged.name}"',
      ));
      return 0;
    }

    // Find default branch id (don't assume 1).
    final branch = await (select(branches)
          ..orderBy([(b) => OrderingTerm.asc(b.id)])
          ..limit(1))
        .getSingleOrNull();
    final branchId = branch?.id ?? 1;

    await into(warehouses).insert(
      WarehousesCompanion.insert(
        name: 'المخزن الرئيسي',
        branchId: Value(branchId),
        isDefault: const Value(true),
        // Spec 136 ISS-2 — deterministic seed gid.
        globalId: Value(UuidV7.deriveSeedGlobalId(
            table: 'warehouses', seedKey: 'المخزن الرئيسي')),
        isSystemDefault: const Value(true),
      ),
    );
    return 1;
  }

  Future<int> _seedUnitsIfMissing() async {
    const defaults = [
      ['قطعة', 'قطعة'],
      ['كيلو', 'كجم'],
      ['علبة', 'علبة'],
      ['كرتونة', 'كرتون'],
    ];
    // Spec 129 F6 — if ANY flagged unit exists the seeder is a no-op
    // (per-table predicate, see T055). Multi-slot tables (units, safes) get
    // all-or-nothing semantics: if all 4 default rows were hard-deleted
    // simultaneously the seeder reinserts; renaming any one of them keeps
    // its flag and prevents reseed.
    final flagged = await (select(units)
          ..where((u) => u.isSystemDefault.equals(true))
          ..limit(1))
        .getSingleOrNull();
    if (flagged != null) {
      unawaited(DiagnosticLogger.log(
        DiagnosticLogger.seedSkipSysdefault,
        'table=units row=${flagged.id} name="${flagged.name}"',
      ));
      return 0;
    }
    var inserted = 0;
    for (final u in defaults) {
      await into(units).insert(
        UnitsCompanion.insert(
          name: u[0],
          symbol: u[1],
          // Spec 136 ISS-2 — deterministic seed gid (keyed by seed name).
          globalId: Value(UuidV7.deriveSeedGlobalId(
              table: 'units', seedKey: u[0])),
          isSystemDefault: const Value(true),
        ),
      );
      inserted++;
    }
    return inserted;
  }

  Future<int> _seedCategoryIfMissing() async {
    final flagged = await (select(categories)
          ..where((c) => c.isSystemDefault.equals(true))
          ..limit(1))
        .getSingleOrNull();
    if (flagged != null) {
      unawaited(DiagnosticLogger.log(
        DiagnosticLogger.seedSkipSysdefault,
        'table=categories row=${flagged.id} name="${flagged.name}"',
      ));
      return 0;
    }
    await into(categories).insert(
      CategoriesCompanion.insert(
        name: 'عام',
        color: const Value('#2563EB'),
        // UUID-First Phase 1 Slice 3: seeded default category gets stable UUID.
        // Spec 136 ISS-2 — deterministic so server + client converge.
        globalId: Value(UuidV7.deriveSeedGlobalId(
            table: 'categories', seedKey: 'عام')),
        isSystemDefault: const Value(true),
      ),
    );
    return 1;
  }

  Future<int> _seedSafesIfMissing() async {
    const defaults = [
      ['صندوق الكاشير', 'cash'],
      ['الحساب البنكي', 'bank'],
      ['صندوق تحويل كليك', 'click'],
    ];
    final flagged = await (select(safes)
          ..where((s) => s.isSystemDefault.equals(true))
          ..limit(1))
        .getSingleOrNull();
    if (flagged != null) {
      unawaited(DiagnosticLogger.log(
        DiagnosticLogger.seedSkipSysdefault,
        'table=safes row=${flagged.id} name="${flagged.name}"',
      ));
      return 0;
    }
    // Find default branch id (don't assume 1).
    final branch = await (select(branches)
          ..orderBy([(b) => OrderingTerm.asc(b.id)])
          ..limit(1))
        .getSingleOrNull();
    final branchId = branch?.id ?? 1;

    var inserted = 0;
    for (final s in defaults) {
      await into(safes).insert(
        SafesCompanion.insert(
          name: s[0],
          safeType: Value(s[1]),
          isDefault: const Value(true),
          branchId: Value(branchId),
          // Spec 136 ISS-2 — deterministic seed gid (keyed by stable safeType).
          globalId: Value(UuidV7.deriveSeedGlobalId(
              table: 'safes', seedKey: s[1])),
          isSystemDefault: const Value(true),
        ),
      );
      inserted++;
    }
    return inserted;
  }

  Future<int> _seedSettingsIfMissing() async {
    // Settings primary key is `key`, so use insertOnConflictUpdate? No — we
    // only want to insert if key is missing (don't clobber user edits).
    const defaults = [
      ['company_name', 'سوبر ماركت'],
      ['tax_rate', '14'],
    ];
    var inserted = 0;
    for (final kv in defaults) {
      final existing = await (select(settings)
            ..where((s) => s.key.equals(kv[0])))
          .getSingleOrNull();
      if (existing != null) continue;
      await into(settings).insert(
        SettingsCompanion.insert(
          key: kv[0],
          value: Value(kv[1]),
        ),
      );
      inserted++;
    }
    return inserted;
  }

  Future<int> _seedChartOfAccountsIfMissing() async {
    // `seedChartOfAccounts()` uses raw SQL with `ON CONFLICT (code) DO NOTHING`
    // (see `database_seeder_accounts.dart::_acct`), so calling it on a
    // half-seeded accounts table is safe — existing codes are skipped, missing
    // codes are inserted. We still short-circuit when the tree is fully
    // populated to avoid hundreds of no-op round-trips on every app start.
    final before = (await select(accounts).get()).length;
    if (before >= 172) return 0; // full tree size (Spec 146 added 5138 → 172)
    await seedChartOfAccounts();
    final after = (await select(accounts).get()).length;
    return (after - before).clamp(0, after);
  }

  Future<int> _seedDeliveryPartiesIfMissing() async {
    final before = (await select(parties).get()).length;
    await seedDeliveryCompanyPartiesIfNotExists();
    final after = (await select(parties).get()).length;
    return (after - before).clamp(0, after);
  }

  Future<int> _seedInvoiceTemplatesIfMissing() async {
    // NO try/catch — see invariant at top of file. A failure here must
    // propagate so the outer transaction rolls back cleanly instead of
    // being poisoned (25P02 cascade).
    final before = (await select(invoiceTemplates).get()).length;
    if (before > 0) return 0;
    await seedDefaultInvoiceTemplates();
    final after = (await select(invoiceTemplates).get()).length;
    return (after - before).clamp(0, after);
  }

  Future<({int yearInserted, int periodsInserted})>
      _seedCurrentFiscalYearIfMissing() async {
    final today = DateTime.now();
    final existingFY = await getFiscalYearByDate(today);
    if (existingFY != null) return (yearInserted: 0, periodsInserted: 0);

    final fyStart = DateTime(today.year, 1, 1);
    final fyEnd = DateTime(today.year, 12, 31, 23, 59, 59);
    final fyId = await createFiscalYear(
      name: 'السنة المالية ${today.year}',
      startDate: fyStart,
      endDate: fyEnd,
    );

    // Clean-slate insert: we just created the fiscal year, so there can be
    // no pre-existing periods for it. Any failure must roll back the whole
    // transaction — no try/catch (see invariant at top of file).
    final periodsBefore = (await select(accountingPeriods).get()).length;
    await generatePeriodsForYear(fyId, fyStart, fyEnd);
    final periodsAfter = (await select(accountingPeriods).get()).length;
    return (
      yearInserted: 1,
      periodsInserted: (periodsAfter - periodsBefore).clamp(0, periodsAfter),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Baseline verification
  // ─────────────────────────────────────────────────────────────────────────

  /// Checks that the DB has the minimum baseline rows expected by the app.
  /// Called by the Setup Wizard's Provisioning step (after seeding) and by
  /// `beforeOpen` for self-healing on existing installs.
  Future<BaselineCheck> verifyPostgresBaseline() async {
    final counts = <String, int>{
      'roles': (await select(roles).get()).length,
      'users': (await select(users).get()).length,
      'branches': (await select(branches).get()).length,
      'warehouses': (await select(warehouses).get()).length,
      'safes': (await select(safes).get()).length,
      'units': (await select(units).get()).length,
      'categories': (await select(categories).get()).length,
      'accounts': (await select(accounts).get()).length,
      'settings': (await select(settings).get()).length,
      'role_permissions': (await select(rolePermissions).get()).length,
      'fiscal_years': (await select(fiscalYears).get()).length,
      'accounting_periods': (await select(accountingPeriods).get()).length,
    };

    const minimums = <String, int>{
      'roles': 5,
      'users': 1,
      'branches': 1,
      'warehouses': 1,
      'safes': 3,
      'units': 4,
      'categories': 1,
      'accounts': 50,
      'settings': 2,
      'role_permissions': 50,
      'fiscal_years': 1,
      'accounting_periods': 12,
    };

    final missing = <String>[];
    minimums.forEach((table, min) {
      final actual = counts[table] ?? 0;
      if (actual < min) missing.add('$table ($actual/$min)');
    });

    return BaselineCheck(
      counts: counts,
      minimums: minimums,
      missing: missing,
    );
  }
}
