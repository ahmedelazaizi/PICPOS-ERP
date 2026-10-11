// ApiHandler - products, categories, units, product units and batches (GET).
part of '../api_handler.dart';

/// products, categories, units, product units and batches (GET) (see [ApiHandler]).
extension ApiHandlerCatalogGets on ApiHandler {
  // ═══════════════════════════════════════════════════════════════
  // Products (GET)
  // ═══════════════════════════════════════════════════════════════

  Future<Response> _getProducts(Request request) async {
    try {
      final branchId = await _extractBranchId(request);
      final warehouseIds = branchId != null ? await _resolveBranchWarehouseIds(branchId) : null;
      
      final query = _db.select(_db.products);
      if (warehouseIds != null && warehouseIds.isNotEmpty) {
        query.where((p) => p.warehouseId.isIn(warehouseIds) | p.warehouseId.isNull());
      }
      final products = await query.get();
      // B3: `tax_exempt` changes money (0 % tax), so it travels with the
      // product. Raw column (v182) — read beside the Drift rows.
      final exemptIds =
          await _db.getTaxExemptProductIds(products.map((p) => p.id));
      final jsonList = products
          .map(
            (p) => <String, dynamic>{
              'id': p.id,
              'code': p.code,
              'barcode': p.barcode,
              'name': p.name,
              'searchName': p.searchName,
              'description': p.description,
              'categoryId': p.categoryId,
              'unitId': p.unitId,
              'supplierId': p.supplierId,
              'warehouseId': p.warehouseId,
              'salePrice': p.salePrice,
              'wholesalePrice': p.wholesalePrice,
              'costPrice': p.costPrice,
              'minStock': p.minStock,
              'currentStock': p.currentStock,
              'isActive': p.isActive,
              'isLocked': p.isLocked,
              'trackInventory': p.trackInventory,
              'isSoldByWeight': p.isSoldByWeight,
              'pricePerUnit': p.pricePerUnit,
              'weightUnit': p.weightUnit,
              'allowNegativeSale': p.allowNegativeSale,
              'taxRate': p.taxRate,
              'taxExempt': exemptIds.contains(p.id),
              'scalePluNumber': p.scalePluNumber,
              'scaleType': p.scaleType,
              'sortOrder': p.sortOrder,
              'createdAt': p.createdAt.toIso8601String(),
              'updatedAt': p.updatedAt.toIso8601String(),
              'globalId': p.globalId,
              // v138 (Issue 2): provenance flag for the client's edit-lock UI.
              'createdOnServer': p.createdOnServer,
            },
          )
          .toList();

      return _json({'products': jsonList, 'count': jsonList.length});
    } catch (e) {
      debugPrint('[API] Error fetching products: $e');
      return ApiErrors.fail(e, 'Failed to fetch products');
    }
  }

  Future<Response> _getProductBarcodes(Request request) async {
    try {
      final barcodesDate = await _db.select(_db.productBarcodes).get();
      final jsonList = barcodesDate
          .map((b) => <String, dynamic>{
                'id': b.id,
                'productId': b.productId,
                'barcode': b.barcode,
                'isPrimary': b.isPrimary,
              })
          .toList();
      return _json({'product_barcodes': jsonList, 'count': jsonList.length});
    } catch (e) {
      debugPrint('[API] Error fetching product barcodes: $e');
      return ApiErrors.fail(e, 'Failed to fetch product barcodes');
    }
  }

