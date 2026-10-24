// ═══════════════════════════════════════════════════════════════════════════
// API PRODUCT HANDLER — CRUD for Products
// ═══════════════════════════════════════════════════════════════════════════
//
// Extracted from ApiDataHandler for maintainability (PIR C-01).

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shelf/shelf.dart';
import 'api_errors.dart';
import 'package:drift/drift.dart';
import '../../core/permissions/permission_codes.dart';
import '../../core/utils/uuid_v7.dart';
import '../../core/tax/tax_rate_policy.dart';
import '../../data/database/database.dart';
import 'api_user_context.dart';
import 'api_handler_base.dart';

/// Handles product CRUD API endpoints.
class ApiProductHandler extends ApiHandlerBase {
  ApiProductHandler(super.db, super.wsClients);

  // ═══════════════════════════════════════════════════════════════
  // Products
  // ═══════════════════════════════════════════════════════════════

  /// البند 4 — يتحقّق من نسبة الضريبة عند حدّ الكتابة على الخادم.
  ///
  /// A UI-only dropdown is not enough: this endpoint is also reachable from a
  /// mirror, an outbox replay and any crafted request, and the Excel importer
  /// is a third ingress. Returns null when the payload omits `taxRate` (leaves
  /// the existing/default value alone); throws [ArgumentError] on an illegal
  /// rate, which the handler maps to 400.
  double? _validatedTaxRate(dynamic raw) {
    final parsed = parseDoubleNullable(raw);
    if (parsed == null) return null;
    TaxRatePolicy.assertAllowed(parsed);
    return parsed;
  }

