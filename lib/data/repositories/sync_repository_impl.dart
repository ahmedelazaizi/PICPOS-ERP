import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import '../../domain/repositories/sync_repository.dart';
import '../../data/database/database.dart' as db;
import '../../services/network_service.dart';
import '../../services/server_proxy.dart';
import '../../services/sync_service.dart';

class SyncRepositoryImpl implements ISyncRepository {
  final db.AppDatabase _db;
  final NetworkService _ns = NetworkService.instance;

  SyncRepositoryImpl(this._db);

  @override
  NetworkMode get mode => _ns.mode;

  @override
  bool get isServerRunning => _ns.isServerRunning;

  @override
  String? get serverAddress => _ns.serverAddress;

  @override
  int get serverPort => _ns.serverPort;

  @override
  int get connectedClientCount => _ns.connectedClientCount;

  @override
  String buildServerUrl({String? address, int? port}) =>
      _ns.buildServerUrl(address: address, port: port);

  @override
  Future<void> loadSettings() async {
    await _ns.loadSettings();
  }

  @override
  Future<void> saveSettings() async {
    await _ns.saveSettings();
  }

  @override
  Future<void> setMode(NetworkMode mode) async {
    await _ns.setMode(mode, db: _db);
  }

  @override
  Future<bool> startServer({int? port}) async {
    return _ns.startServer(_db, port: port);
  }

  @override
  Future<void> stopServer() async {
    await _ns.stopServer();
  }

  @override
  void openDevicePairingWindow() => _ns.openDevicePairingWindow();

  @override
  Future<Map<String, dynamic>> testConnection(String address, int port) async {
    return _ns.testServerConnection(address, port);
  }

  @override
  Future<SyncResult> performFullSync(String serverUrl) async {
    final syncService = SyncService(serverUrl: serverUrl, localDb: _db);
    await syncService.initialize();
    return syncService.fullSync();
  }

  @override
  Future<SyncResult> performTableSync(String serverUrl, String tableName) async {
    final syncService = SyncService(serverUrl: serverUrl, localDb: _db);
    await syncService.initialize();
    try {
      await syncService.syncTable(tableName);
      return SyncResult(
        success: true,
        message: 'تمت مزامنة $tableName',
        itemsSynced: 1,
      );
    } catch (e) {
      return SyncResult(
        success: false,
        message: 'فشلت مزامنة $tableName: $e',
      );
    }
  }