  /// Live barcode lookup — used by branch clients when a product is not
  /// found in the local cache (e.g. product assigned to a different warehouse).
  /// Returns the product + its secondary barcodes so the client can
  /// locally cache it and complete the sale without requiring a full sync.
  Future<Response> _getProductByBarcodeQuery(Request request) async {
    try {
      final barcode = request.requestedUri.queryParameters['barcode'];
      if (barcode == null || barcode.isEmpty) {
        return _error('Missing "barcode" query parameter', statusCode: 400);
      }

      // Branch-scoping: only return products whose warehouse belongs to this branch
      final branchId = await _extractBranchId(request);
      final warehouseIds = branchId != null ? await _resolveBranchWarehouseIds(branchId) : null;

      // 1. Try primary barcode
      Product? product = await (_db.select(_db.products)
            ..where((p) {
              final base = p.barcode.equals(barcode) & p.isActive.equals(true);
              if (warehouseIds != null && warehouseIds.isNotEmpty) {
                return base & (p.warehouseId.isIn(warehouseIds) | p.warehouseId.isNull());
              }
              return base;
            })
            ..limit(1))
          .getSingleOrNull();

      // 2. Try secondary barcodes
      if (product == null) {
        final secondary = await (_db.select(_db.productBarcodes)
              ..where((b) => b.barcode.equals(barcode))
              ..limit(1))
            .getSingleOrNull();
        if (secondary != null) {
          product = await (_db.select(_db.products)
                ..where((p) {
                  final base = p.id.equals(secondary.productId) & p.isActive.equals(true);
                  if (warehouseIds != null && warehouseIds.isNotEmpty) {
                    return base & (p.warehouseId.isIn(warehouseIds) | p.warehouseId.isNull());
                  }
                  return base;
                })
                ..limit(1))
              .getSingleOrNull();
        }
      }

      if (product == null) {
        return _json({'found': false, 'product': null, 'barcodes': []});
      }

      // Return product with ALL its secondary barcodes so client can cache them
      final barcodes = await (_db.select(_db.productBarcodes)
            ..where((b) => b.productId.equals(product!.id)))
          .get();

      return _json({
        'found': true,
        'product': {
          'id': product.id,
          'code': product.code,
          'barcode': product.barcode,
          'name': product.name,
          'searchName': product.searchName,
          'description': product.description,
          'categoryId': product.categoryId,
          'unitId': product.unitId,
          'supplierId': product.supplierId,
          'warehouseId': product.warehouseId,
          'salePrice': product.salePrice,
          'wholesalePrice': product.wholesalePrice,
          'costPrice': product.costPrice,
          'minStock': product.minStock,
          'currentStock': product.currentStock,
          'isActive': product.isActive,
          'isLocked': product.isLocked,
          'trackInventory': product.trackInventory,
          'isSoldByWeight': product.isSoldByWeight,
          'pricePerUnit': product.pricePerUnit,
          'weightUnit': product.weightUnit,
          'allowNegativeSale': product.allowNegativeSale,
          'taxRate': product.taxRate,
          'taxExempt': await _db.getProductTaxExempt(product.id),
          'scalePluNumber': product.scalePluNumber,
          'scaleType': product.scaleType,
          'sortOrder': product.sortOrder,
          'createdAt': product.createdAt.toIso8601String(),
        },
        'barcodes': barcodes.map((b) => {
          'id': b.id,
          'productId': b.productId,
          'barcode': b.barcode,
          'isPrimary': b.isPrimary,
        }).toList(),
      });
    } catch (e) {
      debugPrint('[API] Error in product barcode lookup: $e');
      return ApiErrors.fail(e, 'Failed to lookup barcode');
    }
  }

  Future<Response> _getUserBranchAccess(Request request) async {
    try {
      final accessData = await _db.select(_db.userBranchAccess).get();
      // Spec 136 ISS-10 — also send the branch's globalId so the client can
      // remap the server branchId to its OWN local branch id. Without this the
      // client stored the raw server id, and when local↔server branch ids
      // drift (BranchSync name-match keeps the local id) the login guard's
      // `assignments.contains(client_branch_id)` failed → "ليس لديك صلاحية
      // الدخول لهذا الفرع" even for users assigned that branch / all branches.
      final branches = await _db.select(_db.branches).get();
      final gidById = {for (final b in branches) b.id: b.globalId};
      final jsonList = accessData
          .map((a) => <String, dynamic>{
                'userId': a.userId,
                'branchId': a.branchId,
                'branchGlobalId': gidById[a.branchId],
              })
          .toList();
      return _json({'user_branch_access': jsonList, 'count': jsonList.length});
    } catch (e) {
      debugPrint('[API] Error fetching user branch access: $e');
      return ApiErrors.fail(e, 'Failed to fetch user branch access');
    }
  }

