// Spec 151 / BLOCKER C-02 — Sales-invoice void write-gate guard.
//
// Root cause (pre-fix): SalesRepositoryImpl.voidInvoice called
// `db.voidSalesInvoice(...)` UNCONDITIONALLY. voidSalesInvoice runs the FULL
// local stock + treasury + GL reversal. On a client/mirror device that
// violates R4 (client never writes GL/treasury/stock locally when a server is
// configured): the reversal is applied locally, the server is never told, so
// HQ keeps the invoice active + the phantom stock, and the next DeltaPull
// re-asserts the live invoice — orphaning the local reversal.
//
// Committee-BLOCKED first attempt (Option A): route the client void through
// `ClientWriteInterceptor.deleteSalesInvoice(invoiceId)`. REJECTED: that ships
// the LOCAL autoincrement id, and the server's DELETE /api/sales/<id> handler
// resolves by raw `int.parse(id)` with NO globalId. Client-created sales have
// local id ≠ server id (the orchestrator inserts a local row; DeltaPull keeps
// the divergent local id), so a strict client voiding its own sale either
// no-ops on the server (void lost) or voids a DIFFERENT innocent invoice at HQ
// (collateral corruption).
//
// Fix (this file's contract) — the FULL globalId-resolved void, mirroring the
// purchase-void (batch B6) end-to-end (R4/R9):
//   1. gate on SyncInterceptor.isClientMode (true for client AND mirror — R9);
//   2. the CALLER mints ONE deterministic void globalId
//      (JournalEntryGid.compute(sourceType: sourceSale, ..., verb: 'void') when
//      the invoice has a globalId, else UuidV7) and threads the SAME value into
//      the server submit AND the local reversal-JE derivation (R9);
//   3. client/mirror branch submits via
//      `ClientWriteInterceptor.submitVoidSalesInvoice(...globalId)` — NOT
//      deleteSalesInvoice, NOT the local reversal — writes only a LIGHT
//      updateSalesInvoiceStatus marker, and `return`s;
//   4. standalone/server branch runs the full local reversal
//      `db.voidSalesInvoice(id, reason, globalId: voidGid)` — passing the
//      SAME gid so the reversal JE converges under journal_entries.globalId's
//      UNIQUE index.
//
// This is a grep-style guard mirroring test/unit/orchestrator_gate_predicate_test.dart
// and the purchase-void guards. A behavioral test was considered but rejected:
// exercising voidInvoice in client mode requires a live SyncInterceptor.instance
// + ServerProxy/WriteRouter + sync_outbox stack (submitVoidSalesInvoice drives
// _tryOrQueueVoid, which performs a real server call or outbox insert and, in
// mirror mode, throws MirrorOfflineException). Standing that up in a unit test
// is fragile and adds no coverage the source-level guard doesn't already pin.
// A server-handler behavioral test (resolve-by-globalId + idempotency) would in
// turn need an in-memory AppDatabase, a seeded invoice, a permission bypass and
// a shelf Request — same fragility for no extra signal over the shape guard.
// The R9 family of invariants is enforced this same way across the codebase.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Sales void write-gate (Spec 151 / BLOCKER C-02)', () {
    const relPath = 'lib/data/repositories/sales_repository_impl.dart';
    late final String source;
    late final String voidBody;

    setUpAll(() {
      final file = File(relPath);
      expect(
        file.existsSync(),
        isTrue,
        reason: 'expected sales repository at $relPath',
      );
      source = file.readAsStringSync();

      // Carve the voidInvoice method body: from its signature to the next
      // method (getSalesPrintData). Anchoring on the signature keeps the
      // preceding doc-comment (which legitimately mentions the symbols) out of
      // the carved region.
      final sigIdx = source.indexOf('Future<void> voidInvoice(int invoiceId');
      expect(
        sigIdx,
        greaterThan(0),
        reason: 'expected voidInvoice method in $relPath',
      );
      final endIdx = source.indexOf('getSalesPrintData(', sigIdx);
      expect(
        endIdx,
        greaterThan(sigIdx),
        reason: 'expected getSalesPrintData after voidInvoice — file structure '
            'changed; re-anchor the carve.',
      );
      voidBody = source.substring(sigIdx, endIdx);
    });

    test('voidInvoice gates on SyncInterceptor.isClientMode', () {
      // R9: the write gate MUST be SyncInterceptor.isClientMode (true for
      // client AND mirror), never NetworkService.instance.isClient.
      expect(
        voidBody.contains('SyncInterceptor.isClientMode'),
        isTrue,
        reason:
            '$relPath voidInvoice no longer gates on SyncInterceptor.isClientMode. '
            'Without the gate it calls db.voidSalesInvoice unconditionally, '
            'running the full local stock/treasury/GL reversal on a client/mirror '
            'device (R4 violation) while the server keeps the invoice live. '
            'See specs/151-full-audit/findings — BLOCKER C-02.',
      );
      expect(
        voidBody.contains('NetworkService.instance.isClient'),
        isFalse,
        reason:
            '$relPath voidInvoice gates on NetworkService.instance.isClient, '
            'which is FALSE in mirror mode — the void would run the full local '
            'reversal on a mirror device and never reach HQ. Use '
            'SyncInterceptor.isClientMode (R9).',
      );
    });

    test('caller mints ONE deterministic void globalId (R9)', () {
      // R9: the CALLER — not the server, not the DAO's own random fallback —
      // mints the void's globalId and threads it end-to-end so the reversal JE
      // converges (client submit == server reversal JE == standalone reversal
      // JE) under journal_entries.globalId's UNIQUE index. Deriving it from the
      // invoice's own globalId + verb 'void' also makes an outbox replay
      // reproduce the SAME id instead of duplicating.
      expect(
        voidBody.contains('JournalEntryGid.compute('),
        isTrue,
        reason:
            '$relPath voidInvoice does not mint a deterministic void globalId '
            'via JournalEntryGid.compute(...). Committee BLOCKED the Option A '
            'delete-by-local-id path precisely because it threaded no globalId; '
            'the server then resolves by raw int id and can void the WRONG '
            'invoice at HQ. Mirror purchases_repository_impl _voidOrDeleteInvoice.',
      );
      expect(
        voidBody.contains('JournalEntryGid.sourceSale'),
        isTrue,
        reason:
            '$relPath voidInvoice must key the void gid on the SALE sourceType '
            '(JournalEntryGid.sourceSale), matching the purchase side\'s '
            'sourcePurchase.',
      );
      expect(
        voidBody.contains("verb: 'void'"),
        isTrue,
        reason:
            '$relPath voidInvoice void gid must use verb \'void\' so it is '
            'distinct from the original sale autopost JE gid.',
      );
    });

    test('client/mirror branch submits via submitVoidSalesInvoice with the '
        'threaded globalId — NOT deleteSalesInvoice, NOT the local reversal',
        () {
      // The gate variable is `final isClientMode = SyncInterceptor.isClientMode;`
      // and the client branch opens with `if (isClientMode) {`. The standalone
      // full reversal is the LAST db.voidSalesInvoice call in the method, so
      // carve the client branch as [client-branch-open, last-reversal-call).
      final branchIdx = voidBody.indexOf('if (isClientMode)');
      final standaloneIdx = voidBody.lastIndexOf('db.voidSalesInvoice(');
      expect(
        branchIdx,
        greaterThanOrEqualTo(0),
        reason: '$relPath voidInvoice must open its client branch with '
            '`if (isClientMode) {` (gate hoisted into a local, mirroring the '
            'purchase side).',
      );
      expect(
        standaloneIdx,
        greaterThan(branchIdx),
        reason:
            '$relPath voidInvoice: the standalone db.voidSalesInvoice(...) call '
            'must live AFTER the client branch. If it appears before, the full '
            'local reversal runs on the client. BLOCKER C-02.',
      );

      final clientBranch = voidBody.substring(branchIdx, standaloneIdx);

      // (a) It must submit the void — carrying the threaded globalId — through
      // the already-gated interceptor. That is the server-authoritative path.
      expect(
        clientBranch.contains('ClientWriteInterceptor.submitVoidSalesInvoice('),
        isTrue,
        reason:
            '$relPath voidInvoice client branch no longer submits via '
            'ClientWriteInterceptor.submitVoidSalesInvoice. The server resolves '
            'the invoice by globalId → invoiceNumber → id and performs the '
            'authoritative reversal; without this call (carrying the globalId) '
            'the void never reaches HQ or hits the wrong invoice. BLOCKER C-02.',
      );

      // (b) It must NOT use the committee-BLOCKED delete-by-local-id path.
      expect(
        clientBranch.contains('deleteSalesInvoice('),
        isFalse,
        reason:
            '$relPath voidInvoice client branch still calls '
            'ClientWriteInterceptor.deleteSalesInvoice(invoiceId) — the '
            'committee-BLOCKED Option A. It ships the LOCAL id with no globalId; '
            'the server resolves by raw int.parse(id) and can void a DIFFERENT '
            'invoice at HQ (collateral corruption).',
      );

      // (c) It must NOT run the full local reversal in the client branch.
      expect(
        clientBranch.contains('db.voidSalesInvoice('),
        isFalse,
        reason:
            '$relPath voidInvoice client branch still calls db.voidSalesInvoice '
            '— the FULL local stock/treasury/GL reversal, forbidden on a '
            'client/mirror device (R4). The server is the SSoT here.',
      );

      // (d) It must thread the minted gid into the submit.
      expect(
        clientBranch.contains('globalId: voidGlobalId'),
        isTrue,
        reason:
            '$relPath voidInvoice client branch does not thread the minted '
            'voidGlobalId into submitVoidSalesInvoice. R9 requires the SAME id '
            'reach the server so its reversal JE converges with a retry.',
      );

      // (e) It must write only a LIGHT local status marker.
      expect(
        clientBranch.contains('updateSalesInvoiceStatus('),
        isTrue,
        reason:
            '$relPath voidInvoice client branch no longer writes the light '
            'updateSalesInvoiceStatus marker. Without it the invoice does not '
            'drop out of the active list until the next DeltaPull.',
      );

      // (f) It must short-circuit before the standalone full-reversal call.
      expect(
        clientBranch.contains('return;'),
        isTrue,
        reason:
            '$relPath voidInvoice client branch does not `return;` before the '
            'standalone db.voidSalesInvoice call — the client would fall through '
            'and ALSO run the full local reversal. BLOCKER C-02.',
      );
    });

    test('acting userId is threaded so the voidPaidInvoice critical-op gate '
        'resolves a real user (C-02/062)', () {
      // Without a userId, the server (or standalone) voidSalesInvoice runs
      // requireCriticalOp(userId: null) for a FULLY-PAID invoice, which
      // fails closed (PermissionDenied). With the client submit fire-and-forget,
      // that server 403 is swallowed and DeltaPull reverts the local marker →
      // the paid-invoice void silently vanishes. voidInvoice must accept and
      // thread userId into BOTH the submit and the standalone DAO call.
      expect(
        voidBody.contains('int? userId'),
        isTrue,
        reason:
            '$relPath voidInvoice must take an `int? userId` so the acting user '
            'reaches the voidPaidInvoice critical-op gate.',
      );
      final branchIdx = voidBody.indexOf('if (isClientMode)');
      final standaloneIdx = voidBody.lastIndexOf('db.voidSalesInvoice(');
      final clientBranch = voidBody.substring(branchIdx, standaloneIdx);
      expect(
        clientBranch.contains('userId: userId'),
        isTrue,
        reason:
            '$relPath client branch does not thread userId into '
            'submitVoidSalesInvoice → server deletedBy is null → paid-invoice '
            'void fails the critical-op gate and is silently lost.',
      );
      expect(
        voidBody.substring(standaloneIdx).contains('deletedBy: userId'),
        isTrue,
        reason:
            '$relPath standalone db.voidSalesInvoice must pass deletedBy: userId '
            'so a fully-paid void on a standalone install gates on the real user.',
      );
    });

    test('standalone/server branch runs the full local reversal WITH the '
        'threaded globalId', () {
      // Standalone (no server) is the only mode allowed to run the full local
      // reversal — keep it intact, and pass the minted gid so its reversal JE
      // is deterministic (converges with a server that later joins the fleet).
      expect(
        voidBody.contains('db.voidSalesInvoice('),
        isTrue,
        reason:
            '$relPath voidInvoice dropped the standalone db.voidSalesInvoice '
            'call. Standalone installs have no server, so the local reversal is '
            'the ONLY reversal — removing it silently skips stock/treasury/GL '
            'reversal on void.',
      );
      expect(
        voidBody.contains('globalId: voidGlobalId'),
        isTrue,
        reason:
            '$relPath voidInvoice must thread voidGlobalId into the standalone '
            'db.voidSalesInvoice(...) so the reversal JE is deterministic (R9).',
      );
    });

    test('cancelInvoice funnels through voidInvoice (covered by the same gate)',
        () {
      // cancelInvoice must delegate to voidInvoice (which is gated) rather than
      // reach db.voidSalesInvoice directly — otherwise it would bypass the gate.
      final cancelIdx = source.indexOf('Future<void> cancelInvoice(int invoiceId');
      expect(
        cancelIdx,
        greaterThan(0),
        reason: 'expected cancelInvoice method in $relPath',
      );
      final voidSigIdx = source.indexOf(
        'Future<void> voidInvoice(int invoiceId',
        cancelIdx,
      );
      // cancelInvoice body is everything up to voidInvoice's doc-comment/sig.
      final cancelRegion = source.substring(cancelIdx, voidSigIdx);
      expect(
        cancelRegion.contains('voidInvoice('),
        isTrue,
        reason:
            '$relPath cancelInvoice no longer delegates to voidInvoice. It must '
            'route through the gated voidInvoice, not reach the DAO directly.',
      );
      expect(
        cancelRegion.contains('voidSalesInvoice('),
        isFalse,
        reason:
            '$relPath cancelInvoice now calls voidSalesInvoice(...) directly, '
            'bypassing the client/mirror gate on voidInvoice — same R4 violation '
            'as BLOCKER C-02, via the cancel path.',
      );
    });
  });

  // ── Server + wiring shape guards ─────────────────────────────────────────
  // The client repo shape (above) is only sound if the whole submit chain
  // exists and resolves by globalId. These grep-guards pin the remaining layers
  // that make the threaded globalId land on an authoritative, idempotent void.
  group('Sales void submit chain wiring (Spec 151 / BLOCKER C-02)', () {
    String read(String rel) {
      final f = File(rel);
      expect(f.existsSync(), isTrue, reason: 'expected $rel');
      return f.readAsStringSync();
    }

    test('DAO voidSalesInvoice accepts + threads globalId into the reversal JE',
        () {
      const rel = 'lib/data/database/daos/sales_actions_dao.dart';
      final src = read(rel);
      final start = src.indexOf('Future<void> voidSalesInvoice(int invoiceId');
      final end = src.indexOf('deleteSalesInvoice(int invoiceId', start);
      expect(start, greaterThan(0), reason: 'voidSalesInvoice not found in $rel');
      expect(end, greaterThan(start),
          reason: 'deleteSalesInvoice sentinel not found after voidSalesInvoice');
      final body = src.substring(start, end);
      expect(
        body.contains('String? globalId'),
        isTrue,
        reason:
            '$rel voidSalesInvoice must accept {String? globalId} so the caller '
            'can thread the deterministic void gid into the reversal JE (R9). '
            'Default null keeps standalone behaviour.',
      );
      expect(
        body.contains('globalId: globalId'),
        isTrue,
        reason:
            '$rel voidSalesInvoice does not thread globalId into its reversal '
            'createJournalEntry(...). Without it the reversal JE keeps a random '
            'gid and survives DeltaPull as a duplicate of the server\'s.',
      );
    });

    test('interceptor exposes submitVoidSalesInvoice → sales/void queue',
        () {
      final trading = read('lib/services/interceptor/cwi_trading.dart');
      expect(
        trading.contains('submitVoidSalesInvoice'),
        isTrue,
        reason: 'cwi_trading.dart missing submitVoidSalesInvoice.',
      );
      expect(
        trading.contains('.submitVoidSale('),
        isTrue,
        reason: 'submitVoidSalesInvoice must call _proxy.submitVoidSale(...).',
      );
      final pub = read('lib/services/interceptor/cwi_core.dart');
      expect(
        pub.contains('submitVoidSalesInvoice'),
        isTrue,
        reason: 'cwi_core.dart missing the public '
            'submitVoidSalesInvoice stub.',
      );
    });

    test('proxy posts /api/sales/void', () {
      final proxy = read('lib/services/server_proxy.dart');
      expect(
        proxy.contains('submitVoidSale('),
        isTrue,
        reason: 'server_proxy.dart missing submitVoidSale.',
      );
      expect(
        proxy.contains("'/api/sales/void'"),
        isTrue,
        reason: 'submitVoidSale must POST /api/sales/void.',
      );
    });

    test('route + handler: POST /api/sales/void → postVoidSale', () {
      final router = read('lib/services/api/api_handler.dart');
      expect(
        router.contains("'/api/sales/void'") &&
            router.contains('postVoidSale'),
        isTrue,
        reason: 'api_handler.dart missing route '
            "router.post('/api/sales/void', _sales.postVoidSale).",
      );
    });

    test('handler postVoidSale resolves by globalId, is idempotent, threads gid',
        () {
      const rel = 'lib/services/api/api_sales_handler.dart';
      final src = read(rel);
      final start = src.indexOf('postVoidSale(Request request)');
      expect(start, greaterThan(0), reason: '$rel missing postVoidSale.');
      // Bound the carve at the next method/helper.
      final end = src.indexOf('Future<int> _resolveUserId(', start);
      final body =
          src.substring(start, end > start ? end : src.length);
      // requirePermission gate.
      expect(
        body.contains('requirePermission'),
        isTrue,
        reason: '$rel postVoidSale must gate on requirePermission (salesDelete).',
      );
      // Resolve by globalId → invoiceNumber → id (the whole point of the fix).
      expect(
        body.contains('salesGlobalId') &&
            body.contains('.globalId.equals(') &&
            body.contains('.invoiceNumber.equals(') &&
            body.contains('.id.equals('),
        isTrue,
        reason: '$rel postVoidSale must resolve the invoice by '
            'globalId → invoiceNumber → id (client/server ids diverge; local id '
            'alone would void the WRONG invoice).',
      );
      // Idempotency: an already-voided invoice returns success, no re-reversal.
      expect(
        body.contains("status == 'voided'") && body.contains('idempotent'),
        isTrue,
        reason: '$rel postVoidSale must short-circuit an already-voided invoice '
            '(idempotent replay) before calling db.voidSalesInvoice again.',
      );
      // Thread the client-minted gid into the authoritative reversal: read
      // data['globalId'] and pass it straight into db.voidSalesInvoice.
      expect(
        body.contains("data['globalId']") &&
            body.contains('db.voidSalesInvoice(') &&
            body.contains('globalId: voidGlobalId'),
        isTrue,
        reason: '$rel postVoidSale must read data[\'globalId\'] and pass it into '
            'db.voidSalesInvoice(..., globalId: voidGlobalId) so the server '
            'reversal JE carries the SAME id the client threaded (R9 '
            'convergence).',
      );
    });

    test('offline replay: sales/void → submitVoidSale', () {
      const rel = 'lib/services/offline_sync_worker.dart';
      final src = read(rel);
      final caseIdx = src.indexOf("case 'sales':");
      expect(caseIdx, greaterThan(0), reason: "$rel missing case 'sales':");
      // Bound at the next case label.
      final nextCase = src.indexOf('case ', caseIdx + 10);
      final block = src.substring(caseIdx, nextCase > caseIdx ? nextCase : src.length);
      expect(
        block.contains("operation == 'void'") &&
            block.contains('submitVoidSale('),
        isTrue,
        reason: "$rel case 'sales' does not replay operation 'void' via "
            'proxy.submitVoidSale(...). A void queued while offline would fall '
            'through the switch and be silently dropped on drain.',
      );
    });
  });
}
