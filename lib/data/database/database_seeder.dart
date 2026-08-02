// ═══════════════════════════════════════════════════════════════════════════
// DATABASE SEEDER - Initial Data, Roles, and Permissions
// ═══════════════════════════════════════════════════════════════════════════

part of 'database.dart';

extension DatabaseSeeder on AppDatabase {
  /// Seeds all default data needed for a fresh installation.
  ///
  /// In CLIENT mode the server is the authoritative source for branches,
  /// warehouses, safes, units, categories, accounts, and parties — so we
  /// MUST NOT seed them locally or the very first sync will produce
  /// duplicates (server's row inserts alongside the local seed row because
  /// they have different auto-increment ids and different UUIDs). Roles +
  /// admin user are still seeded so the cashier can log in BEFORE the first
  /// pull completes; permissions are wiped-and-rebuilt by sync anyway.
  Future<void> seedInitialData({bool isClientMode = false}) async {
    // ── Seed roles & permissions FIRST (admin user FK depends on role_id=1) ──
    await seedRolesAndPermissions();

    // Seed default admin user with secure password (password: admin).
    // Raw SQL for parity with the Postgres seeder — see comment there for
    // the `withDefault('')` quirk we're sidestepping on drift_postgres.
    // role_id=1 is 'مدير النظام' from seedRolesAndPermissions().
    final existingAdmin = await customSelect(
      "SELECT id FROM users WHERE username = 'admin' LIMIT 1",
    ).get();
    if (existingAdmin.isEmpty) {
      final salt = SecurityService.generateSalt();
      final passwordHash = SecurityService.hashPassword('admin', salt);
      final globalId = UuidV7.generate();
      final boolTrue = sqlBool(true);
      final boolFalse = sqlBool(false);
      await customStatement(
        "INSERT INTO users (username, password_hash, password_salt, display_name, "
        "role_id, is_active, is_locked, global_id) "
        "VALUES ('admin', ?, ?, 'مدير النظام', 1, $boolTrue, $boolFalse, ?)",
        [passwordHash, salt, globalId],
      );
    }

    // ── Master data — server-authoritative entities ──
    // Skip seeding these in client mode so the first DeltaPull doesn't
    // produce duplicates next to locally-created defaults. The cashier
    // experience tolerates a few-seconds gap before warehouses/safes appear
    // because they're not needed until the user actually opens the POS.
    if (!isClientMode) {
      // Seed default branch + warehouse (skip/heal if already flagged) —
      // split into its own method, see [seedDefaultBranchAndWarehouse].
      await seedDefaultBranchAndWarehouse();

      // Seed default units (skip existing)
      final existingUnits = (await select(units).get()).map((u) => u.name).toSet();
      for (final u in [['قطعة', 'قطعة'], ['كيلو', 'كجم'], ['علبة', 'علبة'], ['كرتونة', 'كرتون']]) {
        if (!existingUnits.contains(u[0])) {
          await into(units).insert(UnitsCompanion.insert(
            name: u[0],
            symbol: u[1],
            // Spec 136 ISS-2 — deterministic seed gid (keyed by seed name).
            globalId: Value(UuidV7.deriveSeedGlobalId(
                table: 'units', seedKey: u[0])),
            isSystemDefault: const Value(true),
          ));
        }
      }

      // Seed default categories (skip existing)
      final existingCats = (await select(categories).get()).map((c) => c.name).toSet();
      if (!existingCats.contains('عام')) {
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
      }

      // Seed default safes (skip existing)
      final existingSafes = (await select(safes).get()).map((s) => s.name).toSet();
      for (final s in [
        ['صندوق الكاشير', 'cash'],
        ['الحساب البنكي', 'bank'],
        ['صندوق تحويل كليك', 'click'],
      ]) {
        if (!existingSafes.contains(s[0])) {
          await into(safes).insert(
            SafesCompanion.insert(
              name: s[0],
              safeType: Value(s[1]),
              isDefault: const Value(true),
              // Spec 136 ISS-2 — deterministic seed gid (keyed by stable
              // safeType, not the editable display name).
              globalId: Value(UuidV7.deriveSeedGlobalId(
                  table: 'safes', seedKey: s[1])),
              isSystemDefault: const Value(true),
            ),
          );
        }
      }

      // Seed Chart of Accounts
      await seedChartOfAccounts();

      // الخزائن اتزرعت فوق قبل الدليل المحاسبي، فالربط بيتعمل هنا بعد ما
      // الحسابات بقت موجودة. من غير الربط، طرفا قيد إقفال الوردية بيطلعوا
      // نفس الحساب والقيد صافيه صفر — الدرج بيتفضّى والأستاذ ما بيتحركش.
      await linkSeededSafesToAccounts();

      // Seed delivery companies as fixed customers (Careem, Talabat, Ashyae)
      await seedDeliveryCompanyParties();
    } else {
      debugPrint('[Seeder] Client mode — skipping master data seed (server is authoritative)');
    }

    // Settings are device-local by definition (currency formatting, locale,
    // etc.) — not duplicated by sync, so seed unconditionally.
    final existingCompanyName = await (select(settings)
          ..where((s) => s.key.equals('company_name')))
        .getSingleOrNull();
    if (existingCompanyName == null) {
      await into(settings).insert(
        SettingsCompanion.insert(
          key: 'company_name',
          value: const Value('سوبر ماركت'),
        ),
      );
    }
    final existingTaxRate = await (select(settings)
          ..where((s) => s.key.equals('tax_rate')))
        .getSingleOrNull();
    if (existingTaxRate == null) {
      await into(settings).insert(
        SettingsCompanion.insert(key: 'tax_rate', value: const Value('14')),
      );
    }

    // Note: seedRolesAndPermissions() is called at the top (before user insert)

    // Seed default invoice templates for designer
    await seedDefaultInvoiceTemplates();
  }

