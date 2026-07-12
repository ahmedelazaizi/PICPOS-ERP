// ═══════════════════════════════════════════════════════════════════════════
// PgCompatSql — unit tests for every SQL transformation
// ═══════════════════════════════════════════════════════════════════════════
//
// These tests exercise the actual regex patterns in PgCompatSql.fixSql().
// They serve as the contract for "this is what the PostgreSQL interceptor
// guarantees" and catch regressions when DAOs add new raw SQL.

import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/pg_compat_sql.dart';

void main() {
  // ─────────────────────────────────────────────────────────────────────────
  group('PgCompatSql.fixSql — strftime', () {
    // ─────────────────────────────────────────────────────────────────────
    test("strftime('%s','now') → EXTRACT(EPOCH FROM NOW())::bigint", () {
      const input = "CAST(strftime('%s','now') AS INTEGER)";
      final out = PgCompatSql.fixSql(input);
      expect(out, contains('EXTRACT(EPOCH FROM NOW())::bigint'));
      expect(out, isNot(contains('strftime')));
    });

    test("strftime('%s', 'now') with spaces → replaced", () {
      const input = "DEFAULT strftime('%s', 'now')";
      final out = PgCompatSql.fixSql(input);
      expect(out, contains('EXTRACT(EPOCH FROM NOW())::bigint'));
    });

    test("strftime('%H', expr/1000, 'unixepoch', 'localtime') → EXTRACT(HOUR)", () {
      const input =
          "CAST(strftime('%H', t.created_at / 1000, 'unixepoch', 'localtime') AS INTEGER)";
      final out = PgCompatSql.fixSql(input);
      expect(out, contains('EXTRACT(HOUR FROM to_timestamp(t.created_at / 1000))::int'));
      expect(out, isNot(contains('strftime')));
    });

    test('strftime inside SELECT clause is fully replaced', () {
      const input =
          "SELECT id, strftime('%s','now') as ts FROM foo WHERE strftime('%s','now') > ?";
      final out = PgCompatSql.fixSql(input);
      expect(out, isNot(contains('strftime')));
      expect(out.split('EXTRACT').length - 1, equals(2),
          reason: 'Both occurrences replaced');
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  group('PgCompatSql.fixSql — datetime', () {
    // ─────────────────────────────────────────────────────────────────────
    test("datetime('now') → NOW()", () {
      const input = "INSERT INTO t (created_at) VALUES (datetime('now'))";
      final out = PgCompatSql.fixSql(input);
      expect(out, contains("NOW()"));
      expect(out, isNot(contains("datetime('now')")));
    });

    test("DATETIME('NOW') case-insensitive → NOW()", () {
      const input = "SET ts = DATETIME('NOW')";
      final out = PgCompatSql.fixSql(input);
      expect(out, contains("NOW()"));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  group('PgCompatSql.fixSql — julianday', () {
    // ─────────────────────────────────────────────────────────────────────
    test("julianday('now') → (EXTRACT(EPOCH FROM NOW()) / 86400.0)", () {
      const input = "julianday('now') - julianday(s.created_at / 1000, 'unixepoch')";
      final out = PgCompatSql.fixSql(input);
      expect(out, contains('(EXTRACT(EPOCH FROM NOW()) / 86400.0)'));
      expect(out, isNot(contains('julianday')));
    });

    test("julianday(expr/1000,'unixepoch') → ((expr) / 86400.0)", () {
      const input = "julianday(pi.invoice_date / 1000, 'unixepoch')";
      final out = PgCompatSql.fixSql(input);
      expect(out, equals("((pi.invoice_date / 1000) / 86400.0)"));
    });

    test("julianday(expr) simple → ((expr) / 86400.0)", () {
      const input = "julianday(woi.completed_at) - julianday(woi.started_at)";
      final out = PgCompatSql.fixSql(input);
      expect(out, equals("((woi.completed_at) / 86400.0) - ((woi.started_at) / 86400.0)"));
    });

    test('BETWEEN age-band query with julianday translates fully', () {
      const input = '''
        SUM(CASE WHEN (julianday('now') - julianday(s.created_at / 1000, 'unixepoch')) <= 30
            THEN amount ELSE 0 END) as current_amount''';
      final out = PgCompatSql.fixSql(input);
      expect(out, isNot(contains('julianday')));
      expect(out, contains('86400.0'));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  group('PgCompatSql.fixSql — INSTR → STRPOS', () {
    // Feature 005 — C.1: INSTR is SQLite-only. PostgreSQL rejects with
    // "function instr(text, unknown) does not exist". Translate to STRPOS,
    // which has identical 1-based / 0-not-found semantics on Postgres.
    // ─────────────────────────────────────────────────────────────────────
    test("INSTR(notes, '#') → STRPOS(notes, '#')", () {
      const input = "INSTR(notes, '#')";
      final out = PgCompatSql.fixSql(input);
      expect(out, equals("STRPOS(notes, '#')"));
    });

    test('lowercase instr also translated', () {
      const input = "instr(name, 'X')";
      final out = PgCompatSql.fixSql(input);
      expect(out, equalsIgnoringCase("STRPOS(name, 'X')"));
      expect(out.toLowerCase(), isNot(contains('instr(')));
    });

    test('INSTR nested inside SUBSTR is translated', () {
      const input = "SUBSTR(notes, INSTR(notes, '#') + 1)";
      final out = PgCompatSql.fixSql(input);
      expect(out, equals("SUBSTR(notes, STRPOS(notes, '#') + 1)"));
    });

    test('multiple INSTR calls all translated', () {
      const input =
          "SELECT INSTR(a, '#'), INSTR(b, '@') FROM t WHERE INSTR(c, '!') > 0";
      final out = PgCompatSql.fixSql(input);
      expect(out, isNot(contains('INSTR(')));
      expect(out.split('STRPOS(').length - 1, equals(3));
    });

    test('sales_dao return-orig-id pattern translates', () {
      // Real production SQL from sales_dao.dart:513
      const input =
          "SELECT CAST(SUBSTR(notes, INSTR(notes, '#') + 1) AS INTEGER) AS orig_id";
      final out = PgCompatSql.fixSql(input);
      expect(out, isNot(contains('INSTR')));
      expect(out, contains("STRPOS(notes, '#')"));
    });

    test('column named "instrument" is NOT touched (word boundary)', () {
      const input = "SELECT instrument FROM tools";
      final out = PgCompatSql.fixSql(input);
      expect(out, equals(input), reason: 'word-boundary protects identifiers');
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  group('PgCompatSql.fixSql — ? placeholder renaming', () {
    // ─────────────────────────────────────────────────────────────────────
    test('single ? → \$1', () {
      const input = 'SELECT * FROM t WHERE id = ?';
      final out = PgCompatSql.fixSql(input);
      expect(out, equals('SELECT * FROM t WHERE id = \$1'));
    });

    test('multiple ? → \$1, \$2, \$3 in order', () {
      const input = 'INSERT INTO t (a, b, c) VALUES (?, ?, ?)';
      final out = PgCompatSql.fixSql(input);
      expect(out, equals('INSERT INTO t (a, b, c) VALUES (\$1, \$2, \$3)'));
    });

    test('? inside string literals are NOT replaced', () {
      const input = "SELECT * FROM t WHERE note = '?' AND id = ?";
      final out = PgCompatSql.fixSql(input);
      expect(out, contains("'?'"), reason: 'literal ? unchanged');
      expect(out, contains('\$1'), reason: 'parametric ? renamed');
    });

    test('no ? → sql unchanged', () {
      const input = 'SELECT count(*) FROM t';
      expect(PgCompatSql.fixSql(input), equals(input));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  group('PgCompatSql.fixSql — idempotency', () {
    // ─────────────────────────────────────────────────────────────────────
    test('already-translated SQL is not double-translated', () {
      const alreadyPg =
          "SELECT EXTRACT(EPOCH FROM NOW())::bigint, (EXTRACT(EPOCH FROM NOW()) / 86400.0)";
      expect(PgCompatSql.fixSql(alreadyPg), equals(alreadyPg));
    });

    test('plain SQL with no SQLite idioms is passed through unchanged', () {
      const plain =
          "SELECT id, name FROM products WHERE is_active = TRUE ORDER BY name";
      expect(PgCompatSql.fixSql(plain), equals(plain));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  group('PgCompatSql.fixArgs — DateTime conversion', () {
    // ─────────────────────────────────────────────────────────────────────
    test('DateTime converted to epoch seconds integer', () {
      final dt = DateTime.fromMillisecondsSinceEpoch(1_000_000_000 * 1000);
      final result = PgCompatSql.fixArgs([dt]);
      expect(result, equals([1_000_000_000]));
    });

    test('non-DateTime args pass through unchanged', () {
      final args = [42, 'hello', 3.14, null, true];
      expect(PgCompatSql.fixArgs(args), equals(args));
    });

    test('mixed list: DateTimes converted, others unchanged', () {
      final dt = DateTime.fromMillisecondsSinceEpoch(1_700_000_000 * 1000);
      final result = PgCompatSql.fixArgs([1, dt, 'foo']);
      expect(result[0], equals(1));
      expect(result[1], equals(1_700_000_000));
      expect(result[2], equals('foo'));
    });

    test('empty list returns same empty list', () {
      final empty = <Object?>[];
      expect(PgCompatSql.fixArgs(empty), same(empty));
    });

    test('list with no DateTimes returns original list identity', () {
      final args = <Object?>[1, 2, 3];
      expect(PgCompatSql.fixArgs(args), same(args));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  group('PgCompatSql — real DAO SQL samples', () {
    // Verify the exact SQL patterns used in production DAOs transform correctly
    // ─────────────────────────────────────────────────────────────────────
    test('cycle_count stock_movements INSERT created_at', () {
      const input =
          "VALUES (?, ?, ?, ?, ?, 'adjustment', 'cycle_count', ?, ?, CAST(strftime('%s','now') AS INTEGER))";
      final out = PgCompatSql.fixSql(input);
      expect(out, isNot(contains('strftime')));
      expect(out, contains('EXTRACT(EPOCH FROM NOW())::bigint'));
      // Placeholders renumbered
      expect(out, contains('\$1'));
      expect(out, contains('\$7'),
          reason: '7 ? placeholders: 5 before the string literals + 2 after');
    });

    test('accounts-receivable aging BETWEEN query', () {
      const input = '''
        SUM(CASE WHEN julianday(? / 1000, 'unixepoch') - julianday(si.invoice_date / 1000, 'unixepoch') <= 30
            THEN si.balance ELSE 0 END) as current_amount,
        SUM(CASE WHEN julianday(? / 1000, 'unixepoch') - julianday(si.invoice_date / 1000, 'unixepoch') BETWEEN 31 AND 60
            THEN si.balance ELSE 0 END) as days_30''';
      final out = PgCompatSql.fixSql(input);
      expect(out, isNot(contains('julianday')));
      expect(out, contains('86400.0'));
      expect(out, contains('\$1'));
      expect(out, contains('\$2'));
    });

    test('inventory balance update last_updated', () {
      const input =
          "UPDATE inventory_balances SET quantity = ?, last_updated = CAST(strftime('%s', 'now') AS INTEGER) WHERE product_id = ? AND warehouse_id = ?";
      final out = PgCompatSql.fixSql(input);
      expect(out, isNot(contains('strftime')));
      expect(out, contains('\$1'));
      expect(out, contains('\$2'));
      expect(out, contains('\$3'));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  group('PgCompatSql.fixSql — GROUP_CONCAT (Feature 011 / Issue PG-GROUPCONCAT)', () {
    // SQLite's GROUP_CONCAT is named STRING_AGG in PostgreSQL. PG also
    // requires the first argument to be text-typed and demands an explicit
    // separator. The translation wraps the expression in `(…)::text` and
    // supplies a default ',' separator when SQLite's caller omitted one.
    //
    // Field incident (server_errors.log 2026-05-05T18:54:43): the
    // categories duplicate-scan dialog crashed with
    //   `42883: function group_concat(bigint) does not exist`
    // when an admin opened it on PG.

    test('one-arg GROUP_CONCAT(id) → STRING_AGG((id)::text, \',\')', () {
      const input = "SELECT GROUP_CONCAT(id) FROM categories";
      final out = PgCompatSql.fixSql(input);
      expect(out, contains("STRING_AGG((id)::text, ',')"));
      expect(out.toUpperCase(), isNot(contains('GROUP_CONCAT')));
    });

    test('two-arg GROUP_CONCAT(name, \'|\') → STRING_AGG with explicit sep',
        () {
      const input = "SELECT GROUP_CONCAT(name, '|') FROM categories";
      final out = PgCompatSql.fixSql(input);
      expect(out, contains("STRING_AGG((name)::text, '|')"));
      expect(out.toUpperCase(), isNot(contains('GROUP_CONCAT')));
    });

    test('exact category-dedup query from the field incident', () {
      // This is the SQL that crashed at category_dedup_extension.dart:32
      const input = 'SELECT LOWER(TRIM(name)) AS norm, '
          '       GROUP_CONCAT(id) AS ids, '
          '       GROUP_CONCAT(name, \'|\') AS names, '
          '       COUNT(*) AS c '
          'FROM categories '
          'GROUP BY LOWER(TRIM(name)) '
          'HAVING c > 1';
      final out = PgCompatSql.fixSql(input);
      expect(out, contains("STRING_AGG((id)::text, ',')"),
          reason: 'one-arg form must use comma default');
      expect(out, contains("STRING_AGG((name)::text, '|')"),
          reason: 'two-arg form must preserve the pipe separator');
      expect(out.toUpperCase(), isNot(contains('GROUP_CONCAT')),
          reason: 'no untranslated GROUP_CONCAT calls may remain');
    });

    test('case-insensitive: group_concat is matched too', () {
      const input = "SELECT group_concat(name) FROM x";
      final out = PgCompatSql.fixSql(input);
      expect(out.toLowerCase(), isNot(contains('group_concat')));
      expect(out, contains('STRING_AGG'));
    });

    test('SQL without GROUP_CONCAT is unchanged by this rule', () {
      const input = "SELECT id, name FROM categories WHERE id > 0";
      final out = PgCompatSql.fixSql(input);
      expect(out, equals(input));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  group('PgCompatSql.fixSql — INSERT OR IGNORE (Feature 031 / Issue PG-INSERT-OR-IGNORE)', () {
    // SQLite's `INSERT OR IGNORE` swallows constraint violations silently.
    // PostgreSQL doesn't speak that dialect — its equivalent is
    // `INSERT … ON CONFLICT DO NOTHING`. Without target columns, PG treats
    // it as "skip on any unique/PK conflict" which mirrors SQLite's behavior.
    //
    // Field incident (server_errors.log 2026-05-11T13:39:26): the bootstrap
    // branch dedup pass crashed against the PG server with
    //   `42601: syntax error at or near "OR"`
    // on `INSERT OR IGNORE INTO user_branch_access (...) SELECT ... FROM ...`.

    test('VALUES form: INSERT OR IGNORE → ON CONFLICT DO NOTHING', () {
      const input =
          "INSERT OR IGNORE INTO settings(key, value) VALUES('k', 'v')";
      final out = PgCompatSql.fixSql(input);
      expect(out, startsWith('INSERT INTO settings'));
      expect(out, endsWith('ON CONFLICT DO NOTHING'));
      expect(out.toUpperCase(), isNot(contains('OR IGNORE')));
    });

    test('SELECT form (the field incident SQL) translates correctly', () {
      const input =
          'INSERT OR IGNORE INTO user_branch_access (user_id, branch_id) '
          'SELECT user_id, ? FROM user_branch_access WHERE branch_id = ?';
      final out = PgCompatSql.fixSql(input);
      expect(out, startsWith('INSERT INTO user_branch_access'));
      expect(out, contains('SELECT user_id, \$1 FROM user_branch_access'));
      expect(out, endsWith('ON CONFLICT DO NOTHING'));
      expect(out.toUpperCase(), isNot(contains('OR IGNORE')));
    });

    test('case-insensitive: lowercase "insert or ignore" also matched', () {
      const input = "insert or ignore into foo(a) values(1)";
      final out = PgCompatSql.fixSql(input);
      expect(out.toUpperCase(), isNot(contains('OR IGNORE')));
      expect(out, contains('ON CONFLICT DO NOTHING'));
    });

    test('trailing semicolon: clause inserted before the ;', () {
      const input =
          "INSERT OR IGNORE INTO settings(key, value) VALUES('k', 'v');";
      final out = PgCompatSql.fixSql(input);
      expect(out, endsWith('ON CONFLICT DO NOTHING;'));
      expect(out, isNot(endsWith(';;')));
    });

    test('idempotency: already-translated SQL is unchanged', () {
      const input =
          "INSERT INTO settings(key, value) VALUES('k', 'v') ON CONFLICT DO NOTHING";
      final out = PgCompatSql.fixSql(input);
      expect(out, equals(input));
    });

    test('SQL with explicit ON CONFLICT clause is not double-appended', () {
      const input =
          "INSERT OR IGNORE INTO settings(key, value) VALUES('k', 'v') ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value";
      final out = PgCompatSql.fixSql(input);
      // OR IGNORE prefix stripped, existing ON CONFLICT preserved as-is.
      expect(out, startsWith('INSERT INTO settings'));
      expect(out, contains('ON CONFLICT (key) DO UPDATE'));
      // Must NOT have an extra ON CONFLICT DO NOTHING appended.
      expect('ON CONFLICT'.allMatches(out).length, equals(1));
    });

    test('plain INSERT INTO is unchanged by this rule', () {
      const input = "INSERT INTO foo(a, b) VALUES(1, 2)";
      final out = PgCompatSql.fixSql(input);
      expect(out, equals(input));
    });
  });
}
