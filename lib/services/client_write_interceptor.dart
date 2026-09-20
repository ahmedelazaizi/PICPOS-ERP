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

part 'interceptor/cwi_commerce.dart';
part 'interceptor/cwi_catalog.dart';
part 'interceptor/cwi_trading.dart';
part 'interceptor/cwi_sync.dart';
part 'interceptor/cwi_admin.dart';

/// Intercepts write operations in client mode and routes them through
/// ServerProxy to the server's API.
///
/// **Offline-First**: If the server is unreachable the operation is queued
/// in [SyncOutbox] and replayed by [OfflineSyncWorker] when connectivity
/// is restored.
///
/// **Week-11 note**: The method bodies live in four focused part files under
/// `lib/services/interceptor/`.  This file contains only the shared
/// infrastructure (`_tryOrQueue`, globalId helpers) and thin delegation stubs
/// so all 41+ existing call-sites remain unchanged.
class ClientWriteInterceptor implements SyncInterceptor {
  ClientWriteInterceptor._();

  static void setup() => SyncInterceptor.instance = ClientWriteInterceptor._();

  /// Returns true whenever writes are routed through this interceptor
  /// (HTTP first, optional outbox second) instead of going to the local
  /// DB. That covers both:
  ///
  ///   • `NetworkMode.client` — the cashier's device, which has its own
  ///     local cache + outbox for offline resilience.
  ///   • `NetworkMode.mirror` — the admin's remote laptop, which uses
  ///     the same HTTP path but has no outbox; failures throw
  ///     [MirrorOfflineException] (handled inside `_tryOrQueue`).
  ///
  /// The legacy name (`isClientModeImpl`) is preserved because 60+ files
  /// already check `SyncInterceptor.isClientMode` to decide "should I
  /// intercept this write?" — broadening the predicate is the
  /// least-disruptive way to support mirror mode without a 60-file
  /// rename. Read it as "intercepted mode" going forward.
  @override
  bool get isClientModeImpl =>
      ServerProxy.isClientMode || WriteRouter.isMirrorActive;

  /// Spec 088 USR-2 — mirror-only predicate. `isClientModeImpl` is true
  /// for both client AND mirror (the broadened R9 gate that 60+ files
  /// depend on); `isMirrorModeImpl` narrows it back to mirror-only for
  /// the few sites that need to distinguish the two.
  @override
  bool get isMirrorModeImpl => WriteRouter.isMirrorActive;

  static final _proxy = ServerProxy.instance;

  /// Local database — set once by [initialize] before any writes.
  static AppDatabase? _db;
  static void initialize(AppDatabase db) => _db = db;

  // ═══════════════════════════════════════════════════════════════
  // Generic offline-safe wrappers (used by every part-file module)
  // ═══════════════════════════════════════════════════════════════

  /// Look up the username for a userId in the local DB, and inject
  /// `createdByUsername` into [payload] if it's missing.  This ensures every
  /// client→server write carries a stable string identifier so the server can
  /// resolve the user by username when the auto-increment IDs diverge (e.g.
  /// a user was created locally before the first full sync).
  static Future<void> _enrichPayloadWithUsername(Map<String, dynamic> payload) async {
    if (_db == null) return;
    if (payload.containsKey('createdByUsername') || payload.containsKey('userName')) return;
    final raw = payload['userId'] ?? payload['changedBy'];
    final uid = raw is int ? raw : (raw is num ? raw.toInt() : int.tryParse('${raw ?? ''}'));
    if (uid == null || uid == 0) return;
    try {
      final user = await (_db!.select(_db!.users)
            ..where((u) => u.id.equals(uid))
            ..limit(1))
          .getSingleOrNull();
      if (user != null) payload['createdByUsername'] = user.username;
    } catch (_) {}
  }

  /// True for exceptions that mean "we never got an answer from HQ"
  /// (offline / unreachable / timeout). Anything else is a server-side
  /// rejection (HTTP 4xx/5xx, JSON parse failure, …) and the operator
  /// needs to see the real reason, not a generic "connection lost".
  static bool _isNetworkException(Object e) =>
      e is SocketException ||
      e is TimeoutException ||
      e is http.ClientException;