  /// Seed the default branch + warehouse, or heal an existing one whose
  /// `is_system_default` flag went missing.
  ///
  /// Spec 129 F6 — isSystemDefault stamps the seeded row so the boot
  /// self-heal (database_startup.dart) gates on the flag instead of
  /// "is the table empty?". Operator renames now survive restart.
  /// FIL-4 (spec 149 B12): gate on is_system_default, NOT "is the table
  /// empty?" — mirrors the PG seeder's _seedBranchIfMissing so the two
  /// paths behave identically. A user-renamed default keeps its flag, so
  /// the rename survives; only when ZERO flagged rows exist (hard-delete,
  /// or a repaired DB whose users were wiped while other branches remained)
  /// do we recreate the canonical default. Previously the SQLite path
  /// skipped reseeding whenever ANY branch existed, so a server that lost
  /// its flagged default never got it back (PG already recovered).
  ///
  /// Split out of [seedInitialData] (spec 150, BUG 5) so it can be
  /// exercised on its own in tests — re-invoking the full seeder duplicates
  /// roles (`seedRolesAndPermissions` has no existence guard).
  Future<void> seedDefaultBranchAndWarehouse() async {
    final flaggedBranch = await (select(branches)
          ..where((b) => b.isSystemDefault.equals(true))
          ..limit(1))
        .getSingleOrNull();
    if (flaggedBranch == null) {
      // BUG 5 heal (spec 150): the flag can go missing from the real main
      // branch (rename, trailing-space mismatch, a v148 backfill exact-
      // name miss) while the row itself survives. Re-flagging it instead
      // of inserting avoids creating a second "الفرع الرئيسي" — there's
      // no UNIQUE on branches.name to catch that.
      final branchSeedGid = UuidV7.deriveSeedGlobalId(
          table: 'branches', seedKey: 'الفرع الرئيسي');
      final unflaggedBranch = await (select(branches)
            ..where((b) =>
                b.globalId.equals(branchSeedGid) |
                b.name.equals('الفرع الرئيسي'))
            ..limit(1))
          .getSingleOrNull();
      if (unflaggedBranch != null) {
        await (update(branches)..where((b) => b.id.equals(unflaggedBranch.id)))
            .write(const BranchesCompanion(isSystemDefault: Value(true)));
      } else {
        await into(branches).insert(
          BranchesCompanion.insert(
            name: 'الفرع الرئيسي',
            // Spec 136 ISS-2 — deterministic seed gid so server + client
            // converge on the sync Tier-1 globalId match instead of name
            // fallback (which trips the duplicate guard).
            globalId: Value(branchSeedGid),
            isSystemDefault: const Value(true),
          ),
        );
      }
    }

    // Seed default warehouse (FIL-4: same is_system_default gate as the
    // branch above; resolve the branch id from the lowest existing branch
    // instead of hardcoding 1 — the recreated default branch may not be id 1
    // on a repaired DB. Matches PG's _seedWarehouseIfMissing).
    final flaggedWarehouse = await (select(warehouses)
          ..where((w) => w.isSystemDefault.equals(true))
          ..limit(1))
        .getSingleOrNull();
    if (flaggedWarehouse == null) {
      final defaultBranch = await (select(branches)
            ..orderBy([(b) => OrderingTerm.asc(b.id)])
            ..limit(1))
          .getSingleOrNull();
      // BUG 5 heal (spec 150) — same pattern as the branch block above.
      final warehouseSeedGid = UuidV7.deriveSeedGlobalId(
          table: 'warehouses', seedKey: 'المخزن الرئيسي');
      final unflaggedWarehouse = await (select(warehouses)
            ..where((w) =>
                w.globalId.equals(warehouseSeedGid) |
                w.name.equals('المخزن الرئيسي'))
            ..limit(1))
          .getSingleOrNull();
      if (unflaggedWarehouse != null) {
        await (update(warehouses)
              ..where((w) => w.id.equals(unflaggedWarehouse.id)))
            .write(const WarehousesCompanion(isSystemDefault: Value(true)));
      } else {
        await into(warehouses).insert(
          WarehousesCompanion.insert(
            name: 'المخزن الرئيسي',
            branchId: Value(defaultBranch?.id ?? 1),
            isDefault: const Value(true),
            // Spec 136 ISS-2 — deterministic seed gid.
            globalId: Value(warehouseSeedGid),
            isSystemDefault: const Value(true),
          ),
        );
      }
    }
  }

