// Spec 088 — permission lookup must not bypass normal authorization.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final src =
      File('lib/services/api/api_user_context.dart').readAsStringSync();

  group('Spec 088 — no bootstrap-admin permission bypass', () {
    test('does not import bootstrap-admin bypass predicate', () {
      expect(src, isNot(contains('bootstrap_admin.dart')));
      expect(src, isNot(contains('isBootstrapAdmin')));
    });

    test('does not emit the bypass PERMS-WARN diagnostic', () {
      // DiagnosticLogger stays imported for unrelated logging in this file;
      // only the bypass-specific warning must be gone.
      expect(src, isNot(contains("'PERMS-WARN'")));
    });

    test('does not define a one-shot bypass flag', () {
      expect(src, isNot(contains('_bootstrapBypassLogged')));
      expect(src, isNot(contains('bootstrap admin bypass engaged')));
    });

    test('always performs the permission lookup', () {
      expect(src, contains('db.userHasPermission(userId, code)'));
    });

    test('permission lookup follows the missing-session 401 guard', () {
      final missingIdx = src.indexOf('Missing or invalid X-Session-Token');
      final lookupIdx = src.indexOf('db.userHasPermission(userId, code)');
      expect(missingIdx, isNot(-1));
      expect(lookupIdx, isNot(-1));
      expect(missingIdx < lookupIdx, isTrue);
    });
  });
}
