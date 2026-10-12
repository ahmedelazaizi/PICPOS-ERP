// ═══════════════════════════════════════════════════════════════════════════
// PARTY DAO - Customer and Supplier Operations
// ═══════════════════════════════════════════════════════════════════════════
//
// This file contains all party-related (customers/suppliers) database operations.
//
// File map (all `part of database.dart`; extensions on AppDatabase):
//   party_dao.dart: stream coalescing helpers, party code generation, insertParty / updateParty / deleteParty (this file)
//   party_reads_dao.dart: watchers, paged lists, branch-scoped reads, getPartyById, invoice due-date resolution
//   party_profile_dao.dart: statement-tab queries (aging invoices, payments, 3-way match, profile rates, papers), batch lookups, FTS search
//   party_coa_repair_dao.dart: Spec 114 COA sub-account repair + historical JE line rewiring
//   party_balances_dao.dart: adjustPartyBalance, outstanding/total balances, party summary, hard delete
//   party_transactions_dao.dart: party transaction history / statement
//   party_reconciliation_dao.dart: AR/AP aging, AR reconciliation, balance mismatches + recompute
//   party_models.dart: PartySummary / PartyStatementEntry / ArReconciliation / ArAgingRow / PartyBalanceMismatch / PartyGroupWithCount
//   party_group_dao.dart: party group CRUD and member assignment (extension PartyGroupDao)
//   party_dedup_dao.dart: duplicate-party detection + dedup repair (Spec 084d)
//   party_dedup_models.dart: dedup data classes
// ═══════════════════════════════════════════════════════════════════════════

part of '../database.dart';

// Spec 115 (L1 + L2) — معالجة rebuild loop على server-mode.
//
// **L1 — distinct(_partyListEquals)**: على server-mode، عمليات clients
// المتعدّدة (sales, payments, balance adjustments) تُولِّد كتابات متكررة
// على parties. Drift يُصدر stream emit على كل write حتى لو محتوى القائمة
// لم يتغيّر. الـ distinct comparator deep-equal يبتلع no-op emissions.
//
// **L2 — debounceTime(200ms)**: حتى مع distinct، burst writes (5 clients
// يدفعون 10 سندات في 1s) تُولِّد ~50 emissions distinct. debounceTime
// يجمّعها في windows 200ms (السقف 200ms مقبول ضمن FR-004 SLA = ≤ 2s).
//
// مرجع: specs/115-parties-rebuild-loop/research.md § الحل المتعدّد الطبقات.
const Duration _kPartyStreamDebounce = Duration(milliseconds: 200);

bool _partyListEquals(List<Party> a, List<Party> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false; // Party.== مُوَلَّد من Drift codegen
  }
  return true;
}

extension on Stream<List<Party>> {
  // الترتيب يهم: distinct أولاً لإلغاء no-op، ثم debounce لتجميع burst.
  Stream<List<Party>> get _coalesced =>
      distinct(_partyListEquals).debounceTime(_kPartyStreamDebounce);
}

/// Extension for Party-related database operations
extension PartyDao on AppDatabase {
  // ═══════════════════════════════════════════════════════════════════════
  // PARTY CODE + CHART-OF-ACCOUNTS INTEGRATION (Phase 1)
  // ═══════════════════════════════════════════════════════════════════════

  /// Parent account codes that every newly-created party is hung beneath.
  /// Customers → 1121 (ذمم عملاء محليون). Suppliers and delivery companies →
  /// 2111 (ذمم موردون محليون). Both codes are seeded by
  /// [seedChartOfAccounts] under their proper hierarchy (`1121` under `112`,
  /// `2111` under `211`).
  ///
  /// **Feature 005 (2026-05-03)** — pre-005 these were `'1201'` and `'2101'`,
  /// codes that existed in [accountPurposes] map historically but were never
  /// added to the seeder. The result was a chart with two parallel control
  /// accounts: the seeded `2111` and the runtime-created `2101` orphan,
  /// each holding a different subset of supplier sub-accounts. Aligning to
  /// the seeder removes the duplication and makes the seeded chart the
  /// single source of truth.
  static const String _arParentCode = '1121';
  static const String _apParentCode = '2111';

