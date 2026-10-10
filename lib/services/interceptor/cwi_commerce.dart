part of '../client_write_interceptor.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Commerce module — Expenses · Receipts · Parties
//
// Part of the ClientWriteInterceptor library.  Extracted as part of
// Week-11 god-file split (original: 2359 lines → 5 focused files).
// All methods are static on _CwiCommerce and are called via thin delegation
// stubs on ClientWriteInterceptor so no call site changes are needed.
// ═══════════════════════════════════════════════════════════════════════════

class _CwiCommerce {
  _CwiCommerce._();

  // ── Expenses ──────────────────────────────────────────────────────────────

  static Future<int?> createExpense({
    required double amount,
    required String category,
    String? description,
    int? partyId,
    int? safeId,
    int? userId,
    int? costCenterId,
    int? branchId,
    String? globalId,
    String? paperType,
  }) async {
    if (!SyncInterceptor.isClientMode) return null;
    debugPrint('[ClientInterceptor] Routing expense to server');

    // Feature 044 — thread `partyGlobalId` + `partyName` so the server can
    // resolve to its OWN party id via `resolvePartyId`. Field log showed:
    //   safe_transactions_party_id_fkey: Key (party_id)=(1000000006) is not
    //   present in table "parties"
    // The mirror's local `parties.id` (a high autoincrement offset) does
    // not exist on the server. Same divergence pattern as supplier/customer
    // in sales/purchases — solved there by routing through `resolvePartyId`
    // which prefers globalId, falls back to clientId, and auto-creates a
    // placeholder when only the globalId is known. Sending nothing about
    // the party identity on these two paths was the only reason it
    // collapsed under FK 23503.
    final partyGlobalId =
        await ClientWriteInterceptor._lookupPartyGlobalId(partyId);
    final partyName = await ClientWriteInterceptor._lookupPartyName(partyId);

    return ClientWriteInterceptor._tryOrQueue(
      tableName: 'expenses',
      operation: 'insert',
      payload: {
        'amount': amount,
        'category': category,
        'description': description,
        'partyId': partyId,
        'partyGlobalId': ?partyGlobalId,
        'partyName': ?partyName,
        'safeId': safeId,
        'userId': userId,
        'costCenterId': costCenterId,
        'branchId': branchId,
        'globalId': globalId,
        'paperType': paperType,
      },
      serverCall: (reqIdemKey) => ClientWriteInterceptor._proxy.submitExpense(
        amount: amount,
        category: category,
        description: description,
        partyId: partyId,
        partyGlobalId: partyGlobalId,
        partyName: partyName,
        safeId: safeId,
        userId: userId,
        costCenterId: costCenterId,
        branchId: branchId,
        globalId: globalId,
        // Spec 081 — was missing on the wire pre-fix; server then treated
        // cheque expenses as cash and posted a duplicate Dr AP / Cr Cash JE.
        paperType: paperType,
        idempotencyKey: reqIdemKey,
      ),
    );
  }

  static Future<bool> deleteExpense(int id) async {
    if (!SyncInterceptor.isClientMode) return false;
    debugPrint('[ClientInterceptor] Routing expense delete to server');
    return ClientWriteInterceptor._tryOrQueueVoid(
      tableName: 'expenses',
      operation: 'delete',
      payload: {'id': id},
      serverCall: (reqIdemKey) async {
        await ClientWriteInterceptor._proxy.deleteExpense(id);
      },
    );
  }

  // ── Receipts ──────────────────────────────────────────────────────────────

