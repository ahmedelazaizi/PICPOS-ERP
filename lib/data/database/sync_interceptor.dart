// import 'package:ural_erp/data/database/database.dart';
// Removed database.dart import to break circular dependency during build_runner analysis.

/// Abstract sync interceptor for database → network decoupling.
/// Implemented by ClientWriteInterceptor in the services layer.
abstract class SyncInterceptor {
  static SyncInterceptor? instance;

  static bool get isClientMode => instance?.isClientModeImpl ?? false;

  bool get isClientModeImpl;

  /// Spec 088 USR-2 — true ONLY when the device is operating in mirror
  /// mode (HQ admin laptop pointed at a remote server). Symmetric to
  /// [isClientMode] but stricter: [isClientMode] is true for client
  /// devices too (the broadened R9 predicate), while [isMirrorMode]
  /// excludes them. Used by [BranchSyncStrategy] to skip auto-deactivation
  /// of branches absent from a sync response, because on a mirror an
  /// absence can mean "out of the calling user's scope" rather than
  /// "deleted upstream". Returns false pre-instance-setup so a sync
  /// running before the interceptor is wired falls into safe (client)
  /// behavior.
  static bool get isMirrorMode => instance?.isMirrorModeImpl ?? false;

  bool get isMirrorModeImpl;

  /// Phase 5A.3 (Issue 5) — set by the auth controller on login, cleared on
  /// logout. Carries the **display name** of the current role, for logging and
  /// for the legacy [isCurrentUserAdmin] getter.
  ///
  /// المرحلة ١ / G2 — لم يعد يقرّر أي شيء في حصر المزامنة. كان
  /// `/api/sync/pull` يتجاوز فلتر الفرع بناءً على مطابقة نصّية لهذا الاسم،
  /// وهي **ليست صلاحية**: اسم يكتبه المشغّل. القرار انتقل إلى
  /// [currentUserIsSystemAdmin].
  static String? currentUserRole;

  /// Spec 060 Phase 2 / Spec 151 (P1-8) — set by the auth controller on login
  /// (mirrors [currentUserRole]). ServerProxy uses it as the key into its
  /// in-memory session-token map: on login it acquires a signed session token
  /// for this user and, on every outbound API call, stamps that token as
  /// `X-Session-Token` (replacing the old, forgeable `X-User-Id` header the
  /// server no longer trusts). The server derives the acting user from the
  /// token and gates handlers via ApiUserCtx.requirePermission. Null pre-login
  /// or post-logout — a request with no session token is treated as anonymous
  /// and a gated handler / branch-scoped read fails closed.
  static int? currentUserId;

  /// المرحلة ١ / G2 — «هل المستخدم الحالي **مدير النظام** فعلاً؟» يضبطه
  /// متحكّم المصادقة عند الدخول والترقية، ويمسحه عند الخروج (نفس نمط
  /// [currentUserRole] و[currentUserId]). هو وحده ما يقرأه مسار حصر
  /// المزامنة في `server_proxy._branchScopeQueryParam`.
  ///
  /// ⚠️ **العمود `roles.isSystemRole` وحده ليس اختبار إدارة.** معناه «دور
  /// مدمج غير قابل للتعديل»، و`database_seeder_permissions.dart` يزرعه
  /// `true` لخمسة أدوار: **مدير النظام · كاشير · مخزني · محاسب · مدير
  /// مالي**. فلو بُني هذا العلَم على العمود وحده لحصل **الكاشير** على سحب
  /// غير مقيّد — أوسع من المطابقة النصّية التي جاء ليستبدلها.
  ///
  /// القيمة الصحيحة هي **الاقتران**: `isSystemRole && name == 'مدير النظام'`
  /// — نفس ما يفعله `permissions_dao._isAdminRole` و
  /// `AuthStateBypass.hasSystemAdminBypass`. شرط `isSystemRole` ضروري
  /// بدوره: بدونه يخترع مشغّل دوراً مخصصاً بالاسم نفسه ويتجاوز كل شيء.
  ///
  /// `null` قبل الدخول ⇒ يُعامَل كـ«ليس مدير نظام» (يفشل مقفولاً).
  static bool? currentUserIsSystemAdmin;

