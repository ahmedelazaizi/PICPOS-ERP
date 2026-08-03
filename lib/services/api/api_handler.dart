// ═══════════════════════════════════════════════════════════════════════════
// API HANDLER — Main router and GET endpoints
// ═══════════════════════════════════════════════════════════════════════════
//
// This is the core API handler that builds the shelf Router and contains
// all read-only (GET) endpoints. Write operations are delegated to
// domain-specific handlers for maintainability (PIR C-01):
//
//   - ApiSalesHandler: Sales, Returns, Held Orders, WebSocket
//   - ApiDataHandler: Expenses, Receipts, Shifts, Parties, Products,
//                     Purchases, Inventory, Treasury, Settings,
//                     Categories, Users, Warehouses, Backup
//
// Display endpoints (CFD, Menu) are still inline since they contain
// large HTML templates that don't benefit from further extraction.

import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../../core/constants/app_constants.dart';
import '../../core/logging/diagnostic_logger.dart';
import '../../services/cfd_service.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:drift/drift.dart';
import '../../data/database/database.dart';
import '../network_service.dart';
import '../security_service.dart';
import 'api_auth_middleware.dart';
import 'api_user_context.dart';
import 'api_handler_base.dart' show WsSubscriberInfo;
import 'api_sales_handler.dart';
import 'api_data_handler.dart';
import 'api_party_handler.dart';
import 'api_product_handler.dart';
import 'api_purchase_handler.dart';
import 'api_auth_handler.dart';
import 'api_terminals_handler.dart';
import 'api_html_templates.dart';

/// REST API handler for the embedded server.
/// Exposes read-only endpoints for products, categories, units,
/// and delegates write endpoints to domain-specific handlers.
class ApiHandler {
  final AppDatabase _db;

  /// Spec 129 F1: connected WebSocket clients mapped to structured
  /// [WsSubscriberInfo] (mode + branchId + deviceId). Mirror subscribers
  /// always have `branchId == null` and receive every broadcast.
  final Map<WebSocketChannel, WsSubscriberInfo> _wsClients = {};

  /// Sub-handlers for domain-specific operations
  late final ApiSalesHandler _sales;
  late final ApiDataHandler _data;
  late final ApiPartyHandler _parties;
  late final ApiProductHandler _products;
  late final ApiPurchaseHandler _purchases;
  late final ApiAuthHandler _auth;
  late final ApiTerminalsHandler _terminals;

  ApiHandler(this._db) {
    _sales = ApiSalesHandler(_db, _wsClients);
    _data = ApiDataHandler(_db, _wsClients);
    _parties = ApiPartyHandler(_db, _wsClients);
    _products = ApiProductHandler(_db, _wsClients);
    _purchases = ApiPurchaseHandler(_db, _wsClients);
    _auth = ApiAuthHandler(_db, _wsClients);
    _terminals = ApiTerminalsHandler(_db, _wsClients);
  }

  /// Build the shelf Router with all API endpoints
  Router buildRouter() {
    final router = Router();

    // Health check
    router.get('/api/health', _healthCheck);

    // ── WebSocket ──
    router.get('/ws', _sales.handleWebSocket);

    // ── Read endpoints (for clients to pull data) ──
    router.get('/api/products', _getProducts);
    router.get('/api/products/updated', _getUpdatedProducts);
    router.get('/api/categories', _getCategories);
    router.get('/api/units', _getUnits);
    router.get('/api/settings', _getSettings);
    router.get('/api/parties', _getParties);
    router.get('/api/branches', _getBranches);
    router.get('/api/regions', _getRegions);
    router.get('/api/user-region-access', _getUserRegionAccess);
    router.get('/api/cost_centers', _getCostCenters);
    router.get('/api/accounts', _getAccounts);
    router.get('/api/warehouses', _getWarehouses);
    router.get('/api/users', _getUsers);
    router.get('/api/roles', _getRoles);
    router.post('/api/roles', _data.createRole);
    router.post('/api/roles/<id>/permissions', _data.setRolePermissions);
    router.get('/api/permissions', _getPermissions);
    router.get('/api/role_permissions', _getRolePermissions);
    router.get('/api/safes', _getSafes);
    router.get('/api/shifts', _getShifts);
    router.get('/api/sales', _getSalesInvoices);
    router.get('/api/sales/held', _getHeldOrders);
    router.get('/api/sales/held-items', _getHeldOrderItems);
    router.get('/api/safe-transactions', _getSafeTransactions);
    router.get('/api/journals', _getJournalEntries);
    router.get('/api/purchases', _getPurchaseInvoices);
    router.get('/api/stock-movements', _getStockMovements);
    router.get('/api/inventory-balances', _getInventoryBalances);
    router.get('/api/commercial-papers', _getCommercialPapers);
    router.get('/api/account-mappings', _getAccountMappings);
    router.get('/api/product-barcodes', _getProductBarcodes);
    router.get('/api/products/barcode', _getProductByBarcodeQuery); // Client-side barcode fallback
    router.get('/api/user-branch-access', _getUserBranchAccess);
    router.get('/api/user-warehouse-access', _getUserWarehouseAccess);
    router.get('/api/offers', _getOffers);
    router.get('/api/product-units', _getProductUnits);
    router.get('/api/document-sequences', _getDocumentSequences);
    router.get('/api/fiscal-years', _getFiscalYears);
    router.get('/api/payments', _getPayments);
    router.get('/api/payment-allocations', _getPaymentAllocations);
    router.get('/api/product-batches', _getProductBatches);
    router.get('/api/sales-orders', _getSalesOrders);
    router.get('/api/purchase-orders', _getPurchaseOrders);
    router.get('/api/accounting-periods', _getAccountingPeriods);

    // ── Write endpoints — delegated to sub-handlers ──
    // POS terminals (Feature 009 / T020) — must come before any catch-all
    router.post('/api/pos-terminals/register', _terminals.register);
    // Sales
    router.post('/api/sales', _sales.postSale);
    router.post('/api/sales/return', _sales.postSalesReturn);
    router.post('/api/sales/held', _sales.postHeldOrder);
    router.delete('/api/sales/held/<id>', _sales.deleteHeldOrder);
    // C-02 (Spec 151): globalId-resolved sales void — a POST so there is no
    // path-shadowing with the DELETE /<id> below. The client ships its LOCAL id
    // (≠ server id), so the handler MUST resolve by globalId or it voids the
    // wrong invoice at HQ. See ApiSalesHandler.postVoidSale (R4/R9).
    router.post('/api/sales/void', _sales.postVoidSale);
    // Spec 151 C-05: client/mirror customer-collection submit — advances
    // invoice.paid + posts Dr Safe / Cr Customer server-side (twin of C-03's
    // /api/purchases/payment). See ApiSalesHandler.postSalesPayment.
    router.post('/api/sales/payment', _sales.postSalesPayment);
    router.delete('/api/sales/<id>', _sales.deleteSalesInvoice);
    // Expenses & Receipts
    router.post('/api/expenses', _data.postExpense);
    router.delete('/api/expenses/<id>', _data.deleteExpense);
    router.post('/api/receipts', _data.postReceipt);
    // Shifts
    router.post('/api/shifts/open', _data.postOpenShift);
    router.post('/api/shifts/close', _data.postCloseShift);
    // Parties
    router.post('/api/parties', _parties.postParty);
    router.put('/api/parties/<id>', _parties.putParty);
    router.delete('/api/parties/<id>', _parties.deleteParty);
    // Products
    router.post('/api/products', _products.postProduct);
    router.put('/api/products/<id>', _products.putProduct);
    router.delete('/api/products/<id>', _products.deleteProduct);
    // Product Units (P5: legacy outbox replay support)
    router.post('/api/product-units', _products.postProductUnit);
    router.put('/api/product-units/<id>', _products.putProductUnit);
    router.delete('/api/product-units/<id>', _products.deleteProductUnit);
    // Product Barcodes
    router.post('/api/product-barcodes', _products.postProductBarcode);
    router.delete('/api/product-barcodes/<id>', _products.deleteProductBarcode);
    // Purchases
    router.post('/api/purchases', _purchases.postPurchase);
    router.post('/api/purchases/return', _purchases.postPurchaseReturn);
    router.post('/api/purchases/return/edit', _purchases.postPurchaseReturnEdit);
    // PR-2 (pre-deploy batch B6): client/mirror void submit — see
    // ApiPurchaseHandler.postVoidPurchase for the R4/R8/R9 rationale.
    router.post('/api/purchases/void', _purchases.postVoidPurchase);
    // Spec 151 C-03: client/mirror payment submit — advances invoice.paid +
    // posts Dr AP / Cr cash server-side. See ApiPurchaseHandler.postPurchasePayment.
    router.post('/api/purchases/payment', _purchases.postPurchasePayment);
    router.put('/api/purchases/<id>', _purchases.putPurchase);
    router.delete('/api/purchases/<id>', _purchases.deletePurchase);
    // Inventory
    router.post('/api/inventory/adjust', _data.postStockAdjust);
    router.post('/api/inventory/transfer', _data.postStockTransfer);
    // Spec 109 — inventory bond endpoint was missing; clients (incl. mirror)
    // hit 404 on every opening-balance / adding-bond submission.
    router.post('/api/inventory/bond', _data.postInventoryBond);
    // Treasury
    router.post('/api/safes/close', _data.postCloseSafe);
    router.post('/api/safes/transaction', _data.postSafeTransaction);
    router.post('/api/safes/transfer', _data.postSafeTransfer);
    router.post('/api/safes/set-default', _data.postSetDefaultSafe);
    // Journal Entries (Client → Server sync)
    router.post('/api/journals', _data.postJournalEntry);
    // Settings
    router.post('/api/settings', _data.postSettings);
    // Categories
    router.post('/api/categories', _data.postCategory);
    router.put('/api/categories/<id>', _data.putCategory);
    router.delete('/api/categories/<id>', _data.deleteCategory);
    // Users
    router.post('/api/users', _data.postUser);
    router.put('/api/users/<id>', _data.putUser);
    router.delete('/api/users/<id>', _data.deleteUser);
    router.post('/api/users/<id>/password', _data.postUserPassword);
    router.post('/api/users/<id>/pin', _data.postUserPin);
    // Warehouses
    router.post('/api/warehouses', _data.postWarehouse);
    router.put('/api/warehouses/<id>', _data.putWarehouse);
    router.delete('/api/warehouses/<id>', _data.deleteWarehouse);

    // Branches CRUD (Feature 006 / MM.C). The mirror admin needs to
    // create / rename / soft-deactivate branches from a remote laptop;
    // GET was already exposed for client sync, the writes are new.
    router.post('/api/branches', _data.postBranch);
    router.put('/api/branches/<id>', _data.putBranch);
    router.delete('/api/branches/<id>', _data.deleteBranch);

    // Safes CRUD (Feature 006 / MM.C). postSafe goes through
    // createSafeWithLinkedAccount so the CoA pairing stays atomic.
    // The pre-existing /api/safes/{close,transaction,transfer,set-default}
    // endpoints handle operational moves and remain unchanged.
    router.post('/api/safes', _data.postSafe);
    router.put('/api/safes/<id>', _data.putSafe);
    router.delete('/api/safes/<id>', _data.deleteSafe);

    // Accounts (CoA) CRUD (Feature 006 / MM.C). The mirror admin
    // can add / rename / soft-delete chart-of-accounts rows. The
    // pre-existing GET /api/accounts is unchanged.
    router.post('/api/accounts', _data.postAccount);
    router.put('/api/accounts/<id>', _data.putAccount);
    router.delete('/api/accounts/<id>', _data.deleteAccount);

    // Account Mappings (purpose → account) — upsert + delete.
    router.post('/api/account-mappings', _data.postAccountMapping);
    router.delete('/api/account-mappings', _data.deleteAccountMapping);

    // Cost Centers CRUD (Feature 006 / MM.C). Document sequences are
    // intentionally NOT exposed for write — they're auto-incremented
    // internally on every invoice creation, not a user-facing edit.
    // Fiscal years and accounting periods are deferred (rarely-touched
    // admin operations with their own financial-lock semantics).
    router.post('/api/cost_centers', _data.postCostCenter);
    router.put('/api/cost_centers/<id>', _data.putCostCenter);
    router.delete('/api/cost_centers/<id>', _data.deleteCostCenter);
    // Backup
    router.post('/api/backup', _data.postBackup);
    // Commercial Papers
    router.post('/api/commercial-papers', _data.postCommercialPaper);
    router.put('/api/commercial-papers/<id>/status', _data.putCommercialPaperStatus);
    router.post('/api/commercial-papers/<id>/renew', _data.postRenewPaper);
    router.post('/api/commercial-papers/<id>/partial-collect', _data.postPartialCollection);
    router.post('/api/commercial-papers/<id>/deposit', _data.postDepositForCollection);
    router.post('/api/commercial-papers/<id>/reissue', _data.postReissuePaper);
    // Regions
    router.post('/api/regions', _data.postRegion);
    router.put('/api/regions/<id>', _data.putRegion);
    router.delete('/api/regions/<id>', _data.deleteRegion);
    router.post('/api/user-region-access', _data.postUserRegionAccess);
    // S4.2: Party Groups
    router.post('/api/party-groups', _data.postPartyGroup);
    router.put('/api/party-groups/<id>', _data.putPartyGroup);
    router.delete('/api/party-groups/<id>', _data.deletePartyGroup);
    // S4.2: Purchase Orders (write)
    router.post('/api/purchase-orders', _data.postPurchaseOrder);
    router.put('/api/purchase-orders/<id>/status', _data.putPurchaseOrderStatus);
    router.delete('/api/purchase-orders/<id>', _data.deletePurchaseOrder);
    // S4.2: Sales Orders (write)
    router.post('/api/sales-orders', _data.postSalesOrder);
    router.put('/api/sales-orders/<id>/status', _data.putSalesOrderStatus);
    router.delete('/api/sales-orders/<id>', _data.deleteSalesOrder);
    // S4.2: Quotations
    router.post('/api/quotations', _data.postQuotation);
    router.put('/api/quotations/<id>/status', _data.putQuotationStatus);
    router.put('/api/quotations/<id>', _data.putQuotation);
    router.delete('/api/quotations/<id>', _data.deleteQuotation);
    // S4.2: Price Lists
    router.post('/api/price-lists', _data.postPriceList);
    router.put('/api/price-lists/<id>', _data.putPriceList);
    router.post('/api/price-list-items', _data.postPriceListItem);
    // S4.2: Printers
    router.post('/api/printers', _data.postPrinter);
    router.put('/api/printers/<id>', _data.putPrinter);
    router.delete('/api/printers/<id>', _data.deletePrinter);
    // Activity Logs — client push endpoint (central audit trail)
    router.post('/api/activity-logs/push', _data.pushActivityLog);

    // Mirror-mode admin verification (Feature 006 / MM.C). Used by the
    // setup wizard to verify the operator's HQ admin identity before
    // entering NetworkMode.mirror, so MirrorState.adminUserId is stamped
    // into every subsequent write payload for audit attribution.
    router.post('/api/auth/verify-admin', _auth.verifyAdmin);
    // Spec 151 (P1-8): issue a signed per-user session token after a credential
    // check — replaces the forgeable X-User-Id header as the identity source.
    router.post('/api/auth/session', _auth.issueSession);
    // Heartbeat
    router.post('/api/sync/heartbeat', _heartbeat);
    // Delta pull — generic watermark-based sync endpoint (P3.1)
    router.get('/api/sync/pull', _getSyncPull);
    // Authoritative server clock — clients use this to seed watermarks
    // instead of their local DateTime.now(), eliminating the risk that a
    // client clock running ahead of the server causes rows modified in the
    // gap to be skipped by the first delta pull.
    router.get('/api/sync/time', (Request r) => _json({
          'serverTime': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        }));

    // CFD Endpoints
    router.get('/cfd', _getCfdDisplay);
    router.get('/api/cfd/stream', _cfdStream);

    // Digital Menu Endpoints
    router.get('/menu', _getMenuDisplay);
    router.get('/api/menu', _getMenuData);

    // Catch-all for undefined routes
    router.all('/<ignored|.*>', _notFound);

    return router;
  }