  Future<Response> postProduct(Request request) async {
    try {
      // Spec 077 Batch 3 (Spec 060 Phase 2): per-user permission gate.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.productsAdd);
      if (perm != null) return perm;

      return await ApiHandlerBase.withBroadcast<Response>(
        endpointLabel: 'postProduct',
        // Maximum declared set: opening_stock>0 branch touches inventory +
        // stock_movements via adjustStock; categories aren't mutated here
        // (caller passes an existing categoryId), so not declared.
        tables: const {
          'products', 'product_barcodes', 'product_units',
          'inventory', 'stock_movements',
        },
        body: () async {
      final data =
          json.decode(await request.readAsString()) as Map<String, dynamic>;

      // ── UUID-First idempotency (Phase 1) ──
      // If the client supplied a `globalId`, look for an existing row with
      // that UUID BEFORE inserting. Same globalId = same logical record
      // across client and server, so a retry that landed at the server
      // twice (flaky network, offline drain replay, etc.) must resolve
      // to the same serverId instead of creating a duplicate product.
      final incomingGlobalId = data['globalId'] as String?;
      if (incomingGlobalId != null && incomingGlobalId.isNotEmpty) {
        final existing = await (db.select(db.products)
              ..where((p) => p.globalId.equals(incomingGlobalId))
              ..limit(1))
            .getSingleOrNull();
        if (existing != null) {
          debugPrint('[API] postProduct: globalId=$incomingGlobalId already '
              'exists as serverId=${existing.id} — returning idempotent result');
          return jsonResponse({'success': true, 'serverId': existing.id});
        }
      }

      // ── Code / barcode fallback idempotency ──
      // The pre-flight in OfflineSyncWorker mints a fresh UUID when the
      // local product row has no globalId. If the server already has the
      // logical product under a DIFFERENT UUID (e.g. it was originally
      // created on the server and pulled later, or came from an older
      // build), a UUID-only check would miss it and the server would
      // insert a DUPLICATE row (type='product' default, zero stock). The
      // fresh duplicate is then what the sale references — blowing up
      // with "الصنف غير متوفر نهائياً فى المستودع" on every subsequent
      // attempt. Treat same `code` (or `barcode`) as same logical product.
      // When found, adopt the incoming globalId so future pushes resolve
      // via the fast UUID path above.
      final incomingCode = (data['code'] as String?)?.trim();
      final incomingBarcode = (data['barcode'] as String?)?.trim();
      Product? existingByNaturalKey;
      if (incomingCode != null && incomingCode.isNotEmpty) {
        existingByNaturalKey = await (db.select(db.products)
              ..where((p) => p.code.equals(incomingCode))
              ..limit(1))
            .getSingleOrNull();
      }
      if (existingByNaturalKey == null &&
          incomingBarcode != null &&
          incomingBarcode.isNotEmpty) {
        existingByNaturalKey = await (db.select(db.products)
              ..where((p) => p.barcode.equals(incomingBarcode))
              ..limit(1))
            .getSingleOrNull();
      }
      if (existingByNaturalKey != null) {
        final existingGid = existingByNaturalKey.globalId;
        final hasExistingGid = existingGid != null && existingGid.isNotEmpty;
        final hasIncomingGid =
            incomingGlobalId != null && incomingGlobalId.isNotEmpty;

        // Conflict: a different product already owns this code/barcode.
        // (`hasExistingGid` AND incoming UUID differs ⇒ the operator
        // typed a code/barcode that belongs to another logical product.)
        // Reject with 409 instead of silently merging the two products
        // — the previous behaviour returned the existing serverId, so
        // the operator's "new" product invisibly became an alias of an
        // unrelated row, then later edits cross-contaminated stock and
        // pricing (user report: code/barcode must be unique per product).
        if (hasExistingGid && hasIncomingGid && existingGid != incomingGlobalId) {
          final field = (incomingCode != null &&
                  incomingCode.isNotEmpty &&
                  existingByNaturalKey.code == incomingCode)
              ? 'الكود'
              : 'الباركود';
          debugPrint('[API] postProduct REJECTED: $field "$incomingCode/$incomingBarcode" '
              'already used by serverId=${existingByNaturalKey.id} '
              '(existing globalId=$existingGid ≠ incoming=$incomingGlobalId)');
          return Response(
            409,
            body: json.encode({
              'error':
                  'هذا $field مستخدم بالفعل لصنف آخر "${existingByNaturalKey.name}"',
              'code': 'UNIQUE_CONFLICT', // SYNC-005 structured code
              'conflictWithProductId': existingByNaturalKey.id,
              'conflictWithGlobalId': existingGid,
            }),
            headers: {'Content-Type': 'application/json'},
          );
        }

        // Idempotent merge path: existing row has no globalId (legacy
        // data, or was created by an older client without UUID-First),
        // OR the incoming globalId matches the existing one (genuine
        // sync retry). Adopt the incoming UUID if the existing row was
        // bare so future pushes resolve via the fast UUID path above.
        if (!hasExistingGid && hasIncomingGid) {
          try {
            await (db.update(db.products)
                  ..where((p) => p.id.equals(existingByNaturalKey!.id)))
                .write(ProductsCompanion(globalId: Value(incomingGlobalId)));
          } catch (e) {
            debugPrint('[API] postProduct: failed to adopt globalId on '
                'existing product #${existingByNaturalKey.id}: $e');
          }
        }
        debugPrint('[API] postProduct: code="$incomingCode" '
            'barcode="$incomingBarcode" already exists as '
            'serverId=${existingByNaturalKey.id} — returning idempotent '
            'result (no duplicate INSERT)');
        return jsonResponse({'success': true, 'serverId': existingByNaturalKey.id});
      }

      // ── Resolve warehouseId against the server's warehouses table ──
      // The client's local DB may have a warehouseId that doesn't exist on
      // this server (e.g. the user was previously on a different install).
      // Inserting that id raises a FK constraint and the whole product
      // creation fails. Fallback: if the client's id isn't valid, use the
      // server's first available warehouse (id=1 by convention), or null.
      int? resolvedWarehouseId = parseIntNullable(data['warehouseId']);
      if (resolvedWarehouseId != null) {
        final whExists = await (db.select(db.warehouses)
              ..where((w) => w.id.equals(resolvedWarehouseId!))
              ..limit(1))
            .getSingleOrNull();
        if (whExists == null) {
          debugPrint('[API] postProduct: warehouseId=$resolvedWarehouseId '
              'not found on server — falling back');
          final fallback = await (db.select(db.warehouses)
                ..where((w) => w.isActive.equals(true))
                ..limit(1))
              .getSingleOrNull();
          resolvedWarehouseId = fallback?.id;
        }
      }

      // ── Resolve categoryId: prefer globalId (UUID), fall back to int id ──
      //
      // Root cause of "23503 products_category_id_fkey" on client→server
      // sync: the client ships its LOCAL category id, but the server's
      // categories table has different auto-increment ids. A bulk Excel
      // import creates categories locally (via getOrCreateCategory at
      // the DAO level, which bypasses ClientWriteInterceptor), so the
      // server never sees them. Every product then failed FK.
      //
      // Fix:
      //   1. If payload includes `categoryGlobalId`, resolve by UUID.
      //      If the UUID is new, AUTO-CREATE the category row so the
      //      product has a valid FK. The category persists with that
      //      UUID, so future products from any client resolve cleanly.
      //   2. Else if `categoryId` (int) exists on the server, use it.
      //   3. Else NULL — categoryId is nullable in the schema, so the
      //      product still inserts. Operator can re-categorise later.
      int? resolvedCategoryId;
      final incomingCategoryGlobalId = data['categoryGlobalId'] as String?;
      if (incomingCategoryGlobalId != null && incomingCategoryGlobalId.isNotEmpty) {
        final existingCat = await (db.select(db.categories)
              ..where((c) => c.globalId.equals(incomingCategoryGlobalId))
              ..limit(1))
            .getSingleOrNull();
        if (existingCat != null) {
          resolvedCategoryId = existingCat.id;
        } else {
          try {
            final catName =
                (data['categoryName'] as String?)?.trim().isNotEmpty == true
                    ? data['categoryName'] as String
                    : 'تصنيف مستورد';
            final newCatId = await db.into(db.categories).insert(
                  CategoriesCompanion.insert(
                    name: catName,
                    color: Value((data['categoryColor'] as String?) ?? '#2563EB'),
                    globalId: Value(incomingCategoryGlobalId),
                    isActive: const Value(true),
                  ),
                );
            resolvedCategoryId = newCatId;
            debugPrint('[API] postProduct: auto-created category '
                '"$catName" globalId=$incomingCategoryGlobalId serverId=$newCatId');
          } catch (e) {
            debugPrint('[API] postProduct: category auto-create failed '
                '$incomingCategoryGlobalId — leaving NULL: $e');
          }
        }
      }
      if (resolvedCategoryId == null) {
        final rawCatId = parseIntNullable(data['categoryId']);
        if (rawCatId != null) {
          final catExists = await (db.select(db.categories)
                ..where((c) => c.id.equals(rawCatId))
                ..limit(1))
              .getSingleOrNull();
          if (catExists != null) {
            resolvedCategoryId = rawCatId;
          } else {
            debugPrint('[API] postProduct: categoryId=$rawCatId '
                'not found on server and no globalId — leaving NULL');
          }
        }
      }

      // ── Resolve unitId the same way (FK also nullable) ──
      int? resolvedUnitId = parseIntNullable(data['unitId']);
      if (resolvedUnitId != null) {
        final unitExists = await (db.select(db.units)
              ..where((u) => u.id.equals(resolvedUnitId!))
              ..limit(1))
            .getSingleOrNull();
        if (unitExists == null) {
          debugPrint('[API] postProduct: unitId=$resolvedUnitId '
              'not found on server — leaving NULL');
          resolvedUnitId = null;
        }
      }

      // Defense-in-depth: any client that sends `currentStock > 0` on the
      // product payload must ALSO get an `inventory_balances` row or
      // subsequent sales blow up with "الصنف غير متوفر نهائياً فى المستودع".
      // The modern client path (Excel import + add_product_dialog) now sends
      // `currentStock: 0` and a separate `adjustStock(opening_stock)` call,
      // but legacy clients/builds may still post a non-zero currentStock.
      // So: zero-out currentStock on the INSERT, then route the opening
      // balance through the canonical `db.adjustStock(opening_stock)` below.
      final openingStockValue = parseDoubleNullable(data['currentStock']) ?? 0;

      final id = await db.insertProduct(
        ProductsCompanion(
          // UUID-First: persist the client-supplied globalId so subsequent
          // retries short-circuit in the block above instead of falling
          // through to a second INSERT.
          globalId: incomingGlobalId != null && incomingGlobalId.isNotEmpty
              ? Value(incomingGlobalId)
              : const Value.absent(),
          // v138 (Issue 2): every postProduct request reaches this handler
          // via the public /api/products endpoint, which clients use through
          // their interceptor. So a row created here is by definition NOT
          // server-canonical — clients can keep editing it freely. Server
          // admins create products through the in-process desktop UI which
          // takes the local DAO path and gets the column's default (true).
          createdOnServer: const Value(false),
          name: Value(data['name'] as String),
          code: Value(data['code'] as String? ?? ''),
          barcode: Value(data['barcode'] as String?),
          categoryId: Value(resolvedCategoryId),
          supplierId: Value(parseIntNullable(data['supplierId'])),
          unitId: Value(resolvedUnitId),
          costPrice: Value(parseDoubleNullable(data['costPrice']) ?? 0),
          salePrice: Value(parseDoubleNullable(data['salePrice']) ?? 0),
          wholesalePrice: Value(
            parseDoubleNullable(data['wholesalePrice']) ?? 0,
          ),
          priceTalabat: Value(
            parseDoubleNullable(data['priceTalabat']) ?? 0,
          ),
          priceCareem: Value(
            parseDoubleNullable(data['priceCareem']) ?? 0,
          ),
          priceAshyae: Value(
            parseDoubleNullable(data['priceAshyae']) ?? 0,
          ),
          // Start at 0 — adjustStock below populates this atomically.
          currentStock: const Value(0),
          minStock: Value(parseDoubleNullable(data['minStock']) ?? 0),
          taxRate: Value(_validatedTaxRate(data['taxRate']) ?? 0),
          isSoldByWeight: Value(parseBool(data['isSoldByWeight'], false)),
          allowNegativeSale: Value(parseBool(data['allowNegativeSale'], false)),
          trackExpiry: Value(parseBool(data['trackExpiry'], false)),
          defaultShelfDays: Value(parseIntNullable(data['defaultShelfDays']) ?? 90),
          alertDaysBefore: Value(parseIntNullable(data['alertDaysBefore']) ?? 30),
          pricePerUnit: Value(parseDoubleNullable(data['pricePerUnit'])),
          scaleType: data['scaleType'] != null ? Value(data['scaleType'] as String) : const Value.absent(),
          scalePluNumber: Value(parseIntNullable(data['scalePluNumber'])),
          productType: Value(data['productType'] as String? ?? 'product'),
          warehouseId: Value(resolvedWarehouseId),
        ),
      );

      // B3: «معفى» — raw column outside the companion; it drives money.
      if (data.containsKey('taxExempt')) {
        await db.setProductTaxExempt(id, parseBool(data['taxExempt'], false));
      }

      // Materialise opening stock via the canonical adjustStock path so the
      // inventory_balances row is created together with current_stock and a
      // stock_movements audit row.
      if (openingStockValue > 0 && resolvedWarehouseId != null) {
        try {
          await db.adjustStock(
            productId: id,
            warehouseId: resolvedWarehouseId,
            quantity: openingStockValue,
            type: 'opening_stock',
            notes: 'Opening balance (legacy currentStock field on postProduct)',
          );
        } catch (e) {
          debugPrint('[API] postProduct: opening_stock adjustStock failed for serverId=$id: $e');
        }
      }

      // P5: Create child rows (units + barcodes) atomically with the product.
      // Previously these were inserted ONLY on the client because there was
      // no /api/product-units endpoint, so the server saw a "naked" product
      // and POS searches by unit barcode failed. The client still ships
      // these as part of the product payload, so handle them here.
      final rawUnits = data['units'];
      if (rawUnits is List) {
        for (final u in rawUnits) {
          if (u is! Map) continue;
          final unitName = (u['unitName'] as String?)?.trim();
          if (unitName == null || unitName.isEmpty) continue;
          final unitGid = u['globalId'] as String?;
          if (unitGid != null && unitGid.isNotEmpty) {
            final dup = await (db.select(db.productUnits)
                  ..where((pu) => pu.globalId.equals(unitGid))
                  ..limit(1))
                .getSingleOrNull();
            if (dup != null) continue;
          }
          try {
            await db.into(db.productUnits).insert(
                  ProductUnitsCompanion.insert(
                    productId: id,
                    unitName: unitName,
                    barcode: Value(u['barcode'] as String?),
                    quantityInBase: Value(parseDoubleNullable(u['quantityInBase']) ?? 1.0),
                    salePrice: Value(parseDoubleNullable(u['salePrice']) ?? 0),
                    costPrice: Value(parseDoubleNullable(u['costPrice']) ?? 0),
                    isBaseUnit: Value(parseBool(u['isBaseUnit'], false)),
                    isDefaultPurchase: Value(parseBool(u['isDefaultPurchase'], false)),
                    isDefaultSale: Value(parseBool(u['isDefaultSale'], false)),
                    sortOrder: Value(parseIntNullable(u['sortOrder']) ?? 0),
                    globalId: unitGid != null && unitGid.isNotEmpty
                        ? Value(unitGid)
                        : Value(UuidV7.generate()),
                  ),
                );
          } catch (e) {
            debugPrint('[API] postProduct: unit insert failed (non-fatal): $e');
          }
        }
      }

      final rawBarcodes = data['barcodes'];
      if (rawBarcodes is List) {
        for (final b in rawBarcodes) {
          if (b is! Map) continue;
          final code = (b['barcode'] as String?)?.trim();
          if (code == null || code.isEmpty) continue;
          try {
            // Idempotent: skip if barcode already mapped to this product.
            final dup = await (db.select(db.productBarcodes)
                  ..where((pb) => pb.barcode.equals(code) & pb.productId.equals(id))
                  ..limit(1))
                .getSingleOrNull();
            if (dup != null) continue;
            await db.into(db.productBarcodes).insert(
                  ProductBarcodesCompanion.insert(
                    productId: id,
                    barcode: code,
                    isPrimary: Value(parseBool(b['isPrimary'], false)),
                  ),
                );
          } catch (e) {
            debugPrint('[API] postProduct: barcode insert failed (non-fatal): $e');
          }
        }
      }

      return jsonResponse({'success': true, 'serverId': id});
        },
      );
    } on ArgumentError catch (e) {
      // البند 4: an illegal tax rate is a client-side validation failure (400),
      // not a server fault (500), so the caller can surface the reason verbatim
      // and the outbox doesn't retry an unfixable payload forever.
      debugPrint('[API] postProduct rejected: ${e.message}');
      return errorResponse('${e.message}', statusCode: 400);
    } catch (e) {
      debugPrint('[API] postProduct error: $e');
      return ApiErrors.fail(e, 'Failed to create product');
    }
  }

