// Spec 007 / SC-003 — Orchestrator gate predicate guard.
//
// The four invoice-creation paths (sales, purchases, sales returns, purchase
// returns) all gate the server-submit branch on a "should I push this write?"
// predicate. Historically this was `NetworkService.instance.isClient`, which
// returns FALSE in mirror mode — so mirror admins' invoices stayed local and
// HQ never received them.
//
// MM.C C2.2 broadened `SyncInterceptor.isClientMode` to evaluate true for
// both client AND mirror modes (`isClientModeImpl => ServerProxy.isClientMode
// || WriteRouter.isMirrorActive`). Feature 007 US1 (T007–T009) switches the
// orchestrators to use that broadened predicate.
//
// This test enforces the convention going forward: any reappearance of the
// legacy `NetworkService.instance.isClient` reference inside the affected
// orchestrators fails the build.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Orchestrator gate predicate (Spec 007 / SC-003)', () {
    final orchestratorFiles = <String>[
      'lib/data/repositories/sales_transaction_orchestrator.dart',
      'lib/data/repositories/purchases_repository_impl.dart',
      'lib/data/repositories/returns_repository_impl.dart',
    ];

    for (final relPath in orchestratorFiles) {
      test('$relPath uses SyncInterceptor.isClientMode for the write gate', () {
        final file = File(relPath);
        expect(
          file.existsSync(),
          isTrue,
          reason: 'expected orchestrator file to exist at $relPath',
        );

        final source = file.readAsStringSync();

        // The write gate is the variable named isClientMode (or shouldRoute*),
        // assigned from a network-mode predicate. Restricting to assignments
        // avoids false-positives on legitimate read-side filters that are
        // intentionally branch-isolated only when the device is a strict
        // client (e.g. watchInvoices warehouse filter — mirror admins should
        // see every warehouse, so the strict-client predicate is correct
        // there). The spec is about WRITE gates, not READ filters.
        final writeGateHits = RegExp(
          r'(?:isClientMode|shouldRoute\w*)\s*=\s*NetworkService\.instance\.isClient',
        ).allMatches(source).toList();

        expect(
          writeGateHits,
          isEmpty,
          reason:
              '$relPath still gates a write on NetworkService.instance.isClient. '
              'Mirror mode evaluates to false on that predicate, so invoices '
              'created on mirror never push to HQ. Use SyncInterceptor.isClientMode '
              'instead — it is broadened in MM.C C2.2 to include mirror mode. '
              'See specs/007-mirror-sync-multibranch/contracts/globalid-flow.md.',
        );
      });
    }
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Feature 009 / T014 — `applyAutoDepleteForSale` MUST be gated on
  // `!isClientMode`. In client/mirror mode the server is the SSoT
  // (Constitution III, R4): inventory writes — including auto-deplete
  // raw-material deductions — happen on the server only. If the orchestrator
  // ever calls the helper without the gate, mirror-mode sales would deduct
  // raw materials twice (once locally, once on the server), corrupting
  // inventory. This grep-style test fails the build at the first regression.
  //
  // Note on call count: the POS-path entry point (`completeSalesTransaction`)
  // delegates to `createSalesInvoice` in non-client mode (see lines around
  // ~586) instead of inlining the work. So a single guarded call site at the
  // end of `createSalesInvoice` covers BOTH the sales-invoice-screen and
  // POS flows. Adding a redundant second call would cause double-deduction.
  // The test therefore asserts ≥1 call, all gated, AND that the delegation
  // edge from `completeSalesTransaction` still exists.
  // ─────────────────────────────────────────────────────────────────────────
  group('Auto-deplete gate (Feature 009 / T014)', () {
    const relPath = 'lib/data/repositories/sales_transaction_orchestrator.dart';

    test('applyAutoDepleteForSale is called at least once and every call is gated',
        () {
      final source = File(relPath).readAsStringSync();

      // Match invocation sites only — `applyAutoDepleteForSale(` with the
      // open paren — to avoid false positives on doc comments that mention
      // the symbol by name.
      final callMatches = RegExp(r'applyAutoDepleteForSale\s*\(')
          .allMatches(source)
          .toList();

      expect(
        callMatches.length,
        greaterThanOrEqualTo(1),
        reason:
            '$relPath must call applyAutoDepleteForSale at least once. If '
            'this drops to zero, T018 has been reverted and mirror-mode '
            'sales will skip raw-material deduction once T020 ships.',
      );

      // Each call site must be preceded — within ~3000 chars (the
      // resolved-policy block that wraps the call grew when Feature 009
      // T025 wired the 3-tier shortage policy resolver) — by a negated
      // isClientMode check. We accept either the `isClientMode` local
      // variable (already declared at the top of both methods, sourced
      // from SyncInterceptor.isClientMode) or the direct
      // `SyncInterceptor.isClientMode` reference.
      const window = 3000;
      final gatePattern = RegExp(
        r'!\s*(?:isClientMode|SyncInterceptor\.isClientMode)\b',
      );
      for (final m in callMatches) {
        final start = (m.start - window).clamp(0, source.length);
        final preceding = source.substring(start, m.start);
        expect(
          gatePattern.hasMatch(preceding),
          isTrue,
          reason:
              'applyAutoDepleteForSale call at offset ${m.start} in '
              '$relPath is missing a `!isClientMode` (or '
              '`!SyncInterceptor.isClientMode`) guard within the preceding '
              '$window chars. In client/mirror mode the server is the SSoT '
              '(R4); calling the helper locally would double-deduct raw '
              'materials. See specs/009-auto-deplete-bom/contracts/'
              'auto-deplete-flow.md §4.',
        );
      }
    });

    test('completeSalesTransaction non-client branch reaches the helper via createSalesInvoice',
        () {
      // Pin the delegation: in `completeSalesTransaction`, the
      // `else { invoiceId = await createSalesInvoice(...) }` branch is what
      // covers POS sales in standalone/server mode. Without that delegation
      // edge, the POS path would silently skip auto-deplete. We assert the
      // delegation literally exists.
      final source = File(relPath).readAsStringSync();
      expect(
        source.contains('invoiceId = await createSalesInvoice('),
        isTrue,
        reason:
            'completeSalesTransaction must continue delegating its '
            'non-client branch to createSalesInvoice. If this delegation '
            'is removed, an explicit applyAutoDepleteForSale call must be '
            'added in completeSalesTransaction OR the POS path will skip '
            'auto-deplete entirely.',
      );
    });

    test('legacy bare call (no gate) does NOT appear', () {
      // Sanity: catch the simplest regression where someone reverts the
      // gate but leaves the call. The previous test already covers this,
      // but a direct line-level check is easier to read in failure output.
      final lines = File(relPath).readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].contains('applyAutoDepleteForSale(')) {
          // Look back up to 60 lines for a gate (the policy-resolution
          // block that wraps the call grew when Feature 009 T025 wired
          // the 3-tier shortage policy resolver).
          final lookbackStart = (i - 60).clamp(0, lines.length);
          final ctx = lines.sublist(lookbackStart, i).join('\n');
          expect(
            RegExp(r'!\s*(?:isClientMode|SyncInterceptor\.isClientMode)\b')
                .hasMatch(ctx),
            isTrue,
            reason:
                'Line ${i + 1} of $relPath calls applyAutoDepleteForSale '
                'without a preceding `!isClientMode` guard.',
          );
        }
      }
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Feature 010 / Cluster A — UI dialogs that route writes to the server via
  // `ClientWriteInterceptor` MUST gate on `SyncInterceptor.isClientMode`, NOT
  // on `NetworkService.instance.isClient`. The legacy predicate evaluates to
  // FALSE in mirror mode, so mirror admins' parties (and any other write
  // routed from a UI dialog with the same antipattern) silently fall through
  // to the local-only repo path and never reach HQ.
  //
  // Real-world incident: suppliers/customers created on a mirror device after
  // Feature 009 shipped never appeared on the server. Root cause was an
  // `if (NetworkService.instance.isClient)` gate immediately wrapping a
  // `ClientWriteInterceptor.createParty(...)` call in `party_dialogs.dart`.
  //
  // The regex below matches the exact antipattern: an `if (...isClient)`
  // condition whose body (within ~800 chars — a generous local block) calls
  // `ClientWriteInterceptor.X(...)`. Files in this list are known to route
  // writes through the interceptor from a UI layer; extend the list when a
  // new dialog/screen starts doing the same.
  // ─────────────────────────────────────────────────────────────────────────
  group('UI write-gate predicate (Feature 010 / Cluster A)', () {
    final uiFiles = <String>[
      'lib/presentation/screens/parties/party_dialogs.dart',
    ];

    final brokenGate = RegExp(
      r'if\s*\(\s*NetworkService\.instance\.isClient\s*\)'
      r'[\s\S]{0,800}?ClientWriteInterceptor\.',
    );

    for (final relPath in uiFiles) {
      test('$relPath does NOT gate ClientWriteInterceptor on NetworkService.instance.isClient',
          () {
        final file = File(relPath);
        expect(
          file.existsSync(),
          isTrue,
          reason: 'expected UI file to exist at $relPath',
        );

        final source = file.readAsStringSync();
        expect(
          brokenGate.hasMatch(source),
          isFalse,
          reason:
              '$relPath wraps a `ClientWriteInterceptor.X(...)` call in an '
              '`if (NetworkService.instance.isClient)` block. That predicate '
              'is FALSE in mirror mode — so the write silently falls to the '
              'local-only branch and never reaches HQ. Use '
              '`SyncInterceptor.isClientMode` instead (true for client AND '
              'mirror). See specs/010-mirror-client-issues-batch/PROMPT.md '
              '§Cluster A.',
        );
      });
    }
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Feature 010 / Cluster D — Supplier statement on mirror.
  //
  // The supplier statement query (party_dao.getPartyStatement) reads the
  // purchase-return AP balance adjustment from a `safe_transactions` row
  // with `transactionType='memo' AND category='purchase_return_balance'`.
  // The standalone path writes that row (purchases_repository_impl.dart
  // ~lines 484-498); the server handler writes it (api_purchase_handler
  // ~lines 384-397). The mirror path historically did NOT write it, so
  // mirror users saw the GL move but the supplier statement stayed blank
  // until the next DeltaPull (and even then, only if the server-side
  // submit succeeded).
  //
  // Fix (this commit): mirror path now seeds the memo row locally as a
  // best-effort cache. Server's authoritative row dedups via
  // SafeTransactionSyncStrategy._syncSingleTransaction's
  // (referenceType, referenceId, safeId) fallback at lines 103-121, so we
  // do NOT double-count.
  //
  // This test pins the contract: the mirror branch of processPurchaseReturn
  // must contain a write to safe_transactions with the exact category that
  // the supplier-statement query filters for.
  // ─────────────────────────────────────────────────────────────────────────
  group('Mirror supplier-statement memo (Feature 010 / Cluster D)', () {
    const relPath = 'lib/data/repositories/purchases_repository_impl.dart';

    test('mirror branch of processPurchaseReturn writes the AP-balance memo row',
        () {
      final source = File(relPath).readAsStringSync();

      // Anchor on the method signature first — the file has multiple
      // `if (isClientMode) { ... }` blocks (createPurchaseInvoice has one
      // too), so a bare indexOf would carve the wrong method.
      final methodStart = source.indexOf('processPurchaseReturn(');
      expect(
        methodStart,
        greaterThan(0),
        reason: 'expected processPurchaseReturn method in $relPath',
      );

      // From the method header, carve from the next `if (isClientMode) {`
      // opener up to the next `// ── Standalone/Server` sentinel.
      final mirrorStart = source.indexOf(
        RegExp(r'if\s*\(\s*isClientMode\s*\)\s*\{'),
        methodStart,
      );
      final standaloneStart = source.indexOf(
        '// ── Standalone/Server: Full local processing ──',
        mirrorStart,
      );
      expect(
        mirrorStart,
        greaterThan(methodStart),
        reason:
            'expected `if (isClientMode) {` opener inside processPurchaseReturn',
      );
      expect(
        standaloneStart,
        greaterThan(mirrorStart),
        reason:
            'expected the standalone-path sentinel comment after the mirror '
            'branch in processPurchaseReturn — refactor changed structure?',
      );

      final mirrorBody = source.substring(mirrorStart, standaloneStart);

      // The memo row's distinguishing marker is its category. The
      // supplier-statement query (party_dao.dart:929) filters on this exact
      // string, so dropping it would silently re-break the bug.
      expect(
        mirrorBody.contains("category: 'purchase_return_balance'"),
        isTrue,
        reason:
            'mirror branch of processPurchaseReturn no longer seeds a '
            "`safe_transactions` row with category 'purchase_return_balance'. "
            'The supplier statement (getPartyStatement, party_dao.dart:929) '
            'reads exactly this category to populate the AP balance line for '
            'a purchase return; without it, mirror admins see the return in '
            'the GL but a blank supplier statement. See '
            'specs/010-mirror-client-issues-batch/PROMPT.md §Cluster D.',
      );

      // The same row must reference the original purchase invoice so the
      // sync strategy can dedup the server's authoritative row by
      // (referenceType, referenceId, safeId) — otherwise we would double-
      // count after DeltaPull arrives.
      expect(
        mirrorBody.contains("referenceType: const Value('purchase_return')"),
        isTrue,
        reason:
            "mirror memo row missing `referenceType: 'purchase_return'`. "
            'SafeTransactionSyncStrategy dedups the server echo by '
            '(referenceType, referenceId, safeId); without the right '
            'referenceType, the server would insert a duplicate memo and '
            'the supplier statement would double-count the AP adjustment.',
      );
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Feature 010 / Cluster B (Issue 2) — Manual JE branch attribution.
  //
  // The manual-journal-entry dialog (journal_entry_create_dialog.dart) does
  // NOT pass a branchId when calling repo.createJournalEntry. The DAO falls
  // back to `branchId ?? 1` (main branch), so on a client device bound to
  // e.g. branch 3, the JE reaches HQ tagged as "branch 1" — the user's
  // complaint: "بيظهر ان العميل فرع كذا هو اللى عمله".
  //
  // Fix: drift_accounting_repository.createJournalEntry now resolves
  // SharedPreferences['client_branch_id'] when the caller didn't supply a
  // branchId AND the device is in client/mirror mode. The threaded value
  // flows into SyncInterceptor.submitJournalEntry's payload at
  // accounting_dao_writes.dart:336, then into the server handler.
  //
  // These tests pin both ends of the contract:
  //   1. The repo resolves client_branch_id when caller-branchId is null.
  //   2. The interceptor payload still includes `branchId` (without it the
  //      repo's resolution would be wasted — server reads payload['branchId']
  //      at api_data_handler.dart:1510).
  // ─────────────────────────────────────────────────────────────────────────
  group('Manual JE branch attribution (Feature 010 / Cluster B)', () {
    test('drift_accounting_repository.createJournalEntry resolves client_branch_id',
        () {
      const relPath = 'lib/data/repositories/drift_accounting_repository.dart';
      final source = File(relPath).readAsStringSync();

      // Locate the createJournalEntry method body — anchor on the method
      // signature, then walk forward to the next blank-line + closing brace
      // sentinel that marks the end of the method.
      final methodStart = source.indexOf('Future<int> createJournalEntry(');
      expect(
        methodStart,
        greaterThan(0),
        reason: 'expected createJournalEntry method in $relPath',
      );

      // Carve until the next method opener or the next top-level helper.
      // _resolveClientBranchId is the helper we added — it is the most
      // stable forward boundary.
      final helperStart = source.indexOf(
        'Future<int?> _resolveClientBranchId',
        methodStart,
      );
      expect(
        helperStart,
        greaterThan(methodStart),
        reason:
            'expected _resolveClientBranchId helper after createJournalEntry — '
            'has the resolution been removed or renamed?',
      );

      final body = source.substring(methodStart, helperStart);

      // The two load-bearing pieces:
      //   1. Gate the resolution on `SyncInterceptor.isClientMode` so
      //      standalone/server installs do NOT touch SharedPreferences.
      //   2. Call the helper that reads `client_branch_id`.
      expect(
        body.contains('SyncInterceptor.isClientMode'),
        isTrue,
        reason:
            '$relPath createJournalEntry no longer gates branchId resolution '
            'on `SyncInterceptor.isClientMode`. Without the gate, '
            'standalone/server installs would do an unnecessary '
            'SharedPreferences lookup on every JE write.',
      );
      expect(
        body.contains('_resolveClientBranchId()'),
        isTrue,
        reason:
            '$relPath createJournalEntry no longer calls '
            '_resolveClientBranchId(). Manual JEs created on a non-main '
            'branch will fall back to branchId=1 in the DAO, and the JE '
            'will appear on HQ as if the main branch created it. See '
            'specs/010-mirror-client-issues-batch/PROMPT.md §Cluster B.',
      );

      // The helper itself must read the same key the rest of the codebase
      // uses — search for `client_branch_id` literal (not the variable
      // name) anywhere in the file.
      expect(
        source.contains("'client_branch_id'"),
        isTrue,
        reason:
            "$relPath no longer reads 'client_branch_id' from "
            'SharedPreferences. Other repos (sales, purchases) and '
            'sync_service all use this exact key — diverging would '
            'silently break attribution.',
      );
    });

    test('party_statement_screen handles party==null without rendering blank', () {
      // Cluster E (Issue 5) — when getPartyById returns null for the
      // partyId provided by the entry-point button, the screen used to
      // render with NO body widget at all (the if/else-if chain in
      // build() had no branch for `_selectedPartyId != null && party ==
      // null`). The user perceived the entry-point button as broken.
      // The fix adds (a) an early-return in loadData that leaves
      // party=null without throwing, and (b) an explicit placeholder
      // branch in build(). This test pins both pieces.
      const relPath = 'lib/presentation/screens/party_statement_screen.dart';
      final source = File(relPath).readAsStringSync();

      // (a) loadData early-return on null party.
      expect(
        source.contains('if (p == null)'),
        isTrue,
        reason:
            '$relPath loadData no longer short-circuits on null party. '
            'Without the guard, getPartySummary throws "Party not found" '
            'and the catch fires only a transient toast — easy to miss '
            'against a blank body. See Cluster E.',
      );

      // (b) Build branch for the missing-party state.
      expect(
        source.contains('_selectedPartyId != null && party == null'),
        isTrue,
        reason:
            "$relPath build() no longer has a branch for "
            "`_selectedPartyId != null && party == null`. The body will "
            'render blank again and the button will appear unresponsive. '
            'See Cluster E.',
      );
    });

    test('postBranch dedups by name when globalId is null (Feature 011)', () {
      // Diagnostic logs from a beta restaurant showed 9 server rows all
      // named "الفرع الرئيسي" with globalId=null. Root cause: postBranch
      // skipped the globalId-dedup branch when the caller didn't supply
      // one, then INSERTed blindly. Fix: name+isActive dedup as a
      // second tier, and always mint a server-side globalId so future
      // syncs can hit the first-tier dedup.
      const relPath = 'lib/services/api/api_data_handler.dart';
      final source = File(relPath).readAsStringSync();

      // Locate postBranch
      final methodStart = source.indexOf('Future<Response> postBranch(');
      expect(
        methodStart,
        greaterThan(0),
        reason: 'expected postBranch handler in $relPath',
      );

      // Walk to next handler / end of method
      final nextHandler =
          source.indexOf('Future<Response> ', methodStart + 1);
      final body = source.substring(
        methodStart,
        nextHandler > 0 ? nextHandler : source.length,
      );

      // Tier 2 — name dedup is the new piece this commit added.
      expect(
        body.contains('b.name.equals'),
        isTrue,
        reason:
            '$relPath postBranch no longer dedups by name. With globalId '
            'omitted, the handler will create a duplicate row on every '
            'POST — exactly the bug we fixed in Feature 011 / Issue 7+8.',
      );
      expect(
        body.contains('isActive.equals(true)'),
        isTrue,
        reason:
            "$relPath postBranch name dedup must scope to is_active=true. "
            'Without the active-only filter, a soft-deleted branch would '
            'shadow a legitimate new branch with the same name.',
      );

      // Server-side globalId mint when the caller didn't send one — so
      // the inserted row never lands with NULL globalId (which would
      // perpetuate the original bug for any future client that does the
      // same thing).
      expect(
        body.contains('UuidV7.generate()'),
        isTrue,
        reason:
            '$relPath postBranch no longer mints a server-side globalId '
            'when the caller omits it. Inserting with globalId=NULL '
            'allows unlimited duplicates because UNIQUE constraints '
            'permit multiple NULLs in SQLite/PG.',
      );
    });

    test('_getUsers always includes id=1 (admin) regardless of branch (Feature 011)',
        () {
      // Issue 9 — server's /api/users handler used to filter by branch
      // access + isSystemRole flag. If neither matched (a fresh client
      // configuration where the local roles table didn't have isSystemRole=
      // true on roleId=1, or where userBranchAccess for id=1 wasn't seeded),
      // the response excluded the admin entirely. The chain failure on the
      // client (rename to __dup_1_admin → role_permissions zero) followed.
      const relPath = 'lib/services/api/api_handler.dart';
      final source = File(relPath).readAsStringSync();

      final methodStart = source.indexOf('Future<Response> _getUsers(');
      expect(
        methodStart,
        greaterThan(0),
        reason: 'expected _getUsers handler in $relPath',
      );

      // Walk forward to capture the where-clause area.
      //
      // ⚠️ **النافذةُ بمحارفَ لا بأسطر، ومرساتُها تحتها.** كانت ٤٠٠٠ محرفٍ،
      // فلمّا أُضيف تعليقٌ في رأس `_getUsers` (‏شرحُ حارسِ الاعتماد ونافذةِ
      // الاقتران) خرج الكودُ المقصودُ من النافذة وسقط الاختبارُ برسالةٍ تقول
      // «‏`_getUsers` لم يعد يضمّ المدير» — وهو **لم يتغيّر إطلاقاً**. حارسٌ
      // يفشل بسببِ تعليقٍ يُضلّل من يقرؤه.
      final body = source.substring(
        methodStart,
        (methodStart + 9000).clamp(0, source.length),
      );

      // المرساة: النافذةُ تصل فعلاً إلى استعلامِ الجدول. لو قصُرت مرّةً
      // أخرى فالرسالةُ تقول ذلك بدل أن تتّهم الكود.
      expect(
        body.contains('_db.select(_db.users)'),
        isTrue,
        reason: 'النافذةُ لم تعد تغطّي جسمَ `_getUsers` — وسّعها بدل أن '
            'تقرأ فشلَها حكماً على الكود.',
      );

      // Feature 029 / US3 Bug A — accept either the original
      // `u.id.equals(1)` disjunction OR the equivalent
      // materialize-set rewrite that builds `allowedIds = {... 1}`
      // and queries `u.id.isIn(allowedIds.toList())`. Both shapes
      // unconditionally include the bootstrap admin; the Set form
      // additionally hardens against drift_postgres empty-IN-list
      // edge cases (production root cause). See
      // specs/029-sync-regression-hardening/contracts/bug-a-admin-self-heal.md.
      final hasLegacyDisjunction = body.contains('u.id.equals(1)');
      final hasMaterializedSet = body.contains('allowedIds') &&
          // The literal `1` must appear inside the Set body — the
          // existing comment `// bootstrap admin — always included`
          // pins this in source.
          RegExp(r'<int>\{[\s\S]{0,400}?\b1\b').hasMatch(body);

      expect(
        hasLegacyDisjunction || hasMaterializedSet,
        isTrue,
        reason:
            '$relPath _getUsers no longer unconditionally includes id=1 in '
            'the response when branchId is supplied. The bootstrap admin '
            'will be filtered out, the client will rename its local admin '
            'to __dup_1_admin, and role_permissions for roleId=1 will sync '
            'to zero. See Feature 011 / Issue 9 + Feature 029 / US3 Bug A.',
      );

      // Feature 029 / US3 Bug A — defense-in-depth: the server-side
      // self-heal must run on first request so a missing or renamed
      // (`__dup_1_admin`) admin row gets restored even before the
      // query runs. Without this, the materialize-set fix only helps
      // when the row at id=1 still exists.
      expect(
        body.contains('_ensureBootstrapAdminOnce()'),
        isTrue,
        reason:
            '$relPath _getUsers no longer calls _ensureBootstrapAdminOnce(). '
            'A corrupt server (id=1 deleted or renamed) keeps shipping '
            'admin-less responses forever without it. See '
            'specs/029-sync-regression-hardening/contracts/bug-a-admin-self-heal.md.',
      );
    });

    test('user_sync_strategy refuses to rename bootstrap admin (id=1)', () {
      // Defense-in-depth for Issue 9: even if a server response carries
      // a DIFFERENT user named "admin", the local id=1 must NOT be
      // renamed to __dup_1_admin.
      const relPath = 'lib/services/sync/strategies/user_sync_strategy.dart';
      final source = File(relPath).readAsStringSync();

      // The guard literal — pinning the specific check.
      expect(
        source.contains('duplicate.id == 1'),
        isTrue,
        reason:
            '$relPath user_sync_strategy no longer guards the bootstrap '
            'admin (id=1) against username-conflict renames. A future '
            'refactor that removes the guard will silently re-introduce '
            'the Feature 011 / Issue 9 chain failure.',
      );
    });

    test('client_write_interceptor kicks outbox drain after successful submit (Issue 10)',
        () {
      // Field evidence: a client queued POS-2/POS-3 offline; POS-4
      // succeeded once the server became reachable, but POS-2/3 sat in
      // the outbox unattended. The drain only fired on WS reconnect /
      // pending-count change at queue time / 30s heartbeat — never on
      // operation success. Fix: kick drainOutbox(force: true) in BOTH
      // _tryOrQueue and _tryOrQueueVoid right after the serverCall
      // succeeds.
      const relPath = 'lib/services/interceptor/cwi_core.dart';
       final libraryEntry = File('lib/services/client_write_interceptor.dart').readAsStringSync();
      final source = File(relPath).readAsStringSync();

      // The drain call must appear in BOTH internal helpers. Use
      // allMatches and assert >= 2 occurrences inside the success
      // branches.
      final hits =
          'OfflineSyncWorker.instance.drainOutbox'.allMatches(source).length;
      expect(
        hits,
        greaterThanOrEqualTo(2),
        reason:
            '$relPath must call OfflineSyncWorker.instance.drainOutbox in '
            'BOTH _tryOrQueue and _tryOrQueueVoid success paths so any '
            'pre-existing outbox items drain immediately after the server '
            'becomes reachable. Found $hits occurrences (expected >= 2). '
            'See Feature 011 / Issue 10.',
      );

      // The import must be present too.
      expect(
        libraryEntry.contains("import 'offline_sync_worker.dart'"),
        isTrue,
        reason:
            '$relPath is missing the offline_sync_worker.dart import — '
            'the drain call would not compile.',
      );
    });

    test('_closeShiftSafes is idempotent on (shiftId, safeId) (Issue NEG-BAL)', () {
      // Real-world incident: a beta restaurant's "إدارة الخزينة" screen
      // showed safes with NEGATIVE balances (e.g. -33.000 on صندوق فيزا
      // مطعم معان) even though no real disbursement happened. The cause
      // was a duplicate shift_closing pair per safe per shift:
      //
      //   1. Client closes shift → submits each safe transaction via
      //      /api/safes/transaction (creates PMT-X on server)
      //   2. Client also submits /api/shifts/close
      //   3. Server's postCloseShift → closeShiftWithAudit → _closeShiftSafes
      //      created ANOTHER zeroing row (ZRO…) on the server. If this
      //      ran BEFORE the matching /api/safes/transaction, the order
      //      was: ZRO sets balance=0, then PMT-X subtracts amount
      //      again → balance = -amount.
      //
      // Fix: _closeShiftSafes now skips a safe entirely if a
      // shift_closing transaction for THIS exact (shiftId, safeId) pair
      // already exists. Standalone mode is unaffected (no prior row).
      const relPath = 'lib/data/database/daos/treasury_dao.dart';
      final source = File(relPath).readAsStringSync();

      // Anchor on the helper signature
      final methodStart = source.indexOf('Future<void> _closeShiftSafes(');
      expect(
        methodStart,
        greaterThan(0),
        reason: 'expected _closeShiftSafes helper in $relPath',
      );
      final body =
          source.substring(methodStart, (methodStart + 6000).clamp(0, source.length));

      // The idempotency check must filter on referenceType='shift_closing'
      // AND referenceId=shiftId AND safeId=sId — all three are required so
      // a stale safe-transaction from a different shift cannot mask a real
      // close.
      expect(
        body.contains("t.referenceType.equals('shift_closing')"),
        isTrue,
        reason:
            '$relPath _closeShiftSafes lost its shift_closing-scoped '
            'idempotency check. Without it, a safe that was already '
            'closed via /api/safes/transaction will be re-zeroed by '
            '_closeShiftSafes and the next PMT-X submit drives the '
            'balance negative. See Issue NEG-BAL.',
      );
      expect(
        body.contains('t.referenceId.equals(shiftId)'),
        isTrue,
        reason:
            '$relPath _closeShiftSafes idempotency check no longer '
            'scopes to the current shiftId. The check would then fire '
            'for ANY prior shift_closing on the same safe — wrong.',
      );
    });

    test('getUserBranchId orders by branchId ASC for determinism (INV-PREFIX)',
        () {
      // Real-world incident: a beta restaurant's invoices flipped between
      // branch-code prefixes (AQ-POS-1, MS-POS-2, AQ-POS-3, ...) for the
      // same multi-branch user, because getUserBranchId did `.limit(1)`
      // with no ORDER BY — the database returned an arbitrary user_branch_
      // access row, and the resolved branchId varied per call. That branchId
      // flowed into activeBranchIdProvider → activeWarehouseIdProvider →
      // the warehouse picked for the next sale → the branchId persisted on
      // the invoice → the server's branch-code prefix.
      const relPath = 'lib/data/database/daos/treasury_dao.dart';
      final source = File(relPath).readAsStringSync();

      final methodStart = source.indexOf('Future<int?> getUserBranchId(');
      expect(
        methodStart,
        greaterThan(0),
        reason: 'expected getUserBranchId helper in $relPath',
      );
      final body =
          source.substring(methodStart, (methodStart + 1500).clamp(0, source.length));

      // The deterministic ordering must be present. Without it the bug
      // silently returns. Match either the property-syntax (`u.branchId`)
      // or the snake-case form some DAOs use.
      expect(
        body.contains('orderBy(') &&
            (body.contains('OrderingTerm.asc(u.branchId)') ||
                body.contains('OrderingTerm.asc(u.userId)')),
        isTrue,
        reason:
            '$relPath getUserBranchId no longer orders by branchId before '
            '`.limit(1)`. Multi-branch users will see invoice prefixes / '
            'warehouse selection / shift attribution flip non-deterministically '
            'between sales. See Feature 011 / Issue INV-PREFIX.',
      );
    });

    test('pos_closing_controller scopes by shift.branchId (CLOSE-SCOPE)', () {
      // Real-world incident: a branch manager (مدير فرع) on فرع العقبة
      // closed their shift and the dialog showed aggregate state for
      // ALL branches (الإدارة + معان + ...). Cause: the controller asked
      // `branchRepo.getActiveBranch()` which on standalone/server (and on
      // mirror — isClient is false there) returns the FIRST active branch
      // by id, not the user's actual operating branch. The OPEN SHIFT
      // itself carries the right branchId; we now read it directly.
      const relPath = 'lib/presentation/pos/providers/pos_closing_controller.dart';
      final source = File(relPath).readAsStringSync();

      // The fix reads the shift's branchId from the DAO row before falling
      // back to getActiveBranch(). Pin both halves.
      expect(
        source.contains('select(db.shifts)'),
        isTrue,
        reason:
            '$relPath no longer queries db.shifts directly to read the '
            'open shift\'s branchId. The dialog will revert to '
            'getActiveBranch() which returns the wrong branch on '
            'server/mirror. See Issue CLOSE-SCOPE.',
      );
      // The fallback chain is preserved (getActiveBranch must still be
      // present as a secondary path for legacy shifts without branchId).
      expect(
        source.contains('branchRepo.getActiveBranch()'),
        isTrue,
        reason:
            '$relPath dropped the getActiveBranch fallback. Legacy shift '
            'rows (pre-v145) without a branchId column populated will '
            'fall through to a NULL filter and show all branches again.',
      );
    });

    test('_syncPullBranchColumn only lists tables that actually have branch_id (PG-SCHEMA)',
        () {
      // Real-world incident: server_errors.log on 2026-05-05 showed
      // every DeltaPull cycle failing with `column "branch_id" does not
      // exist` for four tables — sales_orders, purchase_orders,
      // quotations, commercial_papers — because the api_handler's sync-
      // pull map listed them as branch-scoped, but their Drift schema
      // has no branchId column and the PostgreSQL DDL never created
      // one. Branch-scoped clients couldn't sync those tables AT ALL.
      const apiPath = 'lib/services/api/api_handler.dart';
      final api = File(apiPath).readAsStringSync();

      // The forbidden entries — these tables don't have branch_id.
      // Feature 029 corrective (2026-05-10) — added `held_orders`. Same
      // class of bug: the Drift schema (sales_purchase_tables.dart:282-300)
      // does NOT declare a branchId column, but the api_handler map
      // listed it. Every DeltaPull blew up with `column "branch_id"
      // does not exist`, the frontend retried in a tight loop, and the
      // products/inventory screens appeared to lag. Pin it here so a
      // future revert fails the build.
      const forbidden = [
        "'sales_orders': 'branch_id'",
        "'purchase_orders': 'branch_id'",
        "'quotations': 'branch_id'",
        "'commercial_papers': 'branch_id'",
        "'held_orders': 'branch_id'",
      ];
      for (final entry in forbidden) {
        expect(
          api.contains(entry),
          isFalse,
          reason:
              '$apiPath _syncPullBranchColumn map re-introduced $entry. '
              'The Drift schema for that table does NOT declare a '
              "branchId column; listing it here causes every DeltaPull "
              'request from a branch-scoped client to fail with '
              '`column "branch_id" does not exist` on PostgreSQL. '
              'See Feature 011 / Issue PG-SCHEMA. If the column is '
              'genuinely needed, add it to the table\'s Drift schema '
              'AND ship a migration before re-enabling the entry.',
        );
      }

      // Spot-check that the legitimate entries are still there. These
      // tables DO have branch_id columns in their Drift schemas.
      const required = [
        "'sales_invoices': 'branch_id'",
        "'purchase_invoices': 'branch_id'",
        "'journal_entries': 'branch_id'",
        "'stock_movements': 'branch_id'",
      ];
      for (final entry in required) {
        expect(
          api.contains(entry),
          isTrue,
          reason:
              '$apiPath _syncPullBranchColumn map dropped $entry — '
              'branch-scoped sync for that table is now broken; '
              'every row is pulled regardless of the requesting branch.',
        );
      }
    });

    test('cwi_sync.submitJournalEntry payload still threads branchId', () {
      // The repo-level resolution is wasted unless the interceptor
      // includes branchId in the wire payload — server reads it at
      // api_data_handler.dart:1510.
      const relPath = 'lib/services/interceptor/cwi_sync.dart';
      final source = File(relPath).readAsStringSync();

      final methodStart = source.indexOf('submitJournalEntry(');
      expect(
        methodStart,
        greaterThan(0),
        reason: 'expected submitJournalEntry method in $relPath',
      );

      // Walk forward to the end of the method — bounded by the next
      // top-level method declaration `static Future`.
      final nextMethod = source.indexOf('static Future', methodStart + 1);
      final body = source.substring(
        methodStart,
        nextMethod > 0 ? nextMethod : source.length,
      );

      expect(
        body.contains("'branchId': branchId"),
        isTrue,
        reason:
            "$relPath submitJournalEntry payload no longer includes "
            "'branchId': branchId. The server reads payload['branchId'] "
            'in api_data_handler.postJournalEntry to attribute the JE; '
            'without it, the server defaults to branch 1 (main) and the '
            'Cluster B fix at the repo level becomes a no-op on the wire.',
      );
    });
  });
}