  // ═══════════════════════════════════════════════════════════════
  // Health & Status
  // ═══════════════════════════════════════════════════════════════

  Future<Response> _healthCheck(Request request) async {
    final ns = NetworkService.instance;
    return _json({
      'status': 'ok',
      'version': AppConstants.appVersion,
      'serverTime': DateTime.now().toIso8601String(),
      'uptime': ns.serverStartTime != null
          ? DateTime.now().difference(ns.serverStartTime!).inSeconds
          : 0,
      'connectedClients': ns.connectedClientCount,
      // A-SEC-1: only hand the bearer token to callers during an operator-opened
      // device-pairing window — never in steady state.
      if (ApiAuthMiddleware.isPairingOpen)
        'apiToken': ApiAuthMiddleware.activeToken,
    });
  }

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
      return _error('Failed to fetch products: $e');
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
      return _error('Failed to fetch product barcodes: $e');
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
      return _error('Failed to lookup barcode: $e');
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
      return _error('Failed to fetch user branch access: $e');
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
      return _error('Failed to fetch user warehouse access: $e');
    }
  }

  Future<Response> _getUpdatedProducts(Request request) async {
    try {
      final sinceStr = request.requestedUri.queryParameters['since'];
      if (sinceStr == null) {
        return _error('Missing "since" query parameter', statusCode: 400);
      }

      final branchId = await _extractBranchId(request);
      final warehouseIds = branchId != null ? await _resolveBranchWarehouseIds(branchId) : null;

      final since = DateTime.parse(sinceStr);
      final query = _db.select(_db.products)
        ..where((p) => p.updatedAt.isBiggerOrEqual(Variable(since)));
      
      // Removed warehouseId filtering here to make products globally synced
      
      final products = await query.get();

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
      return _error('Failed to fetch updated products: $e');
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
      return _error('Failed to fetch categories: $e');
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
      return _error('Failed to fetch units: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // Settings (GET)
  // ═══════════════════════════════════════════════════════════════

  Future<Response> _getSettings(Request request) async {
    try {
      final settings = await _db.select(_db.settings).get();
      final settingsMap = <String, String>{};
      for (final s in settings) {
        if (s.value != null) {
          settingsMap[s.key] = s.value!;
        }
      }

      return _json({'settings': settingsMap});
    } catch (e) {
      return _error('Failed to fetch settings: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // Roles & Permissions (GET)
  // ═══════════════════════════════════════════════════════════════

  Future<Response> _getRoles(Request request) async {
    try {
      final roles = await _db.select(_db.roles).get();
      final jsonList = roles
          .map(
            (r) => <String, dynamic>{
              'id': r.id,
              'name': r.name,
              'description': r.description,
              'isSystemRole': r.isSystemRole,
              'createdAt': r.createdAt.toIso8601String(),
            },
          )
          .toList();
      return _json({'roles': jsonList, 'count': jsonList.length});
    } catch (e) {
      return _error('Failed to fetch roles: $e');
    }
  }

  Future<Response> _getPermissions(Request request) async {
    try {
      final perms = await _db.select(_db.permissions).get();
      final jsonList = perms
          .map(
            (p) => <String, dynamic>{
              'id': p.id,
              'code': p.code,
              'name': p.name,
              'category': p.category,
            },
          )
          .toList();
      return _json({'permissions': jsonList, 'count': jsonList.length});
    } catch (e) {
      return _error('Failed to fetch permissions: $e');
    }
  }

  Future<Response> _getRolePermissions(Request request) async {
    try {
      // CRITICAL: Include the permission CODE and role NAME alongside the IDs.
      //
      // The numeric IDs in `permissions` and `roles` tables are auto-increment
      // and CAN DIVERGE between server and client (the seeding order, ON
      // CONFLICT DO NOTHING races, and Phase-additions of new permission codes
      // all leave the two databases with the SAME codes but DIFFERENT IDs).
      //
      // The previous response shipped only IDs, so the client's
      // RolePermissionSyncStrategy filtered each row by
      //     existingPermIds.contains(serverPermId)
      // and dropped every mapping whose server id had no local twin — silently
      // stripping critical permissions like pos_save from the cashier's role
      // even though the server clearly had them. The user's exact symptom:
      // "I added pos_save on the server, the SQL query confirms it, but the
      // override dialog still fires on the cashier's POS".
      //
      // Codes are universal (the same code identifies the same permission on
      // every node), so shipping them lets the client re-resolve to its own
      // local id without depending on id alignment.
      final perms = await _db.select(_db.permissions).get();
      final codeById = <int, String>{
        for (final p in perms) p.id: p.code,
      };
      final roles = await _db.select(_db.roles).get();
      final roleNameById = <int, String>{
        for (final r in roles) r.id: r.name,
      };

      final rp = await _db.select(_db.rolePermissions).get();
      final jsonList = rp
          .map(
            (r) => <String, dynamic>{
              'roleId': r.roleId,
              'permissionId': r.permissionId,
              // New fields — clients on the latest build prefer these.
              if (codeById[r.permissionId] != null)
                'permissionCode': codeById[r.permissionId],
              if (roleNameById[r.roleId] != null)
                'roleName': roleNameById[r.roleId],
            },
          )
          .toList();
      return _json({'role_permissions': jsonList, 'count': jsonList.length});
    } catch (e) {
      return _error('Failed to fetch role_permissions: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // Safes (GET)
  // ═══════════════════════════════════════════════════════════════

  Future<Response> _getSafes(Request request) async {
    try {
      final branchId = await _extractBranchId(request);
      final query = _db.select(_db.safes);
      if (branchId != null) {
        query.where((s) => s.branchId.equals(branchId) | s.branchId.isNull());
      }
      final safes = await query.get();
      final jsonList = safes
          .map(
            (s) => <String, dynamic>{
              'id': s.id,
              'name': s.name,
              'safeType': s.safeType,
              'bankName': s.bankName,
              'accountNumber': s.accountNumber,
              'balance': s.balance,
              'branchId': s.branchId,
              'costCenterId': s.costCenterId,
              'linkedAccountId': s.linkedAccountId,
              'isDefault': s.isDefault,
              'isActive': s.isActive,
            },
          )
          .toList();
      return _json({'safes': jsonList, 'count': jsonList.length});
    } catch (e) {
      return _error('Failed to fetch safes: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // Shifts (GET)
  // ═══════════════════════════════════════════════════════════════

  Future<Response> _getShifts(Request request) async {
    try {
      final branchId = await _extractBranchId(request, failClosedOnNoIdentity: true);
      final query = _db.select(_db.shifts);
      
      if (branchId != null) {
        final scopedUserIds = await _resolveScopedUserIds(branchId);
        if (scopedUserIds.isNotEmpty) {
          query.where((s) => s.userId.isIn(scopedUserIds));
        } else {
          query.where((s) => s.userId.equals(-1)); // Return nothing if no users accessible
        }
      }
      
      final shifts = await query.get();
      final jsonList = shifts
          .map(
            (s) => <String, dynamic>{
              'id': s.id,
              'startTime': s.startTime.toIso8601String(),
              'endTime': s.endTime?.toIso8601String(),
              'userId': s.userId,
              'openingBalance': s.openingBalance,
              'expectedCash': s.expectedCash,
              'actualCash': s.actualCash,
              'variance': s.variance,
              'status': s.status,
              'notes': s.notes,
              // v151 — the closing report's stored figures, so a pulling
              // client can reprint a shift closed on another terminal.
              'closingSnapshot': s.closingSnapshot,
              'createdAt': s.createdAt.toIso8601String(),
              // Spec 008 / FR-001: surface the recorded operating branch so
              // pulling clients see it via shift_sync_strategy.
              'branchId': s.branchId,
              // Spec 029 / US3 Bug B: surface globalId + lastModifiedAt so
              // ShiftSyncStrategy can dedup by globalId (Tier 1) and apply
              // the lastWriteWins comparison + open-shift carve-out without
              // having to invent a synthetic timestamp from startTime.
              'globalId': s.globalId,
              'lastModifiedAt': s.lastModifiedAt?.toIso8601String(),
            },
          )
          .toList();
      return _json({'shifts': jsonList, 'count': jsonList.length});
    } catch (e) {
      return _error('Failed to fetch shifts: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // Sales Invoices (GET)
  // ═══════════════════════════════════════════════════════════════

  Future<Response> _getSalesInvoices(Request request) async {
    try {
      final branchId = await _extractBranchId(request, failClosedOnNoIdentity: true);
      final warehouseIds = branchId != null ? await _resolveBranchWarehouseIds(branchId) : null;
      final query = _db.select(_db.salesInvoices)
        ..orderBy([(s) => OrderingTerm.desc(s.id)]);
      if (warehouseIds != null && warehouseIds.isNotEmpty) {
        query.where((s) => s.warehouseId.isIn(warehouseIds));
      }
      final invoices = await query.get();

      final jsonList = <Map<String, dynamic>>[];
      for (final inv in invoices) {
        final items = await (_db.select(
          _db.salesInvoiceItems,
        )..where((i) => i.invoiceId.equals(inv.id))).get();
        final itemsJson = items
            .map(
              (item) => <String, dynamic>{
                'id': item.id,
                'invoiceId': item.invoiceId,
                'productId': item.productId,
                'quantity': item.quantity,
                'unitPrice': item.unitPrice,
                'discount': item.discount,
                'total': item.total,
                'costPrice': item.costPrice,
                // SAL-2 (pull): thread the UOM factor so a carton sale
                // replicates with the correct base-unit conversion — else the
                // mirror/client stores quantity_in_base=1.0 and its now-UOM-aware
                // local COGS reports diverge from the authoritative GL.
                'quantityInBase': item.quantityInBase,
                'taxRate': item.taxRate,
                'taxAmount': item.taxAmount,
              },
            )
            .toList();

        jsonList.add({
          'id': inv.id,
          'invoiceNumber': inv.invoiceNumber,
          'customerId': inv.customerId,
          'warehouseId': inv.warehouseId,
          'userId': inv.userId,
          'invoiceDate': inv.invoiceDate.toIso8601String(),
          'subtotal': inv.subtotal,
          'discount': inv.discount,
          'tax': inv.tax,
          'total': inv.total,
          'paid': inv.paid,
          'cashPaid': inv.cashPaid,
          'bankPaid': inv.bankPaid,
          'paymentMethod': inv.paymentMethod,
          'saleType': inv.saleType,
          'status': inv.status,
          'orderNumber': inv.orderNumber,
          'deliveryFee': inv.deliveryFee,
          'notes': inv.notes,
          'costCenterId': inv.costCenterId,
          'items': itemsJson,
        });
      }
      return _json({'sales': jsonList, 'count': jsonList.length});
    } catch (e) {
      debugPrint('[API] _getSalesInvoices error: $e');
      return _error('Failed to fetch sales: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // Held Orders (GET)
  // ═══════════════════════════════════════════════════════════════

  Future<Response> _getHeldOrders(Request request) async {
    try {
      final branchId = await _extractBranchId(request, failClosedOnNoIdentity: true);
      // Spec 151 P1-8b: the query below is NOT branch-scoped, so short-circuit
      // the no-identity sentinel to zero rows — otherwise a tokenless caller
      // reads every branch's parked carts. (Branch-scoping held orders for a
      // logged-in restricted user is a separate pre-existing gap; this only
      // closes the omission vector the P1-8b flag promises.)
      if (branchId == _kNoBranchAccess) {
        return _json({'held_orders': const [], 'count': 0});
      }
      final query = _db.select(_db.heldOrders)
        ..orderBy([(h) => OrderingTerm.desc(h.id)]);
      final orders = await query.get();

      final jsonList = orders.map((o) => {
        'id': o.id,
        'holdNumber': o.holdNumber,
        'subtotal': o.subtotal,
        'discount': o.discount,
        'discountIsPercent': o.discountIsPercent,
        'note': o.note,
        'userId': o.userId,
        'customerId': o.customerId,
        'customerName': o.customerName,
        'createdAt': o.createdAt.toIso8601String(),
      }).toList();

      return _json({'held_orders': jsonList, 'count': jsonList.length});
    } catch (e) {
      debugPrint('[API] _getHeldOrders error: $e');
      return _error('Failed to fetch held orders: $e');
    }
  }

  Future<Response> _getHeldOrderItems(Request request) async {
    try {
      // Spec 151 residual #1 — held_order_items' parent (held_orders) has no
      // branch/warehouse/safe linkage, so per-branch scoping isn't feasible.
      // Mirror _getHeldOrders: close the OMISSION (no identity → zero rows) so a
      // tokenless caller can't read every branch's parked cart items. An
      // identified caller still sees all (documented gap, same as held_orders).
      final branchId =
          await _extractBranchId(request, failClosedOnNoIdentity: true);
      if (branchId == _kNoBranchAccess) {
        return _json({'held_order_items': const [], 'count': 0});
      }
      final items = await _db.select(_db.heldOrderItems).get();

      final jsonList = items.map((i) => {
        'id': i.id,
        'heldOrderId': i.heldOrderId,
        'productId': i.productId,
        'quantity': i.quantity,
        'unitPrice': i.unitPrice,
        'customPrice': i.customPrice,
        'note': i.note,
      }).toList();

      return _json({'held_order_items': jsonList, 'count': jsonList.length});
    } catch (e) {
      debugPrint('[API] _getHeldOrderItems error: $e');
      return _error('Failed to fetch held order items: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // Safe Transactions (GET)
  // ═══════════════════════════════════════════════════════════════

  Future<Response> _getSafeTransactions(Request request) async {
    try {
      final branchId = await _extractBranchId(request, failClosedOnNoIdentity: true);
      final safeIds = branchId != null ? await _resolveBranchSafeIds(branchId) : null;
      final query = _db.select(_db.safeTransactions)
        ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]);
      if (safeIds != null && safeIds.isNotEmpty) {
        query.where((t) => t.safeId.isIn(safeIds));
      }
      final txns = await query.get();

      final jsonList = txns
          .map(
            (t) => <String, dynamic>{
              'id': t.id,
              'voucherNumber': t.voucherNumber,
              'safeId': t.safeId,
              'transactionType': t.transactionType,
              'category': t.category,
              'amount': t.amount,
              'discount': t.discount,
              'balanceAfter': t.balanceAfter,
              'referenceType': t.referenceType,
              'referenceId': t.referenceId,
              'partyId': t.partyId,
              'description': t.description,
              'userId': t.userId,
              'costCenterId': t.costCenterId,
              'employeeId': t.employeeId,
              'disbursementType': t.disbursementType,
              // Carry globalId so clients can dedupe/match by UUID across
              // installs, and deletedAt so client-side pull can replicate
              // admin soft-deletes done on the server.
              'globalId': t.globalId,
              'deletedAt': t.deletedAt?.toIso8601String(),
              'createdAt': t.createdAt.toIso8601String(),
            },
          )
          .toList();

      return _json({'transactions': jsonList, 'count': jsonList.length});
    } catch (e) {
      debugPrint('[API] _getSafeTransactions error: $e');
      return _error('Failed to fetch safe transactions: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // Journal Entries (GET — for client pull sync)
  // ═══════════════════════════════════════════════════════════════

  Future<Response> _getJournalEntries(Request request) async {
    try {
      final branchId = await _extractBranchId(request, failClosedOnNoIdentity: true);
      final query = _db.select(_db.journalEntries);
      if (branchId != null) {
        query.where((e) => e.branchId.equals(branchId));
      }
      final entries = await query.get();
      final jsonList = <Map<String, dynamic>>[];

      // Cluster 028 / Bug 2: pre-load cost-center identity so each JE
      // line can carry `costCenterCode` + `costCenterGlobalId` alongside
      // the raw `costCenterId`. Without these the mirror's sync strategy
      // could only insert the server's numeric id as-is, and any local
      // cost-center id drift (cost centers seeded independently on each
      // side, same code → different ids) made the JE show up under the
      // WRONG cost center on the mirror after the next DeltaPull.
      final allCostCenters = await _db.select(_db.costCenters).get();
      final costCenterById = {for (final c in allCostCenters) c.id: c};

      for (final entry in entries) {
        // JOIN with accounts so each line carries the account's `code` and
        // `globalId`. The client uses these to remap to its local account id
        // (server and client account ids diverge: the chart of accounts is
        // seeded independently on each side, then deduped by code). Without
        // the code, the client's INNER-JOIN against accounts on display
        // filters out every line — Issue 11 (empty journals on client).
        final linesQuery = _db.select(_db.journalEntryLines).join([
          leftOuterJoin(_db.accounts,
              _db.accounts.id.equalsExp(_db.journalEntryLines.accountId)),
        ])
          ..where(_db.journalEntryLines.entryId.equals(entry.id))
          ..orderBy([OrderingTerm.asc(_db.journalEntryLines.id)]);
        final lineRows = await linesQuery.get();
        final headerCc =
            entry.costCenterId != null ? costCenterById[entry.costCenterId] : null;

        jsonList.add({
          'id': entry.id,
          // Phase 5B.2 — ship the JE's globalId so the client's
          // JournalSyncStrategy can dedup deterministically by Tier 0
          // globalId before falling back to the legacy server-id /
          // referenceType-referenceId tiers. Critical for the Phase 5B.1
          // voucher fix to actually dedup across sides.
          'globalId': entry.globalId,
          'entryNumber': entry.entryNumber,
          'description': entry.description,
          'entryDate': entry.entryDate.toIso8601String(),
          'referenceType': entry.referenceType,
          'referenceId': entry.referenceId,
          'isAutoPosted': entry.isAutoPosted,
          'costCenterId': entry.costCenterId,
          'costCenterCode': headerCc?.code,
          'costCenterGlobalId': headerCc?.globalId,
          'branchId': entry.branchId,
          'createdAt': entry.createdAt.toIso8601String(),
          'lines': lineRows.map((row) {
            final l = row.readTable(_db.journalEntryLines);
            final acc = row.readTableOrNull(_db.accounts);
            final lineCc =
                l.costCenterId != null ? costCenterById[l.costCenterId] : null;
            return {
              'id': l.id,
              'accountId': l.accountId,
              'accountCode': acc?.code,
              'accountGlobalId': acc?.globalId,
              'debit': l.debit,
              'credit': l.credit,
              'description': l.description,
              'costCenterId': l.costCenterId,
              'costCenterCode': lineCc?.code,
              'costCenterGlobalId': lineCc?.globalId,
            };
          }).toList(),
        });
      }

      return _json({'journals': jsonList, 'count': jsonList.length});
    } catch (e) {
      debugPrint('[API] _getJournalEntries error: $e');
      return _error('Failed to fetch journal entries: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // Purchase Invoices (GET — for client pull sync)
  // ═══════════════════════════════════════════════════════════════

  Future<Response> _getPurchaseInvoices(Request request) async {
    try {
      final branchId = await _extractBranchId(request, failClosedOnNoIdentity: true);
      final warehouseIds = branchId != null ? await _resolveBranchWarehouseIds(branchId) : null;
      final query = _db.select(_db.purchaseInvoices);
      if (warehouseIds != null && warehouseIds.isNotEmpty) {
        query.where((i) => i.warehouseId.isIn(warehouseIds));
      }
      final invoices = await query.get();
      final jsonList = <Map<String, dynamic>>[];

      for (final inv in invoices) {
        final items = await (_db.select(_db.purchaseInvoiceItems)
              ..where((i) => i.invoiceId.equals(inv.id)))
            .get();

        jsonList.add({
          'id': inv.id,
          'invoiceNumber': inv.invoiceNumber,
          'supplierId': inv.supplierId,
          'warehouseId': inv.warehouseId,
          'invoiceDate': inv.invoiceDate.toIso8601String(),
          'subtotal': inv.subtotal,
          'discount': inv.discount,
          'tax': inv.tax,
          'total': inv.total,
          'paid': inv.paid,
          'status': inv.status,
          'notes': inv.notes,
          'costCenterId': inv.costCenterId,
          'createdAt': inv.createdAt.toIso8601String(),
          'items': items
              .map((i) => {
                    'id': i.id,
                    'productId': i.productId,
                    'quantity': i.quantity,
                    'unitCost': i.unitCost,
                    'total': i.total,
                  })
              .toList(),
        });
      }

      return _json({'purchases': jsonList, 'count': jsonList.length});
    } catch (e) {
      debugPrint('[API] _getPurchaseInvoices error: $e');
      return _error('Failed to fetch purchase invoices: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // Stock Movements (GET — for client pull sync)
  // ═══════════════════════════════════════════════════════════════

  Future<Response> _getStockMovements(Request request) async {
    try {
      final branchId = await _extractBranchId(request, failClosedOnNoIdentity: true);
      final warehouseIds = branchId != null ? await _resolveBranchWarehouseIds(branchId) : null;
      final query = _db.select(_db.stockMovements);
      if (warehouseIds != null && warehouseIds.isNotEmpty) {
        query.where((m) => m.warehouseId.isIn(warehouseIds));
      }
      final movements = await query.get();
      final jsonList = movements.map((m) => {
        'id': m.id,
        'productId': m.productId,
        'warehouseId': m.warehouseId,
        'movementType': m.movementType,
        'quantity': m.quantity,
        'unitCost': m.unitCost,
        'balanceAfter': m.balanceAfter,
        'referenceType': m.referenceType,
        'referenceId': m.referenceId,
        'userId': m.userId,
        'branchId': m.branchId,
        'notes': m.notes,
        'createdAt': m.createdAt.toIso8601String(),
      }).toList();

      return _json({'stock_movements': jsonList, 'count': jsonList.length});
    } catch (e) {
      debugPrint('[API] _getStockMovements error: $e');
      return _error('Failed to fetch stock movements: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // Inventory Balances (GET — for client pull sync)
  // ═══════════════════════════════════════════════════════════════

  Future<Response> _getInventoryBalances(Request request) async {
    try {
      final branchId = await _extractBranchId(request, failClosedOnNoIdentity: true);
      final warehouseIds = branchId != null ? await _resolveBranchWarehouseIds(branchId) : null;
      final query = _db.select(_db.inventoryBalances);
      if (warehouseIds != null && warehouseIds.isNotEmpty) {
        query.where((b) => b.warehouseId.isIn(warehouseIds));
      }
      final balances = await query.get();
      final jsonList = balances.map((b) => {
        'id': b.id,
        'productId': b.productId,
        'warehouseId': b.warehouseId,
        'quantity': b.quantity,
        'reservedQuantity': b.reservedQuantity,
        'averageCost': b.averageCost,
        'lastUpdated': b.lastUpdated.toIso8601String(),
      }).toList();

      return _json({'inventory_balances': jsonList, 'count': jsonList.length});
    } catch (e) {
      debugPrint('[API] _getInventoryBalances error: $e');
      return _error('Failed to fetch inventory balances: $e');
    }
  }


  // ═══════════════════════════════════════════════════════════════
  // Commercial Papers (GET — for client pull sync)
  // ═══════════════════════════════════════════════════════════════

  Future<Response> _getCommercialPapers(Request request) async {
    try {
      // Spec 151 residual #1 — the only branch linkage is safeId, which is
      // NULLABLE (pending/undeposited papers have no safe). So:
      //   • no identity / mis-provisioned (sentinel) → fully closed, zero rows
      //     (an early return, NOT `IN(-1) OR IS NULL`, so the NULL-safe papers
      //     do NOT leak to a tokenless caller — omission closed);
      //   • real branch → its safes' papers + NULL-safe (head-office /
      //     undeposited) papers stay visible (the documented convention);
      //   • full-access (admin) → no filter → all.
      final branchId =
          await _extractBranchId(request, failClosedOnNoIdentity: true);
      if (branchId == _kNoBranchAccess) {
        return _json({'commercial_papers': const [], 'count': 0});
      }
      final safeIds =
          branchId != null ? await _resolveBranchSafeIds(branchId) : null;
      final query = _db.select(_db.commercialPapers);
      if (safeIds != null) {
        query.where((p) => p.safeId.isIn(safeIds) | p.safeId.isNull());
      }
      final papers = await query.get();
      final jsonList = <Map<String, dynamic>>[];

      for (final p in papers) {
        final history = await (_db.select(_db.paperStatusHistory)
              ..where((h) => h.paperId.equals(p.id)))
            .get();

        jsonList.add({
          'id': p.id,
          'paperNumber': p.paperNumber,
          'type': p.type,
          'direction': p.direction,
          'partyId': p.partyId,
          'amount': p.amount,
          'issueDate': p.issueDate.toIso8601String(),
          'dueDate': p.dueDate.toIso8601String(),
          'bankName': p.bankName,
          'bankBranch': p.bankBranch,
          'accountNumber': p.accountNumber,
          'status': p.status,
          'endorsedToPartyId': p.endorsedToPartyId,
          'notes': p.notes,
          'safeId': p.safeId,
          'createdAt': p.createdAt.toIso8601String(),
          'statusHistory': history.map((h) => {
            'id': h.id,
            'fromStatus': h.fromStatus,
            'toStatus': h.toStatus,
            'changedAt': h.changedAt.toIso8601String(),
            'changedBy': h.changedBy,
            'notes': h.notes,
          }).toList(),
        });
      }

      return _json({'commercial_papers': jsonList, 'count': jsonList.length});
    } catch (e) {
      debugPrint('[API] _getCommercialPapers error: $e');
      return _error('Failed to fetch commercial papers: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // Sync Endpoints (Parties, Warehouses, Users — GET)
  // ═══════════════════════════════════════════════════════════════

  Future<Response> _getParties(Request request) async {
    try {
      final parties = await _db.select(_db.parties).get();
      // Include `code`, `globalId`, `accountId`, `groupId` so the client's
      // sync strategy can dedupe by `globalId` and reflect the authoritative
      // code that the server generated (e.g. CUST-00001). Dropping these
      // fields was the source of the party-duplication bug on client nodes.
      final jsonList = parties
          .map(
            (p) => <String, dynamic>{
              'id': p.id,
              'globalId': p.globalId,
              'code': p.code,
              'name': p.name,
              'phone': p.phone,
              'address': p.address,
              'taxId': p.taxId,
              'isCustomer': p.isCustomer,
              'isSupplier': p.isSupplier,
              'isDeliveryCompany': p.isDeliveryCompany,
              'isFavorite': p.isFavorite,
              'balance': p.balance,
              'creditLimit': p.creditLimit,
              'fixedDiscount': p.fixedDiscount,
              'priceLevel': p.priceLevel,
              'isActive': p.isActive,
              'accountId': p.accountId,
              'groupId': p.groupId,
            },
          )
          .toList();
      return _json({'parties': jsonList, 'count': jsonList.length});
    } catch (e) {
      return _error('Failed to fetch parties: $e');
    }
  }

  Future<Response> _getBranches(Request request) async {
    try {
      final branchId = await _extractBranchId(request);
      final query = _db.select(_db.branches);
      if (branchId != null) {
        query.where((b) => b.id.equals(branchId));
      }
      final branches = await query.get();
      final jsonList = branches
          .map(
            (b) => <String, dynamic>{
              'id': b.id,
              'name': b.name,
              'code': b.code,
              'address': b.address,
              'phone': b.phone,
              'isActive': b.isActive,
              'costCenterId': b.costCenterId,
              // Cluster 023 / Issue 4 — regionId was missing from this
              // payload, so every pull-sync wiped the branch↔region link
              // a mirror admin had just saved (the put endpoint persisted
              // it correctly, but the next GET dropped it on the floor).
              // globalId is added alongside so BranchSyncStrategy can match
              // on the deterministic key instead of falling back to the
              // name-only tier (R8 SYNC-WARN). Same reasoning for code.
              'regionId': b.regionId,
              'globalId': b.globalId,
            },
          )
          .toList();
      return _json({'branches': jsonList, 'count': jsonList.length});
    } catch (e) {
      return _error('Failed to fetch branches: $e');
    }
  }

  Future<Response> _getRegions(Request request) async {
    try {
      final regionsList = await _db.select(_db.regions).get();
      final jsonList = regionsList
          .map(
            (r) => <String, dynamic>{
              'id': r.id,
              'name': r.name,
              'address': r.address,
              'phone': r.phone,
              'isActive': r.isActive,
              'costCenterId': r.costCenterId,
              'globalId': r.globalId,
            },
          )
          .toList();
      return _json({'regions': jsonList, 'count': jsonList.length});
    } catch (e) {
      return _error('Failed to fetch regions: $e');
    }
  }

  Future<Response> _getUserRegionAccess(Request request) async {
    try {
      final accessData = await _db.select(_db.userRegionAccess).get();
      final jsonList = accessData
          .map((a) => <String, dynamic>{
                'userId': a.userId,
                'regionId': a.regionId,
              })
          .toList();
      return _json({'user_region_access': jsonList, 'count': jsonList.length});
    } catch (e) {
      debugPrint('[API] Error fetching user region access: $e');
      return _error('Failed to fetch user region access: $e');
    }
  }

  Future<Response> _getCostCenters(Request request) async {
    try {
      final branchId = await _extractBranchId(request);
      final query = _db.select(_db.costCenters);

      if (branchId == _kNoBranchAccess) {
        // Spec 151 residual #2 (D-06 fail-open): a mis-provisioned user resolves
        // to the -1 sentinel. Without this branch, the lookup below returns null,
        // the filter is skipped, and the ENTIRE cost-center table leaks. Fail CLOSED.
        query.where((c) => c.id.equals(_kNoBranchAccess));
      } else if (branchId != null) {
        // Resolve the branch to get its costCenterId
        final branch = await (_db.select(_db.branches)
              ..where((b) => b.id.equals(branchId)))
            .getSingleOrNull();

        if (branch != null && branch.costCenterId != null) {
          // Return the branch's cost center and potentially its children
          // For now, let's just return the primary cost center assigned to the branch
          query.where((c) => c.id.equals(branch.costCenterId!));
        }
      }

      final centers = await query.get();
      final jsonList = centers
          .map(
            (c) => <String, dynamic>{
              'id': c.id,
              'code': c.code,
              'name': c.name,
              'parentId': c.parentId,
              'isActive': c.isActive,
              'createdAt': c.createdAt.toIso8601String(),
            },
          )
          .toList();
      return _json({'cost_centers': jsonList, 'count': jsonList.length});
    } catch (e) {
      return _error('Failed to fetch cost centers: $e');
    }
  }

  Future<Response> _getAccounts(Request request) async {
    try {
      final accounts = await _db.select(_db.accounts).get();
      final jsonList = accounts
          .map(
            (a) => <String, dynamic>{
              'id': a.id,
              'code': a.code,
              'name': a.name,
              'accountType': a.accountType,
              'accountNature': a.accountNature,
              'normalBalance': a.normalBalance,
              'level': a.level,
              'parentId': a.parentId,
              'balance': a.balance,
              'isSystem': a.isSystem,
              'isActive': a.isActive,
              'isHiddenFromEntries': a.isHiddenFromEntries,
            },
          )
          .toList();
      return _json({'accounts': jsonList, 'count': jsonList.length});
    } catch (e) {
      return _error('Failed to fetch accounts: $e');
    }
  }

  Future<Response> _getWarehouses(Request request) async {
    try {
      final branchId = await _extractBranchId(request);
      final query = _db.select(_db.warehouses);
      if (branchId != null) {
        query.where((w) => w.branchId.equals(branchId));
      }
      final warehouses = await query.get();
      final jsonList = warehouses
          .map(
            (w) => <String, dynamic>{
              'id': w.id,
              'name': w.name,
              'branchId': w.branchId,
              'isDefault': w.isDefault,
              'isActive': w.isActive,
            },
          )
          .toList();
      return _json({'warehouses': jsonList, 'count': jsonList.length});
    } catch (e) {
      return _error('Failed to fetch warehouses: $e');
    }
  }

  // Spec 029 / US3 Bug A — admin self-heal flag.
  // Production observed admin (id=1) absent from the `/api/users`
  // response despite the source containing `u.id.equals(1)`. Root cause
  // could be: row physically deleted, row renamed to `__dup_1_admin`,
  // or `drift_postgres` empty-IN-list semantics on PostgreSQL. The
  // defensive fix runs ONCE per process: at the first `_getUsers` call,
  // if the bootstrap admin is missing or corrupted, restore it BEFORE
  // executing the query. See contracts/bug-a-admin-self-heal.md.
  bool _adminSelfHealRan = false;

  Future<Response> _getUsers(Request request) async {
    try {
      await _ensureBootstrapAdminOnce();

      final branchId = await _extractBranchId(request);
      final query = _db.select(_db.users);

      if (branchId != null) {
        // Spec 029 / US3 Bug A — materialize the union of allowed user
        // IDs as a Dart Set<int> instead of relying on SQL OR-of-isIn
        // semantics. Two production hypotheses motivated this rewrite:
        //   1. `userIds.toList()` could be empty when the requesting
        //      client's branch has no userBranchAccess rows for the
        //      admin; on `drift_postgres` an `id IN ()` clause is a
        //      defensive minefield (versions vary).
        //   2. `roleId.isIn(systemRoleIds)` similarly returns nothing
        //      when no role is flagged isSystemRole=true (which has
        //      been observed in the field after a corrupt sync).
        // By computing the concrete set of allowed user IDs in Dart
        // and then doing ONE `id IN (concrete-list)` against `users`,
        // we eliminate both empty-IN-list edge cases. The set ALWAYS
        // contains 1 (admin), so even an otherwise empty union still
        // returns at least the admin row.
        final accessibleUserIds = await (_db.select(_db.userBranchAccess)
              ..where((a) => a.branchId.equals(branchId)))
            .get();

        final systemRoles = await (_db.select(_db.roles)
              ..where((r) => r.isSystemRole.equals(true)))
            .get();
        final systemRoleIds = systemRoles.map((r) => r.id).toList();

        // Enumerate users whose role is a system role. We do this in
        // Dart to keep one consistent IN-list shape for the final query.
        final usersInSystemRoles = systemRoleIds.isEmpty
            ? <User>[]
            : await (_db.select(_db.users)
                  ..where((u) => u.roleId.isIn(systemRoleIds)))
                .get();

        // The bootstrap admin is NOT guaranteed to live at id=1. Since the
        // 2026-05-10 corrective patch, `_ensureBootstrapAdminOnce` inserts a
        // restored admin without forcing an id — forcing 1 is what
        // drift_postgres rejected against an already-advanced sequence. So a
        // literal `1` here is not the guarantee it looks like: an admin at
        // id≠1 that has no userBranchAccess row for this branch and whose role
        // is not flagged isSystemRole falls out of the set entirely, which is
        // Feature 011 / Issue 9 — the exact bug this materialize-set exists to
        // prevent. Resolve the row by username so the guarantee follows the
        // admin wherever it actually is, and keep the literal as a fallback
        // for the window where no admin row exists at all.
        final bootstrapAdmin = await (_db.select(_db.users)
              ..where((u) => u.username.equals('admin'))
              ..limit(1))
            .getSingleOrNull();

        final allowedIds = <int>{
          ...accessibleUserIds.map((a) => a.userId),
          ...usersInSystemRoles.map((u) => u.id),
          if (bootstrapAdmin != null) bootstrapAdmin.id,
          1, // bootstrap admin — always included (Feature 011 / Issue 9)
        };

        query.where((u) => u.id.isIn(allowedIds.toList()));
      }

      final users = await query.get();
      final jsonList = users
          .map(
            (u) => <String, dynamic>{
              'id': u.id,
              'username': u.username,
              'displayName': u.displayName,
              'roleId': u.roleId,
              'defaultScreen': u.defaultScreen,
              'isLocked': u.isLocked,
              'isActive': u.isActive,
              'maxDiscountPercent': u.maxDiscountPercent,
              'discountLimitIsPercent': u.discountLimitIsPercent,
              'cardCode': u.cardCode,
              // Include hashed credentials so clients can authenticate
              // locally. Values are already PBKDF2-hashed — safe over LAN.
              'passwordHash': u.passwordHash,
              'passwordSalt': u.passwordSalt,
              'pin': u.pin,
            },
          )
          .toList();
      return _json({'users': jsonList, 'count': jsonList.length});
    } catch (e) {
      return _error('Failed to fetch users: $e');
    }
  }

  /// Spec 029 / US3 Bug A — restore the bootstrap admin if missing or
  /// corrupted. Idempotent and runs at most ONCE per process lifetime
  /// (gated by `_adminSelfHealRan`). Three corruption modes are covered:
  ///
  ///   1. Row at `id=1` does not exist — INSERT a fresh admin row.
  ///   2. Row at `id=1` has `username='__dup_1_admin'` — UPDATE back
  ///      to canonical `username='admin'`. The Issue 9 chain failure
  ///      leaves the row in this state on the CLIENT side; the same
  ///      taint can flow back to a SERVER if a careless cleanup runs.
  ///   3. Row at `id=1` has `isActive=false` paired with
  ///      `username='__dup_1_admin'` — same fix as (2) plus reactivate.
  ///
  /// On a healthy install this method does no work after the first
  /// call. The `[SYNC-WARN]` line is emitted only when corruption was
  /// detected, so the diagnostic log stays clean otherwise.
  ///
  /// See specs/029-sync-regression-hardening/contracts/bug-a-admin-self-heal.md.
  Future<void> _ensureBootstrapAdminOnce() async {
    if (_adminSelfHealRan) return;
    _adminSelfHealRan = true;

    // Spec 029 / US3 Bug A — corrective patch: the original
    // implementation looked up admin by `id=1` only. On a beta server
    // where the bootstrap admin lives at a different id (e.g. id=2 —
    // observed 2026-05-10 when the PG seed sequence advanced before
    // the admin row was created), the id=1 lookup returned null,
    // `missing=true` evaluated, and we tried to INSERT with explicit
    // `id: Value(1)` — which `drift_postgres` rejected against the
    // existing autoincrement sequence on `users.id`. Every `/api/users`
    // request then failed (the exception bubbled up); clients
    // pulse-retried the endpoint, masquerading as products/inventory
    // screen lag.
    //
    // Corrected logic:
    //   1. Look up admin BY USERNAME first. If `username='admin'`
    //      exists at ANY id, no heal is needed — return.
    //   2. Otherwise check id=1 specifically for the `__dup_1_admin`
    //      rename case (Issue 9 chain failure on the client side).
    //      If found, rename it back to canonical 'admin'.
    //   3. Otherwise, INSERT a fresh admin row. Do NOT force id=1 —
    //      let the autoincrement sequence assign one. Forcing id=1
    //      is what crashed in production; the bootstrap admin's id
    //      is not load-bearing in any other code path (clients sync
    //      by username/role and the materialize-set in `_getUsers`
    //      always includes id=1 by literal — irrelevant when the row
    //      lives elsewhere because the response comes back via the
    //      `id IN (concrete-list)` clause regardless).
    //   4. The whole block is wrapped in try/catch so a worst-case
    //      failure logs a SYNC-WARN line but does NOT break
    //      `/api/users` — the materialize-set clause already pulls
    //      the (possibly different-id) admin into the response.
    try {
      final adminByName = await (_db.select(_db.users)
            ..where((u) => u.username.equals('admin'))
            ..limit(1))
          .getSingleOrNull();

      if (adminByName != null) {
        // Admin exists by username at some id. Healthy install.
        return;
      }

      final id1Row = await (_db.select(_db.users)
            ..where((u) => u.id.equals(1))
            ..limit(1))
          .getSingleOrNull();

      final renamed =
          id1Row != null && id1Row.username == '__dup_1_admin';

      if (renamed) {
        // Renamed case: preserve the existing password hash/salt;
        // only restore the username + isActive flag. The operator's
        // existing password keeps working.
        await (_db.update(_db.users)..where((u) => u.id.equals(1))).write(
          const UsersCompanion(
            username: Value('admin'),
            isActive: Value(true),
          ),
        );
        await DiagnosticLogger.log(
          'SYNC-WARN',
          'admin-self-heal triggered: renamed __dup_1_admin → admin',
        );
        return;
      }

      // Genuinely missing — INSERT without forcing an id, letting the
      // autoincrement sequence assign one. The default password is
      // 'admin' so the operator can log in and rotate.
      final salt = SecurityService.generateSalt();
      final passwordHash = SecurityService.hashPassword('admin', salt);
      await _db.into(_db.users).insertOnConflictUpdate(
            UsersCompanion.insert(
              username: 'admin',
              passwordHash: passwordHash,
              passwordSalt: Value(salt),
              displayName: 'مدير النظام',
              roleId: const Value(1),
              isActive: const Value(true),
              isLocked: const Value(false),
              defaultScreen: const Value('pos'),
            ),
          );
      await DiagnosticLogger.log(
        'SYNC-WARN',
        'admin-self-heal triggered: inserted fresh admin row '
            '(autoincrement id; no explicit id=1)',
      );
    } catch (e, stack) {
      // Worst case: log + continue. The materialize-set clause in
      // `_getUsers` will still pull whatever admin row exists.
      // Without this catch a single PG failure would break every
      // `/api/users` response — that was the regression observed
      // 2026-05-10 (held_orders branch_id failure plus this one
      // double-bagged the lag).
      await DiagnosticLogger.log(
        'SYNC-WARN',
        'admin-self-heal FAILED: $e\n$stack',
      );
    }
  }

  /// Account Mappings — read-only for client sync
  Future<Response> _getAccountMappings(Request request) async {
    try {
      final mappings = await _db.select(_db.accountMappings).get();
      final jsonList = mappings.map((m) => <String, dynamic>{
        'id': m.id,
        'purpose': m.purpose,
        'accountId': m.accountId,
        'costCenterId': m.costCenterId,
        'description': m.description,
        'updatedAt': m.updatedAt.toIso8601String(),
      }).toList();
      return _json({'account_mappings': jsonList, 'count': jsonList.length});
    } catch (e) {
      return _error('Failed to fetch account mappings: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // Heartbeat
  // ═══════════════════════════════════════════════════════════════

  // EXEMPT-PER-USER: device-level keepalive; per-user gating makes no
  // semantic sense — the heartbeat is sent by the device, not a user.
  // (Spec 077 Batch 5 allow-list — see §6 of endpoint-permission-map.md)
  Future<Response> _heartbeat(Request request) async {
    try {
      final body = await request.readAsString();
      final data = json.decode(body) as Map<String, dynamic>;
      final clientId = data['clientId'] as String? ?? 'unknown';

      NetworkService.instance.registerClient(clientId);

      return _json({
        'status': 'ok',
        'serverTime': DateTime.now().toIso8601String(),
        'clientId': clientId,
      });
    } catch (e) {
      return _error('Heartbeat failed: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // Digital Menu
  // ═══════════════════════════════════════════════════════════════

  Future<Response> _getMenuData(Request request) async {
    try {
      final categories = await _db.select(_db.categories).get();
      final products = _db.select(_db.products)
        ..where((u) => u.isActive.equals(true));
      final productsList = await products.get();

      return _json({
        'categories': categories
            .map((c) => {'id': c.id, 'name': c.name, 'icon': c.iconName})
            .toList(),
        'products': productsList
            .map(
              (p) => {
                'id': p.id,
                'name': p.name,
                'price': p.salePrice,
                'categoryId': p.categoryId,
                'description': p.description,
              },
            )
            .toList(),
      });
    } catch (e) {
      return _error('Failed to fetch menu data: $e');
    }
  }

  Future<Response> _getMenuDisplay(Request request) async {
    return Response.ok(
      _buildMenuHtml(),
      headers: {'Content-Type': 'text/html; charset=utf-8'},
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // CFD Display & Stream
  // ═══════════════════════════════════════════════════════════════

  Future<Response> _cfdStream(Request request) async {
    final stream = CfdService.instance.connect();
    return Response.ok(
      stream,
      headers: {
        'Content-Type': 'text/event-stream',
        'Cache-Control': 'no-cache',
        'Connection': 'keep-alive',
      },
    );
  }

  Future<Response> _getCfdDisplay(Request request) async {
    return Response.ok(
      _buildCfdHtml(),
      headers: {'Content-Type': 'text/html; charset=utf-8'},
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // Branch Scope Helpers
  // ═══════════════════════════════════════════════════════════════

  /// Spec 151 residual #2 (D-06 fail-open) — impossible branch id used as a
  /// fail-CLOSED sentinel. A mis-provisioned (non-privileged, zero-assignment)
  /// user, and any branch that resolves to no warehouses/safes, are scoped to
  /// this so `col IN (-1)` matches nothing instead of leaking every row.
  static const int _kNoBranchAccess = -1;

  /// Raw parse of `?branch_id=` (unchanged behavior, kept private).
  /// Spec 151 D-06 — split out of the old `_extractBranchId` so the async
  /// clamp below can reuse the pure query-param read.
  int? _rawBranchId(Request request) {
    final param = request.requestedUri.queryParameters['branch_id'];
    if (param == null || param.isEmpty) return null;
    return int.tryParse(param);
  }

  /// Spec 151 D-06 — resolve the EFFECTIVE branch scope for a read request,
  /// binding the client-supplied `?branch_id=` to the CALLING USER's
  /// accessible branches (server-side). Stops a per-branch client from
  /// reading another branch by passing a foreign branch_id.
  ///
  /// - No verified session identity (token absent) → requested honored. This
  ///   path is REQUIRED by the tokenless sync machinery: `ClientFirstSyncService`
  ///   and the boot-time delta pull run BEFORE any user logs in and must read
  ///   the full master + transaction set to seed/replicate the local DB. Since
  ///   they carry no session token, fail-closing here would brick new-client
  ///   provisioning and silently poison delta watermarks. See below.
  /// - Full-access user (admin / financial-manager / userId==1 → allowed==[])
  ///   → requested honored (null = all branches).
  /// - Restricted user: requested ∈ allowed → honored; null or foreign
  ///   → clamp to the user's home branch (getUserBranchId, else allowed.first).
  ///   Never returns a branch outside `allowed`.
  ///
  /// Spec 151 (P1-8): the FORGERY/IMPERSONATION vector is CLOSED — `userId` is
  /// derived server-side from an HMAC-signed session token bound to a credential
  /// check ([ApiSessionToken]), so a holder of the shared bearer can no longer
  /// forge `uid=1` (admin) nor assert any other user's identity to bypass the
  /// clamp. A legit restricted user always sends a valid token → is clamped to
  /// their branches.
  ///
  /// RESIDUAL (deferred, documented): a bearer holder that OMITS the session
  /// token gets `requested` (broad reads) — the pre-existing "shared bearer =
  /// read trust" model. Closing omission for transactional reads requires an
  /// AUTHENTICATED-SYNC redesign (a device/service session minted at pairing,
  /// persisted for boot, and threaded through ClientFirstSyncService /
  /// SyncService._fetchJson / DeltaPull) so the sync path is never tokenless —
  /// otherwise fail-closing here breaks provisioning. Tracked as the P1-8
  /// follow-up; compensating controls: trusted LAN, TLS, guarded bearer token.
  Future<int?> _extractBranchId(Request request,
      {bool failClosedOnNoIdentity = false}) async {
    final requested = _rawBranchId(request);
    final userId = ApiUserCtx.userIdOf(request);
    if (userId == null) {
      // Spec 151 P1-8b: TRANSACTIONAL endpoints pass failClosedOnNoIdentity:true
      // → no verified identity yields the impossible sentinel (zero rows),
      // closing the omission vector. REFERENCE endpoints keep the default
      // (false) → honor `requested`, because the tokenless provisioning path
      // (ClientFirstSyncService / boot delta-pull, pre-login) must read shared
      // master data to seed a new client — fail-closing it would brick setup.
      return failClosedOnNoIdentity ? _kNoBranchAccess : requested;
    }
    final allowed = await _db.getUserAccessibleBranchIds(userId);
    if (allowed.isEmpty) {
      // Spec 151 residual #2 (D-06 fail-open): an empty list is ambiguous — it
      // means full access for a privileged user, but "no assignment" for a
      // mis-provisioned non-privileged user. Split so the latter fails CLOSED
      // (scoped to the impossible sentinel) instead of reading every branch.
      if (await _db.isFullBranchAccessUser(userId)) {
        return requested; // (a) privileged → full access (null = all branches)
      }
      return _kNoBranchAccess; // (b) mis-provisioned → empty scope
    }
    if (requested != null && allowed.contains(requested)) return requested;
    final home = await _db.getUserBranchId(userId); // clamp foreign/null to home
    return (home != null && allowed.contains(home)) ? home : allowed.first;
  }

  /// Resolve branch → warehouse IDs from database.
  Future<List<int>> _resolveBranchWarehouseIds(int branchId) async {
    final warehouses = await (_db.select(_db.warehouses)
          ..where((w) => w.branchId.equals(branchId)))
        .get();
    final ids = warehouses.map((w) => w.id).toList();
    // Spec 151 residual #2 (D-06 fail-open): every consumer guards on
    // `if (ids.isNotEmpty)` and DROPS the branch filter when the list is empty
    // (an empty list ends up meaning ALL rows). Return the sentinel so a scoped
    // read of the sentinel branch — or a real branch with no warehouses — yields
    // ZERO rows via `warehouseId IN (-1)`, never the whole table.
    return ids.isEmpty ? const [_kNoBranchAccess] : ids;
  }

  /// Resolve branch → user IDs that have access to this branch.
  Future<List<int>> _resolveScopedUserIds(int branchId) async {
    // Spec 151 residual #2 (D-06 fail-open): the -1 sentinel means "no branch
    // access" — return it directly. Otherwise the always-added system-role users
    // below would leak admin/FM shift cash/variance to a mis-provisioned user
    // (shifts.userId IN (system ids)). With [-1], the filter matches nothing.
    if (branchId == _kNoBranchAccess) return const [_kNoBranchAccess];
    final accessibleUserIds = await (_db.select(_db.userBranchAccess)
          ..where((a) => a.branchId.equals(branchId)))
        .get();
    final userIds = accessibleUserIds.map((a) => a.userId).toSet();
    
    final systemRoles = await (_db.select(_db.roles)
          ..where((r) => r.isSystemRole.equals(true)))
        .get();
    final systemRoleIds = systemRoles.map((r) => r.id).toList();

    if (systemRoleIds.isNotEmpty) {
      final systemUsers = await (_db.select(_db.users)
            ..where((u) => u.roleId.isIn(systemRoleIds)))
          .get();
      userIds.addAll(systemUsers.map((u) => u.id));
    }
    return userIds.toList();
  }

  /// Resolve branch → safe IDs from database.
  Future<List<int>> _resolveBranchSafeIds(int branchId) async {
    final safes = await (_db.select(_db.safes)
          ..where((s) => s.branchId.equals(branchId)))
        .get();
    final ids = safes.map((s) => s.id).toList();
    // Spec 151 residual #2 (D-06 fail-open): same empty-list-drops-filter
    // hazard as _resolveBranchWarehouseIds — the sentinel keeps the scope
    // closed so `safeId IN (-1)` returns zero rows instead of every safe txn.
    return ids.isEmpty ? const [_kNoBranchAccess] : ids;
  }

  // ═══════════════════════════════════════════════════════════════
  // P3.1 — Delta Pull
  // ═══════════════════════════════════════════════════════════════

  /// Allowlist of tables a client can pull via `/api/sync/pull`.
  /// Must match [DeltaPullService.pullTables] on the client. High-volume
  /// transaction tables are intentionally excluded — they flow via the
  /// client's outbox, not delta pull.
  /// Allowlist of tables a client can pull via `/api/sync/pull`.
  /// Mirrors [DeltaPullService.pullTables] on the client (a list, because the
  /// client pulls in FK-dependency order; here a set, because we only
  /// validate membership). All 40 sync-hardened tables — transactional data
  /// flows via delta pull as well, so a long-offline client can catch up
  /// without a full dump.
  static const _syncPullTables = <String>{
    // Tier 0
    'fiscal_years', 'cost_centers', 'accounts', 'roles', 'currencies',
    'categories', 'units', 'regions', 'party_groups', 'safes', 'printers',
    // Tier 1
    'accounting_periods', 'branches', 'warehouses', 'price_lists',
    'users', 'shifts',
    'activity_logs',      // → users (FK on user_id); all clients share the audit trail
    // Tier 2
    'parties', 'products', 'price_list_items', 'product_barcodes',
    'product_units',
    // Tier 3 — transactional headers
    'sales_invoices', 'purchase_invoices', 'held_orders',
    'sales_orders', 'purchase_orders', 'quotations', 'payments',
    'journal_entries', 'safe_transactions', 'commercial_papers',
    'stock_movements',
    // Tier 4 — transactional items
    'sales_invoice_items', 'purchase_invoice_items', 'held_order_items',
    'sales_order_items', 'purchase_order_items', 'quotation_items',
    'payment_allocations',
  };

  /// Phase 5A.1 (Issue 5) — per-table branch column for the `/api/sync/pull`
  /// scope filter. Tables in this map have their rows filtered to the
  /// caller's `?branch_id=` (when provided) plus rows where the column is
  /// NULL (legacy data without a branch link must remain visible to keep
  /// historical reports intact).
  ///
  /// Tables NOT in this map are universal master data — every paired client
  /// needs the full set (chart of accounts, products, parties, units, etc.)
  /// regardless of which branch they're physically in. Adding a table here
  /// must be done together with confirming the column exists in the schema
  /// — an unknown column produces a SQL error at request time.
  ///
  /// `safe_transactions` and `*_lines/items` rows have no direct branch
  /// column; they inherit scope through their parent (safe.branch_id,
  /// invoice.branch_id, etc.). Filtering them at this layer would need a
  /// JOIN. For now they pass through and the client-side branch scope (5C)
  /// handles the visual filter. The server-side cleanup helper (5A.4)
  /// removes any cross-branch rows that may have already landed locally.
  // Feature 011 / Issue PG-SCHEMA — only list tables whose Drift schema
  // ACTUALLY declares a `branch_id` column. The previous map (Spec 008
  // FR-005 era) included `sales_orders`, `purchase_orders`, `quotations`,
  // `commercial_papers` based on an aspirational migration plan that
  // never landed: those tables exist in Drift WITHOUT a branchId field
  // (sales_purchase_tables.dart:325-346, 376-397; quotation_tables.dart:6-30;
  // commercial_finance_tables.dart:11-36). On a PostgreSQL server the
  // column genuinely does not exist, so DeltaPull blew up every minute
  // with `column "branch_id" does not exist` (server_errors.log dated
  // 2026-05-05) and clients couldn't sync ANY of those four tables.
  //
  // Removing the four bad entries means: branch-scoped clients now see
  // ALL rows from these tables (no server-side branch filter). That is
  // the correct fallback — until a migration adds a real branchId column
  // to each, the client-side branch scope (5C) handles the visual
  // narrowing. The orders/quotations/papers volume is low enough that
  // the unscoped sync isn't a perf problem.
  // Spec 029 / corrective patch (2026-05-10) — `held_orders` removed.
  // Same root cause as the Feature 011 / PG-SCHEMA fix: the table's
  // Drift schema (sales_purchase_tables.dart:282-300) does NOT declare
  // a `branchId` column, so on PostgreSQL the column genuinely does
  // not exist. Every DeltaPull from a branch-scoped client failed
  // with `column "branch_id" does not exist` at api_handler.dart:1925.
  // The frontend kept retrying, masquerading as products/inventory
  // screen lag. Removing the entry means held_orders flows unscoped
  // to all clients — held orders are short-lived and per-cashier
  // anyway, so the cross-branch visibility is harmless.
  static const _syncPullBranchColumn = <String, String>{
    'sales_invoices': 'branch_id',
    'purchase_invoices': 'branch_id',
    'journal_entries': 'branch_id',
    'stock_movements': 'branch_id',
    'activity_logs': 'branch_id',
  };

  /// Spec 151 P1-8b — TRANSACTIONAL delta-pull tables (Tier 3 + Tier 4 +
  /// shift/audit movement tables). These carry per-branch business data and
  /// MUST NOT be served to a caller with no verified identity (no session
  /// token). The per-column scoping above only covers the 5 tables that have a
  /// `branch_id`; the rest (orders, quotations, payments, commercial papers,
  /// held orders, safe transactions, and every *_items child) have no branch
  /// column, so without this denylist they would return in FULL to a tokenless
  /// caller — the omission leak this closes. A logged-in user still pulls them
  /// (scoped by branch where a column exists; full otherwise — pre-existing).
  /// DENYLIST (not allowlist) so a *new* reference table is never accidentally
  /// blocked from tokenless provisioning; a new TRANSACTIONAL table must be
  /// added here.
  static const _transactionalPullTables = <String>{
    'sales_invoices', 'purchase_invoices', 'held_orders', 'sales_orders',
    'purchase_orders', 'quotations', 'payments', 'journal_entries',
    'safe_transactions', 'commercial_papers', 'stock_movements', 'shifts',
    'activity_logs', 'sales_invoice_items', 'purchase_invoice_items',
    'held_order_items', 'sales_order_items', 'purchase_order_items',
    'quotation_items', 'payment_allocations',
  };

  /// Spec 151 P1-8b — exposed so a guard test can assert this stays IDENTICAL
  /// to `DeltaPullService.branchScopedPullTables`. If the two drift apart, one
  /// side silently reopens either the tokenless transactional leak (server
  /// serves a table the client thinks is denied) or the watermark poison
  /// (client seeds a watermark the server denies).
  @visibleForTesting
  static Set<String> get transactionalPullTablesForTest =>
      _transactionalPullTables;

  /// GET /api/sync/pull?table=X&since=Y[&branch_id=Z]
  ///
  /// Returns all rows from [table] whose `last_modified_at > since` (epoch
  /// seconds). Omitting `since` performs a full table dump (first-time sync).
  /// When `branch_id` is supplied AND the table appears in
  /// [_syncPullBranchColumn], rows are scoped to that branch (plus any rows
  /// where the column is NULL — legacy data). Admin clients omit the
  /// parameter and continue to see every branch.
  ///
  /// Response: `{ "rows": [...], "serverTime": <epoch_seconds>, "count": N }`
  ///
  /// Row keys are raw SQL column names (snake_case). The client's
  /// [DeltaPullService._upsertRow] does `INSERT OR REPLACE INTO $table ($cols)
  /// VALUES (...)` using these keys directly, so changing the shape here
  /// would break the upsert.
  Future<Response> _getSyncPull(Request request) async {
    try {
      final table = request.requestedUri.queryParameters['table'];
      if (table == null || table.isEmpty) {
        return _error('Missing "table" query parameter', statusCode: 400);
      }
      if (!_syncPullTables.contains(table)) {
        return _error(
          'Table "$table" is not available for delta pull',
          statusCode: 403,
        );
      }

      final sinceStr = request.requestedUri.queryParameters['since'];
      final int? since = sinceStr == null ? null : int.tryParse(sinceStr);

      // Spec 151 P1-8b — a TRANSACTIONAL table requires a verified identity.
      // Column scoping below only covers tables WITH a branch_id; the rest
      // would leak in FULL to a tokenless caller. Deny outright with NO forward
      // serverTime (null) so a client ignoring its own skip can't advance the
      // watermark and strand its post-login backfill. Reference/master tables
      // fall through and stay readable (tokenless provisioning must work).
      if (ApiUserCtx.userIdOf(request) == null &&
          _transactionalPullTables.contains(table)) {
        return _json({'rows': const [], 'count': 0, 'serverTime': null});
      }

      // Phase 5A.1 — derive the branch filter clause. Empty when admin or
      // when the table is universal master data (not in the map).
      // Spec 151 P1-8b: fail closed on no identity. A master table (branchCol
      // == null) stays full even with the sentinel (branchFilterActive stays
      // false); a branch-scoped table with no identity → sentinel → zero rows.
      final branchId =
          await _extractBranchId(request, failClosedOnNoIdentity: true);
      final branchCol = _syncPullBranchColumn[table];
      // The branch predicate is now assembled with the other conditions
      // below (the two pre-built `branchClause` / `branchClauseStandalone`
      // string fragments are gone — the query is built from a condition list
      // so the cursor predicate can join it without string surgery).
      final bool branchFilterActive = branchId != null && branchCol != null;

      // ── Page size (Spec: bounded delta pull) ────────────────────────────
      // This query used to run with NO LIMIT at all. A table with a large
      // backlog — or any `since=null` first pull — materialised the ENTIRE
      // table into memory, JSON-encoded it, and shipped it in one response,
      // all on the same isolate that serves every other client and the
      // server's own UI. On `activity_logs` / `stock_movements` /
      // `sales_invoice_items` in a store with a year of history that is
      // hundreds of thousands of rows: the server froze and every other
      // client's request queued behind it. That is the single biggest cause
      // of "one or two clients load while the rest are fine" — whichever
      // device had a stale/absent watermark pulled the whole table.
      //
      // The client now drains a table page by page and only advances its
      // watermark once the last page has landed, so the contract is
      // unchanged from its point of view — just bounded per request.
      final rawLimit = int.tryParse(
              request.requestedUri.queryParameters['limit'] ?? '') ??
          _syncPullDefaultLimit;
      final limit = rawLimit.clamp(1, _syncPullMaxLimit);

      // Keyset cursor for pages 2..N. `(COALESCE(last_modified_at,0), id)` is
      // the sort key, so the tie-breaker on `id` is what makes paging exact
      // when many rows share one timestamp — a plain OFFSET or a
      // timestamp-only cursor would silently skip or repeat those rows.
      final cursorTs =
          int.tryParse(request.requestedUri.queryParameters['cursorTs'] ?? '');
      final cursorId =
          int.tryParse(request.requestedUri.queryParameters['cursorId'] ?? '');
      final bool cursorActive = cursorTs != null && cursorId != null;

      // Build the query. Table is from an allowlist, so interpolation is safe.
      // Ordering by (last_modified_at, id) keeps paging deterministic and the
      // watermark advancing monotonically.
      final conditions = <String>[];
      final vars = <Variable>[];

      if (since != null) {
        conditions.add('last_modified_at IS NOT NULL AND last_modified_at > ?');
        vars.add(Variable.withInt(since));
      }
      if (branchFilterActive) {
        conditions.add('($branchCol = ? OR $branchCol IS NULL)');
        vars.add(Variable.withInt(branchId));
      }
      if (cursorActive) {
        conditions.add('(COALESCE(last_modified_at, 0) > ? OR '
            '(COALESCE(last_modified_at, 0) = ? AND id > ?))');
        vars
          ..add(Variable.withInt(cursorTs))
          ..add(Variable.withInt(cursorTs))
          ..add(Variable.withInt(cursorId));
      }

      final whereClause =
          conditions.isEmpty ? '' : 'WHERE ${conditions.join(' AND ')} ';
      final sql = 'SELECT * FROM $table $whereClause'
          'ORDER BY COALESCE(last_modified_at, 0) ASC, id ASC '
          'LIMIT ${limit + 1}';

      // Fetch limit+1 to detect "there is another page" without a COUNT(*)
      // round-trip, then trim back to the page size.
      final fetched = await _db.customSelect(sql, variables: vars).get();
      final bool hasMore = fetched.length > limit;
      final rows = hasMore ? fetched.sublist(0, limit) : fetched;

      final jsonRows = rows.map((r) {
        final out = <String, dynamic>{};
        for (final entry in r.data.entries) {
          final v = entry.value;
          if (v is DateTime) {
            // Drift-native datetime → epoch seconds (matches client schema).
            out[entry.key] = v.millisecondsSinceEpoch ~/ 1000;
          } else if (v is List<int>) {
            // Skip blob columns; master-data tables don't rely on them for
            // cross-device state and JSON-encoding raw bytes is lossy.
            continue;
          } else {
            out[entry.key] = v;
          }
        }
        return out;
      }).toList();

      // Feature 006 / MM.E hot-fix: journal_entry_lines has no
      // `last_modified_at` column, so it can't ride the generic delta
      // pull. Embed the lines for each pulled entry directly in the
      // response — the client's DeltaPull._upsertRow special-cases this
      // table to extract them. Without this the GL screen on mirror /
      // client showed entry headers with empty debit/credit columns.
      if (table == 'journal_entries' && jsonRows.isNotEmpty) {
        final ids = <int>[];
        for (final r in jsonRows) {
          final id = r['id'];
          if (id is int) ids.add(id);
        }
        if (ids.isNotEmpty) {
          final placeholders = List.filled(ids.length, '?').join(',');
          final lineRows = await _db.customSelect(
            'SELECT * FROM journal_entry_lines WHERE entry_id IN ($placeholders) ORDER BY id ASC',
            variables: ids.map(Variable.withInt).toList(),
          ).get();
          final linesByEntry = <int, List<Map<String, dynamic>>>{};
          for (final l in lineRows) {
            final entryId = l.read<int>('entry_id');
            final lineMap = <String, dynamic>{};
            for (final e in l.data.entries) {
              final v = e.value;
              if (v is DateTime) {
                lineMap[e.key] = v.millisecondsSinceEpoch ~/ 1000;
              } else if (v is! List<int>) {
                lineMap[e.key] = v;
              }
            }
            linesByEntry.putIfAbsent(entryId, () => []).add(lineMap);
          }
          for (final r in jsonRows) {
            final id = r['id'];
            if (id is int) {
              r['lines'] = linesByEntry[id] ?? const [];
            }
          }
        }
      }

      return _json({
        'rows': jsonRows,
        'count': jsonRows.length,
        // `hasMore` drives the client's paging loop. Older clients that don't
        // read it still work: they get one bounded page instead of the whole
        // table, and the next poll picks up from the same watermark.
        'hasMore': hasMore,
        'limit': limit,
        'serverTime': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      });
    } catch (e, st) {
      debugPrint('[API] /api/sync/pull failed: $e\n$st');
      return _error('Failed to fetch delta: $e');
    }
  }

  /// Rows per `/api/sync/pull` page when the caller does not ask for a size.
  /// Sized so a page JSON-encodes in tens of milliseconds on the server's
  /// isolate rather than blocking it for seconds.
  static const int _syncPullDefaultLimit = 500;

  /// Hard ceiling on the `limit` query parameter — a client cannot ask the
  /// server to materialise an unbounded result set again.
  static const int _syncPullMaxLimit = 2000;

  // ═══════════════════════════════════════════════════════════════
  // Helpers
  // ═══════════════════════════════════════════════════════════════

  Response _notFound(Request request) {
    debugPrint('[API] 404 — url: ${request.url}, requestedUri: ${request.requestedUri}');
    return Response.notFound(
      json.encode({
        'error': 'Not found',
        'path': request.requestedUri.path,
        'url': request.url.toString(),
        'method': request.method,
      }),
      headers: {'Content-Type': 'application/json'},
    );
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
      return _error('Failed to fetch product units: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // Document Sequences (GET)
  // ═══════════════════════════════════════════════════════════════

  Future<Response> _getDocumentSequences(Request request) async {
    try {
      final seqs = await _db.select(_db.documentSequences).get();
      final jsonList = seqs
          .map((d) => <String, dynamic>{
                'prefix': d.prefix,
                'nextValue': d.nextValue,
              })
          .toList();

      return _json(
          {'document_sequences': jsonList, 'count': jsonList.length});
    } catch (e) {
      return _error('Failed to fetch document sequences: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // Fiscal Years (GET)
  // ═══════════════════════════════════════════════════════════════

  Future<Response> _getFiscalYears(Request request) async {
    try {
      final years = await _db.select(_db.fiscalYears).get();
      final jsonList = years
          .map((f) => <String, dynamic>{
                'id': f.id,
                'name': f.name,
                'startDate': f.startDate.millisecondsSinceEpoch ~/ 1000,
                'endDate': f.endDate.millisecondsSinceEpoch ~/ 1000,
                'isClosed': f.isClosed,
                'isCurrent': f.isCurrent,
              })
          .toList();

      return _json({'fiscal_years': jsonList, 'count': jsonList.length});
    } catch (e) {
      return _error('Failed to fetch fiscal years: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // Payments
  // ═══════════════════════════════════════════════════════════════

  Future<Response> _getPayments(Request request) async {
    try {
      // Spec 151 residual #1 — scope by safe→branch (payments.safeId is NOT
      // NULL). No identity → sentinel → safeId IN (-1) → zero rows (omission
      // closed); full-access (admin) → no filter → all.
      final branchId =
          await _extractBranchId(request, failClosedOnNoIdentity: true);
      final safeIds =
          branchId != null ? await _resolveBranchSafeIds(branchId) : null;
      final query = _db.select(_db.payments);
      if (safeIds != null && safeIds.isNotEmpty) {
        query.where((p) => p.safeId.isIn(safeIds));
      }
      final rows = await query.get();
      final jsonList = rows.map((p) => <String, dynamic>{
        'id': p.id,
        'paymentNumber': p.paymentNumber,
        'paymentDate': p.paymentDate.toIso8601String(),
        'amount': p.amount,
        'paymentMethod': p.paymentMethod,
        'safeId': p.safeId,
        'partyId': p.partyId,
        'paymentType': p.paymentType,
        'notes': p.notes,
        'userId': p.userId,
        'safeTransactionId': p.safeTransactionId,
        'globalId': p.globalId,
        'idempotencyKey': p.idempotencyKey,
        'isDeleted': p.isDeleted,
        'deletedAt': p.deletedAt?.toIso8601String(),
        'deletedBy': p.deletedBy,
        'updatedAt': p.updatedAt.toIso8601String(),
        'createdAt': p.createdAt.toIso8601String(),
      }).toList();
      return _json({'payments': jsonList, 'count': jsonList.length});
    } catch (e) {
      return _error('Failed to fetch payments: $e');
    }
  }

  Future<Response> _getPaymentAllocations(Request request) async {
    try {
      // Spec 151 residual #1 — allocations have no branch column; scope via
      // parent payment→safe→branch. Resolve the caller's in-scope payment ids,
      // then filter allocations by them. No identity / mis-provisioned →
      // sentinel safe → no scoped payments → sentinel id → zero rows.
      final branchId =
          await _extractBranchId(request, failClosedOnNoIdentity: true);
      List<int>? paymentIds;
      if (branchId != null) {
        final safeIds = await _resolveBranchSafeIds(branchId);
        final scoped = await (_db.select(_db.payments)
              ..where((p) => p.safeId.isIn(safeIds)))
            .get();
        paymentIds = scoped.map((p) => p.id).toList();
        // Empty (branch has no in-scope payments) must fail CLOSED, not drop
        // the filter — `paymentId IN (-1)` matches nothing.
        if (paymentIds.isEmpty) paymentIds = const [_kNoBranchAccess];
      }
      final query = _db.select(_db.paymentAllocations);
      if (paymentIds != null) {
        query.where((a) => a.paymentId.isIn(paymentIds!));
      }
      final rows = await query.get();
      final jsonList = rows.map((a) => <String, dynamic>{
        'id': a.id,
        'paymentId': a.paymentId,
        'invoiceType': a.invoiceType,
        'invoiceId': a.invoiceId,
        'allocatedAmount': a.allocatedAmount,
      }).toList();
      return _json({'payment_allocations': jsonList, 'count': jsonList.length});
    } catch (e) {
      return _error('Failed to fetch payment allocations: $e');
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
      return _error('Failed to fetch product batches: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // Sales Orders
  // ═══════════════════════════════════════════════════════════════

  Future<Response> _getSalesOrders(Request request) async {
    try {
      // Spec 151 residual #1 — scope by warehouse→branch (sales_orders has no
      // branch column). Items are scoped implicitly by only iterating the
      // in-scope orders. No identity → sentinel → warehouseId IN (-1) → zero.
      final branchId =
          await _extractBranchId(request, failClosedOnNoIdentity: true);
      final warehouseIds =
          branchId != null ? await _resolveBranchWarehouseIds(branchId) : null;
      final ordersQuery = _db.select(_db.salesOrders);
      if (warehouseIds != null && warehouseIds.isNotEmpty) {
        ordersQuery.where((o) => o.warehouseId.isIn(warehouseIds));
      }
      final orders = await ordersQuery.get();
      final jsonList = <Map<String, dynamic>>[];
      for (final o in orders) {
        final items = await (_db.select(_db.salesOrderItems)
          ..where((i) => i.orderId.equals(o.id))).get();
        final itemsJson = items.map((i) => <String, dynamic>{
          'id': i.id,
          'orderId': i.orderId,
          'productId': i.productId,
          'quantity': i.quantity,
          'unitPrice': i.unitPrice,
          'discount': i.discount,
          'total': i.total,
          'deliveredQuantity': i.deliveredQuantity,
          'taxRate': i.taxRate,
          'taxAmount': i.taxAmount,
          'notes': i.notes,
        }).toList();
        jsonList.add({
          'id': o.id,
          'orderNumber': o.orderNumber,
          'customerId': o.customerId,
          'warehouseId': o.warehouseId,
          'orderDate': o.orderDate.toIso8601String(),
          'expectedDate': o.expectedDate?.toIso8601String(),
          'subtotal': o.subtotal,
          'discount': o.discount,
          'tax': o.tax,
          'total': o.total,
          'status': o.status,
          'notes': o.notes,
          'costCenterId': o.costCenterId,
          'convertedToInvoiceId': o.convertedToInvoiceId,
          'createdAt': o.createdAt.toIso8601String(),
          'items': itemsJson,
        });
      }
      return _json({'sales_orders': jsonList, 'count': jsonList.length});
    } catch (e) {
      return _error('Failed to fetch sales orders: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // Purchase Orders
  // ═══════════════════════════════════════════════════════════════

  Future<Response> _getPurchaseOrders(Request request) async {
    try {
      // Spec 151 residual #1 — scope by warehouse→branch (purchase_orders has
      // no branch column). Items scoped implicitly by iterating in-scope orders.
      final branchId =
          await _extractBranchId(request, failClosedOnNoIdentity: true);
      final warehouseIds =
          branchId != null ? await _resolveBranchWarehouseIds(branchId) : null;
      final ordersQuery = _db.select(_db.purchaseOrders);
      if (warehouseIds != null && warehouseIds.isNotEmpty) {
        ordersQuery.where((o) => o.warehouseId.isIn(warehouseIds));
      }
      final orders = await ordersQuery.get();
      final jsonList = <Map<String, dynamic>>[];
      for (final o in orders) {
        final items = await (_db.select(_db.purchaseOrderItems)
          ..where((i) => i.orderId.equals(o.id))).get();
        final itemsJson = items.map((i) => <String, dynamic>{
          'id': i.id,
          'orderId': i.orderId,
          'productId': i.productId,
          'quantity': i.quantity,
          'unitCost': i.unitCost,
          'discount': i.discount,
          'total': i.total,
          'receivedQuantity': i.receivedQuantity,
          'taxRate': i.taxRate,
          'taxAmount': i.taxAmount,
          'notes': i.notes,
        }).toList();
        jsonList.add({
          'id': o.id,
          'orderNumber': o.orderNumber,
          'supplierId': o.supplierId,
          'warehouseId': o.warehouseId,
          'orderDate': o.orderDate.toIso8601String(),
          'expectedDate': o.expectedDate?.toIso8601String(),
          'subtotal': o.subtotal,
          'discount': o.discount,
          'tax': o.tax,
          'total': o.total,
          'status': o.status,
          'notes': o.notes,
          'costCenterId': o.costCenterId,
          'convertedToInvoiceId': o.convertedToInvoiceId,
          'createdAt': o.createdAt.toIso8601String(),
          'items': itemsJson,
        });
      }
      return _json({'purchase_orders': jsonList, 'count': jsonList.length});
    } catch (e) {
      return _error('Failed to fetch purchase orders: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // Accounting Periods
  // ═══════════════════════════════════════════════════════════════

  Future<Response> _getAccountingPeriods(Request request) async {
    try {
      final rows = await _db.select(_db.accountingPeriods).get();
      final jsonList = rows.map((p) => <String, dynamic>{
        'id': p.id,
        'fiscalYearId': p.fiscalYearId,
        'name': p.name,
        'month': p.month,
        'year': p.year,
        'startDate': p.startDate.toIso8601String(),
        'endDate': p.endDate.toIso8601String(),
        'isClosed': p.isClosed,
        'closedAt': p.closedAt?.toIso8601String(),
        'closedBy': p.closedBy,
        'notes': p.notes,
        'createdAt': p.createdAt.toIso8601String(),
        'globalId': p.globalId,
      }).toList();
      return _json({'accounting_periods': jsonList, 'count': jsonList.length});
    } catch (e) {
      return _error('Failed to fetch accounting periods: $e');
    }
  }

  Response _json(Map<String, dynamic> data, {int statusCode = 200}) {
    return Response(
      statusCode,
      body: json.encode(data),
      headers: {'Content-Type': 'application/json'},
    );
  }

  Response _error(String message, {int statusCode = 500}) {
    return Response(
      statusCode,
      body: json.encode({'error': message}),
      headers: {'Content-Type': 'application/json'},
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // HTML Templates (extracted to api_html_templates.dart)
  // ═══════════════════════════════════════════════════════════════

  String _buildMenuHtml() => menuHtmlTemplate;
  String _buildCfdHtml() => cfdHtmlTemplate;

  /// Public: Broadcast a data_changed event to connected WebSocket clients.
  /// Call this from server-side screens when entities are modified directly
  /// (e.g. branches, cost centers, accounts created via the server UI).
  ///
  /// Delegates to [ApiHandlerBase.broadcast] instead of re-implementing the
  /// fan-out. The duplicate loop this replaces had two defects: it never
  /// pushed to `_localChangeController`, so the SERVER's own open screens did
  /// not refresh after an admin edit (only remote clients did); and it ignored
  /// `WsSubscriberInfo.branchId` entirely, so it could not scope a broadcast
  /// even when the caller knew the branch. Every current caller passes global
  /// master data (accounts, branches, cost centers, role_permissions), which
  /// correctly reaches everyone with [branchId] left null.
  void broadcastChange(String table, {int? branchId}) {
    _data.broadcast(table, branchId: branchId);
  }

  // ═══════════════════════════════════════════════════════════════
  // Offers (GET) — serves all offers + items for client sync
  // ═══════════════════════════════════════════════════════════════

  Future<Response> _getOffers(Request request) async {
    try {
      final offers = await _db.select(_db.offers).get();
      final items = await _db.select(_db.offerItems).get();

      final offersJson = offers.map((o) => <String, dynamic>{
        'id': o.id,
        'name': o.name,
        'barcode': o.barcode,
        'offerPrice': o.offerPrice,
        'startDate': o.startDate != null
            ? o.startDate!.millisecondsSinceEpoch ~/ 1000
            : null,
        'endDate': o.endDate != null
            ? o.endDate!.millisecondsSinceEpoch ~/ 1000
            : null,
        'isActive': o.isActive,
        'offerType': o.offerType,
        'discountValue': o.discountValue,
        'buyQuantity': o.buyQuantity,
        'getQuantity': o.getQuantity,
        'minQuantity': o.minQuantity,
        'maxUses': o.maxUses,
        'currentUses': o.currentUses,
        'timeStart': o.timeStart,
        'timeEnd': o.timeEnd,
        'categoryId': o.categoryId,
      }).toList();

      final itemsJson = items.map((i) => <String, dynamic>{
        'id': i.id,
        'offerId': i.offerId,
        'productId': i.productId,
        'quantity': i.quantity,
      }).toList();

      return _json({
        'offers': offersJson,
        'offerItems': itemsJson,
        'count': offersJson.length,
      });
    } catch (e) {
      return _error('Failed to fetch offers: $e');
    }
  }
}
