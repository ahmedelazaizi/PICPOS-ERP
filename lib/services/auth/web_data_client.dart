import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_auth_service.dart';

/// Thin, typed façade over [SupabaseClient] for the web platform.
///
/// Why this exists:
/// - The existing `IProductRepository` / `ICustomerRepository` interfaces are
///   tightly coupled to Drift row types (int PKs, Drift companions). Plugging
///   Supabase UUID rows through them requires a large refactor of both the
///   domain entities AND every caller — planned for Session 3B.
/// - In the meantime, this client gives web UI code a consistent, typed
///   entry point for Supabase CRUD on the core tables.
/// - All methods implicitly scope to the caller's tenant because RLS is
///   enforced server-side — callers do NOT need to pass tenantId.
class WebDataClient {
  WebDataClient._();
  static final instance = WebDataClient._();

  SupabaseClient get _c => Supabase.instance.client;

  /// Asserts the user is signed in; call at the start of every public method.
  void _requireSignedIn() {
    if (SupabaseAuthService.instance.currentUser == null) {
      throw StateError('WebDataClient: not signed in.');
    }
  }

  // ── products ────────────────────────────────────────────────────────────
  Future<List<Map<String, dynamic>>> listProducts({
    int limit = 50,
    int offset = 0,
    String? search,
    String? categoryId,
  }) async {
    _requireSignedIn();
    var q = _c
        .from('products')
        .select()
        .filter('deleted_at', 'is', null)
        .eq('is_active', true);
    if (search != null && search.isNotEmpty) {
      q = q.ilike('name', '%$search%');
    }
    if (categoryId != null) {
      q = q.eq('category_id', categoryId);
    }
    final rows = await q.order('name').range(offset, offset + limit - 1);
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<Map<String, dynamic>?> getProductById(String id) async {
    _requireSignedIn();
    final row =
        await _c.from('products').select().eq('id', id).maybeSingle();
    return row;
  }

  Future<Map<String, dynamic>> insertProduct(
      Map<String, dynamic> values) async {
    _requireSignedIn();
    final profile = SupabaseAuthService.instance.profile!;
    final payload = {...values, 'tenant_id': profile.tenantId};
    final row =
        await _c.from('products').insert(payload).select().single();
    return row;
  }

  Future<Map<String, dynamic>> updateProduct(
      String id, Map<String, dynamic> values) async {
    _requireSignedIn();
    final row = await _c
        .from('products')
        .update(values)
        .eq('id', id)
        .select()
        .single();
    return row;
  }

  Future<void> softDeleteProduct(String id) async {
    _requireSignedIn();
    await _c
        .from('products')
        .update({'deleted_at': DateTime.now().toUtc().toIso8601String()})
        .eq('id', id);
  }

  // ── categories ──────────────────────────────────────────────────────────
  Future<List<Map<String, dynamic>>> listCategories() async {
    _requireSignedIn();
    final rows = await _c
        .from('categories')
        .select()
        .filter('deleted_at', 'is', null)
        .order('sort_order');
    return List<Map<String, dynamic>>.from(rows);
  }

  // ── customers / suppliers ───────────────────────────────────────────────
  Future<List<Map<String, dynamic>>> listCustomers({
    int limit = 50,
    int offset = 0,
    String? search,
  }) async {
    _requireSignedIn();
    var q = _c.from('customers').select().filter('deleted_at', 'is', null);
    if (search != null && search.isNotEmpty) {
      q = q.or('name.ilike.%$search%,phone.ilike.%$search%');
    }
    final rows = await q.order('name').range(offset, offset + limit - 1);
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<List<Map<String, dynamic>>> listSuppliers({
    int limit = 50,
    int offset = 0,
  }) async {
    _requireSignedIn();
    final rows = await _c
        .from('suppliers')
        .select()
        .filter('deleted_at', 'is', null)
        .order('name')
        .range(offset, offset + limit - 1);
    return List<Map<String, dynamic>>.from(rows);
  }

  // ── branches / warehouses ───────────────────────────────────────────────
  Future<List<Map<String, dynamic>>> listBranches() async {
    _requireSignedIn();
    final rows = await _c
        .from('branches')
        .select()
        .filter('deleted_at', 'is', null)
        .order('name');
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<List<Map<String, dynamic>>> listWarehouses({String? branchId}) async {
    _requireSignedIn();
    var q = _c.from('warehouses').select().filter('deleted_at', 'is', null);
    if (branchId != null) {
      q = q.eq('branch_id', branchId);
    }
    final rows = await q.order('name');
    return List<Map<String, dynamic>>.from(rows);
  }
}
