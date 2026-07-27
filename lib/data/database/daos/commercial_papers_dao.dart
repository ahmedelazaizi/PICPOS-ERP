part of '../database.dart';

// ═══════════════════════════════════════════════════════════════════════════
// COMMERCIAL PAPERS DAO — الأوراق التجارية (شيكات / كمبيالات)
// ═══════════════════════════════════════════════════════════════════════════

extension CommercialPapersDao on AppDatabase {
  // ─────────────────────────────────────────────────────────────────────────
  // COMMERCIAL PAPERS CRUD
  // ─────────────────────────────────────────────────────────────────────────

  /// Watch all commercial papers, newest first
  Stream<List<CommercialPaperData>> watchCommercialPapers({
    String? status,
    String? direction,
  }) {
    final q = select(commercialPapers)
      ..orderBy([(p) => OrderingTerm.desc(p.dueDate)]);
    if (status != null) q.where((p) => p.status.equals(status));
    if (direction != null) q.where((p) => p.direction.equals(direction));
    return q.watch();
  }

  /// Get a single commercial paper by ID
  Future<CommercialPaperData?> getCommercialPaper(int id) {
    return (select(
      commercialPapers,
    )..where((p) => p.id.equals(id))).getSingleOrNull();
  }

  /// Get papers due within a date range
  Future<List<CommercialPaperData>> getPapersDueBetween(
    DateTime from,
    DateTime to,
  ) {
    return (select(commercialPapers)
          ..where((p) => p.dueDate.isBetween(Variable(from), Variable(to)))
          ..where((p) => p.status.isIn(['pending', 'deposited']))
          ..orderBy([(p) => OrderingTerm.asc(p.dueDate)]))
        .get();
  }

