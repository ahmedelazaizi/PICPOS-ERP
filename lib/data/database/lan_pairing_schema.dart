part of 'database.dart';

/// Raw SQL schema for LAN pairing. It deliberately stays outside Drift's table
/// model so pairing changes do not require a long code-generation run.
extension LanPairingSchema on AppDatabase {
  Future<void> ensureLanPairingSchema() async {
    await customStatement('''
      CREATE TABLE IF NOT EXISTS lan_paired_devices (
        device_id TEXT PRIMARY KEY,
        name TEXT NOT NULL DEFAULT '',
        paired_at INTEGER,
        last_seen_at INTEGER,
        last_seen_ip TEXT,
        revoked INTEGER NOT NULL DEFAULT 0,
        legacy_seen INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_lan_paired_devices_seen '
      'ON lan_paired_devices(last_seen_at)',
    );
  }
}
