// ApiHandler - GET route registration (health, ws, read endpoints).
part of '../api_handler.dart';

/// GET route registration (health, ws, read endpoints) (see [ApiHandler.buildRouter]).
/// Registration order inside and across these methods is security-relevant.
extension ApiHandlerReadRoutes on ApiHandler {
  void _registerReadRoutes(Router router) {
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
    router.get('/api/offers', _display.getOffers);
    router.get('/api/product-units', _getProductUnits);
    router.get('/api/document-sequences', _getDocumentSequences);
    router.get('/api/fiscal-years', _getFiscalYears);
    router.get('/api/payments', _getPayments);
    router.get('/api/payment-allocations', _getPaymentAllocations);
    router.get('/api/product-batches', _getProductBatches);
    router.get('/api/sales-orders', _getSalesOrders);
    router.get('/api/purchase-orders', _getPurchaseOrders);
    // v165 — سجلّا تواصلٍ يتبعان `parties`، وسياستُهما سياستُه بالضبط:
    // العميلُ يُرسل `branch_id` والمعالجُ لا يقرؤه بعد، ولا فشلَ مقفولاً على
    // غياب الجلسة (انظر `_getParties`).
    router.get('/api/party-follow-ups', _getPartyFollowUps);
    router.get('/api/supplier-claims', _getSupplierClaims);
    router.get('/api/accounting-periods', _getAccountingPeriods);
    // FLEET-1 / FLEET-3 — the sync engine pulls both; they had no read route.
    router.get('/api/pos-terminals', _getPosTerminals);
    router.get('/api/sale-bom-consumptions', _getSaleBomConsumptions);
  }
}
