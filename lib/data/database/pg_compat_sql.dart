// ═══════════════════════════════════════════════════════════════════════════
// PostgreSQL SQL Compatibility — pure SQL transformation utilities
// ═══════════════════════════════════════════════════════════════════════════
//
// Translates SQLite-specific SQL idioms to their PostgreSQL equivalents.
// Used by _PgCompatInterceptor in connection_io.dart and tested independently.
//
// Transformations applied (in order):
//   1. strftime('%H', expr/1000, 'unixepoch', 'localtime') → EXTRACT(HOUR …)
//   2. strftime(…)                    → EXTRACT(EPOCH FROM NOW())::bigint
//   3. datetime('now')                → NOW()
//   4. julianday('now')               → (EXTRACT(EPOCH FROM NOW()) / 86400.0)
//   5. julianday(expr / 1000, 'unixepoch') → ((expr) / 86400.0)
//   6. julianday(expr)                → ((expr) / 86400.0)
//   7. INSTR(haystack, needle)        → STRPOS(haystack, needle)
//   8. GROUP_CONCAT(expr [, sep])     → STRING_AGG((expr)::text, sep|',')
//   9. INSERT OR IGNORE INTO …        → INSERT INTO … ON CONFLICT DO NOTHING
//  10. ? positional params            → $1, $2, $3 …  (skip inside '' literals)
// ═══════════════════════════════════════════════════════════════════════════

class PgCompatSql {
  PgCompatSql._();

  // ── strftime('%H', expr / 1000, 'unixepoch', 'localtime') ──
  static final _strftimeHour = RegExp(
    r"CAST\s*\(\s*strftime\s*\(\s*'%H'\s*,\s*(.+?)\s*/\s*1000\s*,\s*'unixepoch'\s*,\s*'localtime'\s*\)\s*AS\s+INTEGER\s*\)",
    caseSensitive: false,
  );

  // ── strftime(…) → catch-all for remaining strftime calls ──
  static final _strftimePattern = RegExp(
    r"strftime\s*\([^)]+\)",
    caseSensitive: false,
  );

  // ── datetime('now') ──
  static final _datetimeNow = RegExp(
    r"datetime\s*\(\s*'now'\s*\)",
    caseSensitive: false,
  );

  // ── julianday('now') ──
  static final _juliandayNow = RegExp(
    r"julianday\s*\(\s*'now'\s*\)",
    caseSensitive: false,
  );

  // ── julianday(expr / 1000, 'unixepoch') ──
  static final _juliandayUnixepoch = RegExp(
    r"julianday\s*\(([^,]+),\s*'unixepoch'\s*\)",
    caseSensitive: false,
  );

  // ── julianday(expr) — must be last (most general) ──
  static final _juliandaySimple = RegExp(
    r"julianday\s*\(([^)]+)\)",
    caseSensitive: false,
  );

  // ── INSTR(haystack, needle) → STRPOS(haystack, needle) ──
  // SQLite and PostgreSQL agree on 1-based positions and 0 for "not found",
  // so STRPOS is a drop-in replacement. The regex requires balanced parens
  // inside the arguments (no nested INSTR, no parens inside string literals
  // — both true for current callers).
  static final _instrPattern = RegExp(
    r"\bINSTR\s*\(",
    caseSensitive: false,
  );

