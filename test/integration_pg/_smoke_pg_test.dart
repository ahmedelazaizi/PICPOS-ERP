// Spec 029 / US1 — smoke test for the Postgres integration runner.
//
// Confirms `bootPgTestSchema()` returns an `AppDatabase` with a usable
// connection. The fixture wipes the public schema before opening Drift;
// after Drift's migration runs, the standard tables exist and a trivial
// SELECT against `users` returns an empty result.
//
// This is the runner's own self-test — if it fails, every other
// `*_pg_test.dart` will fail too. Keep it tiny so the failure mode is
// unambiguous.

@Tags(['pg'])
library;

import 'package:flutter_test/flutter_test.dart';

import '_support/pg_fixture.dart';

void main() {
  late PgTestFixture fx;

  setUpAll(() async {
    fx = await bootPgTestSchema();
  });

  tearDownAll(() async {
    await fx.tearDown();
  });

  group('Postgres runner smoke', () {
    test('Drift opened the AppDatabase against the test Postgres', () async {
      final result = await fx.db.customSelect('SELECT 1 AS n').get();
      expect(result, hasLength(1));
      expect(result.first.data['n'], equals(1));
    });

    test('users table is queryable (proves Drift migration ran)', () async {
      final users = await fx.db.select(fx.db.users).get();
      expect(users, isEmpty);
    });

    test('shifts table is queryable (US3 Bug B prerequisite)', () async {
      final shifts = await fx.db.select(fx.db.shifts).get();
      expect(shifts, isEmpty);
    });
  });
}