  /// ⚠️ **مطابقة نصّية على اسم الدور — ليست صلاحية، ولا تستعملها في قرار
  /// أمني.** «مسؤول مبيعات» يطابق `contains('مسؤول')` فتُرجع `true`.
  ///
  /// المرحلة ١ / G2 — أُخرجت من مسار حصر المزامنة واستُبدلت بـ
  /// [currentUserIsSystemAdmin]. لا مستدعي إنتاجي لها الآن؛ أُبقيت في
  /// مكانها فقط لأن حذفها خارج نطاق المرحلة ١.
  static bool get isCurrentUserAdmin {
    final role = currentUserRole?.toLowerCase() ?? '';
    if (role.isEmpty) return false;
    return role.contains('admin') ||
        role.contains('مدير النظام') ||
        role.contains('مسؤول') ||
        role.contains('manager') ||
        role.contains('مدير مالي');
  }

  /// Submit a journal entry to the server for sync.
  Future<void> submitJournalEntry({
    required String description,
    required DateTime date,
    required List<dynamic> lines,
    String? referenceType,
    int? referenceId,
    bool isAutoPosted = false,
    int? costCenterId,
    int? branchId,
    String? globalId, // NEW: UUID-First sync
  });

  /// v166 — يُرسل ورقةَ تحميلٍ **مطبَّقةً** إلى الخادم.
  ///
  /// تطبيقُ الورقة حدثٌ ماليّ: يمزج المتوسّطَ المرجّح على الصنف وعلى
  /// المخزن ويُرحّل قيداً. وقاعدةُ المستودع أنّ **الخادمَ مصدرُ الحقيقة
  /// للمال والأستاذ والخزينة**، فالعميلُ يُرسل المستندَ ولا يحسب شيئاً.
  ///
  /// و[document] يحمل الورقةَ وبنودَها وتوزيعاتِها بمعرّفاتٍ عالميّة.
  Future<void> submitLandedCostApply(Map<String, dynamic> document);

  /// v166 — اقتناءُ أصلٍ ثابت. يحمل [document] هويّةَ الأصل وهويّةَ حسابه
  /// الفرعيّ وفئتَه **كاملةً** — لأنّ فئةً أنشأها هذا الجهازُ قد لا تكون
  /// على الخادم، فإرسالُ معرّفها وحدَه يجعل الأصلَ مردوداً أبداً.
  Future<void> submitFixedAssetCreate(Map<String, dynamic> document);

  /// v166 — طلبُ ترحيلِ إهلاكِ شهر. الطالبُ كثيرٌ والمنفّذُ واحد.
  Future<void> submitAssetDepreciationRun(Map<String, dynamic> request);

  /// v166 — مصروفٌ تشغيليٌّ بأثره الماليِّ كاملاً: قيدٌ وسندُ صرفٍ وخصمُ
  /// رصيد. الخادمُ ينفّذ الثلاثةَ، والعميلُ يُرسل فحسب.
  Future<void> submitOperationalExpense(Map<String, dynamic> document);

  /// v166 — حدثٌ ماليٌّ على أمرِ إنتاج. أثرُه **مخزنيٌّ** لا محاسبيٌّ فقط:
  /// البدءُ يخصم خاماتٍ والإنجازُ يُدخل تامّاً. وخصمٌ مضاعفٌ لا يُعكَس
  /// بقيدٍ — يُنتج رصيداً سالباً أو نقصاً لا يُفسَّر.
  Future<void> submitManufacturingAction(Map<String, dynamic> request);

  /// Submit a safe transaction to the server for sync.
  ///
  /// Phase 5B.4 (Issue 7) — `safeGlobalId` and `costCenterId` are added so
  /// the server can resolve the right safe/cost-center even when its own
  /// autoincrement ids have drifted from the client's. Mirrors what
  /// `/api/receipts` already does in postReceipt (commit 0d93217). Both
  /// optional for backward compatibility — when absent the server falls
  /// back to the legacy `safeId` lookup, matching pre-Phase-5 behaviour.
  Future<void> submitSafeTransaction({
    required int safeId,
    required String transactionType,
    required double amount,
    required String category,
    String? description,
    int? userId,
    String? referenceType,
    int? referenceId,
    String? globalId, // NEW: UUID-First sync
    String? safeGlobalId,
    int? costCenterId,
    // Spec 087 (F2) — thread the partyId + cross-instance globalId
    // through the generic safe-transaction sync path so vouchers
    // created via the legacy `/api/safes/transaction` endpoint land
    // with the right party link on the server. Previously the
    // endpoint dropped partyId silently → server rows had partyId=null
    // → other clients pulling the row saw the voucher missing from
    // the party's statement. The `/api/receipts` and `/api/expenses`
    // endpoints already handled partyId; this fills the gap on the
    // legacy generic endpoint that some replays + non-dialog paths
    // still hit.
    int? partyId,
    String? partyGlobalId,
  });

