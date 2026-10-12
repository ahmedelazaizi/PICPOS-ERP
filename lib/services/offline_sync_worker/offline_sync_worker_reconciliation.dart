// OfflineSyncWorker - id-mapping reconciliation helpers.
part of '../offline_sync_worker.dart';

/// Product pre-flight push, id-mapping load/save and payload mapping of [OfflineSyncWorker].
extension OfflineSyncWorkerReconciliation on OfflineSyncWorker {
  // ═══════════════════════════════════════════════════════════════════════════
  // RECONCILIATION MAPPING LOGIC
  // ═══════════════════════════════════════════════════════════════════════════

  /// Pre-flight: for every `productId` referenced in a sale/return payload,
  /// make sure we either have a server mapping OR can push the product now.
  ///
  /// This plugs a race that produces FK 23503 errors on the server:
  ///   - User creates product on client with local id X.
  ///   - Client-mode detection briefly off → no outbox row queued.
  ///   - User creates a sale referencing product X.
  ///   - Sale goes into the outbox.
  ///   - Drain replays the sale → server sees productId X which never
  ///     arrived → foreign-key violation → dead-letter loop.
  ///
  /// Recovery: when we see an unmapped productId, look up the local
  /// product row, POST it via `createProduct` immediately (out of
  /// queue order), capture the server id, and inject the mapping so
  /// the re-applied payload sends the correct id to the server.
  Future<void> _ensureProductsMappedOrPushed(
    List? items,
    Map<String, Map<String, int>> mappedIds, {
    required ServerProxy proxy,
    required int outboxId,
  }) async {
    if (items == null || items.isEmpty) return;
    if (_db == null) return;

    final productMap = mappedIds.putIfAbsent('products', () => {});

    for (final raw in items) {
      final item = raw is Map ? raw : null;
      if (item == null) continue;
      final rawPid = item['productId'] ?? item['product_id'];
      if (rawPid == null) continue;
      final localIdStr = rawPid.toString();

      // Already mapped OR the value is itself already a server id we've
      // captured from a previous drain → nothing to do.
      if (productMap.containsKey(localIdStr)) continue;
      if (productMap.values.contains(rawPid is int ? rawPid : int.tryParse(localIdStr))) continue;

      // Not mapped — look up the local product and push it now.
      try {
        final localId = int.tryParse(localIdStr);
        if (localId == null) continue;
        final product = await _db!.getProductById(localId);
        if (product == null) {
          debugPrint('[OfflineSyncWorker] ⚠️ pre-flight: local product $localId missing — sale will '
              'fail server FK check. Skipping product push.');
          continue;
        }

        debugPrint('[OfflineSyncWorker] 🔄 pre-flight: product local=$localId '
            '(code=${product.code}) has no server mapping — pushing now to resolve sale $outboxId');

        // Ensure the local product has a globalId so the server's UUID-based
        // idempotency check in postProduct short-circuits on retries instead
        // of inserting a fresh row each time. Missing globalId was the root
        // cause of duplicate server rows (appearing as productType='product'
        // — displayed as "عام" — because the other metadata was also omitted).
        String? effectiveGlobalId = product.globalId;
        if (effectiveGlobalId == null || effectiveGlobalId.isEmpty) {
          effectiveGlobalId = const Uuid().v7();
          try {
            await (_db!.update(_db!.products)
                  ..where((p) => p.id.equals(localId)))
                .write(ProductsCompanion(globalId: Value(effectiveGlobalId)));
          } catch (e) {
            debugPrint('[OfflineSyncWorker] pre-flight: failed to persist globalId on local product $localId: $e');
          }
        }

        // Mirror the full ClientWriteInterceptor.createProduct payload so the
        // server reconstructs the product exactly — productType, globalId,
        // warehouseId, extended price tiers, and scale metadata must all be
        // present. A partial payload here creates a server row that differs
        // from the client's and appears as a duplicate after the next pull.
        String? categoryGlobalId;
        String? categoryName;
        String? categoryColor;
        if (product.categoryId != null) {
          try {
            final cat = await (_db!.select(_db!.categories)
                  ..where((c) => c.id.equals(product.categoryId!))
                  ..limit(1))
                .getSingleOrNull();
            if (cat != null) {
              categoryGlobalId = cat.globalId;
              categoryName = cat.name;
              categoryColor = cat.color;
              if (categoryGlobalId == null || categoryGlobalId.isEmpty) {
                categoryGlobalId = const Uuid().v7();
                try {
                  await (_db!.update(_db!.categories)
                        ..where((c) => c.id.equals(product.categoryId!)))
                      .write(CategoriesCompanion(globalId: Value(categoryGlobalId)));
                } catch (error, stack) {
      // Mapping failures are recoverable, but must remain diagnosable because
      // stale FK mappings can make a financial replay target the wrong row.
      unawaited(DiagnosticLogger.logError(
        'SYNC-MAPPING',
        'best-effort mapping operation failed',
        error,
        stack,
      ));
    }
              }
            }
          } catch (e) {
            debugPrint('[OfflineSyncWorker] pre-flight: category lookup failed (non-fatal): $e');
          }
        }

        final payload = <String, dynamic>{
          'globalId': effectiveGlobalId,
          'code': product.code,
          'name': product.name,
          'salePrice': product.salePrice,
          'costPrice': product.costPrice,
          'categoryId': product.categoryId,
          'categoryGlobalId': categoryGlobalId,
          'categoryName': categoryName,
          'categoryColor': categoryColor,
          'supplierId': product.supplierId,
          'unitId': product.unitId,
          'currentStock': product.currentStock,
          'barcode': product.barcode,
          'minStock': product.minStock,
          'taxRate': product.taxRate,
          'isSoldByWeight': product.isSoldByWeight,
          'allowNegativeSale': product.allowNegativeSale,
          'trackExpiry': product.trackExpiry,
          'defaultShelfDays': product.defaultShelfDays,
          'alertDaysBefore': product.alertDaysBefore,
          'pricePerUnit': product.pricePerUnit,
          'wholesalePrice': product.wholesalePrice,
          'priceTalabat': product.priceTalabat,
          'priceCareem': product.priceCareem,
          'priceAshyae': product.priceAshyae,
          'scaleType': product.scaleType,
          'scalePluNumber': product.scalePluNumber,
          'productType': product.productType,
          'warehouseId': product.warehouseId,
        };

        final serverId = await proxy.createProduct(
          payload,
          idempotencyKey: 'preflight_prod_${product.code}_$localId',
        );
        if (serverId != null && serverId != 0) {
          productMap[localIdStr] = serverId;
          debugPrint('[OfflineSyncWorker] ✅ pre-flight: product local=$localId → server=$serverId');
        } else {
          debugPrint('[OfflineSyncWorker] ⚠️ pre-flight: createProduct returned null/0 for '
              'local=$localId — sale $outboxId may still 23503');
        }
      } catch (e) {
        final err = e.toString();
        // Conflict = product already exists on server with matching code
        // (e.g. by prior sync). Fetch server id by code so the mapping
        // is captured even though the POST itself "failed".
        if (err.contains('409') ||
            err.contains('Conflict') ||
            err.contains('UNIQUE constraint') ||
            err.contains('already exists') ||
            err.contains('duplicate')) {
          debugPrint('[OfflineSyncWorker] pre-flight: product $localIdStr already on server — '
              'mapping will be resolved server-side on retry');
          continue;
        }
        debugPrint('[OfflineSyncWorker] ⚠️ pre-flight push failed for product $localIdStr: $e');
        // Continue — the sale replay will fail its own FK check and move
        // through the normal error handling (attempt counter / retry).
      }
    }
  }

