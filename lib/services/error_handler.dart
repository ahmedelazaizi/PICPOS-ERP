import 'package:flutter/material.dart';
import '../../core/widgets/app_toast.dart';
import 'dart:developer' as developer;
import 'package:intl/intl.dart';
import '../core/config/brand.dart';
import 'log_writer.dart';

/// Log level enumeration
enum LogLevel { debug, info, warning, error }

/// Central logging service for the application
class AppLogger {
  AppLogger._();
  static final AppLogger instance = AppLogger._();

  static const bool _enableFileLogging = true; // PIR P2.5: Always write to log file
  static const LogLevel _minLevel = LogLevel.info;

  final LogWriter _logWriter = LogWriter();
  String? _logFilePath;

  /// Initialize the logger
  Future<void> init() async {
    if (_enableFileLogging) {
      _logFilePath = await _logWriter.getLogPath();
    }
  }

  /// Log a debug message
  void debug(String message, {String? tag}) {
    _log(LogLevel.debug, message, tag: tag);
  }

  /// Log an info message
  void info(String message, {String? tag}) {
    _log(LogLevel.info, message, tag: tag);
  }

  /// Log a warning message
  void warning(String message, {String? tag}) {
    _log(LogLevel.warning, message, tag: tag);
  }

  /// Log an error message with optional exception
  void error(
    String message, {
    String? tag,
    Object? error,
    StackTrace? stackTrace,
  }) {
    _log(
      LogLevel.error,
      message,
      tag: tag,
      error: error,
      stackTrace: stackTrace,
    );
  }

