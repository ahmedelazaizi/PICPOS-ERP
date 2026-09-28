part of '../client_write_interceptor.dart';

/// Shared transport and identity helpers used by interceptor domain parts.
/// Keeping these implementation details outside the public facade keeps the
/// facade small while preserving every existing ClientWriteInterceptor API.
// Documentation retained verbatim while core helper bodies moved here.

  /// Returns true whenever writes are routed through this interceptor
  /// (HTTP first, optional outbox second) instead of going to the local
  /// DB. That covers both:
  ///   • `NetworkMode.client` — the cashier's device, which has its own
  ///     local cache + outbox for offline resilience.
  ///   • `NetworkMode.mirror` — the admin's remote laptop, which uses
  ///     the same HTTP path but has no outbox; failures throw
  ///     [MirrorOfflineException] (handled inside `_tryOrQueue`).
  /// The legacy name (`isClientModeImpl`) is preserved because 60+ files
  /// already check `SyncInterceptor.isClientMode` to decide "should I
  /// intercept this write?" — broadening the predicate is the
  /// least-disruptive way to support mirror mode without a 60-file
  /// rename. Read it as "intercepted mode" going forward.
  /// Spec 088 USR-2 — mirror-only predicate. `isClientModeImpl` is true
  /// for both client AND mirror (the broadened R9 gate that 60+ files
  /// depend on); `isMirrorModeImpl` narrows it back to mirror-only for
  /// the few sites that need to distinguish the two.
  /// Local database — set once by [initialize] before any writes.
  // ═══════════════════════════════════════════════════════════════
  // Generic offline-safe wrappers (used by every part-file module)
  // ═══════════════════════════════════════════════════════════════
  /// Look up the username for a userId in the local DB, and inject
  /// `createdByUsername` into [payload] if it's missing.  This ensures every
  /// client→server write carries a stable string identifier so the server can
  /// resolve the user by username when the auto-increment IDs diverge (e.g.
  /// a user was created locally before the first full sync).
      // Lookup/enrichment failures do not invalidate the original write, but
      // they can remove the stable identity needed for sync reconciliation.
  /// True for exceptions that mean "we never got an answer from HQ"
  /// (offline / unreachable / timeout). Anything else is a server-side
  /// rejection (HTTP 4xx/5xx, JSON parse failure, …) and the operator
  /// needs to see the real reason, not a generic "connection lost".
  /// Execute [serverCall] and, on failure, queue the operation locally.
  /// Returns the server result on success, or null if queued offline.
  /// After a successful call, fires a DeltaPull so side-effect rows
  /// (journal entries, safe transactions, stock movements, …) propagate
  /// back to the local DB without waiting for the next sync tick.
  /// **Mirror-mode behaviour (Feature 006 / MM.C):** when
  /// `WriteRouter.isMirrorActive` is true, the admin's HQ-side userId is
  /// stamped into [payload] for audit attribution, the outbox fallback
  /// is **skipped**, and a network failure raises
  /// [MirrorOfflineException] instead of silently queueing. Mirror mode
  /// is the admin acting as HQ from a remote laptop — buffering writes
  /// in the outbox would let HQ data drift out of sync without anyone
  /// noticing.
      // Feature 011 / Issue 10 — opportunistic outbox drain.
      // Field evidence: a client queued POS-2 and POS-3 offline, then
      // POS-4 succeeded once the server became reachable, but POS-2/3
      // sat in the outbox unattended for minutes. The drain only fired
      // on WebSocket reconnect, pending-count change at queue time, or
      // a 30-second heartbeat — never on operation success. Now that
      // we know the server is reachable (this serverCall just succeeded),
      // kick the drain so any pre-existing pending items go out
      // immediately. drainOutbox() is reentrant-safe via its
      // _isDraining guard, so calling it on every success is cheap.
        // Persist the full underlying error to disk so an operator can pull
        // the log file and see what actually failed — `debugPrint` alone is
        // invisible in release builds.
  /// Dispatch a server write under the failure contract of the CURRENT mode.
  /// [_tryOrQueue] already gets the interceptor side right: mirror mode skips
  /// the outbox and throws [MirrorOfflineException]. The defect this helper
  /// closes is on the **caller** side — repositories launched the submit with
  /// `unawaited(...).catchError(debugPrint)` and then wrote their local cache
  /// row unconditionally. In mirror mode that turns a rejected write into a
  /// row the operator sees as saved forever, while HQ never heard about it
  /// (and the log line even claimed "queued in outbox", which is a lie there).
  /// * **Mirror** — `await` the submit and let the exception propagate, so the
  ///   caller aborts BEFORE writing anything locally. Mirror has no outbox by
  ///   design (SYNC_ARCHITECTURE §8.3); the server is the source of truth and
  ///   the next DeltaPull re-materialises whatever HQ actually accepted.
  /// * **Client** — unchanged fire-and-forget. By the time the future
  ///   completes `_tryOrQueue` has already parked the payload in the outbox,
  ///   so blocking the UI on the network would only hurt offline-first
  ///   resilience on cashier devices.
  /// Awaiting inside a DB transaction is deliberately NOT how this is used:
  /// callers must submit first, then open their local transaction. Holding a
  /// SQLite/PG transaction open across an HTTP round-trip locks the database
  /// for the duration and is a red rule in SYNC_ARCHITECTURE §9.6.
  // ── نطاقُ تجميع الاستبدال ───────────────────────────────────────────────
  //
  // الاستبدالُ مستندان في معاملةٍ واحدة، وقرارُ المالك أن يصلا الخادمَ في
  // **حمولةٍ واحدة**. وشقّاه يرسلان من مستودعَين مختلفَين لا يعرف أحدُهما
  // الآخر، لكنّ كليهما يمرّ من هنا — فالالتقاطُ في هذه النقطة يقمع
  // الحمولتَين المنفردتَين بلا لمسِ أيٍّ من المستودعَين.
  //
  // **و`Zone` لا حقلٌ ساكن:** الحقلُ الساكنُ يتسرّب إن رمى نداءٌ بين الفتح
  // والإغلاق، فيبتلع مزامنةَ كلِّ بيعٍ تالٍ صامتاً. وقيمةُ النطاق تموت مع
  // النطاق مهما خرج منه الاستثناء.
  //
  // ⚠️ **وهذا يرفع انتهاكاً قائماً لا يضيف واحداً:** [dispatchWrite] في وضع
  // المرآة تنتظر الشبكةَ (`await submit()`)، وشقُّ المردود يُنادى **داخل**
  // معاملة الاستبدال ⇒ معاملةُ قاعدةٍ مفتوحةٌ عبر ذهابِ HTTP وإيابِه، وهي
  // قاعدةٌ حمراء (‏SYNC_ARCHITECTURE §9.6). والالتقاطُ لا يلمس الشبكةَ
  // أصلاً، والإرسالُ يقع **بعد** إغلاق المعاملة.
  /// المُجمِّعُ الفعّالُ في النطاق الحاليّ، أو `null` خارجَه — والخارجُ هو
  /// الحالةُ الساحقة، فكلُّ بيعٍ ومردودٍ عاديٍّ يمرّ من هنا بلا تغيير.
  /// يشغّل [body] في نطاقٍ يُلتقَط فيه شقّا الاستبدال بدل إرسالهما منفردَين.
    // Client mode keeps the legacy contract EXACTLY, including the outer
    // guard: a throw raised while merely building the request must not take
    // down the caller, because the local write that follows is the cashier's
    // record of the sale.
  /// Void-returning variant: returns true if succeeded or queued.
  /// Same mirror-mode semantics as [_tryOrQueue] — see that method's
  /// doc for the no-outbox + MirrorOfflineException contract.
      // Feature 011 / Issue 10 — opportunistic outbox drain (mirror of
      // the same logic in _tryOrQueue above; see that comment).
  // ═══════════════════════════════════════════════════════════════
  // Shared globalId helpers (used by all part-file modules)
  // ═══════════════════════════════════════════════════════════════
  /// Look up the local `parties` row for [partyId] and return its `globalId`.
  /// Mints + persists a UUID if missing (legacy data). Returns null for a
  /// null/zero id or when the row cannot be found.
      // Lookup/enrichment failures do not invalidate the original write, but
      // they can remove the stable identity needed for sync reconciliation.
  /// Look up the local `parties` row for [partyId] and return its name.
  /// Returns null for a null/zero id or when the row cannot be found.
  /// Look up the local `products` row for [productId] and return its
  /// `globalId`. Mints + persists a UUID if missing. Returns null for a
  /// null/zero id or when the row doesn't exist.
      // Lookup/enrichment failures do not invalidate the original write, but
      // they can remove the stable identity needed for sync reconciliation.
  /// Walk the items array inside [payload] and inject `productGlobalId` into
  /// each item whose `productId` resolves locally. Server handlers prefer
  /// the UUID over the integer id, surviving client/server id drift.
  // ═══════════════════════════════════════════════════════════════
  // Commerce — Expenses · Receipts · Parties
  // ═══════════════════════════════════════════════════════════════
  // ignore_for_file: lines_longer_than_80_chars
  // ═══════════════════════════════════════════════════════════════
  // Catalog — Products · Purchases · Shifts · Settings
  //           Categories · Users · Warehouses
  // ═══════════════════════════════════════════════════════════════
  // Feature 045 — accept optional [moveToCategoryId] so the caller can
  // pick the destination explicitly (null = uncategorized). Threaded
  // through to the server's deleteCategory handler so the bulk-move +
  // soft-delete run inside one server-side transaction.
  // ═══════════════════════════════════════════════════════════════
  // Trading — Sales · Inventory · Commercial Papers
  //           Safe Operations · Stock Transfers · Purchase Push
  // ═══════════════════════════════════════════════════════════════
  // C-02 (Spec 151) — sales-invoice void submit (globalId-resolved).
  // Spec 151 C-05 — customer-collection submit (globalId-resolved, additive).
  // Feature 048 (v130) — accept `counterAccountId` so the user-chosen
  // contra leg from the status-change dialog reaches the server's
  // JE poster instead of being silently dropped into the notes string.
  // PR-2 (pre-deploy batch B6) — purchase-invoice void submit.
  // Spec 151 C-03 — purchase-invoice payment submit.
  // ═══════════════════════════════════════════════════════════════
  // SyncInterceptor @override implementations — delegated to _CwiSync
  // ═══════════════════════════════════════════════════════════════
  /// v174 / قسمُ ٧ — حفظُ مخطَّط قاعةٍ كاملاً.
  /// **وهي ساكنةٌ لا `@override`** عمداً: `SyncInterceptor` واجهةٌ
  /// ينفّذها غيرُ هذا الصنف، وإضافةُ عضوٍ إليها تُلزِم كلَّ منفّذٍ
  /// بما لا يخصُّه. وهذا نفسُ شكلِ `submitPurchase`.
  /// v176 / §٨ — مرفقٌ واحدٌ ببايتاتِه.
  // ── Activity Logs ──────────────────────────────────────────────────────────
  /// Push an activity log entry to the server (non-blocking, offline-safe).
  // ═══════════════════════════════════════════════════════════════
  // Admin (Feature 006 / MM.C) — Branches · Safes · Accounts
  //                              · Cost Centers · Document Sequences
  //
  // Routes "previously server-only" admin CRUD through the same
  // intercepted path as commerce/catalog so mirror-mode operators can
  // perform these operations from a remote laptop.
  // ═══════════════════════════════════════════════════════════════
  // Feature 049 (v131) — see _CwiAdmin.deleteBranch for the reassign
  // semantics. Null falls back to the legacy "throw if user assignments
  // exist" behaviour so old callers stay safe.