  /// L4 (2026-04-28): Wipe master data created by the local seeder so the
  /// first DeltaPull doesn't produce duplicates next to those rows.
  ///
  /// Called by the setup wizard right after the user picks client mode and
  /// before the first sync. Only deletes rows we KNOW were seeded by us:
  /// the three default delivery-company parties, the four default units,
  /// the three default safes, the default branch + warehouse, the "عام"
  /// category, and the chart-of-accounts entries with `is_system=true`.
  /// Anything else (invoices, transactions, custom categories the user
  /// created during testing) stays untouched.
  ///
  /// Safe even when the seed didn't run — DELETE on a non-existent row is
  /// a no-op. Wraps everything in a transaction so a partial failure can't
  /// leave the DB in a half-wiped state.
  Future<void> wipeSeededMasterDataForClient() async {
    await transaction(() async {
      // Delivery-company parties seeded by seedDeliveryCompanyParties()
      try {
        await (delete(parties)
              ..where((p) =>
                  p.isDeliveryCompany.equals(true) &
                  p.name.isIn(const [
                    'شركة توصيل طلبات',
                    'شركة توصيل كريم',
                    'شركة توصيل اشيائي',
                    'طلبات',
                    'كريم',
                    'اشيائي',
                  ])))
            .go();
      } catch (e) {
        debugPrint('[WipeSeed] parties: $e');
      }

      // Default units seeded with these exact names
      try {
        await (delete(units)
              ..where((u) => u.name.isIn(const ['قطعة', 'كيلو', 'علبة', 'كرتونة'])))
            .go();
      } catch (e) {
        debugPrint('[WipeSeed] units: $e');
      }

      // Default category "عام"
      try {
        await (delete(categories)
              ..where((c) => c.name.equals('عام')))
            .go();
      } catch (e) {
        debugPrint('[WipeSeed] categories: $e');
      }

      // Default safes
      try {
        await (delete(safes)
              ..where((s) => s.name.isIn(const [
                    'صندوق الكاشير',
                    'الحساب البنكي',
                    'صندوق تحويل كليك',
                  ])))
            .go();
      } catch (e) {
        debugPrint('[WipeSeed] safes: $e');
      }

      // Default warehouse + branch — only delete if no FK dependencies remain
      // (a fresh install has none, but be defensive in case the user already
      // created an invoice referencing them).
      try {
        await (delete(warehouses)..where((w) => w.name.equals('المخزن الرئيسي'))).go();
      } catch (e) {
        debugPrint('[WipeSeed] warehouses: $e');
      }
      try {
        await (delete(branches)..where((b) => b.name.equals('الفرع الرئيسي'))).go();
      } catch (e) {
        debugPrint('[WipeSeed] branches: $e');
      }

      // Chart of accounts seeded by seedChartOfAccounts() — all marked is_system=true.
      // Delete those that don't yet have any journal entries pointing at them.
      try {
        await customStatement('''
          DELETE FROM accounts
          WHERE is_system = ${sqlBool(true)}
            AND id NOT IN (SELECT DISTINCT account_id FROM journal_entry_lines)
        ''');
      } catch (e) {
        debugPrint('[WipeSeed] accounts: $e');
      }

      // Feature 042 (Bug 2) — fiscal years were missing from the wipe.
      // Result on every fresh CLIENT pairing: the locally-seeded default
      // fiscal year auto-created by `database_startup.dart` (named
      // "السنة المالية YYYY" with a locally-minted globalId) coexists
      // with the server's authoritative row pulled during first-sync,
      // surfacing as duplicate entries in the fiscal-year list/dropdown
      // on the mirror. The `FiscalYearSyncStrategy` has post-sync recovery
      // (Tier-2 name+dates dedup + soft-mark with "(مكرر)"), but
      // prevention belongs HERE alongside branches/warehouses/safes —
      // wipe seeded rows before first sync runs, so the server's row
      // lands without a competitor.
      //
      // Cascade: deleting fiscal_years requires also wiping the
      // accounting_periods generated for them (no other FK references
      // exist at first-sync time). Both tables are CASCADE-free in the
      // schema, so do it explicitly. Wrap each in try/catch so a partial
      // wipe doesn't abort the rest of the transaction.
      try {
        await customStatement('''
          DELETE FROM accounting_periods
          WHERE fiscal_year_id IN (
            SELECT id FROM fiscal_years
            WHERE name LIKE 'السنة المالية %'
          )
        ''');
      } catch (e) {
        debugPrint('[WipeSeed] accounting_periods: $e');
      }
      try {
        await customStatement('''
          DELETE FROM fiscal_years
          WHERE name LIKE 'السنة المالية %'
        ''');
      } catch (e) {
        debugPrint('[WipeSeed] fiscalYears: $e');
      }

      // Spec 131 (FR-003) — clear settings keys that reference master-data
      // ids. Without this, a stale `pos_default_warehouse_id` row can point
      // at a warehouse that was just deleted by the wipe above, causing the
      // POS form to load with a non-existent default warehouse on the next
      // sale → "Strict Mapping Violation" on the server (field bug 2026-05-25).
      // The IN-list + LIKE-prefix together cover the 6 known POS defaults +
      // the per-branch warehouse override family. Single canonical list of
      // literals lives in lib/services/sync/mirror_settings_keys.dart.
      try {
        final placeholders =
            List<String>.filled(kPosDefaultExactKeys.length, '?').join(',');
        await customStatement(
          'DELETE FROM settings WHERE key IN ($placeholders)',
          kPosDefaultExactKeys,
        );
      } catch (e) {
        debugPrint('[WipeSeed] settings (exact pos_default_*): $e');
      }
      try {
        await customStatement(
          'DELETE FROM settings WHERE key LIKE ?',
          ['$kPosDefaultWarehouseBranchPrefix%'],
        );
      } catch (e) {
        debugPrint('[WipeSeed] settings (pos_default_warehouse_branch_%): $e');
      }

      debugPrint('[WipeSeed] ✓ master data wipe complete — first sync will populate from server');
    });
  }

