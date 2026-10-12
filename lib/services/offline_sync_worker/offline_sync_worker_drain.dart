// OfflineSyncWorker - outbox drain loop.
part of '../offline_sync_worker.dart';

/// Outbox drain loop of [OfflineSyncWorker] (`drainOutbox`).
extension OfflineSyncWorkerDrain on OfflineSyncWorker {
  /// Drain all pending outbox items by replaying them via ServerProxy.
  /// Called when WebSocket reconnects, HTTP polling succeeds, or manually.
  /// Set [force] to true to skip the WebSocket connectivity check
  /// (used by the periodic HTTP sync timer).
  Future<void> drainOutbox({bool force = false}) async {
    if (_isDraining || _db == null) return;
    if (!force && !WebSocketSyncClient.instance.connected.value) return;

    _isDraining = true;

    try {
      // Load persistent ID mappings for reconciliation
      final Map<String, Map<String, int>> mappedIds = await _loadIdMappings();

      // CRITICAL: Ensure we have a valid API token before sending any requests.
      // Without this, all POST calls will fail with 401 Unauthorized.
      final hasToken = await _ensureApiToken();
      if (!hasToken) {
        debugPrint('[OfflineSyncWorker] ❌ Cannot drain: no API token (server unreachable)');
        _scheduleRetry();
        return;
      }
      _retryAttempts = 0; // server reachable — reset backoff

      // Server IS reachable (token fetch succeeded) — reset any permanently
      // failed items so they get a fresh chance to sync.
      final resetCount = await _db!.resetFailedSyncItems();
      if (resetCount > 0) {
        debugPrint('[OfflineSyncWorker] ♻️ Reset $resetCount permanently failed items back to pending');
      }

      // Check if there are pending items
      final pendingCheck = await _db!.getPendingSyncItems(limit: 1);
      if (pendingCheck.isEmpty) {
        debugPrint('[OfflineSyncWorker] ✅ No pending items in outbox');
        return;
      }

      debugPrint('[OfflineSyncWorker] Starting outbox drain...');
      int synced = 0;
      int failed = 0;
      bool mappingsUpdated = false;

      while (true) {
        // Issue 7 — bumped batch from 50 → 200 so a backed-up outbox
        // (e.g. 1000 pending operations after a long offline window)
        // drains in 5 iterations instead of 20. Each item is still
        // sent serially within an iteration to preserve ordering.
        final items = await _db!.getPendingSyncItems(limit: 200);
        if (items.isEmpty) break;

        for (final item in items) {
          try {
            final originalPayload =
                jsonDecode(item.payload) as Map<String, dynamic>;

            // Reconcile IDs locally before sending to server
            final mappedPayload = _applyIdMappings(item.targetTable, originalPayload, mappedIds);

            // CRITICAL PRE-FLIGHT: for sales/returns/held-orders, ensure
            // every product referenced in the items list has a server-
            // side mapping. If not, push the product FIRST (out of
            // order) so the sale doesn't fail with FK 23503 on
            // sales_invoice_items.products_id.
            //
            // Root cause of the regression this guards against: a
            // client-mode detection race at product-create time. If
            // `SyncInterceptor.isClientMode` briefly returned false
            // during startup, `ClientWriteInterceptor.createProduct`
            // early-returned without queueing anything, so the product
            // only existed locally. Sales created later referenced
            // those local product ids that the server never heard of
            // → every drain attempt hit 23503 forever and the 4 failed
            // rows the user showed in the sync dialog piled up until
            // they dead-lettered.
            if (['sales', 'sales_returns', 'held_orders'].contains(item.targetTable)) {
              await _ensureProductsMappedOrPushed(
                mappedPayload['items'] as List?,
                mappedIds,
                proxy: ServerProxy.instance,
                outboxId: item.id,
              );
            }

            // Re-apply mappings AFTER the pre-flight resolved any new
            // ids (the list was mutated in place; items field may now
            // carry server ids).
            final reMappedPayload = _applyIdMappings(item.targetTable, mappedPayload, mappedIds);

            // Enrich payload: add createdByUsername so server can resolve
            // user IDs by username when client/server IDs diverge.
            final enrichedPayload = await _enrichWithUsername(reMappedPayload);

            final dynamic result = await _replayOperation(
              item.targetTable,
              item.operation,
              enrichedPayload,
              item.id,
            );

            // Capture new Server IDs to map dependent entities
            final int? serverId = result is int
                ? result
                : result is Map
                    ? ((result['serverId'] as int?) ?? (result['id'] as int?))
                    : null;
            if (serverId != null) {
                // Resolve the local ID either from `item.recordId` or by querying name/code
                int? localId;
                    if (item.targetTable == 'parties') {
                        final p = await _db!.getPartyByName(originalPayload['name']?.toString() ?? '', false);
                        localId = p?.id;
                    } else if (item.targetTable == 'products') {
                        final pItem = await _db!.getProductByCode(originalPayload['code']?.toString() ?? '');
                        localId = pItem?.id;
                    } else if (item.targetTable == 'units') {
                        // Resolve unit localId by name and symbol
                        final u = await _db!.customSelect(
                            'SELECT id FROM units WHERE name = ? AND symbol = ? LIMIT 1',
                            variables: [
                                Variable<String>(originalPayload['name']?.toString() ?? ''),
                                Variable<String>(originalPayload['symbol']?.toString() ?? ''),
                            ],
                        ).getSingleOrNull();
                        localId = u?.read<int>('id');
                    } else if (item.recordId != '0') {
                        localId = int.tryParse(item.recordId);
                    }

                    if (localId != null) {
                        mappedIds[item.targetTable] ??= {};
                        mappedIds[item.targetTable]![localId.toString()] = serverId;
                        mappingsUpdated = true;
                        debugPrint('[OfflineSyncWorker] 🔗 Mapped ${item.targetTable} Local ID $localId -> Server ID $serverId');
                        // Persist immediately to the relational FK remap table (P2.2)
                        final gid = originalPayload['globalId'] as String?;
                        unawaited(_db!.storeFkMapping(
                          tableName: item.targetTable,
                          localId: localId,
                          remoteId: serverId,
                          globalId: gid,
                        ));
                    }
                }

            await _db!.markAsSyncSuccess(item.id);
            synced++;
            // Spec 136 — breadcrumb the offline→online recovery of the
            // user-visible transactional rows. Success was previously
            // print-only, so a sale made offline showed only its
            // "⏳ queued offline" line and never a confirmation that it
            // reached the server — it looked like the invoice vanished. This
            // closes the loop in the login log (queued → drained → serverId).
            // Spec 136 item 6 — widened to every user-visible money/stock
            // outbox type so safes (safe_transactions/safe_transfers),
            // receipt + payment vouchers (receipts/expenses), inventory
            // adjustments and stock transfers also confirm in the login log
            // (item.operation already distinguishes e.g. safes/close vs
            // inventory/adjust).
            if (const {
              'sales', 'sales_returns', 'held_orders', 'purchases',
              'expenses', 'receipts',
              'safe_transactions', 'safe_transfers',
              'inventory', 'stock_transfers',
            }.contains(item.targetTable)) {
              unawaited(DiagnosticLogger.log(
                'OUTBOX-DRAIN',
                '✓ ${item.targetTable}/${item.operation} outboxId=${item.id} '
                '→ serverId=${serverId ?? '-'}',
              ));
            }
            debugPrint(
              '[OfflineSyncWorker] ✅ Synced ${item.targetTable}/${item.operation} #${item.id}',
            );
          } catch (e) {
            final errorStr = e.toString();
            // Distinguish between network errors and real server errors
            final isNetworkError =
                errorStr.contains('SocketException') ||
                errorStr.contains('Connection refused') ||
                errorStr.contains('Connection reset') ||
                errorStr.contains('TimeoutException') ||
                errorStr.contains('HandshakeException');

            if (isNetworkError) {
              // Network error — DON'T burn retry attempts, just pause and retry later
              debugPrint('[OfflineSyncWorker] ⚠️ Network error on item #${item.id} — pausing drain');
              _scheduleRetry();
              return;
            }

            // 429 Rate limited — DON'T burn retry attempts, wait for the rate-limit window.
            final isRateLimited =
                errorStr.contains('429') ||
                errorStr.contains('Too many requests') ||
                errorStr.contains('rate limit');

            if (isRateLimited) {
              // Extract retryAfterSeconds from the server response if present.
              int waitSecs = 65; // default: slightly more than the 60s window
              final match = RegExp(r'retryAfterSeconds[":]+\s*(\d+)').firstMatch(errorStr);
              if (match != null) waitSecs = (int.tryParse(match.group(1) ?? '') ?? 60) + 5;
              debugPrint('[OfflineSyncWorker] ⏳ Rate limited (429) on item #${item.id} — pausing ${waitSecs}s');
              _retryTimer?.cancel();
              _retryTimer = Timer(Duration(seconds: waitSecs), () => drainOutbox(force: true));
              return;
            }

            // 401 Unauthorized — token expired or invalidated since drain started.
            // Force re-verify on next cycle so a fresh token is obtained before retry.
            final isUnauthorized =
                errorStr.contains('401') ||
                errorStr.toLowerCase().contains('unauthorized') ||
                errorStr.contains('Invalid token') ||
                errorStr.contains('Expired token');

            if (isUnauthorized) {
              _tokenVerifiedAt = null; // Force re-verify next cycle
              // Spec 151 (P1-8) — a 401 may mean the signed session token
              // expired/was rejected. Evict it (keeping the in-memory proof)
              // so the next _ensureApiToken → ensureSession re-mints a fresh
              // one before the retry.
              ServerProxy.instance.invalidateSessionToken();
              debugPrint('[OfflineSyncWorker] 🔑 401 on item #${item.id} — token may be expired, scheduling re-verify');
              _scheduleRetry();
              return;
            }

            // البند 5: a BUSINESS conflict (different data under the same
            // business key) must NOT be folded into success — that would drop
            // the operator's invoice silently. Dead-letter it so it appears in
            // the sync-failures UI with the server's Arabic reason.
            if (isTerminalBusinessConflict(errorStr)) {
              failed++;
              await _db!.markAsSyncDeadLetter(item.id, errorStr);
              lastDeadLetterEvent.value = DeadLetterEvent(
                table: item.targetTable,
                operation: item.operation,
                reason: errorStr,
                timestamp: DateTime.now(),
              );
              debugPrint('[OfflineSyncWorker] ⛔ Business conflict on item #${item.id} '
                  '— dead-lettered, operator action required: $errorStr');
              unawaited(DiagnosticLogger.log('SYNC-WARN',
                  '⛔ BUSINESS-CONFLICT table=${item.targetTable} '
                  'op=${item.operation} id=${item.id} reason=$errorStr'));
              continue;
            }

            // 409 Conflict or duplicate — data already exists on server.
            // Mark as synced (not failed) to prevent infinite retries.
            final isConflict =
                errorStr.contains('409') ||
                errorStr.contains('Conflict') ||
                errorStr.contains('UNIQUE constraint') ||
                errorStr.contains('duplicate') ||
                errorStr.contains('already exists');

            if (isConflict) {
              final serverPayload = _serverPayloadFromConflict(errorStr);
              if (kFinancialSyncTables.contains(item.targetTable)) {
                try {
                  await _db!.into(_db!.syncConflictLog).insert(
                    SyncConflictLogCompanion.insert(
                      conflictTable: item.targetTable,
                      recordId: item.recordId,
                      resolution: 'pending_review',
                      clientPayload: item.payload,
                      serverPayload: Value(
                        serverPayload == null ? null : jsonEncode(serverPayload),
                      ),
                      reason: Value(
                        'بيانات مالية متعارضة؛ بقيت العملية معلقة للمراجعة: '
                        '${errorStr.substring(0, errorStr.length.clamp(0, 200))}',
                      ),
                      clientId: const Value(null),
                    ),
                  );
                } catch (error, stack) {
                  await DiagnosticLogger.logError(
                    'SYNC-CONFLICT',
                    'financial outbox conflict log failed for ${item.targetTable}/${item.recordId}',
                    error,
                    stack,
                  );
                }
                await DiagnosticLogger.log(
                  'SYNC-CONFLICT',
                  'financial outbox conflict pending review table=${item.targetTable} '
                  'record=${item.recordId}',
                );
                continue;
              }

              synced++;
              await _db!.markAsSyncSuccess(item.id);
              // Pull the server's authoritative version so the local row converges
              unawaited(
                DeltaPullService.instance.pullTable(item.targetTable).catchError((Object e) {
                  debugPrint('[OfflineSyncWorker] Delta pull after conflict failed (${item.targetTable}): $e');
                }),
              );
              // Log the conflict for audit
              try {
                await _db!.into(_db!.syncConflictLog).insert(
                  SyncConflictLogCompanion.insert(
                    conflictTable: item.targetTable,
                    recordId: item.recordId,
                    resolution: 'server_wins_pull_triggered',
                    clientPayload: item.payload,
                    serverPayload: Value(
                      serverPayload == null ? null : jsonEncode(serverPayload),
                    ),
                    reason: Value('بيانات موجودة بالفعل على السيرفر: ${errorStr.substring(0, errorStr.length.clamp(0, 200))}'),
                    clientId: const Value(null),
                  ),
                );
              } catch (error, stack) {
                await DiagnosticLogger.logError(
                  'SYNC-CONFLICT',
                  'conflict log insert failed for ${item.targetTable}/${item.recordId}',
                  error,
                  stack,
                );
              }
              debugPrint(
                '[OfflineSyncWorker] ⚠️ Conflict on item #${item.id} (${item.targetTable}) — marked as synced, pulling server state',
              );
              continue;
            }

            // Permanent validation errors — retrying will NEVER help.
            // Immediately dead-letter instead of burning 10 retry attempts.
            // The admin can manually retry from the sync management dialog
            // after fixing the underlying data issue (e.g. re-sync users).
            final isPermanentError =
                errorStr.contains('Strict Mapping Violation') ||
                errorStr.contains('not found on server') ||
                errorStr.contains('Validation Error: Valid userId') ||
                errorStr.contains('Validation Error: Valid warehouseId') ||
                errorStr.contains('Shift not found') ||
                // FIX 2026-04-28: stock validation + invalid items are permanent.
                // Without this, a sale referencing a product the server doesn't
                // have (e.g. local-only product from old build with id 1000000001+)
                // loops forever — the server log filled with 50+ identical
                // "غير متوفر نهائياً" failures for the same POS-2.
                errorStr.contains('غير متوفر نهائياً') ||
                errorStr.contains('item missing productId') ||
                errorStr.contains('Validation Error: item missing') ||
                errorStr.contains('Purchase invoice not found') ||
                // L4 (2026-04-28): cross-branch authorization failures are
                // permanent — retrying with the same branch/warehouse pair
                // will never succeed. Admin must fix the device pairing or
                // warehouse assignment before retrying.
                errorStr.contains('Authorization Error') ||
                errorStr.contains('Cross-branch operation denied') ||
                // A permission denial is permanent FOR THIS ACTOR — the same
                // payload replayed by the same user always fails. Without
                // this it burned all 10 attempts against the server before
                // dead-lettering. Covers both denial shapes:
                //   • ApiUserCtx.requirePermission → 403 "User #N lacks
                //     permission: <code>"
                //   • PermissionEnforcer.requireCriticalOp → 403 with an
                //     Arabic reason; every one of those messages contains
                //     "لا تملك صلاحية" or "يلزم صلاحية".
                // Recovery once an admin grants the permission is the
                // existing "إعادة محاولة الكل" button, which resets
                // dead-letter rows to pending (retryAllDeadLetterItems).
                errorStr.contains('lacks permission') ||
                errorStr.contains('لا تملك صلاحية') ||
                errorStr.contains('يلزم صلاحية') ||
                // Spec 136 (field 2026-06-04): an unbalanced journal entry
                // (debit ≠ credit beyond the balance tolerance — 0.01 since
                // Spec 139) is a
                // data/logic defect in the invoice itself — replaying the
                // identical payload will ALWAYS fail. Without this, invoice
                // AQ-POS-1 retried up to _maxSyncAttempts (10) and EACH
                // attempt inserted+rolled back a sale on the server, churning
                // the invoice sequence and flooding the log with ~40 identical
                // failures. Dead-letter immediately; the GL fix
                // (autoPostCashSale/CreditSale discount derivation) prevents
                // the imbalance for new sales, this caps any residual poison.
                errorStr.contains('خطأ في قيد اليومية') ||
                errorStr.contains('لا يساوي الدائن') ||
                // Spec 136 (field 2026-06-14): selling a product from the wrong
                // warehouse (it lives only in another warehouse) is permanent —
                // the payload's warehouseId never changes on replay, so it
                // looped ~40× in the server log (QRS-POS-6). Dead-letter it; the
                // operator must re-issue from the correct warehouse.
                errorStr.contains('خاص بمستودع آخر') ||
                errorStr.contains('اختر المستودع الصحيح') ||
                // BLOCKER C-01 (Spec 151): an unknown sync table (thrown by the
                // switch `default:` in _replayOperation) is a permanent dispatch
                // defect — no code path exists to replay it, so retrying is
                // pointless. Dead-letter immediately so the drop is surfaced in
                // the SYNC-WARN log instead of being silently marked synced.
                errorStr.contains('Unknown sync table');

            if (isPermanentError) {
              failed++;
              await _db!.markAsSyncDeadLetter(item.id, errorStr);
              lastDeadLetterEvent.value = DeadLetterEvent(
                table: item.targetTable,
                operation: item.operation,
                reason: errorStr,
                timestamp: DateTime.now(),
              );
              debugPrint(
                '[OfflineSyncWorker] 🚫 Permanent validation error on item #${item.id} — immediately dead-lettered (manual retry needed): $e',
              );
              // Surface in persistent diagnostic log so the operator can
              // identify exactly which invoices/operations were dropped.
              unawaited(DiagnosticLogger.log('SYNC-WARN',
                  '🚫 DEAD-LETTER table=${item.targetTable} op=${item.operation} '
                  'id=${item.id} reason=$errorStr'));
              continue;
            }

            // Server/logic error — increment attempts
            failed++;
            debugPrint(
              '[OfflineSyncWorker] ❌ Server error item #${item.id} (attempt ${item.attempts + 1}): $e',
            );
            if (item.attempts >= OfflineSyncWorker._maxSyncAttempts) {
              await _db!.markAsSyncDeadLetter(item.id, errorStr);
              lastDeadLetterEvent.value = DeadLetterEvent(
                table: item.targetTable,
                operation: item.operation,
                reason: errorStr,
                timestamp: DateTime.now(),
              );
              debugPrint('[OfflineSyncWorker] 🚫 Item #${item.id} moved to dead_letter after ${item.attempts + 1} attempts');
              unawaited(DiagnosticLogger.log('SYNC-WARN',
                  '🚫 DEAD-LETTER table=${item.targetTable} op=${item.operation} '
                  'id=${item.id} attempts=${item.attempts + 1} reason=$errorStr'));
            } else {
              await _db!.markAsSyncFailed(item.id, errorStr);
            }
          }
        }
      }

      // Save ID mappings to SQLite settings for safety if we stopped early
      if (mappingsUpdated) {
        await _saveIdMappings(mappedIds);
      }

      if (failed == 0) _retryAttempts = 0;
      debugPrint('[OfflineSyncWorker] Outbox drain complete: $synced synced, $failed failed');
      // Spec 136 — one summary line per productive drain so the operator can
      // see, in the login log, that the offline queue was flushed (and how many
      // remain) instead of inferring it from silence.
      if (synced > 0 || failed > 0) {
        final remaining = await _db!.getPendingSyncItems(limit: 1);
        unawaited(DiagnosticLogger.log(
          'OUTBOX-DRAIN',
          'cycle complete synced=$synced failed=$failed '
          'remaining=${remaining.isEmpty ? 0 : '1+'}',
        ));
      }
      // Pull server changes back — but ONLY when this drain actually pushed
      // something. `pullAll()` is 41 sequential HTTP round-trips; firing it
      // unconditionally meant every drain cycle, including the ones that
      // pushed nothing because the batch was all failures, cost the server
      // another 41 requests. Combined with the watch-stream retry loop above,
      // a single stuck outbox row generated hundreds of pulls per minute from
      // one client. A drain that synced nothing has, by definition, no new
      // server-side result to fetch.
      if (synced > 0) {
        unawaited(DeltaPullService.instance.pullAll());
      }
    } catch (e) {
      debugPrint('[OfflineSyncWorker] Drain error: $e');
      _scheduleRetry();
    } finally {
      _isDraining = false;
    }
  }
}