  // ── GROUP_CONCAT(expr [, sep]) → STRING_AGG((expr)::text, sep|',') ──
  // SQLite's GROUP_CONCAT is named differently in PostgreSQL — and PG's
  // STRING_AGG insists on a text-typed first argument and a REQUIRED
  // separator. Translation:
  //   • GROUP_CONCAT(id)         → STRING_AGG((id)::text, ',')
  //   • GROUP_CONCAT(name, '|')  → STRING_AGG((name)::text, '|')
  // Two regexes, two-arg variant tried first so it doesn't get eaten by
  // the one-arg pattern's match. Both require balanced-paren-free args
  // (no nested GROUP_CONCAT, no commas inside the expression aside from
  // the separator one) — true for every current caller. Field incident
  // (Feature 011 / Issue PG-GROUPCONCAT, server_errors.log
  // 2026-05-05T18:54:43): the categories duplicate-scan dialog crashed
  // with `42883 function group_concat(bigint) does not exist`.
  static final _groupConcatTwoArg = RegExp(
    r"\bGROUP_CONCAT\s*\(\s*([^,()]+?)\s*,\s*('[^']*')\s*\)",
    caseSensitive: false,
  );
  static final _groupConcatOneArg = RegExp(
    r"\bGROUP_CONCAT\s*\(\s*([^,()]+?)\s*\)",
    caseSensitive: false,
  );

  // ── INSERT OR IGNORE INTO … → INSERT INTO … ON CONFLICT DO NOTHING ──
  // SQLite's `INSERT OR IGNORE` swallows constraint violations silently.
  // PostgreSQL's closest equivalent is `INSERT … ON CONFLICT DO NOTHING`
  // (no target column list → matches ANY unique / primary key conflict,
  // which mirrors SQLite's "any unique violation" semantics).
  //
  // Field incident (2026-05-11): branch_dedup_extension's mergeDuplicateBranches
  // called `INSERT OR IGNORE INTO user_branch_access ... SELECT ...` against
  // the PG server during startup and crashed with `42601 syntax error at or
  // near "OR"`, blocking the server's bootstrap dedup pass. The same idiom
  // is used by category_dedup_extension and modifiers_dao.
  static final _insertOrIgnore = RegExp(
    r"\bINSERT\s+OR\s+IGNORE\s+INTO\b",
    caseSensitive: false,
  );