  /// Seed delivery companies as fixed customer parties.
  ///
  /// Spec 129 F6 — isSystemDefault stamps each of the three rows so the boot
  /// self-heal in [seedDeliveryCompanyPartiesIfNotExists] checks the flag
  /// instead of the priceLevel string. An operator who renames "طلبات" to a
  /// localized brand name now keeps the renamed row across restarts.
  Future<void> seedDeliveryCompanyParties() async {
    // طلبات - Talabat
    await into(parties).insert(
      PartiesCompanion.insert(
        name: 'طلبات',
        phone: const Value(null),
        address: const Value(null),
        isCustomer: const Value(true),
        isSupplier: const Value(false),
        isDeliveryCompany: const Value(true),
        balance: const Value(0),
        creditLimit: const Value(999999),
        priceLevel: const Value('talabat'),
        // Spec 136 ISS-2 — deterministic seed gid (keyed by stable priceLevel).
        globalId: Value(UuidV7.deriveSeedGlobalId(
            table: 'parties', seedKey: 'delivery:talabat')),
        isSystemDefault: const Value(true),
      ),
    );

    // كريم - Careem
    await into(parties).insert(
      PartiesCompanion.insert(
        name: 'كريم',
        phone: const Value(null),
        address: const Value(null),
        isCustomer: const Value(true),
        isSupplier: const Value(false),
        isDeliveryCompany: const Value(true),
        balance: const Value(0),
        creditLimit: const Value(999999),
        priceLevel: const Value('careem'),
        // Spec 136 ISS-2 — deterministic seed gid (keyed by stable priceLevel).
        globalId: Value(UuidV7.deriveSeedGlobalId(
            table: 'parties', seedKey: 'delivery:careem')),
        isSystemDefault: const Value(true),
      ),
    );

    // اشيائي - Ashyae
    await into(parties).insert(
      PartiesCompanion.insert(
        name: 'اشيائي',
        phone: const Value(null),
        address: const Value(null),
        isCustomer: const Value(true),
        isSupplier: const Value(false),
        isDeliveryCompany: const Value(true),
        balance: const Value(0),
        creditLimit: const Value(999999),
        priceLevel: const Value('ashyae'),
        // Spec 136 ISS-2 — deterministic seed gid (keyed by stable priceLevel).
        globalId: Value(UuidV7.deriveSeedGlobalId(
            table: 'parties', seedKey: 'delivery:ashyae')),
        isSystemDefault: const Value(true),
      ),
    );
  }

