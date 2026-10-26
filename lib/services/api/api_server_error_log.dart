// Server-side diagnostic log of the purchase endpoints (extracted from
// api_purchase_handler.dart, which is size-ratcheted).
import 'dart:io' show File, FileMode;

import '../../core/config/data_dir.dart';

/// Persist an error + stacktrace to `Documents/server_errors.log` — same
/// location pattern as `DiagnosticLogger` (uralcash_login_log.txt) so the
/// file is easy for operators to find and ship back.
Future<void> writeServerErrorLog(String op, Object e, StackTrace st) async {
  try {
    final dir = await DataDir.documents();
    final path = '${dir.path}/server_errors.log';
    final buf = StringBuffer()
      ..writeln('═══════════════════════════════════════════════════════════')
      ..writeln('[${DateTime.now().toIso8601String()}] op=$op')
      ..writeln('error: $e')
      ..writeln('stacktrace:')
      ..writeln(st.toString());
    await File(path).writeAsString(buf.toString(), mode: FileMode.append, flush: true);
  } catch (_) {/* swallow intentionally — this is a diagnostic path */}
}
