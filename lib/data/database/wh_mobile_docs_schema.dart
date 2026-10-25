// Warehouse-phone document store (plan 2026-10-23 ADR-W5): three raw-SQL
// tables, deliberately OUTSIDE Drift's table model (like lan_pairing_schema
// and warehouse_locations_schema) so no build_runner regeneration of
// database.g.dart and no schemaVersion bump is needed.
//
//   wh_mobile_docs        the document header + state machine
//   wh_mobile_doc_lines   its lines (unique client-generated line id)
//   wh_mobile_doc_events  command log == idempotency ledger (unique command id)
//
// Creation is lazy and idempotent (`CREATE ... IF NOT EXISTS`): every
// document write calls [ensureWhMobileDocsSchema] first, which runs the DDL at
// most once per database instance. Not synchronised to client desktops: the
// documents live on the main (server) desktop that owns the phones.
import 'database.dart';

final Expando<Future<void>> _ensured = Expando('wh_mobile_docs_schema');

extension WhMobileDocsSchema on AppDatabase {
  Future<void> ensureWhMobileDocsSchema() => _ensured[this] ??= _create();

  Future<void> _create() async {
    final pg = isPostgres;
    final pk = pg ? 'SERIAL PRIMARY KEY' : 'INTEGER PRIMARY KEY AUTOINCREMENT';
    final real = pg ? 'DOUBLE PRECISION' : 'REAL';
    final big = pg ? 'BIGINT' : 'INTEGER';
    final ddl = <String>[
      '''CREATE TABLE IF NOT EXISTS wh_mobile_docs (
        id $pk, global_id TEXT NOT NULL UNIQUE, kind TEXT NOT NULL,
        state TEXT NOT NULL, warehouse_id INTEGER NOT NULL,
        to_warehouse_id INTEGER, ref_type TEXT, ref_id TEXT, reason TEXT,
        created_by INTEGER NOT NULL, device_id TEXT,
        approved_by INTEGER, approved_at $big,
        posted_ref_type TEXT, posted_ref_id TEXT,
        row_version INTEGER NOT NULL DEFAULT 0,
        created_at $big NOT NULL, updated_at $big NOT NULL, data_json TEXT)''',
      '''CREATE TABLE IF NOT EXISTS wh_mobile_doc_lines (
        id $pk, doc_id INTEGER NOT NULL REFERENCES wh_mobile_docs(id),
        line_global_id TEXT NOT NULL UNIQUE, product_id INTEGER NOT NULL,
        qty_base $real NOT NULL, location_id INTEGER, batch_number TEXT,
        expiry_date $big, condition TEXT NOT NULL DEFAULT 'ok',
        po_item_id INTEGER, pass INTEGER NOT NULL DEFAULT 1,
        observed_at $big NOT NULL, counter_user_id INTEGER,
        unit_cost $real, extra_json TEXT)''',
      '''CREATE TABLE IF NOT EXISTS wh_mobile_doc_events (
        id $pk, command_id TEXT NOT NULL UNIQUE, doc_id INTEGER,
        action TEXT NOT NULL, actor_user_id INTEGER NOT NULL, device_id TEXT,
        payload_hash TEXT NOT NULL, result_json TEXT, at $big NOT NULL)''',
      'CREATE INDEX IF NOT EXISTS idx_wh_docs_kind_state ON wh_mobile_docs(kind, state, warehouse_id)',
      'CREATE INDEX IF NOT EXISTS idx_wh_docs_ref ON wh_mobile_docs(ref_type, ref_id)',
      'CREATE INDEX IF NOT EXISTS idx_wh_lines_doc ON wh_mobile_doc_lines(doc_id)',
      'CREATE INDEX IF NOT EXISTS idx_wh_events_doc ON wh_mobile_doc_events(doc_id)',
    ];
    for (final sql in ddl) {
      await customStatement(sql);
    }
  }
}
