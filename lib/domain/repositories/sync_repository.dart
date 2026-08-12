import '../../data/database/database.dart' as db;
import '../../services/network_service.dart';
import '../../services/sync_service.dart';

abstract class ISyncRepository {
  NetworkMode get mode;
  bool get isServerRunning;
  String? get serverAddress;
  int get serverPort;
  int get connectedClientCount;

  /// رابط السيرفر جاهزاً للعرض. `serverAddress` وحدَه لا يصلح للّصق في نصّ —
  /// نوعُه `String?` ويبقى null في الوضع المستقلّ، فيُطبع "null" في الرابط.
  /// يحتاطُ بـ`localhost` ويمرّر روابطَ الأنفاق كما هي.
  String buildServerUrl({String? address, int? port});
  
  Future<void> loadSettings();
  Future<void> saveSettings();
  Future<void> setMode(NetworkMode mode);
  Future<bool> startServer({int? port});
  Future<void> stopServer();

  /// A-SEC-1: open a short window during which the server exposes the API
  /// token via `/api/health` so a new client/mirror can pair. Server mode only.
  void openDevicePairingWindow();
  Future<Map<String, dynamic>> testConnection(String address, int port);
  Future<SyncResult> performFullSync(String serverUrl);

  /// Sync a single table from the server — fast variant for targeted refreshes
  /// like post-login user data pull (avoids ~10s of unrelated table syncs).
  Future<SyncResult> performTableSync(String serverUrl, String tableName);

  /// Recovery tool: push every local sales invoice to the server's
  /// `/api/sales` endpoint. The server's duplicate-check (by invoice_number)
  /// makes this idempotent — already-synced invoices return a "duplicate"
  /// acknowledgement and are not re-inserted.
  ///
  /// Used when invoices are stuck locally because the initial fire-and-forget
  /// POST failed (e.g. due to user-mapping errors that were later fixed on
  /// the server). Client-only — on standalone/server mode this is a no-op.
  Future<SyncResult> pushLocalSalesToServer();
  void setServerAddress(String address, {int? port});

  // TLS configuration
  bool get tlsEnabled;
  String? get tlsCertPath;
  String? get tlsKeyPath;
  bool get isServerUsingTls;
  Future<void> configureTls({
    required bool enabled,
    String? certPath,
    String? keyPath,
    String? keyPassword,
  });
  String? validateTlsConfig();

  // Outbox management
  Stream<List<db.SyncOutboxItem>> watchPendingItems();
  Future<void> retryItem(int id);
  Future<void> deleteItem(int id);

  /// L4 (2026-04-28): Bulk-retry every dead-lettered item — used after admin
  /// fixes the underlying root cause (e.g. corrected branch-warehouse mapping
  /// or re-paired a misconfigured device). Returns the count of items reset.
  Future<int> retryAllDeadLetterItems();
}
