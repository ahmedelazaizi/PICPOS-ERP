import 'dart:developer' as developer;
import 'dart:typed_data';
import '../utils/file_utils.dart';
import '../config/brand.dart';

/// Severity levels for logging
enum LogLevel { debug, info, warning, error }

/// Central logging service for UralCash
///
/// All logging should go through this service - no print() statements allowed.
/// Supports correlation IDs for tracing transactions across the system.
class AppLogger {
  static final AppLogger _instance = AppLogger._internal();
  static AppLogger get instance => _instance;
  factory AppLogger() => _instance;
  AppLogger._internal();

  LogLevel _minLevel = LogLevel.debug;
  final List<LogEntry> _buffer = [];
  static const int _maxBufferSize = 500;

  /// Set minimum log level
  void setMinLevel(LogLevel level) => _minLevel = level;

  /// Log debug message
  void debug(
    String message, {
    String? correlationId,
    Map<String, dynamic>? context,
  }) {
    _log(
      LogLevel.debug,
      message,
      correlationId: correlationId,
      context: context,
    );
  }

  /// Log info message
  void info(
    String message, {
    String? correlationId,
    Map<String, dynamic>? context,
  }) {
    _log(
      LogLevel.info,
      message,
      correlationId: correlationId,
      context: context,
    );
  }

  /// Log warning message
  void warning(
    String message, {
    String? correlationId,
    Map<String, dynamic>? context,
  }) {
    _log(
      LogLevel.warning,
      message,
      correlationId: correlationId,
      context: context,
    );
  }

  /// Log error with optional exception and stack trace
  void error(
    String message, [
    Object? exception,
    StackTrace? stackTrace,
    String? correlationId,
    Map<String, dynamic>? context,
  ]) {
    _log(
      LogLevel.error,
      message,
      exception: exception,
      stackTrace: stackTrace,
      correlationId: correlationId,
      context: context,
    );
  }

  /// Internal logging implementation
  void _log(
    LogLevel level,
    String message, {
    Object? exception,
    StackTrace? stackTrace,
    String? correlationId,
    Map<String, dynamic>? context,
  }) {
    if (level.index < _minLevel.index) return;

    final entry = LogEntry(
      level: level,
      message: message,
      timestamp: DateTime.now(),
      exception: exception,
      stackTrace: stackTrace,
      correlationId: correlationId,
      context: context,
    );

    _buffer.add(entry);
    if (_buffer.length > _maxBufferSize) {
      _buffer.removeAt(0);
    }

    // Output to developer console
    final prefix = '[${_levelPrefix(level)}]';
    final corrId = correlationId != null ? ' [$correlationId]' : '';
    final logMessage = '$prefix$corrId $message';

    developer.log(
      logMessage,
      name: Brand.name,
      level: _levelToInt(level),
      error: exception,
      stackTrace: stackTrace,
    );

    // Also print to console in debug mode
    assert(() {
      final timestamp =
          '${entry.timestamp.hour}:${entry.timestamp.minute}:${entry.timestamp.second}';
      // ignore: avoid_print
      print('[$timestamp]$logMessage');
      if (exception != null) {
        // ignore: avoid_print
        print('Exception: $exception');
      }
      return true;
    }());
  }

  String _levelPrefix(LogLevel level) {
    switch (level) {
      case LogLevel.debug:
        return 'DEBUG';
      case LogLevel.info:
        return 'INFO';
      case LogLevel.warning:
        return 'WARN';
      case LogLevel.error:
        return 'ERROR';
    }
  }

  int _levelToInt(LogLevel level) {
    switch (level) {
      case LogLevel.debug:
        return 500;
      case LogLevel.info:
        return 800;
      case LogLevel.warning:
        return 900;
      case LogLevel.error:
        return 1000;
    }
  }

  /// Get recent log entries
  List<LogEntry> getRecentLogs({int count = 100}) {
    final start = _buffer.length > count ? _buffer.length - count : 0;
    return _buffer.sublist(start);
  }

  /// Export logs using platform-specific utilities
  Future<void> exportLogs(String path) async {
    try {
      final buffer = StringBuffer();

      for (final entry in _buffer) {
        buffer.writeln(entry.toFormattedString());
      }

      final bytes = Uint8List.fromList(buffer.toString().codeUnits);
      await fileUtils.saveFile(path, bytes);
    } catch (e) {
      error('Failed to export logs', e);
    }
  }

  /// Clear log buffer
  void clear() => _buffer.clear();
}

/// Single log entry
class LogEntry {
  final LogLevel level;
  final String message;
  final DateTime timestamp;
  final Object? exception;
  final StackTrace? stackTrace;
  final String? correlationId;
  final Map<String, dynamic>? context;

  LogEntry({
    required this.level,
    required this.message,
    required this.timestamp,
    this.exception,
    this.stackTrace,
    this.correlationId,
    this.context,
  });

  String toFormattedString() {
    final buffer = StringBuffer();
    buffer.write('${timestamp.toIso8601String()} ');
    buffer.write('[${level.name.toUpperCase()}] ');
    if (correlationId != null) buffer.write('[$correlationId] ');
    buffer.write(message);
    if (exception != null) buffer.write('\n  Exception: $exception');
    if (stackTrace != null) buffer.write('\n  Stack: $stackTrace');
    if (context != null) buffer.write('\n  Context: $context');
    return buffer.toString();
  }
}

/// Global logger instance for convenience
final logger = AppLogger.instance;
