// OfflineSyncWorker - per-table replay dispatch, part 2: financial and operational tables.
part of '../offline_sync_worker.dart';

/// Middle of the `_replayOperation` switch: commercial papers, journals, floor plan, attachments, landed cost, fixed assets, manufacturing, bookings, safe and stock transfers.
extension OfflineSyncWorkerReplayFinance on OfflineSyncWorker {
  Future<dynamic> _replayOperationFinance(
    String table,
    String operation,
    Map<String, dynamic> payload,
    ServerProxy proxy,
    String idempotencyKey,
  ) async {
    switch (table) {
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

      // Audit B DATA-001 — full snapshot, idempotent by global id.
      case 'table_reservations':
        if (operation == 'upsert') {
          return proxy.submitTableReservation(
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

      default:
        return _replayOperationAdmin(
            table, operation, payload, proxy, idempotencyKey);
    }
  }
}