  /// Seed delivery companies for existing databases (migration v30).
  ///
  /// Spec 129 F6 — uses (priceLevel, isSystemDefault) to detect a still-seeded
  /// row. The pre-v148 fallback path matches by priceLevel alone so a delivery
  /// row left over from before v148 (no isSystemDefault flag set) is still
  /// recognised. A user-renamed delivery company that still has its original
  /// priceLevel keeps the seeded slot — never recreated.
  Future<void> seedDeliveryCompanyPartiesIfNotExists() async {
    for (final entry in const [
      ['talabat', 'طلبات'],
      ['careem',  'كريم'],
      ['ashyae',  'اشيائي'],
    ]) {
      final level = entry[0];
      final canonicalName = entry[1];
      final existing = await (select(parties)
            ..where((p) => p.priceLevel.equals(level)))
          .getSingleOrNull();
      if (existing != null) {
        // Pre-v148 row missing the flag — backfill so future restarts
        // recognise it via the canonical predicate.
        if (!existing.isSystemDefault) {
          try {
            await (update(parties)..where((p) => p.id.equals(existing.id)))
                .write(const PartiesCompanion(
              isSystemDefault: Value(true),
            ));
          } catch (e) {
            debugPrint('[Seeder] backfill parties($level).isSystemDefault: $e');
          }
        }
        continue;
      }
      await into(parties).insert(
        PartiesCompanion.insert(
          name: canonicalName,
          phone: const Value(null),
          address: const Value(null),
          isCustomer: const Value(true),
          isSupplier: const Value(false),
          isDeliveryCompany: const Value(true),
          balance: const Value(0),
          creditLimit: const Value(999999),
          priceLevel: Value(level),
          // Spec 136 ISS-2 — deterministic seed gid (keyed by stable priceLevel).
          globalId: Value(UuidV7.deriveSeedGlobalId(
              table: 'parties', seedKey: 'delivery:$level')),
          isSystemDefault: const Value(true),
        ),
      );
    }
  }

