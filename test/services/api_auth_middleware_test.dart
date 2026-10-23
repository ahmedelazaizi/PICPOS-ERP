import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/services/api/api_auth_middleware.dart';

void main() {
  setUp(() {
    ApiAuthMiddleware.clearToken();
  });

  group('ApiAuthMiddleware', () {
    test('generateToken produces a 32-char hex string', () {
      final token = ApiAuthMiddleware.generateToken('test-seed');
      expect(token.length, 32);
      expect(RegExp(r'^[0-9a-f]+$').hasMatch(token), true);
    });

    test('same seed produces same token', () {
      final t1 = ApiAuthMiddleware.generateToken('machine-123');
      ApiAuthMiddleware.clearToken();
      final t2 = ApiAuthMiddleware.generateToken('machine-123');
      expect(t1, equals(t2));
    });

    test('different seeds produce different tokens', () {
      final t1 = ApiAuthMiddleware.generateToken('machine-A');
      ApiAuthMiddleware.clearToken();
      final t2 = ApiAuthMiddleware.generateToken('machine-B');
      expect(t1, isNot(equals(t2)));
    });

    test('activeToken returns null when cleared', () {
      expect(ApiAuthMiddleware.activeToken, isNull);
    });

    test('activeToken returns token after generation', () {
      final token = ApiAuthMiddleware.generateToken('seed');
      expect(ApiAuthMiddleware.activeToken, equals(token));
    });

    test('setToken overrides the active token', () {
      ApiAuthMiddleware.setToken('custom-token');
      expect(ApiAuthMiddleware.activeToken, 'custom-token');
    });

    test('clearToken resets state', () {
      ApiAuthMiddleware.generateToken('seed');
      expect(ApiAuthMiddleware.activeToken, isNotNull);
      ApiAuthMiddleware.clearToken();
      expect(ApiAuthMiddleware.activeToken, isNull);
    });
  });
}