  /// Makes sure the two parent accounts used for party linking exist in
  /// the Chart of Accounts. Idempotent — safe to call on every insert.
  /// Returns a map keyed by code to the account id, e.g.
  /// `{'1121': 42, '2111': 57}`.
  ///
  /// On normally-seeded installs both accounts already exist (from
  /// `seedChartOfAccounts`) and this method is a fast no-op lookup. The
  /// fallback insert path is kept as a safety net for partially-seeded
  /// databases (e.g. tests that build the schema without the seeder).
  Future<Map<String, int>> ensurePartyParentAccounts() async {
    Future<int> ensure(String code, String name, String type) async {
      final existing = await (select(accounts)
            ..where((a) => a.code.equals(code)))
          .getSingleOrNull();
      if (existing != null) return existing.id;
      // Parent missing — create a system account. isSystem=true protects
      // it from being accidentally deleted via the normal COA UI.
      return into(accounts).insert(
        AccountsCompanion.insert(
          code: code,
          name: name,
          accountType: type,
          isSystem: const Value(true),
          // UUID-First (Phase 1): stable cross-install identity for sync.
          globalId: Value(UuidV7.generate()),
        ),
      );
    }

    return {
      _arParentCode:
          await ensure(_arParentCode, 'ذمم عملاء محليون', 'asset'),
      _apParentCode:
          await ensure(_apParentCode, 'ذمم موردون محليون', 'liability'),
    };
  }

  /// Computes the prefix used for a party's auto-generated code based on
  /// the party's role flags. Kept as a helper so the UI can preview the
  /// prefix before a save.
  ///
  /// Rules (most specific wins):
  ///   1. Delivery companies → `DLV`
  ///   2. Both customer AND supplier → `CS`
  ///   3. Customer only → `CUST`
  ///   4. Supplier only → `SUP`
  static String partyCodePrefix({
    required bool isCustomer,
    required bool isSupplier,
    required bool isDeliveryCompany,
  }) {
    if (isDeliveryCompany) return 'DLV';
    if (isCustomer && isSupplier) return 'CS';
    if (isCustomer) return 'CUST';
    if (isSupplier) return 'SUP';
    // Defensive fallback — a party must be at least one role, but if
    // none are set we still return a sensible prefix.
    return 'PRT';
  }

  /// Generates the next sequential party code for the given role flags.
  ///
  /// Output format: `<PREFIX>-<5-digit zero-padded>` (e.g. `CUST-00001`,
  /// `SUP-00042`). The counter is scoped per-prefix so customers and
  /// suppliers have independent sequences.
  ///
  /// NOTE: this is a _suggestion_. The caller can override it; uniqueness
  /// is only enforced inside [insertParty].
  Future<String> getNextPartyCode({
    required bool isCustomer,
    required bool isSupplier,
    bool isDeliveryCompany = false,
  }) async {
    final prefix = partyCodePrefix(
      isCustomer: isCustomer,
      isSupplier: isSupplier,
      isDeliveryCompany: isDeliveryCompany,
    );

    // Find the highest existing numeric suffix with this prefix. We use
    // a LIKE query + Drift's max() so it works on both SQLite and the
    // PostgreSQL server backend.
    final codeLike = '$prefix-%';
    final rows = await (select(parties)
          ..where((p) => p.code.like(codeLike)))
        .get();

    int nextSeq = 1;
    for (final row in rows) {
      final c = row.code;
      if (c == null || !c.startsWith('$prefix-')) continue;
      final suffix = c.substring(prefix.length + 1);
      final n = int.tryParse(suffix);
      if (n != null && n >= nextSeq) nextSeq = n + 1;
    }
    return '$prefix-${nextSeq.toString().padLeft(5, '0')}';
  }

  /// Checks if a party code is already in use. Used for manual-entry
  /// validation and as a safety check inside [insertParty].
  Future<bool> isPartyCodeInUse(String code, {int? excludeId}) async {
    final query = select(parties)..where((p) => p.code.equals(code));
    if (excludeId != null) {
      query.where((p) => p.id.equals(excludeId).not());
    }
    final row = await query.getSingleOrNull();
    return row != null;
  }

