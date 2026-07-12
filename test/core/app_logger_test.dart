import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/core/logging/app_logger.dart';

/// Core layer tests
void main() {
  group('AppLogger', () {
    late AppLogger logger;

    setUp(() {
      logger = AppLogger.instance;
      logger.clear();
    });

    test('should be singleton', () {
      final logger1 = AppLogger.instance;
      final logger2 = AppLogger.instance;
      final logger3 = AppLogger();

      expect(logger1, same(logger2));
      expect(logger2, same(logger3));
    });

    test('should log debug messages', () {
      logger.debug('Test debug message');
      
      final logs = logger.getRecentLogs();
      expect(logs.length, 1);
      expect(logs.first.level, LogLevel.debug);
      expect(logs.first.message, 'Test debug message');
    });

    test('should log info messages', () {
      logger.info('Test info message', correlationId: 'TEST123');
      
      final logs = logger.getRecentLogs();
      expect(logs.first.level, LogLevel.info);
      expect(logs.first.correlationId, 'TEST123');
    });

    test('should log warning messages', () {
      logger.warning('Test warning');
      
      final logs = logger.getRecentLogs();
      expect(logs.first.level, LogLevel.warning);
    });

    test('should log error messages with exception', () {
      try {
        throw const FormatException('Test error');
      } catch (e, stack) {
        logger.error('Error occurred', e, stack, 'ERR001');
      }
      
      final logs = logger.getRecentLogs();
      expect(logs.first.level, LogLevel.error);
      expect(logs.first.exception, isA<FormatException>());
      expect(logs.first.correlationId, 'ERR001');
    });

    test('should respect min log level', () {
      logger.setMinLevel(LogLevel.warning);
      
      logger.debug('Debug');
      logger.info('Info');
      logger.warning('Warning');
      logger.error('Error');
      
      final logs = logger.getRecentLogs();
      expect(logs.length, 2); // Only warning and error
      expect(logs[0].level, LogLevel.warning);
      expect(logs[1].level, LogLevel.error);
      
      // Reset for other tests
      logger.setMinLevel(LogLevel.debug);
    });

    test('should limit buffer size', () {
      // Log more than max buffer size
      for (int i = 0; i < 600; i++) {
        logger.debug('Message $i');
      }
      
      final logs = logger.getRecentLogs(count: 1000);
      expect(logs.length, lessThanOrEqualTo(500)); // Max buffer size
    });

    test('should clear logs', () {
      logger.info('Test');
      expect(logger.getRecentLogs().length, 1);
      
      logger.clear();
      expect(logger.getRecentLogs().length, 0);
    });

    test('LogEntry should format correctly', () {
      final entry = LogEntry(
        level: LogLevel.error,
        message: 'Test message',
        timestamp: DateTime(2026, 1, 17, 12, 30, 45),
        correlationId: 'CORR123',
        exception: const FormatException('Test'),
      );

      final formatted = entry.toFormattedString();
      expect(formatted, contains('[ERROR]'));
      expect(formatted, contains('[CORR123]'));
      expect(formatted, contains('Test message'));
      expect(formatted, contains('FormatException'));
    });
  });

  group('Global logger', () {
    test('should be accessible globally', () {
      expect(logger, isNotNull);
      expect(logger, isA<AppLogger>());
    });
  });
}