  static Future<int?> createReceipt({
    required double amount,
    required String category,
    String? description,
    int? partyId,
    int? safeId,
    int? userId,
    int? branchId,
    int? costCenterId,
    // Issue 3 (Feature 020): see receipt_voucher_dialog — operator may pick a
    // specific CoA account (e.g. "جاري صاحب المنشأه") to override the
    // category-default credit leg. Threaded into both the local replay
    // payload (so an outbox replay carries the choice) and the live
    // serverCall.
    int? linkedAccountId,
    String? globalId,
    // Spec 133 — symmetric with createExpense. Must reach the server so it
    // can skip the cash JE and the safe transaction for cheque receipts
    // (commercial papers owns both). Pre-133 the field was always null on
    // the wire, so the server posted a phantom Dr Safe / Cr Customer JE
    // on top of the correct CP entry — the customer ledger showed two
    // credits per cheque.
    String? paperType,
  }) async {
    if (!SyncInterceptor.isClientMode) return null;
    debugPrint('[ClientInterceptor] Routing receipt to server');

    // Issue 12: ship the safe's globalId alongside its local id so the
    // server can resolve to its OWN safe id even when the chart of safes
    // was seeded independently on each side. Without this the server
    // looked up safe id=N (= the client's local id) and either missed it
    // entirely or posted to a completely unrelated safe — vouchers ended
    // up in someone else's till. Same FK-divergence pattern the journals
    // fix used for accounts (Issue 11).
    String? safeGlobalId;
    final db = ClientWriteInterceptor._db;
    if (safeId != null && db != null) {
      try {
        final safe = await (db.select(db.safes)
              ..where((s) => s.id.equals(safeId))
              ..limit(1))
            .getSingleOrNull();
        safeGlobalId = safe?.globalId;
      } catch (e) {
        debugPrint('[ClientInterceptor] safe lookup failed (non-fatal): $e');
      }
    }

    // Feature 044 — same `partyGlobalId` + `partyName` threading as
    // createExpense. Receipts on mirror were equally exposed to the FK
    // violation (party_id NOT present in users); the server now resolves
    // the party via `resolvePartyId` so a stale/divergent local id is
    // healed at the server boundary.
    final partyGlobalId =
        await ClientWriteInterceptor._lookupPartyGlobalId(partyId);
    final partyName = await ClientWriteInterceptor._lookupPartyName(partyId);

    // Spec 136 ISS-26 (#4) — light LOCAL cache so a CASH receipt shows in the
    // customer statement IMMEDIATELY on the mirror/client. createReceipt
    // otherwise only routes to the server; the party statement is a LOCAL read,
    // so the receipt was invisible until a delta-pull — and the pulled row
    // carries the SERVER partyId, which never matches the local (1B) party id,
    // so it stayed invisible even after sync (SafeTransactionSyncStrategy
    // stores partyId verbatim, no remap). We write the row with the LOCAL
    // partyId + the SHARED globalId; when the server echoes its copy back, that
    // strategy dedups on globalId and KEEPS this row, so it remains visible
    // against the correct party. Cash only — cheque receipts are the
    // commercial-paper row (dual-written by the dialog) and the server skips
    // the safe txn for cheques (Spec 133). No balance/JE mutation here: the
    // server is the SoT and the next pull reconciles safe/party balances.
    if (db != null &&
        !WriteRouter.isWebClient && // الويب: القاعدة بعيدة للقراءة فقط
        partyId != null &&
        safeId != null &&
        globalId != null &&
        globalId.isNotEmpty &&
        (paperType == null || paperType.isEmpty)) {
      try {
        final safeRow = await (db.select(db.safes)
              ..where((s) => s.id.equals(safeId))
              ..limit(1))
            .getSingleOrNull();
        final shortGid =
            globalId.length >= 12 ? globalId.substring(0, 12) : globalId;
        // Idempotent: skip if a row with this globalId already exists (retry,
        // or the server echo already landed).
        final dup = await (db.select(db.safeTransactions)
              ..where((t) => t.globalId.equals(globalId))
              ..limit(1))
            .getSingleOrNull();
        if (dup == null) {
          await db.into(db.safeTransactions).insert(
                SafeTransactionsCompanion.insert(
                  voucherNumber: 'CACHE-$shortGid',
                  safeId: safeId,
                  transactionType: 'receipt',
                  category: category,
                  amount: amount,
                  balanceAfter: (safeRow?.balance ?? 0) + amount,
                  partyId: Value(partyId),
                  description: Value(description),
                  costCenterId: Value(costCenterId),
                  globalId: Value(globalId),
                ),
              );
          debugPrint('[ClientInterceptor] receipt local cache row written '
              '(party=$partyId safe=$safeId gid=$shortGid)');
        }
      } catch (e) {
        debugPrint(
            '[ClientInterceptor] receipt local cache failed (non-fatal): $e');
      }
    }

    return ClientWriteInterceptor._tryOrQueue(
      tableName: 'receipts',
      operation: 'insert',
      payload: {
        'amount': amount,
        'category': category,
        'description': description,
        'partyId': partyId,
        'partyGlobalId': ?partyGlobalId,
        'partyName': ?partyName,
        'safeId': safeId,
        'safeGlobalId': safeGlobalId,
        'userId': userId,
        'branchId': branchId,
        'costCenterId': costCenterId,
        'linkedAccountId': ?linkedAccountId,
        'globalId': globalId,
        if (paperType != null && paperType.isNotEmpty) 'paperType': paperType,
      },
      serverCall: (reqIdemKey) => ClientWriteInterceptor._proxy.submitReceipt(
        amount: amount,
        category: category,
        description: description,
        partyId: partyId,
        partyGlobalId: partyGlobalId,
        partyName: partyName,
        safeId: safeId,
        safeGlobalId: safeGlobalId,
        userId: userId,
        branchId: branchId,
        costCenterId: costCenterId,
        linkedAccountId: linkedAccountId,
        globalId: globalId,
        paperType: paperType,
        idempotencyKey: reqIdemKey,
      ),
    );
  }

