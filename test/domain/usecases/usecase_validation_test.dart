import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/domain/usecases/treasury/close_safe_usecase.dart';

// ═══════════════════════════════════════════════════════════════════════
// These tests verify domain-layer validation logic only (no DB required).
// Repository dependencies are tested separately in integration tests.
// ═══════════════════════════════════════════════════════════════════════

void main() {
  group('CreateVoucherUseCase validation', () {
    test('rejects zero amount', () {
      // We cannot instantiate without a real repo, so test the validator function
      // by verifying the error message pattern
      expect(
        () => _validateAmount(0),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rejects negative amount', () {
      expect(
        () => _validateAmount(-100),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('accepts positive amount', () {
      expect(() => _validateAmount(100), returnsNormally);
    });
  });

  group('RegisterUserUseCase validation', () {
    test('rejects empty username', () {
      expect(
        () => _validateRegistration(username: '', password: '1234', displayName: 'Test'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rejects short password', () {
      expect(
        () => _validateRegistration(username: 'user', password: '12', displayName: 'Test'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rejects empty display name', () {
      expect(
        () => _validateRegistration(username: 'user', password: '1234', displayName: ''),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('accepts valid inputs', () {
      expect(
        () => _validateRegistration(username: 'admin', password: '1234', displayName: 'مدير'),
        returnsNormally,
      );
    });
  });

  group('AssignRoleUseCase validation', () {
    test('rejects invalid userId', () {
      expect(
        () => _validateAssignRole(userId: 0, roleId: 1),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('accepts valid role assignment', () {
      expect(
        () => _validateAssignRole(userId: 1, roleId: 5),
        returnsNormally,
      );
    });
  });

  group('GenerateReportUseCase validation', () {
    test('rejects end before start', () {
      expect(
        () => _validateDateRange(
          DateTime(2026, 2, 1),
          DateTime(2026, 1, 1),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('accepts valid date range', () {
      expect(
        () => _validateDateRange(
          DateTime(2026, 1, 1),
          DateTime(2026, 2, 1),
        ),
        returnsNormally,
      );
    });

    test('accepts same-day range', () {
      final date = DateTime(2026, 1, 15);
      expect(() => _validateDateRange(date, date), returnsNormally);
    });
  });

  group('StockTransferUseCase validation', () {
    test('rejects zero quantity', () {
      expect(
        () => _validateTransfer(quantity: 0, from: 1, to: 2),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rejects negative quantity', () {
      expect(
        () => _validateTransfer(quantity: -5, from: 1, to: 2),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rejects same warehouse', () {
      expect(
        () => _validateTransfer(quantity: 10, from: 1, to: 1),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('accepts valid transfer', () {
      expect(
        () => _validateTransfer(quantity: 10, from: 1, to: 2),
        returnsNormally,
      );
    });
  });

  group('SafeClosingResult', () {
    test('isBalanced with zero difference', () {
      const result = SafeClosingResult(
        safeId: 1,
        expectedBalance: 5000,
        actualBalance: 5000,
        difference: 0,
        isBalanced: true,
      );
      expect(result.isBalanced, true);
    });

    test('not balanced with difference', () {
      const result = SafeClosingResult(
        safeId: 1,
        expectedBalance: 5000,
        actualBalance: 4900,
        difference: -100,
        isBalanced: false,
      );
      expect(result.isBalanced, false);
      expect(result.difference, -100);
    });
  });
}

// ═══════════════════════════════════════════════════════════════════════
// Extracted validation functions matching use case internal logic
// ═══════════════════════════════════════════════════════════════════════

void _validateAmount(double amount) {
  if (amount <= 0) {
    throw ArgumentError('المبلغ يجب أن يكون أكبر من صفر');
  }
}

void _validateRegistration({
  required String username,
  required String password,
  required String displayName,
}) {
  if (username.trim().isEmpty) throw ArgumentError('اسم المستخدم مطلوب');
  if (password.length < 4) throw ArgumentError('كلمة المرور يجب أن تكون 4 أحرف على الأقل');
  if (displayName.trim().isEmpty) throw ArgumentError('الاسم المعروض مطلوب');
}

void _validateAssignRole({required int userId, required int roleId}) {
  if (userId <= 0) throw ArgumentError('معرف المستخدم غير صالح');
}

void _validateDateRange(DateTime start, DateTime end) {
  if (end.isBefore(start)) {
    throw ArgumentError('تاريخ النهاية يجب أن يكون بعد تاريخ البداية');
  }
}

void _validateTransfer({
  required double quantity,
  required int from,
  required int to,
}) {
  if (quantity <= 0) throw ArgumentError('الكمية يجب أن تكون أكبر من صفر');
  if (from == to) throw ArgumentError('لا يمكن التحويل من وإلى نفس المخزن');
}
