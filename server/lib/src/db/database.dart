import 'package:postgres/postgres.dart';

import 'migrations.dart';

/// Thin wrapper over a postgres [Pool]. All queries are parameterized
/// (`Sql.named`) — no SQL string interpolation of values.
class CloudDatabase {
  CloudDatabase._(this.pool, this.schema);

  final Pool pool;

  /// Optional schema (used by tests to isolate runs inside one database).
  final String? schema;

  static Future<CloudDatabase> open({
    required String host,
    required int port,
    required String database,
    required String username,
    required String password,
    String? schema,
    bool ssl = false,
    int maxConnections = 8,
  }) async {
    if (schema != null && !RegExp(r'^[a-z_][a-z0-9_]*$').hasMatch(schema)) {
      throw ArgumentError('invalid schema name');
    }
    final pool = Pool.withEndpoints(
      [
        Endpoint(
          host: host,
          port: port,
          database: database,
          username: username,
          password: password,
        ),
      ],
      settings: PoolSettings(
        maxConnectionCount: maxConnections,
        sslMode: ssl ? SslMode.require : SslMode.disable,
        onOpen: schema == null
            ? null
            : (c) async {
                await c.execute('CREATE SCHEMA IF NOT EXISTS $schema');
                await c.execute('SET search_path TO $schema');
              },
      ),
    );
    return CloudDatabase._(pool, schema);
  }

  Future<Result> q(Session s, String sql, [Map<String, Object?>? params]) =>
      s.execute(Sql.named(sql), parameters: params ?? const {});

  Future<Result> query(String sql, [Map<String, Object?>? params]) =>
      pool.execute(Sql.named(sql), parameters: params ?? const {});

  Future<R> tx<R>(Future<R> Function(TxSession s) fn) => pool.runTx(fn);

  /// Applies pending [kMigrations] in order. Safe to call on every start.
  Future<void> migrate() async {
    await pool.runTx((s) async {
      // Serialize concurrent starters.
      await s.execute('SELECT pg_advisory_xact_lock(424242)');
      await s.execute('CREATE TABLE IF NOT EXISTS schema_migrations '
          '(version INT PRIMARY KEY, name TEXT NOT NULL, applied_at BIGINT NOT NULL)');
      final done = (await s.execute('SELECT version FROM schema_migrations'))
          .map((r) => r[0] as int)
          .toSet();
      for (final m in kMigrations) {
        if (done.contains(m.version)) continue;
        await s.execute(m.sql, queryMode: QueryMode.simple);
        await s.execute(
          Sql.named('INSERT INTO schema_migrations VALUES (@v, @n, @t)'),
          parameters: {
            'v': m.version,
            'n': m.name,
            't': DateTime.now().millisecondsSinceEpoch,
          },
        );
      }
    });
  }

  /// Test helper: drops the isolated schema.
  Future<void> dropSchema() async {
    if (schema == null) return;
    await pool.execute('DROP SCHEMA IF EXISTS $schema CASCADE');
  }

  Future<void> close() => pool.close();
}

/// Postgres NUMERIC comes back as String in postgres 3.x.
double num0(Object? v) {
  if (v == null) return 0;
  if (v is num) return v.toDouble();
  return double.parse(v.toString());
}