class _CwiCoreSupport {
  _CwiCoreSupport._();

  static final proxy = ServerProxy.instance;
  static AppDatabase? _db;
  static AppDatabase? get database => _db;

  static void initialize(AppDatabase db) => _db = db;

  static Future<void> enrichPayloadWithUsername(
      Map<String, dynamic> payload) async {
    if (_db == null) return;
    if (payload.containsKey('createdByUsername') ||
        payload.containsKey('userName')) {
      return;
    }
    final raw = payload['userId'] ?? payload['changedBy'];
    final uid = raw is int
        ? raw
        : (raw is num ? raw.toInt() : int.tryParse('${raw ?? ''}'));
    if (uid == null || uid == 0) return;
    try {
      final user = await (_db!.select(_db!.users)
            ..where((u) => u.id.equals(uid))
            ..limit(1))
          .getSingleOrNull();
      if (user != null) payload['createdByUsername'] = user.username;
    } catch (error, stack) {
      unawaited(DiagnosticLogger.logError(
        'SYNC-INTERCEPTOR',
        'non-critical identity enrichment failed',
        error,
        stack,
      ));
    }
  }

  static bool _isNetworkException(Object error) =>
      error is SocketException ||
      error is TimeoutException ||
      error is http.ClientException;

  static Future<T?> tryOrQueue<T>({
    required String tableName,
    required String operation,
    required Map<String, dynamic> payload,
    required Future<T?> Function(String idempotencyKey) serverCall,
  }) async {
    await enrichPayloadWithUsername(payload);
    final mirrorMode = WriteRouter.isMirrorActive;
    if (mirrorMode) WriteRouter.stampAdminAttribution(payload);
    final idempotencyKey = const Uuid().v7();
    payload['idempotency_key'] = idempotencyKey;
    try {
      final result = await serverCall(idempotencyKey);
      unawaited(DeltaPullService.instance.pullAll());
      unawaited(OfflineSyncWorker.instance.drainOutbox(force: true));
      return result;
    } catch (error) {
      if (mirrorMode) {
        final isNetwork = _isNetworkException(error);
        unawaited(DiagnosticLogger.log(
          'MIRROR-WRITE',
          '❌ $tableName/$operation failed '
              '(${isNetwork ? "network" : "server"}): $error',
        ));
        debugPrint('[MirrorInterceptor] Mirror write FAILED for '
            '$tableName/$operation — re-throwing as MirrorOfflineException '
            '(${isNetwork ? "network" : "server"}: $error)');
        throw isNetwork
            ? MirrorOfflineException.network(error.toString())
            : MirrorOfflineException.serverError(error.toString());
      }
      debugPrint('[ClientInterceptor] Server unreachable — queueing '
          '$tableName/$operation offline (error: $error)');
      if (_db != null) {
        await _db!.addToSyncOutbox(
          tableName: tableName,
          recordId: payload['id']?.toString() ??
              payload['globalId']?.toString() ??
              payload['invoiceNumber']?.toString() ??
              '0',
          operation: operation,
          payload: payload,
          idempotencyKey: idempotencyKey,
        );
      } else {
        debugPrint('[ClientInterceptor] ⚠️⚠️⚠️ WRITE LOST — _db is null for '
            '$tableName/$operation. Call ClientWriteInterceptor.initialize(db) '
            'at startup BEFORE any writes.');
        unawaited(DiagnosticLogger.log(
          'CLIENT-WRITE',
          '⚠️ WRITE LOST — _db null for $tableName/$operation '
              '(initialize() not called)',
        ));
      }
      return null;
    }
  }