  Future<Response> _getUserWarehouseAccess(Request request) async {
    try {
      final accessData = await _db.select(_db.userWarehouseAccess).get();
      final jsonList = accessData
          .map((a) => <String, dynamic>{
                'userId': a.userId,
                'warehouseId': a.warehouseId,
              })
          .toList();
      return _json({'user_warehouse_access': jsonList, 'count': jsonList.length});
    } catch (e) {
      debugPrint('[API] Error fetching user warehouse access: $e');
      return ApiErrors.fail(e, 'Failed to fetch user warehouse access');
    }
  }

  Future<Response> _getUpdatedProducts(Request request) async {
    try {
      final sinceStr = request.requestedUri.queryParameters['since'];
      if (sinceStr == null) {
        return _error('Missing "since" query parameter', statusCode: 400);
      }

      final branchId = await _extractBranchId(request);
  // ignore: unused_local_variable
      final warehouseIds = branchId != null ? await _resolveBranchWarehouseIds(branchId) : null;

      final since = DateTime.parse(sinceStr);
      final query = _db.select(_db.products)
        ..where((p) => p.updatedAt.isBiggerOrEqual(Variable(since)));
      
      // Removed warehouseId filtering here to make products globally synced
      
      final products = await query.get();
      // B3: see `_getProducts` — the exempt flag travels with the product.
      final exemptIds =
          await _db.getTaxExemptProductIds(products.map((p) => p.id));

      final jsonList = products
          .map(
            (p) => <String, dynamic>{
              'id': p.id,
              'code': p.code,
              'barcode': p.barcode,
              'name': p.name,
              'searchName': p.searchName,
              'description': p.description,
              'categoryId': p.categoryId,
              'unitId': p.unitId,
              'supplierId': p.supplierId,
              'warehouseId': p.warehouseId,
              'salePrice': p.salePrice,
              'wholesalePrice': p.wholesalePrice,
              'costPrice': p.costPrice,
              'minStock': p.minStock,
              'currentStock': p.currentStock,
              'isActive': p.isActive,
              'isLocked': p.isLocked,
              'trackInventory': p.trackInventory,
              'isSoldByWeight': p.isSoldByWeight,
              'pricePerUnit': p.pricePerUnit,
              'weightUnit': p.weightUnit,
              'allowNegativeSale': p.allowNegativeSale,
              'taxRate': p.taxRate,
              'taxExempt': exemptIds.contains(p.id),
              'scalePluNumber': p.scalePluNumber,
              'scaleType': p.scaleType,
              'sortOrder': p.sortOrder,
              'createdAt': p.createdAt.toIso8601String(),
              'updatedAt': p.updatedAt.toIso8601String(),
              'globalId': p.globalId,
              // v138 (Issue 2): provenance flag for the client's edit-lock UI.
              'createdOnServer': p.createdOnServer,
            },
          )
          .toList();

      return _json({
        'products': jsonList,
        'count': jsonList.length,
        'since': sinceStr,
      });
    } catch (e) {
      return ApiErrors.fail(e, 'Failed to fetch updated products');
    }
  }


  // ═══════════════════════════════════════════════════════════════
  // Categories (GET)
  // ═══════════════════════════════════════════════════════════════

