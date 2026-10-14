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
        legacy_seen INTEGER NOT NULL DEFAULT 0,
        device_kind TEXT,
        branch_id INTEGER,
        terminal_code TEXT
      )
    ''');
    for (final column in const [
      'device_kind TEXT',
      'branch_id INTEGER',
      'terminal_code TEXT',
    ]) {
      await _ensureLanPairingColumn(column);
    }
    await customStatement('''
      CREATE TABLE IF NOT EXISTS lan_branch_terminal_codes (
        branch_id INTEGER NOT NULL,
        terminal_code TEXT NOT NULL,
        device_id TEXT NOT NULL,
        assigned_at INTEGER NOT NULL,
        PRIMARY KEY (branch_id, terminal_code)
      )
    ''');
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_lan_paired_devices_seen '
      'ON lan_paired_devices(last_seen_at)',
    );
  }

  Future<void> _ensureLanPairingColumn(String column) async {
    final name = column.split(' ').first;
    if (_isPostgres) {
      await customStatement(
        'ALTER TABLE lan_paired_devices ADD COLUMN IF NOT EXISTS $column',
      );
      return;
    }
    final columns = await customSelect(
      'PRAGMA table_info(lan_paired_devices)',
    ).get();
    if (columns.any((row) => row.data['name'] == name)) return;
    await customStatement('ALTER TABLE lan_paired_devices ADD COLUMN $column');
  }
}