  // UOM AND BARCODE METHODS (Added for ClientMode reconciliation)
  Future<int?> createUnit(dynamic unit);
  Future<bool> updateUnit(int id, Map<String, dynamic> data);
  Future<bool> deleteUnit(int id);
  Future<int?> createProductUnit(dynamic productUnit);
  Future<bool> updateProductUnit(int id, Map<String, dynamic> data);
  Future<bool> deleteProductUnit(int id);
  Future<int?> createProductBarcode(dynamic barcode);
  Future<bool> deleteProductBarcode(int id);

  // USER MANAGEMENT
  Future<int?> createUser({
    required String username,
    required String password,
    required String displayName,
    int? roleId,
    List<int> branchIds = const [],
    // UUID-First (Phase 1): optional globalId so callers can pre-mint a UUID
    // and keep client-side + server-side rows synced by stable identity.
    String? globalId,
    // Issue 4 (Feature 018): MSR card code threaded end-to-end so admins on a
    // paired client can register a swipe-card for new users. Server already
    // accepts it (api_data_handler.dart `postUser`); this just plumbs it
    // through the interceptor + proxy chain.
    String? cardCode,
  });

  // ROLE MANAGEMENT
  Future<int?> createRole({
    required String name,
    String? description,
    bool isSystemRole = false,
  });

  /// Push role-permission assignments to the server.
  ///
  /// Spec 136 ISS-15: [roleGlobalId] + [roleName] let the server resolve (or
  /// placeholder-create) a role created only on this node before the FK-bound
  /// permission write.
  Future<bool> setRolePermissions(int roleId, List<String> permissionCodes,
      {String? roleGlobalId, String? roleName});

  // REGION MANAGEMENT
  Future<int?> createRegion({
    required String name,
    String? address,
    String? phone,
    int? costCenterId,
  });
  Future<bool> updateRegion({
    required int id,
    required String name,
    String? address,
    String? phone,
    int? costCenterId,
  });

  // ─── PARTY GROUP MANAGEMENT ───────────────────────────────────────
  Future<int?> createPartyGroup(dynamic companion);
  Future<bool> updatePartyGroup(int id, Map<String, dynamic> data);
  Future<bool> deletePartyGroup(int id);

  // ─── PURCHASE ORDER MANAGEMENT ────────────────────────────────────
  Future<int?> createPurchaseOrder(Map<String, dynamic> data, List<Map<String, dynamic>> items);
  Future<bool> updatePurchaseOrderStatus(int id, String status);
  Future<bool> deletePurchaseOrder(int id);

  // ─── SALES ORDER MANAGEMENT ───────────────────────────────────────
  Future<int?> createSalesOrder(Map<String, dynamic> data, List<Map<String, dynamic>> items);
  Future<bool> updateSalesOrderStatus(int id, String status);
  Future<bool> deleteSalesOrder(int id);

  // ─── QUOTATION MANAGEMENT ─────────────────────────────────────────
  Future<int?> createQuotation(Map<String, dynamic> data, List<Map<String, dynamic>> items);
  Future<bool> updateQuotationStatus(int id, String status, {int? convertedInvoiceId});
  Future<bool> updateQuotation(int id, Map<String, dynamic> data, List<Map<String, dynamic>> items);
  Future<bool> deleteQuotation(int id);

  // ─── PRICE LIST MANAGEMENT ────────────────────────────────────────
  Future<int?> createPriceList(Map<String, dynamic> data);
  Future<bool> updatePriceList(int id, Map<String, dynamic> data);
  Future<bool> setPriceListItem(Map<String, dynamic> data);

  // ─── PRINTER MANAGEMENT ───────────────────────────────────────────
  Future<int?> createPrinter(Map<String, dynamic> data);
  Future<bool> updatePrinter(int id, Map<String, dynamic> data);
  Future<bool> deletePrinter(int id);
}