  @override
  Future<SyncResult> pushLocalSalesToServer() async {
    // Spec 097 (R9 broadened gate): mirror mode also has local-only
    // invoices when a mode-drift happens (e.g. Spec 089 reconcile flips
    // a mirror device to server briefly, sales saved as server, then
    // user flips back to mirror — those invoices need to backfill to HQ).
    // Strict-client check would reject mirror and strand the rows.
    if (_ns.mode != NetworkMode.client && _ns.mode != NetworkMode.mirror) {
      return SyncResult(
        success: false,
        message: 'هذه العملية متاحة فى وضعَى العميل والمرآة فقط',
      );
    }
    // Collect all local sales that aren't returns.
    //
    // Spec 136 — duplication incident (2026-06-03): this recovery tool used to
    // omit `globalId` and `branchId` from the payload and rely on the server's
    // invoice_number duplicate check. That check FAILS here because the local
    // invoice number (e.g. `AQ-SINV-1`) is NOT the server's stored number
    // (`AQ-POS-1`) — the server re-prefixes the local number and never matches
    // the existing row, so every re-push INSERTED a fresh duplicate (and with
    // branchId missing the server fell back to the `CLTCL-` prefix). Clicking
    // the button on a mirror (which holds the whole company's pulled sales)
    // duplicated the entire ledger.
    //
    // Fix (R9): thread the stable `globalId` + `branchId` + `idempotencyKey`
    // end-to-end. The server then dedups on `journal_entries`/invoice globalId,
    // so re-pushing an already-synced row — whether locally-created or pulled —
    // is a true no-op, and a genuine new insert gets the correct branch prefix.
    final invoices = await (_db.select(_db.salesInvoices)
          ..where((i) =>
              i.isDeleted.equals(false) &
              (i.saleType.equals('return').not() | i.saleType.isNull())))
        .get();
    debugPrint('[PushSales] Found ${invoices.length} local invoices to push');

    int pushed = 0;
    int duplicates = 0;
    int failed = 0;
    final errors = <String>[];
    for (final inv in invoices) {
      try {
        // Load this invoice's items from sales_invoice_items
        final items = await (_db.select(_db.salesInvoiceItems)
              ..where((ii) => ii.invoiceId.equals(inv.id)))
            .get();
        // C2 (v183) — raw column, invisible to the Drift row above.
        final revenueAccountId =
            await _db.getSalesInvoiceRevenueAccountId(inv.id);

        final payload = <String, dynamic>{
          'invoiceNumber': inv.invoiceNumber,
          // R9 (Spec 136): stable identity so the server dedups instead of
          // inserting a CLTCL- duplicate; branchId for correct attribution/prefix.
          'globalId': inv.globalId,
          'branchId': inv.branchId,
          'clientIpSuffix': 'CL',
          'customerId': inv.customerId,
          'warehouseId': inv.warehouseId,
          'userId': inv.userId,
          'costCenterId': inv.costCenterId,
          'subtotal': inv.subtotal,
          'discount': inv.discount,
          'tax': inv.tax,
          'total': inv.total,
          'paid': inv.paid,
          // ⚠️ **بدونه يرحّل الخادمُ قيداً مخالفاً لقيد العميل.** هذا مسارٌ
          // حيٌّ يُطلَق من زرِّ «دفع المبيعات للسيرفر»، والخادمُ يعيد بناءَ
          // القيد من الحمولة: غيابُ الفرق يجعله يرى `total > paid` فيفتح
          // ذمّةً مدينةً على حساب المراقبة، ولا يُصدر سطرَ ٤٣١٩، وتبقى
          // الفاتورةُ `pending` على الخادم و`completed` على الجهاز.
          'roundingAdjustment': inv.roundingAdjustment,
          'paymentMethod': inv.paymentMethod,
          'deliveryFee': inv.deliveryFee,
          'notes': inv.notes,
          'saleType': inv.saleType,
          'invoiceDate': inv.invoiceDate.toIso8601String(),
          'revenueAccountId': ?revenueAccountId,
          'items': items.map((i) => <String, dynamic>{
            'productId': i.productId,
            'quantity': i.quantity,
            'unitPrice': i.unitPrice,
            'discount': i.discount,
            'total': i.total,
            'costPrice': i.costPrice,
            'taxRate': i.taxRate,
            'taxAmount': i.taxAmount,
            'note': i.note,
          }).toList(),
        };

        final response = await ServerProxy.instance
            .submitSale(payload,
                idempotencyKey: inv.idempotencyKey ?? inv.globalId)
            .timeout(const Duration(seconds: 10));
        if (response != null) {
          pushed++;
        } else {
          duplicates++;
        }
      } catch (e) {
        failed++;
        errors.add('فاتورة ${inv.invoiceNumber}: $e');
        debugPrint('[PushSales] Failed to push ${inv.invoiceNumber}: $e');
      }
    }

    final message = 'تم دفع $pushed فاتورة جديدة، '
        '$duplicates موجودة مسبقاً، $failed فشلت';
    debugPrint('[PushSales] $message');
    return SyncResult(
      success: failed == 0,
      message: message,
      itemsSynced: pushed,
    );
  }

  @override
  void setServerAddress(String address, {int? port}) {
    _ns.setServerAddress(address, port: port);
  }

  @override
  bool get tlsEnabled => _ns.tlsEnabled;

  @override
  String? get tlsCertPath => _ns.tlsCertPath;

  @override
  String? get tlsKeyPath => _ns.tlsKeyPath;

  @override
  bool get isServerUsingTls => _ns.isServerUsingTls;

  @override
  Future<void> configureTls({
    required bool enabled,
    String? certPath,
    String? keyPath,
    String? keyPassword,
  }) async {
    await _ns.configureTls(
      enabled: enabled,
      certPath: certPath,
      keyPath: keyPath,
      keyPassword: keyPassword,
    );
  }

  @override
  String? validateTlsConfig() => _ns.validateTlsConfig();

  @override
  Stream<List<db.SyncOutboxItem>> watchPendingItems() {
    return (_db.select(_db.syncOutbox)
          ..where((t) => t.status.equals('synced').not())
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
          ..limit(50))
        .watch();
  }

  @override
  Future<void> retryItem(int id) async {
    await (_db.update(_db.syncOutbox)..where((t) => t.id.equals(id))).write(
      const db.SyncOutboxCompanion(
        status: Value('pending'),
        attempts: Value(0),
      ),
    );
  }

  @override
  Future<void> deleteItem(int id) async {
    await (_db.delete(_db.syncOutbox)..where((t) => t.id.equals(id))).go();
  }

  @override
  Future<int> retryAllDeadLetterItems() async {
    return _db.retryAllDeadLetterItems();
  }
}
