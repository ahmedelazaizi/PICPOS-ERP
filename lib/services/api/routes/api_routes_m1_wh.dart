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
  }
}