// حارس جلسات الويب في الخادم (بند الأمن 1: إبطال الجلسات + قراءة GET).
//
// يعالج ثلاثة أمور لا يعالجها فحصُ التوقيع وحده في `ApiSessionToken.verifyWeb`:
//   1. [isValid]: رمزٌ صالح التوقيع لكنّ مستخدمه عُطِّل/قُفل/حُذف أو تغيّر دوره
//      منذ الإصدار ⇒ يُرفض. الفحص من القاعدة مع كاش قصير ([cacheTtlMs] ≤ 15 ث).
//   2. [WebHttpReadGate]: قراءة GET على مسارات `/api/*` برمز ويب تمرّ بالصلاحية
//      نفسها التي تحكم قناة `/webdb` (`WebTablePolicy`) بدل أن تكون مفتوحةً
//      لكلّ مستخدم نشط (تقرير part2b §3.2).
//   3. [mayServeUserCredentials]: لا تُسلَّم اعتماداتُ المستخدمين (هاش/ملح/
//      cardCode) لرمز ويب أبداً.
//
// ⚠️ الحارس غير مُهيَّأ (`configure` لم يُستدعَ) ⇒ [isValid] يمرّ (اختبارات
// الوحدة بلا قاعدة)، أمّا بوابة GET فتفشل مغلقةً. المضيف الحقيقي يهيّئه من
// منشئ `ApiHandler`.

import 'package:shelf/shelf.dart';

import '../../core/permissions/web_table_policy.dart';
import '../../data/database/database.dart';
import 'api_session_token.dart';
import 'api_web_session_handler.dart' show ApiWebCtx;

class _UserState {
  _UserState({
    required this.atMs,
    required this.usable,
    required this.roleId,
    required this.codes,
  });
  final int atMs;
  final bool usable;
  final int? roleId;
  final List<String> codes;
}

class WebSessionGuard {
  WebSessionGuard._();

  /// عمر الكاش بالميلي ثانية (≤ 15 ث بحسب المتطلّب).
  static const int cacheTtlMs = 10 * 1000;

  static AppDatabase? _db;
  static final Map<int, _UserState> _cache = {};

  static void configure(AppDatabase? db) {
    _db = db;
    _cache.clear();
  }

  /// يُسقط كاش المستخدم فيُعاد فحصه فوراً (يُستدعى عند تعديله).
  static void invalidateUser(int userId) => _cache.remove(userId);

  /// يُستدعى بعد تعديل مستخدم: يُسقط الكاش، و[revokeSessions] يُبطل كلَّ
  /// جلسات الويب الصادرة له (تعطيل/قفل/حذف/تغيير كلمة مرور).
  static void userChanged(int userId, {bool revokeSessions = false}) {
    if (revokeSessions) ApiSessionToken.revokeUser(userId);
    invalidateUser(userId);
  }

  static Future<_UserState?> _state(int userId, int now) async {
    final db = _db;
    if (db == null) return null;
    final cached = _cache[userId];
    if (cached != null && now - cached.atMs < cacheTtlMs) return cached;
    final user = await (db.select(db.users)
          ..where((u) => u.id.equals(userId)))
        .getSingleOrNull();
    final usable = user != null &&
        user.isActive &&
        !user.isLocked &&
        user.deletedAt == null;
    final state = _UserState(
      atMs: now,
      usable: usable,
      roleId: user?.roleId,
      codes: usable ? await db.getUserPermissionCodes(userId) : const [],
    );
    if (_cache.length > 512) _cache.clear();
    _cache[userId] = state;
    return state;
  }

  /// هل ما زال صاحب [claims] مسموحاً؟ (يمرّ إن لم يُهيَّأ الحارس.)
  static Future<bool> isValid(WebSessionClaims claims, {int? nowMs}) async {
    if (_db == null) return true;
    try {
      final s = await _state(
        claims.userId,
        nowMs ?? DateTime.now().millisecondsSinceEpoch,
      );
      if (s == null || !s.usable) return false;
      if (claims.roleBound && claims.roleId != s.roleId) return false;
      return true;
    } catch (_) {
      return false; // تعذّر الفحص (قاعدة مغلقة/عطل) ⇒ فشل مغلق.
    }
  }

  /// أكواد صلاحيات المستخدم من الكاش القصير؛ null إن تعذّر/عُطِّل.
  static Future<List<String>?> codesOf(int userId, {int? nowMs}) async {
    try {
      final s = await _state(
        userId,
        nowMs ?? DateTime.now().millisecondsSinceEpoch,
      );
      return (s == null || !s.usable) ? null : s.codes;
    } catch (_) {
      return null;
    }
  }

