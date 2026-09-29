import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/core/errors/result.dart';

void main() {
  group('Result', () {
    test('Success should contain data', () {
      final result = Result<int>.success(42);

      expect(result.isSuccess, true);
      expect(result.isFailure, false);
      expect(result.dataOrThrow, 42);
      expect(result.dataOrNull, 42);
      expect(result.errorOrNull, null);
    });

    test('Failure should contain error', () {
      final result = Result<int>.failure(
        const ValidationException('Invalid input'),
      );

      expect(result.isSuccess, false);
      expect(result.isFailure, true);
      expect(result.dataOrNull, null);
      expect(result.errorOrNull, isA<ValidationException>());
    });

    test('dataOrThrow should throw on failure', () {
      final result = Result<int>.failure(
        const DatabaseException('Connection failed'),
      );

      expect(() => result.dataOrThrow, throwsA(isA<DatabaseException>()));
    });

    test('map should transform success value', () {
      final result = Result<int>.success(10);
      final mapped = result.map((data) => data * 2);

      expect(mapped.dataOrThrow, 20);
    });

    test('map should preserve failure', () {
      final result = Result<int>.failure(
        const NotFoundException('Item not found'),
      );
      final mapped = result.map((data) => data * 2);

      expect(mapped.isFailure, true);
      expect(mapped.errorOrNull, isA<NotFoundException>());
    });

    test('flatMap should chain operations', () {
      Result<int> doubleIfPositive(int value) {
        if (value > 0) {
          return Result.success(value * 2);
        }
        return Result.failure(const ValidationException('Must be positive'));
      }

      final success = Result<int>.success(5).flatMap(doubleIfPositive);
      expect(success.dataOrThrow, 10);

      final failure = Result<int>.success(-1).flatMap(doubleIfPositive);
      expect(failure.isFailure, true);
    });

    test('onSuccess should execute action on success', () {
      int callCount = 0;
      Result<int>.success(1).onSuccess((_) => callCount++);

      expect(callCount, 1);
    });

    test('onFailure should execute action on failure', () {
      int callCount = 0;
      Result<int>.failure(const ValidationException('error'))
          .onFailure((_) => callCount++);

      expect(callCount, 1);
    });
  });

  group('AppException', () {
    test('ValidationException should have correct code', () {
      const exception = ValidationException('Invalid');
      expect(exception.code, 'VALIDATION_ERROR');
      expect(exception.message, 'Invalid');
    });

    test('InsufficientStockException should format message', () {
      final exception = InsufficientStockException(
        productId: 1,
        available: 5,
        requested: 10,
      );
      expect(exception.message, contains('5'));
      expect(exception.message, contains('10'));
    });

    test('toString should include code', () {
      const exception = DatabaseException('Query failed');
      expect(exception.toString(), contains('DB_ERROR'));
    });
  });
}
