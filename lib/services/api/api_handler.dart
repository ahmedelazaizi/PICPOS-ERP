// Main API router and GET endpoints.

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
import 'package:shelf/shelf.dart';
import 'api_errors.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:drift/drift.dart';
import '../../data/database/database.dart';
import '../network_service.dart';
import '../sync/strategies/setting_sync_strategy.dart'
    show isServerSecretSettingKey;
import 'api_auth_middleware.dart';
import 'api_user_context.dart';
import 'client_schema_gate.dart';
import 'party_visibility.dart';
import 'api_handler_base.dart' show WsSubscriberInfo, ApiHandlerBase;
import 'api_sales_handler.dart';
import 'api_data_handler.dart';
import 'api_party_handler.dart';
import 'api_product_handler.dart';
import 'api_purchase_handler.dart';
import 'api_auth_handler.dart';
import 'api_web_session_handler.dart';
import 'm1_wh/wh_read_handlers.dart';
import 'web_static_handler.dart';
import 'web_session_guard.dart';
import '../web_read/web_read_channel_host.dart';
import 'api_terminals_handler.dart';
import 'api_voucher_handler.dart';
import 'api_display_handler.dart';
import 'table_bill_html.dart';
import 'table_bill_token.dart';
import '../guest_order_requests.dart';
import '../guest_order_approval.dart';
import '../../core/permissions/permission_codes.dart';
import '../table_session_service.dart';
import '../../core/config/app_config.dart';
import '../manufacturing_sync_tables.dart';

// Route registration and GET handlers live in routes/ (parts of this library,
// so the private `_` members stay shared). See each file header.
part 'routes/api_routes_read.dart';
part 'routes/api_routes_write.dart';
part 'routes/api_routes_auth_public.dart';
part 'routes/api_routes_m1_wh.dart';
part 'routes/api_get_catalog.dart';
part 'routes/api_get_system.dart';
part 'routes/api_get_treasury.dart';
part 'routes/api_get_documents.dart';
part 'routes/api_get_directory.dart';
part 'routes/api_get_users.dart';
part 'routes/api_table_guest_routes.dart';
part 'routes/api_branch_scope.dart';
part 'routes/api_sync_pull_tables.dart';
part 'routes/api_get_sync_pull.dart';
part 'routes/api_helpers.dart';

/// REST API handler for embedded server.
/// Exposes read-only endpoints for products, categories, units,
/// and delegates write endpoints to domain handlers.
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
  // الويب: لا يرث ApiHandlerBase (كي لا يُسجَّل _registeredInstance).
  late final ApiWebSessionHandler _webSession;
  late final WebReadChannelHost _webRead;
  late final ApiTerminalsHandler _terminals;
  late final ApiVoucherHandler _vouchers;
  late final ApiDisplayHandler _display;

  /// م3-9: مجلد بناء الويب لتقديمه من نفس الأصل (null = لا تقديم).
  final String? _webStaticDir;

  ApiHandler(this._db, {String? webStaticDir}) : _webStaticDir = webStaticDir {
    _sales = ApiSalesHandler(_db, _wsClients);
    _data = ApiDataHandler(_db, _wsClients);
    _parties = ApiPartyHandler(_db, _wsClients);
    _products = ApiProductHandler(_db, _wsClients);
    _purchases = ApiPurchaseHandler(_db, _wsClients);
    _auth = ApiAuthHandler(_db, _wsClients);
    _webSession = ApiWebSessionHandler(_db);
    WebSessionGuard.configure(_db);
    _webRead = WebReadChannelHost(_db);
    _terminals = ApiTerminalsHandler(_db, _wsClients);
    _vouchers = ApiVoucherHandler(_db, _wsClients);
    _display = ApiDisplayHandler(_db);
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

  /// عدد صفوف `IS NULL` في آخر سحب محصور — منفذ قياس للاختبار.
  /// `debugPrint` وحده لا يكفي: يُخنق تحت الحمل، فـ«صفر سطر في السجل»
  /// ليس دليلاً بلا هذا العدّاد.
  @visibleForTesting
  static int debugLastNullBranchRowCount = 0;

  /// يُفرِّغ خانق السجلّ. الخريطة ساكنة فتعيش عبر اختبارات العملية الواحدة،
  /// فبدون هذا يقرأ اختبارُ «أول قياس» أثرَ اختبار سابق.
  @visibleForTesting
  static void debugResetNullBranchLogThrottle() =>
      _lastLoggedNullBranchRows.clear();

  /// Spec 151 P1-8b — exposed so a guard test can assert this stays IDENTICAL
  /// to `DeltaPullService.branchScopedPullTables`. If the two drift apart, one
  /// side silently reopens either the tokenless transactional leak (server
  /// serves a table the client thinks is denied) or the watermark poison
  /// (client seeds a watermark the server denies).
  @visibleForTesting
  static Set<String> get transactionalPullTablesForTest =>
      ApiHandlerSyncPullTables._transactionalPullTables;

  /// Build the shelf Router with all API endpoints.
  /// Registration order matters (first match wins; catch-all is last).
  Router buildRouter() {
    final router = Router();

    _registerReadRoutes(router);
    _registerWriteRoutes(router);
    _registerAdminWriteRoutes(router);
    _registerAuthSyncRoutes(router);
    _registerWarehouseRoutes(router);
    _registerPublicRoutes(router);

    return router;
  }

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
}