  /// Insert a new party
  Future<int> insertParty(PartiesCompanion party) async {
    return transaction(() async {
      if (AppConfig.isDemo) {
        // Check HMAC-verified activation status (cached at app startup)
        if (!TrialState.isActivatedCached) {
          final isCustomer = party.isCustomer.value;
          final isSupplier = party.isSupplier.value;
          final policy = TrialState.activePolicy;

          if (isCustomer && policy.maxCustomers != null) {
            final count =
                await (selectOnly(parties)
                      ..addColumns([parties.id.count()])
                      ..where(parties.isCustomer.equals(true)))
                    .map((row) => row.read(parties.id.count()))
                    .getSingle();
            if ((count ?? 0) >= policy.maxCustomers!) {
              throw Exception(
                'تم الوصول للحد الأقصى للعملاء في النسخة التجريبية (${policy.maxCustomers} عميل)',
              );
            }
          }

          if (isSupplier && policy.maxSuppliers != null) {
            final count =
                await (selectOnly(parties)
                      ..addColumns([parties.id.count()])
                      ..where(parties.isSupplier.equals(true)))
                    .map((row) => row.read(parties.id.count()))
                    .getSingle();
            if ((count ?? 0) >= policy.maxSuppliers!) {
              throw Exception(
                'تم الوصول للحد الأقصى للموردين في النسخة التجريبية (${policy.maxSuppliers} مورد)',
              );
            }
          }
        }
      }

      // ── Phase 1: Atomic party+account creation ──────────────────────
      //
      // 1. Ensure both parent accounts (1121, 2111) exist — they are
      //    seeded by seedChartOfAccounts(), so this is a no-op lookup
      //    on normal installs. Test-only databases may need the insert
      //    fallback inside ensurePartyParentAccounts().
      // 2. Resolve the party code: honour any caller-supplied code after
      //    a uniqueness check, otherwise auto-generate `CUST-XXXXX` etc.
      // 3. Insert the party row with the resolved code.
      // 4. For roles that should appear in the Chart of Accounts (all
      //    but a pure "nobody" party), create a sub-account whose code
      //    mirrors the party's suffix so the two are visually linked:
      //        CUST-00042 ↔ 1121-00042
      //        SUP-00042  ↔ 2111-00042
      //        CS-00042   ↔ 1121-00042  (primary AR side)
      //        DLV-00042  ↔ 2111-00042  (payable)
      // 5. Link `parties.accountId` to the new sub-account.
      //
      // Everything runs inside the outer transaction — any failure
      // rolls back the entire operation. No silent fallback (the old
      // behaviour left orphaned parties without accounts).

      final parentAccounts = await ensurePartyParentAccounts();
      final isCustomer = party.isCustomer.present ? party.isCustomer.value : false;
      final isSupplier = party.isSupplier.present ? party.isSupplier.value : false;
      final isDelivery = party.isDeliveryCompany.present
          ? party.isDeliveryCompany.value
          : false;

      // ─── Resolve party code ───────────────────────────────────────
      String partyCode;
      if (party.code.present &&
          party.code.value != null &&
          party.code.value!.trim().isNotEmpty) {
        partyCode = party.code.value!.trim();
        final dup = await isPartyCodeInUse(partyCode);
        if (dup) {
          throw Exception('الكود "$partyCode" مستخدم بالفعل لطرف آخر');
        }
      } else {
        partyCode = await getNextPartyCode(
          isCustomer: isCustomer,
          isSupplier: isSupplier,
          isDeliveryCompany: isDelivery,
        );
      }

      // ─── Decide which parent account, if any ──────────────────────
      // A customer-supplier (both) uses the AR parent; that's the
      // convention already used in the journal_entry_factory too.
      int? parentAccountId;
      String parentAccountType = 'asset';
      String namePrefix = 'عميل';
      if (isCustomer) {
        parentAccountId = parentAccounts[_arParentCode];
        parentAccountType = 'asset';
        namePrefix = isSupplier ? 'عميل/مورد' : 'عميل';
      } else if (isSupplier) {
        parentAccountId = parentAccounts[_apParentCode];
        parentAccountType = 'liability';
        namePrefix = 'مورد';
      } else if (isDelivery) {
        parentAccountId = parentAccounts[_apParentCode];
        parentAccountType = 'liability';
        namePrefix = 'شركة توصيل';
      }

      // ─── Insert the party with its resolved code ──────────────────
      // UUID-First (Phase 1): mint a global_id if the caller didn't supply
      // one, so every party has a stable cross-install identity from the
      // moment it's created.
      final partyHasGid = party.globalId.present &&
          (party.globalId.value?.isNotEmpty ?? false);
      final partyWithCode = party.copyWith(
        code: Value(partyCode),
        globalId: partyHasGid ? party.globalId : Value(UuidV7.generate()),
      );
      final partyId = await into(parties).insert(partyWithCode);

      // ─── Create and link sub-account if role warrants it ──────────
      if (parentAccountId != null) {
        // Mirror the party's numeric suffix into the account code.
        // e.g. "CUST-00042" → "00042" → "1121-00042".
        final dashIdx = partyCode.indexOf('-');
        final suffix = dashIdx >= 0 && dashIdx < partyCode.length - 1
            ? partyCode.substring(dashIdx + 1)
            : partyCode;
        final parentCode = isCustomer ? _arParentCode : _apParentCode;
        final accountCode = '$parentCode-$suffix';

        // Spec 118 (Bug X) — recover-on-collision بدلاً من throw.
        //
        // الـ field log أظهر [MIRROR-WRITE] parties/insert failed (500):
        // "كود الحساب الفرعى '1121-00002' مستخدم بالفعل" 3 مرات. السبب:
        // الـ mirror يولّد party code من local max() لكن الـ local قد
        // يفتقد parties من delta pull غير مكتمل، فيُرسل partyCode جديد
        // محلياً لكن مُكافئه accountCode يتصادم مع party سابق على السيرفر
        // (بـ partyCode مختلف).
        //
        // الـ recovery: لو الـ accountCode موجود، جرّب suffix التالي
        // (numeric increment). نحاول حتى 100 مرة قبل الاستسلام.
        String resolvedAccountCode = accountCode;
        int? numericSuffix = int.tryParse(suffix);
        if (numericSuffix != null) {
          for (var attempt = 0; attempt < 100; attempt++) {
            final dupAcc = await (select(accounts)
                  ..where((a) => a.code.equals(resolvedAccountCode)))
                .getSingleOrNull();
            if (dupAcc == null) break;
            numericSuffix = numericSuffix! + 1;
            resolvedAccountCode = '$parentCode-${numericSuffix.toString().padLeft(suffix.length, '0')}';
          }
        }
        // فحص نهائي — لو ما زال يوجد collision بعد 100 محاولة (نادر جداً)،
        // نرفع كمجال للنظر فيه.
        final finalDup = await (select(accounts)
              ..where((a) => a.code.equals(resolvedAccountCode)))
            .getSingleOrNull();
        if (finalDup != null) {
          throw Exception(
            'كود الحساب الفرعى "$resolvedAccountCode" مستخدم بالفعل — '
            'تحقق من دليل الحسابات.',
          );
        }

        final accountName = '$namePrefix: ${party.name.value} ($partyCode)';
        final accId = await into(accounts).insert(
          AccountsCompanion.insert(
            code: resolvedAccountCode,
            name: accountName,
            accountType: parentAccountType,
            parentId: Value(parentAccountId),
            isSystem: const Value(false),
            // UUID-First (Phase 1): stable cross-install identity for sync.
            globalId: Value(UuidV7.generate()),
          ),
        );

        await (update(parties)..where((p) => p.id.equals(partyId))).write(
          PartiesCompanion(accountId: Value(accId)),
        );

        // ─── Opening balance JE ───────────────────────────────────────
        // Audit finding #1 (02_accounting_correctness.md): a non-zero
        // opening `balance` used to update `parties.balance` + link the
        // sub-account without posting any JE — trial balance diverged
        // from `parties.balance` the moment any party was created with
        // a non-zero opening. Post the offsetting entry here so the GL
        // stays balanced from day one.
        //
        // Counterpart = retained_earnings (313), same convention the
        // fiscal-year opening JE already uses (accounting_fiscal_dao).
        // If the mapping isn't present, skip the JE with a loud debug —
        // same fallback policy as the fiscal flow.
        final openingBalance = party.balance.present
            ? (party.balance.value)
            : 0.0;
        if (openingBalance.abs() > 0.001) {
          final retainedEarnings =
              await accountingDao.getAccountByPurpose('retained_earnings');
          if (retainedEarnings == null) {
            debugPrint(
              '[PartyDao] ⚠️ opening balance JE skipped — '
              'retained_earnings mapping missing (party $partyCode, '
              'balance $openingBalance)',
            );
          } else {
            final openingLines = <JournalLine>[];
            final absAmount = openingBalance.abs();
            final desc = 'رصيد افتتاحى — $namePrefix: '
                '${party.name.value} ($partyCode)';
            final partySideDebits = (isCustomer && openingBalance > 0) ||
                (!isCustomer && openingBalance < 0);
            if (partySideDebits) {
              openingLines.add(JournalLine(
                accountId: accId,
                debit: absAmount,
                description: desc,
              ));
              openingLines.add(JournalLine(
                accountId: retainedEarnings.id,
                credit: absAmount,
                description: desc,
              ));
            } else {
              openingLines.add(JournalLine(
                accountId: retainedEarnings.id,
                debit: absAmount,
                description: desc,
              ));
              openingLines.add(JournalLine(
                accountId: accId,
                credit: absAmount,
                description: desc,
              ));
            }
            await accountingDao.createJournalEntry(
              description: desc,
              date: DateTime.now(),
              lines: openingLines,
              referenceType: 'party_opening_balance',
              referenceId: partyId,
              isAutoPosted: true,
            );
          }
        }
      }

      return partyId;
    });
  }