  Future<Response> putProduct(Request request, String id) async {
    try {
      // Spec 077 Batch 3 (Spec 060 Phase 2): per-user permission gate.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.productsEdit);
      if (perm != null) return perm;

      final data =
          json.decode(await request.readAsString()) as Map<String, dynamic>;
      final clientId = int.parse(id);

      // P5 (Issue #2 follow-up): Resolve the target product by ANY of:
      // (1) the URL id, (2) globalId in payload, (3) `code` in payload.
      // The original implementation only looked up by URL id, so an outbox
      // PUT for product #1000000001 returned 404 forever when the original
      // POST had failed and the client/server IDs diverged. Now we try all
      // three keys, and if the product still doesn't exist we treat the PUT
      // as an UPSERT and call into postProduct's create path.
      var product = await db.getProductById(clientId);
      if (product == null) {
        final gid = data['globalId'] as String?;
        if (gid != null && gid.isNotEmpty) {
          product = await (db.select(db.products)
                ..where((p) => p.globalId.equals(gid))
                ..limit(1))
              .getSingleOrNull();
        }
      }
      if (product == null) {
        final code = (data['code'] as String?)?.trim();
        if (code != null && code.isNotEmpty) {
          product = await (db.select(db.products)
                ..where((p) => p.code.equals(code))
                ..limit(1))
              .getSingleOrNull();
        }
      }
      if (product == null) {
        // Upsert path: forward the payload to the create handler. The
        // create handler has its own idempotency + FK resolution logic.
        debugPrint('[API] putProduct: id=$clientId not found — upserting via postProduct');
        // Re-encode the body since we already consumed it above.
        return postProduct(Request(
          'POST',
          request.requestedUri,
          headers: request.headers,
          body: json.encode(data),
        ));
      }

      // Code / barcode uniqueness — when the client sends a new code or
      // barcode in the update payload, reject if it already belongs to
      // a different product. Without this guard a putProduct could
      // silently overwrite the natural keys of an unrelated product
      // sharing the new value (e.g. operator typo).
      final newCode = (data['code'] as String?)?.trim();
      if (newCode != null && newCode.isNotEmpty && newCode != product.code) {
        final clash = await (db.select(db.products)
              ..where((p) =>
                  p.code.equals(newCode) & p.id.equals(product!.id).not())
              ..limit(1))
            .getSingleOrNull();
        if (clash != null) {
          return Response(
            409,
            body: json.encode({
              'error': 'هذا الكود مستخدم بالفعل لصنف آخر "${clash.name}"',
              'conflictWithProductId': clash.id,
            }),
            headers: {'Content-Type': 'application/json'},
          );
        }
      }
      final newBarcode = (data['barcode'] as String?)?.trim();
      if (newBarcode != null &&
          newBarcode.isNotEmpty &&
          newBarcode != product.barcode) {
        final clash = await (db.select(db.products)
              ..where((p) =>
                  p.barcode.equals(newBarcode) & p.id.equals(product!.id).not())
              ..limit(1))
            .getSingleOrNull();
        if (clash != null) {
          return Response(
            409,
            body: json.encode({
              'error':
                  'هذا الباركود مستخدم بالفعل لصنف آخر "${clash.name}"',
              'conflictWithProductId': clash.id,
            }),
            headers: {'Content-Type': 'application/json'},
          );
        }
      }

      // P5: Apply every editable field the client may have sent. Previous
      // implementation silently dropped wholesalePrice / priceTalabat /
      // priceCareem / priceAshyae / scaleType / scalePluNumber / etc., so
      // an admin could "save" their edit on the client and the server would
      // keep the old value forever — outbox said success, sales kept ringing
      // up at the wrong price.
      await db.updateProduct(
        product.copyWith(
          name: data['name'] as String? ?? product.name,
          code: data['code'] as String? ?? product.code,
          description: data.containsKey('description')
              ? Value(data['description'] as String?)
              : Value(product.description),
          barcode: data.containsKey('barcode')
              ? Value(data['barcode'] as String?)
              : Value(product.barcode),
          categoryId: Value(parseIntNullable(data['categoryId']) ?? product.categoryId),
          supplierId: Value(parseIntNullable(data['supplierId']) ?? product.supplierId),
          unitId: Value(parseIntNullable(data['unitId']) ?? product.unitId),
          warehouseId: Value(parseIntNullable(data['warehouseId']) ?? product.warehouseId),
          costPrice:
              parseDoubleNullable(data['costPrice']) ?? product.costPrice,
          salePrice:
              parseDoubleNullable(data['salePrice']) ?? product.salePrice,
          wholesalePrice:
              parseDoubleNullable(data['wholesalePrice']) ??
              product.wholesalePrice,
          priceTalabat:
              parseDoubleNullable(data['priceTalabat']) ?? product.priceTalabat,
          priceCareem:
              parseDoubleNullable(data['priceCareem']) ?? product.priceCareem,
          priceAshyae:
              parseDoubleNullable(data['priceAshyae']) ?? product.priceAshyae,
          pricePerUnit: data.containsKey('pricePerUnit')
              ? Value(parseDoubleNullable(data['pricePerUnit']))
              : Value(product.pricePerUnit),
          minStock: parseDoubleNullable(data['minStock']) ?? product.minStock,
          taxRate: _validatedTaxRate(data['taxRate']) ?? product.taxRate,
          isSoldByWeight: data.containsKey('isSoldByWeight')
              ? parseBool(data['isSoldByWeight'], product.isSoldByWeight)
              : product.isSoldByWeight,
          allowNegativeSale: data.containsKey('allowNegativeSale')
              ? parseBool(data['allowNegativeSale'], product.allowNegativeSale)
              : product.allowNegativeSale,
          trackExpiry: data.containsKey('trackExpiry')
              ? parseBool(data['trackExpiry'], product.trackExpiry)
              : product.trackExpiry,
          defaultShelfDays:
              parseIntNullable(data['defaultShelfDays']) ?? product.defaultShelfDays,
          alertDaysBefore:
              parseIntNullable(data['alertDaysBefore']) ?? product.alertDaysBefore,
          isActive: data.containsKey('isActive')
              ? parseBool(data['isActive'], product.isActive)
              : product.isActive,
          scaleType: data.containsKey('scaleType') && data['scaleType'] != null
              ? data['scaleType'] as String
              : product.scaleType,
          scalePluNumber: data.containsKey('scalePluNumber')
              ? Value(parseIntNullable(data['scalePluNumber']))
              : Value(product.scalePluNumber),
          productType: data['productType'] as String? ?? product.productType,
        ),
      );
      // B3: «معفى» — raw column outside the data class; absent key = keep.
      if (data.containsKey('taxExempt')) {
        await db.setProductTaxExempt(
            product.id, parseBool(data['taxExempt'], false));
      }
      broadcast('products');
      return jsonResponse({'success': true, 'serverId': product.id});
    } on ArgumentError catch (e) {
      debugPrint('[API] putProduct rejected: ${e.message}');
      return errorResponse('${e.message}', statusCode: 400);
    } catch (e) {
      debugPrint('[API] putProduct error: $e');
      return ApiErrors.fail(e, 'Failed to update product');
    }
  }

