// ApiHandler - warehouse mobile app routes (/api/m1/*). See m1_wh/wh_read_handlers.dart.
part of '../api_handler.dart';

/// Routes of the PicPos Warehouse phone app (plan 2026-10-23). Registered
/// before the public/catch-all block; every /api/m1/wh/* handler re-checks the
/// device kind, the user and the permission itself.
extension ApiHandlerWarehouseRoutes on ApiHandler {
  void _registerWarehouseRoutes(Router router) {
    final wh = WhApi(_db);
    router.get('/api/m1/info', wh.info);
    router.get('/api/m1/wh/session', wh.session);
    router.get('/api/m1/wh/items', wh.items);
    final rc = WhReceiptApi(_db);
    router.get('/api/m1/wh/po', rc.listPo);
    router.get('/api/m1/wh/po/<ref>', rc.getPo);
    router.post('/api/m1/wh/po/<ref>/receipts', rc.createOrAppend);
    router.get('/api/m1/wh/receipts', rc.listReceipts);
    router.post('/api/m1/wh/receipts/<gid>/submit', rc.submit);
    router.post('/api/m1/wh/receipts/<gid>/convert', rc.convert);
    router.get('/api/m1/wh/locations/by-barcode/<code>', rc.locationLookup);
    // WH-002: the accountant's inbox for DESKTOP sessions (never a phone).
    router.get('/api/m1/wh/desk/receipts', rc.deskList);
    router.post('/api/m1/wh/desk/receipts/<gid>/convert', rc.deskConvert);
    final ap = WhApprovalApi(_db);
    router.get('/api/m1/wh/approvals', ap.inbox);
    router.get('/api/m1/wh/labels', ap.label);
    final cn = WhCountApi(_db);
    router.get('/api/m1/wh/counts/tasks', cn.tasks);
    router.post('/api/m1/wh/counts/<ref>/entries', cn.entries);
    router.post('/api/m1/wh/counts/<ref>/submit', cn.submit);
    router.get('/api/m1/wh/counts/<ref>/review', cn.review);
    router.post('/api/m1/wh/counts/<ref>/approve', cn.approve);
    final sd = WhStockDocApi(_db);
    router.post('/api/m1/wh/transfers', sd.transferCreate);
    router.get('/api/m1/wh/transfers', sd.transferList);
    router.post('/api/m1/wh/transfers/<gid>/approve', sd.transferApprove);
    router.post('/api/m1/wh/transfers/<gid>/reject', sd.transferReject);
    router.post('/api/m1/wh/transfers/<gid>/dispatch', sd.transferDispatch);
    router.post('/api/m1/wh/transfers/<gid>/receive', sd.transferReceive);
    router.post('/api/m1/wh/transfers/<gid>/resolve', sd.transferResolve);
    router.post('/api/m1/wh/vouchers', sd.voucherCreate);
    router.get('/api/m1/wh/vouchers', sd.voucherList);
    router.post('/api/m1/wh/vouchers/<gid>/approve', sd.voucherApprove);
    router.post('/api/m1/wh/vouchers/<gid>/reject', sd.voucherReject);
  }
}