  Future<Map<String, Map<String, int>>> _loadIdMappings() async {
    if (_db == null) return {};
    // Load from the persistent FK remap table (P2.2)
    try {
      final dbMappings = await _db!.loadAllFkMappings();
      if (dbMappings.isNotEmpty) return dbMappings;
    } catch (error, stack) {
      // Mapping failures are recoverable, but must remain diagnosable because
      // stale FK mappings can make a financial replay target the wrong row.
      unawaited(DiagnosticLogger.logError(
        'SYNC-MAPPING',
        'best-effort mapping operation failed',
        error,
        stack,
      ));
    }
    // Fallback: migrate one-time from the legacy JSON blob in settings
    try {
      final jsonStr = await _db!.getSettingValue('_sync_id_mappings');
      if (jsonStr != null && jsonStr.isNotEmpty) {
        final legacy = await compute(_decodeMappingsBackground, jsonStr);
        if (legacy.isNotEmpty) {
          await _db!.bulkStoreFkMappings(legacy);
          debugPrint('[OfflineSyncWorker] Migrated ${legacy.length} tables from JSON blob → remote_id_mappings');
        }
        return legacy;
      }
    } catch (error, stack) {
      // Mapping failures are recoverable, but must remain diagnosable because
      // stale FK mappings can make a financial replay target the wrong row.
      unawaited(DiagnosticLogger.logError(
        'SYNC-MAPPING',
        'best-effort mapping operation failed',
        error,
        stack,
      ));
    }
    return {};
  }

  Future<void> _saveIdMappings(Map<String, Map<String, int>> mappings) async {
    if (_db == null || mappings.isEmpty) return;
    try {
      await _db!.bulkStoreFkMappings(mappings);
    } catch (error, stack) {
      // Mapping failures are recoverable, but must remain diagnosable because
      // stale FK mappings can make a financial replay target the wrong row.
      unawaited(DiagnosticLogger.logError(
        'SYNC-MAPPING',
        'best-effort mapping operation failed',
        error,
        stack,
      ));
    }
  }