  Future<Response> _getCategories(Request request) async {
    try {
      final categories = await _db.select(_db.categories).get();
      final jsonList = <Map<String, dynamic>>[];

      for (final c in categories) {
        final branches = await (_db.select(_db.categoryBranches)
              ..where((cb) => cb.categoryId.equals(c.id)))
            .get();

        jsonList.add({
          'id': c.id,
          'globalId': c.globalId,
          'name': c.name,
          'parentId': c.parentId,
          'color': c.color,
          'iconName': c.iconName,
          'sortOrder': c.sortOrder,
          'isActive': c.isActive,
          'isGlobal': c.isGlobal,
          'printerId': c.printerId,
          'isLocked': c.isLocked,
          'isExcluded': c.isExcluded,
          'showInPos': c.showInPos,
          'branchIds': branches.map((b) => b.branchId).toList(),
        });
      }

      return _json({'categories': jsonList, 'count': jsonList.length});
    } catch (e) {
      return ApiErrors.fail(e, 'Failed to fetch categories');
    }
  }


  // ═══════════════════════════════════════════════════════════════
  // Units (GET)
  // ═══════════════════════════════════════════════════════════════

  Future<Response> _getUnits(Request request) async {
    try {
      final units = await _db.select(_db.units).get();
      final jsonList = units
          .map((u) => <String, dynamic>{'id': u.id, 'name': u.name})
          .toList();

      return _json({'units': jsonList, 'count': jsonList.length});
    } catch (e) {
      return ApiErrors.fail(e, 'Failed to fetch units');
    }
  }


  // ═══════════════════════════════════════════════════════════════
  // Product Units (GET)
  // ═══════════════════════════════════════════════════════════════

  Future<Response> _getProductUnits(Request request) async {
    try {
      final units = await _db.select(_db.productUnits).get();
      final jsonList = units
          .map((u) => <String, dynamic>{
                'id': u.id,
                'productId': u.productId,
                'unitName': u.unitName,
                'barcode': u.barcode,
                'quantityInBase': u.quantityInBase,
                'salePrice': u.salePrice,
                'costPrice': u.costPrice,
                'isDefaultPurchase': u.isDefaultPurchase,
                'isDefaultSale': u.isDefaultSale,
                'isBaseUnit': u.isBaseUnit,
                'sortOrder': u.sortOrder,
              })
          .toList();

      return _json({'product_units': jsonList, 'count': jsonList.length});
    } catch (e) {
      return ApiErrors.fail(e, 'Failed to fetch product units');
    }
  }


  // ═══════════════════════════════════════════════════════════════
  // Product Batches
  // ═══════════════════════════════════════════════════════════════

  Future<Response> _getProductBatches(Request request) async {
    try {
      // Spec 151 residual #1 — scope by warehouse→branch (batches are per
      // warehouse). No identity → sentinel → warehouseId IN (-1) → zero rows.
      final branchId =
          await _extractBranchId(request, failClosedOnNoIdentity: true);
      final warehouseIds =
          branchId != null ? await _resolveBranchWarehouseIds(branchId) : null;
      final query = _db.select(_db.productBatches);
      if (warehouseIds != null && warehouseIds.isNotEmpty) {
        query.where((b) => b.warehouseId.isIn(warehouseIds));
      }
      final rows = await query.get();
      final jsonList = rows.map((b) => <String, dynamic>{
        'id': b.id,
        'productId': b.productId,
        'warehouseId': b.warehouseId,
        'batchNumber': b.batchNumber,
        'productionDate': b.productionDate?.toIso8601String(),
        'expiryDate': b.expiryDate.toIso8601String(),
        'quantity': b.quantity,
        'initialQuantity': b.initialQuantity,
        'unitCost': b.unitCost,
        'purchaseInvoiceId': b.purchaseInvoiceId,
        'status': b.status,
        'createdAt': b.createdAt.toIso8601String(),
      }).toList();
      return _json({'product_batches': jsonList, 'count': jsonList.length});
    } catch (e) {
      return ApiErrors.fail(e, 'Failed to fetch product batches');
    }
  }

}
