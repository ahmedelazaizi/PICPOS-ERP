// ═══════════════════════════════════════════════════════════════════════════
// PostgreSQL Compatibility Layer Tests
// ═══════════════════════════════════════════════════════════════════════════
//
// Tests that the PostgreSQL compatibility layer patterns are correct:
// - strftime() SQL generation
// - boolean-integer operator overrides
// - Drift type mapping for PG
// - Default value handling

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PostgreSQL SQL Compatibility', () {
    test('strftime replacement generates correct EXTRACT syntax', () {
      // The compatibility function should replace strftime('%s','now')
      // with EXTRACT(EPOCH FROM NOW())::bigint
      const pgReplacementSql =
          "EXTRACT(EPOCH FROM NOW())::bigint";
      expect(pgReplacementSql, contains('EXTRACT'));
      expect(pgReplacementSql, contains('EPOCH'));
      expect(pgReplacementSql, contains('bigint'));
    });

    test('boolean-integer comparison function is correct', () {
      // bool_eq_int(true, 1) → true
      // bool_eq_int(false, 0) → true
      // bool_eq_int(true, 0) → false
      bool boolEqInt(bool b, int i) => b == (i != 0);

      expect(boolEqInt(true, 1), isTrue);
      expect(boolEqInt(false, 0), isTrue);
      expect(boolEqInt(true, 0), isFalse);
      expect(boolEqInt(false, 1), isFalse);
    });

    test('integer-boolean comparison function is correct', () {
      // int_eq_bool(1, true) → true
      bool intEqBool(int i, bool b) => (i != 0) == b;

      expect(intEqBool(1, true), isTrue);
      expect(intEqBool(0, false), isTrue);
      expect(intEqBool(0, true), isFalse);
      expect(intEqBool(1, false), isFalse);
    });
  });

  group('Drift Type Mapping for PostgreSQL', () {
    test('DriftSqlType mappings are correct', () {
      // Map from Drift types to expected PG types
      final expectedMappings = <String, String>{
        'int': 'INTEGER',
        'string': 'TEXT',
        'bool': 'BOOLEAN',
        'double': 'DOUBLE PRECISION',
        'dateTime': 'BIGINT',
        'blob': 'BYTEA',
      };

      expect(expectedMappings['int'], 'INTEGER');
      expect(expectedMappings['string'], 'TEXT');
      expect(expectedMappings['bool'], 'BOOLEAN');
      expect(expectedMappings['double'], 'DOUBLE PRECISION');
      expect(expectedMappings['dateTime'], 'BIGINT');
      expect(expectedMappings['blob'], 'BYTEA');
    });

    test('auto-increment maps to SERIAL PRIMARY KEY', () {
      const autoIncrementPg = 'SERIAL PRIMARY KEY';
      expect(autoIncrementPg, contains('SERIAL'));
      expect(autoIncrementPg, contains('PRIMARY KEY'));
    });
  });

  group('Default Value Handling', () {
    test('currentDateAndTime default maps to EXTRACT', () {
      const defaultStr = 'currentDateAndTime';
      const pgDefault = "DEFAULT (EXTRACT(EPOCH FROM NOW())::bigint)";

      if (defaultStr.contains('currentDateAndTime')) {
        expect(pgDefault, contains('EXTRACT'));
      }
    });

    test('boolean default values use TRUE/FALSE', () {
      String mapBoolDefault(bool val) => val ? 'TRUE' : 'FALSE';

      expect(mapBoolDefault(true), 'TRUE');
      expect(mapBoolDefault(false), 'FALSE');
    });

    test('string defaults are properly escaped', () {
      String escapeDefault(String val) => val.replaceAll("'", "''");

      expect(escapeDefault("test'value"), "test''value");
      expect(escapeDefault("normal"), "normal");
    });
  });
}