  Future<Response> deleteProduct(Request request, String id) async {
    try {
      // Spec 077 Batch 3 (Spec 060 Phase 2): per-user permission gate.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.productsDelete);
      if (perm != null) return perm;

      final productId = int.parse(id);
      await db.deleteProduct(productId);
      broadcast('products');
      broadcastRecordDeleted('products', productId);
      return jsonResponse({'success': true});
    } catch (e) {
      return ApiErrors.fail(e, 'Failed to delete product');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // Product Units — POST/PUT/DELETE
  // P5 (Issue #2 follow-up): Legacy outbox items pre-dating the units-in-
  // createProduct fix still hit these endpoints individually. Add handlers so
  // those dead-lettered items can be retried successfully instead of stuck
  // forever on "Not found" 404s.
  // ═══════════════════════════════════════════════════════════════

  Future<Response> postProductUnit(Request request) async {
    try {
      // Spec 077 Batch 3 (Spec 060 Phase 2): per-user permission gate.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.productsUnits);
      if (perm != null) return perm;

      final data =
          json.decode(await request.readAsString()) as Map<String, dynamic>;

      // UUID-First idempotency
      final incomingGid = data['globalId'] as String?;
      if (incomingGid != null && incomingGid.isNotEmpty) {
        final existing = await (db.select(db.productUnits)
              ..where((u) => u.globalId.equals(incomingGid))
              ..limit(1))
            .getSingleOrNull();
        if (existing != null) {
          return jsonResponse({
            'success': true,
            'serverId': existing.id,
            'duplicate': true,
          });
        }
      }

      // Resolve productId via globalId when client/server IDs differ
      int? productId = parseIntNullable(data['productId']);
      final productGid = data['productGlobalId'] as String?;
      if (productGid != null && productGid.isNotEmpty) {
        final byGid = await (db.select(db.products)
              ..where((p) => p.globalId.equals(productGid))
              ..limit(1))
            .getSingleOrNull();
        if (byGid != null) productId = byGid.id;
      }
      if (productId == null) {
        return errorResponse('Validation Error: missing productId/productGlobalId',
            statusCode: 400);
      }

      // Verify product exists on this server
      final productExists = await (db.select(db.products)
            ..where((p) => p.id.equals(productId!))
            ..limit(1))
          .getSingleOrNull();
      if (productExists == null) {
        return errorResponse('Product #$productId not found on server',
            statusCode: 404);
      }

      final unitName = (data['unitName'] as String?)?.trim() ?? '';
      if (unitName.isEmpty) {
        return errorResponse('Validation Error: unitName is required',
            statusCode: 400);
      }

      final id = await db.into(db.productUnits).insert(
            ProductUnitsCompanion.insert(
              productId: productId,
              unitName: unitName,
              barcode: Value(data['barcode'] as String?),
              quantityInBase: Value(parseDoubleNullable(data['quantityInBase']) ?? 1.0),
              salePrice: Value(parseDoubleNullable(data['salePrice']) ?? 0),
              costPrice: Value(parseDoubleNullable(data['costPrice']) ?? 0),
              isBaseUnit: Value(parseBool(data['isBaseUnit'], false)),
              isDefaultPurchase: Value(parseBool(data['isDefaultPurchase'], false)),
              isDefaultSale: Value(parseBool(data['isDefaultSale'], false)),
              sortOrder: Value(parseIntNullable(data['sortOrder']) ?? 0),
              globalId: incomingGid != null && incomingGid.isNotEmpty
                  ? Value(incomingGid)
                  : Value(UuidV7.generate()),
            ),
          );
      broadcast('product_units');
      return jsonResponse({'success': true, 'serverId': id});
    } catch (e) {
      debugPrint('[API] postProductUnit error: $e');
      return ApiErrors.fail(e, 'Failed to create product unit');
    }
  }

  Future<Response> putProductUnit(Request request, String id) async {
    try {
      // Spec 077 Batch 3 (Spec 060 Phase 2): per-user permission gate.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.productsUnits);
      if (perm != null) return perm;

      final data =
          json.decode(await request.readAsString()) as Map<String, dynamic>;
      final unitId = int.parse(id);
      final updated = await (db.update(db.productUnits)
            ..where((u) => u.id.equals(unitId)))
          .write(ProductUnitsCompanion(
            unitName: data['unitName'] != null
                ? Value(data['unitName'] as String)
                : const Value.absent(),
            barcode: data.containsKey('barcode')
                ? Value(data['barcode'] as String?)
                : const Value.absent(),
            quantityInBase: data['quantityInBase'] != null
                ? Value(parseDouble(data['quantityInBase']))
                : const Value.absent(),
            salePrice: data['salePrice'] != null
                ? Value(parseDouble(data['salePrice']))
                : const Value.absent(),
            costPrice: data['costPrice'] != null
                ? Value(parseDouble(data['costPrice']))
                : const Value.absent(),
            isBaseUnit: data.containsKey('isBaseUnit')
                ? Value(parseBool(data['isBaseUnit'], false))
                : const Value.absent(),
            isDefaultPurchase: data.containsKey('isDefaultPurchase')
                ? Value(parseBool(data['isDefaultPurchase'], false))
                : const Value.absent(),
            isDefaultSale: data.containsKey('isDefaultSale')
                ? Value(parseBool(data['isDefaultSale'], false))
                : const Value.absent(),
            sortOrder: data['sortOrder'] != null
                ? Value(parseInt(data['sortOrder']))
                : const Value.absent(),
          ));
      if (updated == 0) {
        return errorResponse('Product unit #$id not found', statusCode: 404);
      }
      broadcast('product_units');
      return jsonResponse({'success': true});
    } catch (e) {
      return ApiErrors.fail(e, 'Failed to update product unit');
    }
  }

  Future<Response> deleteProductUnit(Request request, String id) async {
    try {
      // Spec 077 Batch 3 (Spec 060 Phase 2): per-user permission gate.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.productsUnits);
      if (perm != null) return perm;

      final unitId = int.parse(id);
      await (db.delete(db.productUnits)..where((u) => u.id.equals(unitId))).go();
      broadcast('product_units');
      broadcastRecordDeleted('product_units', unitId);
      return jsonResponse({'success': true});
    } catch (e) {
      return ApiErrors.fail(e, 'Failed to delete product unit');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // Product Barcodes — POST/DELETE
  // ═══════════════════════════════════════════════════════════════

  Future<Response> postProductBarcode(Request request) async {
    try {
      // Spec 077 Batch 3 (Spec 060 Phase 2): per-user permission gate.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.productsBarcode);
      if (perm != null) return perm;

      final data =
          json.decode(await request.readAsString()) as Map<String, dynamic>;

      int? productId = parseIntNullable(data['productId']);
      final productGid = data['productGlobalId'] as String?;
      if (productGid != null && productGid.isNotEmpty) {
        final byGid = await (db.select(db.products)
              ..where((p) => p.globalId.equals(productGid))
              ..limit(1))
            .getSingleOrNull();
        if (byGid != null) productId = byGid.id;
      }
      if (productId == null) {
        return errorResponse('Validation Error: missing productId/productGlobalId',
            statusCode: 400);
      }

      final barcode = (data['barcode'] as String?)?.trim() ?? '';
      if (barcode.isEmpty) {
        return errorResponse('Validation Error: barcode is required',
            statusCode: 400);
      }

      // Idempotent — same (productId, barcode) returns existing.
      final dup = await (db.select(db.productBarcodes)
            ..where((pb) => pb.productId.equals(productId!) & pb.barcode.equals(barcode))
            ..limit(1))
          .getSingleOrNull();
      if (dup != null) {
        return jsonResponse({'success': true, 'serverId': dup.id, 'duplicate': true});
      }

      final id = await db.into(db.productBarcodes).insert(
            ProductBarcodesCompanion.insert(
              productId: productId,
              barcode: barcode,
              isPrimary: Value(parseBool(data['isPrimary'], false)),
            ),
          );
      broadcast('product_barcodes');
      return jsonResponse({'success': true, 'serverId': id});
    } catch (e) {
      return ApiErrors.fail(e, 'Failed to create product barcode');
    }
  }

  Future<Response> deleteProductBarcode(Request request, String id) async {
    try {
      // Spec 077 Batch 3 (Spec 060 Phase 2): per-user permission gate.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.productsBarcode);
      if (perm != null) return perm;

      final barcodeId = int.parse(id);
      await (db.delete(db.productBarcodes)..where((pb) => pb.id.equals(barcodeId))).go();
      broadcast('product_barcodes');
      broadcastRecordDeleted('product_barcodes', barcodeId);
      return jsonResponse({'success': true});
    } catch (e) {
      return ApiErrors.fail(e, 'Failed to delete product barcode');
    }
  }
}
