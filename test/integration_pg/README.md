# Postgres Integration Test Suite

**Spec**: 029 — Sync Regression Hardening (US1)
**Status**: opt-in. Default `flutter test` does NOT pick these up.

This directory contains tests that need a real PostgreSQL server. They are
the runtime safety net for regressions that a static grep test cannot catch
— Feature 011 / Issue 9 (admin id=1 dropped from `/api/users` despite the
source containing `u.id.equals(1)`) is the canonical example.

## How to run

```bash
melos test:pg
# or directly:
dart run scripts/run_pg_tests.dart
```

The orchestrator:

1. Detects `docker` on PATH; exits non-zero with an actionable message if
   missing (FR-005).
2. Spawns `postgres:16-alpine` on a free host port.
3. Polls `pg_isready` (or a TCP probe) up to 30 seconds.
4. Sets env `PG_TEST_DSN=postgres://postgres:postgres@localhost:<port>/postgres`.
5. Runs `flutter test test/integration_pg/ --tags pg --run-skipped --concurrency=1`.
6. Tears down the container in `try/finally` regardless of test outcome.

The historical total wall-time goal is under 90 seconds (SC-001). It remains
unmet: the latest full run passed 83 tests with exit code 0 in 1,592 seconds
(about 26m32s). Serial concurrency (`--concurrency=1`) remains intentional
because the fixture resets the shared `public` schema between test files.

## How a test file is wired

```dart
@Tags(['pg'])

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

  test('description', () async {
    // use fx.db just like AppDatabase in any other test
  });
}
```

The fixture wipes the `public` schema before opening Drift, so each test
file starts clean. Tests within a single file share the schema and should
truncate any tables they pollute in `setUp`.

## Adding a new PG test

1. Create `test/integration_pg/<area>_pg_test.dart`.
2. Top of file: `@Tags(['pg'])`.
3. Use `bootPgTestSchema()` as shown above.
4. Run via `melos test:pg`.

The `pg` tag (declared in `dart_test.yaml`) is what keeps default
`flutter test` from picking up these files. Do NOT remove the tag.

## CI integration (deferred)

Per [research.md](../../specs/029-sync-regression-hardening/research.md) §R10,
wiring the runner into a hosted CI (GitHub Actions etc.) is a separate
spec. The contract documented here (`melos test:pg` + opt-in tag) is
ready for whoever picks that work up.

## Why a real Postgres, not in-memory SQLite?

The production server uses PostgreSQL via `drift_postgres`. Two regression
classes only surface there:

- Driver quirks (`drift_postgres` companion-value handling, `strftime`
  compatibility) live in `lib/data/database/connection_io.dart` and
  `pg_compat_sql.dart`. SQLite-backed tests bypass all of it.
- Server-side handlers (`api_handler.dart`, `api_data_handler.dart`,
  `api_purchase_handler.dart`) run against the production driver in real
  installs. A mock or SQLite stub gives false confidence.

Static grep tests (`test/unit/orchestrator_gate_predicate_test.dart`,
`test/unit/mode_equality_guard_test.dart`) catch source-shape regressions
at PR time. PG tests catch *behavior* regressions that source-shape can't
see.

The two complementary layers together are what closed the production
incident this feature was triggered by.
