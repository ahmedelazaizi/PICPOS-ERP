import 'dart:async';
import 'dart:io';
import 'package:drift/drift.dart';
import 'package:flutter/material.dart';
import '../errors/app_error.dart';
import '../logging/diagnostic_logger.dart';
import '../widgets/app_toast.dart';

/// Central Error Handler — PIR Phase 1.3
///
/// Translates technical exceptions into user-friendly Arabic messages.
/// Provides a single entry point for consistent error handling across the app.
///
/// Usage:
///   AppErrorHandler.handle(context, error);
///   AppErrorHandler.handleAsync(context, () async { ... });
class AppErrorHandler {
  AppErrorHandler._();

  /// Show a user-friendly error message based on the exception type.
  static void handle(BuildContext context, Object error, [StackTrace? stack]) {
    final message = _translate(error);
    debugPrint('⚠️ AppErrorHandler: $error');
    if (stack != null) debugPrint('$stack');
    // Cluster 034 / Issue 2 diag — pipe the underlying error + truncated
    // stack into diagnostic.log so field operators can report the actual
    // failure mode (the user-facing translation hides crucial details
    // like "Bad state: Too many elements" → which getSingleOrNull misuse).
    final stackStr = stack?.toString() ?? '<no stack>';
    final shortStack = stackStr.length > 1500
        ? '${stackStr.substring(0, 1500)}…[truncated]'
        : stackStr;
    unawaited(DiagnosticLogger.log(
      'APP-ERROR',
      'translated="$message" raw=$error\nstack=$shortStack',
    ));
    if (context.mounted) {
      AppToast.show(context, message, type: ToastType.error);
    }
  }

  /// Wrap an async operation and show error if it fails.
  /// Returns the result on success, null on failure.
  static Future<T?> handleAsync<T>(
    BuildContext context,
    Future<T> Function() operation, {
    String? successMessage,
  }) async {
    try {
      final result = await operation();
      if (successMessage != null && context.mounted) {
        AppToast.show(context, successMessage, type: ToastType.success);
      }
      return result;
    } catch (e, stack) {
      if (!context.mounted) return null;
      handle(context, e, stack);
      return null;
    }
  }

  /// Translate an exception into a user-friendly Arabic message.
  static String _translate(Object error) {
    final message = error.toString();

    // ISS-07: Handle our typed AppError hierarchy first
    if (error is AppError) {
      return error.messageAr;
    }

    // Database / Drift errors
    if (error is DriftWrappedException || message.contains('SqliteException')) {
      if (message.contains('UNIQUE constraint failed')) {
        return 'هذا العنصر موجود بالفعل — يرجى التحقق من البيانات';
      }
      if (message.contains('FOREIGN KEY constraint failed')) {
        return 'لا يمكن حذف — هناك بيانات مرتبطة بهذا العنصر';
      }
      if (message.contains('NOT NULL constraint failed')) {
        return 'يرجى ملء جميع الحقول المطلوبة';
      }
      if (message.contains('database is locked')) {
        return 'قاعدة البيانات مشغولة — يرجى المحاولة مرة أخرى';
      }
      return 'خطأ في قاعدة البيانات — يرجى المحاولة مرة أخرى';
    }

    // Network errors
    if (error is SocketException || message.contains('SocketException')) {
      return 'لا يوجد اتصال بالإنترنت';
    }
    if (error is HttpException || message.contains('HttpException')) {
      return 'خطأ في الاتصال بالخادم';
    }

    // File system errors
    if (error is FileSystemException) {
      if (message.contains('permission denied') ||
          message.contains('Access is denied')) {
        return 'ليس لديك صلاحية الوصول لهذا الملف';
      }
      if (message.contains('No such file')) {
        return 'الملف غير موجود';
      }
      return 'خطأ في قراءة/كتابة الملف';
    }

    // Format errors
    if (error is FormatException) {
      return 'صيغة البيانات غير صحيحة';
    }

    // Range / argument errors
    if (error is RangeError) {
      return 'قيمة خارج النطاق المسموح';
    }
    if (error is ArgumentError) {
      return 'بيانات غير صالحة — يرجى التحقق من المدخلات';
    }

    // State errors
    if (error is StateError) {
      if (message.contains('No element')) {
        return 'لا توجد نتائج';
      }
      return 'حالة غير متوقعة — يرجى إعادة تحميل الشاشة';
    }

    // Type errors
    if (error is TypeError) {
      return 'خطأ في نوع البيانات — يرجى التواصل مع الدعم الفني';
    }

    // Timeout
    if (message.contains('TimeoutException') || message.contains('timed out')) {
      return 'انتهت مهلة الانتظار — يرجى المحاولة مرة أخرى';
    }

    // Printing errors
    if (message.contains('print') || message.contains('printer')) {
      return 'خطأ في الطباعة — تحقق من توصيل الطابعة';
    }

    // Plain Exception with a meaningful Arabic business message — pass through.
    // (e.g. throw Exception('لا يمكن تعديل فاتورة مُرحّلة...'))
    // Non-Arabic exceptions (English stack traces, internal errors) hit the
    // generic fallback below instead of leaking untranslated text to the UI.
    if (error is Exception) {
      final msg = message.replaceFirst('Exception: ', '').trim();
      if (msg.isNotEmpty && RegExp(r'[\u0600-\u06FF]').hasMatch(msg)) {
        return msg;
      }
    }

    // General fallback
    return 'حدث خطأ غير متوقع — يرجى المحاولة مرة أخرى';
  }

  /// Expose translation for testing (PIR-010)
  @visibleForTesting
  static String translateForTest(Object error) => _translate(error);
}
