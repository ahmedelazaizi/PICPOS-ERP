// customUpdate/customStatement بعلامات `?` على PostgreSQL: يجب أن تُحوَّل إلى
// `$n` في كل مسار (خارج المعاملة وداخلها)، وإلا يرد 42601 من الخادم.

@Tags(['pg'])
library;

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';

import '_support/pg_fixture.dart';

void main() {
  group('customUpdate بـ ? على PostgreSQL', () {
    late PgTestFixture fx;
    late AppDatabase db;

    setUpAll(() async {
      fx = await bootPgTestSchema();
      db = fx.db;
      await db.customSelect('SELECT 1').get();
    });

    tearDownAll(() async => fx.tearDown());

    Future<int> seedStock() async {
      await db.customStatement(
        'INSERT INTO warehouses (id, name) VALUES (9001, ?) '
        'ON CONFLICT DO NOTHING',
        ['W-probe'],
      );
      await db.customStatement(
        'INSERT INTO products (id, code, name) VALUES (9001, ?, ?) '
        'ON CONFLICT DO NOTHING',
        ['P-probe', 'P-probe'],
      );
      await db.customStatement(
        'INSERT INTO inventory_balances (product_id, warehouse_id, quantity, '
        'reserved_quantity) VALUES (9001, 9001, 5, 0) '
        'ON CONFLICT DO NOTHING',
        [],
      );
      return 9001;
    }

    test('syncDefaultBinStock مرتين (INSERT ثم UPDATE)', () async {
      final id = await seedStock();
      await db.syncDefaultBinStock(id, id);
      await db.syncDefaultBinStock(id, id);
      final r = await db.customSelect(
        'SELECT quantity FROM location_stock WHERE product_id = ?',
        variables: [Variable<int>(id)],
      ).get();
      expect(r, isNotEmpty);
    });

    test('syncDefaultBinStock داخل transaction', () async {
      final id = await seedStock();
      await db.transaction(() async {
        await db.syncDefaultBinStock(id, id);
        await db.syncDefaultBinStock(id, id);
      });
    });

    test('customUpdate مباشرة', () async {
      await db.customStatement(
        'INSERT INTO settings (key, value) VALUES (?, ?) '
        'ON CONFLICT DO NOTHING',
        ['probe_k', 'a'],
      );
      final n = await db.customUpdate(
        'UPDATE settings SET value = ? WHERE key = ?',
        variables: const [Variable<String>('b'), Variable<String>('probe_k')],
      );
      expect(n, 1);
    });

    test('customUpdate داخل transaction', () async {
      final n = await db.transaction(() => db.customUpdate(
            'UPDATE settings SET value = ? WHERE key = ?',
            variables: const [Variable<String>('c'), Variable<String>('probe_k')],
          ));
      expect(n, 1);
    });

    // السبب الجذري: ما يعمل داخل beforeOpen يتخطّى _PgCompatInterceptor،
    // فالترجمة عند المصدر في AppDatabase هي الوحيدة التي تحميه. نحاكي ذلك
    // بمنفّذ PG خام بلا مُعترِض.
    group('بلا مُعترِض (نموذج beforeOpen)', () {
      late AppDatabase raw;
      setUpAll(() async {
        raw = openUninterceptedPgDatabase();
        await raw.customSelect('SELECT 1').get();
      });
      tearDownAll(() async => raw.close());

      test('customUpdate', () async {
        final n = await raw.customUpdate(
          'UPDATE settings SET value = ? WHERE key = ?',
          variables: const [Variable<String>('d'), Variable<String>('probe_k')],
        );
        expect(n, 1);
      });

      test('customUpdate داخل transaction', () async {
        final n = await raw.transaction(() => raw.customUpdate(
              'UPDATE settings SET value = ? WHERE key = ?',
              variables: const [Variable<String>('e'), Variable<String>('probe_k')],
            ));
        expect(n, 1);
      });

      test('customInsert', () async {
        final id = await raw.customInsert(
          'INSERT INTO settings (key, value) VALUES (?, ?) '
          'ON CONFLICT DO NOTHING',
          variables: const [Variable<String>('probe_i'), Variable<String>('x')],
        );
        expect(id, isNotNull);
      });

      test('customWriteReturning', () async {
        final rows = await raw.customWriteReturning(
          'UPDATE settings SET value = ? WHERE key = ? RETURNING key',
          variables: const [Variable<String>('f'), Variable<String>('probe_k')],
        );
        expect(rows, hasLength(1));
      });

      test('syncDefaultBinStock مرتين', () async {
        final id = await seedStock();
        await raw.syncDefaultBinStock(id, id);
        await raw.syncDefaultBinStock(id, id);
      });
    });
  });
}