  /// Execute [serverCall] and, on failure, queue the operation locally.
  /// Returns the server result on success, or null if queued offline.
  /// After a successful call, fires a DeltaPull so side-effect rows
  /// (journal entries, safe transactions, stock movements, …) propagate
  /// back to the local DB without waiting for the next sync tick.
  ///
  /// **Mirror-mode behaviour (Feature 006 / MM.C):** when
  /// `WriteRouter.isMirrorActive` is true, the admin's HQ-side userId is
  /// stamped into [payload] for audit attribution, the outbox fallback
  /// is **skipped**, and a network failure raises
  /// [MirrorOfflineException] instead of silently queueing. Mirror mode
  /// is the admin acting as HQ from a remote laptop — buffering writes
  /// in the outbox would let HQ data drift out of sync without anyone
  /// noticing.
  static Future<T?> _tryOrQueue<T>({
    required String tableName,
    required String operation,
    required Map<String, dynamic> payload,
    required Future<T?> Function(String idempotencyKey) serverCall,
  }) async {
    await _enrichPayloadWithUsername(payload);
    final mirrorMode = WriteRouter.isMirrorActive;
    if (mirrorMode) WriteRouter.stampAdminAttribution(payload);
    final idempotencyKey = const Uuid().v7();
    payload['idempotency_key'] = idempotencyKey;
    try {
      final result = await serverCall(idempotencyKey);
      unawaited(DeltaPullService.instance.pullAll());
      // Feature 011 / Issue 10 — opportunistic outbox drain.
      // Field evidence: a client queued POS-2 and POS-3 offline, then
      // POS-4 succeeded once the server became reachable, but POS-2/3
      // sat in the outbox unattended for minutes. The drain only fired
      // on WebSocket reconnect, pending-count change at queue time, or
      // a 30-second heartbeat — never on operation success. Now that
      // we know the server is reachable (this serverCall just succeeded),
      // kick the drain so any pre-existing pending items go out
      // immediately. drainOutbox() is reentrant-safe via its
      // _isDraining guard, so calling it on every success is cheap.
      unawaited(OfflineSyncWorker.instance.drainOutbox(force: true));
      return result;
    } catch (e) {
      if (mirrorMode) {
        final isNetwork = _isNetworkException(e);
        // Persist the full underlying error to disk so an operator can pull
        // the log file and see what actually failed — `debugPrint` alone is
        // invisible in release builds.
        unawaited(DiagnosticLogger.log(
          'MIRROR-WRITE',
          '❌ $tableName/$operation failed '
          '(${isNetwork ? "network" : "server"}): $e',
        ));
        debugPrint('[MirrorInterceptor] Mirror write FAILED for '
            '$tableName/$operation — re-throwing as MirrorOfflineException '
            '(${isNetwork ? "network" : "server"}: $e)');
        throw isNetwork
            ? MirrorOfflineException.network(e.toString())
            : MirrorOfflineException.serverError(e.toString());
      }
      debugPrint('[ClientInterceptor] Server unreachable — queueing $tableName/$operation offline (error: $e)');
      if (_db != null) {
        await _db!.addToSyncOutbox(
          tableName: tableName,
          recordId: payload['id']?.toString() ??
              payload['globalId']?.toString() ??
              payload['invoiceNumber']?.toString() ??
              '0',
          operation: operation,
          payload: payload,
          idempotencyKey: idempotencyKey,
        );
      } else {
        debugPrint('[ClientInterceptor] ⚠️⚠️⚠️ WRITE LOST — _db is null for $tableName/$operation. '
            'Call ClientWriteInterceptor.initialize(db) at startup BEFORE any writes.');
        unawaited(DiagnosticLogger.log(
          'CLIENT-WRITE',
          '⚠️ WRITE LOST — _db null for $tableName/$operation '
          '(initialize() not called)',
        ));
      }
      return null;
    }
  }

  /// Dispatch a server write under the failure contract of the CURRENT mode.
  ///
  /// [_tryOrQueue] already gets the interceptor side right: mirror mode skips
  /// the outbox and throws [MirrorOfflineException]. The defect this helper
  /// closes is on the **caller** side — repositories launched the submit with
  /// `unawaited(...).catchError(debugPrint)` and then wrote their local cache
  /// row unconditionally. In mirror mode that turns a rejected write into a
  /// row the operator sees as saved forever, while HQ never heard about it
  /// (and the log line even claimed "queued in outbox", which is a lie there).
  ///
  /// * **Mirror** — `await` the submit and let the exception propagate, so the
  ///   caller aborts BEFORE writing anything locally. Mirror has no outbox by
  ///   design (SYNC_ARCHITECTURE §8.3); the server is the source of truth and
  ///   the next DeltaPull re-materialises whatever HQ actually accepted.
  /// * **Client** — unchanged fire-and-forget. By the time the future
  ///   completes `_tryOrQueue` has already parked the payload in the outbox,
  ///   so blocking the UI on the network would only hurt offline-first
  ///   resilience on cashier devices.
  ///
  /// Awaiting inside a DB transaction is deliberately NOT how this is used:
  /// callers must submit first, then open their local transaction. Holding a
  /// SQLite/PG transaction open across an HTTP round-trip locks the database
  /// for the duration and is a red rule in SYNC_ARCHITECTURE §9.6.
  // ── نطاقُ تجميع الاستبدال ───────────────────────────────────────────────
  //
  // الاستبدالُ مستندان في معاملةٍ واحدة، وقرارُ المالك أن يصلا الخادمَ في
  // **حمولةٍ واحدة**. وشقّاه يرسلان من مستودعَين مختلفَين لا يعرف أحدُهما
  // الآخر، لكنّ كليهما يمرّ من هنا — فالالتقاطُ في هذه النقطة يقمع
  // الحمولتَين المنفردتَين بلا لمسِ أيٍّ من المستودعَين.
  //
  // **و`Zone` لا حقلٌ ساكن:** الحقلُ الساكنُ يتسرّب إن رمى نداءٌ بين الفتح
  // والإغلاق، فيبتلع مزامنةَ كلِّ بيعٍ تالٍ صامتاً. وقيمةُ النطاق تموت مع
  // النطاق مهما خرج منه الاستثناء.
  //
  // ⚠️ **وهذا يرفع انتهاكاً قائماً لا يضيف واحداً:** [dispatchWrite] في وضع
  // المرآة تنتظر الشبكةَ (`await submit()`)، وشقُّ المردود يُنادى **داخل**
  // معاملة الاستبدال ⇒ معاملةُ قاعدةٍ مفتوحةٌ عبر ذهابِ HTTP وإيابِه، وهي
  // قاعدةٌ حمراء (‏SYNC_ARCHITECTURE §9.6). والالتقاطُ لا يلمس الشبكةَ
  // أصلاً، والإرسالُ يقع **بعد** إغلاق المعاملة.
  static const Object _exchangeCollectorKey = #picposExchangeCollector;

  /// المُجمِّعُ الفعّالُ في النطاق الحاليّ، أو `null` خارجَه — والخارجُ هو
  /// الحالةُ الساحقة، فكلُّ بيعٍ ومردودٍ عاديٍّ يمرّ من هنا بلا تغيير.
  static ExchangeLegCollector? get activeExchangeCollector =>
      Zone.current[_exchangeCollectorKey] as ExchangeLegCollector?;

