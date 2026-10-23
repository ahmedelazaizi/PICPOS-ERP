// ApiHandler - write (POST/PUT/DELETE) route registration.
part of '../api_handler.dart';

/// write (POST/PUT/DELETE) route registration (see [ApiHandler.buildRouter]).
/// Registration order inside and across these methods is security-relevant.
extension ApiHandlerWriteRoutes on ApiHandler {
  void _registerWriteRoutes(Router router) {
    // ── Write endpoints — delegated to sub-handlers ──
    // POS terminals (Feature 009 / T020) — must come before any catch-all
    router.post('/api/pos-terminals/register', _terminals.register);
    // Sales
    router.post('/api/sales', _sales.postSale);
    router.post('/api/sales/return', _sales.postSalesReturn);
    // الاستبدال — حمولةٌ واحدةٌ تُفكَّك إلى مستندَين في معاملةٍ واحدة، فلا
    // نافذةَ يصل فيها المردودُ ويسقط بديلُه.
    router.post('/api/sales/exchange', _sales.postSalesExchange);
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
    // E-fix ١ — سندا القبض والصرف من جهاز العميل (تحويلٌ/مستفيدٌ/دفتر).
    router.post('/api/vouchers/receipt', _vouchers.postReceiptVoucher);
    router.post('/api/vouchers/payment', _vouchers.postPaymentVoucher);
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
    // v166 / المرحلة ٢ — تطبيقُ ورقة تحميلٍ واردةٍ من عميل.
    router.post('/api/landed-costs/apply', _data.postLandedCostApply);
    // v174 / قسمُ ٧ — مخطَّطُ القاعة يصل **مستنداً واحداً**.
    router.post('/api/floor-plan', _data.postFloorPlan);
    router.post('/api/table-reservations', _data.postTableReservation);
    // v176 / §٨ — المرفقات: رفعٌ وحذفٌ وجلبٌ كسولٌ للبايتات.
    router.post('/api/attachments', _data.postAttachment);
    router.post('/api/attachments/delete', _data.postAttachmentDelete);
    router.get('/api/attachments/<globalId>', _data.getAttachmentBytes);
    // v166 / المرحلة ٢ — اقتناءُ أصلٍ وترحيلُ إهلاكٍ واردان من عميل.
    router.post('/api/fixed-assets', _data.postFixedAsset);
    router.post('/api/op-expenses', _data.postOperationalExpense);
    router.post('/api/manufacturing/action', _data.postManufacturingAction);
    // v167 / المرحلة ٣ — خصمُ عربونِ حجزٍ واردٌ من عميل.
    router.post('/api/bookings/apply-deposit', _data.postBookingApplyDeposit);
    router.post('/api/fixed-assets/depreciation/run',
        _data.postAssetDepreciationRun);
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
  }

  void _registerAdminWriteRoutes(Router router) {
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
  }
}
