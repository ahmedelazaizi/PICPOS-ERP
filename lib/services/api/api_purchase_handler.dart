// ═══════════════════════════════════════════════════════════════════════════
// API PURCHASE HANDLER — CRUD for Purchases and Purchase Returns
// ═══════════════════════════════════════════════════════════════════════════
//
// Extracted from ApiDataHandler for maintainability (PIR C-01).

import '../../core/constants/payment_methods.dart';
import '../../domain/models/purchase_return_settlement.dart';
import '../../domain/models/import_purchase_plan.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shelf/shelf.dart';
import 'api_errors.dart';
import 'api_server_error_log.dart';
import 'package:drift/drift.dart';
import '../../core/logging/diagnostic_logger.dart';
import '../../core/permissions/permission_codes.dart';
import '../../core/utils/uuid_v7.dart';
import '../../data/database/database.dart';
import '../../domain/entities/accounting_entities.dart';
import '../offline_sync_worker.dart' show kDuplicateSupplierInvoiceNoCode;
import 'api_user_context.dart';
import 'api_handler_base.dart';

/// Handles purchase CRUD API endpoints.
class ApiPurchaseHandler extends ApiHandlerBase {
  ApiPurchaseHandler(super.db, super.wsClients);

  // ═══════════════════════════════════════════════════════════════
  // FK Resolution Helpers (Client SQLite IDs → Server PostgreSQL IDs)
  // ═══════════════════════════════════════════════════════════════