  void _log(
    LogLevel level,
    String message, {
    String? tag,
    Object? error,
    StackTrace? stackTrace,
  }) {
    if (level.index < _minLevel.index) return;

    final timestamp = DateFormat('HH:mm:ss.SSS').format(DateTime.now());
    final levelStr = level.name.toUpperCase().padRight(7);
    final tagStr = tag != null ? '[$tag]' : '';
    final logMessage = '[$timestamp] $levelStr $tagStr $message';

    // Console output
    developer.log(
      message,
      // كان مثبَّت على `MONEXIA` — اسم علامة تالتة بيوسم كل سطر لوج.
      name: tag ?? Brand.name,
      level: _levelToInt(level),
      error: error,
      stackTrace: stackTrace,
    );

    // File output (optional)
    if (_enableFileLogging && _logFilePath != null) {
      _writeToFile(logMessage, error, stackTrace);
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

  Future<void> _writeToFile(
    String message,
    Object? error,
    StackTrace? stackTrace,
  ) async {
    await _logWriter.writeLog(_logFilePath, message, error, stackTrace);
  }
}

/// Global logger instance
final logger = AppLogger.instance;

// ═══════════════════════════════════════════════════════════════════════════
// SMART ERROR PATTERN MATCHING
// ═══════════════════════════════════════════════════════════════════════════

/// A contextual error result with a user-friendly message and optional fix hint.
class SmartErrorResult {
  final String message;
  final String? actionLabel;
  final String? hint;

  const SmartErrorResult(this.message, {this.actionLabel, this.hint});
}

/// Pattern-based error classification rules (Arabic + English).
/// Order matters — first match wins.
const _errorPatterns = <_ErrorPattern>[
  // ── Database Constraints ──
  _ErrorPattern(
    patterns: ['unique constraint', 'unique_violation', 'already exists', 'مستخدم بالفعل'],
    message: 'الاسم أو الكود مستخدم بالفعل. اختر قيمة مختلفة.',
  ),
  _ErrorPattern(
    patterns: ['foreign key', 'foreign_key_violation', 'مرتبط'],
    message: 'لا يمكن الحذف — هذا العنصر مرتبط ببيانات أخرى (فواتير أو حركات).',
  ),
  _ErrorPattern(
    patterns: ['not null', 'null_violation', 'حقل مطلوب'],
    message: 'يوجد حقل مطلوب لم يتم ملؤه. راجع البيانات المدخلة.',
  ),

  // ── Storage / IO ──
  _ErrorPattern(
    patterns: ['disk full', 'no space', 'io error', 'مساحة', 'storage'],
    message: 'مساحة التخزين ممتلئة. احذف ملفات غير ضرورية أو وسّع القرص.',
  ),

  // ── Network / Connection ──
  _ErrorPattern(
    patterns: ['timeout', 'timed out', 'مهلة'],
    message: 'انتهت مهلة الاتصال. تأكد من اتصال الإنترنت وحاول مجدداً.',
  ),
  _ErrorPattern(
    patterns: ['socket', 'connection refused', 'port', 'منفذ'],
    message: 'فشل الاتصال بالجهاز. تأكد من التوصيل والمنفذ الصحيح.',
  ),
  _ErrorPattern(
    patterns: ['network', 'connection', 'اتصال'],
    message: 'خطأ في الاتصال بالشبكة. تأكد من اتصال الإنترنت.',
  ),

  // ── Printing ──
  _ErrorPattern(
    patterns: ['printer', 'print', 'طابعة', 'طباعة'],
    message: 'خطأ في الطباعة. تأكد من تشغيل الطابعة واتصالها.',
    actionLabel: 'إعدادات الطابعة',
  ),

  // ── Trial / License ──
  _ErrorPattern(
    patterns: ['الحد الأقصى', 'حد أقصى', 'النسخة التجريبية', 'trial', 'limit'],
    message: 'تم الوصول للحد الأقصى في النسخة التجريبية.',
    actionLabel: 'تفعيل النظام',
  ),

  // ── Accounting ──
  _ErrorPattern(
    patterns: ['account.*mapping', 'ربط.*حساب', 'حساب.*مرتبط', 'no.*account', 'لم يتم ربط'],
    message: 'يجب ربط الحسابات المحاسبية أولاً من شاشة ربط الحسابات.',
    actionLabel: 'ربط الحسابات',
  ),
  _ErrorPattern(
    patterns: ['balance', 'رصيد', 'insufficient', 'غير كافٍ'],
    message: 'الرصيد غير كافٍ لإتمام هذه العملية.',
  ),

  // ── Permissions ──
  _ErrorPattern(
    patterns: ['permission', 'صلاحية', 'unauthorized', 'غير مصرح'],
    message: 'ليس لديك صلاحية لهذا الإجراء. تواصل مع مدير النظام.',
  ),

  // ── Locked Records ──
  _ErrorPattern(
    patterns: ['locked', 'مقفل', 'closed period', 'فترة مغلقة'],
    message: 'السجل أو الفترة مقفل ولا يمكن تعديله.',
  ),

  // ── Database General ──
  _ErrorPattern(
    patterns: ['database', 'sql', 'drift', 'قاعدة البيانات'],
    message: 'خطأ في قاعدة البيانات. حاول مجدداً أو أعد تشغيل التطبيق.',
  ),

  // ── File ──
  _ErrorPattern(
    patterns: ['file', 'ملف', 'path', 'مسار'],
    message: 'خطأ في الوصول للملف. تأكد من وجوده وصلاحيات القراءة.',
  ),
];

class _ErrorPattern {
  final List<String> patterns;
  final String message;
  final String? actionLabel;

  const _ErrorPattern({
    required this.patterns,
    required this.message,
    this.actionLabel,
  });
}

// ═══════════════════════════════════════════════════════════════════════════
// ERROR HANDLER SERVICE
// ═══════════════════════════════════════════════════════════════════════════

/// Error handler service with smart contextual messages
class ErrorHandler {
  ErrorHandler._();
  static final ErrorHandler instance = ErrorHandler._();

  /// Handle and display error to user
  void handleError(
    BuildContext context,
    dynamic error, {
    String? userMessage,
    bool showDialog = false,
    StackTrace? stackTrace,
  }) {
    // Log the error
    logger.error(
      userMessage ?? 'An error occurred',
      error: error,
      stackTrace: stackTrace,
      tag: 'ErrorHandler',
    );

    // Determine user-facing message
    final result = _getSmartErrorResult(error);
    final displayMessage = userMessage ?? result.message;

    if (showDialog) {
      _showErrorDialog(context, displayMessage);
    } else {
      AppToast.show(
        context,
        displayMessage,
        type: ToastType.error,
        actionLabel: result.actionLabel,
      );
    }
  }

  /// Handle and display error with a custom action button
  void handleErrorWithAction(
    BuildContext context,
    dynamic error, {
    String? userMessage,
    String? actionLabel,
    VoidCallback? onAction,
    StackTrace? stackTrace,
  }) {
    logger.error(
      userMessage ?? 'An error occurred',
      error: error,
      stackTrace: stackTrace,
      tag: 'ErrorHandler',
    );

    final result = _getSmartErrorResult(error);
    final displayMessage = userMessage ?? result.message;
    final displayAction = actionLabel ?? result.actionLabel;

    AppToast.show(
      context,
      displayMessage,
      type: ToastType.error,
      actionLabel: displayAction,
      onAction: onAction,
    );
  }

  /// Handle database errors specifically
  void handleDatabaseError(BuildContext context, dynamic error) {
    final result = _getSmartErrorResult(error);
    handleError(
      context,
      error,
      userMessage: result.message,
    );
  }

  /// Handle network/printing errors
  void handlePrintError(BuildContext context, dynamic error) {
    handleError(
      context,
      error,
      userMessage: 'خطأ في الطباعة. تأكد من تشغيل الطابعة واتصالها.',
    );
  }

  /// Smart pattern-matching error classification
  SmartErrorResult _getSmartErrorResult(dynamic error) {
    final errorStr = error.toString().toLowerCase();

    for (final pattern in _errorPatterns) {
      for (final keyword in pattern.patterns) {
        // Support simple regex-like patterns with .*
        if (keyword.contains('.*')) {
          final regex = RegExp(keyword, caseSensitive: false);
          if (regex.hasMatch(errorStr)) {
            return SmartErrorResult(
              pattern.message,
              actionLabel: pattern.actionLabel,
            );
          }
        } else if (errorStr.contains(keyword)) {
          return SmartErrorResult(
            pattern.message,
            actionLabel: pattern.actionLabel,
          );
        }
      }
    }

    return const SmartErrorResult('حدث خطأ غير متوقع. حاول مجدداً.');
  }

  void _showErrorDialog(BuildContext context, String message) {
    if (!context.mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.error_outline, color: Color(0xFFEF4444)),
            SizedBox(width: 8),
            Text('خطأ'),
          ],
        ),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('حسناً'),
          ),
        ],
      ),
    );
  }
}

/// Global error handler instance
final errorHandler = ErrorHandler.instance;
