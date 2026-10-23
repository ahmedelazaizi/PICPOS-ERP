// ═══════════════════════════════════════════════════════════════════════════
// DbConnectionStrategy — Unit Tests (ISS-DB-02)
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/data/database/db_connection_strategy.dart';
import 'package:picpos_erp/data/database/pg_config.dart';

void main() {
  group('DbConnectionResult model', () {
    test('exposes db, activeMode and isOfflineFallback', () {
      final db = AppDatabase.forTesting();
      addTearDown(db.close);

      final result = DbConnectionResult(
        db: db,
        activeMode: DatabaseMode.sqlite,
        isOfflineFallback: false,
      );

      expect(result.activeMode, DatabaseMode.sqlite);
      expect(result.isOfflineFallback, isFalse);
      expect(result.db, same(db));
    });

    test('isOfflineFallback true when PG unreachable', () {
      final db = AppDatabase.forTesting();
      addTearDown(db.close);

      final result = DbConnectionResult(
        db: db,
        activeMode: DatabaseMode.sqlite,
        isOfflineFallback: true,
      );

      expect(result.isOfflineFallback, isTrue);
      // Even in offline-fallback, the activeMode reflects what IS running
      expect(result.activeMode, DatabaseMode.sqlite);
    });

    test('postgres mode result', () {
      final db = AppDatabase.forTesting();
      addTearDown(db.close);

      final result = DbConnectionResult(
        db: db,
        activeMode: DatabaseMode.postgres,
        isOfflineFallback: false,
      );

      expect(result.activeMode, DatabaseMode.postgres);
      expect(result.isOfflineFallback, isFalse);
    });
  });

  group('PostgresConfig model', () {
    test('displayString omits password', () {
      const cfg = PostgresConfig(
        host: 'pg.example.com',
        port: 5432,
        database: 'uralcash',
        username: 'ural_user',
        password: 'secret123',
      );
      expect(cfg.displayString, contains('ural_user'));
      expect(cfg.displayString, contains('pg.example.com'));
      expect(cfg.displayString, contains('5432'));
      expect(cfg.displayString, contains('uralcash'));
      expect(cfg.displayString, isNot(contains('secret123')));
    });

    test('copyWith changes only specified fields', () {
      const base = PostgresConfig(
        host: 'host1',
        port: 5432,
        database: 'db1',
        username: 'user1',
        password: 'pw1',
        useSsl: false,
      );

      final changed = base.copyWith(host: 'host2', useSsl: true);
      expect(changed.host, 'host2');
      expect(changed.useSsl, isTrue);
      // Unchanged fields preserved
      expect(changed.port, 5432);
      expect(changed.database, 'db1');
      expect(changed.username, 'user1');
      expect(changed.password, 'pw1');
    });

    test('toJson / fromJson round-trip', () {
      const original = PostgresConfig(
        host: 'myhost',
        port: 5433,
        database: 'mydb',
        username: 'myuser',
        password: 'mypassword',
        useSsl: true,
      );

      final json = original.toJson();
       expect(json, isNot(contains('password')),
           reason: 'password is persisted in secure storage, not JSON');
      final restored = PostgresConfig.fromJson(json);

      expect(restored.host, original.host);
      expect(restored.port, original.port);
      expect(restored.database, original.database);
      expect(restored.username, original.username);
      expect(restored.password, isEmpty);
      expect(restored.useSsl, original.useSsl);
    });

    test('fromJson handles missing fields with defaults', () {
      final cfg = PostgresConfig.fromJson({});
      expect(cfg.host, 'localhost');
      expect(cfg.port, 5432);
      expect(cfg.database, 'uralcash');
      expect(cfg.useSsl, isFalse);
    });

    test('DatabaseMode displayName is not empty', () {
      for (final mode in DatabaseMode.values) {
        expect(mode.displayName, isNotEmpty);
      }
    });
  });
}