  /// Resolve a client-provided warehouseId to a valid server warehouseId.
  Future<int> _resolveWarehouseId(int clientWarehouseId, {int? branchId}) async {
    final existing = await (db.select(db.warehouses)
          ..where((w) => w.id.equals(clientWarehouseId)))
        .getSingleOrNull();
    if (existing == null) {
      throw Exception('Strict Mapping Violation: Warehouse ID $clientWarehouseId not found on server.');
    }
    // L4 (2026-04-28): Authorization check — when client declares its branch,
    // ensure the warehouse belongs to that branch. Prevents cross-branch
    // operations from a compromised cashier device.
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
  /// Resolve client-provided user ID to server-side ID with admin fallback.
  /// See `api_sales_handler.dart::_resolveUserId` for the full rationale —
  /// the short version: NEVER throw, always preserve the incoming record by
  /// attributing to admin as a last resort.
  Future<int> _resolveUserId(int clientUserId, {String? fallbackUsername}) async {
    final existing = await (db.select(db.users)
          ..where((u) => u.id.equals(clientUserId)))
        .getSingleOrNull();
    if (existing != null) return clientUserId;

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

    final admin = await (db.select(db.users)
          ..where((u) => u.username.equals('admin') & u.isActive.equals(true))
          ..limit(1))
        .getSingleOrNull();
    if (admin != null) {
      debugPrint('[API] ⚠ _resolveUserId: clientUserId=$clientUserId '
          '(username="$fallbackUsername") not found — attributing to admin '
          '(id=${admin.id}) to preserve data');
      return admin.id;
    }

    throw Exception('No valid user on server — cannot persist record. '
        'clientUserId=$clientUserId fallbackUsername=$fallbackUsername');
  }

  /// Resolve a nullable userId — returns null if input is null.
  Future<int?> _resolveUserIdNullable(int? clientUserId, {String? fallbackUsername}) async {
    if (clientUserId == null) return null;
    return _resolveUserId(clientUserId, fallbackUsername: fallbackUsername);
  }

  Future<void> _writeErrorLog(String op, Object e, StackTrace st) => writeServerErrorLog(op, e, st);

  // ═══════════════════════════════════════════════════════════════
  // Purchases
  // ═══════════════════════════════════════════════════════════════

  Future<Response> postPurchase(Request request) async {
    try {
      // Spec 077 Batch 4 (Spec 060 Phase 2): per-user permission gate.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.purchasesCreate);
      if (perm != null) return perm;

      // Feature 054 (v134): stale-cache invalidation + DiagnosticLogger
      // on every duplicate-return path. See api_handler_base.dart for
      // the verifier wiring and the supermarket field repro that
      // motivated the change.
      final idempotencyKey = request.headers['x-idempotency-key'] ?? request.headers['X-Idempotency-Key'];
      if (idempotencyKey != null) {
        final cached = await checkIdempotency(idempotencyKey,
            verifyExists: idempotencyVerifierFor('postPurchase'));
        if (cached != null) {
          await DiagnosticLogger.log('API-PURCHASE',
              '⚠ idempotency-hit: returning cached response key=$idempotencyKey '
              'cached_serverId=${cached['serverId']}');
          return jsonResponse(cached);
        }
      }

      final data =
          json.decode(await request.readAsString()) as Map<String, dynamic>;

      // UUID-First idempotency (Phase 1): short-circuit if the same
      // globalId is already persisted (outbox replay / network retry).
      final incomingPurchaseGid = data['globalId'] as String?;
      if (incomingPurchaseGid != null && incomingPurchaseGid.isNotEmpty) {
        final existingByGid = await (db.select(db.purchaseInvoices)
              ..where((p) => p.globalId.equals(incomingPurchaseGid))
              ..limit(1))
            .getSingleOrNull();
        if (existingByGid != null) {
          await DiagnosticLogger.log('API-PURCHASE',
              '⚠ duplicate-skip globalId=$incomingPurchaseGid → existing '
              'serverId=${existingByGid.id} (idempotent return)');
          return jsonResponse({
            'success': true,
            'serverId': existingByGid.id,
            'duplicate': true,
          });
        }
      }

      final rawItems = (data['items'] as List);
      final items = <PurchaseInvoiceItemsCompanion>[];
      for (final item in rawItems) {
        final m = item as Map<String, dynamic>;
        final rawExpiry = m['expiryDate'];
        final DateTime? expiryDate = rawExpiry is String && rawExpiry.isNotEmpty
            ? DateTime.tryParse(rawExpiry)
            : null;
        final resolvedProductId = await resolveProductId(
          clientProductId: parseIntNullable(m['productId']),
          productGlobalId: m['productGlobalId'] as String?,
          fallbackCode: m['productCode'] as String?,
          fallbackName: m['productName'] as String?,
        );
        if (resolvedProductId == null) {
          throw Exception('Validation Error: purchase item missing productId/productGlobalId');
        }
        // Feature 043 (Route B.1) — honour the per-item globalId minted on
        // the client. Both sides now store the line under the SAME UUID,
        // so DeltaPull's Tier-1 dedup catches the row on the mirror's
        // pull-back instead of inserting a duplicate. When the field is
        // absent (legacy clients or standalone server), `Value.absent()`
        // lets the DAO mint a fresh UUID — preserves the pre-043 contract
        // for callers that never threaded it.
        final lineGid = (m['globalId'] as String?)?.trim();
        items.add(PurchaseInvoiceItemsCompanion(
          productId: Value(resolvedProductId),
          quantity: Value(parseDouble(m['quantity'])),
          unitCost: Value(parseDouble(m['unitCost'])),
          total: Value(parseDouble(m['total'])),
          taxRate: Value(parseDouble(m['taxRate'])),
          taxAmount: Value(parseDouble(m['taxAmount'])),
          batchNumber: Value(m['batchNumber'] as String?),
          expiryDate: Value(expiryDate),
          unitName: Value(m['unitName'] as String?),
          quantityInBase: Value(parseDouble(m['quantityInBase'], 1.0)),
          // خصمُ السطر — يصل الخادمَ ويوزّعه `resolvePurchaseLineNets`.
          // وغيابُه من حمولةٍ قديمةٍ يعطي صفراً، وهو عينُ السلوك السابق.
          discount: Value(parseDouble(m['discount'])),
          globalId: (lineGid != null && lineGid.isNotEmpty)
              ? Value(lineGid)
              : const Value.absent(),
        ));
      }

      final clientWhId = parseInt(data['warehouseId']);
      if (clientWhId == 0) throw Exception('Validation Error: warehouseId is required.');
      final clientBranchIdPurchase = parseIntNullable(data['branchId']);
      final resolvedWhId = await _resolveWarehouseId(clientWhId, branchId: clientBranchIdPurchase);

      // Resolve supplier via globalId (auto-create placeholder if absent).
      // Purchases require a non-null supplierId so we must produce one even
      // when the client row never propagated via DeltaPush.
      final resolvedSupplierId = await resolvePartyId(
        clientPartyId: parseIntNullable(data['supplierId']),
        partyGlobalId: data['supplierGlobalId'] as String?,
        isSupplier: true,
        fallbackName: data['supplierName'] as String?,
      );
      if (resolvedSupplierId == null) {
        throw Exception('Validation Error: supplierId or supplierGlobalId is required.');
      }

      // ═══ المرحلة ٨ — وسمُ الاستيراد ولقطةُ عملته ═══
      //
      // 🔴 **والخادمُ هو مَن يكتبهما.** صفُّه هو المعتمَد، وسحبُ الدلتا
      //    يستبدل صفَّ العميل به. فعملةٌ ووسمٌ يُكتبان على العميل وحدَه
      //    يُمحيان عند أوّل سحب، فتُقرأ فاتورةُ الدولار محلّيّةً وتختفي
      //    من شاشة الاستيراد — بلا أثرٍ يقول إنّ شيئاً ضاع.
      ImportDocumentFields? importDetails;
      final rawImport = data['importDetails'];
      if (rawImport is Map) {
        // وكيلُ التخليص يُحلّ بمعرِّفه العالميِّ لا برقمه المحلّيّ: رقمُ
        // العميل قد يُطابِق طرفاً آخرَ تماماً هنا.
        final agentId = await resolvePartyId(
          clientPartyId: null,
          partyGlobalId: data['clearingAgentGlobalId'] as String?,
          isSupplier: true,
          fallbackName: data['clearingAgentName'] as String?,
        );
        // ⚠️ **واسمُ الوكيل لا يضيع حين يتعذّر حلُّ الطرف.** التطبيعُ
        //    يُسقط النصَّ متى وُجد معرِّفُ طرفٍ، فحمولةُ `importDetails`
        //    تصل بلا اسم. ولو لم يُحَلَّ المعرِّفُ هنا (طرفٌ لم يُزامَن
        //    بعدُ) كان الوكيلُ يُمحى من الوسم بلا أثر — فالاسمُ يُعاد من
        //    المستوى الأعلى كبديلٍ حين لا طرفَ.
        final doc = Map<String, dynamic>.from(rawImport);
        if (agentId == null && doc['clearingAgentName'] == null) {
          doc['clearingAgentName'] = data['clearingAgentName'];
        }
        importDetails = importDocumentFromJson(
          doc,
          clearingAgentPartyId: agentId,
        );
      }

      // WH-001: the order is named by GLOBAL id and consumed in this transaction.
      int? sourceOrderId;
      final sourceGid = (data['sourceOrderGlobalId'] as String?)?.trim();
      if (sourceGid != null && sourceGid.isNotEmpty) {
        final po = await db.getPurchaseOrderByGlobalId(sourceGid);
        if (po == null) {
          throw PurchaseOrderNotConsumable('po_not_found', 'أمر الشراء المصدر غير موجود على الخادم');
        }
        sourceOrderId = po.id;
      }

      final serverId = await db.createPurchaseInvoice(
        supplierId: resolvedSupplierId,
        warehouseId: resolvedWhId,
        items: items,
        paid: parseDoubleNullable(data['paid']) ?? 0,
        paymentMethod: data['paymentMethod'] as String? ?? 'cash',
        supplierInvoiceNumber: data['supplierInvoiceNumber'] as String?,
        notes: data['notes'] as String?,
        globalId: incomingPurchaseGid, // UUID-First
        // ح-1: without this the server stored the GROSS total for a discounted
        // client invoice, so the supplier kept a payable for the discount that
        // could never be settled.
        discount: parseDoubleNullable(data['discount']) ?? 0,
        currencyId: parseIntNullable(data['currencyId']),
        exchangeRate: parseDoubleNullable(data['exchangeRate']),
        importDetails: importDetails,
        // J1b (v188): the client's chosen «حساب المشتريات»; absent ⇒ NULL ⇒
        // mapped default (older clients unchanged).
        purchaseAccountId: parseIntNullable(data['purchaseAccountId']),
        sourceOrderId: sourceOrderId,
      );
      broadcast('purchases');
      if (sourceOrderId != null) broadcast('purchase_orders');
      broadcast('products');
      // Spec 136 (field 2026-06-14): a cash purchase also creates a PAYMENT
      // safe_transaction (party_id=supplier), the purchase JEs, adjusts the
      // supplier's party balance, and moves stock — but postPurchase only
      // broadcast purchases+products, so the mirror pulled the invoice and NOT
      // the payment voucher → the supplier statement showed the purchase but
      // not its cash payment (field-confirmed: PMT vouchers missing on mirror).
      // Broadcast the affected tables so the mirror's DeltaPull fetches them.
      broadcast('safe_transactions');
      broadcast('journal_entries');
      broadcast('accounting');
      broadcast('parties');
      broadcast('inventory');
      broadcast('stock_movements');
      // Force Drift stream notifications for server-side UI refresh
      db.markTablesUpdated({db.purchaseInvoices, db.safeTransactions});

      final responseBody = {'success': true, 'serverId': serverId, 'idempotencyKey': idempotencyKey};
      if (idempotencyKey != null) {
        await storeIdempotency(idempotencyKey, responseBody, actionType: 'postPurchase');
      }
      return jsonResponse(responseBody);
    } on PurchaseOrderNotConsumable catch (e) {
      return Response(409, // WH-001: final for an outbox replay
          body: json.encode({'error': e.code, 'message': e.message}),
          headers: {'Content-Type': 'application/json'});
    } on StateError catch (e, st) {
      // البند 5 (2026-07-25): a duplicate supplier-invoice-number is a BUSINESS
      // conflict, not a server fault. Returning 500 made the outbox retry it
      // forever; 409 lets the worker park it and surface an actionable message.
      //
      // This sits after the globalId short-circuit above, so a legitimate
      // outbox replay of an already-persisted invoice returns 200/duplicate and
      // never reaches here.
      final msg = e.message;
      if (msg.contains('رقم فاتورة المورد')) {
        debugPrint('[API] postPurchase conflict: $msg');
        // Prefix with the stable machine token so OfflineSyncWorker classifies
        // this as a TERMINAL business conflict (dead-letter + notify) rather
        // than the benign "row already exists" 409 it folds into success.
        return errorResponse('$kDuplicateSupplierInvoiceNoCode: $msg',
            statusCode: 409);
      }
      debugPrint('[API] postPurchase error: $e\n$st');
      await _writeErrorLog('postPurchase', e, st);
      return ApiErrors.fail(e, 'Failed to create purchase');
    } catch (e, st) {
      debugPrint('[API] postPurchase error: $e\n$st');
      await _writeErrorLog('postPurchase', e, st);
      return ApiErrors.fail(e, 'Failed to create purchase');
    }
  }

  /// POST /api/purchases/return — Process a purchase return from a client node.
  /// The server performs the full processing (WAC reversal, stock adjustment,
  /// supplier balance, treasury, accounting) since the client only caches locally.
  Future<Response> postPurchaseReturn(Request request) async {
    try {
      // Spec 077 Batch 4 (Spec 060 Phase 2): per-user permission gate.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.purchasesReturnCreate);
      if (perm != null) return perm;

      return await ApiHandlerBase.withBroadcast<Response>(
        endpointLabel: 'postPurchaseReturn',
        tables: const {
          'purchase_invoices', 'purchase_invoice_items',
          'inventory', 'stock_movements',
          'safe_transactions',
          'parties', 'accounting', 'journal_entries',
        },
        body: () async {
      final data = json.decode(await request.readAsString()) as Map<String, dynamic>;
      unawaited(DiagnosticLogger.log('API-PURCHASE-RETURN',
          'POST /api/purchases/return received '
          'invoiceNumber=${data['invoiceNumber']} '
          'purchaseId=${data['purchaseId']} '
          'totalReturn=${data['totalReturn']} '
          'items=${(data['items'] as List?)?.length ?? 0}'));
      final purchaseId = parseInt(data['purchaseId']);
      final purchaseGlobalId = data['purchaseGlobalId'] as String?;
      final invoiceNumber = data['invoiceNumber'] as String?;
      // سببُ المردود من جهاز العميل — غيابُه مسموحٌ (مساراتٌ أقدم
      // ومنادون آخرون)، والواجهةُ هي التي تفرضه إلزاماً.
      final returnReason = data['reason'] as String?;
      final items = (data['items'] as List).cast<Map<String, dynamic>>();
      final totalReturn = parseDouble(data['totalReturn']);

      // Look up the original purchase invoice on the server.
      // Resolution order: globalId (deterministic) → invoiceNumber → id (legacy).
      // Client and server IDs often diverge — globalId is the only stable key.
      // (Type inferred via `var` to avoid importing the Drift row class.)
      var lookup = (purchaseGlobalId != null && purchaseGlobalId.isNotEmpty)
          ? await (db.select(db.purchaseInvoices)
                ..where((p) => p.globalId.equals(purchaseGlobalId)))
              .getSingleOrNull()
          : null;
      if (lookup == null && invoiceNumber != null && invoiceNumber.isNotEmpty) {
        lookup = await (db.select(db.purchaseInvoices)
              ..where((p) => p.invoiceNumber.equals(invoiceNumber)))
            .getSingleOrNull();
      }
      lookup ??= await (db.select(db.purchaseInvoices)
            ..where((p) => p.id.equals(purchaseId)))
          .getSingleOrNull();
      if (lookup == null) {
        return errorResponse(
          'Purchase invoice not found (id=$purchaseId, globalId=$purchaseGlobalId, num=$invoiceNumber)',
          statusCode: 404,
        );
      }
      // Re-bind to a final non-null name — Dart does not smart-cast `var`s
      // captured inside closures, and the transaction body below references
      // `invoice` heavily.
      final invoice = lookup;

      // FIX 2026-04-28: Idempotency check by globalId.
      // When the client retries submitPurchaseReturn (timeout-without-response),
      // each retry would re-reverse stock, re-update supplier balance, and
      // create duplicate journal/safe entries — the user would see the return
      // appear twice on the مرتجع المشتريات screen and the financial impact
      // would double. Block replay using the processed_messages table.
      final returnGlobalId = data['globalId'] as String?;
      if (returnGlobalId != null && returnGlobalId.isNotEmpty) {
        final alreadyProcessed = await (db.select(db.processedMessages)
          ..where((m) => m.idempotencyKey.equals(returnGlobalId))
          ..limit(1)
        ).getSingleOrNull();
        if (alreadyProcessed != null) {
          debugPrint('[API] postPurchaseReturn: globalId=$returnGlobalId already processed → idempotent return');
          return jsonResponse({
            'success': true,
            'serverId': invoice.id,
            'idempotent': true,
          });
        }
      }

      // Look up invoice items to get tax/original qty info
      final invoiceItems = await (db.select(db.purchaseInvoiceItems)
            ..where((i) => i.invoiceId.equals(purchaseId)))
          .get();
      final itemById = <int, PurchaseInvoiceItem>{
        for (final i in invoiceItems) i.productId: i,
      };

      // Build return items with full info
      // 066 (D5-001): generateInvoiceNumber must run inside the same txn as
      // the dependent inserts so the counter rolls back on failure.
      double totalVatReturn = 0;

      await db.transaction(() async {
        final returnVoucherNumber = await db.generateInvoiceNumber('PRET-');
        bool isFullReturn = true;

        for (final item in items) {
          debugPrint('[API:postPurchaseReturn] item raw=$item');
          final resolvedPid = await resolveProductId(
            clientProductId: parseIntNullable(item['productId']),
            productGlobalId: item['productGlobalId'] as String?,
            fallbackCode: item['productCode'] as String?,
            fallbackName: item['productName'] as String?,
          );
          final productId = resolvedPid ?? 0;
          if (productId == 0) {
            throw Exception('Validation Error: purchase return item missing productId/productGlobalId');
          }
          final returnQty = parseDouble(item['returnQuantity']);
          final unitCost = parseDouble(item['unitCost']);
          debugPrint('[API:postPurchaseReturn] step=parsed productId=$productId returnQty=$returnQty unitCost=$unitCost');
          if (returnQty <= 0) continue;

          final origItem = itemById[productId];
          final origQty = origItem?.quantity ?? returnQty;
          if (returnQty < origQty) isFullReturn = false;

          // VAT calculation
          final taxAmount = origItem?.taxAmount ?? 0.0;
          if (taxAmount > 0 && origQty > 0) {
            totalVatReturn += taxAmount * (returnQty / origQty);
          }

          // Reverse WAC
          debugPrint('[API:postPurchaseReturn] step=reverseProductWAC productId=$productId qty=$returnQty cost=$unitCost');
          await db.reverseProductWAC(
            productId: productId,
            reversedQuantity: returnQty,
            reversedUnitCost: unitCost,
          );

          // Reverse stock — pass unitCost so the movement records the original
          // invoice cost, not the current WAC (which would cause the returns-list
          // total to diverge from the per-item detail view).
          debugPrint('[API:postPurchaseReturn] step=adjustStock productId=$productId warehouseId=${invoice.warehouseId} qty=${-returnQty}');
          await db.adjustStock(
            productId: productId,
            warehouseId: invoice.warehouseId,
            quantity: -returnQty,
            type: 'purchase_return',
            referenceType: 'purchase_return',
            referenceId: invoice.id,
            unitCost: unitCost,
          );
        }

        // القسمةُ من الصيغة الواحدة — نفسُها في المستودع المحلّيّ وفي
        // مرآةِ الواجهة، فلا ينحرف خادمٌ عن عميلٍ بمقدارٍ واحد.
        final settlement = resolvePurchaseReturnSettlement(
          returnNet: totalReturn,
          returnVat: totalVatReturn,
          invoiceTotal: invoice.total,
          invoicePaid: invoice.paid,
        );
        final grossReturn = settlement.gross;
        final oldRemaining = settlement.remainingBefore;
        final balanceCorrection = settlement.apPortion;
        debugPrint('[API:postPurchaseReturn] step=balanceCalc gross=$grossReturn oldRemaining=$oldRemaining balanceCorrection=$balanceCorrection');
        if (balanceCorrection > 0) {
          debugPrint('[API:postPurchaseReturn] step=adjustPartyBalance supplierId=${invoice.supplierId} amount=${-balanceCorrection}');
          await db.adjustPartyBalance(invoice.supplierId, -balanceCorrection);

          // Mirror the local repo (purchases_repository_impl.dart): record a
          // memo row in safe_transactions so the supplier ledger shows the
          // unpaid-return AP adjustment. Without this, server-mode clients
          // see the supplier balance change but no line item explaining it,
          // and the ledger's opening-balance calculation (which subtracts
          // memos with category='purchase_return_balance') drifts.
          //
          // Direct INSERT (not createSafeTransaction): we must NOT mutate the
          // safe balance (no cash moved) nor re-adjust the supplier balance
          // (already done above).
          final balanceSafe = isBankPaymentMethod(invoice.paymentMethod)
              ? await db.getDefaultSafeByType('bank')
              : await db.getDefaultSafeByType('cash');
          if (balanceSafe != null) {
            // Cluster 028 / Bug 1: derive a deterministic globalId from the
            // purchase invoice's globalId so the mirror's local placeholder
            // (which derives the same value) deduplicates via Tier 1
            // (globalId match) when the mirror's DeltaPull reads this row.
            // Spec 136 ISS-7 — derive the memo gid from the per-return-event
            // id the client threaded (data['returnGlobalId']) so multiple
            // partial returns on one invoice get distinct, mirror↔server-
            // consistent memo globalIds. Older clients omit it → legacy
            // invoice-keyed form (unchanged behaviour for them).
            final memoReturnEventId = data['returnGlobalId'] as String?;
            final memoGlobalId =
                (invoice.globalId != null && invoice.globalId!.isNotEmpty)
                    ? UuidV7.deriveReturnMemoGlobalId(
                        invoiceGlobalId: invoice.globalId!,
                        returnType: 'purchase_return',
                        partyId: invoice.supplierId,
                        returnEventId: memoReturnEventId,
                      )
                    : UuidV7.generate();
            await db.into(db.safeTransactions).insert(
              SafeTransactionsCompanion.insert(
                voucherNumber: returnVoucherNumber,
                safeId: balanceSafe.id,
                transactionType: 'memo',
                category: 'purchase_return_balance',
                amount: balanceCorrection,
                balanceAfter: balanceSafe.balance,
                referenceType: const Value('purchase_return'),
                referenceId: Value(invoice.id),
                partyId: Value(invoice.supplierId),
                description: Value('تسوية رصيد مرتجع مشتريات فاتورة ${invoice.invoiceNumber}'),
                globalId: Value(memoGlobalId),
              ),
            );
          }
        }

        final cashReturnAmount = settlement.cashPortion;
        if (cashReturnAmount > 0) {
          final isBank = isBankPaymentMethod(invoice.paymentMethod);
          final safe = isBank
              ? await db.getDefaultSafeByType('bank')
              : await db.getDefaultSafeByType('cash');
          debugPrint('[API:postPurchaseReturn] step=safeLookup paymentMethod=${invoice.paymentMethod} safeId=${safe?.id} cashReturn=$cashReturnAmount');
          if (safe != null) {
            // ⚠️ لا كتابةَ رصيدٍ هنا: `createSafeTransaction('receipt')`
            // يزيد الرصيدَ بنفسه، فالكتابةُ قبله تُضيف المبلغَ مرّتين
            // (‏`treasury_dao.dart:1464-1469`). `newBalance` لقطةٌ لا أمر.
            final newBalance = safe.balance + cashReturnAmount;
            await db.createSafeTransaction(
              SafeTransactionsCompanion.insert(
                voucherNumber: returnVoucherNumber,
                safeId: safe.id,
                transactionType: 'receipt',
                category: 'purchase_return',
                amount: cashReturnAmount,
                balanceAfter: newBalance,
                referenceType: const Value('purchase_return'),
                referenceId: Value(invoice.id),
                partyId: Value(invoice.supplierId),
                description: Value('استرداد نقدي مرتجع مشتريات فاتورة ${invoice.invoiceNumber}'),
              ),
            );
          }
        }

        // Accounting entry
        // B8 (PRET-1): thread the return's own voucher number as the dedup
        // discriminator so two distinct partial returns of the same amount
        // on this invoice don't collide (see autoPostPurchaseReturn docstring).
        debugPrint('[API:postPurchaseReturn] step=autoPostPurchaseReturn returnAmount=$totalReturn vat=$totalVatReturn');
        // B9 (PRET-2): thread the AP/cash split computed above
        // (balanceCorrection = unpaid portion → Dr Payables; cashReturnAmount
        // = paid portion → Dr Cash) so the GL mirrors the actual supplier
        // balance / safe effect instead of lumping the whole refund onto a
        // single leg keyed only on paymentMethod.
        await db.autoPostPurchaseReturn(
          originalPurchase: invoice,
          reason: returnReason,
          returnAmount: totalReturn,
          vatAmount: totalVatReturn,
          costCenterId: invoice.costCenterId,
          returnEventId: returnVoucherNumber,
          apPortion: balanceCorrection,
          cashPortion: cashReturnAmount,
        );

        // Update invoice status
        debugPrint('[API:postPurchaseReturn] step=updateStatus invoiceId=${invoice.id} isFullReturn=$isFullReturn');
        await db.updatePurchaseInvoiceStatus(
          invoice.id,
          isFullReturn ? 'returned' : 'partial_return',
        );
        debugPrint('[API:postPurchaseReturn] ✓ transaction body complete');
      });

      db.markTablesUpdated({db.purchaseInvoices});

      // FIX 2026-04-28: Mark this globalId as processed so retries become
      // idempotent. Without this, a retry that arrived after the initial
      // success-but-network-failed would re-reverse stock again.
      if (returnGlobalId != null && returnGlobalId.isNotEmpty) {
        try {
          await db.into(db.processedMessages).insert(
            ProcessedMessagesCompanion.insert(
              idempotencyKey: returnGlobalId,
              responsePayload: '{"success":true,"serverId":${invoice.id}}',
              actionType: const Value('purchase_return'),
            ),
            // Bare `ON CONFLICT DO NOTHING` — drift drops `insertOrIgnore` on
            // postgres. The enclosing catch would swallow the resulting 23505,
            // but then the idempotency record is never written and the next
            // retry re-runs the whole return: re-reverses stock, re-posts the
            // JE, re-adjusts the supplier balance.
            onConflict: DoNothing(target: []),
          );
        } catch (e) {
          debugPrint('[API] postPurchaseReturn: idempotency record failed (non-fatal): $e');
        }
      }

      // FIX 2026-04-28: Return serverId so client's _tryOrQueueVoid can
      // capture it for FK remapping. Previous response was just {success:true}
      // which made ServerProxy.submitPurchaseReturn return null even on success
      // → the outbox would replay forever thinking the call had failed.
      return jsonResponse({'success': true, 'serverId': invoice.id});
        },
      );
    } catch (e, st) {
      // Spec 002 Round 3-6: include the stack trace in the server log AND in
      // the response so the client can see exactly where the type error
      // ("type 'String' is not a subtype of type 'num' of 'value'") came
      // from. Without this we only get the message and have to guess.
      debugPrint('[API] postPurchaseReturn error: $e\n$st');
      final stackLines = st.toString().split('\n').take(10).join(' | ');
      unawaited(DiagnosticLogger.log('API-PURCHASE-RETURN',
          '❌ error: $e\nstack: $stackLines'));
      return ApiErrors.fail(e, 'Failed to process purchase return', st: st);
    }
  }

  /// Feature 015 — POST /api/purchases/return/edit
  /// Atomically reverse the currently-posted purchase return for an invoice
  /// and re-post fresh values from [items]. Mirrors the local
  /// `editPurchaseReturn` orchestrator: period-lock gate, append-only
  /// reverse rows, then the standard create-return body.
  Future<Response> postPurchaseReturnEdit(Request request) async {
    try {
      // Spec 077 Batch 4 (Spec 060 Phase 2): per-user permission gate.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.purchasesReturnEdit);
      if (perm != null) return perm;

      return await ApiHandlerBase.withBroadcast<Response>(
        endpointLabel: 'postPurchaseReturnEdit',
        tables: const {
          'purchase_invoices', 'purchase_invoice_items',
          'inventory', 'stock_movements',
          'safe_transactions',
          'parties', 'accounting', 'journal_entries',
        },
        body: () async {
      final data = json.decode(await request.readAsString()) as Map<String, dynamic>;
      unawaited(DiagnosticLogger.log('API-PURCHASE-RETURN-EDIT',
          'POST /api/purchases/return/edit received '
          'invoiceNumber=${data['invoiceNumber']} '
          'purchaseId=${data['purchaseId']} '
          'totalReturn=${data['totalReturn']} '
          'items=${(data['items'] as List?)?.length ?? 0}'));
      final purchaseId = parseInt(data['purchaseId']);
      final purchaseGlobalId = data['purchaseGlobalId'] as String?;
      final invoiceNumber = data['invoiceNumber'] as String?;
      // سببُ المردود من جهاز العميل — غيابُه مسموحٌ (مساراتٌ أقدم
      // ومنادون آخرون)، والواجهةُ هي التي تفرضه إلزاماً.
      final returnReason = data['reason'] as String?;
      final items = (data['items'] as List).cast<Map<String, dynamic>>();
      final totalReturn = parseDouble(data['totalReturn']);

      // Same invoice resolution chain as postPurchaseReturn (globalId →
      // invoiceNumber → id) — globalId is the only stable cross-node key.
      var lookup = (purchaseGlobalId != null && purchaseGlobalId.isNotEmpty)
          ? await (db.select(db.purchaseInvoices)
                ..where((p) => p.globalId.equals(purchaseGlobalId)))
              .getSingleOrNull()
          : null;
      if (lookup == null && invoiceNumber != null && invoiceNumber.isNotEmpty) {
        lookup = await (db.select(db.purchaseInvoices)
              ..where((p) => p.invoiceNumber.equals(invoiceNumber)))
            .getSingleOrNull();
      }
      lookup ??= await (db.select(db.purchaseInvoices)
            ..where((p) => p.id.equals(purchaseId)))
          .getSingleOrNull();
      if (lookup == null) {
        return errorResponse(
          'Purchase invoice not found (id=$purchaseId, globalId=$purchaseGlobalId, num=$invoiceNumber)',
          statusCode: 404,
        );
      }
      final invoice = lookup;

      // Idempotency check by edit's globalId. A retry after a timeout-without-
      // response must NOT re-reverse + re-recreate (it would double the
      // compensating rows and corrupt the JE trail).
      final editGlobalId = data['globalId'] as String?;
      if (editGlobalId != null && editGlobalId.isNotEmpty) {
        final alreadyProcessed = await (db.select(db.processedMessages)
              ..where((m) => m.idempotencyKey.equals(editGlobalId))
              ..limit(1))
            .getSingleOrNull();
        if (alreadyProcessed != null) {
          debugPrint('[API] postPurchaseReturnEdit: globalId=$editGlobalId already processed → idempotent return');
          return jsonResponse({
            'success': true,
            'serverId': invoice.id,
            'idempotent': true,
          });
        }
      }

      // Period-lock gate (Feature 014). Server enforces independently of
      // the client so the policy stays consistent across both paths.
      final closed = await db.isDateInClosedPeriod(invoice.invoiceDate);
      if (closed) {
        return errorResponse(
          'لا يمكن تنفيذ مرتجع المشتريات — الفترة المحاسبية '
          '(${invoice.invoiceDate.toIso8601String().substring(0, 10)}) '
          'مقفلة. يرجى فتح الفترة من شاشة السنوات المالية إذا كان التعديل ضرورياً.',
          statusCode: 400,
        );
      }

      final invoiceItems = await (db.select(db.purchaseInvoiceItems)
            ..where((i) => i.invoiceId.equals(purchaseId)))
          .get();
      final itemByPid = <int, PurchaseInvoiceItem>{
        for (final i in invoiceItems) i.productId: i,
      };

      double totalVatReturn = 0;

      // 066 (D5-001): generateInvoiceNumber moved inside the txn so the
      // counter rolls back if any subsequent step fails.
      await db.transaction(() async {
        final returnVoucherNumber = await db.generateInvoiceNumber('PRET-');
        // Pre-pass: capture the current-net returned qty per product BEFORE
        // we insert any compensating rows (otherwise the same query during
        // the reverse step would sum to ~0).
        final currentReturnedByPid = <int, double>{};
        for (final origItem in invoiceItems) {
          final movements = await (db.select(db.stockMovements)
                ..where((m) =>
                    m.productId.equals(origItem.productId) &
                    m.referenceId.equalsNullable(invoice.id) &
                    (m.referenceType.equals('purchase_return') |
                        m.referenceType.equals('purchase_return_reverse'))))
              .get();
          double net = 0;
          for (final mv in movements) {
            net += mv.quantity;
          }
          currentReturnedByPid[origItem.productId] = -net;
        }

        // Old totals — must mirror exactly what the original postPurchaseReturn
        // computed when it first persisted the return.
        double oldTotalReturn = 0;
        double oldVatReturn = 0;
        for (final origItem in invoiceItems) {
          final qty = currentReturnedByPid[origItem.productId] ?? 0;
          if (qty <= 0.001) continue;
          oldTotalReturn += qty * origItem.unitCost;
          if (origItem.taxAmount > 0 && origItem.quantity > 0) {
            oldVatReturn += origItem.taxAmount * (qty / origItem.quantity);
          }
        }
        final oldSettlement = resolvePurchaseReturnSettlement(
          returnNet: oldTotalReturn,
          returnVat: oldVatReturn,
          invoiceTotal: invoice.total,
          invoicePaid: invoice.paid,
        );
  // ignore: unused_local_variable
        final oldGrossReturn = oldSettlement.gross;
        final oldBalanceCorrection = oldSettlement.apPortion;
        final oldCashReturn = oldSettlement.cashPortion;

        final reverseVoucher =
            'PRET-REV-${invoice.id}-${DateTime.now().millisecondsSinceEpoch}';

        // ── Step A: Reverse the current state (append-only) ──

        // A1: Stock + WAC (positive compensating movements + full WAC recalc).
        for (final origItem in invoiceItems) {
          final qty = currentReturnedByPid[origItem.productId] ?? 0;
          if (qty <= 0.001) continue;
          await db.adjustStock(
            productId: origItem.productId,
            warehouseId: invoice.warehouseId,
            quantity: qty,
            type: 'purchase_return_reverse',
            referenceType: 'purchase_return_reverse',
            referenceId: invoice.id,
            unitCost: origItem.unitCost,
          );
          await db.recalculateProductWAC(origItem.productId);
        }

        // A2: Restore supplier balance + compensating memo.
        if (oldBalanceCorrection > 0) {
          await db.adjustPartyBalance(invoice.supplierId, oldBalanceCorrection);
          final balanceSafe =
              isBankPaymentMethod(invoice.paymentMethod)
                  ? await db.getDefaultSafeByType('bank')
                  : await db.getDefaultSafeByType('cash');
          if (balanceSafe != null) {
            await db.into(db.safeTransactions).insert(
                  SafeTransactionsCompanion.insert(
                    voucherNumber: reverseVoucher,
                    safeId: balanceSafe.id,
                    transactionType: 'memo',
                    category: 'purchase_return_balance_reverse',
                    amount: oldBalanceCorrection,
                    balanceAfter: balanceSafe.balance,
                    referenceType: const Value('purchase_return_reverse'),
                    referenceId: Value(invoice.id),
                    partyId: Value(invoice.supplierId),
                    description: Value(
                      'إلغاء تسوية رصيد مرتجع مشتريات فاتورة '
                      '${invoice.invoiceNumber}',
                    ),
                  ),
                );
          }
        }

        // A3: Reverse cash refund — fail closed if the safe is below the
        //     un-refund amount (we never want to push the safe negative).
        if (oldCashReturn > 0) {
          final isBank =
              isBankPaymentMethod(invoice.paymentMethod);
          final safe = isBank
              ? await db.getDefaultSafeByType('bank')
              : await db.getDefaultSafeByType('cash');
          if (safe != null) {
            if (safe.balance + 0.001 < oldCashReturn) {
              throw Exception(
                'لا يمكن تعديل المرتجع — رصيد الخزنة (${safe.balance}) '
                'لا يكفي لاستعادة الاسترداد النقدي ($oldCashReturn). '
                'يرجى تعويض الخزنة قبل التعديل.',
              );
            }
            // H15 — استعادةُ الاسترداد القديم خصمٌ ذرّيّ. الصفُّ التالي
            // `into(...).insert` لا يمسّ الرصيد، فالخصمُ هنا وحدَه.
            final newBalance = safe.balance - oldCashReturn;
            await db.adjustSafeBalance(safe.id, -oldCashReturn);
            await db.into(db.safeTransactions).insert(
                  SafeTransactionsCompanion.insert(
                    voucherNumber: reverseVoucher,
                    safeId: safe.id,
                    transactionType: 'payment',
                    category: 'purchase_return_reverse',
                    amount: oldCashReturn,
                    balanceAfter: newBalance,
                    referenceType: const Value('purchase_return_reverse'),
                    referenceId: Value(invoice.id),
                    partyId: Value(invoice.supplierId),
                    description: Value(
                      'إلغاء استرداد نقدي مرتجع مشتريات فاتورة '
                      '${invoice.invoiceNumber}',
                    ),
                  ),
                );
          }
        }

        // A4: Reverse the JE trail. Spec 151 (F-04): autoPostPurchaseReturn now
        //     keys referenceId on the ORIGINATING invoice id — match by that id
        //     instead of a `description LIKE '%فاتورة {number}%'` scan that
        //     cross-reversed substring-colliding invoices (editing "12" also
        //     reversed "120"'s return JE and flipped its isAutoPosted). Then
        //     flip isAutoPosted=false on the originals so the recreate step's
        //     guard doesn't re-match them.
        //
        // §٦‑٢ — ويُبطَل مستندُ المرتجع مع قيده، كنظيره في
        // `purchases_repository_impl`. بلا هذا تقرأ تسويةُ ض.ق.م على الخادم
        // ضريبةَ مرتجعٍ أُلغي.
        await db.voidPurchaseReturnDocs(invoice.id);

        final originalEntries = await (db.select(db.journalEntries)
              ..where((e) =>
                  e.referenceType.equals('purchase_return') &
                  e.isAutoPosted.equals(true) &
                  e.referenceId.equalsNullable(invoice.id)))
            .get();
        for (final entry in originalEntries) {
          final lines = await (db.select(db.journalEntryLines)
                ..where((l) => l.entryId.equals(entry.id)))
              .get();
          final reverseLines = <JournalLine>[];
          for (final line in lines) {
            reverseLines.add(JournalLine(
              accountId: line.accountId,
              debit: line.credit,
              credit: line.debit,
              description: 'إلغاء — ${line.description ?? ''}',
            ));
          }
          if (reverseLines.isNotEmpty) {
            await db.createJournalEntry(
              description:
                  'إلغاء قيد مرتجع مشتريات فاتورة ${invoice.invoiceNumber}',
              date: DateTime.now(),
              lines: reverseLines,
              referenceType: 'purchase_return',
              referenceId: invoice.id,
              isAutoPosted: false,
              costCenterId: entry.costCenterId,
            );
          }
          await (db.update(db.journalEntries)
                ..where((e) => e.id.equals(entry.id)))
              .write(const JournalEntriesCompanion(
            isAutoPosted: Value(false),
          ));
        }

        await db.updatePurchaseInvoiceStatus(invoice.id, 'none');

        // ── Step B: Recreate the return with the new items
        //     (mirrors postPurchaseReturn's transaction body) ──
        bool isFullReturn = true;
        for (final item in items) {
          final resolvedPid = await resolveProductId(
            clientProductId: parseIntNullable(item['productId']),
            productGlobalId: item['productGlobalId'] as String?,
            fallbackCode: item['productCode'] as String?,
            fallbackName: item['productName'] as String?,
          );
          final productId = resolvedPid ?? 0;
          if (productId == 0) {
            throw Exception(
                'Validation Error: purchase return edit item missing productId/productGlobalId');
          }
          final returnQty = parseDouble(item['returnQuantity']);
          final unitCost = parseDouble(item['unitCost']);
          if (returnQty <= 0) continue;

          final origItem = itemByPid[productId];
          final origQty = origItem?.quantity ?? returnQty;
          if (returnQty < origQty) isFullReturn = false;

          final taxAmount = origItem?.taxAmount ?? 0.0;
          if (taxAmount > 0 && origQty > 0) {
            totalVatReturn += taxAmount * (returnQty / origQty);
          }

          await db.reverseProductWAC(
            productId: productId,
            reversedQuantity: returnQty,
            reversedUnitCost: unitCost,
          );
          await db.adjustStock(
            productId: productId,
            warehouseId: invoice.warehouseId,
            quantity: -returnQty,
            type: 'purchase_return',
            referenceType: 'purchase_return',
            referenceId: invoice.id,
            unitCost: unitCost,
          );
        }

        final newGross = totalReturn + totalVatReturn;
        final newRemaining = (invoice.total - invoice.paid)
            .clamp(0.0, double.infinity)
            .toDouble();
        final newBalanceCorrection = newRemaining > 0
            ? newGross.clamp(0.0, newRemaining).toDouble()
            : 0.0;
        if (newBalanceCorrection > 0) {
          await db.adjustPartyBalance(invoice.supplierId, -newBalanceCorrection);
          final balanceSafe =
              isBankPaymentMethod(invoice.paymentMethod)
                  ? await db.getDefaultSafeByType('bank')
                  : await db.getDefaultSafeByType('cash');
          if (balanceSafe != null) {
            await db.into(db.safeTransactions).insert(
                  SafeTransactionsCompanion.insert(
                    voucherNumber: returnVoucherNumber,
                    safeId: balanceSafe.id,
                    transactionType: 'memo',
                    category: 'purchase_return_balance',
                    amount: newBalanceCorrection,
                    balanceAfter: balanceSafe.balance,
                    referenceType: const Value('purchase_return'),
                    referenceId: Value(invoice.id),
                    partyId: Value(invoice.supplierId),
                    description: Value(
                      'تسوية رصيد مرتجع مشتريات فاتورة '
                      '${invoice.invoiceNumber}',
                    ),
                  ),
                );
          }
        }

        final newCashReturnAmount = newGross - newBalanceCorrection;
        if (newCashReturnAmount > 0) {
          final isBank =
              isBankPaymentMethod(invoice.paymentMethod);
          final safe = isBank
              ? await db.getDefaultSafeByType('bank')
              : await db.getDefaultSafeByType('cash');
          if (safe != null) {
            // نفسُ علّة `postPurchaseReturn` أعلاه: الدالّةُ تزيد الرصيدَ
            // بنفسها، فالكتابةُ قبلها تطبّق الاسترداد مرّتين.
            final newBalance = safe.balance + newCashReturnAmount;
            await db.createSafeTransaction(
              SafeTransactionsCompanion.insert(
                voucherNumber: returnVoucherNumber,
                safeId: safe.id,
                transactionType: 'receipt',
                category: 'purchase_return',
                amount: newCashReturnAmount,
                balanceAfter: newBalance,
                referenceType: const Value('purchase_return'),
                referenceId: Value(invoice.id),
                partyId: Value(invoice.supplierId),
                description: Value(
                  'استرداد نقدي مرتجع مشتريات فاتورة ${invoice.invoiceNumber}',
                ),
              ),
            );
          }
        }

        // B8 (PRET-1): thread the (edit's) return voucher number as the
        // dedup discriminator — see autoPostPurchaseReturn docstring.
        // B9 (PRET-2): thread the AP/cash split computed above (mirrors
        // postPurchaseReturn's split — see its comment for the reconciliation
        // rule) instead of lumping the whole refund onto a single leg.
        await db.autoPostPurchaseReturn(
          originalPurchase: invoice,
          reason: returnReason,
          returnAmount: totalReturn,
          vatAmount: totalVatReturn,
          costCenterId: invoice.costCenterId,
          returnEventId: returnVoucherNumber,
          apPortion: newBalanceCorrection,
          cashPortion: newCashReturnAmount,
        );

        await db.updatePurchaseInvoiceStatus(
          invoice.id,
          isFullReturn ? 'returned' : 'partial_return',
        );
      });

      db.markTablesUpdated({db.purchaseInvoices});

      if (editGlobalId != null && editGlobalId.isNotEmpty) {
        try {
          await db.into(db.processedMessages).insert(
                ProcessedMessagesCompanion.insert(
                  idempotencyKey: editGlobalId,
                  responsePayload:
                      '{"success":true,"serverId":${invoice.id}}',
                  actionType: const Value('purchase_return_edit'),
                ),
                // Same as the purchase_return site above: bare
                // `ON CONFLICT DO NOTHING`, because drift drops
                // `insertOrIgnore` on postgres.
                onConflict: DoNothing(target: []),
              );
        } catch (e) {
          debugPrint(
              '[API] postPurchaseReturnEdit: idempotency record failed (non-fatal): $e');
        }
      }

      return jsonResponse({'success': true, 'serverId': invoice.id});
        },
      );
    } catch (e, st) {
      debugPrint('[API] postPurchaseReturnEdit error: $e\n$st');
      final stackLines = st.toString().split('\n').take(10).join(' | ');
      unawaited(DiagnosticLogger.log('API-PURCHASE-RETURN-EDIT',
          '❌ error: $e\nstack: $stackLines'));
      return ApiErrors.fail(e, 'Failed to process purchase return edit', st: st);
    }
  }

  /// PR-2 (pre-deploy batch B6, R4/R8/R9) — POST /api/purchases/void
  ///
  /// Client/mirror-submitted purchase-invoice void. Client mode no longer
  /// runs the full local stock/AP/treasury/JE reversal itself (that was the
  /// bug: it wrote everything LOCALLY, never told the server, and the next
  /// DeltaPull re-asserted the still-active invoice from HQ, leaving
  /// orphaned local reversals). The server — the single source of truth —
  /// performs the authoritative void here; the mirror's next DeltaPull
  /// reconciles the result. Invoice resolution + idempotency mirror
  /// [postPurchaseReturn] above.
  Future<Response> postVoidPurchase(Request request) async {
    try {
      // Spec 062 (D1-004) reuses PermissionCodes.purchasesDelete at the route
      // gate — same permission the legacy DELETE /api/purchases/<id> route
      // requires. The finer-grained "void a fully-paid invoice" critical-op
      // gate (voidPaidInvoice) is enforced inside db.voidPurchaseInvoice
      // itself and surfaces as a PermissionDeniedException below.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.purchasesDelete);
      if (perm != null) return perm;

      return await ApiHandlerBase.withBroadcast<Response>(
        endpointLabel: 'postVoidPurchase',
        tables: const {
          'purchase_invoices', 'purchase_invoice_items',
          'inventory', 'stock_movements',
          'safe_transactions',
          'parties', 'accounting', 'journal_entries',
        },
        body: () async {
          final data =
              json.decode(await request.readAsString()) as Map<String, dynamic>;
          final purchaseId = parseInt(data['purchaseId']);
          final purchaseGlobalId = data['purchaseGlobalId'] as String?;
          final invoiceNumber = data['invoiceNumber'] as String?;
          final reason = data['reason'] as String?;
          // R9 — the SAME globalId the client threaded into the local
          // reversal-JE derivation (see purchases_repository_impl.dart)
          // must land on the server's reversal JE too, so both sides
          // converge to one JE row instead of surviving DeltaPull as two.
          final voidGlobalId = data['globalId'] as String?;

          unawaited(DiagnosticLogger.log('API-PURCHASE-VOID',
              'POST /api/purchases/void received '
              'invoiceNumber=$invoiceNumber purchaseId=$purchaseId '
              'purchaseGlobalId=$purchaseGlobalId voidGlobalId=$voidGlobalId'));

          // Same resolution chain as postPurchaseReturn: globalId
          // (deterministic) → invoiceNumber → id (legacy). Client/server
          // ids diverge routinely, globalId is the only stable key.
          var lookup = (purchaseGlobalId != null && purchaseGlobalId.isNotEmpty)
              ? await (db.select(db.purchaseInvoices)
                    ..where((p) => p.globalId.equals(purchaseGlobalId)))
                  .getSingleOrNull()
              : null;
          if (lookup == null && invoiceNumber != null && invoiceNumber.isNotEmpty) {
            lookup = await (db.select(db.purchaseInvoices)
                  ..where((p) => p.invoiceNumber.equals(invoiceNumber)))
                .getSingleOrNull();
          }
          lookup ??= await (db.select(db.purchaseInvoices)
                ..where((p) => p.id.equals(purchaseId)))
              .getSingleOrNull();
          if (lookup == null) {
            return errorResponse(
              'Purchase invoice not found (id=$purchaseId, globalId=$purchaseGlobalId, num=$invoiceNumber)',
              statusCode: 404,
            );
          }
          final invoice = lookup;

          // Idempotency: a re-submitted void (outbox replay after a
          // timeout-without-response, or a WriteRouter retry) must NOT
          // re-reverse stock/AP/treasury a second time. voidPurchaseInvoice
          // itself throws "الفاتورة ملغية بالفعل" on a second call — short-
          // circuit BEFORE calling it so the retry sees a success response,
          // not an error (same contract as postPurchaseReturn's
          // processedMessages check, adapted to void's single terminal
          // state instead of a re-derivable amount).
          if (invoice.status == 'voided') {
            unawaited(DiagnosticLogger.log('API-PURCHASE-VOID',
                '⚠ already voided invoice=${invoice.invoiceNumber} → idempotent return'));
            return jsonResponse({
              'success': true,
              'serverId': invoice.id,
              'idempotent': true,
            });
          }

          // ── الفاعلُ من الجلسة لا من الجسم ────────────────────────────────
          // توأمُ `postVoidSale`: `deletedBy` هو **موضوعُ** فحصِ
          // `voidPaidInvoice` في `purchase_dao`، فقراءتُه من الجسم تجعل
          // المستدعيَ يختار من تُفحَص صلاحيّتُه. ونفسُ النمط في
          // `putPurchase` أدناه منذ البداية.
          final sessionUserId = ApiUserCtx.userIdOf(request);
          final rawUserId = parseIntNullable(data['userId']);
          if (rawUserId != null &&
              sessionUserId != null &&
              rawUserId != sessionUserId) {
            unawaited(DiagnosticLogger.log(
                'API-PURCHASE-VOID',
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

          await db.voidPurchaseInvoice(
            invoice.id,
            reason: reason,
            deletedBy: sessionUserId,
            globalId: voidGlobalId,
          );

          db.markTablesUpdated({db.purchaseInvoices});

          unawaited(DiagnosticLogger.log('API-PURCHASE-VOID',
              '✓ voided invoice=${invoice.invoiceNumber} serverId=${invoice.id}'));

          return jsonResponse({'success': true, 'serverId': invoice.id});
        },
      );
    } on PermissionDeniedException catch (e) {
      // Symmetric with deletePurchase: a permission denial is 403, not 500.
      return errorResponse(e.message, statusCode: 403);
    } catch (e, st) {
      debugPrint('[API] postVoidPurchase error: $e\n$st');
      final stackLines = st.toString().split('\n').take(10).join(' | ');
      unawaited(DiagnosticLogger.log('API-PURCHASE-VOID',
          '❌ error: $e\nstack: $stackLines'));
      return ApiErrors.fail(e, 'Failed to void purchase', st: st);
    }
  }

  /// Spec 151 C-03 — client/mirror purchase PAYMENT submit (R4/R8/R9). The
  /// server (SSoT) resolves the invoice (globalId → invoiceNumber → id),
  /// advances invoice.paid and posts the authoritative Dr AP / Cr cash JE +
  /// safe move via db.addPurchasePayment. A payment is ADDITIVE, so
  /// addPurchasePayment dedups on the caller's per-event globalId — an outbox
  /// replay / WriteRouter retry carrying the same id applies it exactly once.
  Future<Response> postPurchasePayment(Request request) async {
    try {
      // A payment advances the invoice's paid/status — same authority as an
      // edit. purchasesEdit mirrors the route gate on PUT /api/purchases/<id>.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.purchasesEdit);
      if (perm != null) return perm;

      return await ApiHandlerBase.withBroadcast<Response>(
        endpointLabel: 'postPurchasePayment',
        tables: const {
          'purchase_invoices',
          'safe_transactions',
          'parties', 'accounting', 'journal_entries',
        },
        body: () async {
          final data =
              json.decode(await request.readAsString()) as Map<String, dynamic>;
          final purchaseId = parseInt(data['purchaseId']);
          final purchaseGlobalId = data['purchaseGlobalId'] as String?;
          final invoiceNumber = data['invoiceNumber'] as String?;
          final amount = parseDouble(data['amount']);
           final paymentRate = parseDoubleNullable(data['paymentRate'] ?? data['payment_rate']);
           final foreignAmount = parseDoubleNullable(data['foreignAmount'] ?? data['foreign_amount']);
          // R9 — the SAME deterministic per-event id the client stamped on the
          // local payment context. addPurchasePayment dedups on it.
          final paymentGlobalId = data['globalId'] as String?;

          if (amount <= 0) {
            return errorResponse('Invalid payment amount: $amount', statusCode: 400);
          }

          unawaited(DiagnosticLogger.log('API-PURCHASE-PAYMENT',
              'POST /api/purchases/payment received '
              'invoiceNumber=$invoiceNumber purchaseId=$purchaseId '
              'purchaseGlobalId=$purchaseGlobalId amount=$amount '
              'globalId=$paymentGlobalId'));

          // Same resolution chain as postVoidPurchase: globalId (deterministic)
          // → invoiceNumber → id (legacy). Client/server ids diverge routinely.
          var lookup = (purchaseGlobalId != null && purchaseGlobalId.isNotEmpty)
              ? await (db.select(db.purchaseInvoices)
                    ..where((p) => p.globalId.equals(purchaseGlobalId)))
                  .getSingleOrNull()
              : null;
          if (lookup == null && invoiceNumber != null && invoiceNumber.isNotEmpty) {
            lookup = await (db.select(db.purchaseInvoices)
                  ..where((p) => p.invoiceNumber.equals(invoiceNumber)))
                .getSingleOrNull();
          }
          lookup ??= await (db.select(db.purchaseInvoices)
                ..where((p) => p.id.equals(purchaseId)))
              .getSingleOrNull();
          if (lookup == null) {
            return errorResponse(
              'Purchase invoice not found (id=$purchaseId, globalId=$purchaseGlobalId, num=$invoiceNumber)',
              statusCode: 404,
            );
          }
          final invoice = lookup;

          final resolvedUserId = await _resolveUserIdNullable(
            parseIntNullable(data['userId']),
            fallbackUsername: data['createdByUsername'] as String?,
          );

          // Advances paid + posts the balanced Dr AP / Cr cash JE + safe move
          // atomically (its own transaction); idempotent on paymentGlobalId.
          await db.addPurchasePayment(
            invoiceId: invoice.id,
            amount: amount,
            userId: resolvedUserId,
            globalId: paymentGlobalId,
            paymentRate: paymentRate,
            foreignAmount: foreignAmount,
          );

          db.markTablesUpdated({db.purchaseInvoices, db.safeTransactions});

          unawaited(DiagnosticLogger.log('API-PURCHASE-PAYMENT',
              '✓ payment applied invoice=${invoice.invoiceNumber} '
              'serverId=${invoice.id} amount=$amount'));

          return jsonResponse({'success': true, 'serverId': invoice.id});
        },
      );
    } on PermissionDeniedException catch (e) {
      return errorResponse(e.message, statusCode: 403);
    } catch (e, st) {
      debugPrint('[API] postPurchasePayment error: $e\n$st');
      final stackLines = st.toString().split('\n').take(10).join(' | ');
      unawaited(DiagnosticLogger.log('API-PURCHASE-PAYMENT',
          '❌ error: $e\nstack: $stackLines'));
      return ApiErrors.fail(e, 'Failed to record purchase payment', st: st);
    }
  }

  Future<Response> putPurchase(Request request, String id) async {
    try {
      // Spec 077 Batch 4 (Spec 060 Phase 2): per-user permission gate.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.purchasesEdit);
      if (perm != null) return perm;

      final data =
          json.decode(await request.readAsString()) as Map<String, dynamic>;
      final rawItems = (data['items'] as List);
      final items = <PurchaseInvoiceItemsCompanion>[];
      for (final item in rawItems) {
        final m = item as Map<String, dynamic>;
        final rawExpiry = m['expiryDate'];
        final DateTime? expiryDate = rawExpiry is String && rawExpiry.isNotEmpty
            ? DateTime.tryParse(rawExpiry)
            : null;
        final resolvedProductId = await resolveProductId(
          clientProductId: parseIntNullable(m['productId']),
          productGlobalId: m['productGlobalId'] as String?,
          fallbackCode: m['productCode'] as String?,
          fallbackName: m['productName'] as String?,
        );
        if (resolvedProductId == null) {
          throw Exception('Validation Error: purchase item missing productId/productGlobalId');
        }
        // Feature 043 (Route B.1) — honour the per-item globalId minted on
        // the client. Both sides now store the line under the SAME UUID,
        // so DeltaPull's Tier-1 dedup catches the row on the mirror's
        // pull-back instead of inserting a duplicate. When the field is
        // absent (legacy clients or standalone server), `Value.absent()`
        // lets the DAO mint a fresh UUID — preserves the pre-043 contract
        // for callers that never threaded it.
        final lineGid = (m['globalId'] as String?)?.trim();
        items.add(PurchaseInvoiceItemsCompanion(
          productId: Value(resolvedProductId),
          quantity: Value(parseDouble(m['quantity'])),
          unitCost: Value(parseDouble(m['unitCost'])),
          total: Value(parseDouble(m['total'])),
          taxRate: Value(parseDouble(m['taxRate'])),
          taxAmount: Value(parseDouble(m['taxAmount'])),
          batchNumber: Value(m['batchNumber'] as String?),
          expiryDate: Value(expiryDate),
          unitName: Value(m['unitName'] as String?),
          quantityInBase: Value(parseDouble(m['quantityInBase'], 1.0)),
          // خصمُ السطر — يصل الخادمَ ويوزّعه `resolvePurchaseLineNets`.
          // وغيابُه من حمولةٍ قديمةٍ يعطي صفراً، وهو عينُ السلوك السابق.
          discount: Value(parseDouble(m['discount'])),
          globalId: (lineGid != null && lineGid.isNotEmpty)
              ? Value(lineGid)
              : const Value.absent(),
        ));
      }

      final invoiceIdUp = int.parse(id);

      // warehouseId is optional on an EDIT: a client that only changed lines
      // has no reason to resend it. Falling back to the invoice's own
      // warehouse keeps the edit valid instead of 500-ing with
      // "warehouseId is required" — the failure that made every client-mode
      // purchase edit impossible AND left a poison row in the client outbox
      // (which then drove the retry storm in OfflineSyncWorker).
      final clientWhIdUp = parseInt(data['warehouseId']);
      final int resolvedWhIdUp;
      if (clientWhIdUp == 0) {
        final existing = await db.getPurchaseInvoiceById(invoiceIdUp);
        if (existing == null) {
          throw Exception('Validation Error: purchase invoice $id not found.');
        }
        resolvedWhIdUp = existing.warehouseId;
      } else {
        final clientBranchIdUp = parseIntNullable(data['branchId']);
        resolvedWhIdUp =
            await _resolveWarehouseId(clientWhIdUp, branchId: clientBranchIdUp);
      }

      await db.updatePurchaseInvoice(
        invoiceId: invoiceIdUp,
        supplierId: parseInt(data['supplierId']),
        warehouseId: resolvedWhIdUp,
        items: items,
        paid: parseDoubleNullable(data['paid']) ?? 0,
        paymentMethod: data['paymentMethod'] as String? ?? 'cash',
        notes: data['notes'] as String?,
        supplierInvoiceNumber: data['supplierInvoiceNumber'] as String?,
        costCenterId: parseIntNullable(data['costCenterId']),
        // Purchase-edit policy — the DAO gate evaluates `purchases_edit`
        // against THIS user. ApiUserCtx.userIdOf is the session-token-derived
        // identity that `requirePermission` above already validated, so the
        // local gate and the API gate now agree on who is acting.
        userId: ApiUserCtx.userIdOf(request),
        // ح-1: the server edit path dropped the discount too, so a discounted
        // invoice edited from any client came back gross. Absent key = null =
        // keep the stored discount rather than wiping it.
        discount: parseDoubleNullable(data['discount']),
        // J1b (v188): key present ⇒ the edit set/cleared the chosen account.
        changePurchaseAccount: data.containsKey('purchaseAccountId'),
        purchaseAccountId: parseIntNullable(data['purchaseAccountId']),
      );
      broadcast('purchases');
      broadcast('products');
      db.markTablesUpdated({db.purchaseInvoices});
      return jsonResponse({'success': true});
    } on PermissionDeniedException catch (e) {
      // The DAO's purchases_edit gate throws this. It is a 403, not a 500 —
      // otherwise the client outbox treats it as a retryable server error and
      // replays it until dead-letter.
      return errorResponse(e.message, statusCode: 403);
    } catch (e) {
      debugPrint('[API] putPurchase error: $e');
      return ApiErrors.fail(e, 'Failed to update purchase');
    }
  }

  Future<Response> deletePurchase(Request request, String id) async {
    try {
      // Spec 077 Batch 4 (Spec 060 Phase 2): per-user permission gate.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.purchasesDelete);
      if (perm != null) return perm;

      final invoiceId = int.parse(id);
      await db.deletePurchaseInvoice(invoiceId);
      broadcast('purchases');
      broadcast('products');
      broadcastRecordDeleted('purchase_invoices', invoiceId);
      db.markTablesUpdated({db.purchaseInvoices});
      return jsonResponse({'success': true});
    } on PermissionDeniedException catch (e) {
      // A permission denial is 403 Forbidden, not 500 (symmetric with
      // deleteSalesInvoice). The Spec 062 paid-invoice void gate throws this
      // when the caller lacks the critical-op permission.
      return errorResponse(e.message, statusCode: 403);
    } catch (e) {
      return ApiErrors.fail(e, 'Failed to delete purchase');
    }
  }
}