  static const Object exchangeCollectorKey = #picposExchangeCollector;

  static ExchangeLegCollector? get activeExchangeCollector =>
      Zone.current[exchangeCollectorKey] as ExchangeLegCollector?;

  static Future<T> runWithExchangeCollector<T>(
    ExchangeLegCollector collector,
    Future<T> Function() body,
  ) => runZoned(
        body,
        zoneValues: <Object?, Object?>{exchangeCollectorKey: collector},
      );

  static Future<void> dispatchWrite(
    Future<Object?> Function() submit, {
    required String tag,
  }) async {
    if (SyncInterceptor.isMirrorMode) {
      await submit();
      return;
    }
    try {
      unawaited(submit().catchError((Object error) {
        debugPrint('[$tag] Server sync failed (queued in outbox): $error');
        return null;
      }));
    } catch (error) {
      debugPrint('[$tag] Sync setup failed: $error');
    }
  }

  static Future<bool> tryOrQueueVoid({
    required String tableName,
    required String operation,
    required Map<String, dynamic> payload,
    required Future<void> Function(String idempotencyKey) serverCall,
  }) async {
    await enrichPayloadWithUsername(payload);
    final mirrorMode = WriteRouter.isMirrorActive;
    if (mirrorMode) WriteRouter.stampAdminAttribution(payload);
    final idempotencyKey = const Uuid().v7();
    payload['idempotency_key'] = idempotencyKey;
    try {
      await serverCall(idempotencyKey);
      unawaited(DeltaPullService.instance.pullAll());
      unawaited(OfflineSyncWorker.instance.drainOutbox(force: true));
      return true;
    } catch (error) {
      if (mirrorMode) {
        final isNetwork = _isNetworkException(error);
        unawaited(DiagnosticLogger.log(
          'MIRROR-WRITE',
          '❌ $tableName/$operation failed '
              '(${isNetwork ? "network" : "server"}): $error',
        ));
        debugPrint('[MirrorInterceptor] Mirror void write FAILED for '
            '$tableName/$operation — re-throwing as MirrorOfflineException '
            '(${isNetwork ? "network" : "server"}: $error)');
        throw isNetwork
            ? MirrorOfflineException.network(error.toString())
            : MirrorOfflineException.serverError(error.toString());
      }
      debugPrint('[ClientInterceptor] Server unreachable — queueing '
          '$tableName/$operation offline (error: $error)');
      if (_db != null) {
        await _db!.addToSyncOutbox(
          tableName: tableName,
          recordId: payload['id']?.toString() ??
              payload['globalId']?.toString() ??
              payload['invoiceNumber']?.toString() ??
              '0',
          operation: operation,
          payload: payload,
          idempotencyKey: idempotencyKey,
        );
      } else {
        debugPrint('[ClientInterceptor] ⚠️⚠️⚠️ WRITE LOST — _db is null for '
            '$tableName/$operation (void variant). Call '
            'ClientWriteInterceptor.initialize(db) at startup BEFORE any writes.');
        unawaited(DiagnosticLogger.log(
          'CLIENT-WRITE',
          '⚠️ WRITE LOST — _db null for $tableName/$operation void '
              '(initialize() not called)',
        ));
      }
      return true;
    }
  }