  // ── Parties ───────────────────────────────────────────────────────────────

  static Future<int?> createParty({
    required String name,
    String? code,
    String? phone,
    String? address,
    bool isCustomer = true,
    bool isSupplier = false,
    bool isDeliveryCompany = false,
    String? taxId,
    double creditLimit = 0,
    // v164 — مهلةُ السداد. تمرّ إلى الخادم وإلى المرآة معاً: حقلٌ يُكتَب
    // محلّيّاً ولا يصل المركزَ يعود مختلفاً بأوّل سحبِ دلتا.
    int paymentTermsDays = 0,
    double balance = 0,
    double fixedDiscount = 0,
    String priceLevel = 'default',
    int? groupId,
    String? globalId,
    List<int> branchIds = const [],
    int? costCenterId,
  }) async {
    if (!SyncInterceptor.isClientMode) return null;
    debugPrint('[ClientInterceptor] Routing party create to server');

    final db = ClientWriteInterceptor._db;

    // ── Local dedup guard ──────────────────────────────────────────────────
    if (db != null) {
      try {
        final trimmedCode = code?.trim();
        if (trimmedCode != null && trimmedCode.isNotEmpty) {
          final existing = await (db.select(db.parties)
                ..where((p) => p.code.equals(trimmedCode))
                ..limit(1))
              .getSingleOrNull();
          if (existing != null) {
            debugPrint('[ClientInterceptor] createParty dedup: '
                'code="$trimmedCode" already exists as id=${existing.id}.');
            return existing.id;
          }
        }
        final trimmedPhone = phone?.trim();
        final trimmedName = name.trim();
        if (trimmedName.isNotEmpty && trimmedPhone != null && trimmedPhone.isNotEmpty) {
          final candidates = await (db.select(db.parties)
                ..where((p) => p.name.equals(trimmedName))
                ..limit(20))
              .get();
          for (final c in candidates) {
            if (c.phone == trimmedPhone) {
              debugPrint('[ClientInterceptor] createParty dedup: '
                  'name+phone match existing id=${c.id}.');
              return c.id;
            }
          }
        }
        // Cluster 035 / Issue 2 (2026-05-12) — known-seed-name dedup for
        // delivery companies. Without this guard, a cashier quick-adding
        // 'اشيائي' / 'طلبات' / 'كريم' (no phone) mints a fresh globalId
        // and creates a second row alongside the seeded one. Same set of
        // names PartySyncStrategy's Tier C re-link covers, so the two
        // guards stay consistent.
        if (isDeliveryCompany && trimmedName.isNotEmpty) {
          const knownDeliverySeedNames = <String>{
            'طلبات', 'كريم', 'اشيائي',
            'شركة توصيل طلبات',
            'شركة توصيل كريم',
            'شركة توصيل اشيائي',
          };
          if (knownDeliverySeedNames.contains(trimmedName)) {
            // Match the existing dedup style in this file: name-only query
            // + isDeliveryCompany check in Dart (the parent client_write_-
            // interceptor.dart imports drift with `show Value` only, so the
            // `&` boolean-Expression operator isn't in scope here).
            final candidates = await (db.select(db.parties)
                  ..where((p) => p.name.equals(trimmedName))
                  ..limit(5))
                .get();
            for (final c in candidates) {
              if (c.isDeliveryCompany) {
                debugPrint('[ClientInterceptor] createParty dedup: '
                    'delivery seed-name "$trimmedName" → existing id=${c.id}.');
                return c.id;
              }
            }
          }
        }
      } catch (e) {
        debugPrint('[ClientInterceptor] createParty local dedup failed (non-fatal): $e');
      }
    }

    final effectiveGlobalId =
        (globalId != null && globalId.isNotEmpty) ? globalId : const Uuid().v7();
    final isGlobal = branchIds.isEmpty;
    final data = {
      'globalId': effectiveGlobalId,
      'name': name,
      if (code != null && code.isNotEmpty) 'code': code,
      'phone': phone,
      'address': address,
      'isCustomer': isCustomer,
      'isSupplier': isSupplier,
      'isDeliveryCompany': isDeliveryCompany,
      'taxId': taxId,
      'creditLimit': creditLimit,
      'paymentTermsDays': paymentTermsDays,
      'balance': balance,
      'fixedDiscount': fixedDiscount,
      'priceLevel': priceLevel,
      'groupId': ?groupId,
      'isGlobal': isGlobal,
      if (!isGlobal) 'branchIds': branchIds.join(','),
      'costCenterId': ?costCenterId,
    };

    final serverId = await ClientWriteInterceptor._tryOrQueue(
      tableName: 'parties',
      operation: 'insert',
      payload: data,
      serverCall: (reqIdemKey) =>
          ClientWriteInterceptor._proxy.createParty(data, idempotencyKey: reqIdemKey),
    );

    // ── Local mirror (offline-first UX) ──────────────────────────────────
    //
    // Without this, the just-created party is invisible on the client's
    // own screen until DeltaPull eventually backfills it.
    // (الويب: لا كاش محلي — القراءة من القناة.)
    if (db != null && !WriteRouter.isWebClient) {
      try {
        await db.into(db.parties).insertOnConflictUpdate(
          PartiesCompanion.insert(
            name: name,
            code: code != null && code.isNotEmpty ? Value(code) : const Value.absent(),
            phone: Value(phone),
            address: Value(address),
            isCustomer: Value(isCustomer),
            isSupplier: Value(isSupplier),
            isDeliveryCompany: Value(isDeliveryCompany),
            isActive: const Value(true),
            taxId: Value(taxId),
            balance: Value(balance),
            creditLimit: Value(creditLimit),
            paymentTermsDays: Value(paymentTermsDays),
            fixedDiscount: Value(fixedDiscount),
            priceLevel: Value(priceLevel),
            groupId: groupId != null ? Value(groupId) : const Value.absent(),
            globalId: Value(effectiveGlobalId),
            isGlobal: Value(isGlobal),
            branchIds: !isGlobal ? Value(branchIds.join(',')) : const Value.absent(),
            costCenterId: costCenterId != null ? Value(costCenterId) : const Value.absent(),
          ),
        );
      } catch (e) {
        debugPrint('[ClientInterceptor] party local mirror failed (non-fatal): $e');
      }
    }
    return serverId;
  }

  static Future<bool> updateParty(int id, Map<String, dynamic> data) async {
    if (!SyncInterceptor.isClientMode) return false;
    debugPrint('[ClientInterceptor] Routing party update to server');
    return ClientWriteInterceptor._tryOrQueueVoid(
      tableName: 'parties',
      operation: 'update',
      payload: {'id': id, ...data},
      serverCall: (reqIdemKey) async {
        await ClientWriteInterceptor._proxy.updateParty(id, data, idempotencyKey: reqIdemKey);
      },
    );
  }

  static Future<bool> deleteParty(int id, {String? idempotencyKey}) async {
    if (!SyncInterceptor.isClientMode) return false;
    debugPrint('[ClientInterceptor] Routing party delete to server');
    return ClientWriteInterceptor._tryOrQueueVoid(
      tableName: 'parties',
      operation: 'delete',
      payload: {'id': id},
      serverCall: (reqIdemKey) async {
        await ClientWriteInterceptor._proxy
            .deleteParty(id, idempotencyKey: idempotencyKey ?? reqIdemKey);
      },
    );
  }
}
