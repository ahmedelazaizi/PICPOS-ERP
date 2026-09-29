/// Raw-table names introduced by manufacturing schema v180.
///
/// Kept as a shared constant so the API pull allowlist and sync services cannot
/// drift while the API handler remains under its CI size threshold.
const manufacturingV180SyncTables = <String>{
  'butchery_templates',
  'butchery_template_lines',
  'butchery_orders',
  'butchery_order_lines',
};

/// Manufacturing tables that carry transactional documents and require a
/// verified session before delta pull.
const manufacturingV180TransactionalTables = <String>{
  'manufacturing_orders',
  'mfg_order_costs',
  'butchery_orders',
  'butchery_order_lines',
};
