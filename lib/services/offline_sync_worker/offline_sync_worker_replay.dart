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

      case 'commercial_papers':
        if (operation == 'insert') {
          // `return` مش `await`: الـdrain بيلتقط الـserverId من القيمة
          // المرجَّعة ويسجّل mapping في `remote_id_mappings`. `await` بيرجّع
          // `null` فمفيش mapping — والعمليات اللاحقة (تجديد · تحصيل جزئي ·
          // إيداع · إعادة إصدار) بتبعت الـid **المحلي** في مسار الـURL،
          // فبتضرب ورقة تانية خالص على السيرفر ليها نفس الرقم.
          return proxy.createCommercialPaper(payload, idempotencyKey: idempotencyKey);
        } else if (operation == 'update_status') {
          await proxy.updateCommercialPaperStatus(
            payload['id'] as int,
            status: payload['status'] as String,
            changedBy: payload['changedBy'] as int?,
            // Feature 042 (Bug 5) — forward the cached username from the
            // queued payload so a deferred replay still resolves the
            // server-side user_id via _resolveUserIdNullable. Older
            // queue entries without this field still work via the
            // integer changedBy fallback.
            changedByUsername: payload['changedByUsername'] as String?,
            notes: payload['notes'] as String?,
            endorsedToPartyId: payload['endorsedToPartyId'] as int?,
            globalId: payload['globalId'] as String?,
            // Feature 048 (v130) — forward the user-chosen contra leg so a
            // deferred replay still posts the JE to the right account.
            counterAccountId: payload['counterAccountId'] as int?,
            counterAccountGlobalId:
                payload['counterAccountGlobalId'] as String?,
          );
        } else if (operation == 'renew') {
          await proxy.renewCommercialPaper(
            payload['id'] as int,
            newDueDate: payload['newDueDate'] as String,
            changedBy: payload['changedBy'] as int?,
            notes: payload['notes'] as String?,
          );
        } else if (operation == 'partial_collect') {
          await proxy.partialCollectPaper(
            payload['id'] as int,
            amount: (payload['amount'] as num).toDouble(),
            changedBy: payload['changedBy'] as int?,
            notes: payload['notes'] as String?,
          );
        } else if (operation == 'endorse') {
          await proxy.updateCommercialPaperStatus(
            payload['id'] as int,
            status: 'endorsed',
            changedBy: payload['changedBy'] as int?,
            notes: payload['notes'] as String?,
            endorsedToPartyId: payload['endorsedToPartyId'] as int?,
          );
        } else if (operation == 'deposit') {
          await proxy.depositPaperForCollection(
            payload['id'] as int,
            bankSafeId: payload['bankSafeId'] as int,
            changedBy: payload['changedBy'] as int?,
            notes: payload['notes'] as String?,
          );
        } else if (operation == 'reissue') {
          await proxy.reissuePaper(
            payload['id'] as int,
            newPartyId: payload['newPartyId'] as int,
            changedBy: payload['changedBy'] as int?,
            notes: payload['notes'] as String?,
          );
        }
        break;

      // BLOCKER C-01 (Spec 151) — offline journal-entry replay.
      // The outbox producer (cwi_sync.submitJournalEntry) queues manual/auto
      // journal entries under tableName:'journal_entries'. Before this fix the
      // switch had ONLY a (dead) 'journals' case and NO 'journal_entries'
      // case, so every offline JE fell through to `default:`, which
      // debugPrint'd and returned null. The drain loop then called
      // markAsSyncSuccess unconditionally → the GL write was cleared from the
      // outbox and NEVER reached the server: a silent GL loss with no
      // dead-letter. Both names now share one body so a JE queued under either
      // key replays correctly. ('journals' is retained because the pull-side /
      // websocket subscription map still references that name.)
      case 'journals':
      case 'journal_entries':
        if (operation == 'insert') {
          return proxy.submitJournalEntry(
            description: (payload['description'] ?? payload['notes']) as String? ?? '',
            date: (payload['date'] ?? payload['entry_date'] ?? payload['created_at']) as String? ?? DateTime.now().toIso8601String(),
            lines: (payload['lines'] as List?)
                    ?.cast<Map<String, dynamic>>() ??
                [],
            referenceType: (payload['referenceType'] ?? payload['reference_type']) as String?,
            referenceId: (payload['referenceId'] ?? payload['reference_id']) as int?,
            isAutoPosted: (payload['isAutoPosted'] ?? payload['is_auto_posted']) as bool? ?? true,
            costCenterId: (payload['costCenterId'] ?? payload['cost_center_id']) as int?,
            branchId: (payload['branchId'] ?? payload['branch_id']) as int?,
            // R9: thread the caller-minted globalId (UUIDv7) end-to-end so the
            // server dedups by it on retries instead of inserting a phantom
            // duplicate JE. The legacy 'journals' body omitted it — a real R9
            // gap that this fix closes for both keys.
            globalId: (payload['globalId'] ?? payload['global_id']) as String?,
            idempotencyKey: idempotencyKey,
          );
        }
        break;

      // v166 — ورقةُ تحميلٍ مطبَّقة. الحمولةُ هي المستندُ نفسُه، فتُعاد
      // كما هي: الخادمُ يزيل التكرارَ بمعرّف الورقة العالميّ، فإعادةُ
      // الإرسال بعد انقطاعٍ لا تُنتج تطبيقاً ثانياً ولا قيداً ثانياً.
      // v174 / قسمُ ٧ — مخطَّطُ قاعةٍ كاملاً. الحمولةُ **صورةٌ نهائيّةٌ**
      // لا فرقٌ، فإعادةُ إرسالِها بعد انقطاعٍ تُعيد نفسَ المخطَّط لا
      // معالمَ مضاعَفةً: المعالمُ تُطابَق بمعرّفاتِها العالميّة،
      // والغائبُ عنها يُحذَف حذفاً ناعماً.
      case 'floor_plan_items':
        if (operation == 'save') {
          return proxy.submitFloorPlan(
            payload,
            idempotencyKey: idempotencyKey,
          );
        }
        throw StateError('Unhandled op $operation for table $table');

      case 'attachments':
        // v176 / §٨ — ورقةٌ رُفعت والشبكةُ مقطوعة. والحمولةُ
        // **تحمل البايتاتِ نفسَها** (base64) لا مسارَ ملفٍّ على
        // القرص: مسارٌ يصير مُعلَّقاً إن نُقِل الملفُّ أو مُسِح،
        // فيُعاد إرسالُ مرفقٍ لا وجودَ له إلى الأبد.
        if (operation == 'insert') {
          return proxy.submitAttachment(
            payload,
            idempotencyKey: idempotencyKey,
          );
        }
        if (operation == 'delete') {
          return proxy.submitAttachmentDelete(
            payload,
            idempotencyKey: idempotencyKey,
          );
        }
        throw StateError('Unhandled op $operation for table $table');

      case 'landed_cost_sheets':
        if (operation == 'apply') {
          return proxy.submitLandedCostApply(
            payload,
            idempotencyKey: idempotencyKey,
          );
        }
        throw StateError('Unhandled op $operation for table $table');

      // v166 — اقتناءُ أصلٍ وترحيلُ إهلاك. الحمولةُ هي الطلبُ نفسُه:
      // الخادمُ يزيل تكرارَ الأصل بمعرّفه، ويزيل تكرارَ الإهلاك بمفتاحه
      // الطبيعيّ `(asset_id, period_date)`.
      case 'fixed_assets':
        if (operation == 'insert') {
          return proxy.submitFixedAssetCreate(payload,
              idempotencyKey: idempotencyKey);
        }
        throw StateError('Unhandled op $operation for table $table');

      case 'asset_depreciations':
        if (operation == 'run') {
          return proxy.submitAssetDepreciationRun(payload,
              idempotencyKey: idempotencyKey);
        }
        throw StateError('Unhandled op $operation for table $table');

      // v166 — مصروفٌ تشغيليّ. الخادمُ يزيل التكرارَ بمعرّفه.
      case 'op_expenses':
        if (operation == 'insert') {
          return proxy.submitOperationalExpense(payload,
              idempotencyKey: idempotencyKey);
        }
        throw StateError('Unhandled op $operation for table $table');

      // v166 — حدثٌ على أمرِ إنتاج. الخادمُ يفحص حالةَ الأمر قبل التنفيذ
      // (‏`draft` للبدء و`in_progress` للإنجاز)، فإعادةُ الإرسال بعد
      // انقطاعٍ تُردّ بدل أن تستهلك الخاماتِ ثانية.
      case 'manufacturing_orders':
        if (operation == 'action') {
          return proxy.submitManufacturingAction(payload,
              idempotencyKey: idempotencyKey);
        }
        throw StateError('Unhandled op $operation for table $table');

      // v167 — خصمُ عربون. الخادمُ يفحص `bookings.invoice_id` قبل التنفيذ،
      // فإعادةُ الإرسال بعد انقطاعٍ تُردّ بدل أن تُطفئ الالتزامَ مرّتين
      // وتنقص رصيدَ العميل ضِعفَ ما دفع.
      case 'bookings':
        if (operation == 'apply_deposit') {
          return proxy.submitBookingDepositApplication(payload,
              idempotencyKey: idempotencyKey);
        }
        throw StateError('Unhandled op $operation for table $table');

      case 'safe_transactions':
        if (operation == 'insert') {
          return proxy.submitSafeTransaction(
            safeId: (payload['safeId'] ?? payload['safe_id']) as int? ?? 1,
            transactionType: (payload['transactionType'] ?? payload['transaction_type']) as String? ?? 'receipt',
            amount: (payload['amount'] as num?)?.toDouble() ?? 0,
            category: payload['category'] as String? ?? 'general',
            description: (payload['description'] ?? payload['notes']) as String?,
            userId: (payload['userId'] ?? payload['user_id']) as int?,
            referenceType: (payload['referenceType'] ?? payload['reference_type']) as String?,
            referenceId: (payload['referenceId'] ?? payload['reference_id']) as int?,
            // Phase 5B.4 (Issue 7) — ferry the optional safeGlobalId +
            // costCenterId hints when the queued payload carried them.
            // Older outbox rows queued before this change won't have these
            // keys; the proxy treats absent values as null and the server
            // falls back to its existing safeId-based lookup.
            globalId: payload['globalId'] as String?,
            safeGlobalId: payload['safeGlobalId'] as String?,
            costCenterId: payload['costCenterId'] as int?,
            idempotencyKey: idempotencyKey,
          );
        }
        break;

      case 'safe_transfers':
        if (operation == 'insert') {
          await proxy.submitSafeTransfer(
            fromSafeId: (payload['fromSafeId'] ?? payload['from_safe_id']) as int,
            toSafeId: (payload['toSafeId'] ?? payload['to_safe_id']) as int,
            amount: (payload['amount'] as num).toDouble(),
            userId: (payload['userId'] ?? payload['user_id']) as int?,
            description: (payload['description'] ?? payload['notes']) as String?,
            // نفس سبب stock_transfers تحت: /api/safes/transfer بيعمل dedup
            // بالـglobalId ومش بيقرا هيدر الـidempotency.
            globalId: replayGlobalIdFrom(payload),
            idempotencyKey: idempotencyKey,
          );
        }
        break;

      case 'stock_transfers':
        if (operation == 'insert') {
          await proxy.submitStockTransfer(
            fromWarehouseId: (payload['fromWarehouseId'] ?? payload['from_warehouse_id']) as int,
            toWarehouseId: (payload['toWarehouseId'] ?? payload['to_warehouse_id']) as int,
            items: (payload['items'] as List?)
                    ?.cast<Map<String, dynamic>>() ??
                [],
            userId: (payload['userId'] ?? payload['user_id']) as int?,
            notes: (payload['notes'] ?? payload['description']) as String?,
            // بلا ده كانت إعادة الإرسال بعد timeout بتخصم المخزون تاني:
            // السيرفر بيعمل dedup بالـglobalId حصرياً، و/api/inventory/transfer
            // مش بيقرا هيدر الـidempotency فالمفتاح تحت بلا أثر هنا.
            globalId: replayGlobalIdFrom(payload),
            idempotencyKey: idempotencyKey,
          );
        }
        break;

      case 'roles':
        if (operation == 'insert') {
          return proxy.createRole(
            name: payload['name'] as String,
            description: payload['description'] as String?,
            isSystemRole: payload['isSystemRole'] as bool? ?? false,
          );
        }
        break;

      case 'role_permissions':
        // Replay a queued role-permission save. The payload was stored by
        // cwi_sync.setRolePermissions when the server was unreachable; we
        // forward it as-is. The same idempotency key is reused so the
        // server can dedupe a request that succeeded but whose response
        // never reached us.
        if (operation == 'set') {
          await proxy.setRolePermissions(
            payload['roleId'] as int,
            (payload['permissionCodes'] as List).cast<String>(),
            idempotencyKey: idempotencyKey,
            // Spec 136 ISS-15: replay the role identity so an offline-queued
            // save still lets the server resolve/create the role.
            roleGlobalId: payload['roleGlobalId'] as String?,
            roleName: payload['roleName'] as String?,
          );
        }
        break;

      case 'users':
        if (operation == 'insert') {
          return proxy.createUser(
            username: payload['username'] as String,
            password: payload['password'] as String,
            displayName: payload['displayName'] as String,
            roleId: payload['roleId'] as int?,
            branchIds: (payload['branchIds'] as List?)?.cast<int>(),
            globalId: payload['globalId'] as String?,
          );
        } else if (operation == 'update') {
          final id = payload['id'] as int;
          // Three possible shapes from ClientWriteInterceptor: full field update,
          // password-only update, or pin-only update. Dispatch by which key is
          // the sole payload field after stripping 'id'.
          final fields = Map<String, dynamic>.from(payload)..remove('id');
          if (fields.length == 1 && fields.containsKey('password')) {
            await proxy.updateUserPassword(id, fields['password'] as String,
                idempotencyKey: idempotencyKey);
          } else if (fields.length == 1 && fields.containsKey('pin')) {
            await proxy.updateUserPin(id, fields['pin'] as String?,
                idempotencyKey: idempotencyKey);
          } else {
            await proxy.updateUser(id, fields, idempotencyKey: idempotencyKey);
          }
        }
        break;

      case 'regions':
        if (operation == 'insert') {
          return proxy.createRegion(
            name: payload['name'] as String,
            address: payload['address'] as String?,
            phone: payload['phone'] as String?,
            costCenterId: payload['costCenterId'] as int?,
          );
        } else if (operation == 'update') {
          await proxy.updateRegion(
            id: payload['id'] as int,
            name: payload['name'] as String,
            address: payload['address'] as String?,
            phone: payload['phone'] as String?,
            costCenterId: payload['costCenterId'] as int?,
          );
        }
        break;

      case 'party_groups':
        if (operation == 'insert') {
          return proxy.createPartyGroup(payload, idempotencyKey: idempotencyKey);
        } else if (operation == 'update') {
          final id = payload['id'] as int;
          final data = Map<String, dynamic>.from(payload)..remove('id');
          await proxy.updatePartyGroup(id, data, idempotencyKey: idempotencyKey);
        } else if (operation == 'delete') {
          await proxy.deletePartyGroup(payload['id'] as int, idempotencyKey: idempotencyKey);
        }
        break;

      case 'purchase_orders':
        if (operation == 'insert') {
          return proxy.createPurchaseOrder(payload, idempotencyKey: idempotencyKey);
        } else if (operation == 'update') {
          await proxy.updatePurchaseOrderStatus(
            payload['id'] as int,
            payload['status'] as String,
            idempotencyKey: idempotencyKey,
          );
        } else if (operation == 'delete') {
          await proxy.deletePurchaseOrder(payload['id'] as int, idempotencyKey: idempotencyKey);
        }
        break;

      case 'sales_orders':
        if (operation == 'insert') {
          return proxy.createSalesOrder(payload, idempotencyKey: idempotencyKey);
        } else if (operation == 'update') {
          await proxy.updateSalesOrderStatus(
            payload['id'] as int,
            payload['status'] as String,
            idempotencyKey: idempotencyKey,
          );
        } else if (operation == 'delete') {
          await proxy.deleteSalesOrder(payload['id'] as int, idempotencyKey: idempotencyKey);
        }
        break;

      case 'price_lists':
        if (operation == 'insert') {
          return proxy.createPriceList(payload, idempotencyKey: idempotencyKey);
        } else if (operation == 'update') {
          final id = payload['id'] as int;
          final data = Map<String, dynamic>.from(payload)..remove('id');
          await proxy.updatePriceList(id, data, idempotencyKey: idempotencyKey);
        }
        break;

      case 'price_list_items':
        if (operation == 'upsert') {
          await proxy.setPriceListItem(payload, idempotencyKey: idempotencyKey);
        }
        break;

      case 'printers':
        if (operation == 'insert') {
          return proxy.createPrinter(payload, idempotencyKey: idempotencyKey);
        } else if (operation == 'update') {
          final id = payload['id'] as int;
          final data = Map<String, dynamic>.from(payload)..remove('id');
          await proxy.updatePrinter(id, data, idempotencyKey: idempotencyKey);
        } else if (operation == 'delete') {
          await proxy.deletePrinter(payload['id'] as int, idempotencyKey: idempotencyKey);
        }
        break;

      case 'inventory_bonds':
        if (operation == 'insert') {
          return proxy.submitInventoryBond(payload, idempotencyKey: idempotencyKey);
        }
        break;

      // ── Admin / structural tables ────────────────────────────────────────
      // These seven had NO case at all, so every queued operation fell to the
      // `default:` StateError → isPermanentError → markAsSyncDeadLetter. The
      // "retry all" button flips dead-letter rows back to pending with
      // attempts=0, they hit the same StateError, and dead-letter again —
      // an endless loop the admin can never clear. Eighteen enqueue sites
      // across cwi_admin/cwi_catalog/cwi_sync fed it.
      //
      // Every operation below already has a tested method on ServerProxy (the
      // same one the online path calls) and every payload already carries what
      // that method needs, so this is dispatch-table plumbing, not new
      // behaviour. NOTE: mirror mode never reaches here — it throws
      // MirrorOfflineException instead of queueing — so this is a client-mode
      // fix exclusively.

      case 'branches':
        if (operation == 'insert') {
          await proxy.createBranch(payload, idempotencyKey: idempotencyKey);
        } else if (operation == 'update') {
          await proxy.updateBranch(
            payload['id'] as int,
            OfflineSyncWorker._withoutId(payload),
            idempotencyKey: idempotencyKey,
          );
        } else if (operation == 'delete') {
          await proxy.deleteBranch(
            payload['id'] as int,
            reassignUsersToBranchId: payload['reassignUsersToBranchId'] as int?,
            idempotencyKey: idempotencyKey,
          );
        } else {
          throw StateError('Unhandled op $operation for table $table');
        }
        break;

      case 'accounts':
        if (operation == 'insert') {
          await proxy.createAccount(payload, idempotencyKey: idempotencyKey);
        } else if (operation == 'update') {
          await proxy.updateAccount(
            payload['id'] as int,
            OfflineSyncWorker._withoutId(payload),
            idempotencyKey: idempotencyKey,
          );
        } else if (operation == 'delete') {
          await proxy.deleteAccount(payload['id'] as int,
              idempotencyKey: idempotencyKey);
        } else {
          throw StateError('Unhandled op $operation for table $table');
        }
        break;

      case 'account_mappings':
        if (operation == 'upsert') {
          await proxy.setAccountMapping(payload,
              idempotencyKey: idempotencyKey);
        } else if (operation == 'delete') {
          await proxy.deleteAccountMapping(
            purpose: payload['purpose'] as String,
            costCenterId: payload['costCenterId'] as int?,
            idempotencyKey: idempotencyKey,
          );
        } else {
          throw StateError('Unhandled op $operation for table $table');
        }
        break;

      case 'cost_centers':
        if (operation == 'insert') {
          await proxy.createCostCenter(payload, idempotencyKey: idempotencyKey);
        } else if (operation == 'update') {
          await proxy.updateCostCenter(
            payload['id'] as int,
            OfflineSyncWorker._withoutId(payload),
            idempotencyKey: idempotencyKey,
          );
        } else if (operation == 'delete') {
          await proxy.deleteCostCenter(payload['id'] as int,
              idempotencyKey: idempotencyKey);
        } else {
          throw StateError('Unhandled op $operation for table $table');
        }
        break;

      case 'user_region_access':
        if (operation == 'upsert') {
          await proxy.setUserRegionAccess(
            payload['userId'] as int,
            (payload['regionIds'] as List).map((e) => e as int).toList(),
            idempotencyKey: idempotencyKey,
          );
        } else {
          throw StateError('Unhandled op $operation for table $table');
        }
        break;

      case 'warehouses':
        if (operation == 'insert') {
          return proxy.createWarehouse(
            name: payload['name'] as String,
            branchId: payload['branchId'] as int?,
            globalId: payload['globalId'] as String?,
          );
        } else if (operation == 'update') {
          // Three distinct enqueue sites share operation='update' and are
          // told apart by these flags (cwi_catalog setDefault/unsetDefault).
          // Replaying the wrong one silently re-points the POS's default
          // warehouse, so the discrimination has to match the producer.
          if (payload['setDefault'] == true) {
            await proxy.setDefaultWarehouse(payload['id'] as int,
                idempotencyKey: idempotencyKey);
          } else if (payload['unsetDefault'] == true) {
            await proxy.unsetDefaultWarehouse(payload['id'] as int,
                idempotencyKey: idempotencyKey);
          } else {
            await proxy.updateWarehouse(
              payload['id'] as int,
              OfflineSyncWorker._withoutId(payload),
              idempotencyKey: idempotencyKey,
            );
          }
        } else if (operation == 'delete') {
          await proxy.deleteWarehouse(payload['id'] as int,
              idempotencyKey: idempotencyKey);
        } else {
          throw StateError('Unhandled op $operation for table $table');
        }
        break;

      case 'activity_logs':
        if (operation == 'insert') {
          await proxy.pushActivityLog(payload,
              idempotencyKey: idempotencyKey);
        } else {
          throw StateError('Unhandled op $operation for table $table');
        }
        break;

      case 'safes':
        if (operation == 'close') {
          // Spec 135: forward the cached amounts + closeEventGid so a deferred
          // replay re-sends the SAME deterministic closing-JE id and the same
          // split (older entries without these keys replay as null — pre-135
          // behaviour). The DAO's gid guard + balance<=0 check keep replay
          // idempotent.
          await proxy.closeSafe(
            payload['safeId'] as int,
            userId: payload['userId'] as int?,
            cashAmount: (payload['cashAmount'] as num?)?.toDouble(),
            bankAmount: (payload['bankAmount'] as num?)?.toDouble(),
            notes: payload['notes'] as String?,
            closeEventGid: payload['closeEventGid'] as String?,
            idempotencyKey: idempotencyKey,
          );
        } else if (operation == 'insert') {
          await proxy.createSafe(payload, idempotencyKey: idempotencyKey);
        } else if (operation == 'delete') {
          await proxy.deleteSafe(payload['id'] as int,
              idempotencyKey: idempotencyKey);
        } else if (operation == 'update') {
          // ClientWriteInterceptor.submitSetDefaultSafe queues this shape.
          if (payload['isDefault'] == true) {
            await proxy.submitSetDefaultSafe(
              safeId: payload['id'] as int,
              idempotencyKey: idempotencyKey,
            );
          } else {
            // A generic safe edit (rename / bank details / isActive). Falling
            // through to `break` here returned null, which drainOutbox reads
            // as SUCCESS and clears the row — the edit vanished with no
            // dead-letter, no log, no trace. That is strictly worse than the
            // dead-letter loop the seven tables above suffered: at least a
            // dead-letter is visible.
            await proxy.updateSafe(
              payload['id'] as int,
              OfflineSyncWorker._withoutId(payload),
              idempotencyKey: idempotencyKey,
            );
          }
        } else {
          throw StateError('Unhandled op $operation for table $table');
        }
        break;

      default:
        // BLOCKER C-01 (Spec 151) — FAIL-LOUD. Previously this debugPrint'd and
        // returned null, so the drain loop marked the item as a sync SUCCESS
        // and cleared it from the outbox — silently DROPPING the write (an
        // offline journal_entries GL row was the field repro). Throwing routes
        // the item through the permanent-error classifier in drainOutbox →
        // markAsSyncDeadLetter + SYNC-WARN, turning a silent drop into a
        // visible dead-letter the admin can see (and manually retry once a code
        // fix adds the missing case). NEVER return null here.
        throw StateError('Unknown sync table: $table (op=$operation)');
    }
  }
}