  /// Translate [sql] from SQLite dialect to PostgreSQL dialect.
  ///
  /// Idempotent: already-translated SQL is unchanged because the SQLite
  /// patterns no longer appear after the first pass.
  static String fixSql(String sql) {
    // The compatibility layer itself creates `strftime` overloads. Do not
    // rewrite the function declaration into `CREATE FUNCTION EXTRACT(...)`;
    // only rewrite calls in ordinary SQLite-derived statements.
    if (RegExp(
      r'CREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION\s+strftime',
      caseSensitive: false,
    ).hasMatch(sql)) {
      return sql;
    }
    var result = sql;

    // 1 & 2. strftime
    if (result.contains('strftime')) {
      result = result.replaceAllMapped(_strftimeHour, (m) {
        final expr = m.group(1)!.trim();
        return "EXTRACT(HOUR FROM to_timestamp($expr / 1000))::int";
      });
      result = result.replaceAll(_strftimePattern, "EXTRACT(EPOCH FROM NOW())::bigint");
    }

    // 3. datetime('now')
    if (result.toLowerCase().contains('datetime')) {
      result = result.replaceAll(_datetimeNow, "NOW()");
    }

    // 4–6. julianday (specific before general)
    if (result.contains('julianday')) {
      result = result.replaceAllMapped(_juliandayNow, (_) =>
          "(EXTRACT(EPOCH FROM NOW()) / 86400.0)");
      result = result.replaceAllMapped(_juliandayUnixepoch, (m) {
        final expr = m.group(1)!.trim();
        return "(($expr) / 86400.0)";
      });
      result = result.replaceAllMapped(_juliandaySimple, (m) {
        final expr = m.group(1)!.trim();
        return "(($expr) / 86400.0)";
      });
    }

    // 7. INSTR(haystack, needle) → STRPOS(haystack, needle)
    // Case-insensitive replacement of the function name only — argument
    // expressions are left untouched, including any nested SUBSTR calls.
    if (_instrPattern.hasMatch(result)) {
      result = result.replaceAll(_instrPattern, 'STRPOS(');
    }

    // 8. GROUP_CONCAT(...) → STRING_AGG(...)
    // Two-arg form first (so the explicit separator is preserved), then
    // the one-arg form which gets a default ',' separator. The expression
    // is wrapped in parens and ::text-cast so STRING_AGG accepts non-text
    // columns (the original GROUP_CONCAT was happy with INTEGER ids).
    if (result.toUpperCase().contains('GROUP_CONCAT')) {
      result = result.replaceAllMapped(_groupConcatTwoArg, (m) {
        final expr = m.group(1)!.trim();
        final sep = m.group(2)!;
        return "STRING_AGG(($expr)::text, $sep)";
      });
      result = result.replaceAllMapped(_groupConcatOneArg, (m) {
        final expr = m.group(1)!.trim();
        return "STRING_AGG(($expr)::text, ',')";
      });
    }

    // 9. INSERT OR IGNORE INTO … → INSERT INTO … ON CONFLICT DO NOTHING
    // Replace the OR IGNORE prefix and append the conflict clause at the
    // end of the statement (before a trailing semicolon if present). Skip
    // the append when the SQL already contains an explicit ON CONFLICT
    // clause, since combining the two is a syntax error.
    if (_insertOrIgnore.hasMatch(result)) {
      result = result.replaceAll(_insertOrIgnore, 'INSERT INTO');
      if (!RegExp(r"\bON\s+CONFLICT\b", caseSensitive: false).hasMatch(result)) {
        final trimmed = result.trimRight();
        if (trimmed.endsWith(';')) {
          result =
              '${trimmed.substring(0, trimmed.length - 1)} ON CONFLICT DO NOTHING;';
        } else {
          result = '$trimmed ON CONFLICT DO NOTHING';
        }
      }
    }

    // 10. ? → $1, $2, … (skip characters inside single-quoted string literals)
    // FIX 2026-04-28: Use LOOKAHEAD to correctly distinguish between
    //   - empty string literal '' (open + immediate close)
    //   - escape sequence '' inside an existing string ('don''t')
    //
    // The previous lookbehind algorithm couldn't tell these apart: when it
    // saw the second ' of '' it always treated it as an escape and refused
    // to toggle, leaving inSingleQuote=true forever once the SQL contained
    // any '' literal. That meant every subsequent ? was treated as "inside
    // a string" and never translated → PostgreSQL got raw ? and rejected
    // the statement with `42601: syntax error`. Crashed every call to
    // getSalesReturnItemDetails / getPurchaseReturnItemDetails (both have
    // `'' AS unit_name` in the SELECT list).
    if (result.contains('?')) {
      final buf = StringBuffer();
      var paramIndex = 0;
      var inSingleQuote = false;
      var i = 0;
      while (i < result.length) {
        final ch = result[i];
        if (ch == "'") {
          if (inSingleQuote && i + 1 < result.length && result[i + 1] == "'") {
            // Escaped '' inside a string literal — emit both chars verbatim,
            // stay inside the string.
            buf.write("''");
            i += 2;
            continue;
          }
          // Real quote boundary — toggle.
          inSingleQuote = !inSingleQuote;
          buf.write(ch);
        } else if (ch == '?' && !inSingleQuote) {
          paramIndex++;
          buf.write('\$$paramIndex');
        } else {
          buf.write(ch);
        }
        i++;
      }
      result = buf.toString();
    }

    return result;
  }

  /// Convert any [DateTime] values in [args] to epoch seconds (int).
  ///
  /// Drift stores DateTime as epoch-seconds in BIGINT columns. SQLite's
  /// native driver auto-converts, but drift_postgres sends DateTime as
  /// timestamptz — which mismatches BIGINT columns and silently returns
  /// empty results. Converting here fixes all queries at once.
  static List<Object?> fixArgs(List<Object?> args) {
    if (!args.any((a) => a is DateTime)) return args;
    return args.map((a) => a is DateTime ? a.millisecondsSinceEpoch ~/ 1000 : a).toList();
  }
}