  static Future<String?> lookupPartyGlobalId(int? partyId) async {
    if (partyId == null || partyId == 0 || _db == null) return null;
    try {
      final row = await (_db!.select(_db!.parties)
            ..where((p) => p.id.equals(partyId))
            ..limit(1))
          .getSingleOrNull();
      if (row == null) return null;
      var gid = row.globalId;
      if (gid == null || gid.isEmpty) {
        gid = const Uuid().v7();
        try {
          await (_db!.update(_db!.parties)..where((p) => p.id.equals(partyId)))
              .write(PartiesCompanion(globalId: Value(gid)));
        } catch (error, stack) {
          unawaited(DiagnosticLogger.logError(
            'SYNC-INTERCEPTOR',
            'non-critical party identity enrichment failed',
            error,
            stack,
          ));
        }
      }
      return gid;
    } catch (error) {
      debugPrint('[ClientInterceptor] party lookup for id=$partyId '
          'failed (non-fatal): $error');
      return null;
    }
  }

  static Future<String?> lookupPartyName(int? partyId) async {
    if (partyId == null || partyId == 0 || _db == null) return null;
    try {
      final row = await (_db!.select(_db!.parties)
            ..where((p) => p.id.equals(partyId))
            ..limit(1))
          .getSingleOrNull();
      return row?.name;
    } catch (error) {
      debugPrint('[ClientInterceptor] party name lookup for id=$partyId '
          'failed (non-fatal): $error');
      return null;
    }
  }

