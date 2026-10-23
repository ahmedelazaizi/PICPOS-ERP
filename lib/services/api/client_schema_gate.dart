/// SYNC-001 (audit 2026-10-23) — host-side client-schema handshake.
///
/// Clients announce their local DB schema version in `X-Client-Schema`
/// (stamped by `ServerProxy` / `SyncService`). The host uses it to
///  * refuse clients older than [minSupported] (HTTP 426), so they keep their
///    watermark instead of silently losing rows; and
///  * strip columns added after the client's schema from delta-pull rows
///    ([columnsToStrip]), so an older client's `INSERT OR REPLACE` doesn't fail
///    with "no such column" and drop the whole row.
///
/// A client that sends no header is a pre-handshake build (v195 and older):
/// it is treated as [legacySchema].
class ClientSchemaGate {
  ClientSchemaGate._();

  static const String headerName = 'x-client-schema';

  /// Schema assumed for clients that predate the handshake (3.9.1 = v195).
  static const int legacySchema = 195;

  /// Oldest client schema the host still serves safely.
  static const int minSupported = 195;

  /// The local DB schema of THIS app, set once at client startup (the client
  /// stamps it on every request; null on a pure host ⇒ no header).
  static int? clientSchemaVersion;

  /// Columns introduced by each schema version, per table. Add an entry
  /// whenever a migration adds a column to a SYNCED table.
  static const Map<int, Map<String, Set<String>>> columnsAddedAt = {
    196: {
      'table_reservations': {'party_id'},
    },
  };

  static int parse(String? header) =>
      int.tryParse((header ?? '').trim()) ?? legacySchema;

  static bool isTooOld(int clientSchema) => clientSchema < minSupported;

  /// Columns of [table] the client (at [clientSchema]) does not have yet.
  static Set<String> columnsToStrip(String table, int clientSchema) => {
        for (final e in columnsAddedAt.entries)
          if (e.key > clientSchema) ...?e.value[table],
      };
}