  /// يشغّل [body] في نطاقٍ يُلتقَط فيه شقّا الاستبدال بدل إرسالهما منفردَين.
  static Future<T> runWithExchangeCollector<T>(
    ExchangeLegCollector collector,
    Future<T> Function() body,
  ) =>
      runZoned(
        body,
        zoneValues: <Object?, Object?>{_exchangeCollectorKey: collector},
      );

  static Future<void> dispatchWrite(
    Future<Object?> Function() submit, {
    required String tag,
  }) async {
    if (SyncInterceptor.isMirrorMode) {
      await submit();
      return;
    }
    // Client mode keeps the legacy contract EXACTLY, including the outer
    // guard: a throw raised while merely building the request must not take
    // down the caller, because the local write that follows is the cashier's
    // record of the sale.
    try {
      unawaited(submit().catchError((Object e) {
        debugPrint('[$tag] Server sync failed (queued in outbox): $e');
        return null;
      }));
    } catch (e) {
      debugPrint('[$tag] Sync setup failed: $e');
    }
  }

  /// Void-returning variant: returns true if succeeded or queued.
  ///
  /// Same mirror-mode semantics as [_tryOrQueue] — see that method's
  /// doc for the no-outbox + MirrorOfflineException contract.
  static Future<bool> _tryOrQueueVoid({
    required String tableName,
    required String operation,
    required Map<String, dynamic> payload,
    required Future<void> Function(String idempotencyKey) serverCall,
  }) async {
    await _enrichPayloadWithUsername(payload);
    final mirrorMode = WriteRouter.isMirrorActive;
    if (mirrorMode) WriteRouter.stampAdminAttribution(payload);
    final idempotencyKey = const Uuid().v7();
    payload['idempotency_key'] = idempotencyKey;
    try {
      await serverCall(idempotencyKey);
      unawaited(DeltaPullService.instance.pullAll());
      // Feature 011 / Issue 10 — opportunistic outbox drain (mirror of
      // the same logic in _tryOrQueue above; see that comment).
      unawaited(OfflineSyncWorker.instance.drainOutbox(force: true));
      return true;
    } catch (e) {
      if (mirrorMode) {
        final isNetwork = _isNetworkException(e);
        unawaited(DiagnosticLogger.log(
          'MIRROR-WRITE',
          '❌ $tableName/$operation failed '
          '(${isNetwork ? "network" : "server"}): $e',
        ));
        debugPrint('[MirrorInterceptor] Mirror void write FAILED for '
            '$tableName/$operation — re-throwing as MirrorOfflineException '
            '(${isNetwork ? "network" : "server"}: $e)');
        throw isNetwork
            ? MirrorOfflineException.network(e.toString())
            : MirrorOfflineException.serverError(e.toString());
      }
      debugPrint('[ClientInterceptor] Server unreachable — queueing $tableName/$operation offline (error: $e)');
      if (_db != null) {
        await _db!.addToSyncOutbox(
          tableName: tableName,
          recordId: payload['id']?.toString() ??
              payload['globalId']?.toString() ??
              payload['invoiceNumber']?.toString() ??
              '0',
          operation: operation,
          payload: payload,
          idempotencyKey: idempotencyKey,
        );
      } else {
        debugPrint('[ClientInterceptor] ⚠️⚠️⚠️ WRITE LOST — _db is null for $tableName/$operation (void variant). '
            'Call ClientWriteInterceptor.initialize(db) at startup BEFORE any writes.');
        unawaited(DiagnosticLogger.log(
          'CLIENT-WRITE',
          '⚠️ WRITE LOST — _db null for $tableName/$operation void '
          '(initialize() not called)',
        ));
      }
      return true; // queued offline
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // Shared globalId helpers (used by all part-file modules)
  // ═══════════════════════════════════════════════════════════════

  /// Look up the local `parties` row for [partyId] and return its `globalId`.
  /// Mints + persists a UUID if missing (legacy data). Returns null for a
  /// null/zero id or when the row cannot be found.
  static Future<String?> _lookupPartyGlobalId(int? partyId) async {
    if (partyId == null || partyId == 0 || _db == null) return null;
    try {
      final row = await (_db!.select(_db!.parties)
            ..where((p) => p.id.equals(partyId))
            ..limit(1))
          .getSingleOrNull();
      if (row == null) return null;
      var gid = row.globalId;
      if (gid == null || gid.isEmpty) {
        gid = const Uuid().v7();
        try {
          await (_db!.update(_db!.parties)..where((p) => p.id.equals(partyId)))
              .write(PartiesCompanion(globalId: Value(gid)));
        } catch (_) {}
      }
      return gid;
    } catch (e) {
      debugPrint('[ClientInterceptor] party lookup for id=$partyId failed (non-fatal): $e');
      return null;
    }
  }

  /// Look up the local `parties` row for [partyId] and return its name.
  /// Returns null for a null/zero id or when the row cannot be found.
  static Future<String?> _lookupPartyName(int? partyId) async {
    if (partyId == null || partyId == 0 || _db == null) return null;
    try {
      final row = await (_db!.select(_db!.parties)
            ..where((p) => p.id.equals(partyId))
            ..limit(1))
          .getSingleOrNull();
      return row?.name;
    } catch (e) {
      debugPrint('[ClientInterceptor] party name lookup for id=$partyId failed (non-fatal): $e');
      return null;
    }
  }

  /// Look up the local `products` row for [productId] and return its
  /// `globalId`. Mints + persists a UUID if missing. Returns null for a
  /// null/zero id or when the row doesn't exist.
  static Future<String?> _lookupProductGlobalId(int? productId) async {
    if (productId == null || productId == 0 || _db == null) return null;
    try {
      final row = await (_db!.select(_db!.products)
            ..where((p) => p.id.equals(productId))
            ..limit(1))
          .getSingleOrNull();
      if (row == null) return null;
      var gid = row.globalId;
      if (gid == null || gid.isEmpty) {
        gid = const Uuid().v7();
        try {
          await (_db!.update(_db!.products)..where((p) => p.id.equals(productId)))
              .write(ProductsCompanion(globalId: Value(gid)));
        } catch (_) {}
      }
      return gid;
    } catch (e) {
      debugPrint('[ClientInterceptor] product lookup for id=$productId failed (non-fatal): $e');
      return null;
    }
  }

  /// Walk the items array inside [payload] and inject `productGlobalId` into
  /// each item whose `productId` resolves locally. Server handlers prefer
  /// the UUID over the integer id, surviving client/server id drift.
  static Future<void> _enrichItemsWithProductGlobalId(
    Map<String, dynamic> payload, {
    String itemsKey = 'items',
  }) async {
    final raw = payload[itemsKey];
    if (raw is! List) return;
    for (final item in raw) {
      if (item is! Map) continue;
      if (item['productGlobalId'] is String &&
          (item['productGlobalId'] as String).isNotEmpty) continue;
      final pid = item['productId'];
      final pidInt = pid is int
          ? pid
          : (pid is num ? pid.toInt() : int.tryParse('${pid ?? ''}'));
      if (pidInt == null || pidInt == 0) continue;
      final gid = await _lookupProductGlobalId(pidInt);
      if (gid != null && gid.isNotEmpty) item['productGlobalId'] = gid;
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // Commerce — Expenses · Receipts · Parties
  // ═══════════════════════════════════════════════════════════════

  // ignore_for_file: lines_longer_than_80_chars
  static Future<int?> createExpense({required double amount, required String category, String? description, int? partyId, int? safeId, int? userId, int? costCenterId, int? branchId, String? globalId, String? paperType}) => _CwiCommerce.createExpense(amount: amount, category: category, description: description, partyId: partyId, safeId: safeId, userId: userId, costCenterId: costCenterId, branchId: branchId, globalId: globalId, paperType: paperType);

  static Future<bool> deleteExpense(int id) => _CwiCommerce.deleteExpense(id);

  static Future<int?> createReceipt({required double amount, required String category, String? description, int? partyId, int? safeId, int? userId, int? branchId, int? costCenterId, int? linkedAccountId, String? globalId, String? paperType}) => _CwiCommerce.createReceipt(amount: amount, category: category, description: description, partyId: partyId, safeId: safeId, userId: userId, branchId: branchId, costCenterId: costCenterId, linkedAccountId: linkedAccountId, globalId: globalId, paperType: paperType);

  static Future<int?> createParty({required String name, String? code, String? phone, String? address, bool isCustomer = true, bool isSupplier = false, bool isDeliveryCompany = false, String? taxId, double creditLimit = 0, int paymentTermsDays = 0, double balance = 0, double fixedDiscount = 0, String priceLevel = 'default', int? groupId, String? globalId, List<int> branchIds = const [], int? costCenterId}) => _CwiCommerce.createParty(name: name, code: code, phone: phone, address: address, isCustomer: isCustomer, isSupplier: isSupplier, isDeliveryCompany: isDeliveryCompany, taxId: taxId, creditLimit: creditLimit, paymentTermsDays: paymentTermsDays, balance: balance, fixedDiscount: fixedDiscount, priceLevel: priceLevel, groupId: groupId, globalId: globalId, branchIds: branchIds, costCenterId: costCenterId);

  static Future<bool> updateParty(int id, Map<String, dynamic> data) => _CwiCommerce.updateParty(id, data);

  static Future<int?> createUnitStatic(UnitsCompanion unit) async => SyncInterceptor.instance?.createUnit(unit);
  static Future<bool> updateUnitStatic(int id, Map<String, dynamic> data) async => SyncInterceptor.instance?.updateUnit(id, data) ?? Future.value(false);
  static Future<bool> deleteUnitStatic(int id) async => SyncInterceptor.instance?.deleteUnit(id) ?? Future.value(false);

  static Future<bool> deleteParty(int id, {String? idempotencyKey}) => _CwiCommerce.deleteParty(id, idempotencyKey: idempotencyKey);

  // ═══════════════════════════════════════════════════════════════
  // Catalog — Products · Purchases · Shifts · Settings
  //           Categories · Users · Warehouses
  // ═══════════════════════════════════════════════════════════════

  static Future<int?> createProduct({required String code, required String name, required double salePrice, required double costPrice, int? categoryId, int? supplierId, double currentStock = 0, String? barcode, double minStock = 0, double taxRate = 0, bool isSoldByWeight = false, bool allowNegativeSale = false, bool trackExpiry = false, int defaultShelfDays = 90, int alertDaysBefore = 30, double? pricePerUnit, double wholesalePrice = 0, double priceTalabat = 0, double priceCareem = 0, double priceAshyae = 0, String? scaleType, int? scalePluNumber, String productType = 'product', int? warehouseId, String? globalId, List<Map<String, dynamic>>? units, List<Map<String, dynamic>>? barcodes}) => _CwiCatalog.createProduct(code: code, name: name, salePrice: salePrice, costPrice: costPrice, categoryId: categoryId, supplierId: supplierId, currentStock: currentStock, barcode: barcode, minStock: minStock, taxRate: taxRate, isSoldByWeight: isSoldByWeight, allowNegativeSale: allowNegativeSale, trackExpiry: trackExpiry, defaultShelfDays: defaultShelfDays, alertDaysBefore: alertDaysBefore, pricePerUnit: pricePerUnit, wholesalePrice: wholesalePrice, priceTalabat: priceTalabat, priceCareem: priceCareem, priceAshyae: priceAshyae, scaleType: scaleType, scalePluNumber: scalePluNumber, productType: productType, warehouseId: warehouseId, globalId: globalId, units: units, barcodes: barcodes);

  static Future<bool> updateProduct(int id, Map<String, dynamic> data) => _CwiCatalog.updateProduct(id, data);

  static Future<int?> createProductUnitStatic(ProductUnitsCompanion unit) async => SyncInterceptor.instance?.createProductUnit(unit);
  static Future<bool> updateProductUnitStatic(int id, Map<String, dynamic> data) async => SyncInterceptor.instance?.updateProductUnit(id, data) ?? Future.value(false);
  static Future<bool> deleteProductUnitStatic(int id) async => SyncInterceptor.instance?.deleteProductUnit(id) ?? Future.value(false);

  static Future<bool> deleteProduct(int id, {String? idempotencyKey}) => _CwiCatalog.deleteProduct(id, idempotencyKey: idempotencyKey);

  static Future<int?> createPurchase({required int supplierId, required List<Map<String, dynamic>> items, double paid = 0, String? notes, String? globalId, int? userId}) => _CwiCatalog.createPurchase(supplierId: supplierId, items: items, paid: paid, notes: notes, globalId: globalId, userId: userId);

  static Future<bool> updatePurchase({required int invoiceId, required int supplierId, required List<Map<String, dynamic>> items, double paid = 0, String? notes, int? warehouseId, int? branchId, int? costCenterId, String? paymentMethod, String? supplierInvoiceNumber, int? userId}) => _CwiCatalog.updatePurchase(invoiceId: invoiceId, supplierId: supplierId, items: items, paid: paid, notes: notes, warehouseId: warehouseId, branchId: branchId, costCenterId: costCenterId, paymentMethod: paymentMethod, supplierInvoiceNumber: supplierInvoiceNumber, userId: userId);

  static Future<bool> deletePurchase(int id) => _CwiCatalog.deletePurchase(id);

  static Future<int?> openShift(int userId, double openingBalance,
          {int? localShiftId, int? branchId, String? globalId}) =>
      _CwiCatalog.openShift(userId, openingBalance,
          localShiftId: localShiftId,
          branchId: branchId,
          globalId: globalId);

  static Future<bool> closeShift({required int userId, required double actualCash, double actualCard = 0}) => _CwiCatalog.closeShift(userId: userId, actualCash: actualCash, actualCard: actualCard);

  static Future<bool> saveSettings(Map<String, String> settings) => _CwiCatalog.saveSettings(settings);

  static Future<int?> createCategory({required String name, required String color, int? printerId, String? iconName, bool isGlobal = true, List<int> branchIds = const []}) => _CwiCatalog.createCategory(name: name, color: color, printerId: printerId, iconName: iconName, isGlobal: isGlobal, branchIds: branchIds);

  static Future<bool> updateCategory({required int id, required String name, required String color, int? printerId, String? iconName, bool isGlobal = true, List<int> branchIds = const []}) => _CwiCatalog.updateCategory(id: id, name: name, color: color, printerId: printerId, iconName: iconName, isGlobal: isGlobal, branchIds: branchIds);

  // Feature 045 — accept optional [moveToCategoryId] so the caller can
  // pick the destination explicitly (null = uncategorized). Threaded
  // through to the server's deleteCategory handler so the bulk-move +
  // soft-delete run inside one server-side transaction.
  static Future<bool> deleteCategory(int id, {int? moveToCategoryId}) =>
      _CwiCatalog.deleteCategory(id, moveToCategoryId: moveToCategoryId);

  static Future<bool> updateUser(int userId, Map<String, dynamic> fields) => _CwiCatalog.updateUser(userId, fields);
  static Future<bool> updateUserPassword(int userId, String password) => _CwiCatalog.updateUserPassword(userId, password);
  static Future<bool> updateUserPin(int userId, String? pin) => _CwiCatalog.updateUserPin(userId, pin);

  static Future<int?> createWarehouse({required String name, int? branchId, String? globalId}) => _CwiCatalog.createWarehouse(name: name, branchId: branchId, globalId: globalId);
  static Future<bool> updateWarehouse(int id, Map<String, dynamic> fields) => _CwiCatalog.updateWarehouse(id, fields);
  static Future<bool> setDefaultWarehouse(int id) => _CwiCatalog.setDefaultWarehouse(id);
  static Future<bool> unsetDefaultWarehouse(int id) => _CwiCatalog.unsetDefaultWarehouse(id);
  static Future<bool> deleteWarehouse(int id) => _CwiCatalog.deleteWarehouse(id);

  // ═══════════════════════════════════════════════════════════════
  // Trading — Sales · Inventory · Commercial Papers
  //           Safe Operations · Stock Transfers · Purchase Push
  // ═══════════════════════════════════════════════════════════════

  static Future<int?> submitSale(Map<String, dynamic> saleData) => _CwiTrading.submitSale(saleData);
  static Future<int?> submitHeldOrder(Map<String, dynamic> orderData) => _CwiTrading.submitHeldOrder(orderData);
  static Future<bool> deleteHeldOrder(int id) => _CwiTrading.deleteHeldOrder(id);
  static Future<int?> submitSalesReturn(Map<String, dynamic> returnData) => _CwiTrading.submitSalesReturn(returnData);
  static Future<int?> submitExchange(Map<String, dynamic> exchangeData) => _CwiTrading.submitExchange(exchangeData);
  static Future<bool> deleteSalesInvoice(int id) => _CwiTrading.deleteSalesInvoice(id);
  static Future<bool> updateSalesInvoice(int id, Map<String, dynamic> data) => _CwiTrading.updateSalesInvoice(id, data);
  // C-02 (Spec 151) — sales-invoice void submit (globalId-resolved).
  static Future<bool> submitVoidSalesInvoice({required int salesId, String? salesGlobalId, String? invoiceNumber, String? reason, required String globalId, int? userId}) => _CwiTrading.submitVoidSalesInvoice(salesId: salesId, salesGlobalId: salesGlobalId, invoiceNumber: invoiceNumber, reason: reason, globalId: globalId, userId: userId);
  // Spec 151 C-05 — customer-collection submit (globalId-resolved, additive).
  static Future<bool> submitSalesPayment({required int salesId, String? salesGlobalId, String? invoiceNumber, required double amount, required String globalId, int? userId}) => _CwiTrading.submitSalesPayment(salesId: salesId, salesGlobalId: salesGlobalId, invoiceNumber: invoiceNumber, amount: amount, globalId: globalId, userId: userId);

  static Future<bool> adjustStock({required int productId, required int warehouseId, required double quantity, String? type, String? notes, String? adjustmentEventGid}) => _CwiTrading.adjustStock(productId: productId, warehouseId: warehouseId, quantity: quantity, type: type, notes: notes, adjustmentEventGid: adjustmentEventGid);

  static Future<int> reconcileOpeningStocks() => _CwiTrading.reconcileOpeningStocks();

  static Future<int?> createCommercialPaper({required String paperNumber, required String type, required String direction, required int partyId, required double amount, required DateTime issueDate, required DateTime dueDate, String? bankName, int? safeId, String? accountNumber, String? notes, String? globalId}) => _CwiTrading.createCommercialPaper(paperNumber: paperNumber, type: type, direction: direction, partyId: partyId, amount: amount, issueDate: issueDate, dueDate: dueDate, bankName: bankName, safeId: safeId, accountNumber: accountNumber, notes: notes, globalId: globalId);

  // Feature 048 (v130) — accept `counterAccountId` so the user-chosen
  // contra leg from the status-change dialog reaches the server's
  // JE poster instead of being silently dropped into the notes string.
  static Future<bool> updateCommercialPaperStatus(int id, String status,
          {int? changedBy, String? notes, int? counterAccountId}) =>
      _CwiTrading.updateCommercialPaperStatus(id, status,
          changedBy: changedBy,
          notes: notes,
          counterAccountId: counterAccountId);
  static Future<bool> renewCommercialPaper(int id, DateTime newDueDate, {int? changedBy, String? notes}) => _CwiTrading.renewCommercialPaper(id, newDueDate, changedBy: changedBy, notes: notes);
  static Future<bool> partialCollectPaper(int id, double amount, {int? changedBy, String? notes}) => _CwiTrading.partialCollectPaper(id, amount, changedBy: changedBy, notes: notes);
  static Future<bool> endorseCommercialPaper(int id, int toPartyId, {int? changedBy, String? notes}) => _CwiTrading.endorseCommercialPaper(id, toPartyId, changedBy: changedBy, notes: notes);
  static Future<bool> depositPaperForCollection(int id, int bankSafeId, {int? changedBy, String? notes}) => _CwiTrading.depositPaperForCollection(id, bankSafeId, changedBy: changedBy, notes: notes);
  static Future<bool> reissueCommercialPaper(int id, int newPartyId, {int? changedBy, String? notes}) => _CwiTrading.reissueCommercialPaper(id, newPartyId, changedBy: changedBy, notes: notes);

  static Future<bool> submitSafeTransfer({required int fromSafeId, required int toSafeId, required double amount, int? userId, String? description}) => _CwiTrading.submitSafeTransfer(fromSafeId: fromSafeId, toSafeId: toSafeId, amount: amount, userId: userId, description: description);

  static Future<bool> submitSetDefaultSafe({required int safeId}) => _CwiTrading.submitSetDefaultSafe(safeId: safeId);

  static Future<bool> submitStockTransfer({required int fromWarehouseId, required int toWarehouseId, required List<Map<String, dynamic>> items, int? userId, String? notes, String? globalId}) => _CwiTrading.submitStockTransfer(fromWarehouseId: fromWarehouseId, toWarehouseId: toWarehouseId, items: items, userId: userId, notes: notes, globalId: globalId);

  static Future<bool> submitPurchase({required int supplierId, required int warehouseId, required List<Map<String, dynamic>> items, required double paid, String paymentMethod = 'cash', String? supplierInvoiceNumber, String? notes, int? costCenterId, int? branchId, int? safeId, String? globalId, int? userId, String? createdByUsername, double discount = 0, int? currencyId, double? exchangeRate, ImportDocumentFields? importDetails}) => _CwiTrading.submitPurchase(supplierId: supplierId, warehouseId: warehouseId, items: items, paid: paid, paymentMethod: paymentMethod, supplierInvoiceNumber: supplierInvoiceNumber, notes: notes, costCenterId: costCenterId, branchId: branchId, safeId: safeId, globalId: globalId, userId: userId, createdByUsername: createdByUsername, discount: discount, currencyId: currencyId, exchangeRate: exchangeRate, importDetails: importDetails);

  static Future<bool> submitPurchaseReturn(Map<String, dynamic> returnData) => _CwiTrading.submitPurchaseReturn(returnData);
  static Future<bool> submitPurchaseReturnEdit(Map<String, dynamic> editData) => _CwiTrading.submitPurchaseReturnEdit(editData);

  // PR-2 (pre-deploy batch B6) — purchase-invoice void submit.
  static Future<bool> submitVoidPurchase({required int purchaseId, String? purchaseGlobalId, String? invoiceNumber, String? reason, required String globalId, int? userId}) => _CwiTrading.submitVoidPurchase(purchaseId: purchaseId, purchaseGlobalId: purchaseGlobalId, invoiceNumber: invoiceNumber, reason: reason, globalId: globalId, userId: userId);
  // Spec 151 C-03 — purchase-invoice payment submit.
  static Future<bool> submitPurchasePayment({required int purchaseId, String? purchaseGlobalId, String? invoiceNumber, required double amount, required String globalId, int? userId}) => _CwiTrading.submitPurchasePayment(purchaseId: purchaseId, purchaseGlobalId: purchaseGlobalId, invoiceNumber: invoiceNumber, amount: amount, globalId: globalId, userId: userId);
  static Future<bool> submitInventoryBond(Map<String, dynamic> bondData) => _CwiTrading.submitInventoryBond(bondData);
  static Future<bool> closeSafe(int safeId, {int? userId, double? cashAmount, double? bankAmount, String? notes, String? closeEventGid}) =>
      _CwiTrading.closeSafe(safeId, userId: userId, cashAmount: cashAmount, bankAmount: bankAmount, notes: notes, closeEventGid: closeEventGid);

  // ═══════════════════════════════════════════════════════════════
  // SyncInterceptor @override implementations — delegated to _CwiSync
  // ═══════════════════════════════════════════════════════════════

  @override
  Future<void> submitLandedCostApply(Map<String, dynamic> document) =>
      _CwiSync.submitLandedCostApply(document);

  @override
  Future<void> submitFixedAssetCreate(Map<String, dynamic> document) =>
      _CwiSync.submitFixedAssetCreate(document);

  @override
  Future<void> submitAssetDepreciationRun(Map<String, dynamic> request) =>
      _CwiSync.submitAssetDepreciationRun(request);

  @override
  Future<void> submitOperationalExpense(Map<String, dynamic> document) =>
      _CwiSync.submitOperationalExpense(document);

  @override
  Future<void> submitManufacturingAction(Map<String, dynamic> request) =>
      _CwiSync.submitManufacturingAction(request);

  @override
  Future<void> submitBookingDepositApplication(
          Map<String, dynamic> request) =>
      _CwiSync.submitBookingDepositApplication(request);

  @override
  Future<void> submitJournalEntry({required String description, required DateTime date, required List<dynamic> lines, String? referenceType, int? referenceId, bool isAutoPosted = false, int? costCenterId, int? branchId, String? globalId}) => _CwiSync.submitJournalEntry(description: description, date: date, lines: lines, referenceType: referenceType, referenceId: referenceId, isAutoPosted: isAutoPosted, costCenterId: costCenterId, branchId: branchId, globalId: globalId);

  @override
  Future<void> submitSafeTransaction({required int safeId, required String transactionType, required double amount, required String category, String? description, int? userId, String? referenceType, int? referenceId, String? globalId, String? safeGlobalId, int? costCenterId, int? partyId, String? partyGlobalId}) => _CwiSync.submitSafeTransaction(safeId: safeId, transactionType: transactionType, amount: amount, category: category, description: description, userId: userId, referenceType: referenceType, referenceId: referenceId, globalId: globalId, safeGlobalId: safeGlobalId, costCenterId: costCenterId, partyId: partyId, partyGlobalId: partyGlobalId);

  @override
  Future<int?> createUnit(covariant UnitsCompanion unit) => _CwiSync.createUnit(unit);
  @override
  Future<bool> updateUnit(int id, Map<String, dynamic> data) => _CwiSync.updateUnit(id, data);
  @override
  Future<bool> deleteUnit(int id) => _CwiSync.deleteUnit(id);
  @override
  Future<int?> createProductUnit(covariant ProductUnitsCompanion productUnit) => _CwiSync.createProductUnit(productUnit);
  @override
  Future<bool> updateProductUnit(int id, Map<String, dynamic> data) => _CwiSync.updateProductUnit(id, data);
  @override
  Future<bool> deleteProductUnit(int id) => _CwiSync.deleteProductUnit(id);
  @override
  Future<int?> createProductBarcode(covariant ProductBarcodesCompanion barcode) => _CwiSync.createProductBarcode(barcode);
  @override
  Future<bool> deleteProductBarcode(int id) => _CwiSync.deleteProductBarcode(id);
  @override
  Future<int?> createUser({required String username, required String password, required String displayName, int? roleId, List<int> branchIds = const [], String? globalId, String? cardCode}) => _CwiSync.createUser(username: username, password: password, displayName: displayName, roleId: roleId, branchIds: branchIds, globalId: globalId, cardCode: cardCode);
  @override
  Future<int?> createRole({required String name, String? description, bool isSystemRole = false}) => _CwiSync.createRole(name: name, description: description, isSystemRole: isSystemRole);
  @override
  Future<bool> setRolePermissions(int roleId, List<String> permissionCodes, {String? roleGlobalId, String? roleName}) => _CwiSync.setRolePermissions(roleId, permissionCodes, roleGlobalId: roleGlobalId, roleName: roleName);
  @override
  Future<int?> createRegion({required String name, String? address, String? phone, int? costCenterId}) => _CwiSync.createRegion(name: name, address: address, phone: phone, costCenterId: costCenterId);
  @override
  Future<bool> updateRegion({required int id, required String name, String? address, String? phone, int? costCenterId}) => _CwiSync.updateRegion(id: id, name: name, address: address, phone: phone, costCenterId: costCenterId);
  @override
  Future<int?> createPartyGroup(covariant dynamic companion) => _CwiSync.createPartyGroup(companion);
  @override
  Future<bool> updatePartyGroup(int id, Map<String, dynamic> data) => _CwiSync.updatePartyGroup(id, data);
  @override
  Future<bool> deletePartyGroup(int id) => _CwiSync.deletePartyGroup(id);
  @override
  Future<int?> createPurchaseOrder(Map<String, dynamic> data, List<Map<String, dynamic>> items) => _CwiSync.createPurchaseOrder(data, items);
  @override
  Future<bool> updatePurchaseOrderStatus(int id, String status) => _CwiSync.updatePurchaseOrderStatus(id, status);
  @override
  Future<bool> deletePurchaseOrder(int id) => _CwiSync.deletePurchaseOrder(id);
  @override
  Future<int?> createSalesOrder(Map<String, dynamic> data, List<Map<String, dynamic>> items) => _CwiSync.createSalesOrder(data, items);
  @override
  Future<bool> updateSalesOrderStatus(int id, String status) => _CwiSync.updateSalesOrderStatus(id, status);
  @override
  Future<bool> deleteSalesOrder(int id) => _CwiSync.deleteSalesOrder(id);
  @override
  Future<int?> createQuotation(Map<String, dynamic> data, List<Map<String, dynamic>> items) => _CwiSync.createQuotation(data, items);
  @override
  Future<bool> updateQuotationStatus(int id, String status, {int? convertedInvoiceId}) => _CwiSync.updateQuotationStatus(id, status, convertedInvoiceId: convertedInvoiceId);
  @override
  Future<bool> updateQuotation(int id, Map<String, dynamic> data, List<Map<String, dynamic>> items) => _CwiSync.updateQuotation(id, data, items);
  @override
  Future<bool> deleteQuotation(int id) => _CwiSync.deleteQuotation(id);
  @override
  Future<int?> createPriceList(Map<String, dynamic> data) => _CwiSync.createPriceList(data);
  @override
  Future<bool> updatePriceList(int id, Map<String, dynamic> data) => _CwiSync.updatePriceList(id, data);
  @override
  Future<bool> setPriceListItem(Map<String, dynamic> data) => _CwiSync.setPriceListItem(data);
  @override
  Future<int?> createPrinter(Map<String, dynamic> data) => _CwiSync.createPrinter(data);
  @override
  Future<bool> updatePrinter(int id, Map<String, dynamic> data) => _CwiSync.updatePrinter(id, data);
  @override
  Future<bool> deletePrinter(int id) => _CwiSync.deletePrinter(id);

  // ── Activity Logs ──────────────────────────────────────────────────────────

  /// Push an activity log entry to the server (non-blocking, offline-safe).
  static Future<bool> pushActivityLog(Map<String, dynamic> logData) =>
      _CwiSync.pushActivityLog(logData);

  // ═══════════════════════════════════════════════════════════════
  // Admin (Feature 006 / MM.C) — Branches · Safes · Accounts
  //                              · Cost Centers · Document Sequences
  //
  // Routes "previously server-only" admin CRUD through the same
  // intercepted path as commerce/catalog so mirror-mode operators can
  // perform these operations from a remote laptop.
  // ═══════════════════════════════════════════════════════════════

  static Future<int?> createBranch({
    required String name,
    String? code,
    String? address,
    String? phone,
    int? costCenterId,
    int? regionId,
    String? globalId,
  }) =>
      _CwiAdmin.createBranch(
        name: name,
        code: code,
        address: address,
        phone: phone,
        costCenterId: costCenterId,
        regionId: regionId,
        globalId: globalId,
      );

  static Future<bool> updateBranch(int id, Map<String, dynamic> data) =>
      _CwiAdmin.updateBranch(id, data);

  // Feature 049 (v131) — see _CwiAdmin.deleteBranch for the reassign
  // semantics. Null falls back to the legacy "throw if user assignments
  // exist" behaviour so old callers stay safe.
  static Future<bool> deleteBranch(int id, {int? reassignUsersToBranchId}) =>
      _CwiAdmin.deleteBranch(id,
          reassignUsersToBranchId: reassignUsersToBranchId);

  static Future<int?> createSafe({
    required String name,
    required String safeType,
    String? bankName,
    String? accountNumber,
    int? costCenterId,
    int? branchId,
    String? globalId,
  }) =>
      _CwiAdmin.createSafe(
        name: name,
        safeType: safeType,
        bankName: bankName,
        accountNumber: accountNumber,
        costCenterId: costCenterId,
        branchId: branchId,
        globalId: globalId,
      );

  static Future<bool> updateSafe(int id, Map<String, dynamic> data) =>
      _CwiAdmin.updateSafe(id, data);

  static Future<bool> deleteSafe(int id) => _CwiAdmin.deleteSafe(id);

  static Future<int?> createAccount({
    required String code,
    required String name,
    required String accountType,
    int? parentId,
    String? globalId,
  }) =>
      _CwiAdmin.createAccount(
        code: code,
        name: name,
        accountType: accountType,
        parentId: parentId,
        globalId: globalId,
      );

  static Future<bool> updateAccount(int id, Map<String, dynamic> data) =>
      _CwiAdmin.updateAccount(id, data);

  static Future<bool> deleteAccount(int id) => _CwiAdmin.deleteAccount(id);

  static Future<bool> setAccountMapping({
    required String purpose,
    required int accountId,
    int? costCenterId,
  }) =>
      _CwiAdmin.setAccountMapping(
        purpose: purpose,
        accountId: accountId,
        costCenterId: costCenterId,
      );

  static Future<bool> deleteAccountMapping({
    required String purpose,
    int? costCenterId,
  }) =>
      _CwiAdmin.deleteAccountMapping(
        purpose: purpose,
        costCenterId: costCenterId,
      );

  static Future<int?> createCostCenter({
    required String code,
    required String name,
    int? parentId,
    String? globalId,
  }) =>
      _CwiAdmin.createCostCenter(
        code: code,
        name: name,
        parentId: parentId,
        globalId: globalId,
      );

  static Future<bool> updateCostCenter(int id, Map<String, dynamic> data) =>
      _CwiAdmin.updateCostCenter(id, data);

  static Future<bool> deleteCostCenter(int id) => _CwiAdmin.deleteCostCenter(id);

  static Future<bool> setUserRegionAccess(int userId, List<int> regionIds) =>
      _CwiAdmin.setUserRegionAccess(userId, regionIds);
}
