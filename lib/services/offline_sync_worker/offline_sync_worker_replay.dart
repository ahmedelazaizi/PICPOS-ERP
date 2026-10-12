// OfflineSyncWorker - per-table replay dispatch (`_replayOperation`).
part of '../offline_sync_worker.dart';

/// Per-table replay dispatch of [OfflineSyncWorker]: one `switch` over the outbox table name.
extension OfflineSyncWorkerReplay on OfflineSyncWorker {
  /// Replay a single queued operation via ServerProxy
  Future<dynamic> _replayOperation(
    String table,
    String operation,
    Map<String, dynamic> payload,
    int outboxId,
  ) async {
    final proxy = ServerProxy.instance;
    // Spec 136 ISS-21 — use the globally-unique idempotency key that
    // ClientWriteInterceptor._tryOrQueue already minted (a UUIDv7 stored in
    // payload['idempotency_key']) instead of regenerating 'SyncOutbox_<localId>'.
    //
    // The local outbox autoincrement id is NOT globally unique: it restarts at
    // 1 after a wipe/reinstall (this device gets MIRROR-WIPE) and repeats across
    // devices, while the server's `processed_messages` cache is persistent and
    // global. So 'SyncOutbox_3' from a fresh outbox collided with a DIFFERENT
    // invoice's cached entry from an earlier session — the server returned that
    // stale cached response and SILENTLY DROPPED the new offline invoice
    // (field repro: SINV-32 hit cached AQ-POS-18 serverId=84 → never persisted →
    // shift variance). The UUIDv7 key never collides; a genuine retry of the
    // SAME item reuses the same stored key (correct idempotency), and the
    // server's globalId dedup remains the authoritative guard.
    final idempotencyKey = OfflineSyncWorker.idempotencyKeyFor(payload, outboxId);

    switch (table) {
      case 'sales':
        if (operation == 'insert') {
          return proxy.submitSale(payload, idempotencyKey: idempotencyKey);
        } else if (operation == 'delete') {
          // FIX 3.4: Pass idempotencyKey to DELETE — prevents double-delete on reconnect
          await proxy.deleteSalesInvoice(payload['id'] as int, idempotencyKey: idempotencyKey);
        } else if (operation == 'void') {
          // C-02 (Spec 151): sales-invoice void submit queued while the server
          // was unreachable. Without this branch the payload would silently
          // fall through the switch on drain — the client thinks the void is
          // "queued" forever but it is actually dropped. Server resolves by the
          // threaded globalId (payload['globalId']) and is idempotent.
          return proxy.submitVoidSale(payload, idempotencyKey: idempotencyKey);
        } else if (operation == 'payment') {
          // Spec 151 C-05: customer collection queued while the server was
          // unreachable. Same drop-on-drain hazard as void — replay via the
          // dedicated endpoint (server dedups on the payload globalId).
          return proxy.submitSalesPayment(payload, idempotencyKey: idempotencyKey);
        } else if (operation == 'update') {
          // Pre-deploy BLOCKER (sync audit): an invoice edit queued offline must
          // reach HQ (was silently dropped via break→null→markAsSyncSuccess).
          await proxy.updateSalesInvoice(payload['id'] as int, payload, idempotencyKey: idempotencyKey);
        } else {
          throw StateError('Unhandled op $operation for table $table');
        }
        break;

      case 'sales_returns':
        if (operation == 'insert') {
          return proxy.submitSalesReturn(payload, idempotencyKey: idempotencyKey);
        }
        break;

      case 'sales_exchanges':
        if (operation == 'insert') {
          // بلا هذا الفرع تُصَفُّ حمولةُ الاستبدال ثم تسقط صامتةً عند
          // التصريف (‏`break` → null → `markAsSyncSuccess`) — نفسُ ما وقع
          // لـ`void` و`payment` قبلَها. والعميلُ يظنّها «مُصفَّفة» وهي مفقودة.
          return proxy.submitExchange(payload, idempotencyKey: idempotencyKey);
        }
        break;

      case 'held_orders':
        if (operation == 'insert') {
          return proxy.submitHeldOrder(payload, idempotencyKey: idempotencyKey);
        } else if (operation == 'delete') {
          // FIX 3.4: Pass idempotencyKey to DELETE
          await proxy.deleteHeldOrder(payload['id'] as int, idempotencyKey: idempotencyKey);
        }
        break;

      case 'expenses':
        if (operation == 'insert') {
          return proxy.submitExpense(
            amount: (payload['amount'] as num).toDouble(),
            category: payload['category'] as String,
            description: payload['description'] as String?,
            partyId: payload['partyId'] as int?,
            // Feature 044 — forward cached party identifiers so a
            // deferred replay still resolves via `resolvePartyId` on the
            // server. Older queue entries without these fields fall back
            // to the integer partyId path.
            partyGlobalId: payload['partyGlobalId'] as String?,
            partyName: payload['partyName'] as String?,
            safeId: payload['safeId'] as int?,
            userId: payload['userId'] as int?,
            costCenterId: payload['costCenterId'] as int?,
            branchId: payload['branchId'] as int?,
            globalId: payload['globalId'] as String?,
            idempotencyKey: idempotencyKey,
          );
        } else if (operation == 'delete') {
          // FIX 3.4: Pass idempotencyKey to DELETE
          await proxy.deleteExpense(payload['id'] as int, idempotencyKey: idempotencyKey);
        }
        break;

      case 'receipts':
        if (operation == 'insert') {
          return proxy.submitReceipt(
            amount: (payload['amount'] as num).toDouble(),
            category: payload['category'] as String,
            description: payload['description'] as String?,
            partyId: payload['partyId'] as int?,
            // Feature 044 — same party-resolution threading.
            partyGlobalId: payload['partyGlobalId'] as String?,
            partyName: payload['partyName'] as String?,
            safeId: payload['safeId'] as int?,
            safeGlobalId: payload['safeGlobalId'] as String?,
            userId: payload['userId'] as int?,
            branchId: payload['branchId'] as int?,
            costCenterId: payload['costCenterId'] as int?,
            linkedAccountId: payload['linkedAccountId'] as int?,
            globalId: payload['globalId'] as String?,
            idempotencyKey: idempotencyKey,
          );
        }
        break;

      case 'vouchers':
        // E-fix ١ — سندُ العميل الكامل (`ClientVoucherInterceptor`). الخادمُ
        // يُطابق على `globalId` فالتصريفُ المكرَّرُ لا يقيّد مرّتين.
        if (operation == 'insert') {
          return proxy.submitVoucher(payload, idempotencyKey: idempotencyKey);
        }
        break;

      case 'parties':
        if (operation == 'insert') {
          return proxy.createParty(payload, idempotencyKey: idempotencyKey);
        } else if (operation == 'update') {
          // Pre-deploy BLOCKER (sync audit): a customer edit (credit-limit,
          // balance, phone, discount) queued offline via cwi_commerce.dart must
          // reach HQ. Without this branch the op hit break→null→markAsSyncSuccess
          // and was silently dropped, then reverted on the next serverWins pull.
          await proxy.updateParty(payload['id'] as int, payload, idempotencyKey: idempotencyKey);
        } else if (operation == 'delete') {
          await proxy.deleteParty(payload['id'] as int, idempotencyKey: idempotencyKey);
        } else {
          throw StateError('Unhandled op $operation for table $table');
        }
        break;

      case 'units':
        if (operation == 'insert') {
          return proxy.submitUnit(payload, idempotencyKey: idempotencyKey);
        } else if (operation == 'update') {
          await proxy.updateUnit(payload['id'] as int, payload, idempotencyKey: idempotencyKey);
        } else if (operation == 'delete') {
          await proxy.deleteUnit(payload['id'] as int, idempotencyKey: idempotencyKey);
        }
        break;

      case 'product_units':
        if (operation == 'insert') {
          return proxy.submitProductUnitMapping(payload, idempotencyKey: idempotencyKey);
        } else if (operation == 'update') {
          // ⚠️ كان هذا الفرعُ **غائباً**، فيسقط `update` على `break` ويعود
          // `null` ⇒ يُعلَّم في الطابور **ناجحاً** بلا إرسال. تعديلُ سعرِ
          // وحدةٍ أو معامِلِ تحويلٍ أثناء انقطاعٍ كان يُمحى من الطابور ثم
          // يُرجَع بأوّل سحبٍ تالٍ (`serverWins`) — فيبيع الكرتونةَ بسعرٍ
          // خاطئ. نفسُ فئةِ العطب التي أُغلقت لـ`parties/update` و
          // `sales/update`.
          await proxy.updateProductUnitMapping(
              payload['id'] as int, payload,
              idempotencyKey: idempotencyKey);
        } else if (operation == 'delete') {
          await proxy.deleteProductUnitMapping(payload['id'] as int, idempotencyKey: idempotencyKey);
        } else {
          // فخُّ الفئة: عمليةٌ غيرُ معروفةٍ تُرمى ولا تُبتلع. الصمتُ هنا هو
          // العطبُ نفسُه.
          throw StateError('Unhandled op $operation for table $table');
        }
        break;

      case 'product_barcodes':
        if (operation == 'insert') {
          return proxy.submitProductBarcode(payload, idempotencyKey: idempotencyKey);
        } else if (operation == 'delete') {
          await proxy.deleteProductBarcode(payload['id'] as int, idempotencyKey: idempotencyKey);
        }
        break;

      case 'products':
        if (operation == 'insert') {
          return proxy.createProduct(payload, idempotencyKey: idempotencyKey);
        } else if (operation == 'update') {
          await proxy.updateProduct(payload['id'] as int, payload, idempotencyKey: idempotencyKey);
        } else if (operation == 'delete') {
          await proxy.deleteProduct(payload['id'] as int, idempotencyKey: idempotencyKey);
        }
        break;

      case 'purchase_returns':
        if (operation == 'insert') {
          return proxy.submitPurchaseReturn(payload, idempotencyKey: idempotencyKey);
        } else if (operation == 'edit') {
          // Feature 015 — purchase return edit (atomic reverse + recreate).
          return proxy.submitPurchaseReturnEdit(payload, idempotencyKey: idempotencyKey);
        }
        break;

      case 'purchases':
      case 'purchase_invoices':
        if (operation == 'insert') {
          // Replay the ORIGINAL payload, only normalising snake_case keys that
          // the PurchaseDao outbox writes. The previous hand-built map listed
          // 7 fields and silently dropped everything else — `discount`,
          // `globalId`, `costCenterId`, `branchId`, `userId`, and per-line
          // `taxRate`/`taxAmount`/`batchNumber`/`expiryDate`/`unitName`/
          // `quantityInBase`/`globalId`. So any purchase queued while offline
          // reached the server GROSS, with zero VAT, no idempotency key and no
          // line identities (which then duplicated on the next pull).
          final replay = <String, dynamic>{...payload};
          void alias(String camel, String snake) {
            if (replay[camel] == null && replay[snake] != null) {
              replay[camel] = replay[snake];
            }
          }
          alias('supplierId', 'supplier_id');
          alias('warehouseId', 'warehouse_id');
          alias('invoiceDate', 'invoice_date');
          alias('paymentMethod', 'payment_method');
          alias('supplierInvoiceNumber', 'invoice_number');
          alias('costCenterId', 'cost_center_id');
          alias('branchId', 'branch_id');
          alias('globalId', 'global_id');
          alias('userId', 'user_id');
          replay['paid'] ??= 0;
          replay['items'] = (payload['items'] as List?)?.map((item) {
            final m = Map<String, dynamic>.from(item as Map);
            m['productId'] ??= m['product_id'];
            m['unitCost'] ??= m['unit_cost'];
            m['taxRate'] ??= m['tax_rate'];
            m['taxAmount'] ??= m['tax_amount'];
            m['quantityInBase'] ??= m['quantity_in_base'];
            m['globalId'] ??= m['global_id'];
            m['total'] ??= ((m['quantity'] as num?)?.toDouble() ?? 0) *
                ((m['unitCost'] as num?)?.toDouble() ?? 0);
            return m;
          }).toList() ?? [];
          return proxy.createPurchase(replay, idempotencyKey: idempotencyKey);
        } else if (operation == 'update') {
          await proxy.updatePurchase(payload['id'] as int, payload, idempotencyKey: idempotencyKey);
        } else if (operation == 'delete') {
          await proxy.deletePurchase(payload['id'] as int);
        } else if (operation == 'void') {
          // PR-2 (pre-deploy batch B6): void submit queued while the server
          // was unreachable. Without this branch the payload would silently
          // fall through the switch on drain — the client thinks the void
          // is "queued" forever but it's actually dropped.
          return proxy.submitVoidPurchase(payload, idempotencyKey: idempotencyKey);
        } else if (operation == 'payment') {
          // Spec 151 C-03: purchase payment queued while the server was
          // unreachable. Same drop-on-drain hazard as void — replay via the
          // dedicated endpoint (server dedups on the payload globalId).
          return proxy.submitPurchasePayment(payload, idempotencyKey: idempotencyKey);
        }
        break;

      case 'quotations':
        // Offline-queued quotation operations. Without this case, entries
        // created or edited while the server was unreachable used to fall
        // through to the `default:` branch below and get silently dropped —
        // the user saw the save succeed locally, but the server never heard
        // about it, which is why editing an "already-saved" quotation hung
        // on a loading state that waited for a server round-trip that was
        // never going to happen.
        if (operation == 'insert') {
          return proxy.createQuotation(payload, idempotencyKey: idempotencyKey);
        } else if (operation == 'update') {
          // Two shapes land here:
          //   (a) status-only update — payload carries `status` (+ optional
          //       `convertedToInvoiceId`) and no `items` array.
          //   (b) full-row edit      — payload carries an `items` list (and
          //       typically subtotal/total/discount/...); routed to the
          //       full PUT /api/quotations/<id> endpoint.
          final hasItems = payload['items'] is List;
          if (hasItems) {
            await proxy.updateQuotation(
              payload['id'] as int,
              payload,
              idempotencyKey: idempotencyKey,
            );
          } else {
            await proxy.updateQuotationStatus(
              payload['id'] as int,
              payload['status'] as String? ?? 'draft',
              convertedInvoiceId: payload['convertedToInvoiceId'] as int?,
              idempotencyKey: idempotencyKey,
            );
          }
        } else if (operation == 'delete') {
          await proxy.deleteQuotation(payload['id'] as int, idempotencyKey: idempotencyKey);
        }
        break;

      case 'shifts':
        if (operation == 'open') {
          // Return the server's shiftId so the calling drain loop captures it
          // into mappedIds['shifts'] → ensures any subsequent close operation
          // gets remapped from local id to server id (otherwise the close
          // fails with "Shift not found").
          return proxy.openShift(
            payload['userId'] as int,
            (payload['openingBalance'] as num).toDouble(),
            // Spec 008 / FR-006: forward branchId from the outbox payload
            // so a delayed-drain shift open lands on the server with the
            // correct branch attribution.
            branchId: payload['branchId'] is int
                ? payload['branchId'] as int
                : (payload['branchId'] is num
                    ? (payload['branchId'] as num).toInt()
                    : null),
            // R9: forward globalId so the server dedups by it on retries
            // (idempotent open) instead of inserting a fresh phantom shift.
            globalId: payload['globalId'] as String?,
            idempotencyKey: idempotencyKey,
          );
        } else if (operation == 'close') {
          // Phase 5A.7 (Issue 2) — forward the optional reconstruction
          // hints (userId/openingBalance/openedAt) so the server can
          // recreate the shift if /api/shifts/open never drained before
          // the close arrived. Older outbox rows queued before this
          // change won't have these keys; the proxy treats them as null.
          final openedAtRaw = payload['openedAt'] as String?;
          await proxy.closeShift(
            payload['shiftId'] as int,
            (payload['actualCash'] as num).toDouble(),
            notes: payload['notes'] as String?,
            userId: payload['userId'] as int?,
            openingBalance: (payload['openingBalance'] as num?)?.toDouble(),
            openedAt: openedAtRaw != null ? DateTime.tryParse(openedAtRaw) : null,
            // R9: forward shiftGlobalId so the server resolves the right
            // shift even when the local→server id mapping is missing
            // (the recurring "Shift not found" DEAD-LETTER root cause).
            shiftGlobalId: payload['shiftGlobalId'] as String?,
            idempotencyKey: idempotencyKey,
          );
        }
        break;

      case 'categories':
        if (operation == 'insert') {
          return proxy.createCategory(
            name: payload['name'] as String,
            color: payload['color'] as String,
            printerId: payload['printerId'] as int?,
            iconName: payload['iconName'] as String?,
            idempotencyKey: idempotencyKey,
          );
        } else if (operation == 'update') {
          await proxy.updateCategory(
            id: payload['id'] as int,
            name: payload['name'] as String,
            color: payload['color'] as String,
            printerId: payload['printerId'] as int?,
            iconName: payload['iconName'] as String?,
            idempotencyKey: idempotencyKey,
          );
        } else if (operation == 'delete') {
          // FIX 3.4: Pass idempotencyKey to DELETE
          // Feature 045: forward the cached `moveToCategoryId` so a
          // deferred replay still runs the same bulk-move + soft-delete
          // server-side. Older queue entries without this key replay as
          // `moveToCategoryId=null` (uncategorized) — matches the
          // legacy "products survive" expectation.
          await proxy.deleteCategory(
            payload['id'] as int,
            moveToCategoryId: payload['moveToCategoryId'] as int?,
            idempotencyKey: idempotencyKey,
          );
        }
        break;

      case 'inventory':
        if (operation == 'adjust') {
          // Spec 135 BUG-A: forward the cached productGlobalId + per-event
          // adjustmentEventGid from the outbox payload so a deferred replay
          // re-sends the SAME deterministic JE globalId. Without this, the
          // server falls back to a fresh UuidV7 on replay → a divergent JE
          // globalId that the UNIQUE constraint can't dedup → phantom
          // duplicate JE (or 23505) if the first attempt partially landed.
          // Older queue entries lacking these keys replay as null (pre-135
          // behaviour — still event-unique, just not cross-instance-deduped).
          await proxy.adjustStock(
            productId: payload['productId'] as int,
            warehouseId: payload['warehouseId'] as int,
            quantity: (payload['quantity'] as num).toDouble(),
            type: payload['type'] as String?,
            notes: payload['notes'] as String?,
            productGlobalId: payload['productGlobalId'] as String?,
            // Spec 136 ISS-26 #2 — forward the cached warehouseGlobalId so a
            // deferred replay still resolves the correct server warehouse.
            warehouseGlobalId: payload['warehouseGlobalId'] as String?,
            adjustmentEventGid: payload['adjustmentEventGid'] as String?,
            idempotencyKey: idempotencyKey,
          );
        }
        break;

      case 'settings':
        if (operation == 'update') {
          final settings = (payload['settings'] as Map?)?.cast<String, String>();
          if (settings != null) {
            await proxy.saveSettings(settings, idempotencyKey: idempotencyKey);
          }
        }
        break;

      default:
        return _replayOperationFinance(
            table, operation, payload, proxy, idempotencyKey);
    }
  }
}
