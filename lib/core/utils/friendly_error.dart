import '../logging/diagnostic_logger.dart';

/// Spec 137 (BUG-U07/U16/U17/U18): map a raw exception to a short, Arabic,
/// user-facing message while preserving the technical detail in the diagnostic
/// log. Never show a raw `$e` to the (Arabic, non-technical) operator.
///
/// Pass [context] to tag the log line (e.g. 'COURIER-DELETE'), and
/// [stackTrace] when the caller has it (e.g. `catch (e, s)` /
/// `error: (e, s) => ...`) so the diagnostic line keeps the stack.
String friendlyError(Object error, {String context = 'APP', StackTrace? stackTrace}) {
  // Preserve the technical detail for support — fire-and-forget, the UI does
  // not wait on the log write.
  final detail = stackTrace == null ? '$error' : '$error\n$stackTrace';
  DiagnosticLogger.log('UI-ERROR', '$context: $detail');

  final s = error.toString().toLowerCase();
  if (s.contains('socket') ||
      s.contains('network') ||
      s.contains('connection') ||
      s.contains('timeout') ||
      s.contains('handshake') ||
      s.contains('http')) {
    return 'تعذّر الاتصال بالخادم. تحقّق من الشبكة وحاول مرة أخرى.';
  }
  if (s.contains('permission') ||
      s.contains('denied') ||
      s.contains('403') ||
      s.contains('unauthor')) {
    return 'ليس لديك صلاحية لإتمام هذا الإجراء.';
  }
  if (s.contains('foreign key') ||
      s.contains('constraint') ||
      s.contains('unique') ||
      s.contains('sqlite') ||
      s.contains('database')) {
    return 'تعذّر إتمام العملية بسبب تعارض في البيانات.';
  }
  if (s.contains('format') || s.contains('invalid') || s.contains('parse')) {
    return 'البيانات المُدخلة غير صحيحة. تحقّق منها وحاول مرة أخرى.';
  }
  return 'حدث خطأ غير متوقّع. حاول مرة أخرى.';
}