  static Future<String?> lookupProductGlobalId(int? productId) async {
    if (productId == null || productId == 0 || _db == null) return null;
    try {
      final row = await (_db!.select(_db!.products)
            ..where((p) => p.id.equals(productId))
            ..limit(1))
          .getSingleOrNull();
      if (row == null) return null;
      var gid = row.globalId;
      if (gid == null || gid.isEmpty) {
        gid = const Uuid().v7();
        try {
          await (_db!.update(_db!.products)..where((p) => p.id.equals(productId)))
              .write(ProductsCompanion(globalId: Value(gid)));
        } catch (error, stack) {
          unawaited(DiagnosticLogger.logError(
            'SYNC-INTERCEPTOR',
            'non-critical product identity enrichment failed',
            error,
            stack,
          ));
        }
      }
      return gid;
    } catch (error) {
      debugPrint('[ClientInterceptor] product lookup for id=$productId '
          'failed (non-fatal): $error');
      return null;
    }
  }

  static Future<void> enrichItemsWithProductGlobalId(
    Map<String, dynamic> payload, {
    String itemsKey = 'items',
  }) async {
    final raw = payload[itemsKey];
    if (raw is! List) return;
    for (final item in raw) {
      if (item is! Map) continue;
      if (item['productGlobalId'] is String &&
          (item['productGlobalId'] as String).isNotEmpty) {
        continue;
      }
      final productId = item['productId'];
      final id = productId is int
          ? productId
          : (productId is num
              ? productId.toInt()
              : int.tryParse('${productId ?? ''}'));
      if (id == null || id == 0) continue;
      final gid = await lookupProductGlobalId(id);
      if (gid != null && gid.isNotEmpty) item['productGlobalId'] = gid;
    }
  }
}