  /// Create a new commercial paper (شيك/كمبيالة)
  ///
  /// Cluster 030 / Bug D: optional [globalId] lets the caller pass a
  /// pre-minted UUID so mirror/client and server converge on the SAME
  /// identity. Without it, the mirror's interceptor sent the create
  /// to the server with no globalId; server minted its own; the
  /// mirror's local row had a different globalId; the next
  /// `update_status` lookup-by-globalId on the server failed and
  /// produced "Commercial paper not found".
  Future<int> createCommercialPaper({
    required String paperNumber,
    required String type, // cheque, promissory_note, bill_of_exchange
    required String direction, // received, issued
    required int partyId,
    required double amount,
    required DateTime issueDate,
    required DateTime dueDate,
    String? bankName,
    String? bankBranch,
    String? accountNumber,
    int? safeId,
    String? notes,
    String? globalId,
  }) async {
    return transaction(() async {
      // Spec 112 — Real-world cheque uniqueness scope.
      //
      // Pre-112 the check was (paperNumber, direction, type) which is
      // strictly too tight for `received` cheques: customer A can hand
      // us cheque #20 drawn on bank X while customer B hands us cheque
      // #20 drawn on bank Y — both legitimate, but the old check rejected
      // the second one with "ورقة تجارية برقم 20 (received) موجودة مسبقاً"
      // (field log 2026-05-20 from mirror).
      //
      // New uniqueness:
      //   • received  → (paperNumber, type, partyId)  — same customer twice
      //                  with the same paper number is a real duplicate
      //   • issued    → (paperNumber, type, bankName) — our own chequebook
      //                  numbers are unique per drawer bank
      //
      // `.limit(1)` is still defensive against legacy duplicate rows that
      // a failed DeltaPull may have left behind (Cluster 028 / Bug 3 —
      // without it, `getSingleOrNull` throws "too many elements" and
      // blocks the dialog).
      final dupQuery = select(commercialPapers)
        ..where((p) => p.paperNumber.equals(paperNumber))
        ..where((p) => p.direction.equals(direction))
        ..where((p) => p.type.equals(type))
        ..where((p) => p.status.isNotIn(const ['cancelled']));
      if (direction == 'received') {
        dupQuery.where((p) => p.partyId.equals(partyId));
      } else if (bankName != null && bankName.trim().isNotEmpty) {
        dupQuery.where((p) => p.bankName.equals(bankName.trim()));
      }
      final existing = await (dupQuery..limit(1)).getSingleOrNull();
      if (existing != null) {
        final scopeLabel = direction == 'received'
            ? 'لنفس العميل'
            : (bankName != null && bankName.isNotEmpty
                ? 'لنفس البنك ($bankName)'
                : '');
        throw Exception(
            'ورقة تجارية برقم $paperNumber ($direction) موجودة مسبقاً $scopeLabel');
      }

      final id = await into(commercialPapers).insert(
        CommercialPapersCompanion.insert(
          paperNumber: paperNumber,
          type: type,
          direction: direction,
          partyId: partyId,
          amount: amount,
          issueDate: issueDate,
          dueDate: dueDate,
          bankName: Value(bankName),
          bankBranch: Value(bankBranch),
          accountNumber: Value(accountNumber),
          safeId: Value(safeId),
          notes: Value(notes),
          // UUID-First Phase 1 Slice 3: cheques/bills need stable cross-
          // install identity so endorsement history syncs deterministically.
          // Cluster 030 / Bug D: honour caller-provided globalId so mirror
          // and server converge on the same identity (otherwise the
          // mirror's update_status hits "paper not found" on the server).
          globalId: Value(globalId ?? UuidV7.generate()),
        ),
      );

      final paper = await getCommercialPaper(id);
      if (paper != null) {
        await _autoPostPaperStatusChange(paper, 'none', 'pending');
      }

      return id;
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // STATUS MANAGEMENT + AUTO-POSTING
  // ─────────────────────────────────────────────────────────────────────────

  /// Change the status of a commercial paper with full audit trail + auto-posting
  ///
  /// Feature 048 (v130): [counterAccountId] is the user-chosen contra leg
  /// for the auto-posted JE. The status-change dialog presents an
  /// "الحساب المقابل" autocomplete; that selection now flows through
  /// to `_autoPostPaperStatusChange` instead of being silently dropped
  /// into the notes string. Null falls back to the legacy purposes-map
  /// resolution (`cash` / `bank`) so standalone callers + replays of
  /// pre-v130 outbox entries keep working.
  Future<void> changePaperStatus({
    required int paperId,
    required String newStatus,
    required int changedBy,
    String? notes,
    int? endorsedToPartyId,
    int? costCenterId,
    int? counterAccountId,
  }) async {
    await _ensureValidActor(changedBy);
    await transaction(() async {
      final paper = await getCommercialPaper(paperId);
      if (paper == null) {
        throw Exception('Commercial paper not found: $paperId');
      }

      // 0. Soft/Hard Period Closing Gating
      await accountingDao.validateFinancialPeriod(DateTime.now(), operation: 'تغيير حالة ورقة تجارية');

      // Prevent redundant status change
      final oldStatus = paper.status;

      // Update paper status
      await (update(
        commercialPapers,
      )..where((p) => p.id.equals(paperId))).write(
        CommercialPapersCompanion(
          status: Value(newStatus),
          endorsedToPartyId: endorsedToPartyId != null
              ? Value(endorsedToPartyId)
              : const Value.absent(),
        ),
      );

      // Record status history
      await into(paperStatusHistory).insert(
        PaperStatusHistoryCompanion.insert(
          paperId: paperId,
          fromStatus: oldStatus,
          toStatus: newStatus,
          changedBy: changedBy,
          notes: Value(notes),
        ),
      );

      // Auto-post journal entry for status change
      await _autoPostPaperStatusChange(
        paper,
        oldStatus,
        newStatus,
        costCenterId: costCenterId,
        counterAccountId: counterAccountId,
      );
    });
  }

  /// `paper_status_history.changed_by` is a NOT NULL FK to users. A caller that
  /// passes an id with no matching user — e.g. the repository's `changedBy ?? 0`
  /// fallback when no acting user was supplied — would otherwise fail the
  /// history insert with an opaque `SqliteException(787)` at the client (a
  /// failure that stayed invisible to the tests while FK enforcement was off).
  /// Fail loud and actionable instead of writing a broken foreign key.
  Future<void> _ensureValidActor(int changedBy) async {
    final actor = await (select(users)..where((u) => u.id.equals(changedBy)))
        .getSingleOrNull();
    if (actor == null) {
      throw StateError(
        'commercial paper status change: changedBy=$changedBy is not a valid '
        'user id — a real acting user must be supplied',
      );
    }
  }

  /// Auto-post journal entries for commercial paper status changes
  ///
  /// Feature 048 (v130): [counterAccountId] overrides the default
  /// `cash` / `bank` purpose lookup for the contra leg. The status
  /// transitions that consume the override:
  ///   - received/deposited: bank leg → user-chosen account
  ///   - received/cashed: cash leg → user-chosen account
  ///   - paid/deposited / paid/cashed: bank or cash → user-chosen
  /// Other transitions (pending issue / bounced / endorsed) don't
  /// touch a treasury account and ignore the override.
  Future<void> _autoPostPaperStatusChange(
    CommercialPaperData paper,
    String oldStatus,
    String newStatus, {
    int? costCenterId,
    int? counterAccountId,
  }) async {
    // Look up account IDs via the central purposes map so codes stay in
    // sync with the seeded chart of accounts. The previous implementation
    // hard-coded codes ('1202','2102','1101','1102','1201','2101') that
    // do NOT exist in the v110 chart (seed uses 1123/2113/1111/1113/1121/
    // 2111), so EVERY lookup returned null, the `cashAccount==null` guard
    // fired and the journal entry was silently skipped — which is exactly
    // why deposits didn't show up in دليل الحسابات or دفتر اليومية.
    //
    // Route the AR/AP lines through the customer/supplier sub-account
    // when possible so per-party balances appear in the COA tree (same
    // pattern applied to sales/purchase posting).
    final notesReceivable = await _cpResolveAccount('notes_receivable');
    final notesPayable = await _cpResolveAccount('notes_payable');
    final defaultCashAccount = await _cpResolveAccount('cash');
    final defaultBankAccount = await _cpResolveAccount('bank');

    // Feature 048 — caller-chosen contra leg takes precedence over the
    // defaults from the purposes map. Validates the override actually
    // exists; silently falls back to the default if the id is stale
    // (deleted account, partial mirror sync) so the JE still posts.
    //
    // Spec 082b — convert the fallback notice from debugPrint to
    // DiagnosticLogger. Field smoke V148 reported "تسديد الشيك لا يظهر
    // بدفتر الأستاذ مع اختيار الحساب المقابل"; without a persistent
    // log line, support could not tell whether the JE was missing
    // because the override silently fell back to a null default
    // (purposes map unmapped → per-arm warnMissing → JE skipped) or
    // for some other reason. The CP-AUTOPOST-OVERRIDE-FALLBACK tag
    // surfaces the fallback so support can correlate "operator picked
    // account X, JE landed on account Y" without database forensics.
    Account? counterOverride;
    if (counterAccountId != null) {
      counterOverride = await (select(accounts)
            ..where((a) => a.id.equals(counterAccountId))
            ..limit(1))
          .getSingleOrNull();
      if (counterOverride == null) {
        await DiagnosticLogger.log(
          'CP-AUTOPOST-OVERRIDE-FALLBACK',
          'counterAccountId=$counterAccountId not found locally '
              '(paper.id=${paper.id} transition=$oldStatus→$newStatus '
              'direction=${paper.direction}) — falling back to '
              'purposes-map defaults. If JE is missing, the default '
              'cash/bank purpose is likely unmapped (look for '
              'CP-AUTOPOST-WARN line immediately below).',
        );
      }
    }
    final cashAccount = counterOverride ?? defaultCashAccount;
    final bankAccount = counterOverride ?? defaultBankAccount;
    final receivablesControl = await _cpResolveAccount('receivables');
    final payablesControl = await _cpResolveAccount('payables');
    // Prefer the party's sub-account when the paper is tied to a specific
    // customer/supplier (e.g. `1121-00042`), falling back to the control
    // account if the party has no linked sub-account.
    final partyRow = await (select(parties)..where((p) => p.id.equals(paper.partyId))..limit(1))
        .getSingleOrNull();
    Account? partySubAccount;
    if (partyRow?.accountId != null) {
      partySubAccount = await (select(accounts)..where((a) => a.id.equals(partyRow!.accountId!))..limit(1))
          .getSingleOrNull();
    }
    final receivables = partySubAccount ?? receivablesControl;
    final payables = partySubAccount ?? payablesControl;

    // Spec 082 — per-transition account checks.
    //
    // Previously this method had a global `if (cashAccount == null ||
    // bankAccount == null) return;` guard at this point. That gate aborted
    // the ENTIRE auto-post — including the JE — whenever either purpose was
    // unmapped, even for transitions that only need one of the two (e.g.
    // issued/cashed only needs bankAccount). The status update and the safe
    // side-effects still ran, so the books and the treasury silently drifted
    // apart with no log signal.
    //
    // We gate per switch arm on the specific accounts that arm needs and call
    // `warnMissing` when a required mapping is absent.
    //
    // Spec 135 silent-drift (a): `warnMissing` now THROWS (fail-loud) — it does
    // NOT leave `lines` empty and continue. The whole changePaperStatus runs
    // inside transaction() (see method top), so a missing mapping rolls back
    // the status update, the JE, AND the balance side-effects together. This
    // replaced the earlier warn-and-skip behaviour that let a status change +
    // party-balance move land with no GL entry (books vs treasury drift). The
    // balance side-effects (_cpApplyBalanceSideEffects) run only AFTER a real
    // JE is posted, and the Spec 129 F5 idempotency guard below returns early
    // (skipping BOTH the JE and the balance move) on a replayed transition —
    // so the party balance is always tied to an actual new JE insert (the
    // re-presentation double-debit guard, silent-drift (b)).
    Future<void> warnMissing(String purpose, String transition) async {
      final arabicPurpose = {
        'bank': 'حساب البنك',
        'cash': 'حساب الصندوق',
        'notes_receivable': 'أوراق القبض',
        'notes_payable': 'أوراق الدفع',
        'receivables': 'ذمم العملاء',
        'payables': 'ذمم الموردين',
      }[purpose] ?? purpose;
      // Spec 136 (review 2026-06-14): the fail-loud rewrite dropped the old
      // persisted CP-AUTOPOST-WARN — re-emit it so the blocked transition is
      // traceable in the field log, not just surfaced as a thrown toast.
      await DiagnosticLogger.log(
          'CP-AUTOPOST-WARN',
          'شيك ${paper.paperNumber} الانتقال=$transition محظور — '
          '$arabicPurpose ($purpose) غير مربوط؛ تم التراجع عن تغيير الحالة '
          'وحركة الرصيد. اربطه في الدليل المحاسبي.');
      throw Exception('لا يمكن الاستمرار: $arabicPurpose غير مربوط في الدليل المحاسبي. يرجى مراجعة إعدادات الحسابات.');
    }

    List<JournalLine> lines = [];
    String description = '';

    // Hotfix 2026-05-26 (field smoke) — every per-line `description` now
    // includes the cheque number + drawee bank (when known) so the general
    // ledger / sub-ledger / customer statement / bank statement views all
    // show "تحصيل شيك 100100 - بنك مصر" instead of the generic "البنك -
    // تحصيل" that left the operator unable to trace which cheque the row
    // belonged to. The JE header `description` was already cheque-aware;
    // the per-line descriptions were not, and most ledger views render
    // the per-line text. Symmetric across all 10 transition arms below.
    final chequeRef = paper.bankName != null && paper.bankName!.trim().isNotEmpty
        ? 'شيك ${paper.paperNumber} - ${paper.bankName!.trim()}'
        : 'شيك ${paper.paperNumber}';

    if (paper.direction == 'received') {
      // ══════ RECEIVED PAPERS (أوراق واردة/قبض) ══════
      switch (newStatus) {
        case 'pending': // استلام شيك
          if (notesReceivable != null && receivables != null) {
            description = 'استلام شيك رقم ${paper.paperNumber}';
            lines = [
              JournalLine(
                accountId: notesReceivable.id,
                debit: paper.amount,
                credit: 0,
                description: 'أوراق قبض - استلام $chequeRef',
              ),
              JournalLine(
                accountId: receivables.id,
                debit: 0,
                credit: paper.amount,
                description: 'استلام $chequeRef',
              ),
            ];
          } else {
            if (notesReceivable == null) await warnMissing('notes_receivable', 'received/$newStatus');
            if (receivables == null) await warnMissing('receivables', 'received/$newStatus');
          }
          break;
        case 'deposited': // إيداع برسم التحصيل — حالة وسيطة، لا تلمس البنك
          // Spec 136 (field 2026-06-08): deposit is INTERMEDIATE — the cheque is
          // handed to the bank for collection but the money has NOT cleared, so
          // it must NOT debit the bank. The cheque stays in أوراق القبض (under
          // collection) until "تحصيل" clears it to the bank exactly ONCE.
          // Pre-fix this debited the bank AND credited the bank safe, so
          // إيداع→تحصيل recorded the cheque value TWICE. No JE / no safe move.
          description = 'إيداع شيك رقم ${paper.paperNumber} برسم التحصيل';
          break;
        case 'cashed': // تحصيل الشيك (بالبنك بعد الإيداع، أو نقداً مباشرةً)
          {
            // Spec 136 (field 2026-06-08): a cheque collected AFTER being
            // deposited clears into the BANK; one cashed directly at the
            // counter (straight from pending) goes to CASH. Because the deposit
            // no longer touches the bank, the value now hits exactly ONCE here.
            final collectedViaBank = oldStatus == 'deposited' ||
                oldStatus == 'deposited_for_collection';
            final collectionAccount =
                collectedViaBank ? bankAccount : cashAccount;
            if (notesReceivable != null && collectionAccount != null) {
              description = collectedViaBank
                  ? 'تحصيل شيك رقم ${paper.paperNumber} بالبنك'
                  : 'تحصيل شيك رقم ${paper.paperNumber} نقداً';
              lines = [
                JournalLine(
                  accountId: collectionAccount.id,
                  debit: paper.amount,
                  credit: 0,
                  description: collectedViaBank
                      ? 'تحصيل $chequeRef بالبنك'
                      : 'تحصيل $chequeRef نقداً',
                ),
                JournalLine(
                  accountId: notesReceivable.id,
                  debit: 0,
                  credit: paper.amount,
                  description: 'أوراق قبض - تحصيل $chequeRef',
                ),
              ];
            } else if (collectionAccount == null && notesReceivable != null) {
              await warnMissing(
                  collectedViaBank ? 'bank' : 'cash', 'received/$newStatus');
            }
          }
          break;
        case 'bounced': // ارتجاع (شيك مرتد)
          if (notesReceivable != null && receivables != null) {
            description = 'ارتجاع شيك رقم ${paper.paperNumber}';
            lines = [
              JournalLine(
                accountId: receivables.id,
                debit: paper.amount,
                credit: 0,
                description: 'ارتجاع $chequeRef',
              ),
              JournalLine(
                accountId: notesReceivable.id,
                debit: 0,
                credit: paper.amount,
                description: 'أوراق قبض - ارتجاع $chequeRef',
              ),
            ];
          } else {
            if (notesReceivable == null) await warnMissing('notes_receivable', 'received/$newStatus');
            if (receivables == null) await warnMissing('receivables', 'received/$newStatus');
          }
          break;
        case 'endorsed': // تظهير لطرف ثالث
          if (notesReceivable != null && payables != null) {
            description = 'تظهير شيك رقم ${paper.paperNumber}';
            lines = [
              JournalLine(
                accountId: payables.id,
                debit: paper.amount,
                credit: 0,
                description: 'تظهير $chequeRef',
              ),
              JournalLine(
                accountId: notesReceivable.id,
                debit: 0,
                credit: paper.amount,
                description: 'أوراق قبض - تظهير $chequeRef',
              ),
            ];
          } else {
            if (notesReceivable == null) await warnMissing('notes_receivable', 'received/$newStatus');
            if (payables == null) await warnMissing('payables', 'received/$newStatus');
          }
          break;
        case 'in_portfolio': // حافظة الشيكات — لا تأثير محاسبي
          description = 'إدخال شيك رقم ${paper.paperNumber} في الحافظة';
          // No journal entry — purely organizational
          break;
        case 'deposited_for_collection': // إيداع برسم التحصيل — حالة وسيطة
          // Spec 136 — same as 'deposited': intermediate (under collection), no
          // bank debit. The bank is credited once at 'cashed'.
          description = 'إيداع شيك رقم ${paper.paperNumber} برسم التحصيل';
          break;
      }
    } else {
      // ══════ ISSUED PAPERS (أوراق صادرة/دفع) ══════
      switch (newStatus) {
        case 'pending': // إصدار شيك
          if (notesPayable != null && payables != null) {
            description = 'إصدار شيك رقم ${paper.paperNumber}';
            lines = [
              JournalLine(
                accountId: payables.id,
                debit: paper.amount,
                credit: 0,
                description: 'إصدار $chequeRef',
              ),
              JournalLine(
                accountId: notesPayable.id,
                debit: 0,
                credit: paper.amount,
                description: 'أوراق دفع - إصدار $chequeRef',
              ),
            ];
          } else {
            if (notesPayable == null) await warnMissing('notes_payable', 'issued/$newStatus');
            if (payables == null) await warnMissing('payables', 'issued/$newStatus');
          }
          break;
        case 'cashed': // تم صرف الشيك
          if (notesPayable != null && bankAccount != null) {
            description = 'صرف شيك رقم ${paper.paperNumber}';
            lines = [
              JournalLine(
                accountId: notesPayable.id,
                debit: paper.amount,
                credit: 0,
                description: 'أوراق دفع - صرف $chequeRef',
              ),
              JournalLine(
                accountId: bankAccount.id,
                debit: 0,
                credit: paper.amount,
                description: 'صرف $chequeRef',
              ),
            ];
          } else if (bankAccount == null && notesPayable != null) {
            await warnMissing('bank', 'issued/$newStatus');
          }
          break;
        case 'bounced': // ارتجاع شيك صادر
          if (notesPayable != null && payables != null) {
            description = 'ارتجاع شيك صادر رقم ${paper.paperNumber}';
            lines = [
              JournalLine(
                accountId: notesPayable.id,
                debit: paper.amount,
                credit: 0,
                description: 'أوراق دفع - ارتجاع $chequeRef',
              ),
              JournalLine(
                accountId: payables.id,
                debit: 0,
                credit: paper.amount,
                description: 'ارتجاع شيك صادر $chequeRef',
              ),
            ];
          } else {
            if (notesPayable == null) await warnMissing('notes_payable', 'issued/$newStatus');
            if (payables == null) await warnMissing('payables', 'issued/$newStatus');
          }
          break;
      }
    }

    // Spec 129 F5 — deterministic JE globalId replaces the legacy
    // `[IDEM:cp-<paperId>-<newStatus>]` description tag.
    //
    // Why: the tag-based scanner relied on substring matching, which broke
    // when server-pull JEs landed without the tag (Spec 117 Bug H workaround
    // was to widen the predicate, but that still left a race between mirror
    // and server). Deterministic globalIds let `journal_entries.globalId`
    // UNIQUE catch the duplicate at INSERT time on whichever side arrives
    // second — no scan, no description-string coupling.
    //
    // Read side: the `[IDEM:`/description-prefix scanner stays alive for one
    // release (FR-503) so legacy rows still dedup. Write side stops emitting
    // `[IDEM:…]` markers (FR-504, enforced by a follow-up grep test).
    //
    // Fallback: if `paper.globalId` is null (legacy pre-v118 row that never
    // sync'd), fall back to `cp-id-<paperId>` so the formula still produces
    // a deterministic string. Field hot-path always has a globalId because
    // every CP write path mints one.
    final paperSourceGid = (paper.globalId != null && paper.globalId!.isNotEmpty)
        ? paper.globalId!
        : 'cp-id-${paper.id}';
    final jeGid = JournalEntryGid.compute(
      sourceType: JournalEntryGid.sourceCommercialPaper,
      sourceGid: paperSourceGid,
      verb: newStatus,
    );
    if (lines.isNotEmpty) {
      // Spec 117 (Bug H) carry-over — keep the legacy scanner alive for the
      // transition window. Once the `[IDEM:` retirement spec ships and any
      // remaining tagged rows are gone, this widened predicate plus the
      // `'[IDEM:cp-${paper.id}-$newStatus]'` literal can be removed (FR-503).
      final legacyIdemTag = '[IDEM:cp-${paper.id}-$newStatus]';
      final existing = await (select(journalEntries)
            ..where((e) =>
                e.referenceType.equals('commercial_paper') &
                e.referenceId.equals(paper.id) &
                e.isDeleted.equals(false) &
                (e.globalId.equals(jeGid) |
                 e.description.contains(legacyIdemTag) |
                 e.description.like('$description%')))
            ..limit(1))
          .getSingleOrNull();
      if (existing != null) {
        debugPrint('[CP-AUTOPOST] Skipping duplicate JE + balance update '
            'for paper.id=${paper.id} transition=$newStatus — already '
            'posted as JE id=${existing.id}. '
            '(Spec 129 F5 — globalId-first guard with [IDEM:…] fallback.)');
        unawaited(DiagnosticLogger.log('CP-AUTOPOST',
            'Spec 129 F5 — duplicate prevented paper=${paper.id} '
            'transition=$newStatus matched JE id=${existing.id} '
            'gid=$jeGid'));
        return; // Both JE and balance side-effects already applied earlier.
      }

      // Spec 136 (B2) — UNIQUE(global_id) hardening. The active-dup guard above
      // filters isDeleted=false, but the deterministic jeGid is STILL occupied
      // in the UNIQUE index by any SOFT-DELETED JE for the same (paper,
      // transition). Re-applying the transition (an operator's clean re-do
      // after soft-deleting the auto-posted JE) would otherwise crash with
      // "UNIQUE constraint failed: journal_entries.global_id". Revive the
      // soft-deleted row instead of inserting a colliding one — it restores the
      // single canonical JE for this transition. Balances are intentionally
      // untouched here: a bare JE soft-delete does NOT reverse them (the real
      // reversal path posts a separate `-rev` JE and leaves the original
      // active, so it never reaches here), matching the skip path's
      // "already applied" semantics above.
      final revivableSameGid = await (select(journalEntries)
            ..where((e) => e.globalId.equals(jeGid) & e.isDeleted.equals(true))
            ..limit(1))
          .getSingleOrNull();
      if (revivableSameGid != null) {
        await (update(journalEntries)
              ..where((e) => e.id.equals(revivableSameGid.id)))
            .write(const JournalEntriesCompanion(isDeleted: Value(false)));
        unawaited(DiagnosticLogger.log(
            'CP-AUTOPOST',
            'revived soft-deleted JE id=${revivableSameGid.id} gid=$jeGid on '
            're-post — avoids UNIQUE global_id collision (Spec 136 B2)'));
        return;
      }

      unawaited(DiagnosticLogger.log(
        DiagnosticLogger.gidAutopost,
        'sourceType=cp sourceGid=${paperSourceGid.length >= 8 ? paperSourceGid.substring(0, 8) : paperSourceGid} '
        'verb=$newStatus paperId=${paper.id}',
      ));
      await accountingDao.createJournalEntry(
        date: DateTime.now(),
        description: description,
        lines: lines,
        referenceType: 'commercial_paper',
        referenceId: paper.id,
        isAutoPosted: true,
        costCenterId: costCenterId,
        globalId: jeGid,
      );
    }

    // ── Safe + party balance side-effects ─────────────────────────────────
    // The journal entry records the GL impact; we also need to keep the
    // treasury safe balances and the party.balance snapshot in sync so
    // treasury screens, party statements, and shift-close reports agree
    // with the books.
    await _cpApplyBalanceSideEffects(paper, oldStatus, newStatus);
  }

  /// Resolve an account by centralized purpose — avoids the widespread
  /// pre-v110 bug where hard-coded codes drifted out of sync with the seed.
  Future<Account?> _cpResolveAccount(String purpose) async {
    final code = await accountingDao.getMappedAccountCode(
      purpose,
      AccountingDao.accountPurposes[purpose] ?? '',
    );
    if (code.isEmpty) return null;
    return _cpGetAccountByCode(code);
  }

  /// Apply safe-balance and party-balance adjustments matching the paper
  /// lifecycle. Kept outside the JE block so the books and the treasury
  /// always move together (every transition that should hit the safe/
  /// party balance is enumerated here explicitly).
  ///
  /// Accounting semantics (both sides):
  ///   RECEIVED
  ///     pending  → customer handed us a cheque; AR already reduced via JE,
  ///                mirror by reducing `parties.balance`.
  ///     deposited / cashed → bank safe grows by `amount` (cash inflow).
  ///     bounced  → reverse the deposit: bank safe shrinks by `amount`;
  ///                customer AR grows (bank safe update only if previously
  ///                deposited/cashed — we re-debit).
  ///   ISSUED
  ///     pending  → we wrote a cheque; AP already reduced via JE, mirror by
  ///                reducing `parties.balance`.
  ///     cashed   → bank safe shrinks by `amount` (bank actually paid).
  ///     bounced  → reverse: bank safe grows; party balance grows again.
  Future<void> _cpApplyBalanceSideEffects(
    CommercialPaperData paper,
    String oldStatus,
    String newStatus,
  ) async {
    if (oldStatus == newStatus) return;

    if (paper.direction == 'received') {
      switch (newStatus) {
        case 'pending':
          // Customer paid us with the cheque → reduce their outstanding AR.
          await accountingDao.adjustPartyBalance(paper.partyId, -paper.amount);
          break;
        case 'deposited':
        case 'deposited_for_collection':
          // Spec 136 (field 2026-06-08): intermediate (برسم التحصيل) — NO money
          // in the safe yet. The bank safe is credited ONCE at 'cashed'. Pre-fix
          // both deposit and cashed credited the bank safe → double-count.
          break;
        case 'cashed':
          // Match the GL: deposited→collected clears through the BANK; a direct
          // counter collection (pending→cashed) is CASH (Spec 136 — was always
          // crediting the bank safe → books/treasury divergence).
          final collectedViaBank = oldStatus == 'deposited' ||
              oldStatus == 'deposited_for_collection';
          await _cpCreditSafeForPaper(paper, bank: collectedViaBank);
          break;
        case 'bounced':
          // Spec 136 — only reverse the safe if the cheque had actually been
          // COLLECTED (cashed). A deposited-but-not-collected cheque never added
          // money to a safe. Reverse the SAME channel it was credited to: a
          // deposit set paper.safeId (bank); a direct cash collection didn't.
          if (oldStatus == 'cashed') {
            await _cpDebitSafeForPaper(paper, bank: paper.safeId != null);
          }
          // Reinstate the customer's AR.
          await accountingDao.adjustPartyBalance(paper.partyId, paper.amount);
          break;
      }
    } else {
      // Issued (outgoing cheque)
      switch (newStatus) {
        case 'pending':
          // We issued a cheque to the supplier → reduce what we owe them.
          await accountingDao.adjustPartyBalance(paper.partyId, -paper.amount);
          break;
        case 'cashed':
          // Issued cheques clear through the BANK (our account is debited).
          await _cpDebitSafeForPaper(paper, bank: true);
          break;
        case 'bounced':
          if (oldStatus == 'cashed') {
            await _cpCreditSafeForPaper(paper, bank: true);
          }
          // Supplier is owed again.
          await accountingDao.adjustPartyBalance(paper.partyId, paper.amount);
          break;
      }
    }
  }

  Future<void> _cpCreditSafeForPaper(CommercialPaperData paper,
      {required bool bank}) async {
    final safe = await _cpResolveSafeForPaper(paper, bank: bank);
    if (safe == null) {
      throw Exception(bank
          ? 'لا يوجد صندوق بنكي مسجل. يرجى إضافة حساب بنكي في الخزن.'
          : 'لا يوجد صندوق نقدي مسجل. يرجى إضافة صندوق نقدي في الخزن.');
    }
    await customStatement(
      'UPDATE safes SET balance = balance + ? WHERE id = ?',
      [paper.amount, safe.id],
    );
  }

  Future<void> _cpDebitSafeForPaper(CommercialPaperData paper,
      {required bool bank}) async {
    final safe = await _cpResolveSafeForPaper(paper, bank: bank);
    if (safe == null) {
      throw Exception(bank
          ? 'لا يوجد صندوق بنكي مسجل. يرجى إضافة حساب بنكي في الخزن.'
          : 'لا يوجد صندوق نقدي مسجل. يرجى إضافة صندوق نقدي في الخزن.');
    }
    await customStatement(
      'UPDATE safes SET balance = balance - ? WHERE id = ?',
      [paper.amount, safe.id],
    );
  }

  /// Spec 136 (field 2026-06-14): resolve the safe to move money in/out of when
  /// a cheque is collected/bounced. MUST match the GL collection account so the
  /// books and the treasury never diverge: a cheque collected directly at the
  /// counter (pending→cashed) debits the CASH account in the JE, so it must
  /// credit a CASH safe — NOT the bank safe (the old code always credited the
  /// bank safe → permanent books-vs-treasury gap). A cheque deposited first
  /// (برسم التحصيل) clears through the BANK.
  Future<Safe?> _cpResolveSafeForPaper(CommercialPaperData paper,
      {bool bank = true}) async {
    // 1) Explicit safe linked on the paper (set when user picked a specific
    //    bank during "إيداع برسم التحصيل"). Only honour it for the bank channel;
    //    a direct cash collection has no deposit safe and must hit a cash safe.
    if (bank && paper.safeId != null) {
      final explicit = await (select(safes)..where((s) => s.id.equals(paper.safeId!))..limit(1))
          .getSingleOrNull();
      if (explicit != null) return explicit;
    }
    // 2) Default safe of the matching type (bank for deposited, cash for a
    //    direct counter collection).
    final safeType = bank ? 'bank' : 'cash';
    final resolved = await (select(safes)
          ..where((s) => s.safeType.equals(safeType) & s.isActive.equals(true))
          ..orderBy([(s) => OrderingTerm(expression: s.isDefault, mode: OrderingMode.desc)])
          ..limit(1))
        .getSingleOrNull();
    return resolved;
  }

  /// Get paper status history
  Future<List<PaperStatusHistoryData>> getPaperHistory(int paperId) {
    return (select(paperStatusHistory)
          ..where((h) => h.paperId.equals(paperId))
          ..orderBy([(h) => OrderingTerm.desc(h.changedAt)]))
        .get();
  }

  /// Paper summary: totals by status and direction
  Future<Map<String, dynamic>> getCommercialPapersSummary() async {
    final allPapers = await select(commercialPapers).get();

    double receivedPending = 0,
        receivedInPortfolio = 0,
        receivedDeposited = 0,
        receivedForCollection = 0,
        receivedCashed = 0,
        receivedBounced = 0;
    double issuedPending = 0, issuedCashed = 0, issuedBounced = 0;

    for (final p in allPapers) {
      if (p.direction == 'received') {
        switch (p.status) {
          case 'pending':
            receivedPending += p.amount;
            break;
          case 'in_portfolio':
            receivedInPortfolio += p.amount;
            break;
          case 'deposited':
            receivedDeposited += p.amount;
            break;
          case 'deposited_for_collection':
            receivedForCollection += p.amount;
            break;
          case 'cashed':
            receivedCashed += p.amount;
            break;
          case 'bounced':
            receivedBounced += p.amount;
            break;
        }
      } else {
        switch (p.status) {
          case 'pending':
            issuedPending += p.amount;
            break;
          case 'cashed':
            issuedCashed += p.amount;
            break;
          case 'bounced':
            issuedBounced += p.amount;
            break;
        }
      }
    }

    return {
      'received': {
        'pending': receivedPending,
        'in_portfolio': receivedInPortfolio,
        'deposited': receivedDeposited,
        'deposited_for_collection': receivedForCollection,
        'cashed': receivedCashed,
        'bounced': receivedBounced,
      },
      'issued': {
        'pending': issuedPending,
        'cashed': issuedCashed,
        'bounced': issuedBounced,
      },
    };
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ADVANCED OPERATIONS
  // ─────────────────────────────────────────────────────────────────────────

  /// Renew a commercial paper (تجديد) — extend due date
  Future<void> renewPaper({
    required int paperId,
    required DateTime newDueDate,
    required int changedBy,
    String? notes,
  }) async {
    await _ensureValidActor(changedBy);
    await transaction(() async {
      final paper = await getCommercialPaper(paperId);
      if (paper == null) throw Exception('الورقة التجارية غير موجودة');
      if (paper.status == 'cashed' || paper.status == 'cancelled') {
        throw Exception('لا يمكن تجديد ورقة محصلة أو ملغاة');
      }

      // 0. Soft/Hard Period Closing Gating
      await accountingDao.validateFinancialPeriod(DateTime.now(), operation: 'تجديد ورقة تجارية');

      await (update(commercialPapers)..where((p) => p.id.equals(paperId)))
          .write(CommercialPapersCompanion(dueDate: Value(newDueDate)));

      await into(paperStatusHistory).insert(
        PaperStatusHistoryCompanion.insert(
          paperId: paperId,
          fromStatus: paper.status,
          toStatus: paper.status, // Status unchanged — only date extended
          changedBy: changedBy,
          notes: Value(notes ?? 'تجديد — تاريخ الاستحقاق الجديد: ${newDueDate.toString().substring(0, 10)}'),
        ),
      );
    });
  }

  /// Get papers due within N days (تنبيه الاستحقاق)
  Future<List<CommercialPaperData>> getPapersDueSoon({int withinDays = 7}) async {
    final now = DateTime.now();
    final cutoff = now.add(Duration(days: withinDays));
    return (select(commercialPapers)
          ..where((p) =>
              p.status.isIn(['pending', 'deposited']) &
              p.dueDate.isBetweenValues(now, cutoff))
          ..orderBy([(p) => OrderingTerm.asc(p.dueDate)]))
        .get();
  }

  /// Partial collection of a commercial paper (تحصيل جزئي)
  Future<void> partialCollection({
    required int paperId,
    required double collectedAmount,
    required int changedBy,
    int? costCenterId,
    String? notes,
  }) async {
    await _ensureValidActor(changedBy);
    await transaction(() async {
      final paper = await getCommercialPaper(paperId);
      if (paper == null) throw Exception('الورقة التجارية غير موجودة');
      if (paper.status == 'cashed' || paper.status == 'cancelled') {
        throw Exception('الورقة محصلة بالكامل أو ملغاة');
      }
      if (collectedAmount <= 0 || collectedAmount >= paper.amount) {
        throw Exception('المبلغ المحصل يجب أن يكون أقل من إجمالي الورقة');
      }

      // 0. Soft/Hard Period Closing Gating
      await accountingDao.validateFinancialPeriod(DateTime.now(), operation: 'تحصيل جزئي ورقة تجارية');

      final remaining = paper.amount - collectedAmount;

      // Update amount to remaining
      await (update(commercialPapers)..where((p) => p.id.equals(paperId)))
          .write(CommercialPapersCompanion(amount: Value(remaining)));

      // Record partial collection
      await into(paperStatusHistory).insert(
        PaperStatusHistoryCompanion.insert(
          paperId: paperId,
          fromStatus: paper.status,
          toStatus: 'partial_collected',
          changedBy: changedBy,
          notes: Value(notes ?? 'تحصيل جزئي: ${collectedAmount.toStringAsFixed(AppConstants.decimalPlaces)} — المتبقي: ${remaining.toStringAsFixed(AppConstants.decimalPlaces)}'),
        ),
      );

      // Auto-post partial collection journal entry — routed through the
      // purposes map (was hard-coded to 1101/1202 which don't exist in the
      // v110 seeded chart of accounts; posting therefore silently skipped).
      final cashAccount = await _cpResolveAccount('cash');
      final receivableAccount = await _cpResolveAccount('notes_receivable');
      if (cashAccount != null && receivableAccount != null) {
        await accountingDao.createJournalEntry(
          description: 'تحصيل جزئي ورقة تجارية #${paper.paperNumber}',
          date: DateTime.now(),
          lines: [
            JournalLine(accountId: cashAccount.id, debit: collectedAmount, description: 'تحصيل جزئي'),
            JournalLine(accountId: receivableAccount.id, credit: collectedAmount, description: 'تخفيض ذمم'),
          ],
          referenceType: 'commercial_paper',
          referenceId: paperId,
          isAutoPosted: true,
          costCenterId: costCenterId,
        );
      }
    });
  }

  /// Re-issue a check from portfolio to another party (إعادة إصدار)
  Future<void> reissueToParty({
    required int paperId,
    required int newPartyId,
    required int changedBy,
    int? costCenterId,
    String? notes,
  }) async {
    await _ensureValidActor(changedBy);
    await transaction(() async {
      final paper = await getCommercialPaper(paperId);
      if (paper == null) {
        throw Exception('Commercial paper not found: $paperId');
      }

      // 0. Soft/Hard Period Closing Gating
      await accountingDao.validateFinancialPeriod(DateTime.now(), operation: 'إعادة إصدار ورقة تجارية');

      if (paper.status != 'pending' && paper.status != 'in_portfolio') {
        throw Exception('لا يمكن إعادة إصدار ورقة ليست في الحافظة أو معلقة');
      }

      // Update the paper: new party, status = endorsed
      await (update(commercialPapers)..where((p) => p.id.equals(paperId)))
          .write(CommercialPapersCompanion(
            endorsedToPartyId: Value(newPartyId),
            status: const Value('endorsed'),
            notes: Value(notes ?? 'إعادة إصدار لطرف #$newPartyId'),
          ));

      // Record history
      await into(paperStatusHistory).insert(
        PaperStatusHistoryCompanion.insert(
          paperId: paperId,
          fromStatus: paper.status,
          toStatus: 'endorsed',
          changedBy: changedBy,
          notes: Value(notes ?? 'إعادة إصدار من الحافظة لطرف آخر'),
        ),
      );

      // Auto-post journal entry
      await _autoPostPaperStatusChange(paper, paper.status, 'endorsed',
          costCenterId: costCenterId);
    });
  }

  /// Deposit check for collection at a specific bank (إيداع برسم التحصيل)
  Future<void> depositForCollection({
    required int paperId,
    required int bankSafeId,
    required int changedBy,
    int? costCenterId,
    String? notes,
  }) async {
    await _ensureValidActor(changedBy);
    await transaction(() async {
      final paper = await getCommercialPaper(paperId);
      if (paper == null) {
        throw Exception('Commercial paper not found: $paperId');
      }

      // 0. Soft/Hard Period Closing Gating
      await accountingDao.validateFinancialPeriod(DateTime.now(), operation: 'إيداع ورقة تجارية برسم التحصيل');

      if (!['pending', 'in_portfolio'].contains(paper.status)) {
        throw Exception('يجب أن تكون الورقة معلقة أو في الحافظة');
      }

      // Link the paper to the bank safe & update status
      await (update(commercialPapers)..where((p) => p.id.equals(paperId)))
          .write(CommercialPapersCompanion(
            status: const Value('deposited_for_collection'),
            safeId: Value(bankSafeId),
            notes: Value(notes ?? 'إيداع برسم التحصيل'),
          ));

      // Record history
      await into(paperStatusHistory).insert(
        PaperStatusHistoryCompanion.insert(
          paperId: paperId,
          fromStatus: paper.status,
          toStatus: 'deposited_for_collection',
          changedBy: changedBy,
          notes: Value(notes ?? 'إيداع برسم التحصيل في بنك #$bankSafeId'),
        ),
      );

      // Auto-post
      await _autoPostPaperStatusChange(
        paper, paper.status, 'deposited_for_collection',
        costCenterId: costCenterId,
      );
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // REPORTS
  // ─────────────────────────────────────────────────────────────────────────

  /// Get checks by bank (for bank reports)
  Future<List<CommercialPaperData>> getChecksByBank(int bankSafeId) async {
    return (select(commercialPapers)
          ..where((p) => p.safeId.equals(bankSafeId))
          ..orderBy([(p) => OrderingTerm.desc(p.dueDate)]))
        .get();
  }

  /// Get bank check report — grouped totals by status for a specific bank
  Future<Map<String, double>> getBankCheckReport(int bankSafeId) async {
    final checks = await getChecksByBank(bankSafeId);
    final totals = <String, double>{};
    for (final c in checks) {
      totals[c.status] = (totals[c.status] ?? 0) + c.amount;
    }
    return totals;
  }

  /// Helper: get account by code.
  ///
  /// Cluster 028 / Bug 3 — defensive `.limit(1)`. Mirror installs can
  /// accumulate duplicate accounts with the same code if the sync
  /// strategy fails to dedup; without the limit, `getSingleOrNull`
  /// throws "Bad state: too many elements" the moment the operator
  /// opens any commercial-papers screen, since `_autoPostPaperStatusChange`
  /// resolves several accounts by code on every paper save.
  Future<Account?> _cpGetAccountByCode(String code) async {
    return (select(accounts)
          ..where((a) => a.code.equals(code))
          ..limit(1))
        .getSingleOrNull();
  }
}
