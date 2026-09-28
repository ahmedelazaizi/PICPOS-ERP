import 'dart:async';
import 'dart:io' show SocketException;
import 'package:http/http.dart' as http show ClientException;
import 'package:uuid/uuid.dart';
import 'package:flutter/foundation.dart';
import 'package:drift/drift.dart' show Value;
import 'server_proxy.dart';
import 'delta_pull_service.dart';
import 'offline_sync_worker.dart';
import 'write_router.dart';
import '../core/logging/diagnostic_logger.dart';
import '../data/database/database.dart';
import '../data/database/sync_interceptor.dart';
import '../domain/models/exchange_sync_payload.dart';
import '../domain/models/import_purchase_plan.dart';

/// Intercepts write operations in client mode and routes them through
/// ServerProxy to the server's API.
///
/// **Offline-First**: If the server is unreachable the operation is queued
/// in [SyncOutbox] and replayed by [OfflineSyncWorker] when connectivity
/// is restored. The implementation is split into focused domain parts below;
/// this entrypoint keeps the public import path unchanged.
part 'interceptor/cwi_core_support.dart';
part 'interceptor/cwi_core.dart';
part 'interceptor/cwi_commerce.dart';
part 'interceptor/cwi_catalog.dart';
part 'interceptor/cwi_catalog_products.dart';
part 'interceptor/cwi_catalog_operations.dart';
part 'interceptor/cwi_trading.dart';
part 'interceptor/cwi_trading_sales.dart';
part 'interceptor/cwi_trading_inventory.dart';
part 'interceptor/cwi_trading_papers.dart';
part 'interceptor/cwi_trading_purchases.dart';
part 'interceptor/cwi_sync.dart';
part 'interceptor/cwi_sync_foundation.dart';
part 'interceptor/cwi_sync_catalog.dart';
part 'interceptor/cwi_sync_orders.dart';
part 'interceptor/cwi_admin.dart';
