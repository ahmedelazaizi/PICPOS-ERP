// ═══════════════════════════════════════════════════════════════════════════
// API SALES HANDLER — Sales, Returns, Held Orders, WebSocket
// ═══════════════════════════════════════════════════════════════════════════
//
// Extracted from ApiHandler for maintainability (PIR C-01).

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:shelf/shelf.dart';
import 'api_errors.dart';
import 'ws_connection_guard.dart';
import 'package:drift/drift.dart';
import '../../core/logging/diagnostic_logger.dart';
import '../../core/permissions/permission_codes.dart';
import '../../data/database/database.dart';
import '../../domain/models/exchange_sync_payload.dart';
import '../../domain/models/distribution_model.dart';
import 'api_user_context.dart';
import '../stock_shortage_policy_service.dart';
import 'api_handler_base.dart';

/// Handles all sales-related API endpoints.
class ApiSalesHandler extends ApiHandlerBase {
  ApiSalesHandler(super.db, super.wsClients);

  // ═══════════════════════════════════════════════════════════════
  // POST /api/sales — Create a new sale
  // ═══════════════════════════════════════════════════════════════

  Future<Response> postSale(Request request) async {
    try {
      // Spec 077 Batch 1 (Spec 060 Phase 2): per-user permission gate.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.salesCreate);
      if (perm != null) return perm;

      final body = await request.readAsString();
      final data = json.decode(body) as Map<String, dynamic>;

      final clientInvoiceNumber = data['invoiceNumber'] as String?;
      final clientIpSuffix = data['clientIpSuffix'] as String?;
      final clientBranchId = parseIntNullable(data['branchId']);
      await DiagnosticLogger.log('API-SALE',
          'POST /api/sales from client: invoice=$clientInvoiceNumber '
          'ipSuffix=$clientIpSuffix branchId=$clientBranchId userId=${data['userId']} '
          'total=${data['total']} saleType=${data['saleType']}');

      // L4 (2026-04-28): Resolve the branch code so server-side invoice
      // numbers carry a meaningful branch prefix (e.g. CAI-POS-1) instead of
      // the opaque CLT{ipSuffix}-POS-1.
      //
      // Feature 054 (v134): the legacy CLT{ipSuffix} fallback is a
      // collision risk under N-branch concurrency — two clients on the
      // same NAT/IP suffix produce the same prefix and the same
      // expected invoice number. Now we LOG the fallback loudly (was
      // silent) so operators can spot a branch missing its code; a
      // future v135 will promote this to a hard 400 once all the
      // production deployments are guaranteed to have branch codes
      // set.
      String? branchCodePrefix;
      if (clientBranchId != null) {
        try {
          final br = await (db.select(db.branches)
                ..where((b) => b.id.equals(clientBranchId)))
              .getSingleOrNull();
          if (br?.code != null && br!.code!.isNotEmpty) {
            branchCodePrefix = br.code;
          } else if (br != null) {
            await DiagnosticLogger.log('API-SALE',
                '⚠ branch_code_missing: branchId=$clientBranchId '
                'name="${br.name}" — falling back to CLT prefix which is '
                'collision-prone under concurrent multi-branch traffic. '
                'Operator must set a unique `code` on this branch. '
                '(Feature 054 v134 observability.)');
          } else {
            await DiagnosticLogger.log('API-SALE',
                '⚠ branch_not_found: branchId=$clientBranchId — request '
                'will be processed with CLT fallback prefix. Likely a '
                'stale client cache pointing at a soft-deleted branch.');
          }
        } catch (_) {/* non-fatal */}
      }

      final isClientSale =
          clientIpSuffix != null ||
          (clientInvoiceNumber?.startsWith('CLT') ?? false) ||
          (branchCodePrefix != null &&
              (clientInvoiceNumber?.startsWith('$branchCodePrefix-') ?? false));

      // Pre-compute the expected server invoice number for client sales so we
      // can properly check for duplicates. If the client retries a sync, it
      // sends the original local invoice number (e.g. POS-1). The server
      // saves it as <BRANCH>-POS-1 (or CLT{ip}-POS-1 when no branch code).
      // Idempotency relies on us looking up the *prefixed* form.
      String? expectedServerInvoiceNumber;
      if (isClientSale && clientInvoiceNumber != null) {
        if (branchCodePrefix != null &&
            !clientInvoiceNumber.startsWith('$branchCodePrefix-')) {
          expectedServerInvoiceNumber = '$branchCodePrefix-$clientInvoiceNumber';
        } else if (branchCodePrefix == null && !clientInvoiceNumber.startsWith('CLT')) {
          expectedServerInvoiceNumber = 'CLT${clientIpSuffix ?? '00'}-$clientInvoiceNumber';
        } else {
          expectedServerInvoiceNumber = clientInvoiceNumber;
        }
      } else {
        expectedServerInvoiceNumber = clientInvoiceNumber;
      }

      debugPrint(
        '[API] Sale received from client: ${clientInvoiceNumber ?? 'unknown'}, '
        'branch=$branchCodePrefix, IP suffix: $clientIpSuffix, '
        'mapping to: $expectedServerInvoiceNumber',
      );

      // Idempotency Check (Solves Duplicate Transaction Vulnerability)
      //
      // Feature 054 (v134) — pass the per-action verifier so a cached
      // response pointing at a row that no longer exists in
      // `sales_invoices` is invalidated instead of being returned.
      // The supermarket data-loss incident (2026-05-14) traced to a
      // cache row that outlived its target. See spec.md §"Root cause
      // sequence" for the full repro.
      final idempotencyKey = request.headers['x-idempotency-key'] ?? request.headers['X-Idempotency-Key'];
      if (idempotencyKey != null) {
        final cached = await checkIdempotency(idempotencyKey,
            verifyExists: idempotencyVerifierFor('postSale'));
        if (cached != null) {
          await DiagnosticLogger.log('API-SALE',
              '⚠ idempotency-hit: returning cached response key=$idempotencyKey '
              'cached_serverId=${cached['serverId']} '
              'cached_invoice=${cached['invoiceNumber']}');
          return jsonResponse(cached);
        }
      }

      // UUID-First idempotency (Phase 1): if the same globalId has been
      // synced before, return the existing server row. Catches the case
      // where the idempotency-key cache has been cleared (e.g. server
      // restart) but the client still retries the same logical invoice.
      //
      // Feature 054 (v134) — this is now the SOLE dedup path. The
      // legacy invoice_number dedup block (previously here) was
      // removed: invoice_number can collide across DB resets and
      // branches that share prefixes, while globalId (UUIDv7 minted on
      // the originating client per ENGINEERING_GUIDELINES.md R9) cannot. Keeping the
      // weaker dedup let the supermarket lose 15 sales when leftover
      // `processed_messages` entries pointed at wiped `sales_invoices`
      // rows.
      final incomingGlobalId = data['globalId'] as String?;
      if (incomingGlobalId != null && incomingGlobalId.isNotEmpty) {
        final existingByGid = await (db.select(db.salesInvoices)
              ..where((s) => s.globalId.equals(incomingGlobalId))
              ..limit(1))
            .getSingleOrNull();
        if (existingByGid != null) {
          await DiagnosticLogger.log('API-SALE',
              '⚠ duplicate-skip globalId=$incomingGlobalId → existing serverId='
              '${existingByGid.id} invoice=${existingByGid.invoiceNumber} '
              '(idempotent return, no insert)');
          return jsonResponse({
            'success': true,
            'duplicate': true,
            'serverId': existingByGid.id,
            'invoiceNumber': existingByGid.invoiceNumber,
            'orderNumber': existingByGid.orderNumber,
            'message': 'Invoice already exists on server (by globalId)',
          });
        }
      }

      // Feature 054 (v134): invoice_number-based dedup REMOVED.
      //
      // The previous block here used `expectedServerInvoiceNumber`
      // (e.g. "QS-POS-1") as the dedup key. That's fundamentally weak:
      //   1. invoice_number is reset every time a client's local DB is
      //      wiped — the next session generates POS-1 again with a
      //      fresh globalId, but the SAME prefixed name collides with
      //      a leftover row on the server.
      //   2. Branches without a `code` fell back to "CLT{ipSuffix}-",
      //      which collides across branches on the same IP suffix.
      //
      // Field repro (2026-05-14, supermarket): leftover QS-POS-1
      // through QS-POS-40 from a prior session, plus orphaned cache
      // entries in `processed_messages`, made today's 15 fresh sales
      // (each with a NEW globalId) come back as `duplicate: true,
      // serverId=<old>` — all 15 sales lost.
      //
      // `globalId` (UUIDv7) is the cryptographically unique key and
      // is now the SOLE dedup path. The UNIQUE constraint on
      // `sales_invoices.global_id` (Feature 007) prevents true
      // duplicates from ever reaching the table.

      // Parse items. Each productId is resolved via productGlobalId when
      // the client sent one — this absorbs client/server id drift and also
      // prevents the server from silently inventing a new product row later
      // (the "duplicate product from sales flow" bug root cause).
      final itemsList = (data['items'] as List? ?? []);
      final items = <SalesInvoiceItemsCompanion>[];
      for (final item in itemsList) {
        final m = item as Map<String, dynamic>;
        final resolvedProductId = await resolveProductId(
          clientProductId: parseIntNullable(m['productId']),
          productGlobalId: m['productGlobalId'] as String?,
          fallbackCode: m['productCode'] as String?,
          fallbackName: m['productName'] as String?,
        );
        if (resolvedProductId == null) {
          throw Exception('Validation Error: item missing productId/productGlobalId');
        }
        items.add(SalesInvoiceItemsCompanion(
          productId: Value(resolvedProductId),
          quantity: Value(parseDouble(m['quantity'])),
          unitPrice: Value(parseDouble(m['unitPrice'])),
          discount: Value(parseDoubleNullable(m['discount']) ?? 0.0),
          total: Value(parseDouble(m['total'])),
          costPrice: Value(parseDoubleNullable(m['costPrice']) ?? 0.0),
          // SAL-2: sale-unit → base-unit conversion factor. Without this the
          // server defaulted to 1.0 and under-decremented physical stock on
          // non-base-unit (carton/box) sales.
          quantityInBase: Value(parseDoubleNullable(m['quantityInBase']) ?? 1.0),
          taxRate: Value(parseDoubleNullable(m['taxRate']) ?? 0.0),
          taxAmount: Value(parseDoubleNullable(m['taxAmount']) ?? 0.0),
          note: Value(m['note'] as String?),
        ));
      }

      final clientWarehouseId = parseInt(data['warehouseId']);
      if (clientWarehouseId == 0) throw Exception('Validation Error: Valid warehouseId is required.');
      final clientCostCenterId = parseIntNullable(data['costCenterId']);
      // clientBranchId already parsed at the top of this method (line ~33)
      final resolvedWarehouseId = await _resolveWarehouseId(clientWarehouseId, branchId: clientBranchId);
      final clientUserId = parseInt(data['userId']);
      if (clientUserId == 0) throw Exception('Validation Error: Valid userId is required.');
      final resolvedUserId = await _resolveUserId(clientUserId,
          fallbackUsername: data['createdByUsername'] as String?,
          fallbackGlobalId: data['userGlobalId'] as String?);

      // Parse client invoice date (preserve original date for reports)
      final clientInvoiceDate = data['invoiceDate'] != null
          ? DateTime.tryParse(data['invoiceDate'] as String)
          : null;

      // Format ad-hoc customer info into notes (POS-4/POS-6)
      final adhocName = data['adhocCustomerName'] as String?;
      final adhocPhone = data['adhocCustomerPhone'] as String?;
      final adhocNote = data['adhocCustomerNote'] as String?;
      final originalNotes = data['notes'] as String?;

      final List<String> notesParts = [];
      if (adhocName != null && adhocName.trim().isNotEmpty) {
        notesParts.add('العميل: ${adhocName.trim()}');
      }
      if (adhocPhone != null && adhocPhone.trim().isNotEmpty) {
        notesParts.add('هاتف: ${adhocPhone.trim()}');
      }
      if (adhocNote != null && adhocNote.trim().isNotEmpty) {
        notesParts.add(adhocNote.trim());
      }
      if (originalNotes != null && originalNotes.trim().isNotEmpty) {
        notesParts.add(originalNotes.trim());
      }
      final resolvedNotes = notesParts.isNotEmpty ? notesParts.join(' | ') : null;

      // Resolve customerId via globalId to absorb client/server FK drift
      // (parties row never reached the server, or client id is from the
      // client's 1B+ namespace). Auto-creates a placeholder row keyed on
      // UUID when needed; DeltaPull will later merge the full details.
      final resolvedCustomerId = await resolvePartyId(
        clientPartyId: parseIntNullable(data['customerId']),
        partyGlobalId: data['customerGlobalId'] as String?,
        isCustomer: true,
        fallbackName: adhocName,
      );

      // Insert invoice + post accounting in ONE atomic transaction (P0-01 fix).
      // Previously: invoice committed first, accounting in a separate non-fatal
      // try/catch — a crash between the two left orphan invoices with no GL entry.
      // Now: both operations share a single db.transaction(); any accounting
      // failure rolls back the invoice as well. The client's outbox retries.
      final serverId = await db.transaction(() async {
        final id = await db.createSalesInvoice(
          globalId: incomingGlobalId, // UUID-First: carry client identity through
          invoiceNumber: expectedServerInvoiceNumber,
          customerId: resolvedCustomerId,
          warehouseId: resolvedWarehouseId,
          userId: resolvedUserId,
          subtotal: (parseDoubleNullable(data['subtotal']))?.toDouble() ?? 0,
          discount: (parseDoubleNullable(data['discount']))?.toDouble() ?? 0,
          tax: (parseDoubleNullable(data['tax']))?.toDouble() ?? 0,
          total: (parseDoubleNullable(data['total']))?.toDouble() ?? 0,
          paid: (parseDoubleNullable(data['paid']))?.toDouble() ?? 0,
           currencyId: parseIntNullable(data['currencyId'] ?? data['currency_id']),
           exchangeRate: parseDoubleNullable(data['exchangeRate'] ?? data['exchange_rate']),
          // ⚠️ **بدونه يرحّل الخادمُ قيداً مخالفاً لقيد العميل.** الخادمُ
          // يعيد بناءَ القيد من الحمولة، فغيابُ الفرق يجعله يرى `total > paid`
          // فيفتح ذمّةً مدينةً لا وجودَ لها ويترك الفاتورةَ `pending` —
          // بينما الفاتورةُ نفسُها على الجهاز مكتملةٌ ومتوازنة.
          // و`?? 0` يُبقي عميلاً أقدمَ لا يرسل المفتاح على سلوكه حرفيّاً.
          roundingAdjustment:
              (parseDoubleNullable(data['roundingAdjustment']))?.toDouble() ?? 0,
          paymentMethod: data['paymentMethod'] as String? ?? 'cash',
          deliveryFee: (parseDoubleNullable(data['deliveryFee']))?.toDouble() ?? 0,
          notes: resolvedNotes,
          cashAmount: (parseDoubleNullable(data['cashAmount']))?.toDouble(),
          bankAmount: (parseDoubleNullable(data['bankAmount']))?.toDouble(),
          clickAmount: (parseDoubleNullable(data['clickAmount']))?.toDouble(),
          cashSafeId: parseIntNullable(data['cashSafeId']),
          bankSafeId: parseIntNullable(data['bankSafeId']),
          clickSafeId: parseIntNullable(data['clickSafeId']),
          saleType: data['saleType'] as String? ?? 'default',
          items: items,
          invoiceDate: clientInvoiceDate,
          costCenterId: clientCostCenterId,
          branchId: clientBranchId,
          deliveryCompanyId: parseIntNullable(data['deliveryCompanyId']),
          courierId: parseIntNullable(data['courierId']),
          deliveryStatus: data['deliveryStatus'] as String?,
          // C2 (v183) — the client's chosen «حساب المبيعات»; absent ⇒ NULL ⇒
          // mapped default (older clients unchanged).
          revenueAccountId: parseIntNullable(data['revenueAccountId']),
          // v185 — the client's rep/route stamp; absent ⇒ resolved here.
          repStamp: RepStamp(
            repEmployeeId: parseIntNullable(data['repEmployeeId']),
            routeId: parseIntNullable(data['routeId']),
          ),
        );

        // Feature 009 / T020 — server-side auto-deplete (R4 / Constitution III).
        // The server is the SSoT in client/mirror modes: clients/mirrors do
        // NOT run applyAutoDepleteForSale locally for the same sale; we run it
        // here so raw materials are deducted exactly once. Skipped when the
        // client didn't send a `globalId` (legacy clients pre-Spec-002) — that
        // case still has no idempotent identity to derive consumption ids from.
        // The server's accounting path uses `autoPostCashSale` (legacy single-
        // account COGS leg). The per-raw-material JE split (T017) is a
        // documented deferral on the server side — the value of Feature 009
        // (correct stock + consumption rows + reports) is preserved.
        if (incomingGlobalId != null && incomingGlobalId.isNotEmpty) {
          final savedItems = await (db.select(db.salesInvoiceItems)
                ..where((it) => it.invoiceId.equals(id)))
              .get();
          final saleLineRefs = savedItems
              .map((it) => SaleLineRef(
                    saleItemId: it.id,
                    productId: it.productId,
                    // ⚠️ بوحدة الأساس — انظر التعليقَ المفصَّل في
                    // `sales_transaction_orchestrator`. نفسُ العطب: صينيّةٌ
                    // ×١٢ كانت تستهلك خاماتِ وجبةٍ واحدة.
                    qty: it.quantity *
                        (it.quantityInBase > 0 ? it.quantityInBase : 1.0),
                    warehouseId: resolvedWarehouseId,
                  ))
              .toList();
          // Feature 009 / T025: server runs the same 3-tier resolution as
          // the orchestrator. terminalId is intentionally null — the server
          // is not a POS terminal, so per-terminal overrides only fire on
          // the client side. Per-branch + global tiers still apply.
          final serverPolicy = await StockShortagePolicyService.resolveWith(
            get: db.getSettingValue,
            terminalId: null,
            branchId: clientBranchId,
          );
          await db.applyAutoDepleteForSale(
            saleInvoiceId: id,
            items: saleLineRefs,
            branchId: clientBranchId,
            shortagePolicy: serverPolicy.wireName,
            saleGlobalId: incomingGlobalId,
          );
        }

        // Accounting — no try/catch: failure MUST rollback the whole transaction.
        final createdInv = await db.getSalesInvoiceById(id);
        if (createdInv != null) {
          await db.autoPostCashSale(createdInv, costCenterId: clientCostCenterId);
          debugPrint('[API] Accounting entry created for sale $id');
        }
        await db.resignSalesInvoice(id);
        return id;
      });

      debugPrint('[API] Sale inserted as server ID: $serverId');
      await DiagnosticLogger.log('API-SALE',
          '✓ persisted: invoice=$expectedServerInvoiceNumber → serverId=$serverId '
          'userId=$resolvedUserId warehouseId=$resolvedWarehouseId');

      broadcast('sales');
      broadcast('accounting');

      // Force Drift stream notifications for server-side UI refresh.
      // Notify ALL affected tables so the server's own screens update immediately.
      db.markTablesUpdated({db.salesInvoices, db.salesInvoiceItems, db.journalEntries, db.journalEntryLines, db.safeTransactions});

      final createdInvoice = await db.getSalesInvoiceById(serverId);
      final responseBody = {
        'success': true,
        'serverId': serverId,
        'idempotencyKey': idempotencyKey, // Return back to confirm
        'invoiceNumber': createdInvoice?.invoiceNumber ?? '',
        'orderNumber': createdInvoice?.orderNumber ?? 0,
        'message': 'Sale inserted successfully',
        'serverTime': DateTime.now().toIso8601String(),
      };

      if (idempotencyKey != null) {
        await storeIdempotency(idempotencyKey, responseBody, actionType: 'postSale');
      }

      return jsonResponse(responseBody);
    } catch (e, st) {
      debugPrint('[API] postSale error: $e\n$st');
      await DiagnosticLogger.log('API-SALE',
          '❌ FAILED to persist client sale: $e');
      return ApiErrors.fail(e, 'Failed to process sale', st: st);
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // WebSocket (real-time push to clients)
  // ═══════════════════════════════════════════════════════════════

  FutureOr<Response> handleWebSocket(Request request) async {
    // 5.3: Origin + optional-token + connection caps (see WsConnectionGuard).
    final denied = await WsConnectionGuard.check(request);
    if (denied != null) return denied;
    // Spec 129 F1 — accept mode='mirror' + device_id query params alongside
    // the existing branch_id. Pre-129 clients send only branch_id and get
    // mode='client' by default (backward-compat: identical routing behaviour).
    final branchId = int.tryParse(
      request.requestedUri.queryParameters['branch_id'] ?? '',
    );
    final mode = request.requestedUri.queryParameters['mode'] ?? 'client';
    final deviceId = request.requestedUri.queryParameters['device_id'];
    final info = WsSubscriberInfo(mode: mode, branchId: branchId, deviceId: deviceId);

    final handler = webSocketHandler((WebSocketChannel ws, String? protocol) {
      wsClients[ws] = info;
      WsConnectionGuard.register(ws, request);
      debugPrint('[WS] $mode connected (branch=$branchId, device=${deviceId ?? "n/a"}, ${wsClients.length} total)');
      // FR-OBS-1 — every accepted WS lifecycle event logged with device_id.
      DiagnosticLogger.log(
        DiagnosticLogger.wsConnect,
        'mode=$mode device=${deviceId ?? "n/a"} branch=${branchId ?? "all"}',
      );
      ws.sink.add(
        json.encode({
          'event': 'connected',
          'ts': DateTime.now().millisecondsSinceEpoch,
        }),
      );
      ws.stream.listen(
        (_) {},
        onDone: () {
          wsClients.remove(ws);
          WsConnectionGuard.unregister(ws);
          debugPrint('[WS] $mode disconnected (${wsClients.length} remaining)');
          DiagnosticLogger.log(
            DiagnosticLogger.wsDisconnect,
            'mode=$mode device=${deviceId ?? "n/a"} reason=close',
          );
        },
        onError: (_) {
          wsClients.remove(ws);
          WsConnectionGuard.unregister(ws);
          DiagnosticLogger.log(
            DiagnosticLogger.wsDisconnect,
            'mode=$mode device=${deviceId ?? "n/a"} reason=error',
          );
        },
      );
    });
    return handler(request);
  }

  // ═══════════════════════════════════════════════════════════════
  // POST /api/sales/return — Process a sales return
  // ═══════════════════════════════════════════════════════════════

  Future<Response> postSalesReturn(Request request) async {
    try {
      // Spec 077 Batch 1 (Spec 060 Phase 2): per-user permission gate.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.salesReturnCreate);
      if (perm != null) return perm;

      return await ApiHandlerBase.withBroadcast<Response>(
        endpointLabel: 'postSalesReturn',
        tables: const {
          'sales_invoices', 'sales_invoice_items',
          'inventory', 'stock_movements',
          'parties', 'accounting', 'journal_entries',
        },
        body: () async {

      final data =
          json.decode(await request.readAsString()) as Map<String, dynamic>;

      // P5: UUID-First idempotency for sales returns. Without this, every
      // outbox replay (network blip, 429, etc.) created a brand-new return
      // invoice on the server, which then propagated back to the client via
      // DeltaPull as a phantom duplicate. The user-visible symptom: the same
      // return appearing 2-3 times in the returns history.
      final incomingReturnGlobalId = data['globalId'] as String?;
      if (incomingReturnGlobalId != null && incomingReturnGlobalId.isNotEmpty) {
        final existing = await (db.select(db.salesInvoices)
              ..where((s) => s.globalId.equals(incomingReturnGlobalId))
              ..limit(1))
            .getSingleOrNull();
        if (existing != null) {
          debugPrint('[API] postSalesReturn: globalId=$incomingReturnGlobalId '
              'already exists as serverId=${existing.id} — idempotent');
          return jsonResponse({'success': true, 'serverId': existing.id, 'duplicate': true});
        }
      }

      final originalInvoiceId = parseInt(data['originalInvoiceId']);
      final rawItems = (data['items'] as List);
      final items = <SalesInvoiceItemsCompanion>[];
      for (final item in rawItems) {
        final m = item as Map<String, dynamic>;
        final resolvedProductId = await resolveProductId(
          clientProductId: parseIntNullable(m['productId']),
          productGlobalId: m['productGlobalId'] as String?,
          fallbackCode: m['productCode'] as String?,
          fallbackName: m['productName'] as String?,
        );
        if (resolvedProductId == null) {
          throw Exception('Validation Error: return item missing productId/productGlobalId');
        }
        items.add(SalesInvoiceItemsCompanion(
          productId: Value(resolvedProductId),
          quantity: Value(parseDouble(m['quantity'])),
          unitPrice: Value(parseDouble(m['unitPrice'])),
          discount: Value(parseDoubleNullable(m['discount']) ?? 0.0),
          total: Value(parseDouble(m['total'])),
          costPrice: Value(parseDoubleNullable(m['costPrice']) ?? 0.0),
          // SAL-2: without this the server defaulted quantityInBase to 1.0
          // and under-restored physical stock on non-base-unit returns.
          quantityInBase: Value(parseDoubleNullable(m['quantityInBase']) ?? 1.0),
          taxRate: Value(parseDoubleNullable(m['taxRate']) ?? 0.0),
          taxAmount: Value(parseDoubleNullable(m['taxAmount']) ?? 0.0),
        ));
      }

      // Resolve warehouseId for returns too
      final clientWarehouseIdRet = parseInt(data['warehouseId']);
      if (clientWarehouseIdRet == 0) throw Exception('Validation Error: Valid warehouseId is required.');
      final clientBranchIdRet = parseIntNullable(data['branchId']);
      final resolvedWarehouseIdRet = await _resolveWarehouseId(clientWarehouseIdRet, branchId: clientBranchIdRet);
      final clientUserIdRet = parseInt(data['userId']);
      if (clientUserIdRet == 0) throw Exception('Validation Error: Valid userId is required.');
      final resolvedUserIdRet = await _resolveUserId(clientUserIdRet,
          fallbackUsername: data['createdByUsername'] as String?);

      final resolvedReturnCustomerId = await resolvePartyId(
        clientPartyId: parseIntNullable(data['customerId']),
        partyGlobalId: data['customerGlobalId'] as String?,
        isCustomer: true,
      );

      // Spec 002 (B2): resolve the original invoice by globalId first
      // (preferred — survives id divergence between client and server), then
      // by numeric id as fallback.
      //
      // Client issue #3 (2026-07-25): this resolution MUST happen BEFORE the
      // return row is created, because the return→original link is carried in
      // the `notes` text that `getReturnedAmountsForInvoices` parses. Writing
      // the client's raw `originalInvoiceId` there attributes the return to a
      // *client-local* id, which matches nothing on the server — so the
      // server's "المتبقي" never reflected the refund while the client's did.
      SalesInvoiceData? original;
      try {
        final originalGlobalId = data['originalInvoiceGlobalId'] as String?;
        if (originalGlobalId != null && originalGlobalId.isNotEmpty) {
          original = await (db.select(db.salesInvoices)
                ..where((s) => s.globalId.equals(originalGlobalId))
                ..limit(1))
              .getSingleOrNull();
        }
        original ??= await (db.select(db.salesInvoices)
              ..where((s) => s.id.equals(originalInvoiceId))
              ..limit(1))
            .getSingleOrNull();
      } catch (e) {
        // Non-fatal: fall back to the client's id below (pre-fix behaviour).
        debugPrint('[API] postSalesReturn: original lookup failed: $e');
      }

      // Prefer the resolved SERVER id; fall back to the client's only when the
      // original genuinely can't be found (orphan return).
      final linkedOriginalId = original?.id ?? originalInvoiceId;

      final serverId = await db.createSalesInvoice(
        invoiceNumber: data['invoiceNumber'] as String?,
        customerId: resolvedReturnCustomerId,
        warehouseId: resolvedWarehouseIdRet,
        userId: resolvedUserIdRet,
        subtotal: (parseDoubleNullable(data['subtotal']))?.toDouble() ?? 0,
        discount: (parseDoubleNullable(data['discount']))?.toDouble() ?? 0,
        tax: (parseDoubleNullable(data['tax']))?.toDouble() ?? 0,
        total: (parseDoubleNullable(data['total']))?.toDouble() ?? 0,
        paid: (parseDoubleNullable(data['paid']))?.toDouble() ?? 0,
           currencyId: parseIntNullable(data['currencyId'] ?? data['currency_id']),
           exchangeRate: parseDoubleNullable(data['exchangeRate'] ?? data['exchange_rate']),
        paymentMethod: data['paymentMethod'] as String? ?? 'cash',
        saleType: 'return',
        // Carry the original's UUID so the client can re-resolve this link
        // against its OWN ids after DeltaPull replaces this row locally.
        notes: localReturnLinkNote(linkedOriginalId,
            originalGlobalId: original?.globalId),
        items: items,
        // P5: Carry the client's UUID through so the persisted row matches the
        // dedup key checked above on subsequent retries.
        globalId: incomingReturnGlobalId,
      );

      // Flip the original invoice's status to 'returned' or 'partial_return'
      // so the server's invoices screen + returns history dialog reflect it.
      try {
        final isFullReturn = (data['isFullReturn'] as bool?) ?? false;
        final newStatus = isFullReturn ? 'returned' : 'partial_return';

        if (original != null) {
          await (db.update(db.salesInvoices)
                ..where((s) => s.id.equals(original!.id)))
              .write(SalesInvoicesCompanion(status: Value(newStatus)));
          debugPrint('[API] postSalesReturn: original invoice ${original.id} '
              'status → $newStatus');
        } else {
          debugPrint('[API] postSalesReturn: could not find original invoice '
              '(id=$originalInvoiceId) — status flip skipped');
        }
      } catch (e) {
        // Non-fatal: the return itself was recorded. Surface the failure
        // in logs so we can investigate, but don't roll back the return.
        debugPrint('[API] postSalesReturn: status flip failed: $e');
      }

      // Feature 009 / T033 (Issue 6 / Cluster 021): on a server-side return
      // for a sale that used BOM auto-deplete, restore the raw materials at
      // the FROZEN unit_cost_at_sale. Mirrors the client-mode wiring in
      // returns_repository_impl. Best-effort: a missing original invoice or
      // a non-auto-deplete sale silently skips. Pragmatic mapping by
      // productId (rather than the client's saleInvoiceItemId, which can
      // diverge from the server's id) — works in the common case where each
      // product appears at most once in the original sale; degrades to
      // "consolidate per-product" if duplicated, which is acceptable for
      // this rare edge case.
      try {
        if (original != null) {
          final originalItems = await (db.select(db.salesInvoiceItems)
                ..where((i) => i.invoiceId.equals(original!.id)))
              .get();
          final origByProduct = <int, SalesInvoiceItem>{};
          for (final oi in originalItems) {
            origByProduct[oi.productId] = oi;
          }
          final fractionByOriginalItemId = <int, double>{};
          for (final ri in rawItems) {
            final m = ri as Map<String, dynamic>;
            final pid = parseIntNullable(m['productId']);
            final qty = parseDouble(m['quantity']);
            if (pid == null || qty <= 0) continue;
            final origItem = origByProduct[pid];
            if (origItem == null || origItem.quantity <= 0) continue;
            final fraction =
                (qty / origItem.quantity).clamp(0.0, 1.0).toDouble();
            fractionByOriginalItemId[origItem.id] = fraction;
          }
          if (fractionByOriginalItemId.isNotEmpty) {
            await db.reverseSaleConsumption(
              saleInvoiceId: original.id,
              salesReturnId: serverId,
              itemReturnFractions: fractionByOriginalItemId,
            );
          }
        }
      } catch (e) {
        // Non-fatal — the return invoice itself was recorded. Surface the
        // failure in logs so the field can investigate but don't roll
        // back: the client-side reversal already happened on the original
        // device.
        debugPrint('[API] postSalesReturn: BOM reversal failed: $e');
      }

      await db.resignSalesInvoice(serverId);
      return jsonResponse({'success': true, 'serverId': serverId});
        },
      );
    } catch (e) {
      debugPrint('[API] postSalesReturn error: $e');
      return ApiErrors.fail(e, 'Failed to process return');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // Exchange — المردودُ وبديلُه في معاملةٍ واحدة
  // ═══════════════════════════════════════════════════════════════

  /// يفكّ حمولةَ الاستبدال **الواحدة** إلى مستندَين داخل معاملةٍ واحدة.
  ///
  /// **لماذا مسارٌ ثالثٌ لا نداءان لـ[postSalesReturn] و[postSale]:** النداءان
  /// معاملتان منفصلتان، فسقوطُ الثاني يترك الأوّلَ مُودَعاً — وهي بعينِها
  /// نافذةُ الانفصال التي أُنشئت الحمولةُ الواحدةُ لإغلاقها. وهنا كلُّ
  /// الكتابات في `db.transaction` واحدة: تنجح كاملةً أو لا يبقى منها أثر.
  ///
  /// **ولا حسابَ ماليٌّ مكرَّر:** المالُ كلُّه يُحسب في طبقة `db.*` نفسِها
  /// التي ينادينها المعالجان الآخران — `createSalesInvoice` و
  /// `applyAutoDepleteForSale` و`autoPostCashSale` و`reverseSaleConsumption`.
  /// المكرَّرُ هنا هو الفكُّ والحلُّ فقط، وكلاهما يمرّ بنفس المساعدات
  /// المشتركة (`resolveProductId` · `resolvePartyId` · [_resolveWarehouseId] ·
  /// [_resolveUserId]) فلا تنزلق نسختان من منطق الحلّ.
  ///
  /// **وشقوقُ المردود قائمةٌ لا مستندٌ واحد:** `processSalesReturn` على العميل
  /// يقبل `isDamaged` للنداء كلِّه لا للسطر، فالوسمُ المختلط يُنتج سندَي
  /// مردودٍ. وحقلٌ مفردٌ هنا كان سيُسقط الشقَّ الثاني صامتاً.
  ///
  /// **وعكسُ استهلاك BOM داخل المعاملة لا خارجَها:** في [postSalesReturn] هو
  /// أفضلُ جهدٍ ملفوفٌ بـ`try/catch` لأن سندَ المردود كان قد أُودع فعلاً. هنا
  /// لا شيءَ أُودع بعد، فالسقوطُ يُرجِع الكلَّ ولا يترك نصفَ استبدال.
  Future<Response> postSalesExchange(Request request) async {
    try {
      // الاستبدالُ يرتجع **ويبيع** — فالصلاحيتان معاً لا إحداهما. ومن يملك
      // المردودَ وحدَه لا يفتح بابَ بيعٍ من هنا.
      final permReturn = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.salesReturnCreate);
      if (permReturn != null) return permReturn;
      final permSale = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.salesCreate);
      if (permSale != null) return permSale;

      return await ApiHandlerBase.withBroadcast<Response>(
        endpointLabel: 'postSalesExchange',
        tables: const {
          'sales_invoices', 'sales_invoice_items',
          'inventory', 'stock_movements',
          'parties', 'accounting', 'journal_entries',
        },
        body: () async {
          final data =
              json.decode(await request.readAsString()) as Map<String, dynamic>;

          final exchangeKey =
              (data['exchangeKey'] ?? data['globalId']) as String?;
          if (exchangeKey == null || exchangeKey.isEmpty) {
            throw Exception('Validation Error: exchangeKey is required');
          }
          final rawLegs = (data['returnLegs'] as List?) ?? const <dynamic>[];
          final saleData = (data['sale'] as Map?)?.cast<String, dynamic>();
          if (rawLegs.isEmpty || saleData == null || saleData.isEmpty) {
            throw Exception('Validation Error: exchange needs BOTH returnLegs '
                'and sale — نصفُ استبدالٍ لا يُودَع');
          }

          // Idempotency — على `globalId` فاتورةِ البيع البديلة، نفسِ مفتاح
          // [postSale]. فإعادةُ الإرسال من الطابور لا تُنشئ استبدالاً ثانياً.
          final saleGlobalId = saleData['globalId'] as String?;
          if (saleGlobalId != null && saleGlobalId.isNotEmpty) {
            final existing = await (db.select(db.salesInvoices)
                  ..where((s) => s.globalId.equals(saleGlobalId))
                  ..limit(1))
                .getSingleOrNull();
            if (existing != null) {
              debugPrint('[API] postSalesExchange: sale globalId=$saleGlobalId '
                  'already exists as serverId=${existing.id} — idempotent');
              return jsonResponse({
                'success': true,
                'serverId': existing.id,
                'duplicate': true,
              });
            }
          }

          // حلُّ الأصلية **قبل** أيّ كتابة: مفتاحُ الربط يُبنى على معرِّف
          // الخادم، وكتابتُه بمعرِّف العميل تُسنِد المردودَ إلى صفٍّ لا يطابق
          // شيئاً هنا — نفسُ عطبِ العميل #3 الموثَّق في [postSalesReturn].
          final fallbackOriginalId = parseInt(data['originalInvoiceId']);
          final originalGlobalId = data['originalInvoiceGlobalId'] as String?;
          SalesInvoiceData? lookedUp;
          if (originalGlobalId != null && originalGlobalId.isNotEmpty) {
            lookedUp = await (db.select(db.salesInvoices)
                  ..where((s) => s.globalId.equals(originalGlobalId))
                  ..limit(1))
                .getSingleOrNull();
          }
          lookedUp ??= await (db.select(db.salesInvoices)
                ..where((s) => s.id.equals(fallbackOriginalId))
                ..limit(1))
              .getSingleOrNull();
          // نسخةٌ نهائيّةٌ كي يترقّى النوعُ داخل المُغلَقات.
          final original = lookedUp;

          final serverId = await db.transaction(() async {
            for (final rawLeg in rawLegs) {
              await _applyExchangeReturnLeg(
                (rawLeg as Map).cast<String, dynamic>(),
                original: original,
                fallbackOriginalId: fallbackOriginalId,
                exchangeKey: exchangeKey,
              );
            }

            final saleId = await _applyExchangeSale(
              saleData,
              exchangeKey: exchangeKey,
              returnDocumentId: original?.id ?? fallbackOriginalId,
            );

            // حالةُ الأصلية ووسمُها — كتابةٌ **واحدة** بعد الشقَّين، فتحمل
            // `isFullReturn` المحسوبَ على المجموعتَين معاً لا على شقٍّ وحدَه.
            if (original != null) {
              final isFullReturn = (data['isFullReturn'] as bool?) ?? false;
              await (db.update(db.salesInvoices)
                    ..where((s) => s.id.equals(original.id)))
                  .write(SalesInvoicesCompanion(
                status: Value(isFullReturn ? 'returned' : 'partial_return'),
                notes: Value('${original.notes ?? 'استبدال'}'
                    '${exchangeLinkTag(exchangeKey)}'
                    '${exchangeSaleTag(saleId)}'),
              ));
            } else {
              debugPrint('[API] postSalesExchange: original invoice '
                  '(id=$fallbackOriginalId) not found — status flip skipped');
            }
            await db.resignSalesInvoice(saleId);
            return saleId;
          });

          // لا `broadcast()` يدويّاً هنا: `withBroadcast` أعلاه يبثّ كلَّ
          // جدولٍ في `tables` بنفسه، والحارسُ الهيكليُّ
          // `no_manual_broadcast_test` يرفض النداءَ المباشر. ونداءُ البثِّ في
          // `postSale` ليس نظيراً — تلك لا تستعمل الغلافَ أصلاً.
          //
          // و`markTablesUpdated` يبقى: هو إخطارُ مجاري drift لشاشات الخادم
          // نفسِه، لا بثُّ الشبكة — ونفسُ النمط داخل الغلاف في `postVoidSale`.
          db.markTablesUpdated({
            db.salesInvoices,
            db.salesInvoiceItems,
            db.journalEntries,
            db.journalEntryLines,
            db.safeTransactions,
          });

          return jsonResponse({
            'success': true,
            'serverId': serverId,
            'exchangeKey': exchangeKey,
          });
        },
      );
    } catch (e, st) {
      debugPrint('[API] postSalesExchange error: $e\n$st');
      return ApiErrors.fail(e, 'Failed to process exchange');
    }
  }

  /// بنودُ فاتورةٍ من حمولةٍ خام — مشتركةٌ بين شقَّي الاستبدال كي لا تنزلق
  /// نسختان من التحويل (‏`quantityInBase` وحدَه أسقط استعادةَ المخزون مرّةً
  /// حين غاب — اقرأ SAL-2 في [postSalesReturn]).
  Future<List<SalesInvoiceItemsCompanion>> _parseExchangeItems(
    List<dynamic> rawItems,
    String label,
  ) async {
    final items = <SalesInvoiceItemsCompanion>[];
    for (final item in rawItems) {
      final m = (item as Map).cast<String, dynamic>();
      final resolvedProductId = await resolveProductId(
        clientProductId: parseIntNullable(m['productId']),
        productGlobalId: m['productGlobalId'] as String?,
        fallbackCode: m['productCode'] as String?,
        fallbackName: m['productName'] as String?,
      );
      if (resolvedProductId == null) {
        throw Exception(
            'Validation Error: $label item missing productId/productGlobalId');
      }
      items.add(SalesInvoiceItemsCompanion(
        productId: Value(resolvedProductId),
        quantity: Value(parseDouble(m['quantity'])),
        unitPrice: Value(parseDouble(m['unitPrice'])),
        discount: Value(parseDoubleNullable(m['discount']) ?? 0.0),
        total: Value(parseDouble(m['total'])),
        costPrice: Value(parseDoubleNullable(m['costPrice']) ?? 0.0),
        quantityInBase: Value(parseDoubleNullable(m['quantityInBase']) ?? 1.0),
        taxRate: Value(parseDoubleNullable(m['taxRate']) ?? 0.0),
        taxAmount: Value(parseDoubleNullable(m['taxAmount']) ?? 0.0),
      ));
    }
    return items;
  }

  /// شقُّ مردودٍ واحدٌ — يُنادى **داخل** معاملة [postSalesExchange].
  Future<int> _applyExchangeReturnLeg(
    Map<String, dynamic> leg, {
    required SalesInvoiceData? original,
    required int fallbackOriginalId,
    required String exchangeKey,
  }) async {
    final rawItems = (leg['items'] as List?) ?? const <dynamic>[];
    final items = await _parseExchangeItems(rawItems, 'exchange return');

    final clientWarehouseId = parseInt(leg['warehouseId']);
    if (clientWarehouseId == 0) {
      throw Exception('Validation Error: exchange return needs warehouseId');
    }
    final clientBranchId = parseIntNullable(leg['branchId']);
    final resolvedWarehouseId =
        await _resolveWarehouseId(clientWarehouseId, branchId: clientBranchId);
    final clientUserId = parseInt(leg['userId']);
    if (clientUserId == 0) {
      throw Exception('Validation Error: exchange return needs userId');
    }
    final resolvedUserId = await _resolveUserId(clientUserId,
        fallbackUsername: leg['createdByUsername'] as String?);
    final resolvedCustomerId = await resolvePartyId(
      clientPartyId: parseIntNullable(leg['customerId']),
      partyGlobalId: leg['customerGlobalId'] as String?,
      isCustomer: true,
    );

    final linkedOriginalId = original?.id ?? fallbackOriginalId;
    final returnId = await db.createSalesInvoice(
      invoiceNumber: leg['invoiceNumber'] as String?,
      customerId: resolvedCustomerId,
      warehouseId: resolvedWarehouseId,
      userId: resolvedUserId,
      subtotal: (parseDoubleNullable(leg['subtotal']))?.toDouble() ?? 0,
      discount: (parseDoubleNullable(leg['discount']))?.toDouble() ?? 0,
      tax: (parseDoubleNullable(leg['tax']))?.toDouble() ?? 0,
      total: (parseDoubleNullable(leg['total']))?.toDouble() ?? 0,
      paid: (parseDoubleNullable(leg['paid']))?.toDouble() ?? 0,
      paymentMethod: leg['paymentMethod'] as String? ?? 'cash',
      saleType: 'return',
      // الوسمان معاً: [localReturnLinkNote] يُبقي
      // `getReturnedAmountsForInvoices` عاملةً كما هي، و[exchangeLinkTag]
      // يربط المستندَ باستبداله. وحذفُ الأوّل كان سيُخفي المردودَ عن
      // «المتبقّي» على الخادم.
      notes: '${localReturnLinkNote(linkedOriginalId, originalGlobalId: original?.globalId)}'
          '${exchangeLinkTag(exchangeKey)}',
      items: items,
      globalId: leg['globalId'] as String?,
    );

    // عكسُ استهلاك BOM — بلا `try/catch` هنا عن قصد: نحن داخل معاملةٍ لم
    // يُودَع منها شيءٌ بعد، فالسقوطُ يُرجِع الاستبدالَ كلَّه بدل أن يترك
    // مردوداً بمخزونٍ خامٍ لم يعُد.
    if (original != null) {
      final originalItems = await (db.select(db.salesInvoiceItems)
            ..where((i) => i.invoiceId.equals(original.id)))
          .get();
      final origByProduct = <int, SalesInvoiceItem>{};
      for (final oi in originalItems) {
        origByProduct[oi.productId] = oi;
      }
      final fractionByOriginalItemId = <int, double>{};
      for (final ri in rawItems) {
        final m = (ri as Map).cast<String, dynamic>();
        final pid = parseIntNullable(m['productId']);
        final qty = parseDouble(m['quantity']);
        if (pid == null || qty <= 0) continue;
        final origItem = origByProduct[pid];
        if (origItem == null || origItem.quantity <= 0) continue;
        fractionByOriginalItemId[origItem.id] =
            (qty / origItem.quantity).clamp(0.0, 1.0).toDouble();
      }
      if (fractionByOriginalItemId.isNotEmpty) {
        await db.reverseSaleConsumption(
          saleInvoiceId: original.id,
          salesReturnId: returnId,
          itemReturnFractions: fractionByOriginalItemId,
        );
      }
    }
    await db.resignSalesInvoice(returnId);
    return returnId;
  }

  /// شقُّ البيع البديل — يُنادى **داخل** معاملة [postSalesExchange].
  Future<int> _applyExchangeSale(
    Map<String, dynamic> sale, {
    required String exchangeKey,
    required int returnDocumentId,
  }) async {
    final rawItems = (sale['items'] as List?) ?? const <dynamic>[];
    if (rawItems.isEmpty) {
      throw Exception('Validation Error: exchange sale has no items');
    }
    final items = await _parseExchangeItems(rawItems, 'exchange sale');

    final clientWarehouseId = parseInt(sale['warehouseId']);
    if (clientWarehouseId == 0) {
      throw Exception('Validation Error: exchange sale needs warehouseId');
    }
    final clientBranchId = parseIntNullable(sale['branchId']);
    final resolvedWarehouseId =
        await _resolveWarehouseId(clientWarehouseId, branchId: clientBranchId);
    final clientUserId = parseInt(sale['userId']);
    if (clientUserId == 0) {
      throw Exception('Validation Error: exchange sale needs userId');
    }
    final resolvedUserId = await _resolveUserId(clientUserId,
        fallbackUsername: sale['createdByUsername'] as String?);
    final resolvedCustomerId = await resolvePartyId(
      clientPartyId: parseIntNullable(sale['customerId']),
      partyGlobalId: sale['customerGlobalId'] as String?,
      isCustomer: true,
    );
    final clientCostCenterId = parseIntNullable(sale['costCenterId']);
    final saleGlobalId = sale['globalId'] as String?;

    final saleId = await db.createSalesInvoice(
      globalId: saleGlobalId,
      invoiceNumber: sale['invoiceNumber'] as String?,
      customerId: resolvedCustomerId,
      warehouseId: resolvedWarehouseId,
      userId: resolvedUserId,
      subtotal: (parseDoubleNullable(sale['subtotal']))?.toDouble() ?? 0,
      discount: (parseDoubleNullable(sale['discount']))?.toDouble() ?? 0,
      tax: (parseDoubleNullable(sale['tax']))?.toDouble() ?? 0,
      total: (parseDoubleNullable(sale['total']))?.toDouble() ?? 0,
      paid: (parseDoubleNullable(sale['paid']))?.toDouble() ?? 0,
      // نفسُ سببِ شقِّ البيع أعلاه — القيدُ يُعاد بناؤه من الحمولة.
      roundingAdjustment:
          (parseDoubleNullable(sale['roundingAdjustment']))?.toDouble() ?? 0,
      paymentMethod: sale['paymentMethod'] as String? ?? 'cash',
      saleType: sale['saleType'] as String? ?? 'default',
      notes: '${(sale['notes'] as String?)?.isNotEmpty == true ? sale['notes'] : 'استبدال'}'
          '${exchangeLinkTag(exchangeKey)}'
          '${exchangeReturnTag(returnDocumentId)}',
      items: items,
      cashAmount: (parseDoubleNullable(sale['cashAmount']))?.toDouble(),
      bankAmount: (parseDoubleNullable(sale['bankAmount']))?.toDouble(),
      clickAmount: (parseDoubleNullable(sale['clickAmount']))?.toDouble(),
      cashSafeId: parseIntNullable(sale['cashSafeId']),
      bankSafeId: parseIntNullable(sale['bankSafeId']),
      clickSafeId: parseIntNullable(sale['clickSafeId']),
      costCenterId: clientCostCenterId,
      branchId: clientBranchId,
    );

    // استنزافُ المكوّنات — نفسُ شرطِ [postSale] وسببِه: بلا `globalId` لا
    // هُويّةَ ثابتةً تُشتقّ منها معرِّفاتُ الاستهلاك.
    if (saleGlobalId != null && saleGlobalId.isNotEmpty) {
      final savedItems = await (db.select(db.salesInvoiceItems)
            ..where((it) => it.invoiceId.equals(saleId)))
          .get();
      final serverPolicy = await StockShortagePolicyService.resolveWith(
        get: db.getSettingValue,
        terminalId: null,
        branchId: clientBranchId,
      );
      await db.applyAutoDepleteForSale(
        saleInvoiceId: saleId,
        items: savedItems
            .map((it) => SaleLineRef(
                  saleItemId: it.id,
                  productId: it.productId,
                  // ⚠️ بوحدة الأساس — الموضعُ الثالثُ لنفس العطب (‏مسارُ
                  // الاستبدال). انظر `sales_transaction_orchestrator`.
                  qty: it.quantity *
                      (it.quantityInBase > 0 ? it.quantityInBase : 1.0),
                  warehouseId: resolvedWarehouseId,
                ))
            .toList(),
        branchId: clientBranchId,
        shortagePolicy: serverPolicy.wireName,
        saleGlobalId: saleGlobalId,
      );
    }

    // المحاسبة — بلا `try/catch`: فشلُها يُرجِع الاستبدالَ كلَّه.
    final createdInv = await db.getSalesInvoiceById(saleId);
    if (createdInv != null) {
      await db.autoPostCashSale(createdInv, costCenterId: clientCostCenterId);
    }
    await db.resignSalesInvoice(saleId);
    return saleId;
  }

  // ═══════════════════════════════════════════════════════════════
  // Held Orders
  // ═══════════════════════════════════════════════════════════════

  Future<Response> postHeldOrder(Request request) async {
    try {
      // Spec 077 Batch 1 (Spec 060 Phase 2): per-user permission gate.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.posHoldOrder);
      if (perm != null) return perm;

      final data =
          json.decode(await request.readAsString()) as Map<String, dynamic>;
      final rawItems = (data['items'] as List).cast<Map<String, dynamic>>();
      // Resolve each item's productId through globalId — client may be
      // referencing a product whose integer id drifted from server's.
      final resolvedItems = <Map<String, dynamic>>[];
      for (final m in rawItems) {
        final resolvedPid = await resolveProductId(
          clientProductId: parseIntNullable(m['productId']),
          productGlobalId: m['productGlobalId'] as String?,
          fallbackCode: m['productCode'] as String?,
          fallbackName: m['productName'] as String?,
        );
        if (resolvedPid == null) {
          throw Exception('Validation Error: held order item missing productId/productGlobalId');
        }
        resolvedItems.add({...m, 'productId': resolvedPid});
      }
      final id = await db.createHeldOrder(
        holdNumber: data['holdNumber'] as String,
        subtotal: (parseDouble(data['subtotal'])).toDouble(),
        discount: (parseDoubleNullable(data['discount']))?.toDouble() ?? 0,
  // ignore: dead_code
        discountIsPercent: parseBool(data['discountIsPercent']) ?? true,
        customerId: parseIntNullable(data['customerId']),
        customerName: data['customerName'] as String?,
        items: resolvedItems,
      );
      broadcast('held_orders');
      return jsonResponse({'success': true, 'serverId': id});
    } catch (e) {
      debugPrint('[API] postHeldOrder error: $e');
      return ApiErrors.fail(e, 'Failed to hold order');
    }
  }

  Future<Response> deleteHeldOrder(Request request, String id) async {
    try {
      // Spec 077 Batch 1 (Spec 060 Phase 2): per-user permission gate.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.posDeleteHeld);
      if (perm != null) return perm;

      final orderId = int.parse(id);
      await db.deleteHeldOrder(orderId);
      broadcast('held_orders');
      broadcastRecordDeleted('held_orders', orderId);
      return jsonResponse({'success': true});
    } catch (e) {
      return ApiErrors.fail(e, 'Failed to delete held order');
    }
  }

  Future<Response> deleteSalesInvoice(Request request, String id) async {
    try {
      // 060 (D1-001): per-user permission gate (settings-flag gated).
      final perm = await ApiUserCtx.requirePermission(
        request, db, PermissionCodes.salesDelete);
      if (perm != null) return perm;

      final invoiceId = int.parse(id);
      await db.deleteSalesInvoice(invoiceId);
      broadcast('sales');
      broadcastRecordDeleted('sales_invoices', invoiceId);
      return jsonResponse({'success': true});
    } on PermissionDeniedException catch (e) {
      // A permission denial is 403 Forbidden, not 500. The Spec 062
      // paid-invoice void gate throws this when the caller lacks
      // voidPaidInvoice; returning a 500 mislabels an authorization refusal
      // as a server error and hides the real cause from the client.
      return errorResponse(e.message, statusCode: 403);
    } catch (e) {
      return ApiErrors.fail(e, 'Failed to delete sales invoice');
    }
  }

  /// POST /api/sales/void — C-02 (Spec 151), R4/R9.
  ///
  /// Client/mirror-submitted sales-invoice void. Client mode no longer runs the
  /// full local stock/treasury/JE reversal itself (that was the bug: it wrote
  /// everything LOCALLY, never told the server, and the next DeltaPull
  /// re-asserted the still-active invoice from HQ). The committee-BLOCKED
  /// interim (`DELETE /api/sales/<id>` with the LOCAL id) could void a DIFFERENT
  /// invoice at HQ because client/server ids diverge. This endpoint resolves the
  /// invoice by globalId → invoiceNumber → id and performs the authoritative
  /// void; the mirror's next DeltaPull reconciles. Resolution + idempotency
  /// mirror [ApiPurchaseHandler.postVoidPurchase].
  Future<Response> postVoidSale(Request request) async {
    try {
      // Same permission the DELETE /api/sales/<id> route requires (delete==void
      // server-side). The finer-grained "void a fully-paid invoice" critical-op
      // gate (voidPaidInvoice) is enforced inside db.voidSalesInvoice itself and
      // surfaces as a PermissionDeniedException below.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.salesDelete);
      if (perm != null) return perm;

      return await ApiHandlerBase.withBroadcast<Response>(
        endpointLabel: 'postVoidSale',
        tables: const {
          'sales_invoices', 'sales_invoice_items',
          'inventory', 'stock_movements',
          'safe_transactions',
          'parties', 'accounting', 'journal_entries',
        },
        body: () async {
          final data =
              json.decode(await request.readAsString()) as Map<String, dynamic>;
          final salesId = parseInt(data['salesId']);
          final salesGlobalId = data['salesGlobalId'] as String?;
          final invoiceNumber = data['invoiceNumber'] as String?;
          final reason = data['reason'] as String?;
          // R9 — the SAME globalId the client threaded into the local
          // reversal-JE derivation (see sales_repository_impl.dart) must land on
          // the server's reversal JE too, so both sides converge to one JE row
          // instead of surviving DeltaPull as two.
          final voidGlobalId = data['globalId'] as String?;

          unawaited(DiagnosticLogger.log('API-SALE-VOID',
              'POST /api/sales/void received '
              'invoiceNumber=$invoiceNumber salesId=$salesId '
              'salesGlobalId=$salesGlobalId voidGlobalId=$voidGlobalId'));

          // Resolution chain: globalId (deterministic) → invoiceNumber → id
          // (legacy). Client/server ids diverge routinely; globalId is the only
          // stable key. No isDeleted filter here — an already-voided invoice
          // must still resolve so the idempotency short-circuit can fire.
          var lookup = (salesGlobalId != null && salesGlobalId.isNotEmpty)
              ? await (db.select(db.salesInvoices)
                    ..where((s) => s.globalId.equals(salesGlobalId)))
                  .getSingleOrNull()
              : null;
          if (lookup == null && invoiceNumber != null && invoiceNumber.isNotEmpty) {
            lookup = await (db.select(db.salesInvoices)
                  ..where((s) => s.invoiceNumber.equals(invoiceNumber)))
                .getSingleOrNull();
          }
          lookup ??= await (db.select(db.salesInvoices)
                ..where((s) => s.id.equals(salesId)))
              .getSingleOrNull();
          if (lookup == null) {
            return errorResponse(
              'Sales invoice not found (id=$salesId, globalId=$salesGlobalId, num=$invoiceNumber)',
              statusCode: 404,
            );
          }
          final invoice = lookup;

          // Idempotency: a re-submitted void (outbox replay after a
          // timeout-without-response, or a WriteRouter retry) must NOT
          // re-reverse stock/treasury/GL a second time. voidSalesInvoice itself
          // throws "الفاتورة ملغية بالفعل" on a second call — short-circuit
          // BEFORE calling it so the retry sees a success response, not an error
          // (same contract as postVoidPurchase).
          if (invoice.status == 'voided') {
            unawaited(DiagnosticLogger.log('API-SALE-VOID',
                '⚠ already voided invoice=${invoice.invoiceNumber} → idempotent return'));
            return jsonResponse({
              'success': true,
              'serverId': invoice.id,
              'idempotent': true,
            });
          }

          // ── الفاعلُ من الجلسة لا من الجسم ────────────────────────────────
          // `voidSalesInvoice` يجعل `deletedBy` **موضوعَ** فحصِ
          // `voidPaidInvoice` (‏sales_actions_dao — من العمليّات الحرجة
          // المستثناة عمداً من تجاوز المدير). فقراءةُ `data['userId']` كانت
          // تجعل المستدعيَ يختار من تُفحَص صلاحيّتُه: كاشيرٌ يرسل رقمَ مديرٍ
          // فيُبطل فاتورةً مدفوعةً كاملاً — ويُنسَب الإبطالُ لمن لم يلمسه.
          // النمطُ منسوخٌ من `api_purchase_handler` (‏نداءُ `putPurchase`)
          // وهو الموضعُ الوحيدُ الذي كان يفعلها صواباً.
          final sessionUserId = ApiUserCtx.userIdOf(request);
          final rawUserId = parseIntNullable(data['userId']);
          if (rawUserId != null &&
              sessionUserId != null &&
              rawUserId != sessionUserId) {
            unawaited(DiagnosticLogger.log(
                'API-SALE-VOID',
                '⛔ رفض تعارضِ هويّة: الجسم يدّعي #$rawUserId '
                    'والجلسة #$sessionUserId — invoice=${invoice.invoiceNumber}'));
            return Response(
              403,
              body: jsonEncode({
                'error': 'هويّةُ الجسم تخالف هويّةَ الجلسة — الطلب مرفوض',
              }),
              headers: const {'content-type': 'application/json'},
            );
          }

          await db.voidSalesInvoice(
            invoice.id,
            reason: reason,
            deletedBy: sessionUserId,
            globalId: voidGlobalId,
          );

          db.markTablesUpdated({db.salesInvoices});

          unawaited(DiagnosticLogger.log('API-SALE-VOID',
              '✓ voided invoice=${invoice.invoiceNumber} serverId=${invoice.id}'));

          return jsonResponse({'success': true, 'serverId': invoice.id});
        },
      );
    } on PermissionDeniedException catch (e) {
      // Symmetric with deleteSalesInvoice: a permission denial is 403, not 500.
      return errorResponse(e.message, statusCode: 403);
    } catch (e, st) {
      debugPrint('[API] postVoidSale error: $e\n$st');
      final stackLines = st.toString().split('\n').take(10).join(' | ');
      unawaited(DiagnosticLogger.log('API-SALE-VOID',
          '❌ error: $e\nstack: $stackLines'));
      return ApiErrors.fail(e, 'Failed to void sale', st: st);
    }
  }

  /// Spec 151 C-05 — client/mirror customer-COLLECTION submit (R4/R8/R9), the
  /// exact TWIN of ApiPurchaseHandler.postPurchasePayment. The server (SSoT)
  /// resolves the invoice (globalId → invoiceNumber → id), advances
  /// invoice.paid and posts the authoritative Dr Safe / Cr Customer receipt +
  /// balanced JE + safe move via db.addSalesPayment (which reuses the receipt
  /// path). A collection is ADDITIVE, so addSalesPayment dedups on the caller's
  /// per-event globalId — an outbox replay / WriteRouter retry carrying the same
  /// id applies it exactly once.
  Future<Response> postSalesPayment(Request request) async {
    try {
      // A collection advances the invoice's paid/status — same authority as an
      // edit. salesEdit mirrors the intent of the purchase side's purchasesEdit
      // gate; the money leg is separately covered because addSalesPayment posts
      // the receipt voucher server-side (treasury_receipts_create semantics).
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.salesEdit);
      if (perm != null) return perm;

      return await ApiHandlerBase.withBroadcast<Response>(
        endpointLabel: 'postSalesPayment',
        tables: const {
          'sales_invoices',
          'safe_transactions',
          'parties', 'accounting', 'journal_entries',
        },
        body: () async {
          final data =
              json.decode(await request.readAsString()) as Map<String, dynamic>;
          final salesId = parseInt(data['salesId']);
          final salesGlobalId = data['salesGlobalId'] as String?;
          final invoiceNumber = data['invoiceNumber'] as String?;
          final amount = parseDouble(data['amount']);
           final paymentRate = parseDoubleNullable(data['paymentRate'] ?? data['payment_rate']);
           final foreignAmount = parseDoubleNullable(data['foreignAmount'] ?? data['foreign_amount']);
          // R9 — the SAME deterministic per-event id the client stamped on the
          // local collection context. addSalesPayment dedups on it.
          final paymentGlobalId = data['globalId'] as String?;

          if (amount <= 0) {
            return errorResponse('Invalid collection amount: $amount', statusCode: 400);
          }

          unawaited(DiagnosticLogger.log('API-SALE-PAYMENT',
              'POST /api/sales/payment received '
              'invoiceNumber=$invoiceNumber salesId=$salesId '
              'salesGlobalId=$salesGlobalId amount=$amount '
              'globalId=$paymentGlobalId'));

          // Same resolution chain as postVoidSale: globalId (deterministic) →
          // invoiceNumber → id (legacy). Client/server ids diverge routinely.
          var lookup = (salesGlobalId != null && salesGlobalId.isNotEmpty)
              ? await (db.select(db.salesInvoices)
                    ..where((s) => s.globalId.equals(salesGlobalId)))
                  .getSingleOrNull()
              : null;
          if (lookup == null && invoiceNumber != null && invoiceNumber.isNotEmpty) {
            lookup = await (db.select(db.salesInvoices)
                  ..where((s) => s.invoiceNumber.equals(invoiceNumber)))
                .getSingleOrNull();
          }
          lookup ??= await (db.select(db.salesInvoices)
                ..where((s) => s.id.equals(salesId)))
              .getSingleOrNull();
          if (lookup == null) {
            return errorResponse(
              'Sales invoice not found (id=$salesId, globalId=$salesGlobalId, num=$invoiceNumber)',
              statusCode: 404,
            );
          }
          final invoice = lookup;

          int? resolvedUserId;
          final rawUserId = parseIntNullable(data['userId']);
          if (rawUserId != null) {
            resolvedUserId = await _resolveUserId(
              rawUserId,
              fallbackUsername: data['createdByUsername'] as String?,
            );
          }

          // Advances paid + posts the balanced Dr Safe / Cr Customer JE + safe
          // move atomically (its own transaction); idempotent on paymentGlobalId.
          await db.addSalesPayment(
            invoiceId: invoice.id,
            amount: amount,
            userId: resolvedUserId,
            globalId: paymentGlobalId,
            paymentRate: paymentRate,
            foreignAmount: foreignAmount,
          );

          db.markTablesUpdated({db.salesInvoices, db.safeTransactions});

          unawaited(DiagnosticLogger.log('API-SALE-PAYMENT',
              '✓ collection applied invoice=${invoice.invoiceNumber} '
              'serverId=${invoice.id} amount=$amount'));

          return jsonResponse({'success': true, 'serverId': invoice.id});
        },
      );
    } on PermissionDeniedException catch (e) {
      return errorResponse(e.message, statusCode: 403);
    } catch (e, st) {
      debugPrint('[API] postSalesPayment error: $e\n$st');
      final stackLines = st.toString().split('\n').take(10).join(' | ');
      unawaited(DiagnosticLogger.log('API-SALE-PAYMENT',
          '❌ error: $e\nstack: $stackLines'));
      return ApiErrors.fail(e, 'Failed to record sales collection', st: st);
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // Helpers
  // ═══════════════════════════════════════════════════════════════

  Future<int> _resolveWarehouseId(int clientWarehouseId, {int? branchId}) async {
    // Only check if client's warehouseId exists on the server.
    // PIR-04: Do NOT fallback to default or first active warehouse.
    // If it doesn't exist, it means Global Mapping is broken.
    final existing = await (db.select(db.warehouses)
          ..where((w) => w.id.equals(clientWarehouseId)))
        .getSingleOrNull();
    if (existing == null) {
      throw Exception('Strict Mapping Violation: Warehouse ID $clientWarehouseId not found on server.');
    }
    // L4 (2026-04-28): Authorization check — when the client declares its
    // branch, ensure the warehouse it's writing to belongs to that branch.
    // Prevents a compromised cashier device from operating against another
    // branch's warehouse by guessing IDs. branch=null on the warehouse means
    // "shared/unassigned" so we don't block (legacy data + setup tolerance).
    if (branchId != null && existing.branchId != null && existing.branchId != branchId) {
      throw Exception(
        'Authorization Error: warehouse $clientWarehouseId belongs to branch '
        '${existing.branchId} but client declared branch $branchId. '
        'Cross-branch operation denied.',
      );
    }
    return clientWarehouseId;
  }

  /// Resolve a client-provided userId to a valid server userId.
  /// Primary: exact ID match. Fallback: username lookup (handles client/server
  /// auto-increment divergence when user was created in client mode).
  /// Resolve the client-provided user ID to a server-side user ID.
  ///
  /// Resolution order:
  ///   1. Exact ID match (most common)
  ///   2. Username fallback (for pre-sync offline-created users)
  ///   3. Admin fallback — DO NOT throw, so the invoice is still persisted
  ///
  /// Previously this method threw "Strict Mapping Violation" when nothing
  /// matched, which caused client-synced sales invoices to be LOST on the
  /// server. The invoice was failing with a 500 error, the client's outbox
  /// would retry forever, but the server never accepted them — leading to
  /// the symptom "sales invoices screen empty on server".
  ///
  /// Data integrity: attributing to admin is better than losing the whole
  /// invoice. A warning log lets operators discover and fix the mapping
  /// manually.
  Future<int> _resolveUserId(int clientUserId, {String? fallbackUsername, String? fallbackGlobalId}) async {
    final existing = await (db.select(db.users)
          ..where((u) => u.id.equals(clientUserId)))
        .getSingleOrNull();
    if (existing != null) return clientUserId;

    // P5 (Issue #6): Resolve by globalId FIRST when provided — more
    // deterministic than username (handles renamed users) and survives
    // username conflicts. Only after globalId fails do we fall back to
    // username, then admin.
    if (fallbackGlobalId != null && fallbackGlobalId.isNotEmpty) {
      final byGid = await (db.select(db.users)
            ..where((u) => u.globalId.equals(fallbackGlobalId))
            ..limit(1))
          .getSingleOrNull();
      if (byGid != null) {
        debugPrint('[API] _resolveUserId: ID $clientUserId not found — '
            'fell back to globalId "$fallbackGlobalId" → server ID ${byGid.id}');
        return byGid.id;
      }
    }

    // Username-based fallback: when client and server IDs diverge (e.g. user
    // was created offline), find the same user by username.
    if (fallbackUsername != null && fallbackUsername.isNotEmpty) {
      final byUsername = await (db.select(db.users)
            ..where((u) => u.username.equals(fallbackUsername)))
          .getSingleOrNull();
      if (byUsername != null) {
        debugPrint('[API] _resolveUserId: ID $clientUserId not found — '
            'fell back to username "$fallbackUsername" → server ID ${byUsername.id}');
        return byUsername.id;
      }
    }

    // Last-resort fallback: attribute the invoice to the first admin user
    // so it's STILL persisted. Throwing here would drop the invoice entirely.
    final admin = await (db.select(db.users)
          ..where((u) => u.username.equals('admin') & u.isActive.equals(true))
          ..limit(1))
        .getSingleOrNull();
    if (admin != null) {
      debugPrint('[API] ⚠ _resolveUserId: clientUserId=$clientUserId '
          '(username="$fallbackUsername") not found on server — '
          'attributing invoice to admin (id=${admin.id}) to preserve data');
      // ⚠️ أثرٌ **باقٍ** — انظر النظيرَ في `api_data_handler.dart`. الفاتورةُ
      // تُحفظ (وفقدُها أسوأ)، لكنها تُنسب لغير بائعها فيكذب تقريرُ «حسب
      // الكاشير» بلا أثرٍ يبقى بعد الإصدار. بلاغُ المالك 2026-08-14.
      unawaited(DiagnosticLogger.log(
          'USER-ATTRIBUTION',
          '⚠ فاتورةٌ أُسنِدت إلى admin(id=${admin.id}) لأن '
          'clientUserId=$clientUserId username="$fallbackUsername" '
          'غيرُ موجودٍ على السيرفر — تقاريرُ «حسب المستخدم» ستنسبها للمدير'));
      return admin.id;
    }

    // If even admin is missing, something is very wrong — throw as last resort.
    throw Exception('No valid user on server — cannot persist invoice. '
        'clientUserId=$clientUserId fallbackUsername=$fallbackUsername');
  }
}