  /// طلبٌ بجلسة ويب؟ (يضع الوسيط [ApiWebCtx.claimsKey] في السياق.)
  static bool isWebRequest(Request request) =>
      request.context[ApiWebCtx.claimsKey] is WebSessionClaims;

  /// هل يجوز تضمين اعتمادات المستخدمين (هاش/ملح/cardCode) في الاستجابة؟
  /// [pairingOpen]: نافذة الإقران مفتوحة. رمزُ الويب لا يستحقّها أبداً.
  static bool mayServeUserCredentials(
    Request request, {
    required bool pairingOpen,
    required bool hasIdentity,
  }) =>
      !isWebRequest(request) && (pairingOpen || hasIdentity);
}

/// بوابة قراءة GET لرمز الويب: بادئةُ المسار → الجداول التي يقرؤها.
///
/// قائمةُ سماحٍ صريحة: مسارٌ تحت `webWritePrefixes` غير مذكور هنا يُرفض على
/// GET (403). والصلاحيةُ هي صلاحيةُ جدول `WebTablePolicy` نفسه (جدولٌ ممنوع على
/// الويب ⇒ مسارٌ ممنوع)، فلا يُتجاوز تصنيفُ `/webdb` عبر HTTP.
class WebHttpReadGate {
  WebHttpReadGate._();

  static const Map<String, List<String>> tablesByPrefix = {
    '/api/accounts': ['accounts'],
    '/api/account-mappings': ['account_mappings'],
    '/api/accounting-periods': ['accounting_periods'],
    '/api/activity-logs': ['activity_logs'],
    '/api/attachments': ['attachments'],
    '/api/branches': ['branches'],
    '/api/categories': ['categories'],
    '/api/commercial-papers': ['commercial_papers'],
    '/api/cost_centers': ['cost_centers'],
    '/api/document-sequences': ['document_sequences'],
    '/api/expenses': ['op_expenses'],
    '/api/fiscal-years': ['fiscal_years'],
    '/api/fixed-assets': ['fixed_assets'],
    '/api/inventory': ['inventory_balances'],
    '/api/journals': ['journal_entries', 'journal_entry_lines'],
    '/api/landed-costs': ['landed_cost_sheets'],
    '/api/offers': ['offers'],
    '/api/op-expenses': ['op_expenses'],
    '/api/parties': ['parties'],
    '/api/party-groups': ['party_groups'],
    '/api/payments': ['payments'],
    '/api/permissions': ['permissions'],
    '/api/price-list-items': ['price_list_items'],
    '/api/price-lists': ['price_lists'],
    '/api/product-barcodes': ['product_barcodes'],
    '/api/product-units': ['product_units'],
    '/api/products': ['products'],
    '/api/purchase-orders': ['purchase_orders'],
    '/api/purchases': ['purchase_invoices'],
    '/api/quotations': ['quotations'],
    '/api/receipts': ['safe_transactions'],
    '/api/regions': ['regions'],
    '/api/role_permissions': ['role_permissions'],
    '/api/roles': ['roles'],
    '/api/safes': ['safes'],
    '/api/sales': ['sales_invoices'],
    '/api/sales-orders': ['sales_orders'],
    '/api/settings': ['settings'],
    '/api/stock-movements': ['stock_movements'],
    '/api/units': ['units'],
    '/api/user-branch-access': ['user_branch_access'],
    '/api/user-region-access': ['user_region_access'],
    '/api/user-warehouse-access': ['user_warehouse_access'],
    '/api/users': ['users'],
    '/api/vouchers': ['safe_transactions'],
    '/api/warehouses': ['warehouses'],
  };

  /// أطول بادئةٍ تطابق [path]، أو null.
  static List<String>? tablesFor(String path) {
    String? best;
    for (final p in tablesByPrefix.keys) {
      if (path.startsWith(p) && (best == null || p.length > best.length)) {
        best = p;
      }
    }
    return best == null ? null : tablesByPrefix[best];
  }

  /// يرجع null إن سُمح بالقراءة، وإلا رسالة السبب (للـ403).
  static Future<String?> check(WebSessionClaims claims, String path) async {
    final tables = tablesFor(path);
    if (tables == null) return 'Path not readable with a web session';
    final codes = await WebSessionGuard.codesOf(claims.userId);
    if (codes == null) return 'User not allowed';
    final allowed = WebTablePolicy.allowedTables(codes);
    return tables.every(allowed.contains) ? null : 'Permission denied';
  }
}
