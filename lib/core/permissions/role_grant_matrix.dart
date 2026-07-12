// Spec 078 — Role-Permission default-grant matrix.
//
// Mirrors the role-permission seed in database_seeder_permissions.dart
// (seedRolesAndPermissions). Re-declared here as a typed, immutable
// constant so:
//   1. The pre-flight check (RoleGrantPreflightService) has a single
//      source of truth to diff against without going through the
//      seeder's imperative INSERT loops.
//   2. The Settings UI can display "this role normally has X perms"
//      to operators without re-running the seeder.
//
// Source of truth contract:
// - Fresh installs: the seeder's role-grant loops (lines ~693-880 of
//   database_seeder_permissions.dart) are authoritative.
// - Existing installs after upgrade: this matrix tells the operator
//   which perms SHOULD have been granted but weren't (because the
//   seeder only runs on fresh install). The UI's "grant defaults"
//   button INSERT-OR-IGNOREs from this matrix.
//
// **Drift detector**: a unit test (role_grant_matrix_test.dart) reads
// the seeder source and asserts each role's list matches the matrix
// below — change the seeder, this test fails until you mirror the
// change here. Prevents silent divergence between the two declarations.
//
// **Admin role**: gets a catch-all in the seeder (every perm except
// `criticalFinancialOps`) AND syncAllPermissions auto-grants new
// perms to admin on every server-mode boot. So in theory admin
// never needs an entry here.
//
// **In practice** (Spec 086, field 2026-05-19): on at least one
// production server the auto-grant in `syncAllPermissions` silently
// missed `branches_manage`, `pos_shift_open`, `pos_shift_close` —
// admin hit 403 on shift open/close and branch insert through the
// mirror. Root cause undetermined (raw SQL `ON CONFLICT DO NOTHING`
// against composite PK + per-row try blocks make individual failures
// invisible). Adding a minimal safety-net entry below makes the
// matrix-based self-heal (`grantMissingDefaults`) treat admin like
// any other role for THESE specific codes — defense in depth.

class RoleGrantMatrix {
  RoleGrantMatrix._();

  /// Role name (Arabic, as inserted by the seeder) → set of perm
  /// codes that role SHOULD have for default operation.
  ///
  /// "Should have" means: without these, the user in that role will
  /// hit 403 on common server endpoints once Spec 077's flag is ON.
  static const Map<String, Set<String>> defaultGrants = {
    // Spec 086 — safety net for admin essentials. NOT a full admin
    // perm list (the seeder + syncAllPermissions catch-all are still
    // authoritative for the complete set). These are the codes that
    // field smoke (2026-05-19, mirror V148) caught silently missing
    // and that block core POS / branch flows when absent.
    'مدير النظام': {
      'branches_manage',
      'pos_shift_open',
      'pos_shift_close',
    },
    'كاشير': {
      'pos_access',
      'pos_hold_order',
      'pos_save',
      'pos_print',
      'pos_shift_open',
      'pos_shift_close',
      // Spec 084 — Spec 077 gates `/api/sales` POST on `sales_create`.
      // Without it the entire POS path dies (4× DEAD-LETTER per session).
      // `sales_view` lets the cashier list their previous invoices.
      'sales_create',
      'sales_view',
    },
    'مخزني': {
      'inventory_view',
      'inventory_edit',
      'products_view',
      'products_add',
      'products_edit',
      'suppliers_view',
      'purchases_create',
      'categories_view',
    },
    'محاسب': {
      'reports_view',
      'reports_export',
      'treasury_view',
      'customers_view',
      'suppliers_view',
      'sales_view',
      'purchases_view',
      'dashboard_access',
    },
    'مدير مالي': {
      // Inherits the full accountant set
      'reports_view',
      'reports_export',
      'treasury_view',
      'customers_view',
      'suppliers_view',
      'sales_view',
      'purchases_view',
      'dashboard_access',
      // FM-only extras (Spec 077 Batch 0.5)
      'commercial_papers_manage',
    },
    'كاشير متقدم': {
      'pos_access',
      'pos_discount',
      'pos_return',
      'pos_payment_cash',
      'pos_payment_card',
      'pos_hold_order',
      'customers_view',
      'pos_shift_open',
      'pos_shift_close',
      // Spec 084 — same gap as basic cashier.
      'sales_create',
      'sales_view',
    },
    'مدير فرع': {
      // Inherits advanced cashier
      'pos_access',
      'pos_discount',
      'pos_return',
      'pos_payment_cash',
      'pos_payment_card',
      'pos_hold_order',
      'customers_view',
      'pos_shift_open',
      'pos_shift_close',
      // Spec 084 — branch manager must be able to ring sales too.
      'sales_create',
      // Plus branch-manager extras
      'inventory_view',
      'reports_view',
      'treasury_view',
      'pos_closing_view_details',
      'products_add',
      'branches_manage',
      'users_manage',
      'sales_view',
      'purchases_create',
      'settings_view',
    },
    'محاسب متقدم': {
      'treasury_view',
      'reports_view',
      'settings_view',
      'pos_closing_view_details',
      'sales_view',
      'purchases_create',
      'inventory_view',
      'analytics_view',
    },
    'مدير مخزون': {
      'inventory_view',
      'inventory_transfer',
      'products_add',
      'purchases_create',
      'reports_view',
      'sales_view',
    },
  };

  /// Roles in the matrix — for quick membership check.
  /// Custom roles created by operators won't appear here and are
  /// considered "not managed by the matrix" — the pre-flight check
  /// surfaces them with a "manual grant required" note instead of
  /// auto-granting.
  static Set<String> get knownRoleNames => defaultGrants.keys.toSet();
}