  /// Seed Click safe for existing databases
  Future<void> seedClickSafeIfNotExists() async {
    // `.limit(1)` guards against duplicates: a user might have manually
    // created a second click safe, in which case `getSingleOrNull` would
    // throw "Bad state: Too many elements" and crash the seeder.
    final existing = await (select(safes)
          ..where((s) => s.safeType.equals('click'))
          ..limit(1))
        .getSingleOrNull();
    if (existing == null) {
      await into(safes).insert(
        SafesCompanion.insert(
          name: 'صندوق تحويل كليك',
          safeType: const Value('click'),
          isDefault: const Value(true),
          // Spec 136 ISS-2 — deterministic seed gid (matches the main safe
          // seed keying by safeType so both paths converge to one gid).
          globalId: Value(UuidV7.deriveSeedGlobalId(
              table: 'safes', seedKey: 'click')),
        ),
      );
    }
  }
  
  /// Seed standard units if they don't exist
  Future<void> seedStandardUnitsIfNotExists() async {
    final standardUnits = [
      {'name': 'قطعة', 'symbol': 'قطعة'},
      {'name': 'كيلو', 'symbol': 'كجم'},
      {'name': 'علبة', 'symbol': 'علبة'},
      {'name': 'كرتونة', 'symbol': 'كرتون'},
      {'name': 'جرام', 'symbol': 'جرام'},
      {'name': 'متر', 'symbol': 'متر'},
      {'name': 'لتر', 'symbol': 'لتر'},
      {'name': 'باكيت', 'symbol': 'باكيت'},
      {'name': 'كيس', 'symbol': 'كيس'},
      {'name': 'درزن', 'symbol': 'درزن'},
      {'name': 'مللي', 'symbol': 'مل'},
      {'name': 'صندوق', 'symbol': 'صندوق'},
      {'name': 'شوال', 'symbol': 'شوال'},
      {'name': 'لفة', 'symbol': 'لفة'},
      {'name': 'طرد', 'symbol': 'طرد'},
      {'name': 'شدة', 'symbol': 'شدة'},
      {'name': 'قارورة', 'symbol': 'قارورة'},
      {'name': 'بندق', 'symbol': 'بندق'},
      {'name': 'برميل', 'symbol': 'برميل'},
    ];

    for (final u in standardUnits) {
      final existing = await (select(units)..where((ut) => ut.name.equals(u['name']!))).getSingleOrNull();
      if (existing == null) {
        await into(units).insert(UnitsCompanion.insert(
          name: u['name']!,
          symbol: u['symbol']!,
          // Spec 136 ISS-2 — deterministic seed gid (keyed by seed name).
          globalId: Value(UuidV7.deriveSeedGlobalId(
              table: 'units', seedKey: u['name']!)),
        ));
      }
    }
  }


  // -----------------------------------------------------------------------
  // ROLES & PERMISSIONS -- See database_seeder_permissions.dart
  // -----------------------------------------------------------------------

  // -----------------------------------------------------------------------
  // CHART OF ACCOUNTS & TEMPLATES -- See database_seeder_accounts.dart
  // -----------------------------------------------------------------------
}