  /// Update a party
  Future<bool> updateParty(Party party) async {
    // J3 — طرفٌ نظاميٌّ يبقى نشطاً وفي دوره؛ الاسمُ وحدَه (وما شابهه) يُعدَّل.
    final role = await systemRoleOfParty(party.id);
    return update(parties)
        .replace(role == null ? party : lockSystemPartyFields(party, role));
  }

  /// Check if party has any transaction history
  Future<bool> partyHasTransactions(int partyId) async {
    // Check sales invoices
    final salesCount =
        await (selectOnly(salesInvoices)
              ..addColumns([salesInvoices.id.count()])
              ..where(salesInvoices.customerId.equals(partyId)))
            .map((row) => row.read(salesInvoices.id.count())!)
            .getSingle();
    if (salesCount > 0) return true;

    // Check purchase invoices
    final purchaseCount =
        await (selectOnly(purchaseInvoices)
              ..addColumns([purchaseInvoices.id.count()])
              ..where(purchaseInvoices.supplierId.equals(partyId)))
            .map((row) => row.read(purchaseInvoices.id.count())!)
            .getSingle();
    if (purchaseCount > 0) return true;

    // Check safe transactions (payments/receipts)
    final transactionCount =
        await (selectOnly(safeTransactions)
              ..addColumns([safeTransactions.id.count()])
              ..where(safeTransactions.partyId.equals(partyId)))
            .map((row) => row.read(safeTransactions.id.count())!)
            .getSingle();
    return transactionCount > 0;
  }

  /// Soft delete a party (with transaction history check)
  Future<void> deleteParty(int partyId) async {
    // J3 — «عميل نقدي» / «مورد نقدي» نظاميّان لا يُحذفان.
    await assertPartyDeletable(partyId);
    // Check for transaction history before allowing deletion
    final hasTransactions = await partyHasTransactions(partyId);
    if (hasTransactions) {
      throw Exception(
        'لا يمكن حذف هذا العميل/المورد - يوجد سجل معاملات مرتبط به. استخدم إلغاء التفعيل بدلاً من ذلك.',
      );
    }

    // Soft delete - mark as inactive
    await (update(parties)..where((p) => p.id.equals(partyId))).write(
      const PartiesCompanion(isActive: Value(false)),
    );
  }
}