  /// Enrich a payload with `createdByUsername` so the server can resolve user
  /// IDs by username when client/server auto-increment IDs diverge.
  /// Only adds the field if `userId` is present and `createdByUsername` is absent.
  Future<Map<String, dynamic>> _enrichWithUsername(Map<String, dynamic> payload) async {
    if (_db == null) return payload;
    final userId = payload['userId'];
    if (userId == null || payload.containsKey('createdByUsername')) return payload;
    try {
      final uid = userId is int ? userId : int.tryParse(userId.toString());
      if (uid == null || uid == 0) return payload;
      final user = await _db!.getUserById(uid);
      if (user != null) {
        final enriched = Map<String, dynamic>.from(payload);
        enriched['createdByUsername'] = user.user.username;
        return enriched;
      }
    } catch (error, stack) {
      // Mapping failures are recoverable, but must remain diagnosable because
      // stale FK mappings can make a financial replay target the wrong row.
      unawaited(DiagnosticLogger.logError(
        'SYNC-MAPPING',
        'best-effort mapping operation failed',
        error,
        stack,
      ));
    }
    return payload;
  }

  Map<String, dynamic> _applyIdMappings(String table, Map<String, dynamic> payload, Map<String, Map<String, int>> mappings) {
    if (mappings.isEmpty) return payload;
    final p = Map<String, dynamic>.from(payload);

    // Sales and Returns mapping
    if (['sales', 'sales_returns', 'held_orders'].contains(table)) {
      if (p['customerId'] != null && mappings['parties']?.containsKey(p['customerId'].toString()) == true) {
        p['customerId'] = mappings['parties']![p['customerId'].toString()];
      }
    }
    // Purchases mapping
    if (['purchases', 'purchase_invoices'].contains(table)) {
      if (p['supplierId'] != null && mappings['parties']?.containsKey(p['supplierId'].toString()) == true) {
        p['supplierId'] = mappings['parties']![p['supplierId'].toString()];
      }
      if (p['supplier_id'] != null && mappings['parties']?.containsKey(p['supplier_id'].toString()) == true) {
        p['supplier_id'] = mappings['parties']![p['supplier_id'].toString()];
      }
    }
    // Items Mapping
    if (p['items'] is List) {
      final items = (p['items'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      for (var item in items) {
        if (item['productId'] != null && mappings['products']?.containsKey(item['productId'].toString()) == true) {
          item['productId'] = mappings['products']![item['productId'].toString()];
        }
        if (item['product_id'] != null && mappings['products']?.containsKey(item['product_id'].toString()) == true) {
          item['product_id'] = mappings['products']![item['product_id'].toString()];
        }
      }
      p['items'] = items;
    }
      if (p['partyId'] != null && mappings['parties']?.containsKey(p['partyId'].toString()) == true) {
        p['partyId'] = mappings['parties']![p['partyId'].toString()];
      }
    // Product Unit & Barcode mapping (needs productId)
    if (['product_units', 'product_barcodes', 'warehouse_prices'].contains(table)) {
      if (p['productId'] != null && mappings['products']?.containsKey(p['productId'].toString()) == true) {
        p['productId'] = mappings['products']![p['productId'].toString()];
      }
      if (p['product_id'] != null && mappings['products']?.containsKey(p['product_id'].toString()) == true) {
        p['product_id'] = mappings['products']![p['product_id'].toString()];
      }
    }

    // ── Self-id remap (update/delete ops on client-originated records) ──
    // If an earlier outbox entry inserted this record and received a server id,
    // subsequent update/delete ops must target the server id, not the local one.
    if (p['id'] != null && mappings[table]?.containsKey(p['id'].toString()) == true) {
      p['id'] = mappings[table]![p['id'].toString()];
    }

    // ── Shift close: shiftId references a previously-opened local shift ──
    if (table == 'shifts' && p['shiftId'] != null &&
        mappings['shifts']?.containsKey(p['shiftId'].toString()) == true) {
      p['shiftId'] = mappings['shifts']![p['shiftId'].toString()];
    }

    // ── referenceType/referenceId — journals + safe_transactions ──
    // Translate referenceType → the outbox case-name that owned the mapping.
    // C-01: producers queue JEs under 'journal_entries' (not the dead
    // 'journals'), so include it here or an offline JE's referenceId never
    // gets remapped to the server id.
    if (['journals', 'journal_entries', 'safe_transactions'].contains(table)) {
      final refType = (p['referenceType'] ?? p['reference_type']) as String?;
      final refIdRaw = p['referenceId'] ?? p['reference_id'];
      const refTypeToCaseName = <String, String>{
        'sales_invoice': 'sales',
        'purchase_invoice': 'purchases',
        'sales_return': 'sales_returns',
        'purchase_return': 'purchase_returns',
        'shift_closing': 'shifts',
      };
      if (refType != null && refIdRaw != null) {
        final caseName = refTypeToCaseName[refType];
        if (caseName != null &&
            mappings[caseName]?.containsKey(refIdRaw.toString()) == true) {
          final remoteId = mappings[caseName]![refIdRaw.toString()];
          if (p.containsKey('referenceId')) p['referenceId'] = remoteId;
          if (p.containsKey('reference_id')) p['reference_id'] = remoteId;
        }
      }
    }

    return p;
  }
}
